#include "bridge.h"
#include "llama.h"
#include "ggml-backend.h"
#include "gguf.h"
#include "chat.h"
#include "common.h"
#include "fit.h"
#include "json-schema-to-grammar.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <map>
#include <set>
#include "nlohmann/json.hpp"
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <condition_variable>
#include <fstream>
#include <mutex>
#include <atomic>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#if !defined(_WIN32)
#include <sys/resource.h>
#endif
#if defined(__ANDROID__)
#include <android/log.h>
#include <jni.h>
#endif
using json = nlohmann::ordered_json;
using Clock = std::chrono::steady_clock;
static std::atomic<int64_t> next_session{1};
static std::mutex cancellation_mutex;
static std::map<int64_t, std::shared_ptr<std::atomic<bool>>> cancellations;
static bool cancelled_callback(void * data) {
    return static_cast<std::atomic<bool> *>(data)->load(std::memory_order_relaxed);
}
static bool loading_callback(float, void * data) { return !cancelled_callback(data); }
struct Runtime;
// Every live runtime, so an Android window that closes can free the models
// it loaded (od_release_owner): the activity and its Dart isolates go away
// but the process, and native memory, can live on. Relaunching then loaded
// a second copy on top (report 2026-09-28: 6.6 GB native heap).
static std::mutex registry_mutex;
static std::set<Runtime *> registry;
// Owners being released right now: a load in another window waits for that
// memory to come back before measuring what is free.
static std::mutex release_mutex;
static std::condition_variable release_done;
static std::multiset<int64_t> releasing;
struct Runtime {
    const int64_t session = next_session.fetch_add(1);
    const std::shared_ptr<std::atomic<bool>> cancelled = std::make_shared<std::atomic<bool>>(false);
    // The window (Android activity) that created this runtime; 0 = none.
    const int64_t owner;
    // Held by every call that reads or changes the model, because a release
    // arrives from another thread. `released` refuses work afterwards.
    std::mutex use;
    bool released = false;
    explicit Runtime(int64_t owner_id) : owner(owner_id) {
        { std::lock_guard<std::mutex> lock(cancellation_mutex); cancellations.emplace(session, cancelled); }
        std::lock_guard<std::mutex> lock(registry_mutex);
        registry.insert(this);
    }
    llama_model * model = nullptr;
    llama_context * ctx = nullptr;
    llama_sampler * sampler = nullptr;
    // Grammar (structured output or the template's tool-call grammar) is kept
    // out of the chain: the chain sees the prompt for repetition penalties,
    // the grammar must only see what the model generates.
    llama_sampler * grammar = nullptr;
    std::vector<llama_token_data> candidates;   // reused per sampled token
    // Jinja templates from the GGUF. Null when the model ships no template and
    // we must fall back to a family template through the legacy C API.
    common_chat_templates_ptr templates;
    bool supports_thinking = false, forced_open = false, supports_tools = false;
    std::string think_start, error, info, preview, fallback_reason, backend = "CPU", adapter_info;
    json effective = json::object();
    std::vector<std::string> think_ends;
    std::vector<llama_token> prompt;
    std::vector<ggml_backend_dev_t> devices;
    int batch = 256, cursor = 0, generated = 0, maximum = 0, trimmed = 0, pending = -1;
    bool done = true;
    double first_ms = 0;
    Clock::time_point started, first, last;
    // Prompt cache (roadmap PERF-02): the token sequence whose state is in the
    // context memory right now. A new prompt that shares a prefix with it is
    // evaluated from the first differing token only.
    std::vector<llama_token> cached;
    int reused = 0;
    // Partial-state checkpoints for memories that cannot drop a tail
    // (recurrent/hybrid such as Qwen3.5, sliding-window such as Gemma):
    // restoring one rolls the sequence back to `pos` tokens.
    struct Checkpoint { int pos; std::vector<uint8_t> data; };
    std::vector<Checkpoint> checkpoints;
    std::vector<int> checkpoint_at;   // ascending; each taken when the prefill cursor reaches it
    bool needs_checkpoints = false;
    int n_swa = 0;
    // Thinking budget: after this many reasoning tokens the block is closed
    // for the model so the answer starts (0 = the turn does not think).
    // [reasoning] counts the block's tokens, the hand-off included: since
    // 2026-09-28 [maximum] caps the answer only (review), and
    // [total_cap] is where the context ends.
    int think_budget = 0, think_tokens = 0, reasoning = 0, total_cap = 0;
    bool in_think = false;
    std::string tail;
    // Vision (libmtmd): the projector, decoded photos by path (kept for the
    // session so a follow-up does not re-read the file), and the current
    // turn's chunks when it carries photos. A photo turn takes part in the
    // prompt cache: `cached` then holds one LLAMA_TOKEN_NULL per image token
    // and `media_meta` says which image (by id) occupies which run, the way
    // llama-server's server_tokens does, so a follow-up keeps the encoded
    // photo and the conversation instead of re-encoding everything (that
    // cost minutes per message on the phone, report 2026-09-20).
    mtmd_context * mctx = nullptr;
    std::string vision_error;
    std::map<std::string, mtmd_bitmap *> bitmaps;
    mtmd_input_chunks * chunks = nullptr;
    bool media_pending = false;
    int media_tokens = 0;
    struct MediaMeta { size_t idx; std::string id; size_t n_tokens; llama_pos n_pos; };
    std::vector<MediaMeta> media_meta;          // images inside `cached`
    std::vector<llama_token> media_flat;        // this turn's flattened prompt
    std::vector<MediaMeta> media_meta_next;     // its images
    size_t media_keep = 0;                      // flat index already resident
    llama_pos media_keep_pos = 0;               // ...and its KV position
    long media_checkpoint_at = -1;              // flat index of the history boundary
    // Embedding mode (FX-02): the context pools sequence embeddings instead
    // of producing logits; od_begin/od_step are refused, od_embed works.
    bool embedding = false;
    std::string embedded;
    // ABI 6 --------------------------------------------------------------
    // Stop sequences (settings.stopSequences plus the template's own for
    // tool formats). Output is held back while it could still be the start
    // of one, so a stop that spans tokens is never shown.
    std::vector<std::string> stops;
    std::string held;
    bool flush_only = false;
    // Why the answer ended: "eog", "stop", "length", "" while running.
    std::string finish;
    // Native tool calling: the template's parser for the finished text, and
    // the calls it found (od_info "toolCalls" after the end).
    common_chat_parser_params parser;
    bool tools_active = false;
    std::string generated_text;
    json tool_calls = json::array();
    std::string tool_format;
    // The finished text without its tool-call markup, as the template's
    // parser split it (od_info "toolContent"): what the assistant turn says
    // when it is sent back with its calls.
    std::string tool_content;
    // LoRA adapters attached to the context (freed with the model).
    std::vector<llama_adapter_lora *> adapters;
    json adapter_report = json::array();
    // Speculative decoding with a draft model: the draft runs on the CPU,
    // proposes up to `draft_max` greedy tokens, the target verifies them in
    // one batch. Vocabularies are checked at load.
    llama_model * draft_model = nullptr;
    llama_context * draft_ctx = nullptr;
    llama_sampler * draft_sampler = nullptr;
    int draft_max = 0;
    std::vector<llama_token> draft_cached;   // tokens in the draft KV
    std::vector<llama_token> draft_queue;    // accepted tokens the draft has not seen yet
    long draft_proposed = 0, draft_accepted = 0, draft_rounds = 0;   // this turn
    // Recurrent/hybrid memories cannot drop rejected draft tokens with
    // seq_rm: the state from before the batch is kept (partial state only,
    // a few MB) and restored, then the kept tokens are replayed. The draft
    // gets the same treatment before every proposal. `draft_replays` counts
    // target replays this turn (each costs one extra decode).
    bool draft_needs_checkpoints = false;
    std::vector<uint8_t> draft_undo; int draft_undo_pos = -1;
    long draft_replays = 0;
    // Speculation that does not pay for itself is switched off for the rest
    // of the turn (and tried again on the next one): after draft_probe rounds
    // when acceptance is below draft_floor, or when the rounds produced fewer
    // tokens per millisecond than the plain steps measured in the same turn
    // (the first draft_warm tokens always run plain so that rate exists).
    bool draft_disabled = false;
    static constexpr long draft_probe = 4;
    static constexpr double draft_floor = 0.35;
    static constexpr long draft_warm = 3;
    double plain_ms = 0, spec_ms = 0; long plain_steps = 0, spec_tokens = 0;
    std::string draft_name;
    void reset() { if (sampler) llama_sampler_free(sampler); if (grammar) llama_sampler_free(grammar); sampler = nullptr; grammar = nullptr; }
    void forget() { cached.clear(); media_meta.clear(); checkpoints.clear(); checkpoint_at.clear(); reused = 0; draft_cached.clear(); draft_queue.clear(); }
    void drop_chunks() { if (chunks) mtmd_input_chunks_free(chunks); chunks = nullptr; media_pending = false; }
    void unload() {
        reset(); forget(); drop_chunks();
        for (auto & b : bitmaps) mtmd_bitmap_free(b.second);
        bitmaps.clear();
        if (mctx) mtmd_free(mctx);
        mctx = nullptr; vision_error.clear(); media_tokens = 0;
        templates.reset();
        if (draft_sampler) llama_sampler_free(draft_sampler);
        if (draft_ctx) llama_free(draft_ctx);
        if (draft_model) llama_model_free(draft_model);
        draft_sampler = nullptr; draft_ctx = nullptr; draft_model = nullptr; draft_max = 0; draft_name.clear();
        draft_proposed = draft_accepted = draft_rounds = 0; draft_disabled = false;
        draft_needs_checkpoints = false; draft_undo.clear(); draft_undo_pos = -1; draft_replays = 0;
        plain_ms = spec_ms = 0; plain_steps = spec_tokens = 0;
        // Adapters belong to the model and are released with it.
        adapters.clear(); adapter_report = json::array();
        if (ctx) llama_free(ctx);
        if (model) llama_model_free(model);
        ctx = nullptr; model = nullptr; done = true; effective = json::object();
        supports_thinking = false; forced_open = false; supports_tools = false; think_start.clear(); think_ends.clear();
        needs_checkpoints = false; n_swa = 0; embedding = false;
        stops.clear(); held.clear(); flush_only = false; finish.clear();
        tools_active = false; generated_text.clear(); tool_calls = json::array(); tool_format.clear(); tool_content.clear();
    }
    ~Runtime() {
        { std::lock_guard<std::mutex> lock(cancellation_mutex); cancellations.erase(session); }
        // Waits for a release in progress; afterwards nobody else can reach this runtime.
        { std::lock_guard<std::mutex> lock(registry_mutex); registry.erase(this); }
        unload();
    }
};
static const char * released_message = "The model was unloaded because the app window closed.";
static std::once_flag init_flag;
#if defined(__ANDROID__)
#include <thread>
#include <unistd.h>
// llama.cpp and ggml write some diagnostics straight to stderr, which Android
// discards. Relay it to logcat so shader-compiler failures are visible.
static void relay_stderr() {
    int fds[2];
    if (pipe(fds) != 0) return;
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);
    std::thread([fd = fds[0]] {
        std::string line; char buf[512];
        for (ssize_t n; (n = read(fd, buf, sizeof buf)) > 0;) {
            for (ssize_t i = 0; i < n; ++i) {
                if (buf[i] == '\n') { __android_log_write(ANDROID_LOG_WARN, "ondevice_llm", line.c_str()); line.clear(); }
                else line += buf[i];
            }
        }
    }).detach();
}
#endif
// Warnings and errors from llama.cpp go to the platform log so failures such as
// a GPU shader that will not compile are diagnosable; info/debug stay quiet.
static void native_log(enum ggml_log_level level, const char * text, void *) {
    if (level != GGML_LOG_LEVEL_WARN && level != GGML_LOG_LEVEL_ERROR) return;
#if defined(__ANDROID__)
    __android_log_write(level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR : ANDROID_LOG_WARN, "ondevice_llm", text);
#else
    fputs(text, stderr);
#endif
}
static int fail(Runtime * r, const std::exception & e) { r->error = e.what(); r->done = true; r->finish = "error"; return -1; }
static double peak_rss_mb() {
#if defined(_WIN32)
    return 0;
#else
    rusage usage{};
    if (getrusage(RUSAGE_SELF, &usage) != 0) return 0;
#if defined(__APPLE__)
    return usage.ru_maxrss / 1048576.0; // bytes on Darwin
#else
    return usage.ru_maxrss / 1024.0;    // kilobytes on Linux/Android
#endif
#endif
}
static std::string kernel_cache_dir;
int32_t od_version() { return 7; }
void * od_create(const char * options) {
    try {
        auto opts = options && *options ? json::parse(options, nullptr, false) : json::object();
        if (!opts.is_object()) opts = json::object();
        std::call_once(init_flag, [&opts] {
#if defined(__ANDROID__)
            relay_stderr();
#endif
            // ggml-opencl looks up its program cache through this variable. An
            // Android app has no TMPDIR, so without it every load recompiles
            // every kernel (tens of seconds on Adreno).
            if (opts.value("cacheDir", "").size()) {
                kernel_cache_dir = opts.value("cacheDir", "") + "/opencl-kernels";
#if defined(_WIN32)
                _putenv_s("GGML_OPENCL_KERNEL_CACHE_DIR", kernel_cache_dir.c_str());
#else
                setenv("GGML_OPENCL_KERNEL_CACHE_DIR", kernel_cache_dir.c_str(), 1);
#endif
            }
            llama_log_set(native_log, nullptr); llama_backend_init(); ggml_backend_load_all();
        });
        const auto owner = opts.contains("owner") && opts["owner"].is_number_integer() ? opts["owner"].get<int64_t>() : 0;
        return new Runtime(owner);
    } catch (...) { return nullptr; }
}
void od_destroy(void * h) { delete static_cast<Runtime *>(h); }
int32_t od_release_owner(int64_t owner) {
    if (owner == 0) return 0;
    { std::lock_guard<std::mutex> lock(release_mutex); releasing.insert(owner); }
    int32_t freed = 0;
    {
        // Held throughout so od_destroy cannot free a runtime being released.
        std::lock_guard<std::mutex> lock(registry_mutex);
        // Cancel everything first: a generation or load in progress stops at
        // its next check and lets go of the runtime's lock.
        for (auto * r : registry) if (r->owner == owner) r->cancelled->store(true, std::memory_order_relaxed);
        for (auto * r : registry) {
            if (r->owner != owner) continue;
            std::lock_guard<std::mutex> use(r->use);
            if (r->released) continue;
            r->released = true;
            if (r->model) ++freed;
            r->unload();
        }
    }
    {
        std::lock_guard<std::mutex> lock(release_mutex);
        releasing.erase(releasing.find(owner));
    }
    release_done.notify_all();
    return freed;
}
#if defined(__ANDROID__)
// MainActivity.onDestroy -> NativeBridge.releaseOwner(tester).
extern "C" JNIEXPORT jint JNICALL Java_app_ondevicellm_ondevice_1llm_NativeBridge_releaseOwner(JNIEnv *, jclass, jlong owner) {
    return od_release_owner((int64_t)owner);
}
#endif
int64_t od_session_id(void * h) { return static_cast<Runtime *>(h)->session; }
void od_cancel_session(int64_t session) {
    std::lock_guard<std::mutex> lock(cancellation_mutex);
    auto found = cancellations.find(session);
    if (found != cancellations.end()) found->second->store(true, std::memory_order_relaxed);
}
void od_reset_cancel(void * h) { static_cast<Runtime *>(h)->cancelled->store(false, std::memory_order_relaxed); }
int32_t od_cancelled(void * h) { return static_cast<Runtime *>(h)->cancelled->load(std::memory_order_relaxed); }
const char * od_error(void * h) { return static_cast<Runtime *>(h)->error.c_str(); }
const char * od_info(void * h) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    double seconds = r->generated > 1 ? std::chrono::duration<double>(r->last - r->first).count() : 0;
    json devices = json::array();
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto dev = ggml_backend_dev_get(i);
        const auto type = ggml_backend_dev_type(dev);
        devices.push_back({{"backend", ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev))},
            {"description", ggml_backend_dev_description(dev)},
            {"gpu", type == GGML_BACKEND_DEVICE_TYPE_GPU || type == GGML_BACKEND_DEVICE_TYPE_IGPU}});
    }
    r->info = json{{"abiVersion", 7}, {"devices", devices}, {"kernelCacheDir", kernel_cache_dir},
        {"effectiveSettings", r->effective}, {"fallbackReason", r->fallback_reason},
        {"backend", r->backend}, {"tokens", r->generated}, {"promptTokens", r->prompt.size()},
        {"firstTokenMs", r->first_ms}, {"tokensPerSecond", seconds > 0 ? (r->generated - 1) / seconds : 0},
        {"trimmedMessages", r->trimmed}, {"contextSize", r->ctx ? llama_n_ctx(r->ctx) : 0},
        {"contextTrain", r->model ? llama_model_n_ctx_train(r->model) : 0},
        {"cachedPromptTokens", r->reused}, {"thinkingTokens", r->think_tokens},
        {"contextUsed", r->media_tokens ? r->media_tokens + r->generated : (int)r->prompt.size() + r->generated}, {"peakRssMb", peak_rss_mb()},
        {"supportsVision", r->mctx && mtmd_support_vision(r->mctx)}, {"visionError", r->vision_error},
        {"mediaMarker", mtmd_default_marker()}, {"mediaTokens", r->media_tokens},
        {"released", r->released},
        {"supportsThinking", r->supports_thinking}, {"thinkingForcedOpen", r->forced_open},
        {"thinkingStartTag", r->think_start}, {"thinkingEndTags", r->think_ends},
        {"hasTemplate", (bool)r->templates}, {"embedding", r->embedding},
        {"embeddingDim", r->model ? llama_model_n_embd_out(r->model) : 0},
        // A reranker (pooling RANK): od_embed scores request.pairs.
        {"ranks", r->ctx && llama_pooling_type(r->ctx) == LLAMA_POOLING_TYPE_RANK},
        // ABI 7: media embeddings (EmbeddingGemma 2 projector) and audio input.
        {"supportsAudio", r->mctx && mtmd_support_audio(r->mctx)},
        // ABI 6
        {"finishReason", r->finish}, {"supportsTools", r->supports_tools}, {"toolFormat", r->tool_format},
        {"toolCalls", r->tool_calls}, {"toolContent", r->tool_content}, {"adapters", r->adapter_report},
        {"draftModel", r->draft_name}, {"draftProposed", r->draft_proposed}, {"draftAccepted", r->draft_accepted},
        {"draftRounds", r->draft_rounds}, {"draftDisabled", r->draft_disabled}, {"draftReplays", r->draft_replays},
        // Tokens per ms of speculative rounds relative to plain steps this turn (0 when unmeasured).
        {"draftSpeedup", r->spec_ms > 0 && r->plain_ms > 0 && r->plain_steps > 0
            ? ((double)r->spec_tokens / r->spec_ms) / ((double)r->plain_steps / r->plain_ms) : 0.0},
        {"draftAcceptRate", r->draft_proposed > 0 ? (double)r->draft_accepted / (double)r->draft_proposed : 0.0}}.dump();
    return r->info.c_str();
}
static ggml_type cache_type(const std::string & name) {
    return name == "q8_0" ? GGML_TYPE_Q8_0 : name == "q4_0" ? GGML_TYPE_Q4_0 : name == "q5_0" ? GGML_TYPE_Q5_0
        : name == "q5_1" ? GGML_TYPE_Q5_1 : name == "q4_1" ? GGML_TYPE_Q4_1 : name == "iq4_nl" ? GGML_TYPE_IQ4_NL
        : name == "bf16" ? GGML_TYPE_BF16 : name == "f32" ? GGML_TYPE_F32 : GGML_TYPE_F16;
}
// Two models can share a speculation pipeline only if the draft's tokens
// are the target's tokens (same rule as llama.cpp's speculative examples).
static std::string draft_incompatible(const llama_model * tgt, const llama_model * dft) {
    const auto * vt = llama_model_get_vocab(tgt);
    const auto * vd = llama_model_get_vocab(dft);
    if (llama_vocab_type(vt) != llama_vocab_type(vd)) return "the draft model uses a different tokenizer type";
    if (llama_vocab_get_add_bos(vt) != llama_vocab_get_add_bos(vd) || llama_vocab_get_add_eos(vt) != llama_vocab_get_add_eos(vd)
        || llama_vocab_bos(vt) != llama_vocab_bos(vd) || llama_vocab_eos(vt) != llama_vocab_eos(vd)) return "the draft model's special tokens differ";
    const int nt = llama_vocab_n_tokens(vt), nd = llama_vocab_n_tokens(vd);
    if (std::abs(nt - nd) > 128) return "the draft model's vocabulary size differs (" + std::to_string(nd) + " vs " + std::to_string(nt) + ")";
    for (int i = 5; i < std::min(nt, nd); ++i) {
        const char * a = llama_vocab_get_text(vt, i), * b = llama_vocab_get_text(vd, i);
        if (!a || !b || std::string(a) != b) return "the draft model's vocabulary differs at token " + std::to_string(i);
    }
    return "";
}
// Renders one user turn with a probe tool: a template that names the tool
// in its output can carry tool definitions and parse calls.
static bool probe_tools(Runtime * r) {
    if (!r->templates) return false;
    try {
        common_chat_templates_inputs in;
        common_chat_msg u; u.role = "user"; u.content = "hi"; in.messages.push_back(u);
        common_chat_tool t; t.name = "odllm_probe_tool"; t.description = "probe"; t.parameters = R"({"type":"object","properties":{"q":{"type":"string"}},"required":["q"]})";
        in.tools.push_back(t);
        in.enable_thinking = false;
        auto p = common_chat_templates_apply(r->templates.get(), in);
        return p.prompt.find("odllm_probe_tool") != std::string::npos;
    } catch (const std::exception &) { return false; }
}
// The draft model for speculative decoding runs on the CPU with plain FP16
// KV and follows the target's context.
static llama_model_params draft_model_params(Runtime * r) {
    auto dp = llama_model_default_params();
    dp.progress_callback = loading_callback;
    dp.progress_callback_user_data = r->cancelled.get();
    dp.n_gpu_layers = 0;
    return dp;
}
static llama_context_params draft_context_params(Runtime * r, const llama_context_params & cp) {
    auto dc = llama_context_default_params();
    dc.abort_callback = cancelled_callback;
    dc.abort_callback_data = r->cancelled.get();
    dc.n_ctx = cp.n_ctx; dc.n_batch = cp.n_batch; dc.n_ubatch = cp.n_ubatch;
    dc.n_threads = cp.n_threads; dc.n_threads_batch = cp.n_threads_batch;
    dc.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    return dc;
}
// A "Key:  123 kB" field of a /proc file ("/proc/meminfo", "MemAvailable:")
// in bytes; 0 where there is none.
static int64_t proc_bytes(const char * file, const std::string & key) {
#if defined(__linux__)
    std::ifstream f(file);
    for (std::string line; std::getline(f, line);) {
        if (line.compare(0, key.size(), key) == 0) return std::atoll(line.c_str() + key.size()) * 1024;
    }
#else
    (void)file; (void)key;
#endif
    return 0;
}
static int64_t file_bytes(const std::string & path) {
    if (path.empty()) return 0;
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    return f ? (int64_t)f.tellg() : 0;
}
// Bytes the model plus a context of cp.n_ctx take on every device, as
// llama.cpp lays them out, measured without allocating (no_alloc). The
// helper swaps llama's global logger while it runs, hence the lock.
static std::mutex measure_mutex;
static int64_t measure(const char * path, const llama_model_params & mp, const llama_context_params & cp, uint32_t * train = nullptr) {
    std::lock_guard<std::mutex> lock(measure_mutex);
    std::vector<ggml_backend_dev_t> devs;
    uint32_t layers = 0, n_train = 0, experts = 0;
    const auto data = common_get_device_memory_data(path, &mp, &cp, devs, layers, n_train, experts, GGML_LOG_LEVEL_ERROR);
    if (train) *train = n_train;
    int64_t bytes = 0;
    for (const auto & d : data) bytes += (int64_t)(d.model + d.context + d.compute);
    return bytes;
}
// Memory admission (report 2026-09-28): the saved context was used as
// is, so a 64K context on Qwen3 1.7B asked for ~7 GiB of cache and Android
// killed the app while it loaded. The context is capped to the model's
// trained length (unless the user chose linear or YaRN scaling to stretch
// it) and to what fits in the memory free right now; cp.n_ctx is the
// result. The returned fields go into effectiveSettings so the app can say
// what happened.
static json admit(Runtime * r, const char * path, const json & s, const llama_model_params & mp, llama_context_params & cp,
                  const std::string & draft, const llama_model_params & dp, const std::string & mmproj) {
    const uint32_t asked = cp.n_ctx;
    json out = {{"contextRequested", asked}, {"contextCap", ""}};
    if (!s.value("memoryGuard", true)) return out;
    {
        // A window closing elsewhere may still be giving its memory back.
        std::unique_lock<std::mutex> lock(release_mutex);
        release_done.wait_for(lock, std::chrono::seconds(5), [r] {
            return std::all_of(releasing.begin(), releasing.end(), [r](int64_t o) { return o == r->owner; });
        });
    }
    const auto started = Clock::now();
    // The projector's weights; its encoder buffers are small next to them.
    const int64_t extra = file_bytes(mmproj);
    uint32_t train = 0;
    auto need_at = [&](uint32_t n) {
        if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Loading cancelled.");
        cp.n_ctx = n;
        int64_t bytes = measure(path, mp, cp, &train) + extra;
        if (!draft.empty()) bytes += measure(draft.c_str(), dp, draft_context_params(r, cp));
        return bytes;
    };
    uint32_t n = asked;
    int64_t need = 0;
    try {
        need = need_at(n);
    } catch (const std::exception &) {
        // Unreadable here: the real load below reports why.
        cp.n_ctx = asked;
        return out;
    }
    const std::string rope = s.value("ropeScaling", "model");
    if (train > 0 && n > train && rope != "linear" && rope != "yarn") {
        n = train;
        need = need_at(n);
        out["contextCap"] = "train";
    }
    const int64_t available = proc_bytes("/proc/meminfo", "MemAvailable:");
    int64_t budget = 0;
    if (available > 0) {
        // Measured on an 11 GB phone (2026-09-28): a load that left 0.8 GB
        // available survived, with the phone one app switch from killing
        // it, so a sixth of the RAM stays free for everything else. Busy
        // phones read low because MemAvailable leaves out the background
        // apps Android closes on demand, yet a foreground app can count on
        // about 40% of the RAM (Gemma 4 E2B at 5.4 GB RSS never died).
        const int64_t total = proc_bytes("/proc/meminfo", "MemTotal:");
        const int64_t own = proc_bytes("/proc/self/status", "VmRSS:");
        budget = std::max(available - std::max<int64_t>(1ll << 30, total / 6), total * 2 / 5 - own);
        out["memoryAvailableMb"] = available >> 20;
        out["memoryBudgetMb"] = budget >> 20;
        if (need > budget) {
            // Model memory is fixed and the cache grows with the context, so
            // two measurements give the context that fits; it is then
            // confirmed, because compute buffers do not grow exactly linearly.
            const uint32_t low = std::min(n, std::max<uint32_t>(1024, std::min<uint32_t>(n / 2, 4096)));
            const int64_t need_low = low < n ? need_at(low) : need;
            if (need_low > budget) {
#if defined(__ANDROID__)
                __android_log_print(ANDROID_LOG_WARN, "ondevice_llm", "admit: refused, need %lld MB at context %u, budget %lld MB",
                    (long long)(need_low >> 20), low, (long long)(budget >> 20));
#endif
                throw std::runtime_error("Not enough free memory for this model: it needs about " + std::to_string(need_low >> 20)
                    + " MB even with a small context, and " + std::to_string(std::max<int64_t>(budget, 0) >> 20)
                    + " MB is free. Close other apps or choose a smaller model.");
            }
            const double per_token = double(need - need_low) / double(n - low);
            uint32_t fit = (uint32_t)std::min<double>(n - 1, low + double(budget - need_low) / per_token);
            fit = std::max(low, fit / 1024 * 1024);
            need = fit == low ? need_low : need_at(fit);
            for (int i = 0; i < 4 && fit > low && need > budget; ++i) {
                fit = std::max(low, (uint32_t)(fit * 0.9) / 1024 * 1024);
                need = fit == low ? need_low : need_at(fit);
            }
            // The small context was measured to fit; use it if nothing larger did.
            if (need > budget) { fit = low; need = need_low; }
            n = fit;
            out["contextCap"] = "memory";
        }
    }
    cp.n_ctx = n;
    out["contextTrain"] = train;
    out["memoryNeedMb"] = need >> 20;
    out["admissionMs"] = std::chrono::duration<double, std::milli>(Clock::now() - started).count();
#if defined(__ANDROID__)
    // One line per load, so a phone that kills or caps a model can be read
    // back from logcat without a debug build.
    __android_log_print(ANDROID_LOG_INFO, "ondevice_llm", "admit: asked %u, train %u, context %u (%s), need %lld MB, budget %lld MB, available %lld MB, %.0f ms",
        asked, train, n, out["contextCap"].get<std::string>().c_str(), (long long)(need >> 20), (long long)(budget >> 20),
        (long long)(available >> 20), out["admissionMs"].get<double>());
#endif
    return out;
}
static void load_with(Runtime * r, const char * path, const json & s, const std::string & requested) {
        auto mp = llama_model_default_params();
        mp.progress_callback = loading_callback;
        mp.progress_callback_user_data = r->cancelled.get();
        r->devices.clear(); r->backend = "CPU"; r->fallback_reason.clear();
        std::string skipped;
        if (requested != "cpu" && s.value("nGpuLayers", 999) > 0) {
            for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
                auto dev = ggml_backend_dev_get(i);
                // Phone GPUs (Adreno, Mali, Apple) report as integrated.
                auto type = ggml_backend_dev_type(dev);
                if (type != GGML_BACKEND_DEVICE_TYPE_GPU && type != GGML_BACKEND_DEVICE_TYPE_IGPU) continue;
                std::string name = ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev));
                std::string lower = name;
                std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
                // Auto only takes Metal, the one GPU path that is a measured win.
                // OpenCL on Adreno 830 (Qwen3.5 2B, b10951) prefills 2x faster but
                // decodes ~20% slower than the CPU, so it stays an explicit choice
                // until a per-device benchmark profile approves it (roadmap GPU-05).
                const bool auto_ok = requested == "auto" && lower == "metal";
                if (requested == "auto" && !auto_ok) { if (skipped.empty()) skipped = name; continue; }
                if (auto_ok || lower.find(requested) != std::string::npos) {
                    r->devices.push_back(dev); r->backend = name + " / " + ggml_backend_dev_description(dev); break;
                }
            }
            if (r->devices.empty() && requested != "auto") throw std::runtime_error("Requested GPU backend is unavailable in this build/device. Select CPU or Auto.");
        }
        if (requested == "auto" && r->devices.empty()) {
            r->fallback_reason = s.value("nGpuLayers", 999) == 0 ? "GPU layers are set to zero."
                : skipped.empty() ? "No GPU backend was registered on this build/device."
                : skipped + " is available but not chosen automatically: it is not yet a measured win on this device. Select it under Settings > Hardware.";
            r->backend = skipped.empty() || s.value("nGpuLayers", 999) == 0
                ? "CPU (GPU unavailable: " + r->fallback_reason + ")" : "CPU (" + skipped + " available, not auto-selected)";
        }
        mp.n_gpu_layers = r->devices.empty() ? 0 : s.value("nGpuLayers", 999);
        r->devices.push_back(nullptr); mp.devices = r->devices.data();
        r->embedding = s.value("embedding", false);
        auto cp = llama_context_default_params();
        cp.abort_callback = cancelled_callback;
        cp.abort_callback_data = r->cancelled.get();
        // The user's choice (roadmap SET-01), then capped below to the model's
        // trained length and to the memory free right now.
        cp.n_ctx = std::clamp(s.value("contextSize", 4096), 512, 1 << 20);
        r->batch = std::clamp(s.value("effectiveBatchSize", 256), 32, 4096);
        if (r->embedding) {
            // One passage per decode, pooled by the model's own policy (GGUF
            // metadata: mean for EmbeddingGemma/nomic, CLS for bge). The batch
            // must hold a whole passage, so it equals the context.
            cp.embeddings = true;
            cp.pooling_type = LLAMA_POOLING_TYPE_UNSPECIFIED;
            r->batch = (int)cp.n_ctx;
        }
        cp.n_batch = r->batch;
        cp.n_ubatch = std::clamp(s.value("effectiveMicroBatchSize", std::min(r->batch, 128)), 32, r->batch);
        // An encoder attends both ways, so one input must fit one micro-batch
        // (llama.cpp asserts it); photos alone are ~280 tokens.
        if (r->embedding) cp.n_ubatch = r->batch;
        cp.n_threads = std::clamp(s.value("effectiveThreads", 4), 1, 16);
        // Prefill scales past the decode optimum (S25+: 8 threads prefill 14%
        // faster than 6 while 8 collapses decode), so the two are separate.
        cp.n_threads_batch = std::clamp(s.value("effectiveBatchThreads", cp.n_threads), 1, 16);
        cp.flash_attn_type = s.value("flashAttention", true) ? LLAMA_FLASH_ATTN_TYPE_AUTO : LLAMA_FLASH_ATTN_TYPE_DISABLED;
        // Separate K and V cache types (ABI 6): "vCacheType" empty = same as K.
        const auto kv = s.value("kvCacheType", "fp16");
        auto vv = s.value("vCacheType", ""); if (vv.empty()) vv = kv;
        cp.type_k = cache_type(kv); cp.type_v = cache_type(vv);
        // A quantized V cache needs flash attention; a quantized K alone does not.
        if (cp.type_v != GGML_TYPE_F16 && cp.type_v != GGML_TYPE_F32 && cp.type_v != GGML_TYPE_BF16) cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        // RoPE / YaRN (ABI 6): "model" keeps the GGUF's values; the others
        // override the scaling type and, when non-zero, base/scale/yarn.
        const std::string rope = s.value("ropeScaling", "model");
        cp.rope_scaling_type = rope == "none" ? LLAMA_ROPE_SCALING_TYPE_NONE : rope == "linear" ? LLAMA_ROPE_SCALING_TYPE_LINEAR
            : rope == "yarn" ? LLAMA_ROPE_SCALING_TYPE_YARN : LLAMA_ROPE_SCALING_TYPE_UNSPECIFIED;
        if (s.value("ropeFreqBase", 0.0f) > 0) cp.rope_freq_base = s.value("ropeFreqBase", 0.0f);
        if (s.value("ropeFreqScale", 0.0f) > 0) cp.rope_freq_scale = s.value("ropeFreqScale", 0.0f);
        if (rope == "yarn") {
            if (s.value("yarnExtFactor", -1.0f) >= 0) cp.yarn_ext_factor = s.value("yarnExtFactor", -1.0f);
            if (s.value("yarnAttnFactor", 0.0f) > 0) cp.yarn_attn_factor = s.value("yarnAttnFactor", 1.0f);
            if (s.value("yarnBetaFast", 0.0f) > 0) cp.yarn_beta_fast = s.value("yarnBetaFast", 32.0f);
            if (s.value("yarnBetaSlow", 0.0f) > 0) cp.yarn_beta_slow = s.value("yarnBetaSlow", 1.0f);
            if (s.value("yarnOrigCtx", 0) > 0) cp.yarn_orig_ctx = s.value("yarnOrigCtx", 0);
        }
        const std::string draft = r->embedding ? "" : s.value("draftModel", "");
        const std::string mmproj = s.value("mmproj", "");
        auto dp = draft_model_params(r);
        const json admission = r->embedding ? json::object() : admit(r, path, s, mp, cp, draft, dp, mmproj);
        r->model = llama_model_load_from_file(path, mp);
        if (!r->model) throw std::runtime_error("Cannot load this GGUF. It may be unsupported, incomplete, or too large for available memory.");
        if (llama_model_has_encoder(r->model) || !llama_model_has_decoder(r->model)) throw std::runtime_error("Only decoder text-generation models are supported.");
        // Prefer the template the publisher shipped. A broken or missing template
        // is not fatal here: od_begin falls back to the family template.
        if (!r->embedding && llama_model_chat_template(r->model, nullptr)) {
            try {
                r->templates = common_chat_templates_init(r->model, "");
                r->supports_thinking = common_chat_templates_support_enable_thinking(r->templates.get());
            } catch (const std::exception &) { r->templates.reset(); }
        }
        r->supports_tools = probe_tools(r);
        // LoRA adapters (roadmap P2): loaded against the base weights, applied
        // to the context below with their scales. A wrong-architecture file
        // fails here with the adapter's name in the message.
        json adapter_report = json::array();
        std::vector<float> scales;
        if (s.contains("loraAdapters") && s["loraAdapters"].is_array() && !r->embedding) {
            for (const auto & a : s["loraAdapters"]) {
                const std::string apath = a.value("path", "");
                const float scale = a.value("scale", 1.0f);
                if (apath.empty() || scale == 0.0f) continue;
                auto * adapter = llama_adapter_lora_init(r->model, apath.c_str());
                if (!adapter) throw std::runtime_error("The adapter \"" + apath.substr(apath.find_last_of("/\\") + 1) + "\" could not be loaded: it is not a LoRA GGUF for this model's architecture.");
                r->adapters.push_back(adapter); scales.push_back(scale);
                char buf[256];
                std::string name = llama_adapter_meta_val_str(adapter, "general.name", buf, sizeof buf) >= 0 ? buf : "";
                adapter_report.push_back({{"path", apath}, {"scale", scale}, {"name", name}});
            }
        }
        r->ctx = llama_init_from_model(r->model, cp);
        if (!r->ctx) throw std::runtime_error("Cannot allocate context. Reduce context size, use FP16 cache, or choose a smaller model.");
        if (!r->adapters.empty() && llama_set_adapters_lora(r->ctx, r->adapters.data(), r->adapters.size(), scales.data()) != 0)
            throw std::runtime_error("The LoRA adapters could not be applied to this model.");
        r->adapter_report = adapter_report;
        r->n_swa = llama_model_n_swa(r->model);
        r->needs_checkpoints = llama_model_is_recurrent(r->model) || llama_model_is_hybrid(r->model) || r->n_swa > 0;
        // Vision projector: optional; a failure leaves the text model usable
        // and is reported so the app can say why photos are unavailable.
        if (!mmproj.empty()) {
            auto vp = mtmd_context_params_default();
            vp.use_gpu = mp.n_gpu_layers > 0;
            vp.device = vp.use_gpu ? r->devices.front() : nullptr;
            vp.n_threads = cp.n_threads_batch;
            vp.flash_attn_type = cp.flash_attn_type;
            vp.print_timings = false;
            vp.warmup = false;
            // Dynamic-resolution encoders (Qwen-VL style) would spend up to
            // the projector's own maximum on a photo; on a phone every image
            // token costs an encoder pass and a prefill token, so cap it.
            if (!r->embedding || s.contains("imageMaxTokens")) vp.image_max_tokens = std::clamp(s.value("imageMaxTokens", 1024), 64, 16384);
            r->mctx = mtmd_init_from_file(mmproj.c_str(), r->model, vp);
            if (!r->mctx) r->vision_error = "The vision projector could not be loaded (wrong file for this model, or out of memory).";
            else if (!mtmd_support_vision(r->mctx) && !(r->embedding && mtmd_support_audio(r->mctx))) { mtmd_free(r->mctx); r->mctx = nullptr; r->vision_error = "This projector has no image encoder."; }
        }
        // Draft model for speculative decoding (ABI 6): CPU only, plain FP16
        // KV, same context. Vocabulary mismatch is a load error the app shows.
        if (!draft.empty()) {
            r->draft_model = llama_model_load_from_file(draft.c_str(), dp);
            if (!r->draft_model) throw std::runtime_error("The draft model could not be loaded.");
            const auto why = draft_incompatible(r->model, r->draft_model);
            if (!why.empty()) throw std::runtime_error("Speculative decoding is off: " + why + ".");
            const auto dc = draft_context_params(r, cp);
            r->draft_ctx = llama_init_from_model(r->draft_model, dc);
            if (!r->draft_ctx) throw std::runtime_error("Cannot allocate the draft model's context. Reduce context size or turn speculative decoding off.");
            r->draft_max = std::clamp(s.value("draftMaxTokens", 6), 1, 32);
            r->draft_needs_checkpoints = llama_model_is_recurrent(r->draft_model) || llama_model_is_hybrid(r->draft_model)
                || llama_model_n_swa(r->draft_model) > 0;
            r->draft_sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
            llama_sampler_chain_add(r->draft_sampler, llama_sampler_init_greedy());
            char buf[256];
            r->draft_name = llama_model_meta_val_str(r->draft_model, "general.name", buf, sizeof buf) >= 0 ? buf : draft.substr(draft.find_last_of("/\\") + 1);
        }
        // These are accepted context parameters, not a claim that every tensor
        // was offloaded. Upstream may place unsupported operations on the CPU.
        r->effective = {{"contextSize", llama_n_ctx(r->ctx)}, {"batchSize", llama_n_batch(r->ctx)},
            {"microBatchSize", llama_n_ubatch(r->ctx)}, {"threads", llama_n_threads(r->ctx)},
            {"batchThreads", llama_n_threads_batch(r->ctx)}, {"requestedGpuLayers", mp.n_gpu_layers},
            {"kvCacheType", kv}, {"vCacheType", vv}, {"flashAttentionPolicy", cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_ENABLED
                ? "enabled" : cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_DISABLED ? "disabled" : "auto"},
            {"contextTrain", llama_model_n_ctx_train(r->model)}, {"memory", llama_model_is_hybrid(r->model) ? "hybrid"
                : llama_model_is_recurrent(r->model) ? "recurrent" : r->n_swa > 0 ? "swa" : "kv"},
            {"ropeScaling", rope}, {"ropeFreqBase", cp.rope_freq_base}, {"ropeFreqScale", cp.rope_freq_scale},
            {"ropeFreqScaleTrain", llama_model_rope_freq_scale_train(r->model)},
            {"adapters", (int)r->adapters.size()}, {"draftModel", r->draft_name}, {"draftMaxTokens", r->draft_max}};
        r->effective.update(admission);
        // Warm-up decode: GPU backends compile their kernels lazily, so a driver
        // that rejects a shader only fails here. Doing it at load time makes the
        // failure attributable (and the fallback possible) and moves the one-off
        // compile cost out of the user's first message.
        const auto * vocab = llama_model_get_vocab(r->model);
        llama_token probe = llama_vocab_bos(vocab);
        if (probe == LLAMA_TOKEN_NULL) probe = 0;
        if (llama_decode(r->ctx, llama_batch_get_one(&probe, 1)) != 0) throw std::runtime_error("Backend warm-up decode failed.");
        llama_memory_clear(llama_get_memory(r->ctx), true);
        if (r->draft_ctx) llama_memory_clear(llama_get_memory(r->draft_ctx), true);
        r->forget();
}
static mtmd_input_chunks * tokenize_media(Runtime * r, const std::string & text, const std::vector<std::string> & images, int & n_pos);
// One pooled, L2-normalised vector from the last decode, cut to [dims]
// (Matryoshka: EmbeddingGemma 2 is trained for 768/512/256/128) and
// normalised again so cosine similarity stays a dot product.
static std::vector<float> pooled(Runtime * r, int last, int dims) {
    const int n_out = llama_model_n_embd_out(r->model);
    const float * embd = llama_pooling_type(r->ctx) == LLAMA_POOLING_TYPE_NONE
        ? llama_get_embeddings_ith(r->ctx, last)
        : llama_get_embeddings_seq(r->ctx, 0);
    if (!embd) throw std::runtime_error("The model produced no embedding.");
    const int n = dims > 0 ? std::min(dims, n_out) : n_out;
    std::vector<float> out((size_t)n);
    common_embd_normalize(embd, out.data(), n, 2);
    return out;
}
// A text with photos or recordings (ABI 7): the projector encodes each
// medium, and its rows go into ONE batch with the text tokens, because the
// encoder attends both ways and pools over the whole sequence; separate
// decodes would pool only the last piece.
static std::vector<float> embed_media(Runtime * r, const std::string & text, const std::vector<std::string> & media, int dims) {
    std::string prompt;
    for (size_t i = 0; i < media.size(); ++i) prompt += mtmd_default_marker();
    if (!text.empty()) prompt += (prompt.empty() ? "" : " ") + text;
    int n_pos = 0;
    auto * chunks = tokenize_media(r, prompt, media, n_pos);
    std::unique_ptr<mtmd_input_chunks, decltype(&mtmd_input_chunks_free)> own(chunks, mtmd_input_chunks_free);
    const int total = (int)mtmd_helper_get_n_tokens(chunks);
    if (total > (int)llama_n_ctx(r->ctx)) throw std::runtime_error("This item is too long to index (" + std::to_string(total) + " tokens; the embedding context holds " + std::to_string(llama_n_ctx(r->ctx)) + "). Shorten the recording or use fewer photos.");
    const size_t n_inp = (size_t)llama_model_n_embd_inp(r->model);
    // The projector reuses its output buffer, so every medium is copied out.
    std::vector<std::vector<float>> rows;
    auto * batch = llama_batch_ext_init(r->ctx);
    std::unique_ptr<llama_batch_ext, decltype(&llama_batch_ext_free)> own_batch(batch, llama_batch_ext_free);
    llama_pos pos = 0; int last = -1;
    for (size_t i = 0; i < mtmd_input_chunks_size(chunks); ++i) {
        const auto * c = mtmd_input_chunks_get(chunks, i);
        if (mtmd_input_chunk_get_type(c) == MTMD_INPUT_CHUNK_TYPE_TEXT) {
            size_t n = 0; const auto * t = mtmd_input_chunk_get_tokens_text(c, &n);
            for (size_t k = 0; k < n; ++k) {
                last = llama_batch_ext_add_token(batch, 0, t[k]);
                if (last < 0) throw std::runtime_error("Embedding batch is full.");
                llama_batch_ext_set_pos(batch, last, &pos); ++pos;
            }
            continue;
        }
        if (mtmd_encode_chunk(r->mctx, c) != 0) throw std::runtime_error("The projector could not encode this photo or recording.");
        const size_t n = mtmd_input_chunk_get_n_tokens(c);
        const float * e = mtmd_get_output_embd(r->mctx);
        rows.emplace_back(e, e + n * n_inp);
        const float * kept = rows.back().data();
        for (size_t k = 0; k < n; ++k) {
            last = llama_batch_ext_add_embd(batch, 0, llama_embd{kept + k * n_inp, 1, n_inp});
            if (last < 0) throw std::runtime_error("Embedding batch is full.");
            llama_batch_ext_set_pos(batch, last, &pos); ++pos;
        }
    }
    if (last < 0) throw std::runtime_error("Nothing to embed.");
    llama_batch_ext_set_output_embd(batch, last, true);
    llama_memory_clear(llama_get_memory(r->ctx), true);
    if (llama_process(r->ctx, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) throw std::runtime_error("Embedding decode failed.");
    return pooled(r, last, dims);
}
// Tokens of a rerank prompt piece: the template's markup parses as special
// tokens, the query and document stay literal text.
static std::vector<llama_token> rank_tokens(const llama_vocab * vocab, const std::string & text, bool first, bool markup) {
    if (text.empty()) return {};
    int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, first, markup);
    if (count < 0) count = -count;
    std::vector<llama_token> tokens((size_t)count);
    const int n = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), count, first, markup);
    if (n < 0) throw std::runtime_error("Tokenization failed.");
    tokens.resize((size_t)n);
    return tokens;
}
// The classifier's raw outputs for one {query, document} pair with a
// reranker (pooling RANK). The GGUF's "rerank" template wraps the pair
// (Qwen3-Reranker: a yes/no judgement whose outputs are the "yes" and "no"
// logits); without one, query and document are joined the BERT way. A
// non-empty [instruction] replaces the template's "<Instruct>:" line (Qwen3
// rerankers are trained with task instructions). The document is cut so
// the pair fits the context.
static std::vector<float> rank_pair(Runtime * r, const std::string & query, const std::string & doc, const std::string & instruction) {
    const auto * vocab = llama_model_get_vocab(r->model);
    const int n_ctx = (int)llama_n_ctx(r->ctx);
    std::vector<std::vector<llama_token>> parts;
    int doc_part = -1;
    if (const char * t = llama_model_chat_template(r->model, "rerank")) {
        std::string rest = t;
        const std::string tag = "<Instruct>: ";
        const size_t at_tag = rest.find(tag);
        if (!instruction.empty() && at_tag != std::string::npos) {
            const size_t from = at_tag + tag.size(), to = rest.find('\n', from);
            if (to != std::string::npos) rest.replace(from, to - from, instruction);
        }
        bool first = true;
        while (!rest.empty()) {
            const size_t q = rest.find("{query}"), d = rest.find("{document}");
            const size_t at = std::min(q, d);
            std::string markup = rest.substr(0, at);
            // A space before the text belongs to its first word, as it would
            // in one tokenisation.
            std::string lead;
            if (at != std::string::npos && !markup.empty() && markup.back() == ' ') { markup.pop_back(); lead = " "; }
            parts.push_back(rank_tokens(vocab, markup, first, true));
            first = false;
            if (at == std::string::npos) break;
            if (at == d) doc_part = (int)parts.size();
            parts.push_back(rank_tokens(vocab, lead + (at == d ? doc : query), false, false));
            rest = rest.substr(at + (at == d ? 10 : 7));
        }
    } else {
        std::vector<llama_token> head;
        if (llama_vocab_get_add_bos(vocab)) head.push_back(llama_vocab_bos(vocab));
        llama_token eos = llama_vocab_eos(vocab);
        if (eos == LLAMA_TOKEN_NULL) eos = llama_vocab_sep(vocab);
        std::vector<llama_token> sep;
        if (llama_vocab_get_add_eos(vocab)) sep.push_back(eos);
        if (llama_vocab_get_add_sep(vocab)) sep.push_back(llama_vocab_sep(vocab));
        parts.push_back(head);
        parts.push_back(rank_tokens(vocab, query, false, false));
        parts.push_back(sep);
        doc_part = (int)parts.size();
        parts.push_back(rank_tokens(vocab, doc, false, false));
        if (llama_vocab_get_add_eos(vocab)) parts.push_back({eos});
    }
    size_t total = 0;
    for (const auto & p : parts) total += p.size();
    if ((int)total > n_ctx) {
        if (doc_part < 0 || total - parts[doc_part].size() + 16 > (size_t)n_ctx) throw std::runtime_error("This pair is too long to score.");
        parts[doc_part].resize(parts[doc_part].size() - (total - (size_t)n_ctx));
    }
    std::vector<llama_token> tokens;
    for (const auto & p : parts) tokens.insert(tokens.end(), p.begin(), p.end());
    if (tokens.empty()) throw std::runtime_error("Nothing to score.");
    llama_memory_clear(llama_get_memory(r->ctx), true);
    if (llama_decode(r->ctx, llama_batch_get_one(tokens.data(), (int)tokens.size())) != 0) throw std::runtime_error("Scoring decode failed.");
    const float * out = llama_get_embeddings_seq(r->ctx, 0);
    if (!out) throw std::runtime_error("The model produced no score.");
    const int n = std::max(1, (int)llama_model_n_cls_out(r->model));
    return std::vector<float>(out, out + n);
}
// Embeds every item of request.texts with the loaded embedding model: one
// item per decode, truncated to the context, pooled by the model's policy
// and L2-normalised so cosine similarity is a dot product. An item is a
// string, or (ABI 7) {"text": "...", "media": ["/path.jpg", "/note.wav"]}
// for photos and recordings through the loaded projector. Optional
// request.dims cuts every vector to its leading dimensions (Matryoshka).
// Returns {"dim": n, "vectors": [[...], ...]} or null (see od_error).
// With a reranker loaded, request.pairs ([{"query", "document"}, ...])
// returns {"labels": [...], "scores": [[raw outputs], ...]} instead
// (optional request.instruction: see rank_pair).
const char * od_embed(void * h, const char * request) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    try {
        if (r->released) throw std::runtime_error(released_message);
        if (!r->ctx) throw std::runtime_error("No model loaded.");
        if (!r->embedding) throw std::runtime_error("The loaded model is not an embedding model.");
        auto req = json::parse(request);
        const auto * vocab = llama_model_get_vocab(r->model);
        const int n_ctx = (int)llama_n_ctx(r->ctx);
        const int dims = req.value("dims", 0);
        if (req.contains("pairs")) {
            if (llama_pooling_type(r->ctx) != LLAMA_POOLING_TYPE_RANK) throw std::runtime_error("The loaded model is not a reranker.");
            json labels = json::array(), scores = json::array();
            for (uint32_t i = 0; i < llama_model_n_cls_out(r->model); ++i) {
                const char * l = llama_model_cls_label(r->model, i);
                labels.push_back(l ? l : "");
            }
            for (const auto & p : req.at("pairs")) {
                if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Scoring cancelled.");
                scores.push_back(rank_pair(r, p.value("query", std::string()), p.value("document", std::string()), req.value("instruction", std::string())));
            }
            r->embedded = json{{"labels", labels}, {"scores", scores}}.dump();
            return r->embedded.c_str();
        }
        json vectors = json::array();
        int dim = 0;
        for (const auto & item : req.at("texts")) {
            if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Embedding cancelled.");
            std::vector<float> v;
            std::string text;
            if (item.is_object()) {
                std::vector<std::string> media;
                for (const auto & m : item.value("media", json::array())) media.push_back(m.get<std::string>());
                text = item.value("text", std::string());
                if (!media.empty()) { v = embed_media(r, text, media, dims); vectors.push_back(v); dim = (int)v.size(); continue; }
            } else {
                text = item.get<std::string>();
            }
            // Passage text is data: special-token syntax inside it stays literal.
            int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, true, false);
            if (count < 0) count = -count;
            std::vector<llama_token> tokens((size_t)count);
            int n = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), count, true, false);
            if (n <= 0) throw std::runtime_error("Tokenization failed.");
            tokens.resize((size_t)std::min(n, n_ctx));
            llama_memory_clear(llama_get_memory(r->ctx), true);
            if (llama_decode(r->ctx, llama_batch_get_one(tokens.data(), (int)tokens.size())) != 0) throw std::runtime_error("Embedding decode failed.");
            v = pooled(r, (int)tokens.size() - 1, dims);
            dim = (int)v.size();
            vectors.push_back(v);
        }
        if (dim == 0) dim = dims > 0 ? std::min(dims, llama_model_n_embd_out(r->model)) : llama_model_n_embd_out(r->model);
        r->embedded = json{{"dim", dim}, {"vectors", vectors}}.dump();
        return r->embedded.c_str();
    } catch (const std::exception & e) { r->error = e.what(); return nullptr; }
}
// GGUF header only (no tensor data): enough to tell a LoRA adapter, its base
// architecture and name before it is attached to a model.
const char * od_adapter_info(void * h, const char * path) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    try {
        gguf_init_params ip{true, nullptr};
        gguf_context * g = gguf_init_from_file(path, ip);
        if (!g) throw std::runtime_error("Not a GGUF file.");
        json keys = json::object();
        const int64_t n = gguf_get_n_kv(g);
        for (int64_t i = 0; i < n; ++i) {
            const char * key = gguf_get_key(g, i);
            const auto type = gguf_get_kv_type(g, i);
            if (type == GGUF_TYPE_STRING) keys[key] = gguf_get_val_str(g, i);
            else if (type == GGUF_TYPE_FLOAT32) keys[key] = gguf_get_val_f32(g, i);
            else if (type == GGUF_TYPE_UINT32) keys[key] = gguf_get_val_u32(g, i);
            else if (type == GGUF_TYPE_INT32) keys[key] = gguf_get_val_i32(g, i);
            else if (type == GGUF_TYPE_BOOL) keys[key] = gguf_get_val_bool(g, i);
        }
        const int64_t tensors = gguf_get_n_tensors(g);
        gguf_free(g);
        r->adapter_info = json{{"architecture", keys.value("general.architecture", "")}, {"type", keys.value("general.type", "")},
            {"adapterType", keys.value("adapter.type", "")}, {"name", keys.value("general.name", "")},
            {"alpha", keys.contains("adapter.lora.alpha") && keys["adapter.lora.alpha"].is_number() ? keys["adapter.lora.alpha"].get<double>() : 0.0}, {"tensors", tensors}, {"keys", keys}}.dump();
        return r->adapter_info.c_str();
    } catch (const std::exception & e) { r->error = e.what(); return nullptr; }
}
int32_t od_load(void * h, const char * path, const char * settings) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    try {
        if (r->released) throw std::runtime_error(released_message);
        r->unload(); r->error.clear(); r->prompt.clear(); r->generated = 0; r->trimmed = 0; r->first_ms = 0;
        auto s = json::parse(settings);
        const std::string requested = s.value("backend", "auto");
        if (requested == "qnn") throw std::runtime_error("QNN is not integrated in this build. Select Auto or CPU.");
        try {
            load_with(r, path, s, requested);
        } catch (const std::exception & e) {
            // A GPU driver can reject shaders while the device is enumerated or
            // the context is created (Adreno + Vulkan does). With Auto we retry
            // on the CPU and report why; if that also fails, the CPU error is
            // the real one and propagates.
            if (requested != "auto" || r->cancelled->load(std::memory_order_relaxed)) throw;
            std::string reason = e.what();
            r->unload();
            load_with(r, path, s, "cpu");
            r->fallback_reason = reason;
            r->backend = "CPU (GPU unavailable: " + reason + ")";
        }
        return 0;
    } catch (const std::exception & e) { r->unload(); return fail(r, e); }
}
static bool ends_with_tag(const std::string & text, const std::string & tag) {
    size_t end = text.find_last_not_of(" \t\r\n");
    if (tag.empty() || end == std::string::npos) return false;
    ++end;
    return end >= tag.size() && text.compare(end - tag.size(), tag.size(), tag) == 0;
}
// Continuation (CHAT-02): the caller's partial answer is appended verbatim
// after the generation prompt so the model resumes it. If the template had
// opened a reasoning block, close it first: the prefix is final-answer text.
static std::string with_prefix(Runtime * r, std::string text, const std::string & prefix) {
    if (prefix.empty()) return text;
    if (r->forced_open && !r->think_ends.empty()) text += r->think_ends.front();
    r->forced_open = false;
    return text + prefix;
}
static std::vector<common_chat_tool> tools_of(const json & req) {
    std::vector<common_chat_tool> out;
    if (!req.contains("tools") || !req["tools"].is_array()) return out;
    for (const auto & t : req["tools"]) {
        common_chat_tool tool;
        tool.name = t.value("name", "");
        tool.description = t.value("description", "");
        tool.parameters = t.contains("parameters") ? (t["parameters"].is_string() ? t["parameters"].get<std::string>() : t["parameters"].dump()) : "{}";
        if (!tool.name.empty()) out.push_back(tool);
    }
    return out;
}
// Message JSON -> common_chat_msg: assistant turns may carry tool_calls
// [{id, name, arguments}], tool results use role "tool" with tool_call_id.
static common_chat_msg message_of(const json & m) {
    common_chat_msg msg;
    msg.role = m.at("role").get<std::string>();
    msg.content = m.value("content", "");
    if (m.contains("tool_calls") && m["tool_calls"].is_array()) {
        for (const auto & c : m["tool_calls"]) {
            common_chat_tool_call call;
            call.id = c.value("id", "");
            call.name = c.value("name", "");
            call.arguments = c.contains("arguments") ? (c["arguments"].is_string() ? c["arguments"].get<std::string>() : c["arguments"].dump()) : "{}";
            msg.tool_calls.push_back(call);
        }
    }
    msg.tool_call_id = m.value("tool_call_id", "");
    msg.tool_name = m.value("name", "");
    return msg;
}
// [generation] false renders the history only (no assistant prompt): the
// token count of that text is where the next turn will still match this one.
// With tools, the template's grammar/parser for calls come back in [params].
static std::string render(Runtime * r, const json & messages, const std::string & fallback, bool thinking, bool generation = true,
                          const std::vector<common_chat_tool> & tools = {}, const std::string & tool_choice = "auto", common_chat_params * params_out = nullptr) {
    if (generation) { r->forced_open = false; r->think_start.clear(); r->think_ends.clear(); }
    if (r->templates) {
        common_chat_templates_inputs inputs;
        for (const auto & m : messages) inputs.messages.push_back(message_of(m));
        inputs.enable_thinking = thinking;
        inputs.add_generation_prompt = generation;
        if (!tools.empty()) {
            inputs.tools = tools;
            inputs.tool_choice = tool_choice == "required" ? COMMON_CHAT_TOOL_CHOICE_REQUIRED
                : tool_choice == "none" ? COMMON_CHAT_TOOL_CHOICE_NONE : COMMON_CHAT_TOOL_CHOICE_AUTO;
            inputs.parallel_tool_calls = false;
        }
        auto params = common_chat_templates_apply(r->templates.get(), inputs);
        if (!generation) return params.prompt;
        r->think_start = params.thinking_start_tag; r->think_ends = params.thinking_end_tags;
        // Some templates open the reasoning block inside the prompt itself, so the
        // model never emits the opening tag. Dart re-inserts it.
        r->forced_open = params.supports_thinking && thinking && ends_with_tag(params.prompt, params.thinking_start_tag);
        if (params_out) *params_out = params;
        return params.prompt;
    }
    std::vector<llama_chat_message> chat;
    for (const auto & m : messages) {
        if (m.contains("tool_calls") || m.value("role", "") == "tool") throw std::runtime_error("This model's fallback template cannot carry tool calls. Use a GGUF that ships its own chat template.");
        chat.push_back({m.at("role").get_ref<const std::string &>().c_str(), m.at("content").get_ref<const std::string &>().c_str()});
    }
    if (fallback.empty()) throw std::runtime_error("This GGUF ships no chat template. Import it again and choose its model family as the template fallback.");
    int n = llama_chat_apply_template(fallback.c_str(), chat.data(), chat.size(), generation, nullptr, 0);
    if (n < 0) throw std::runtime_error("Unsupported chat template. Import with the correct model family, or use a supported GGUF.");
    std::vector<char> out(n + 1);
    int written = llama_chat_apply_template(fallback.c_str(), chat.data(), chat.size(), generation, out.data(), out.size());
    if (written < 0 || written > n) throw std::runtime_error("Chat template rendering failed.");
    return std::string(out.data(), written);
}
static std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & text) {
    int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, true, true);
    if (count < 0) count = -count;
    std::vector<llama_token> out(count);
    int n = llama_tokenize(vocab, text.data(), text.size(), out.data(), count, true, true);
    if (n < 0) throw std::runtime_error("Tokenization failed.");
    out.resize(n);
    return out;
}
// Photos in the rendered prompt: every media marker becomes the matching
// bitmap's tokens. Returns the chunks (caller owns) and the positions they
// will occupy, the number that must fit the context.
static mtmd_input_chunks * tokenize_media(Runtime * r, const std::string & text, const std::vector<std::string> & images, int & n_pos) {
    if (!r->mctx) throw std::runtime_error(r->vision_error.empty()
        ? "This model has no vision projector. Add vision under Models, pick a vision model, or remove the photo."
        : r->vision_error);
    std::vector<const mtmd_bitmap *> bms;
    // Decoded photos are ~7 MB each; keep a handful, not a gallery.
    if (r->bitmaps.size() > 8) { for (auto & b : r->bitmaps) mtmd_bitmap_free(b.second); r->bitmaps.clear(); }
    for (const auto & path : images) {
        auto it = r->bitmaps.find(path);
        if (it == r->bitmaps.end()) {
            auto w = mtmd_helper_bitmap_init_from_file(r->mctx, path.c_str(), false, mtmd_helper_init_opt_default());
            if (!w.bitmap) throw std::runtime_error("Could not decode the attached photo or recording (images: jpg/png/bmp/gif; audio: wav/mp3/flac).");
            if (w.video_ctx) mtmd_helper_video_free(w.video_ctx);
            mtmd_bitmap_set_id(w.bitmap, path.c_str());
            it = r->bitmaps.emplace(path, w.bitmap).first;
        }
        bms.push_back(it->second);
    }
    auto * out = mtmd_input_chunks_init();
    mtmd_input_text in{text.c_str(), text.size(), true, true};
    const int rc = mtmd_tokenize(r->mctx, out, &in, bms.data(), bms.size());
    if (rc != 0) {
        mtmd_input_chunks_free(out);
        throw std::runtime_error(rc == 1 ? "Photo count and media markers differ." : "Photo or audio preprocessing failed.");
    }
    n_pos = (int)mtmd_helper_get_n_pos(out);
    return out;
}
static int restore_checkpoint(Runtime * r, int limit);
static void take_checkpoint(Runtime * r, int pos);
// Bitmaps decoded by the helper carry no id; the attachment path is unique
// per photo in the app, so it identifies the encoded image across turns.
static void flatten_chunks(const mtmd_input_chunks * chunks, std::vector<llama_token> & flat, std::vector<Runtime::MediaMeta> & meta) {
    flat.clear(); meta.clear();
    for (size_t i = 0; i < mtmd_input_chunks_size(chunks); ++i) {
        const auto * c = mtmd_input_chunks_get(chunks, i);
        if (mtmd_input_chunk_get_type(c) == MTMD_INPUT_CHUNK_TYPE_TEXT) {
            size_t n = 0; const auto * t = mtmd_input_chunk_get_tokens_text(c, &n);
            flat.insert(flat.end(), t, t + n);
        } else {
            const size_t n = mtmd_input_chunk_get_n_tokens(c);
            meta.push_back({flat.size(), mtmd_input_chunk_get_id(c) ? mtmd_input_chunk_get_id(c) : "", n, mtmd_input_chunk_get_n_pos(c)});
            flat.insert(flat.end(), n, LLAMA_TOKEN_NULL);
        }
    }
}
static const Runtime::MediaMeta * media_at(const std::vector<Runtime::MediaMeta> & meta, size_t idx) {
    for (const auto & m : meta) if (idx >= m.idx && idx < m.idx + m.n_tokens) return &m;
    return nullptr;
}
// Longest common prefix of two flattened prompts; an image counts only whole
// and only when the same photo produced the same number of tokens.
static size_t media_common_prefix(const std::vector<llama_token> & a, const std::vector<Runtime::MediaMeta> & am,
                                  const std::vector<llama_token> & b, const std::vector<Runtime::MediaMeta> & bm) {
    const size_t n = std::min(a.size(), b.size());
    for (size_t i = 0; i < n; ++i) {
        if (a[i] == LLAMA_TOKEN_NULL || b[i] == LLAMA_TOKEN_NULL) {
            const auto * x = media_at(am, i); const auto * y = media_at(bm, i);
            if (!x || !y || x->idx != i || y->idx != i || x->id != y->id || x->n_tokens != y->n_tokens || x->n_pos != y->n_pos) return i;
            i += x->n_tokens - 1;
            continue;
        }
        if (a[i] != b[i]) return i;
    }
    return n;
}
// KV position of flat index [idx] (images occupy n_pos positions, not n_tokens).
static llama_pos media_pos_of(const std::vector<Runtime::MediaMeta> & meta, size_t idx) {
    llama_pos pos = (llama_pos)idx;
    for (const auto & m : meta) if (m.idx + m.n_tokens <= idx) pos += m.n_pos - (llama_pos)m.n_tokens;
    return pos;
}
// Inverse of media_pos_of: the flat index at KV position [pos]; a position
// inside an image maps to that image's start.
static size_t media_idx_of(const std::vector<Runtime::MediaMeta> & meta, llama_pos pos) {
    size_t idx = 0; llama_pos p = 0;
    for (const auto & m : meta) {
        const llama_pos text = (llama_pos)(m.idx - idx);
        if (p + text >= pos) return idx + (size_t)(pos - p);
        p += text; idx = m.idx;
        if (p + m.n_pos > pos) return m.idx;
        p += m.n_pos; idx += m.n_tokens;
    }
    return idx + (size_t)(pos - p);
}
// Decides how much of the resident sequence a photo turn keeps, mirroring
// reuse_prefix() for text. Sets media_keep/media_keep_pos for eval_media().
static void reuse_media_prefix(Runtime * r, bool enabled) {
    auto mem = llama_get_memory(r->ctx);
    flatten_chunks(r->chunks, r->media_flat, r->media_meta_next);
    size_t keep = enabled ? media_common_prefix(r->cached, r->media_meta, r->media_flat, r->media_meta_next) : 0;
    // At least one token is evaluated so the answer has logits; never cut an image.
    if (keep >= r->media_flat.size()) keep = r->media_flat.size() - 1;
    if (const auto * m = media_at(r->media_meta_next, keep); m && m->idx != keep) keep = m->idx;
    llama_pos keep_pos = media_pos_of(r->media_meta_next, keep);
    bool ok = keep > 0;
    if (ok) {
        ok = llama_memory_seq_rm(mem, 0, keep_pos, -1);
        if (ok && r->n_swa > 0) ok = llama_memory_seq_pos_min(mem, 0) <= std::max(0, keep_pos - r->n_swa);
        if (!ok) {
            const int pos = restore_checkpoint(r, keep_pos);
            ok = pos > 0;
            if (ok) { keep_pos = pos; keep = media_idx_of(r->media_meta_next, pos); }
        }
    }
    if (!ok) { llama_memory_clear(mem, true); keep = 0; keep_pos = 0; }
    r->cached.assign(r->media_flat.begin(), r->media_flat.begin() + keep);
    r->media_meta.clear();
    for (const auto & m : r->media_meta_next) if (m.idx + m.n_tokens <= keep) r->media_meta.push_back(m);
    r->checkpoints.erase(std::remove_if(r->checkpoints.begin(), r->checkpoints.end(), [&](const Runtime::Checkpoint & c) { return c.pos > keep_pos; }), r->checkpoints.end());
    r->media_keep = keep; r->media_keep_pos = keep_pos; r->reused = (int)keep; r->cursor = 0;
    r->media_checkpoint_at = -1;
    // The draft never sees photo turns (speculation is off with media).
    if (r->draft_ctx) { llama_memory_clear(llama_get_memory(r->draft_ctx), true); r->draft_cached.clear(); r->draft_queue.clear(); }
}
// Evaluates the part of the photo turn that is not resident yet: text runs
// with explicit positions, images through the mtmd helper, a checkpoint at
// the history boundary for memories that cannot drop a tail.
static void eval_media(Runtime * r) {
    const size_t total = r->media_flat.size();
    size_t idx = 0; llama_pos pos = 0;
    llama_batch batch = llama_batch_init(r->batch, 0, 1);
    auto free_batch = [&]() { llama_batch_free(batch); };
    try {
        for (size_t i = 0; i < mtmd_input_chunks_size(r->chunks); ++i) {
            const auto * c = mtmd_input_chunks_get(r->chunks, i);
            if (mtmd_input_chunk_get_type(c) == MTMD_INPUT_CHUNK_TYPE_TEXT) {
                size_t n = 0; const auto * t = mtmd_input_chunk_get_tokens_text(c, &n);
                const size_t end = idx + n;
                if (end <= r->media_keep) { idx = end; pos += (llama_pos)n; continue; }
                size_t k = std::max(idx, r->media_keep);
                pos += (llama_pos)(k - idx);
                // A boundary right at the start of this run (after an image
                // or at the resident prefix) is checkpointed before decoding.
                if ((long)k == r->media_checkpoint_at) { take_checkpoint(r, pos); r->media_checkpoint_at = -1; }
                while (k < end) {
                    size_t stop = std::min(end, k + (size_t)r->batch);
                    if (r->media_checkpoint_at > (long)k && r->media_checkpoint_at < (long)stop) stop = (size_t)r->media_checkpoint_at;
                    batch.n_tokens = 0;
                    for (size_t j = k; j < stop; ++j) {
                        const int32_t b = batch.n_tokens++;
                        batch.token[b] = t[j - idx]; batch.pos[b] = pos++;
                        batch.n_seq_id[b] = 1; batch.seq_id[b][0] = 0;
                        batch.logits[b] = j + 1 == total;
                    }
                    if (llama_decode(r->ctx, batch) != 0) throw std::runtime_error("Evaluating the photo turn failed. Try a smaller context or the CPU backend.");
                    k = stop;
                    if ((long)k == r->media_checkpoint_at) { take_checkpoint(r, pos); r->media_checkpoint_at = -1; }
                }
                idx = end;
            } else {
                const size_t n = mtmd_input_chunk_get_n_tokens(c);
                if (idx + n <= r->media_keep) { idx += n; pos += mtmd_input_chunk_get_n_pos(c); continue; }
                llama_pos next = pos;
                if (mtmd_helper_eval_chunk_single(r->mctx, r->ctx, c, pos, 0, r->batch, idx + n == total, &next) != 0)
                    throw std::runtime_error("Evaluating the photo failed. Try a smaller context or the CPU backend.");
                pos = next; idx += n;
            }
        }
    } catch (...) { free_batch(); r->forget(); llama_memory_clear(llama_get_memory(r->ctx), true); throw; }
    free_batch();
    r->cached = r->media_flat; r->media_meta = r->media_meta_next;
    r->media_tokens = (int)pos; r->media_pending = false;
}
static std::vector<std::string> images_of(const json & messages) {
    std::vector<std::string> out;
    for (const auto & m : messages)
        if (m.contains("images") && m["images"].is_array())
            for (const auto & p : m["images"]) if (p.is_string()) out.push_back(p.get<std::string>());
    return out;
}
// Restores the newest checkpoint at or before [limit]. Returns the position
// the sequence now ends at, or -1 when none applied.
static int restore_checkpoint(Runtime * r, int limit) {
    auto mem = llama_get_memory(r->ctx);
    for (auto it = r->checkpoints.rbegin(); it != r->checkpoints.rend(); ++it) {
        if (it->pos > limit) continue;
        if (llama_state_seq_set_data_ext(r->ctx, it->data.data(), it->data.size(), 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) continue;
        if (!llama_memory_seq_rm(mem, 0, it->pos, -1)) continue;
        return it->pos;
    }
    return -1;
}
static void take_checkpoint(Runtime * r, int pos) {
    const size_t size = llama_state_seq_get_size_ext(r->ctx, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY);
    if (size == 0 || size > (size_t)256 << 20) return;
    Runtime::Checkpoint c{pos, std::vector<uint8_t>(size)};
    if (llama_state_seq_get_data_ext(r->ctx, c.data.data(), size, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) != size) return;
    r->checkpoints.erase(std::remove_if(r->checkpoints.begin(), r->checkpoints.end(), [&](const Runtime::Checkpoint & o) { return o.pos == c.pos; }), r->checkpoints.end());
    r->checkpoints.push_back(std::move(c));
    // Keep the earliest boundary (the system prompt and schema, from the
    // chat's first question) and the two newest (where the last question
    // starts and ends). Transient tool rounds, a clock line or evidence in a
    // request extend history the saved conversation does not keep; without
    // an earlier boundary a recurrent model prefills everything next turn.
    while (r->checkpoints.size() > 3) r->checkpoints.erase(r->checkpoints.begin() + 1);
    size_t total = 0;
    for (const auto & checkpoint : r->checkpoints) total += checkpoint.data.size();
    // Bound total checkpoint memory, not just the size of each snapshot.
    while (total > (size_t)256 << 20 && r->checkpoints.size() > 1) {
        total -= r->checkpoints.front().data.size();
        r->checkpoints.erase(r->checkpoints.begin());
    }
}
// Decides how much of the resident sequence survives for the new prompt.
static void reuse_prefix(Runtime * r, bool enabled) {
    auto mem = llama_get_memory(r->ctx);
    int keep = 0;
    if (enabled) {
        const int limit = std::min((int)r->cached.size(), (int)r->prompt.size() - 1);
        while (keep < limit && r->cached[keep] == r->prompt[keep]) ++keep;
    }
    bool ok = keep > 0;
    if (ok) {
        // Plain KV caches drop a tail; recurrent/hybrid memories refuse unless a
        // bounded rollback covers it; a sliding window must still hold the
        // n_swa tokens before the cut (same rule as llama-server).
        ok = llama_memory_seq_rm(mem, 0, keep, -1);
        if (ok && r->n_swa > 0) ok = llama_memory_seq_pos_min(mem, 0) <= std::max(0, keep - r->n_swa);
        if (!ok) {
            const int pos = restore_checkpoint(r, keep);
            ok = pos > 0; if (ok) keep = pos;
        }
    }
    if (!ok) { llama_memory_clear(mem, true); keep = 0; }
    // LLAMA_TOKEN_NULL placeholders never match a real token, so the common
    // prefix ends before the first image and positions equal indices there.
    r->cached.assign(r->prompt.begin(), r->prompt.begin() + keep);
    r->media_meta.clear();
    r->checkpoints.erase(std::remove_if(r->checkpoints.begin(), r->checkpoints.end(), [&](const Runtime::Checkpoint & c) { return c.pos > keep; }), r->checkpoints.end());
    r->cursor = keep; r->reused = keep;
    // The draft mirrors the target: keep its matching prefix, drop the rest.
    if (r->draft_ctx) {
        auto dmem = llama_get_memory(r->draft_ctx);
        int dkeep = 0;
        const int limit = std::min((int)r->draft_cached.size(), (int)r->prompt.size());
        while (dkeep < limit && r->draft_cached[dkeep] == r->prompt[dkeep]) ++dkeep;
        if (dkeep == 0 || !llama_memory_seq_rm(dmem, 0, dkeep, -1)) { llama_memory_clear(dmem, true); dkeep = 0; }
        r->draft_cached.assign(r->prompt.begin(), r->prompt.begin() + dkeep);
        r->draft_queue.assign(r->prompt.begin() + dkeep, r->prompt.end());
    }
}
// Room kept for reasoning when the prompt is placed: Max tokens is the
// answer's since 2026-09-28 (review) and thinking comes on top, up to
// its budget and at most a quarter of the context.
static int think_room(const json & s, int context) {
    if (!s.value("thinkingModeEnabled", false) || s.value("responseFormat", std::string("text")) != "text") return 0;
    const int budget = s.value("thinkingBudgetTokens", 0);
    return std::min(budget > 0 ? budget : context / 4, context / 4);
}
const char * od_preview(void * h, const char * request) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    // render() discovers thinking markers; preserve the active generation's metadata.
    const auto forced = r->forced_open;
    const auto start = r->think_start;
    const auto ends = r->think_ends;
    auto restore = [&] { r->forced_open = forced; r->think_start = start; r->think_ends = ends; };
    try {
        if (r->released) throw std::runtime_error(released_message);
        if (!r->ctx) throw std::runtime_error("No model loaded.");
        if (r->embedding) throw std::runtime_error("This is an embedding model; it cannot chat.");
        auto req = json::parse(request);
        auto s = req.at("settings");
        auto text = with_prefix(r, render(r, req.at("messages"), req.value("fallbackTemplate", ""), s.value("thinkingModeEnabled", false), true, tools_of(req), req.value("toolChoice", "auto")), req.value("assistantPrefix", ""));
        int count = 0;
        const auto images = images_of(req.at("messages"));
        if (!images.empty()) {
            auto * chunks = tokenize_media(r, text, images, count);
            mtmd_input_chunks_free(chunks);
        } else {
            count = llama_tokenize(llama_model_get_vocab(r->model), text.data(), text.size(), nullptr, 0, true, true);
            if (count < 0) count = -count;
        }
        const int context = llama_n_ctx(r->ctx);
        const int reserve = std::min(std::clamp(s.value("maxTokens", 1024), 1, context - 1) + think_room(s, context), context - 1);
        r->preview = json{{"promptTokens", count}, {"contextSize", context},
            {"reservedTokens", reserve}, {"availableTokens", context - reserve - count},
            {"fits", count + reserve <= context}}.dump();
        restore();
        return r->preview.c_str();
    } catch (const std::exception & e) { restore(); r->error = e.what(); return nullptr; }
}
// The sampler chain in the user's order (ABI 6). Names follow llama.cpp:
// penalties, dry, top_n_sigma, top_k, typ_p, top_p, min_p, xtc, temperature.
static void build_sampler(Runtime * r, const json & s, const std::string & grammar, bool grammar_lazy,
                          const std::vector<std::string> & trigger_patterns, const std::vector<llama_token> & trigger_tokens, const std::string & generation_prompt, bool prefill_grammar) {
    const auto * vocab = llama_model_get_vocab(r->model);
    r->sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!grammar.empty()) {
        llama_sampler * g = nullptr;
        if (grammar_lazy) {
            std::vector<const char *> pats;
            for (const auto & p : trigger_patterns) pats.push_back(p.c_str());
            g = llama_sampler_init_grammar_lazy_patterns(vocab, grammar.c_str(), "root", pats.data(), pats.size(), trigger_tokens.data(), trigger_tokens.size());
        } else {
            g = llama_sampler_init_grammar(vocab, grammar.c_str(), "root");
        }
        if (!g) throw std::runtime_error("The grammar could not be parsed. Check the GBNF or JSON schema.");
        // Tool/format grammars generated by the template already contain the
        // generation prompt the template placed in the prompt.
        if (prefill_grammar && !grammar_lazy && !generation_prompt.empty()) {
            try {
                auto tokens = common_tokenize(vocab, generation_prompt, false, true);
                for (size_t i = 0; i < tokens.size(); ++i) {
                    // Some tokenizers put a space before the first special token.
                    const auto piece = common_token_to_piece(vocab, tokens[i], true);
                    if (i == 0 && !piece.empty() && std::isspace((unsigned char)piece[0]) && !std::isspace((unsigned char)generation_prompt[0])) continue;
                    llama_sampler_accept(g, tokens[i]);
                }
            } catch (const std::exception &) {}
        }
        r->grammar = g;
    }
    const float temp = s.value("temperature", 0.7f);
    const int last_n = s.value("repeatLastN", 64);
    auto add_penalties = [&] {
        llama_sampler_chain_add(r->sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), last_n, s.value("repetitionPenalty", 1.0f),
            s.value("frequencyPenalty", 0.0f), s.value("presencePenalty", 0.0f)));
    };
    auto add_dry = [&] {
        const float mult = s.value("dryMultiplier", 0.0f);
        if (mult <= 0) return;
        static const char * breakers[] = {"\n", ":", "\"", "*"};
        llama_sampler_chain_add(r->sampler, llama_sampler_init_dry(vocab, mult, s.value("dryBase", 1.75f),
            s.value("dryAllowedLength", 2), s.value("dryPenaltyLastN", -1), breakers, 4));
    };
    if (temp <= 0) {
        add_penalties(); add_dry();
        llama_sampler_chain_add(r->sampler, llama_sampler_init_greedy());
        return;
    }
    std::vector<std::string> order = {"penalties", "dry", "top_n_sigma", "top_k", "typ_p", "top_p", "min_p", "xtc", "temperature"};
    if (s.contains("samplerOrder") && s["samplerOrder"].is_array() && !s["samplerOrder"].empty()) {
        order.clear();
        for (const auto & n : s["samplerOrder"]) if (n.is_string()) order.push_back(n.get<std::string>());
        // Anything the user's list omits is appended in the default order, so a
        // stale list never silently drops the temperature.
        for (const char * n : {"penalties", "dry", "top_n_sigma", "top_k", "typ_p", "top_p", "min_p", "xtc", "temperature"})
            if (std::find(order.begin(), order.end(), n) == order.end()) order.push_back(n);
    }
    const uint32_t seed = s.value("seed", 0) > 0 ? (uint32_t)s.value("seed", 0) : LLAMA_DEFAULT_SEED;
    for (const auto & name : order) {
        if (name == "penalties") add_penalties();
        else if (name == "dry") add_dry();
        else if (name == "top_n_sigma") { if (s.value("topNSigma", -1.0f) > 0) llama_sampler_chain_add(r->sampler, llama_sampler_init_top_n_sigma(s.value("topNSigma", -1.0f))); }
        else if (name == "top_k") { if (s.value("topK", 40) > 0) llama_sampler_chain_add(r->sampler, llama_sampler_init_top_k(s.value("topK", 40))); }
        else if (name == "typ_p") { if (s.value("typicalP", 1.0f) < 1.0f) llama_sampler_chain_add(r->sampler, llama_sampler_init_typical(s.value("typicalP", 1.0f), 1)); }
        else if (name == "top_p") llama_sampler_chain_add(r->sampler, llama_sampler_init_top_p(s.value("topP", .95f), 1));
        else if (name == "min_p") llama_sampler_chain_add(r->sampler, llama_sampler_init_min_p(s.value("minP", .05f), 1));
        else if (name == "xtc") { if (s.value("xtcProbability", 0.0f) > 0) llama_sampler_chain_add(r->sampler, llama_sampler_init_xtc(s.value("xtcProbability", 0.0f), s.value("xtcThreshold", 0.1f), 1, seed)); }
        else if (name == "temperature") llama_sampler_chain_add(r->sampler, llama_sampler_init_temp(temp));
    }
    llama_sampler_chain_add(r->sampler, llama_sampler_init_dist(seed));
}
// Sampling with the grammar applied first, then the user's chain, as
// llama_sampler_sample would do for a single chain.
// Sampling with grammar-based rejection, as llama.cpp's common_sampler
// does: the chain picks a token from the raw logits; only when the grammar
// refuses that one token are the logits rebuilt, the grammar applied over
// the whole vocabulary and the chain run again. A JSON or tool-call
// answer mostly proposes legal tokens, so the full grammar pass — a walk
// over every vocabulary entry, tens of thousands of them per token — is
// the exception rather than the rule.
static llama_token_data_array fill_candidates(Runtime * r, int idx) {
    const float * logits = llama_get_logits_ith(r->ctx, idx);
    if (!logits) throw std::runtime_error("No logits for sampling.");
    const int n = llama_vocab_n_tokens(llama_model_get_vocab(r->model));
    auto & cur = r->candidates;
    cur.resize((size_t)n);
    for (int i = 0; i < n; ++i) cur[i] = llama_token_data{(llama_token)i, logits[i], 0.0f};
    return {cur.data(), cur.size(), -1, false};
}
static llama_token sample(Runtime * r, int idx) {
    auto cur_p = fill_candidates(r, idx);
    llama_sampler_apply(r->sampler, &cur_p);
    if (cur_p.selected < 0 || cur_p.selected >= (int64_t)cur_p.size) throw std::runtime_error("Sampling selected no token.");
    llama_token token = cur_p.data[cur_p.selected].id;
    if (r->grammar) {
        llama_token_data single = {token, 1.0f, 0.0f};
        llama_token_data_array one = {&single, 1, -1, false};
        llama_sampler_apply(r->grammar, &one);
        if (one.data[0].logit == -INFINITY) {
            cur_p = fill_candidates(r, idx);
            llama_sampler_apply(r->grammar, &cur_p);
            llama_sampler_apply(r->sampler, &cur_p);
            if (cur_p.selected < 0 || cur_p.selected >= (int64_t)cur_p.size) throw std::runtime_error("The grammar allows no token here.");
            token = cur_p.data[cur_p.selected].id;
        }
    }
    llama_sampler_accept(r->sampler, token);
    if (r->grammar) llama_sampler_accept(r->grammar, token);
    return token;
}
// Tokens the bridge puts in the model's mouth (a closed reasoning block).
static void accept_generated(Runtime * r, const std::vector<llama_token> & tokens) {
    for (auto t : tokens) { llama_sampler_accept(r->sampler, t); if (r->grammar) llama_sampler_accept(r->grammar, t); }
}
int32_t od_begin(void * h, const char * request) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    try {
        if (r->released) throw std::runtime_error(released_message);
        if (!r->ctx) throw std::runtime_error("No model loaded.");
        if (r->embedding) throw std::runtime_error("This is an embedding model; it cannot chat.");
        auto req = json::parse(request); auto s = req.at("settings"); auto messages = req.at("messages");
        r->reset(); r->error.clear(); r->trimmed = 0; r->generated = 0; r->first_ms = 0;
        r->held.clear(); r->flush_only = false; r->finish.clear(); r->stops.clear();
        r->tools_active = false; r->generated_text.clear(); r->tool_calls = json::array(); r->tool_format.clear(); r->tool_content.clear();
        r->draft_proposed = r->draft_accepted = r->draft_rounds = 0; r->draft_disabled = false; r->draft_replays = 0;
        r->plain_ms = r->spec_ms = 0; r->plain_steps = r->spec_tokens = 0;
        r->parser = common_chat_parser_params();
        const int n_ctx = (int)llama_n_ctx(r->ctx);
        r->maximum = std::clamp(s.value("maxTokens", 1024), 1, n_ctx - 1);
        // Structured output and tool calling constrain the token stream, so a
        // visible reasoning block cannot precede them: thinking is off then.
        const std::string format = s.value("responseFormat", "text");
        const auto tools = tools_of(req);
        const std::string tool_choice = req.value("toolChoice", "auto");
        const bool constrained = format != "text";
        const bool thinking = s.value("thinkingModeEnabled", false) && !constrained;
        r->think_budget = 0; r->think_tokens = 0; r->reasoning = 0; r->tail.clear();
        // The prompt is placed so the reasoning and the answer both fit; a
        // message too long for that keeps the answer's room only.
        int thinking_room = thinking ? think_room(s, n_ctx) : 0;
        const json original = messages;
        int prompt_count = 0;
        const auto * vocab = llama_model_get_vocab(r->model);
        const std::string fallback = req.value("fallbackTemplate", ""), prefix = req.value("assistantPrefix", "");
        if (s.contains("stopSequences") && s["stopSequences"].is_array())
            for (const auto & st : s["stopSequences"]) if (st.is_string() && !st.get<std::string>().empty()) r->stops.push_back(st.get<std::string>());
        r->drop_chunks(); r->media_tokens = 0;
        std::vector<std::string> images;
        common_chat_params chat_params;
        while (true) {
            auto text = with_prefix(r, render(r, messages, fallback, thinking, true, tools, tool_choice, &chat_params), prefix);
            images = images_of(messages);
            int count = 0;
            if (!images.empty()) {
                r->drop_chunks();
                r->chunks = tokenize_media(r, text, images, count);
                r->prompt.clear();
            } else {
                r->prompt = tokenize(vocab, text);
                if (r->prompt.empty()) throw std::runtime_error("Tokenization failed.");
                count = (int)r->prompt.size();
            }
            if (count + std::min(r->maximum + thinking_room, n_ctx - 1) <= n_ctx) { r->media_tokens = images.empty() ? 0 : count; prompt_count = count; break; }
            // Drop the oldest exchange after the system prompt, but never the
            // current question or anything after it: in a tool round the tail
            // is [user, assistant(tool_calls), tool...] and a chat template
            // refuses a conversation without a user message.
            const size_t head = !messages.empty() && messages[0].value("role", "") == "system" ? 1 : 0;
            size_t last_user = messages.size();
            for (size_t i = messages.size(); i-- > 0;) if (messages[i].value("role", "") == "user") { last_user = i; break; }
            if (last_user == messages.size() || last_user <= head) {
                if (thinking_room > 0) { thinking_room = 0; messages = original; r->trimmed = 0; continue; }
                const bool tools_in_play = std::any_of(messages.begin(), messages.end(), [](const json & m) { return m.value("role", "") == "tool"; });
                throw std::runtime_error(tools_in_play
                    ? "Tool results plus the response budget exceed the context. Raise the context size, lower the per-tool output budget or reduce max tokens."
                    : "Message plus response budget exceeds context. Shorten the message or reduce max tokens.");
            }
            messages.erase(messages.begin() + (long)head); ++r->trimmed;
            while (messages.size() > head + 1 && messages[head].value("role", "") != "user") { messages.erase(messages.begin() + (long)head); ++r->trimmed; }
        }
        // Generation stops at the end of the context whatever the counts say.
        // The reasoning ends at its budget, or where only the answer's room
        // (plus the hand-off) is left: an unlimited budget still leaves the
        // answer its tokens.
        r->total_cap = std::max(1, n_ctx - prompt_count - 1);
        if (thinking) {
            const int left = std::max(1, r->total_cap - r->maximum - 64);
            const int budget = std::max(0, s.value("thinkingBudgetTokens", 0));
            r->think_budget = budget > 0 ? std::min(budget, left) : left;
        }
        if (!images.empty()) {
            reuse_media_prefix(r, s.value("promptCache", true));
            r->media_pending = true;
            if (r->needs_checkpoints) {
                // Same rule as the text path: checkpoint where the next turn's
                // history will still match, measured on the flattened prompt.
                try {
                    int n = 0;
                    auto * hist = tokenize_media(r, render(r, messages, fallback, thinking, false, tools, tool_choice), images, n);
                    std::vector<llama_token> hflat; std::vector<Runtime::MediaMeta> hmeta;
                    flatten_chunks(hist, hflat, hmeta); mtmd_input_chunks_free(hist);
                    const size_t h = media_common_prefix(hflat, hmeta, r->media_flat, r->media_meta_next);
                    if (h > r->media_keep && h < r->media_flat.size()) r->media_checkpoint_at = (long)h;
                } catch (const std::exception &) {}
            }
        } else {
            reuse_prefix(r, s.value("promptCache", true));
        }
        r->checkpoint_at.clear();
        if (r->needs_checkpoints && images.empty()) {
            // Where the next turn will still match this one. Tokenization may
            // merge across a boundary, so only the part that is a prefix of the
            // real prompt counts.
            auto boundary = [&](const json & rendered) {
                try {
                    auto other = tokenize(vocab, render(r, rendered, fallback, thinking, false, tools, tool_choice));
                    int h = 0;
                    const int limit = std::min((int)other.size(), (int)r->prompt.size() - 1);
                    while (h < limit && other[h] == r->prompt[h]) ++h;
                    if (h > r->cursor) r->checkpoint_at.push_back(h);
                } catch (const std::exception &) {}
            };
            // Before this turn's question: the next turn renders it as saved,
            // without the clock line or evidence this request may carry, and
            // a recurrent memory can only resume at a checkpoint. On a chat's
            // first question this is the end of the system prompt and schema.
            json probe = messages;
            for (size_t i = probe.size(); i-- > 0;) {
                if (probe[i].value("role", "") != "user" || !probe[i].contains("content") || !probe[i]["content"].is_string()) continue;
                probe[i]["content"] = "\x01";
                boundary(probe);
                break;
            }
            // After it: the history without the assistant prompt.
            boundary(messages);
            std::sort(r->checkpoint_at.begin(), r->checkpoint_at.end());
            r->checkpoint_at.erase(std::unique(r->checkpoint_at.begin(), r->checkpoint_at.end()), r->checkpoint_at.end());
        }
        r->in_think = r->forced_open;
        // Grammar: the user's structured-output request, else the template's
        // tool-call grammar (lazy: it engages when the model starts a call).
        std::string grammar; bool lazy = false; bool prefill = false;
        std::vector<std::string> patterns; std::vector<llama_token> trigger_tokens;
        if (format == "gbnf") { grammar = s.value("grammar", ""); if (grammar.empty()) throw std::runtime_error("Structured output is set to GBNF but no grammar was given."); }
        else if (format == "json" || format == "json_schema") {
            const std::string schema = format == "json" || s.value("jsonSchema", "").empty() ? "{}" : s.value("jsonSchema", "");
            try { grammar = json_schema_to_grammar(common_json::parse(schema), true); }
            catch (const std::exception & e) { throw std::runtime_error(std::string("The JSON schema could not be turned into a grammar: ") + e.what()); }
        } else if (!tools.empty() && r->templates && !chat_params.grammar.empty()) {
            grammar = chat_params.grammar; lazy = chat_params.grammar_lazy; prefill = true;
            for (const auto & t : chat_params.grammar_triggers) {
                if (t.type == COMMON_GRAMMAR_TRIGGER_TYPE_TOKEN) trigger_tokens.push_back(t.token);
                else if (t.type == COMMON_GRAMMAR_TRIGGER_TYPE_WORD) patterns.push_back(regex_escape(t.value));
                else if (t.type == COMMON_GRAMMAR_TRIGGER_TYPE_PATTERN) patterns.push_back(t.value);
                else if (t.type == COMMON_GRAMMAR_TRIGGER_TYPE_PATTERN_FULL) {
                    std::string p = t.value.empty() ? "^$" : (t.value.front() != '^' ? "^" : "") + t.value + (t.value.back() != '$' ? "$" : "");
                    patterns.push_back(p);
                }
            }
        }
        if (!tools.empty() && r->templates) {
            r->tools_active = true;
            r->parser = common_chat_parser_params(chat_params);
            r->parser.reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK;
            if (!chat_params.parser.empty()) r->parser.parser.load(chat_params.parser);
            r->tool_format = common_chat_format_name(chat_params.format);
            for (const auto & st : chat_params.additional_stops) if (!st.empty()) r->stops.push_back(st);
        }
        build_sampler(r, s, grammar, lazy, patterns, trigger_tokens, chat_params.generation_prompt, prefill);
        // The prompt primes the repetition penalties only. The grammar must
        // not see it: chat templates quote tool-call examples in the system
        // prompt, which would fire a lazy grammar's trigger mid-prompt.
        for (auto token : r->prompt) llama_sampler_accept(r->sampler, token);
        // reuse_prefix set the cursor to the first token that still needs evaluating.
        r->pending = -1; r->done = false; r->started = Clock::now();
        return 0;
    } catch (const std::exception & e) { return fail(r, e); }
}
// Stop-sequence hold-back: the longest suffix of [held] that is a proper
// prefix of some stop sequence stays unsent.
static size_t hold_length(const Runtime * r) {
    size_t best = 0;
    for (const auto & st : r->stops) {
        if (st.empty()) continue;
        for (size_t n = std::min(st.size() - 1, r->held.size()); n > best; --n)
            if (r->held.compare(r->held.size() - n, n, st, 0, n) == 0) { best = n; break; }
    }
    return best;
}
// The answer has its Max tokens, or the context is full.
static bool out_of_room(const Runtime * r) {
    return r->generated - r->reasoning >= r->maximum || r->generated >= r->total_cap;
}
// Text produced this step goes through the reasoning-budget tracker and the
// stop scanner. Returns false when a stop sequence ended the answer.
static bool emit_piece(Runtime * r, const std::string & piece) {
    if (r->think_budget > 0) {
        // Track the reasoning block from the emitted text so the budget only
        // counts thinking; models that open the block themselves included.
        r->tail += piece;
        const std::string start = r->think_start.empty() ? "<think>" : r->think_start;
        if (!r->in_think && r->tail.find(start) != std::string::npos) { r->in_think = true; r->tail.clear(); ++r->reasoning; }
        else if (r->in_think) {
            ++r->think_tokens; ++r->reasoning;
            bool closed = r->think_ends.empty() && r->tail.find("</think>") != std::string::npos;
            for (const auto & end : r->think_ends) closed = closed || r->tail.find(end) != std::string::npos;
            if (closed) { r->in_think = false; r->tail.clear(); }
        }
        if (r->tail.size() > 64) r->tail.erase(0, r->tail.size() - 64);
    }
    // [held] is always a suffix of [generated_text], so a stop found in one
    // is cut from both by the same amount.
    r->held += piece;
    r->generated_text += piece;
    for (const auto & st : r->stops) {
        const size_t at = r->held.find(st);
        if (at != std::string::npos) {
            const size_t cut = r->held.size() - at;
            r->held.erase(at);
            r->generated_text.erase(r->generated_text.size() - cut);
            return false;
        }
    }
    return true;
}
// Moves the sendable part of [held] to the caller's buffer.
static int flush(Runtime * r, uint8_t * output, int32_t capacity, bool all) {
    const size_t keep = all ? 0 : hold_length(r);
    const size_t n = std::min(r->held.size() - keep, (size_t)capacity);
    std::copy(r->held.begin(), r->held.begin() + n, reinterpret_cast<char *>(output));
    r->held.erase(0, n);
    return (int)n;
}
// After the last token: parse tool calls out of the finished text.
static void finish_tools(Runtime * r) {
    if (!r->tools_active) return;
    try {
        auto msg = common_chat_parse(common_chat_input(r->generated_text), false, r->parser);
        r->tool_calls = json::array();
        for (const auto & c : msg.tool_calls) r->tool_calls.push_back({{"id", c.id}, {"name", c.name}, {"arguments", c.arguments}});
        r->tool_content = msg.content;
    } catch (const std::exception &) { r->tool_calls = json::array(); r->tool_content.clear(); }
}
// Decodes [tokens] into the target one batch at a time and records them.
static void decode_into_target(Runtime * r, const std::vector<llama_token> & tokens) {
    for (size_t i = 0; i < tokens.size(); i += (size_t)r->batch) {
        int n = std::min((int)(tokens.size() - i), r->batch);
        if (llama_decode(r->ctx, llama_batch_get_one(const_cast<llama_token *>(tokens.data()) + i, n)) != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
    }
    for (auto t : tokens) r->cached.push_back(t);
    if (r->draft_ctx) for (auto t : tokens) r->draft_queue.push_back(t);
}
// The partial (recurrent / sliding-window) state of sequence 0, or empty
// when the context has none or it is unreasonably large.
static std::vector<uint8_t> partial_state(llama_context * ctx) {
    const size_t size = llama_state_seq_get_size_ext(ctx, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY);
    if (size == 0 || size > (size_t)256 << 20) return {};
    std::vector<uint8_t> data(size);
    if (llama_state_seq_get_data_ext(ctx, data.data(), size, 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) != size) return {};
    return data;
}
// Drops everything from [pos] on: seq_rm when the memory allows it, else the
// [undo] state taken at [pos] is restored first (the attention part of the
// batch is then removed by the same seq_rm, which the recurrent part no
// longer intersects). False when neither works.
static bool drop_tail(llama_context * ctx, int pos, const std::vector<uint8_t> & undo) {
    auto mem = llama_get_memory(ctx);
    if (llama_memory_seq_rm(mem, 0, pos, -1)) return true;
    if (undo.empty()) return false;
    if (llama_state_seq_set_data_ext(ctx, undo.data(), undo.size(), 0, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) return false;
    return llama_memory_seq_rm(mem, 0, pos, -1);
}
// Feeds the draft everything the target has accepted (draft_queue) plus
// [last], then proposes up to [limit] greedy continuations, each decoded into
// the draft as it goes. Afterwards the draft KV holds
// cached ++ [last] ++ proposals. Returns false when the draft failed; it is
// then switched off for the rest of the session.
static bool propose(Runtime * r, llama_token last, int limit, std::vector<llama_token> & out) {
    out.clear();
    auto & q = r->draft_queue; q.push_back(last);
    auto fail_draft = [&] {
        llama_memory_clear(llama_get_memory(r->draft_ctx), true);
        r->draft_cached.clear(); q.clear(); r->draft_max = 0; return false;
    };
    // Where a rejected round rolls the draft back to: the state before this
    // proposal, which a recurrent draft cannot recover with seq_rm alone.
    r->draft_undo_pos = (int)r->draft_cached.size();
    r->draft_undo = r->draft_needs_checkpoints ? partial_state(r->draft_ctx) : std::vector<uint8_t>{};
    for (size_t i = 0; i < q.size(); i += (size_t)r->batch) {
        int n = std::min((int)(q.size() - i), r->batch);
        if (llama_decode(r->draft_ctx, llama_batch_get_one(q.data() + i, n)) != 0) return fail_draft();
    }
    for (auto t : q) r->draft_cached.push_back(t);
    q.clear();
    const auto * vocab = llama_model_get_vocab(r->draft_model);
    for (int i = 0; i < limit; ++i) {
        llama_token t = llama_sampler_sample(r->draft_sampler, r->draft_ctx, -1);
        if (llama_vocab_is_eog(vocab, t)) break;
        if (llama_decode(r->draft_ctx, llama_batch_get_one(&t, 1)) != 0) return fail_draft();
        out.push_back(t); r->draft_cached.push_back(t);
    }
    return true;
}
int32_t od_step(void * h, uint8_t * output, int32_t capacity, int32_t * length) {
    auto * r = static_cast<Runtime *>(h); *length = 0;
    std::lock_guard<std::mutex> use(r->use);
    try {
        if (r->released) throw std::runtime_error(released_message);
        if (r->flush_only) {
            // The answer ended with text still held back for a possible stop
            // sequence: send it, then report the end.
            *length = flush(r, output, capacity, true);
            if (r->held.empty()) { r->flush_only = false; r->done = true; }
            return *length > 0 ? 1 : 2;
        }
        if (r->done) return 2;
        const auto * vocab = llama_model_get_vocab(r->model);
        if (r->media_pending) {
            try { eval_media(r); } catch (...) { r->drop_chunks(); throw; }
            return 0;
        }
        if (r->cursor < (int)r->prompt.size()) {
            int n = std::min(r->batch, (int)r->prompt.size() - r->cursor);
            for (const int at : r->checkpoint_at) if (at > r->cursor && at < r->cursor + n) { n = at - r->cursor; break; }
            auto batch = llama_batch_get_one(r->prompt.data() + r->cursor, n);
            if (llama_decode(r->ctx, batch) != 0) { r->forget(); throw std::runtime_error("Prompt evaluation failed. Try a smaller context/model."); }
            r->cursor += n;
            r->cached.assign(r->prompt.begin(), r->prompt.begin() + r->cursor);
            while (!r->checkpoint_at.empty() && r->checkpoint_at.front() <= r->cursor) {
                if (r->checkpoint_at.front() == r->cursor) take_checkpoint(r, r->cursor);
                r->checkpoint_at.erase(r->checkpoint_at.begin());
            }
            return 0;
        }
        auto end = [&](const char * why) {
            r->finish = why; finish_tools(r);
            if (r->held.empty()) { r->done = true; return 2; }
            r->flush_only = true; *length = flush(r, output, capacity, true);
            if (r->held.empty()) { r->flush_only = false; r->done = true; }
            return 1;
        };
        if (out_of_room(r)) return end("length");
        if (r->in_think && r->think_budget > 0 && r->think_tokens >= r->think_budget) {
            // Budget spent: close the reasoning block on the model's behalf, let
            // it see the closing tokens, then sample the answer.
            if (r->pending >= 0) { decode_into_target(r, {(llama_token)r->pending}); r->pending = -1; }
            // A bare close tag left small models reasoning on in the answer
            // ("Wait, I need to check…" in every Qwen3.5 0.8B goal step on
            // the phone, 2026-09-24). Qwen's recommended hand-off sentence
            // before the tag makes them answer.
            std::string close = "\n\nConsidering the limited time by the user, I have to give the solution based on the thinking directly now.\n"
                + (r->think_ends.empty() ? std::string("</think>") : r->think_ends.front()) + "\n\n";
            auto tokens = tokenize(vocab, close);
            if (tokens.empty()) throw std::runtime_error("Cannot close the reasoning block.");
            decode_into_target(r, tokens);
            accept_generated(r, tokens);
            r->generated += (int)tokens.size(); r->reasoning += (int)tokens.size(); r->in_think = false; r->tail.clear();
            r->held += close; r->generated_text += close;
            *length = flush(r, output, capacity, false);
            r->last = Clock::now();
            return 1;
        }
        std::vector<llama_token> accepted;   // tokens sampled this step, in order
        bool eog = false;
        // Room for [pending] + drafts + the bonus token, within context and cap.
        const int room = std::min({(int)llama_n_ctx(r->ctx) - (int)r->cached.size() - 2,
            r->maximum - (r->generated - r->reasoning) - 1, r->total_cap - r->generated - 1});
        std::vector<llama_token> drafts;
        const auto step_started = Clock::now();
        if (r->draft_ctx && r->draft_max > 0 && !r->draft_disabled && r->plain_steps >= Runtime::draft_warm
            && r->pending >= 0 && room > 0 && !r->media_tokens
            && propose(r, (llama_token)r->pending, std::min(r->draft_max, room), drafts)) {
            // Speculative round: the target verifies [pending, d0, d1, ...] in
            // one decode and every draft token it would have sampled itself is
            // kept; the first disagreement replaces the draft and ends the round.
            // Invariant before and after: draft KV == cached ++ draft_queue.
            const llama_token last = (llama_token)r->pending;
            const int n = 1 + (int)drafts.size();
            const int base = (int)r->cached.size();
            const auto undo = r->needs_checkpoints ? partial_state(r->ctx) : std::vector<uint8_t>{};
            llama_batch batch = llama_batch_init(n, 0, 1);
            for (int i = 0; i < n; ++i) {
                batch.token[i] = i == 0 ? last : drafts[i - 1]; batch.pos[i] = (llama_pos)(base + i);
                batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0; batch.logits[i] = true;
            }
            batch.n_tokens = n;
            const int rc = llama_decode(r->ctx, batch);
            llama_batch_free(batch);
            if (rc != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
            ++r->draft_rounds; r->draft_proposed += (long)drafts.size();
            int matched = 0;
            llama_token next = LLAMA_TOKEN_NULL;
            for (int i = 0; i <= (int)drafts.size(); ++i) {
                next = sample(r, i);
                accepted.push_back(next);
                if (llama_vocab_is_eog(vocab, next)) { eog = true; break; }
                if (i == (int)drafts.size() || next != drafts[i]) break;
                ++matched; ++r->draft_accepted;
            }
            // Target keeps [last] + the matched drafts; both caches drop the rest.
            r->cached.push_back(last);
            for (int k = 0; k < matched; ++k) r->cached.push_back(drafts[k]);
            if (matched < (int)drafts.size()) {
                const int keep = (int)r->cached.size();
                if (!llama_memory_seq_rm(llama_get_memory(r->ctx), 0, (llama_pos)keep, -1)) {
                    // Recurrent state: back to before the batch, then replay
                    // the kept tokens so the state matches `cached` again.
                    if (!drop_tail(r->ctx, base, undo)) { r->forget(); throw std::runtime_error("Speculative decoding could not roll back a rejected draft on this model's memory."); }
                    const int m = keep - base;
                    llama_batch replay = llama_batch_init(m, 0, 1);
                    for (int i = 0; i < m; ++i) {
                        replay.token[i] = r->cached[(size_t)base + i]; replay.pos[i] = (llama_pos)(base + i);
                        replay.n_seq_id[i] = 1; replay.seq_id[i][0] = 0; replay.logits[i] = false;
                    }
                    replay.n_tokens = m;
                    const int rrc = llama_decode(r->ctx, replay);
                    llama_batch_free(replay);
                    if (rrc != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
                    ++r->draft_replays;
                }
                // The draft rolls back to its pre-proposal state and re-reads
                // the kept tokens through its queue on the next round.
                if (!llama_memory_seq_rm(llama_get_memory(r->draft_ctx), 0, (llama_pos)keep, -1)) {
                    if (!drop_tail(r->draft_ctx, r->draft_undo_pos, r->draft_undo)) {
                        llama_memory_clear(llama_get_memory(r->draft_ctx), true); r->draft_undo_pos = 0;
                    }
                    r->draft_cached.resize((size_t)r->draft_undo_pos);
                    r->draft_queue.assign(r->cached.begin() + r->draft_undo_pos, r->cached.end());
                } else {
                    r->draft_cached.resize((size_t)keep);
                }
            }
            r->pending = eog ? -1 : next;
            r->spec_ms += std::chrono::duration<double, std::milli>(Clock::now() - step_started).count();
            r->spec_tokens += (long)accepted.size();
            if (r->draft_rounds >= Runtime::draft_probe) {
                const bool missing = r->draft_proposed > 0 && (double)r->draft_accepted / (double)r->draft_proposed < Runtime::draft_floor;
                const bool slower = r->plain_ms > 0 && r->spec_ms > 0
                    && (double)r->spec_tokens / r->spec_ms < (double)r->plain_steps / r->plain_ms;
                if (missing || slower) r->draft_disabled = true;
            }
        } else {
            if (r->pending >= 0) {
                auto token = (llama_token)r->pending;
                auto batch = llama_batch_get_one(&token, 1);
                if (llama_decode(r->ctx, batch) != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
                r->cached.push_back(token); r->pending = -1;
                if (r->draft_ctx) r->draft_queue.push_back(token);
                // A plain step: decode + sample of one token, the yardstick
                // speculative rounds are measured against.
                if (r->draft_ctx) { r->plain_ms += std::chrono::duration<double, std::milli>(Clock::now() - step_started).count(); ++r->plain_steps; }
            }
            auto token = sample(r, -1);
            accepted.push_back(token);
            if (llama_vocab_is_eog(vocab, token)) eog = true; else r->pending = token;
        }
        // Text for every sampled token, in order; a stop sequence or the
        // token cap can end the answer in the middle of a speculative round.
        std::string piece; piece.resize(512);
        bool stopped = false;
        for (auto token : accepted) {
            if (llama_vocab_is_eog(vocab, token)) break;
            int n = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, true);
            if (n < 0) { piece.resize((size_t)-n); n = llama_token_to_piece(vocab, token, piece.data(), (int)piece.size(), 0, true); }
            ++r->generated;
            if (r->generated == 1) { r->first = Clock::now(); r->first_ms = std::chrono::duration<double, std::milli>(r->first - r->started).count(); }
            if (!emit_piece(r, std::string(piece.data(), (size_t)std::max(n, 0)))) { stopped = true; break; }
            if (out_of_room(r)) break;
        }
        r->last = Clock::now();
        if (stopped) { r->pending = -1; return end("stop"); }
        if (eog) { r->pending = -1; return end("eog"); }
        *length = flush(r, output, capacity, false);
        return 1;
    } catch (const std::exception & e) { return fail(r, e); }
}
