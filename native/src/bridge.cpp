#include "memory_admission.h"
#include "bridge.h"
#include "load_policy.h"
#include "prompt_store.h"
#include "llama.h"
#include "ggml-backend.h"
#include "gguf.h"
#include "chat.h"
#include "common.h"
#include "speculative.h"
#include "fit.h"
#include "json-schema-to-grammar.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <map>
#include <set>
#include "nlohmann/json.hpp"
#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <condition_variable>
#include <fstream>
#include <mutex>
#include <atomic>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#ifdef ODLLM_CUDA_PTX
#include <cuda_runtime_api.h>
#endif
#else
#include <sys/resource.h>
#endif
#if defined(__ANDROID__)
#include <android/log.h>
#include <jni.h>
#endif
using json = nlohmann::ordered_json;
using Clock = std::chrono::steady_clock;
// Inputs one embedding decode may carry as distinct sequences (audit E22);
// the embedding context reserves exactly this many sequences.
static constexpr int kEmbedBatchSeqs = 8;
static std::atomic<int64_t> next_session{1};
static std::mutex cancellation_mutex;
static std::map<int64_t, std::shared_ptr<std::atomic<bool>>> cancellations;
static std::map<int64_t, std::shared_ptr<std::atomic<float>>> load_progress;
static bool cancelled_callback(void * data) {
    return static_cast<std::atomic<bool> *>(data)->load(std::memory_order_relaxed);
}
static bool loading_callback(float, void * data) { return !cancelled_callback(data); }
struct LoadingProgress {
    std::atomic<bool> * cancelled;
    std::atomic<float> * progress;
};
static bool weight_loading_callback(float progress, void * data) {
    auto * loading = static_cast<LoadingProgress *>(data);
    loading->progress->store(std::clamp(progress, 0.0f, 1.0f) * 0.85f, std::memory_order_relaxed);
    return !cancelled_callback(loading->cancelled);
}
struct Runtime;
struct SideBatch;
static void close_side_batches(Runtime * r);
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
    const std::shared_ptr<std::atomic<float>> progress = std::make_shared<std::atomic<float>>(-1.0f);
    // The window (Android activity) that created this runtime; 0 = none.
    const int64_t owner;
    // Held by every call that reads or changes the model, because a release
    // arrives from another thread. `released` refuses work afterwards.
    std::mutex use;
    bool released = false;
    // od_estimate's scratch runtime: memory short of the need is reported
    // (ramNeedMb over ramAvailableMb), not refused, so callers can weigh it.
    bool planning = false;
    const bool tracked;
    explicit Runtime(int64_t owner_id, bool track = true) : owner(owner_id), tracked(track) {
        if (!tracked) return;
        { std::lock_guard<std::mutex> lock(cancellation_mutex); cancellations.emplace(session, cancelled); load_progress.emplace(session, progress); }
        std::lock_guard<std::mutex> lock(registry_mutex);
        registry.insert(this);
    }
    std::vector<std::weak_ptr<SideBatch>> sides;
    std::string model_path;
    llama_model * model = nullptr;
    llama_context * ctx = nullptr;
    llama_sampler * sampler = nullptr;
    // The GPU runs the whole chain and hands back only the token (opt-in).
    bool sampler_offloadable = false, backend_sampled = false;
    // Grammar (structured output or the template's tool-call grammar) is kept
    // out of the chain: the chain sees the prompt for repetition penalties,
    // the grammar must only see what the model generates.
    llama_sampler * grammar = nullptr;
    std::vector<llama_token_data> candidates;   // reused per sampled token
    // Jinja templates from the GGUF. Null when the model ships no template and
    // we must fall back to a family template through the legacy C API.
    common_chat_templates_ptr templates;
    bool supports_thinking = false, forced_open = false, supports_tools = false;
    std::string template_error, template_probe_error;
    std::string think_start, error, info, preview, fallback_reason, backend = "CPU", adapter_info;
    json effective = json::object();
    std::vector<std::string> think_ends;
    std::vector<llama_token> prompt;
    std::vector<ggml_backend_dev_t> devices;
    // Buffers common_fit_params writes and the model params point into.
    std::vector<float> split;
    std::vector<llama_model_tensor_buft_override> overrides;
    std::vector<llama_model_kv_override> kv_overrides;
    std::string estimate;
    int batch = 256, cursor = 0, generated = 0, maximum = 0, trimmed = 0, pending = -1;
    bool done = true;
    double first_ms = 0;
    // Where the first token's time went (od_info): od_begin itself (prompt
    // formatting, tokenizing, cache reuse), prompt and photo decodes, and
    // the sliding-window checkpoints copied during them (part of prefill).
    double begin_ms = 0, prefill_ms = 0, checkpoint_ms = 0, sample_ms = 0, sample_cpu_ms = 0;
    long sample_cpu_tokens = 0;
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
    // Prompt store (llama-server's --cache-ram): text sequences this context
    // held before another prompt replaced them, with their full state, so a
    // chat or client that comes back after a title, memory or other
    // request resumes instead of prefilling again. Least recently used
    // goes first past `store_limit` bytes (settings.promptStoreMb). An entry
    // is charged before it is allocated and evicted before its state is
    // copied, so the cap bounds peak memory too; a snapshot larger than the
    // cap is never cached.
    // Recurrent/hybrid memories keep their rollback checkpoints with them.
    struct Stored {
        std::vector<llama_token> tokens; std::vector<uint8_t> state, head; std::vector<Checkpoint> marks; uint64_t used;
        size_t bytes() const {
            size_t marks_bytes = 0;
            for (const auto & m : marks) marks_bytes += m.data.size();
            return od_prompt_store::entry_bytes(state.size(), head.size(), marks_bytes, tokens.size());
        }
    };
    std::vector<Stored> store;
    size_t store_limit = 0; uint64_t store_clock = 0;
    int store_restored = 0;   // tokens this turn took from the store
    static constexpr size_t store_min = 128, store_gain = 32;
    bool needs_checkpoints = false;
    int n_swa = 0;
    bool swa_full = false;
    std::string context_overflow = "trim";
    int keep_tokens = 0;
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
    // Metrics (od_info): the rendered prompt in KV positions (text is one
    // position per token, a media chunk takes n_pos positions while it
    // contributes n_tokens placeholders to the flat prompt), the positions
    // its images occupy, and the positions context shift discarded. Photo
    // turns clear `prompt`, so promptTokens cannot come from it (audit E26).
    int prompt_positions = 0, media_positions = 0, shifted_positions = 0;
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
    // Every templated turn uses the syntax returned with its prompt.
    common_chat_parser_params parser;
    bool tools_active = false, parser_active = false, parser_finished = false, output_thinking = false;
    common_chat_input generated_input;
    common_chat_msg parsed_msg;
    std::string parsed_output, parse_error;
    size_t parsed_raw_length = 0, streamed_raw_length = 0;
    Clock::time_point parsed_at{};
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
    // What the chat context was loaded with: helper batches share its weights,
    // so they take the same RoPE/YaRN, cache and attention parameters and the
    // same adapters (audit E06).
    llama_context_params context_params{};
    std::vector<float> adapter_scales;
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
    // An MTP head verifies almost for free, so it pays at acceptance far
    // below the floor (LM Studio: 97 tok/s on Gemma 4 E4B at 31%): it is
    // judged on speed alone, over more rounds, after mtp_settle rounds that
    // are not timed (the first verify batches pay one-time setup; counting
    // them switched MTP off at temperature 0.7, where it gives 77-81 tok/s
    // against 61 plain on the 3070, 2026-10-28), and only when clearly
    // slower (mtp_margin). After draft_give_up turns in a row lose, the load
    // stops trying: Qwen3.6 35B A3B with experts in RAM verifies on the CPU
    // and decoded 13-17 tok/s with MTP against 24 plain, the probe included
    // (3070, 4 threads, 2026-10-29).
    bool draft_disabled = false;
    int draft_losses = 0;
    static constexpr int draft_give_up = 2;
    static constexpr long draft_probe = 4, mtp_probe = 24, mtp_settle = 4;
    static constexpr double mtp_margin = 0.9;
    static constexpr double draft_floor = 0.35;
    static constexpr long draft_warm = 3;
    double plain_ms = 0, spec_ms = 0, draft_ms = 0; long plain_steps = 0, spec_tokens = 0;
    std::string draft_name;
    float draft_p_min = 0;   // Stop drafting below this confidence
    llama_context * mtp_ctx = nullptr;
    // MTP and DFlash share the common driver's capture/verify lifecycle.
    common_speculative_ptr mtp;
    bool dflash = false;
    int64_t dflash_features = 0;
    int dflash_max = 0, dflash_block = 0;
    void reset() { if (backend_sampled && ctx) llama_set_sampler(ctx, 0, nullptr); backend_sampled = false; if (sampler) llama_sampler_free(sampler); if (grammar) llama_sampler_free(grammar); sampler = nullptr; grammar = nullptr; }
    void forget() { cached.clear(); media_meta.clear(); checkpoints.clear(); checkpoint_at.clear(); reused = 0; draft_cached.clear(); draft_queue.clear(); }
    void drop_chunks() { if (chunks) mtmd_input_chunks_free(chunks); chunks = nullptr; media_pending = false; }
    void unload() {
        close_side_batches(this);
        progress->store(-1.0f, std::memory_order_relaxed);
        reset(); forget(); drop_chunks(); store.clear(); store_restored = 0;
        for (auto & b : bitmaps) mtmd_bitmap_free(b.second);
        bitmaps.clear();
        if (mctx) mtmd_free(mctx);
        mctx = nullptr; vision_error.clear(); media_tokens = 0;
        prompt_positions = media_positions = shifted_positions = 0;
        templates.reset(); template_error.clear(); template_probe_error.clear();
        mtp.reset();
        if (mtp_ctx) llama_free(mtp_ctx);
        mtp_ctx = nullptr; dflash = false; dflash_features = 0; dflash_max = dflash_block = 0;
        if (draft_sampler) llama_sampler_free(draft_sampler);
        if (draft_ctx) llama_free(draft_ctx);
        if (draft_model) llama_model_free(draft_model);
        draft_sampler = nullptr; draft_ctx = nullptr; draft_model = nullptr; draft_max = 0; draft_name.clear();
        draft_proposed = draft_accepted = draft_rounds = 0; draft_disabled = false; draft_losses = 0;
        draft_needs_checkpoints = false; draft_undo.clear(); draft_undo_pos = -1; draft_replays = 0;
        plain_ms = spec_ms = draft_ms = 0; plain_steps = spec_tokens = 0;
        // Adapters belong to the model and are released with it.
        adapters.clear(); adapter_report = json::array();
        adapter_scales.clear(); context_params = llama_context_default_params();
        if (ctx) llama_free(ctx);
        if (model) llama_model_free(model);
        ctx = nullptr; model = nullptr; done = true; effective = json::object();
        supports_thinking = false; forced_open = false; supports_tools = false; think_start.clear(); think_ends.clear();
        needs_checkpoints = false; n_swa = 0; swa_full = false; embedding = false;
        stops.clear(); held.clear(); flush_only = false; finish.clear();
        parser_active = false; parser_finished = false; output_thinking = false;
        generated_input = {}; parsed_msg = {}; parsed_output.clear(); parse_error.clear();
        parsed_raw_length = streamed_raw_length = 0;
        tools_active = false; generated_text.clear(); tool_calls = json::array(); tool_format.clear(); tool_content.clear();
    }
    ~Runtime() {
        if (!tracked) { unload(); return; }
        { std::lock_guard<std::mutex> lock(cancellation_mutex); cancellations.erase(session); load_progress.erase(session); }
        // Waits for a release in progress; afterwards nobody else can reach this runtime.
        { std::lock_guard<std::mutex> lock(registry_mutex); registry.erase(this); }
        unload();
    }
};
static void reset_mtp(Runtime * r) {
    r->mtp.reset();
    if (!r->ctx || !r->model || !r->mtp_ctx) throw std::runtime_error("The MTP target or head context is missing.");
    llama_memory_clear(llama_get_memory(r->mtp_ctx), true);
    common_params_speculative spec;
    spec.types = {r->dflash ? COMMON_SPECULATIVE_TYPE_DRAFT_DFLASH : COMMON_SPECULATIVE_TYPE_DRAFT_MTP};
    spec.draft.ctx_tgt = r->ctx;
    spec.draft.ctx_dft = r->mtp_ctx;
    spec.draft.n_max = r->draft_max;
    spec.draft.p_min = r->draft_p_min;
    // DFlash consumes multiple output rows. Keep sampling on the host so
    // the common driver can inspect each row without backend sampler state.
    spec.draft.backend_sampling = !r->dflash;
    r->mtp.reset(common_speculative_init(spec, 1));
    if (!r->mtp) throw std::runtime_error(r->dflash ? "OD_DFLASH_METADATA" : "The MTP draft driver could not be initialized.");
}
// The common driver owns hidden-state capture; no staging llama-ext API here.
static int decode_target(Runtime * r, llama_batch batch) {
    if (!r->mtp || r->media_tokens) return llama_decode(r->ctx, batch);
    const int chunk = r->dflash ? (int)llama_n_ubatch(r->ctx) : batch.n_tokens;
    const auto base = llama_memory_seq_pos_max(llama_get_memory(r->ctx), 0) + 1;
    for (int offset = 0; offset < batch.n_tokens; offset += chunk) {
        const int n = std::min(chunk, batch.n_tokens - offset);
        common_batch mirror(r->ctx);
        for (int i = offset; i < offset + n; ++i)
            mirror.add(batch.token[i], batch.pos ? batch.pos[i] : base + i, 0, batch.logits ? batch.logits[i] : i == batch.n_tokens - 1);
        auto part = batch;
        part.n_tokens = n; part.token += offset;
        if (part.pos) part.pos += offset;
        if (part.n_seq_id) part.n_seq_id += offset;
        if (part.seq_id) part.seq_id += offset;
        if (part.logits) part.logits += offset;
        const int rc = llama_decode(r->ctx, part);
        if (rc != 0) return rc;
        if (!common_speculative_process(r->mtp.get(), mirror)) return -1;
    }
    return 0;
}
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
// The last error on this thread, so a failed load can say why (an unknown
// architecture, a truncated file) instead of guessing.
static thread_local std::string last_native_error;
static void native_log(enum ggml_log_level level, const char * text, void *) {
    if (level != GGML_LOG_LEVEL_WARN && level != GGML_LOG_LEVEL_ERROR) return;
    if (level == GGML_LOG_LEVEL_ERROR && text) {
        std::string line = text;
        while (!line.empty() && (line.back() == '\n' || line.back() == ' ')) line.pop_back();
        // llama.cpp says why once ("error loading model: ..."), then only
        // that it failed.
        const auto at = line.find("error loading model");
        if (at != std::string::npos) last_native_error = line.substr(at);
    }
#if defined(__ANDROID__)
    __android_log_write(level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR : ANDROID_LOG_WARN, "ondevice_llm", text);
#else
    fputs(text, stderr);
#endif
}
static int fail(Runtime * r, const std::exception & e) { r->error = e.what(); r->done = true; r->finish = "error"; return -1; }
static double peak_rss_mb() {
#if defined(_WIN32)
    PROCESS_MEMORY_COUNTERS pmc{};
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof pmc)) return 0;
    return pmc.PeakWorkingSetSize / 1048576.0;
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
#ifdef ODLLM_CUDA_PTX
// A cubin for sm_XY runs on the same major version with minor >= Y; PTX
// for compute_V is JIT-compiled for any later GPU.
static bool cuda_arch_supported(int cc) {
    const int real[] = {ODLLM_CUDA_REAL};
    for (int r : real) if (r / 10 == cc / 10 && r <= cc) return true;
    return ODLLM_CUDA_PTX > 0 && cc >= ODLLM_CUDA_PTX;
}

static int32_t cuda_supported_devices() {
    int n = 0, count = 0;
    if (cudaGetDeviceCount(&n) != cudaSuccess) return 0;
    for (int i = 0; i < n; ++i) {
        int major = 0, minor = 0;
        if (cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, i) != cudaSuccess ||
            cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, i) != cudaSuccess) continue;
        if (cuda_arch_supported(major * 10 + minor)) ++count;
    }
    return count;
}

// What NVML (shipped with the driver; it does not start CUDA) says about the
// GPUs before anything starts CUDA. The driver reads CUDA_VISIBLE_DEVICES
// once per process, so the CUDA 13 bridge must not start CUDA or hide GPUs
// when it cannot use any of them: the CUDA 12 bridge, opened next in the same
// process, needs the driver untouched.
struct CudaPlan { bool known = false; int usable = 0; bool hidden = false; std::string visible; };

static const CudaPlan & cuda_plan() {
    static const CudaPlan plan = [] {
        CudaPlan p;
        HMODULE nvml = LoadLibraryExA("nvml.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!nvml) return p;
        using nvml_init_t = int (*)();
        using nvml_int_t = int (*)(int *);
        using nvml_count_t = int (*)(unsigned *);
        using nvml_handle_t = int (*)(unsigned, void **);
        using nvml_cc_t = int (*)(void *, int *, int *);
        using nvml_uuid_t = int (*)(void *, char *, unsigned);
        auto init = (nvml_init_t)GetProcAddress(nvml, "nvmlInit_v2");
        auto shutdown = (nvml_init_t)GetProcAddress(nvml, "nvmlShutdown");
        auto driver = (nvml_int_t)GetProcAddress(nvml, "nvmlSystemGetCudaDriverVersion_v2");
        auto count = (nvml_count_t)GetProcAddress(nvml, "nvmlDeviceGetCount_v2");
        auto handle = (nvml_handle_t)GetProcAddress(nvml, "nvmlDeviceGetHandleByIndex_v2");
        auto cc = (nvml_cc_t)GetProcAddress(nvml, "nvmlDeviceGetCudaComputeCapability");
        auto uuid = (nvml_uuid_t)GetProcAddress(nvml, "nvmlDeviceGetUUID");
        if (init && shutdown && driver && count && handle && cc && uuid && init() == 0) {
            unsigned n = 0;
            int version = 0;
            bool complete = driver(&version) == 0 && count(&n) == 0;
            // Minor version compatibility: any driver of the runtime's major
            // version runs it.
            const bool driver_ok = version / 1000 >= CUDART_VERSION / 1000;
            for (unsigned i = 0; complete && i < n; ++i) {
                void * dev = nullptr;
                int major = 0, minor = 0;
                char id[96] = {};
                if (handle(i, &dev) || cc(dev, &major, &minor) || uuid(dev, id, sizeof id)) { complete = false; break; }
                if (driver_ok && cuda_arch_supported(major * 10 + minor)) {
                    ++p.usable;
                    p.visible += (p.visible.empty() ? "" : ",") + std::string(id);
                } else p.hidden = true;
            }
            shutdown();
            p.known = complete;
        }
        FreeLibrary(nvml);
        return p;
    }();
    return plan;
}

// Hides GPUs this build has no kernels for (a Pascal card next to an RTX card
// with the CUDA 13 bridge) so llama.cpp and mtmd never place work there. Only
// when some GPU stays usable; a user's own CUDA_VISIBLE_DEVICES wins.
static void cuda_hide_unsupported() {
    const auto & p = cuda_plan();
    if (p.known && p.hidden && p.usable > 0 && !std::getenv("CUDA_VISIBLE_DEVICES"))
        _putenv_s("CUDA_VISIBLE_DEVICES", p.visible.c_str());
}
#endif

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
#ifdef ODLLM_CUDA_PTX
            cuda_hide_unsupported();
#endif
            llama_log_set(native_log, nullptr); llama_backend_init(); ggml_backend_load_all();
            // A GPU backend with no usable device (old driver, no GPU) would
            // keep its DLL and driver/cuBLAS state loaded for nothing (P3-06).
            for (size_t i = ggml_backend_reg_count(); i-- > 0;) {
                ggml_backend_reg_t reg = ggml_backend_reg_get(i);
                if (ggml_backend_reg_dev_count(reg) == 0) ggml_backend_unload(reg);
            }
        });
        const auto owner = opts.contains("owner") && opts["owner"].is_number_integer() ? opts["owner"].get<int64_t>() : 0;
        return new Runtime(owner);
    } catch (...) { return nullptr; }
}

int32_t od_gpu_device_count() {
    try {
#ifdef ODLLM_CUDA_PTX
        // No GPU this bridge can run on: answer without starting CUDA. A
        // CUDA_VISIBLE_DEVICES subset cannot add a GPU the plan ruled out.
        if (cuda_plan().known && cuda_plan().usable == 0) return 0;
#endif
        // Reuse the normal one-time initialization and exception boundary.
        // Its empty options skip the OpenCL kernel cache folder (P3-07):
        // only the Windows loader calls this, where OpenCL is not built and
        // TMPDIR exists; Android always reaches od_create with its options.
        void * h = od_create(nullptr);
        if (!h) return 0;
        od_destroy(h);
        int32_t count = 0;
        for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
            const auto type = ggml_backend_dev_type(ggml_backend_dev_get(i));
            if (type == GGML_BACKEND_DEVICE_TYPE_GPU || type == GGML_BACKEND_DEVICE_TYPE_IGPU) ++count;
        }
#ifdef ODLLM_CUDA_PTX
        // ggml lists every CUDA GPU, including ones without kernels here.
        count = std::min(count, cuda_supported_devices());
#endif
        return count;
    } catch (...) { return 0; }
}
int32_t od_cpu_cores() {
    // llama.cpp's own default: physical cores (performance cores on hybrid
    // Linux CPUs). On SMT desktops the second thread per core only slows
    // the matrix work down.
    try { return std::max<int32_t>(1, common_cpu_get_num_math()); } catch (...) { return 1; }
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
float od_load_progress(int64_t session) {
    std::lock_guard<std::mutex> lock(cancellation_mutex);
    auto found = load_progress.find(session);
    return found == load_progress.end() ? -1.0f : found->second->load(std::memory_order_relaxed);
}
void od_reset_cancel(void * h) { static_cast<Runtime *>(h)->cancelled->store(false, std::memory_order_relaxed); }
int32_t od_cancelled(void * h) { return static_cast<Runtime *>(h)->cancelled->load(std::memory_order_relaxed); }
const char * od_error(void * h) { return static_cast<Runtime *>(h)->error.c_str(); }
// b12342: CPU has generic FP8 conversion/dot/FA kernels; CUDA has FA
// instances. Other backend families must opt in only after gaining kernels.
static bool supports_fp8_kv(ggml_backend_dev_t dev) {
    const std::string name = ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev));
    if (name != "CPU" && name != "CUDA") return false;
    // Ask the loaded backend too: CUDA builds may disable FA/type instances.
    auto * ctx = ggml_init({ggml_tensor_overhead() * 8, nullptr, true});
    if (!ctx) return false;
    auto * q = ggml_new_tensor_4d(ctx, GGML_TYPE_F32, 128, 1, 1, 1);
    auto * k = ggml_new_tensor_4d(ctx, GGML_TYPE_F8_E4M3, 128, 256, 1, 1);
    auto * v = ggml_new_tensor_4d(ctx, GGML_TYPE_F8_E4M3, 128, 256, 1, 1);
    auto * fa = ggml_flash_attn_ext(ctx, q, k, v, nullptr, 1.0f, 0.0f, 0.0f);
    const bool supported = ggml_backend_dev_supports_op(dev, fa);
    ggml_free(ctx);
    return supported;
}
const char * od_info(void * h) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    double seconds = r->generated > 1 ? std::chrono::duration<double>(r->last - r->first).count() : 0;
    json devices = json::array();
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto dev = ggml_backend_dev_get(i);
        const auto type = ggml_backend_dev_type(dev);
        devices.push_back({{"backend", ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev))},
            {"supportsFp8Kv", supports_fp8_kv(dev)},
            {"description", ggml_backend_dev_description(dev)},
            {"gpu", type == GGML_BACKEND_DEVICE_TYPE_GPU || type == GGML_BACKEND_DEVICE_TYPE_IGPU}});
    }
    r->info = json{{"abiVersion", 7}, {"supportsDFlash", true},
        {"supportsFp8Kv", r->effective.value("supportsFp8Kv", false)}, {"devices", devices}, {"kernelCacheDir", kernel_cache_dir},
        {"effectiveSettings", r->effective}, {"fallbackReason", r->fallback_reason},
        {"backend", r->backend}, {"tokens", r->generated}, {"promptTokens", r->prompt_positions},
        {"firstTokenMs", r->first_ms}, {"tokensPerSecond", seconds > 0 ? (r->generated - 1) / seconds : 0},
        {"beginMs", r->begin_ms}, {"prefillMs", r->prefill_ms}, {"checkpointMs", r->checkpoint_ms}, {"sampleMs", r->sample_ms},
        {"sampleCpuMs", r->sample_cpu_ms}, {"sampleCpuTokens", r->sample_cpu_tokens},
        {"firstTokenFromBeginMs", r->generated > 0 ? r->begin_ms + r->first_ms : 0},
        {"trimmedMessages", r->trimmed}, {"contextSize", r->ctx ? llama_n_ctx(r->ctx) : 0},
        {"contextTrain", r->model ? llama_model_n_ctx_train(r->model) : 0},
        {"cachedPromptTokens", r->reused}, {"storedPromptTokens", r->store_restored},
        {"storedPrompts", r->store.size()}, {"backendSampling", r->backend_sampled}, {"thinkingTokens", r->think_tokens},
        {"contextUsed", r->prompt_positions + r->generated - r->shifted_positions}, {"peakRssMb", peak_rss_mb()},
        {"supportsVision", r->mctx && mtmd_support_vision(r->mctx)}, {"visionError", r->vision_error},
        {"mediaMarker", mtmd_default_marker()}, {"mediaTokens", r->media_tokens},
        {"mediaPositions", r->media_positions}, {"shiftedTokens", r->shifted_positions},
        {"released", r->released},
        {"supportsThinking", r->supports_thinking}, {"thinkingForcedOpen", r->forced_open && !r->parser_active},
        {"thinkingStartTag", r->parser_active ? std::string("<think>") : r->think_start},
        {"thinkingEndTags", r->parser_active ? std::vector<std::string>{"</think>"} : r->think_ends},
        {"templateError", r->template_error}, {"templateProbeError", r->template_probe_error}, {"parseError", r->parse_error},
        {"embeddedChatTemplate", r->model && llama_model_chat_template(r->model, nullptr) ? llama_model_chat_template(r->model, nullptr) : ""},
        {"hasTemplate", (bool)r->templates}, {"embedding", r->embedding},
        {"embeddingDim", r->model ? llama_model_n_embd_out(r->model) : 0},
        // A reranker (pooling RANK): od_embed scores request.pairs.
        {"ranks", r->ctx && llama_pooling_type(r->ctx) == LLAMA_POOLING_TYPE_RANK},
        // ABI 7: media embeddings (EmbeddingGemma 2 projector) and audio input.
        {"supportsAudio", r->mctx && mtmd_support_audio(r->mctx)},
        // ABI 6
        {"finishReason", r->finish}, {"supportsTools", r->supports_tools}, {"toolFormat", r->tool_format},
        {"toolCalls", r->tool_calls}, {"toolContent", r->tool_content}, {"adapters", r->adapter_report},
        {"speculationMode", r->dflash ? "dflash" : r->mtp ? "mtp" : r->draft_ctx ? "draft" : "off"},
        {"mtp", (bool)r->mtp && !r->dflash}, {"mtpAcceptRate", r->mtp && !r->dflash && r->draft_proposed > 0 ? (double)r->draft_accepted / r->draft_proposed : 0.0},
        {"draftModel", r->draft_name}, {"draftProposed", r->draft_proposed}, {"draftAccepted", r->draft_accepted},
        {"draftRounds", r->draft_rounds}, {"draftMs", r->draft_ms}, {"specMs", r->spec_ms}, {"draftDisabled", r->draft_disabled}, {"draftReplays", r->draft_replays},
        // Tokens per ms of speculative rounds relative to plain steps this turn (0 when unmeasured).
        // Both rates are per token: a plain step decodes and samples one token.
        {"draftSpeedup", r->spec_ms > 0 && r->plain_ms > 0 && r->plain_steps > 0
            ? ((double)r->spec_tokens / r->spec_ms) / ((double)r->plain_steps / r->plain_ms) : 0.0},
        {"draftAcceptRate", r->draft_proposed > 0 ? (double)r->draft_accepted / (double)r->draft_proposed : 0.0}}.dump();
    return r->info.c_str();
}
static ggml_type cache_type(const std::string & name) {
    return name == "f8_e4m3" ? GGML_TYPE_F8_E4M3 : name == "q8_0" ? GGML_TYPE_Q8_0 : name == "q4_0" ? GGML_TYPE_Q4_0 : name == "q5_0" ? GGML_TYPE_Q5_0
        : name == "q5_1" ? GGML_TYPE_Q5_1 : name == "q4_1" ? GGML_TYPE_Q4_1 : name == "iq4_nl" ? GGML_TYPE_IQ4_NL
        : name == "bf16" ? GGML_TYPE_BF16 : name == "f32" ? GGML_TYPE_F32 : GGML_TYPE_F16;
}
// Two models can share a speculation pipeline only if the draft's tokens
// are the target's tokens (same rule as llama.cpp's speculative examples).
static std::string draft_incompatible(const llama_model * tgt, const llama_model * dft) {
    if (!tgt || !dft) return "the target or draft model is missing";
    const auto * vt = llama_model_get_vocab(tgt);
    const auto * vd = llama_model_get_vocab(dft);
    if (llama_vocab_type(vt) != llama_vocab_type(vd)) return "the draft model uses a different tokenizer type";
    if (llama_vocab_get_add_bos(vt) != llama_vocab_get_add_bos(vd) || llama_vocab_get_add_eos(vt) != llama_vocab_get_add_eos(vd)
        || llama_vocab_bos(vt) != llama_vocab_bos(vd) || llama_vocab_eos(vt) != llama_vocab_eos(vd)) return "the draft model's special tokens differ";
    const int nt = llama_vocab_n_tokens(vt), nd = llama_vocab_n_tokens(vd);
    return od_load_policy::vocabulary_difference(nt, nd,
        [vt](int i) { return llama_vocab_get_text(vt, i); },
        [vd](int i) { return llama_vocab_get_text(vd, i); });
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
        return p.prompt.str().find("odllm_probe_tool") != std::string::npos;
    } catch (const std::exception & e) { r->template_probe_error = e.what(); return false; }
}
// An MTP sidecar: a small separate head file that drafts from the target's
// hidden states (Unsloth's mtp-gemma-4-E4B-it, architecture
// "gemma4-assistant"). LM Studio runs Gemma 4 E4B at about 90 tok/s with it
// on an RTX 3070 against 62 without. It needs an MTP context on the target,
// not a draft model of its own.
static std::string gguf_arch(const std::string & path, uint32_t * experts = nullptr, uint32_t * used = nullptr, uint32_t * blocks = nullptr) {
    gguf_init_params params{true, nullptr};
    auto * meta = gguf_init_from_file(path.c_str(), params);
    if (!meta) return "";
    const int key = gguf_find_key(meta, "general.architecture");
    const std::string arch = key >= 0 && gguf_get_kv_type(meta, key) == GGUF_TYPE_STRING ? gguf_get_val_str(meta, key) : "";
    auto u32 = [&](const std::string & name) -> uint32_t {
        const int k = gguf_find_key(meta, (arch + "." + name).c_str());
        return k >= 0 && gguf_get_kv_type(meta, k) == GGUF_TYPE_UINT32 ? gguf_get_val_u32(meta, k) : 0;
    };
    if (experts) *experts = u32("expert_count");
    if (used) *used = u32("expert_used_count");
    if (blocks) *blocks = u32("block_count");
    gguf_free(meta);
    return arch;
}
struct HeadMetadata {
    std::string arch;
    uint32_t nextn = 0;
    uint32_t blocks = 0;
    bool trunk = false;
    bool projection = false;
    bool only = false;
    uint32_t embedding = 0;
    uint32_t dflash_block = 0;
    std::vector<int32_t> target_layers;
};
static HeadMetadata head_metadata(const std::string & path) {
    HeadMetadata h;
    gguf_init_params params{true, nullptr};
    auto * meta = gguf_init_from_file(path.c_str(), params);
    if (!meta) return h;
    const int arch = gguf_find_key(meta, "general.architecture");
    if (arch >= 0 && gguf_get_kv_type(meta, arch) == GGUF_TYPE_STRING) h.arch = gguf_get_val_str(meta, arch);
    const int blocks = gguf_find_key(meta, (h.arch + ".block_count").c_str());
    if (blocks >= 0 && gguf_get_kv_type(meta, blocks) == GGUF_TYPE_UINT32) h.blocks = gguf_get_val_u32(meta, blocks);
    const int embedding = gguf_find_key(meta, (h.arch + ".embedding_length").c_str());
    if (embedding >= 0 && gguf_get_kv_type(meta, embedding) == GGUF_TYPE_UINT32) h.embedding = gguf_get_val_u32(meta, embedding);
    if (h.arch == "dflash") {
        const int block = gguf_find_key(meta, "dflash.block_size");
        if (block >= 0 && gguf_get_kv_type(meta, block) == GGUF_TYPE_UINT32) h.dflash_block = gguf_get_val_u32(meta, block);
        const int layers = gguf_find_key(meta, "dflash.target_layers");
        if (layers >= 0 && gguf_get_kv_type(meta, layers) == GGUF_TYPE_ARRAY && gguf_get_arr_type(meta, layers) == GGUF_TYPE_INT32) {
            const size_t n = gguf_get_arr_n(meta, layers);
            const auto * ids = static_cast<const int32_t *>(gguf_get_arr_data(meta, layers));
            if (n <= 256) h.target_layers.assign(ids, ids + n);
        }
    }
    const int key = gguf_find_key(meta, (h.arch + ".nextn_predict_layers").c_str());
    if (key >= 0 && gguf_get_kv_type(meta, key) == GGUF_TYPE_UINT32) h.nextn = gguf_get_val_u32(meta, key);
    for (int64_t i = 0; i < gguf_get_n_tensors(meta); ++i) {
        const std::string name = gguf_get_tensor_name(meta, i);
        h.trunk |= name.compare(0, 6, "blk.0.") == 0;
        h.projection |= name.find(".nextn.eh_proj.weight") != std::string::npos;
    }
    h.only = od_load_policy::mtp_only(h.arch, h.nextn, h.trunk);
    gguf_free(meta);
    return h;
}
static bool is_mtp_sidecar(const std::string & path) { return head_metadata(path).only; }
static void check_head(const std::string & path, const HeadMetadata & h, const std::string & target) {
    if (!h.only) return;
    if (h.arch == "gemma4-assistant" && target == "gemma4") return;
    // b12342 nextn_flags still permits missing trunk weights. Qwen35 MTP graphs use
    // this model's head weights and the common driver supplies target hidden rows.
    if ((h.arch == "qwen35" || h.arch == "qwen35moe") && target == h.arch && h.nextn == 1 && h.projection) return;
    throw std::runtime_error(path + " is only an MTP head for " + h.arch
        + "; this engine cannot attach this head to " + target
        + ". Use matching heads inside the model file (for example unsloth's ...-MTP-GGUF).");
}
// The draft model for speculative decoding defaults to the CPU, with plain
// FP16 KV and the target's context; draftGpuLayers moves its layers onto
// the target's GPU.
static llama_model_params draft_model_params(Runtime * r, const json & s, const llama_model_params & mp) {
    auto dp = llama_model_default_params();
    dp.progress_callback = loading_callback;
    dp.progress_callback_user_data = r->cancelled.get();
    dp.n_gpu_layers = mp.n_gpu_layers > 0 ? std::clamp(s.value("draftGpuLayers", 0), 0, 999) : 0;
    if (dp.n_gpu_layers > 0) { dp.devices = mp.devices; dp.main_gpu = mp.main_gpu; dp.split_mode = mp.split_mode; }
    return dp;
}
static llama_context_params draft_context_params(Runtime * r, const llama_context_params & cp) {
    auto dc = llama_context_default_params();
    dc.abort_callback = cancelled_callback;
    dc.abort_callback_data = r->cancelled.get();
    dc.n_ctx = cp.n_ctx; dc.n_batch = cp.n_batch; dc.n_ubatch = cp.n_ubatch;
    dc.n_threads = cp.n_threads; dc.n_threads_batch = cp.n_threads_batch;
    dc.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    // An autoregressive draft samples only its final row. DFlash overrides
    // this for its parallel noise block below.
    dc.n_outputs_max = dc.n_outputs_max_per_seq = 1;
    if (r->dflash) {
        // Block diffusion samples all noise positions in one physical batch.
        dc.ctx_other = r->ctx;
        const uint32_t outputs = r->dflash_block;
        dc.n_batch = std::max(dc.n_batch, outputs);
        dc.n_ubatch = std::max(dc.n_ubatch, outputs);
        dc.n_outputs_max = dc.n_outputs_max_per_seq = outputs;
    }
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
// Adapter tensors follow the base tensor placement. Reserve the full GGUF
// plus buffer/alignment overhead in RAM and on each candidate card: this
// deliberately overestimates mixed placement and includes host staging.
static int64_t adapter_reserve(const json & s) {
    int64_t bytes = 0;
    if (!s.value("embedding", false) && s.contains("loraAdapters") && s["loraAdapters"].is_array()) {
        for (const auto & a : s["loraAdapters"]) {
            const std::string path = a.value("path", "");
            if (!path.empty() && a.value("scale", 1.0f) != 0.0f)
                bytes += file_bytes(path) + (64ll << 20);
        }
    }
    return bytes;
}
static bool has_mtp_heads(const char * path) {
    gguf_init_params params{true, nullptr};
    auto * meta = gguf_init_from_file(path, params);
    if (!meta) return false;
    const auto contains_heads = [](const gguf_context * gguf) {
        for (int64_t i = 0; i < gguf_get_n_tensors(gguf); ++i)
            if (std::string(gguf_get_tensor_name(gguf, i)).find(".nextn.eh_proj.weight") != std::string::npos) return true;
        return false;
    };
    bool found = contains_heads(meta);
    const int count_key = gguf_find_key(meta, "split.count"), no_key = gguf_find_key(meta, "split.no");
    const int count = count_key >= 0 && gguf_get_kv_type(meta, count_key) == GGUF_TYPE_UINT16 ? gguf_get_val_u16(meta, count_key) : 1;
    const int no = no_key >= 0 && gguf_get_kv_type(meta, no_key) == GGUF_TYPE_UINT16 ? gguf_get_val_u16(meta, no_key) : 0;
    gguf_free(meta);
    // Head tensors can be in a later shard of a split GGUF.
    std::vector<char> prefix(std::string(path).size() + 1), shard(prefix.size() + 64);
    if (!found && count > 1 && llama_split_prefix(prefix.data(), prefix.size(), path, no, count) > 0) {
        for (int i = 0; i < count && !found; ++i) {
            if (i == no) continue;
            llama_split_path(shard.data(), shard.size(), prefix.data(), i, count);
            meta = gguf_init_from_file(shard.data(), params);
            if (!meta) continue;
            found = contains_heads(meta);
            gguf_free(meta);
        }
    }
    return found;
}
// RAM in bytes: available now, installed, and this process's own share;
// zeros where the platform gives no reading (macOS, iOS).
struct SystemMemory { int64_t available = 0, total = 0, own = 0; };
static SystemMemory system_memory() {
    SystemMemory m;
#if defined(_WIN32)
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof status;
    if (GlobalMemoryStatusEx(&status)) { m.available = (int64_t)status.ullAvailPhys; m.total = (int64_t)status.ullTotalPhys; }
    PROCESS_MEMORY_COUNTERS pmc{};
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof pmc)) m.own = (int64_t)pmc.WorkingSetSize;
#else
    m.available = proc_bytes("/proc/meminfo", "MemAvailable:");
    m.total = proc_bytes("/proc/meminfo", "MemTotal:");
    m.own = proc_bytes("/proc/self/status", "VmRSS:");
#endif
    return m;
}
// A card with its own memory (CUDA, Vulkan on a discrete GPU). Phone and
// Apple GPUs share the RAM, so what they take counts against the RAM.
static bool own_memory(ggml_backend_dev_t dev) {
#if defined(__APPLE__)
    (void)dev; return false;
#else
    return dev && ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU;
#endif
}
// Bytes the model plus a context of cp.n_ctx take, as llama.cpp lays them
// out, measured without allocating (no_alloc): the return value is what
// lands in RAM, [vram] what lands on cards with their own memory. The
// helper swaps llama's global logger while it runs, hence the lock.
static std::mutex measure_mutex;
static int64_t measure(const char * path, const llama_model_params & mp, const llama_context_params & cp, uint32_t * train = nullptr,
                       int64_t * vram = nullptr, uint32_t * layers_out = nullptr, int64_t * host_weights = nullptr) {
    if (head_metadata(path).only && cp.ctx_type != LLAMA_CONTEXT_TYPE_MTP)
        throw std::runtime_error(std::string(path) + " is only an MTP head; a decoder context cannot use it.");
    std::lock_guard<std::mutex> lock(measure_mutex);
    std::vector<ggml_backend_dev_t> devs;
    uint32_t layers = 0, skipped_nextn = 0, n_train = 0, experts = 0;
    const auto data = common_get_device_memory_data({path}, &mp, &cp, devs, layers, skipped_nextn, n_train, experts, GGML_LOG_LEVEL_ERROR);
    if (train) *train = n_train;
    if (layers_out) *layers_out = layers;
    int64_t bytes = 0, card = 0, weights = 0;
    // One entry per device in devs, then the host.
    for (size_t i = 0; i < data.size(); ++i) {
        const int64_t b = (int64_t)(data[i].model + data[i].context + data[i].compute);
        if (i < devs.size() && own_memory(devs[i])) card += b; else { bytes += b; weights += (int64_t)data[i].model; }
    }
    if (host_weights) *host_weights = weights;
    if (mp.load_mtp) {
        auto mc = cp;
        mc.ctx_type = LLAMA_CONTEXT_TYPE_MTP;
        mc.n_rs_seq = 0;
        const auto extra = common_get_device_memory_data({path}, &mp, &mc, devs, layers, skipped_nextn, n_train, experts, GGML_LOG_LEVEL_ERROR);
        for (size_t i = 0; i < extra.size(); ++i) {
            const int64_t b = (int64_t)(extra[i].context + extra[i].compute);
            if (i < devs.size() && own_memory(devs[i])) card += b; else bytes += b;
        }
    }
    if (vram) *vram = card;
    return bytes;
}
// Canonical DFlash drafts may borrow token embeddings/output from the
// target. The no-allocation graph must see that target too, even on the
// estimator's unloaded runtime. Never measure it as an independent decoder.
static int64_t measure_draft(Runtime * r, const char * target, const llama_model_params & mp,
                             const llama_context_params & cp, const std::string & draft,
                             const llama_model_params & dp, int64_t * vram = nullptr) {
    auto dc = draft_context_params(r, cp);
    if (!r->dflash) return measure(draft.c_str(), dp, dc, nullptr, vram);
    auto tm = mp; tm.no_alloc = true; tm.load_mode = LLAMA_LOAD_MODE_NONE;
    std::unique_ptr<llama_model, decltype(&llama_model_free)> model(llama_model_load_from_file(target, tm), llama_model_free);
    if (!model) throw std::runtime_error("OD_DFLASH_METADATA");
    std::unique_ptr<llama_context, decltype(&llama_free)> ctx(llama_init_from_model(model.get(), cp), llama_free);
    if (!ctx) throw std::runtime_error("OD_DFLASH_METADATA");
    dc.ctx_other = ctx.get();
    return measure(draft.c_str(), dp, dc, nullptr, vram);
}
// Memory admission (report 2026-09-28): the saved context was used as
// is, so a 64K context on Qwen3 1.7B asked for ~7 GiB of cache and Android
// killed the app while it loaded. The context is capped to the model's
// trained length (unless the user chose linear or YaRN scaling to stretch
// it) and to what fits in the memory free right now; cp.n_ctx is the
// result. The returned fields go into effectiveSettings so the app can say
// what happened.
static json admit(Runtime * r, const char * path, const json & s, const llama_model_params & mp, llama_context_params & cp,
                  const std::string & draft, const llama_model_params & dp, const std::string & mmproj, int64_t sidecar = 0) {
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
    const int64_t adapters = adapter_reserve(s);
    const int64_t extra = file_bytes(mmproj) + sidecar + adapters + r->dflash_features;
    const bool on_card = mp.n_gpu_layers > 0 && std::any_of(r->devices.begin(), r->devices.end(), own_memory);
    uint32_t train = 0;
    int64_t vram = 0, weights = 0;
    std::map<uint32_t, int64_t> vram_at;
    auto need_at = [&](uint32_t n) {
        if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Loading cancelled.");
        cp.n_ctx = n;
        int64_t bytes = measure(path, mp, cp, &train, &vram, nullptr, &weights) + extra;
        int64_t draft_vram = 0;
        if (!draft.empty()) bytes += measure_draft(r, path, mp, cp, draft, dp, &draft_vram);
        vram_at[n] = vram + draft_vram + (on_card ? adapters + r->dflash_features : 0);
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
    const SystemMemory ram = system_memory();
    const int64_t available = ram.available;
    int64_t budget = 0;
    if (available > 0) {
#if defined(_WIN32)
        // Windows pages instead of killing, but a model paged out decodes
        // at disk speed; an eighth of the RAM (at least 1 GB) stays free
        // for the desktop and the other apps.
        budget = available - std::max<int64_t>(1ll << 30, ram.total / 8);
        // Memory-mapped weights are file-backed: Windows drops and re-reads
        // them rather than failing, and the CPU retry loads them unchecked,
        // so only the cache and buffers have to fit. Counting them refused
        // the GPU for Qwen3.6 35B A3B (18 GB of experts on the host) on a
        // 32 GB PC and the CPU retry decoded at 5 tok/s instead of 31.
        if (s.value("useMmap", true) && !s.value("useMlock", false)) {
            budget += weights;
            out["memoryPagedMb"] = weights >> 20;
            if (weights > available) out["memoryWarning"] = "weightsExceedFreeRam";
        }
#else
        // Measured on an 11 GB phone (2026-09-28): a load that left 0.8 GB
        // available survived, with the phone one app switch from killing
        // it, so a sixth of the RAM stays free for everything else. Busy
        // phones read low because MemAvailable leaves out the background
        // apps Android closes on demand, yet a foreground app can count on
        // about 40% of the RAM (Gemma 4 E2B at 5.4 GB RSS never died).
        budget = std::max(available - std::max<int64_t>(1ll << 30, ram.total / 6), ram.total * 2 / 5 - ram.own);
#endif
        out["memoryAvailableMb"] = available >> 20;
        out["memoryBudgetMb"] = budget >> 20;
        if (need > budget) {
            // Model memory is fixed and the cache grows with the context, so
            // two measurements give the context that fits; it is then
            // confirmed, because compute buffers do not grow exactly linearly.
            const uint32_t low = std::min(n, std::max<uint32_t>(1024, std::min<uint32_t>(n / 2, 4096)));
            const int64_t need_low = low < n ? need_at(low) : need;
            if (need_low > budget && r->planning) {
                cp.n_ctx = low;
                out["contextCap"] = "memory";
                out["memoryNeedMb"] = need_low >> 20;
                if (vram_at[low] > 0) out["vramNeedMb"] = vram_at[low] >> 20;
                return out;
            }
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
    if (vram_at[n] > 0) out["vramNeedMb"] = vram_at[n] >> 20;
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
// GPU offload fit (desktop): with every layer asked for on a card with its
// own memory, llama.cpp's fit lowers the layers on the card (or moves MoE
// experts to the CPU) until the model and this context leave [vramReserveMb]
// free. Without it a model bigger than the card fails to allocate. A number
// of layers below "all" is the user's own choice and is kept as is. The
// projector placed on the card (load_with) joins the margin.
static json fit_gpu(Runtime * r, const char * path, const json & s, llama_model_params & mp, llama_context_params & cp,
                    int64_t projector) {
    json out = json::object();
    ggml_backend_dev_t card = r->devices.empty() ? nullptr : r->devices[mp.split_mode == LLAMA_SPLIT_MODE_NONE ? mp.main_gpu : 0];
    if (!own_memory(card)) return out;
    size_t free = 0, total = 0;
    ggml_backend_dev_memory(card, &free, &total);
    out["vramFreeMb"] = (int64_t)(free >> 20);
    out["vramTotalMb"] = (int64_t)(total >> 20);
    if (mp.n_gpu_layers <= 0) return out;
    if (s.value("nCpuMoe", -1) >= 0) { out["gpuFit"] = "manual"; return out; }
    // A count at or above the model's layers (n_gpu_layers counts the output
    // layer too) asks for every layer, the same as 999: an old saved 64 on a
    // 31-layer MoE skipped the fit, put every expert on an 8 GB card and
    // spilled into shared memory (4 tok/s instead of 20 with experts in RAM).
    if (mp.n_gpu_layers < 999) {
        uint32_t blocks = 0;
        gguf_arch(path, nullptr, nullptr, &blocks);
        if (od_load_policy::all_layers(mp.n_gpu_layers, blocks)) mp.n_gpu_layers = 999;
    }
    if (mp.n_gpu_layers < 999 || !s.value("gpuFit", true)) { out["gpuFit"] = "manual"; return out; }
    std::lock_guard<std::mutex> lock(measure_mutex);
    r->split.assign(llama_max_devices(), 0.0f);
    r->overrides.assign(llama_max_tensor_buft_overrides(), llama_model_tensor_buft_override{nullptr, nullptr});
    std::vector<size_t> margins(llama_max_devices(), (size_t)std::clamp(s.value("vramReserveMb", 768), 0, 8192) << 20);
    const int64_t adapters = adapter_reserve(s);
    for (auto & margin : margins) margin += (size_t)adapters;
    margins[0] += (size_t)std::max<int64_t>(projector, 0);
    // Only parameters still at llama's defaults are changed, and a context
    // that is set (not 0) is kept: the RAM admission caps it afterwards.
    mp.n_gpu_layers = llama_model_default_params().n_gpu_layers;
    auto mc = cp;
    mc.ctx_type = LLAMA_CONTEXT_TYPE_MTP;
    mc.n_rs_seq = 0;
    common_fit_extra_model extra{{path}, &mp, &mc, true};
    const auto status = common_fit_params({path}, &mp, &cp, r->split.data(), r->overrides.data(), margins.data(),
                                          cp.n_ctx, mp.load_mtp ? &extra : nullptr, GGML_LOG_LEVEL_ERROR);
    if (status == COMMON_PARAMS_FIT_STATUS_ERROR) {
        // Unreadable here: the real load reports why.
        mp.n_gpu_layers = 999; mp.tensor_buft_overrides = nullptr; mp.tensor_split = nullptr;
        return out;
    }
    if (mp.n_gpu_layers < 0) mp.n_gpu_layers = 999;
    out["gpuFit"] = status == COMMON_PARAMS_FIT_STATUS_SUCCESS ? "fit" : "failed";
    out["gpuExpertsOnCpu"] = mp.tensor_buft_overrides != nullptr && mp.tensor_buft_overrides[0].pattern != nullptr;
    return out;
}
// Loads the model, or with [estimate_only] stops after planning and returns
// what the load would use (od_estimate).
static json load_with(Runtime * r, const char * path, const json & config, const std::string & requested, bool estimate_only = false) {
        auto s = config;
        const std::string mode = s.value("speculationMode", "auto");
        if (mode == "off") { s["draftModel"] = ""; s["mtp"] = false; }
        if (mode == "mtp") s["mtp"] = true;
        if (mode == "draft" || mode == "dflash") s["mtp"] = false;
        const auto target_meta = head_metadata(path);
        if (target_meta.arch == "dflash" || target_meta.arch == "dflash-draft") throw std::runtime_error("OD_SPEC_MODE");
        if (target_meta.only) throw std::runtime_error(std::string(path) + " is only an MTP head for " + target_meta.arch + "; select a full target model.");
        const std::string selected_draft = s.value("embedding", false) ? "" : s.value("draftModel", "");
        // Validate before any measurement can build an ordinary decoder graph.
        const auto draft_meta = selected_draft.empty() ? HeadMetadata{} : head_metadata(selected_draft);
        r->dflash = draft_meta.arch == "dflash";
        r->dflash_features = 0;
        if (draft_meta.arch == "dflash-draft") throw std::runtime_error("OD_DFLASH_FORMAT");
        if ((mode == "draft" || mode == "dflash") && selected_draft.empty()) throw std::runtime_error("OD_DRAFT_REQUIRED");
        if ((mode == "dflash" && !r->dflash) || (mode == "draft" && (r->dflash || draft_meta.only))
            || (mode == "mtp" && !selected_draft.empty() && !draft_meta.only)) throw std::runtime_error("OD_SPEC_MODE");
        if (!selected_draft.empty()) check_head(selected_draft, draft_meta, target_meta.arch);
        if (r->dflash) {
            if (draft_meta.dflash_block < 2 || draft_meta.dflash_block > 512 || draft_meta.target_layers.empty()
                || target_meta.embedding == 0 || draft_meta.embedding != target_meta.embedding || std::any_of(draft_meta.target_layers.begin(), draft_meta.target_layers.end(),
                    [&](int32_t id) { return id < 0 || (uint32_t)id >= target_meta.blocks; })) throw std::runtime_error("OD_DFLASH_METADATA");
            r->dflash_block = draft_meta.dflash_block;
            r->dflash_max = std::min<int>(std::clamp(s.value("draftMaxTokens", 6), 1, 32), draft_meta.dflash_block - 1);
            s["draftMaxTokens"] = r->dflash_max;
        }
        auto mp = llama_model_default_params();
        const bool use_mmap = s.value("useMmap", true), use_mlock = s.value("useMlock", false);
        // Newer llama.cpp folds mmap and mlock into one load mode.
        mp.load_mode = use_mmap ? (use_mlock ? LLAMA_LOAD_MODE_MMAP_MLOCK : LLAMA_LOAD_MODE_AUTO)
                                : (use_mlock ? LLAMA_LOAD_MODE_MLOCK : LLAMA_LOAD_MODE_NONE);
        mp.main_gpu = std::clamp(s.value("mainGpu", 0), 0, 127);
        const std::string split_mode = s.value("splitMode", "layer");
        mp.split_mode = split_mode == "none" ? LLAMA_SPLIT_MODE_NONE : split_mode == "row" ? LLAMA_SPLIT_MODE_ROW : LLAMA_SPLIT_MODE_LAYER;
        const int n_cpu_moe = std::clamp(s.value("nCpuMoe", -1), -1, 4096);
        r->overrides.clear();
        if (n_cpu_moe >= 0) {
            std::lock_guard<std::mutex> lock(measure_mutex);
            llm_add_n_cpu_ffn_overrides(n_cpu_moe, LLM_FFN_EXPS_REGEX, r->overrides);
            r->overrides.push_back({nullptr, nullptr});
            mp.tensor_buft_overrides = r->overrides.data();
        }
        mp.progress_callback = loading_callback;
        mp.progress_callback_user_data = r->cancelled.get();
        r->devices.clear(); r->backend = "CPU"; r->fallback_reason = s.value("speculationFallback", "");
        std::string skipped;
        if (requested != "cpu" && s.value("nGpuLayers", 999) > 0) {
            std::vector<ggml_backend_dev_t> candidates;
            for (size_t i = 0; i < ggml_backend_dev_count(); ++i) candidates.push_back(ggml_backend_dev_get(i));
#if defined(_WIN32)
            // Prefer dedicated VRAM on hybrid laptops; integrated GPUs remain a fallback.
            std::stable_sort(candidates.begin(), candidates.end(), [](auto a, auto b) {
                return (ggml_backend_dev_type(a) == GGML_BACKEND_DEVICE_TYPE_GPU)
                    > (ggml_backend_dev_type(b) == GGML_BACKEND_DEVICE_TYPE_GPU);
            });
#endif
            for (auto dev : candidates) {
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
                // Windows Auto takes a discrete Vulkan GPU only: Intel UHD (i7-11800H,
                // Qwen3.5 0.8B Q8) decoded 18.7 tok/s against 31 tok/s on the CPU, so
                // integrated GPUs stay an explicit "Vulkan" choice.
                const bool auto_ok = requested == "auto" && (lower == "metal"
                    || (lower == "cuda" && type == GGML_BACKEND_DEVICE_TYPE_GPU)
#if defined(_WIN32)
                    || (lower == "vulkan" && type == GGML_BACKEND_DEVICE_TYPE_GPU)
#endif
                    );
                if (requested == "auto" && !auto_ok) { if (skipped.empty()) skipped = name; continue; }
                if (auto_ok || lower.find(requested) != std::string::npos) {
                    // Auto chooses one backend family, then includes every matching card.
                    if (!r->devices.empty() && ggml_backend_dev_backend_reg(dev) != ggml_backend_dev_backend_reg(r->devices.front())) continue;
                    r->devices.push_back(dev);
                    if (r->devices.size() == 1) r->backend = name + " / " + ggml_backend_dev_description(dev);
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
        const bool on_cpu = r->devices.empty() || mp.n_gpu_layers == 0;
        mp.main_gpu = r->devices.empty() ? 0 : std::min<int>(mp.main_gpu, (int)r->devices.size() - 1);
        r->devices.push_back(nullptr); mp.devices = r->devices.data();
        r->embedding = s.value("embedding", false);
        mp.load_mtp = !r->embedding && s.value("mtp", false) && s.value("draftModel", "").empty() && has_mtp_heads(path);
        auto cp = llama_context_default_params();
        // App units match upstream --moe-cache-mib; C API takes bytes.
        if (s.contains("moeCacheSizeMb")) cp.moe_cache_size = (size_t)std::clamp<int64_t>(s.value("moeCacheSizeMb", int64_t(0)), 0, int64_t(1) << 30) * 1024 * 1024;
        if (s.contains("moeCacheCpuShare")) {
            const float share = s.value("moeCacheCpuShare", 0.0f);
            cp.moe_cache_cpu_share = std::isfinite(share) ? std::clamp(share, 0.0f, 1.0f) : 0.0f;
        }
        cp.offload_kqv = s.value("offloadKv", true);
        cp.swa_full = s.value("swaFull", false);
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
            // Several inputs may ride one decode as distinct sequences over
            // the shared unified window (audit E22); the batch is still
            // bounded by n_batch, and od_embed clears the memory between
            // batches, so an item alone can use the whole context.
            cp.n_seq_max = std::max<int>(cp.n_seq_max, kEmbedBatchSeqs);
            cp.kv_unified = true;
        }
        cp.n_batch = r->batch;
        cp.n_ubatch = std::clamp(s.value("effectiveMicroBatchSize", std::min(r->batch, 128)), 32, r->batch);
        // An encoder attends both ways, so one input must fit one micro-batch
        // (llama.cpp asserts it); photos alone are ~280 tokens.
        if (r->embedding) cp.n_ubatch = r->batch;
        // Zero or less = auto: the physical cores (od_cpu_cores). The upper
        // bound follows the detected core count instead of a fixed 16.
        auto threads = [](int asked) {
          return std::clamp(asked > 0 ? asked : od_cpu_cores(), 1, od_cpu_cores());
        };
        // The app's automatic count assumes the GPU it asked for; a CPU load
        // (no GPU found) decodes on every physical core instead.
        cp.n_threads = threads(on_cpu && s.value("threadsAuto", false) ? 0 : s.value("effectiveThreads", 4));
        // Prefill scales past the decode optimum (S25+: 8 threads prefill 14%
        // faster than 6 while 8 collapses decode), so the two are separate.
        cp.n_threads_batch = threads(s.value("effectiveBatchThreads", (int)cp.n_threads));
        cp.flash_attn_type = s.value("flashAttention", true) ? LLAMA_FLASH_ATTN_TYPE_AUTO : LLAMA_FLASH_ATTN_TYPE_DISABLED;
        // Separate K and V cache types (ABI 6): "vCacheType" empty = same as K.
        auto kv = s.value("kvCacheType", "fp16");
        auto vv = s.value("vCacheType", ""); if (vv.empty()) vv = kv;
        // Gate before fit/measurement as those also create contexts. Conservatively
        // exclude MLA families and the direct cache consumers rejected upstream.
        const std::set<std::string> no_fp8_arch = {"deepseek2", "deepseek2-ocr", "deepseek32", "deepseek4", "deepseek41",
            "bailingmoe3", "kimi-linear", "kimi-k3", "kimi-k31", "xing4_0",
            "glm-dsa", "glm5-next", "dots3note", "mistral-large4", "hy_v4", "minimax-m3", "qwen4exp", "dflash"};
        bool fp8_backend = true;
        for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
            auto dev = ggml_backend_dev_get(i);
            if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_CPU) fp8_backend &= supports_fp8_kv(dev);
        }
        for (auto dev : r->devices) if (dev) fp8_backend &= supports_fp8_kv(dev);
        const bool fp8_supported = fp8_backend && no_fp8_arch.count(target_meta.arch) == 0 && !r->dflash;
        std::string kv_fallback;
        if (!fp8_supported && (kv == "f8_e4m3" || vv == "f8_e4m3")) {
            kv_fallback = "FP8 E4M3 KV cache is unsupported for the selected backend, architecture or DFlash pipeline; using q8_0.";
            if (kv == "f8_e4m3") kv = "q8_0";
            if (vv == "f8_e4m3") vv = "q8_0";
            std::fprintf(stderr, "odllm: %s\n", kv_fallback.c_str());
            if (!r->fallback_reason.empty()) r->fallback_reason += " ";
            r->fallback_reason += kv_fallback;
        }
        cp.type_k = cache_type(kv); cp.type_v = cache_type(vv);
        // A quantized V cache needs flash attention; a quantized K alone does not.
        if (cp.type_v != GGML_TYPE_F16 && cp.type_v != GGML_TYPE_F32 && cp.type_v != GGML_TYPE_BF16) cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        if (cp.type_k == GGML_TYPE_F8_E4M3) cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
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
        // Experts per token for a mixture-of-experts model (LM Studio's
        // "number of experts"): fewer is faster and less accurate. Applied as
        // the model's own <arch>.expert_used_count key, before the fit.
        r->kv_overrides.clear();
        if (s.value("expertsUsed", -1) > 0) {
            uint32_t experts = 0, used = 0;
            const std::string arch = gguf_arch(path, &experts, &used);
            const int want = std::min<int>(s.value("expertsUsed", -1), (int)experts);
            if (experts > 0 && used > 0 && want != (int)used) {
                llama_model_kv_override o{};
                o.tag = LLAMA_KV_OVERRIDE_TYPE_INT;
                o.val_i64 = want;
                const std::string name = arch + ".expert_used_count";
                if (name.size() < sizeof o.key) {
                    std::memcpy(o.key, name.c_str(), name.size() + 1);
                    r->kv_overrides.push_back(o);
                    r->kv_overrides.push_back(llama_model_kv_override{});
                    mp.kv_overrides = r->kv_overrides.data();
                }
            }
        }
        const std::string draft = r->embedding ? "" : s.value("draftModel", "");
        const std::string mmproj = s.value("mmproj", "");
        auto dp = draft_model_params(r, s, mp);
        // An MTP head shares the target's KV cache: its weights plus a small
        // compute buffer, on the target's device.
        const bool sidecar = !draft.empty() && is_mtp_sidecar(draft);
        dp.load_mtp = sidecar;
        // A head reads the target's hidden rows every step: it follows the
        // target onto the card unless draftGpuLayers places it (0 = default).
        // A DFlash drafter reads the target's features every round too; on
        // the CPU it cost more than it saved (owner 2026-11-12: Nemotron
        // Bolt 41 tok/s with DFlash on the CPU, 58 plain, 60 on the card).
        if ((sidecar || r->dflash) && dp.n_gpu_layers == 0 && mp.n_gpu_layers > 0) {
            dp.n_gpu_layers = 999;
            dp.devices = mp.devices; dp.main_gpu = mp.main_gpu; dp.split_mode = mp.split_mode;
        }
        // Recurrent state snapshots per draft position (as llama-server sets
        // them; llama ignores them for models without recurrent layers): a
        // rejected draft is dropped with seq_rm instead of a state copy,
        // restore and replay decode every round, which made MTP on Qwen3.6
        // slower than plain decoding (2026-10-29).
        if (!draft.empty() || mp.load_mtp) cp.n_rs_seq = (uint32_t)std::clamp(s.value("draftMaxTokens", 6), 1, 32);
        r->draft_p_min = std::clamp(s.value("draftMinP", 0.0f), 0.0f, 1.0f);
        // Match llama-server's single-sequence output limits BEFORE fitting:
        // otherwise the fit budgets a worst-case n_batch-row vocabulary
        // projection and can leave the output layer on the CPU unnecessarily.
        // Prompt evaluation requests only the last row; verification needs
        // drafts + one. Embedding contexts still need every prompt row.
        if (!r->embedding) {
            const auto limits = common_speculative_get_output_limits(r->batch, 1,
                (!draft.empty() || mp.load_mtp) ? std::clamp(s.value("draftMaxTokens", 6), 1, 32) : 0);
            cp.n_outputs_max = limits.total;
            cp.n_outputs_max_per_seq = limits.per_seq;
        }
        if (r->dflash) {
            cp.n_ubatch = std::max<uint32_t>(cp.n_ubatch, r->dflash_block);
            cp.n_batch = std::max(cp.n_batch, cp.n_ubatch);
            // Host gather plus target extraction/transfer buffers, with graph
            // headroom. Reserve on both RAM and VRAM conservatively.
            r->dflash_features = (64ll << 20) + 2ll * cp.n_ubatch * target_meta.embedding * draft_meta.target_layers.size() * sizeof(float);
        }
        const int64_t sidecar_bytes = sidecar ? file_bytes(draft) + (64ll << 20) : 0;
        // Vision projector placement (projectorDevice auto | gpu | cpu). Auto
        // keeps it on the GPU when the whole model still fits there with it,
        // else puts it on the CPU when that lets every layer onto the card
        // (Ollama's rule, llm/server.go): on an 8 GB card the f16 projector
        // of Gemma 4 E4B costs 6 of its 43 layers and every token then
        // decodes about half as fast, while a photo is encoded once.
        const std::string projector_choice = s.value("projectorDevice", "auto");
        bool projector_gpu = !mmproj.empty() && projector_choice != "cpu";
        json admission = json::object();
        if (!r->embedding) {
            const uint32_t context_requested = cp.n_ctx;
            std::string context_cap;
            // Use the same trained length and scaling exceptions as admit(),
            // before either GPU fit budgets the target's cache.
            if (s.value("memoryGuard", true) && rope != "linear" && rope != "yarn") {
                uint32_t train = 0;
                try { measure(path, mp, cp, &train); } catch (const std::exception &) { train = 0; }
                if (train > 0 && cp.n_ctx > train) {
                    cp.n_ctx = train;
                    context_cap = "train";
                }
            }
            const auto requested_mp = mp;
            // One retry after RAM admission, starting from the user's layer
            // request so layers removed by the first fit can return to the GPU.
            for (int attempt = 0; attempt < 2; ++attempt) {
                mp = requested_mp;
                projector_gpu = !mmproj.empty() && projector_choice != "cpu";
                // Recompute the draft's VRAM reserve at this context too.
                int64_t draft_card = 0;
                if (!sidecar && !draft.empty() && dp.n_gpu_layers > 0) {
                    measure_draft(r, path, mp, cp, draft, dp, &draft_card);
                    draft_card = std::max(draft_card, file_bytes(draft));
                }
                const int64_t others = (dp.n_gpu_layers > 0 ? sidecar_bytes : 0) + draft_card + r->dflash_features;
                const auto mp0 = mp;
                const auto cp0 = cp;
                admission = fit_gpu(r, path, s, mp, cp, (projector_gpu ? file_bytes(mmproj) : 0) + others);
                if (projector_gpu && projector_choice == "auto" && admission.value("gpuFit", "") == "fit") {
                    uint32_t blocks = 0;
                    gguf_arch(path, nullptr, nullptr, &blocks);
                    // n_gpu_layers counts the output layer too.
                    auto whole = [&](const llama_model_params & p, const json & fit) {
                        return blocks > 0 && fit.value("gpuFit", "") == "fit" && !fit.value("gpuExpertsOnCpu", false)
                            && p.n_gpu_layers >= (int32_t)blocks + 1;
                    };
                    if (!whole(mp, admission)) {
                        // The fit writes into r->split and r->overrides; a rejected
                        // second fit gives the first one's values back.
                        const auto split = r->split;
                        const auto overrides = r->overrides;
                        auto mp1 = mp0;
                        auto cp1 = cp0;
                        json alt = fit_gpu(r, path, s, mp1, cp1, others);
                        if (whole(mp1, alt)) {
                            mp = mp1; cp = cp1; admission = alt; projector_gpu = false;
                        } else {
                            r->split = split; r->overrides = overrides;
                            if (mp.tensor_split) mp.tensor_split = r->split.data();
                            if (mp.tensor_buft_overrides) mp.tensor_buft_overrides = r->overrides.data();
                        }
                    }
                }
                // A projector or MTP head the fit put on the card is in its VRAM
                // budget, not the RAM's (as the estimate below counts them):
                // counting it twice refused Gemma 4 26B A4B (1.4 GB of them) on
                // a 32 GB PC that LM Studio loads.
                const bool on_card = mp.n_gpu_layers > 0 && own_memory(r->devices.empty() ? nullptr : r->devices[mp.split_mode == LLAMA_SPLIT_MODE_NONE ? mp.main_gpu : 0]);
                admission.update(admit(r, path, s, mp, cp, sidecar ? "" : draft, dp, projector_gpu && on_card ? "" : mmproj,
                    on_card && dp.n_gpu_layers > 0 ? 0 : sidecar_bytes));
                if (!admission.value("contextCap", "").empty()) context_cap = admission.value("contextCap", "");
                if (cp.n_ctx >= cp0.n_ctx) break;
            }
            admission["contextRequested"] = context_requested;
            admission["contextCap"] = context_cap;
        }
        // Without layers on a GPU the projector runs on the CPU too.
        projector_gpu = projector_gpu && mp.n_gpu_layers > 0;
        admission["supportsDFlash"] = true;
        admission["supportsFp8Kv"] = fp8_supported;
        admission["kvCacheFallbackReason"] = kv_fallback;
        admission["kvCacheType"] = kv;
        admission["vCacheType"] = vv;
        admission["moeCacheSizeMb"] = cp.moe_cache_size >> 20;
        admission["moeCacheCpuShare"] = cp.moe_cache_cpu_share;
        admission["speculationMode"] = r->dflash ? "dflash" : sidecar || mp.load_mtp ? "mtp" : !draft.empty() ? "draft" : "off";
        admission["dflashReserveMb"] = r->dflash_features >> 20;
        admission["projectorDevice"] = mmproj.empty() ? "" : projector_gpu ? "gpu" : "cpu";
        admission.update({{"useMmap", use_mmap}, {"useMlock", use_mlock}, {"mainGpu", mp.main_gpu},
            {"splitMode", mp.split_mode == LLAMA_SPLIT_MODE_NONE ? "none" : mp.split_mode == LLAMA_SPLIT_MODE_ROW ? "row" : "layer"},
            {"offloadKv", cp.offload_kqv}, {"swaFull", cp.swa_full}, {"nCpuMoe", n_cpu_moe},
            {"expertsUsed", r->kv_overrides.empty() ? -1 : (int)r->kv_overrides[0].val_i64},
            {"keepTokens", std::clamp(s.value("keepTokens", 0), 0, (int)cp.n_ctx - 2)},
            {"contextOverflow", s.value("contextOverflow", "trim")}, {"logitBias", s.value("logitBias", json::object())}});
        if (estimate_only) {
            uint32_t layers = 0;
            int64_t vram = 0;
            int64_t host_weights = 0;
            int64_t ram = measure(path, mp, cp, nullptr, &vram, &layers, &host_weights) + adapter_reserve(s) + r->dflash_features;
            if (mp.n_gpu_layers > 0) vram += r->dflash_features;
            if (mp.n_gpu_layers > 0 && std::any_of(r->devices.begin(), r->devices.end(), own_memory)) vram += adapter_reserve(s);
            // The projector goes where the placement above put it; the draft
            // model is counted as admission counts it.
            const bool on_card = mp.n_gpu_layers > 0 && own_memory(r->devices.empty() ? nullptr : r->devices[mp.split_mode == LLAMA_SPLIT_MODE_NONE ? mp.main_gpu : 0]);
            (on_card && dp.n_gpu_layers > 0 ? vram : ram) += sidecar_bytes;
            (on_card && projector_gpu ? vram : ram) += file_bytes(mmproj);
            if (!draft.empty() && !sidecar) {
                int64_t draft_vram = 0;
                ram += measure_draft(r, path, mp, cp, draft, dp, &draft_vram);
                vram += draft_vram;
            }
            admission["contextSize"] = cp.n_ctx;
            // n_gpu_layers counts the output layer too.
            const uint32_t all_layers = (target_meta.blocks > 0 ? target_meta.blocks : layers) + 1;
            admission["layers"] = all_layers;
            admission["gpuLayers"] = std::min<int64_t>(mp.n_gpu_layers, all_layers);
            // Match admit(): only the target's file-backed host weights are
            // credited there; sidecars and draft buffers remain resident.
            int64_t paged = 0;
#if defined(_WIN32)
            if (use_mmap && !use_mlock) paged = host_weights;
#endif
            admission["ramPagedMb"] = paged >> 20;
            admission["ramNeedMb"] = std::max<int64_t>(0, ram - paged) >> 20;
            if (admission.contains("memoryBudgetMb")) {
                admission["ramBudgetMb"] = std::max<int64_t>(0,
                    admission["memoryBudgetMb"].get<int64_t>() - (paged >> 20));
            }
            admission["vramNeedMb"] = vram >> 20;
            admission["backend"] = r->backend;
            return admission;
        }
        LoadingProgress loading{r->cancelled.get(), r->progress.get()};
        mp.progress_callback = weight_loading_callback;
        mp.progress_callback_user_data = &loading;
        last_native_error.clear();
        r->model = llama_model_load_from_file(path, mp);
        if (!r->model) {
            // llama.cpp's own words, e.g. "unknown model architecture: 'x'".
            const std::string why = last_native_error;
            if (why.empty()) throw std::runtime_error("Cannot load this GGUF. It may be unsupported, incomplete, or too large for available memory.");
            throw std::runtime_error("Cannot load this GGUF (" + why + "). It may need a newer engine, or the file is incomplete.");
        }
        r->progress->store(0.9f, std::memory_order_relaxed);
        if (llama_model_has_encoder(r->model) || !llama_model_has_decoder(r->model)) throw std::runtime_error("Only decoder text-generation models are supported.");
        r->model_path = path;
        const std::string chat_template = s.value("chatTemplate", "");
        if (!r->embedding) {
            try {
                // Empty override lets common discover the tool_use variant too.
                r->templates = common_chat_templates_init(r->model, chat_template);
                common_chat_templates_inputs probe;
                common_chat_msg user; user.role = "user"; user.content = "hi"; probe.messages.push_back(user);
                probe.force_pure_content = true;
                common_chat_templates_apply(r->templates.get(), probe);
            } catch (const std::exception & e) {
                r->template_error = e.what(); r->templates.reset();
                if (!chat_template.empty()) throw std::runtime_error(std::string("Invalid prompt template: ") + e.what());
            }
            if (r->templates) {
                try { r->supports_thinking = common_chat_templates_support_enable_thinking(r->templates.get()); }
                catch (const std::exception & e) { r->template_probe_error = e.what(); }
                // A missing template still permits the caller's legacy family fallback.
                if (!common_chat_templates_was_explicit(r->templates.get())) r->templates.reset();
            }
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
        // The accepted parameters and scales are kept for helper contexts.
        r->context_params = cp; r->adapter_scales = scales;
        if (!r->adapters.empty() && llama_set_adapters_lora(r->ctx, r->adapters.data(), r->adapters.size(), scales.data()) != 0)
            throw std::runtime_error("The LoRA adapters could not be applied to this model.");
        r->adapter_report = adapter_report;
        r->swa_full = cp.swa_full;
        r->n_swa = llama_model_n_swa(r->model);
        r->needs_checkpoints = llama_model_is_recurrent(r->model) || llama_model_is_hybrid(r->model) || (r->n_swa > 0 && !r->swa_full);
        // Vision projector: optional; a failure leaves the text model usable
        // and is reported so the app can say why photos are unavailable.
        if (!mmproj.empty()) {
            auto vp = mtmd_context_params_default();
            // Weights placed off the card still compute there: the scheduler
            // copies each one over for an image's large batches (op offload,
            // patches/mtmd-weights-on-host.patch). Without it a 1,023-token
            // photo took 25.7 s on 8 CPU cores against 2.5 s on an RTX 3070.
            vp.use_gpu = mp.n_gpu_layers > 0;
            vp.weights_on_host = vp.use_gpu && !projector_gpu;
            vp.device = vp.use_gpu ? r->devices[mp.split_mode == LLAMA_SPLIT_MODE_NONE ? mp.main_gpu : 0] : nullptr;
            vp.n_threads = cp.n_threads_batch;
            vp.flash_attn_type = cp.flash_attn_type;
            vp.print_timings = false;
            vp.warmup = false;
            // Dynamic-resolution encoders (Qwen-VL style) would spend up to
            // the projector's own maximum on a photo; on a phone every image
            // token costs an encoder pass and a prefill token, so cap it.
            if (!r->embedding || s.contains("imageMaxTokens")) vp.image_max_tokens = std::clamp(s.value("imageMaxTokens", 1024), 64, 16384);
            // Load cancellation: stop projector initialization when the
            // session is cancelled, matching the model/context loads (audit E21).
            vp.progress_callback = loading_callback;
            vp.progress_callback_user_data = r->cancelled.get();
            r->mctx = mtmd_init_from_file(mmproj.c_str(), r->model, vp);
            if (!r->mctx) r->vision_error = "The vision projector could not be loaded (wrong file for this model, or out of memory).";
            else if (!mtmd_support_vision(r->mctx) && !(r->embedding && mtmd_support_audio(r->mctx))) { mtmd_free(r->mctx); r->mctx = nullptr; r->vision_error = "This projector has no image encoder."; }
        }
        // Draft model for speculative decoding (ABI 6): CPU unless
        // draftGpuLayers, plain FP16 KV, same context. Vocabulary mismatch is a load error the app shows.
        if (sidecar) {
            // Head placement honors draftGpuLayers, including CPU.
            r->draft_model = llama_model_load_from_file(draft.c_str(), dp);
            if (!r->draft_model) throw std::runtime_error("The MTP head could not be loaded.");
            auto why = draft_incompatible(r->model, r->draft_model);
            if (why.empty() && llama_model_n_embd_out(r->draft_model) != llama_model_n_embd_out(r->model))
                why = "its hidden size does not match this model";
            if (!why.empty()) throw std::runtime_error("This MTP head is for a different model: " + why + ".");
            char buf[256];
            r->draft_name = llama_model_meta_val_str(r->draft_model, "general.name", buf, sizeof buf) >= 0 ? buf : draft.substr(draft.find_last_of("/\\") + 1);
        } else if (!draft.empty()) {
            r->draft_model = llama_model_load_from_file(draft.c_str(), dp);
            if (!r->draft_model) throw std::runtime_error("The draft model could not be loaded.");
            const auto why = draft_incompatible(r->model, r->draft_model);
            if (!why.empty()) throw std::runtime_error("Speculative decoding is off: " + why + ".");
            const auto dc = draft_context_params(r, cp);
            auto * draft_ctx = llama_init_from_model(r->draft_model, dc);
            if (r->dflash) r->mtp_ctx = draft_ctx; else r->draft_ctx = draft_ctx;
            if (!draft_ctx) throw std::runtime_error("Cannot allocate the draft model's context. Reduce context size or turn speculative decoding off.");
            r->draft_max = std::clamp(s.value("draftMaxTokens", 6), 1, 32);
            // Only recurrent state cannot drop a rejected tail; a sliding
            // window cache can, so it is not snapshot every round.
            r->draft_needs_checkpoints = llama_model_is_recurrent(r->draft_model) || llama_model_is_hybrid(r->draft_model);
            if (!r->dflash) {
                r->draft_sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
                llama_sampler_chain_add(r->draft_sampler, llama_sampler_init_greedy());
            }
            char buf[256];
            r->draft_name = llama_model_meta_val_str(r->draft_model, "general.name", buf, sizeof buf) >= 0 ? buf : draft.substr(draft.find_last_of("/\\") + 1);
        }
        r->progress->store(0.97f, std::memory_order_relaxed);
        // These are accepted context parameters, not a claim that every tensor
        // was offloaded. Upstream may place unsupported operations on the CPU.
        r->effective = {{"contextSize", llama_n_ctx(r->ctx)}, {"batchSize", llama_n_batch(r->ctx)},
            {"microBatchSize", llama_n_ubatch(r->ctx)}, {"threads", llama_n_threads(r->ctx)},
            {"batchThreads", llama_n_threads_batch(r->ctx)}, {"cpuCores", od_cpu_cores()}, {"requestedGpuLayers", mp.n_gpu_layers},
            {"gpuLayers", r->devices.size() > 1 ? std::min<int64_t>(mp.n_gpu_layers, target_meta.blocks + 1) : 0},
            {"layers", target_meta.blocks + 1},
            {"kvCacheType", kv}, {"vCacheType", vv}, {"flashAttentionPolicy", cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_ENABLED
                ? "enabled" : cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_DISABLED ? "disabled" : "auto"},
            {"contextTrain", llama_model_n_ctx_train(r->model)}, {"memory", llama_model_is_hybrid(r->model) ? "hybrid"
                : llama_model_is_recurrent(r->model) ? "recurrent" : r->n_swa > 0 ? "swa" : "kv"},
            {"ropeScaling", rope}, {"ropeFreqBase", cp.rope_freq_base}, {"ropeFreqScale", cp.rope_freq_scale},
            {"ropeFreqScaleTrain", llama_model_rope_freq_scale_train(r->model)},
            {"adapters", (int)r->adapters.size()}, {"draftModel", r->draft_name}, {"draftMaxTokens", r->draft_max},
            {"draftGpuLayers", r->draft_model ? std::min<int>(dp.n_gpu_layers, llama_model_n_layer(r->draft_model) + llama_model_n_layer_nextn(r->draft_model) + 1) : 0}};
        r->effective.update(admission);
        // Warm-up decode: GPU backends compile their kernels lazily, so a driver
        // that rejects a shader only fails here. Doing it at load time makes the
        // failure attributable (and the fallback possible) and moves the one-off
        // compile cost out of the user's first message.
        const auto * vocab = llama_model_get_vocab(r->model);
        llama_token probe = llama_vocab_bos(vocab);
        if (probe == LLAMA_TOKEN_NULL) probe = 0;
        const auto warm_started = Clock::now();
        if (llama_decode(r->ctx, llama_batch_get_one(&probe, 1)) != 0) throw std::runtime_error("Backend warm-up decode failed.");
#if !defined(__ANDROID__)
        // Desktop: also run the shapes a first message uses, so its prefill
        // and first tokens do not pay for graph building, kernel selection
        // and weights paging in (a cold 512-token step took 363 ms against
        // 134 ms warm on an RTX 3070). Strata (MIT, q36_engine.cu) warms a
        // full micro-batch, a small chunk and decode steps the same way.
        // Phones keep the single token: their load time is the scarcer.
        if (!r->embedding && s.value("warmup", true)) {
            const int ctx_room = (int)llama_n_ctx(r->ctx) - 64;
            const int full = std::min<int>((int)llama_n_ubatch(r->ctx), ctx_room / 2);
            std::vector<llama_token> filler(std::max(full, 1), probe);
            for (const int n : {full, 17, 1, 1, 1}) {
                if (n < 1) continue;
                if (llama_decode(r->ctx, llama_batch_get_one(filler.data(), n)) != 0) throw std::runtime_error("Backend warm-up decode failed.");
            }
        }
#endif
        // Before the reset, so no queued warmup work lands in the first turn's counters.
        llama_synchronize(r->ctx);
        r->effective["warmupMs"] = std::chrono::duration<double, std::milli>(Clock::now() - warm_started).count();
        llama_memory_clear(llama_get_memory(r->ctx), true);
        llama_perf_context_reset(r->ctx);
        if (r->draft_ctx) llama_memory_clear(llama_get_memory(r->draft_ctx), true);
        // A separately selected draft keeps precedence over the model's own heads.
        if (sidecar || (mp.load_mtp && !r->draft_ctx && llama_model_n_layer_nextn(r->model) > 0)) {
            auto mc = cp;
            mc.ctx_type = LLAMA_CONTEXT_TYPE_MTP;
            mc.ctx_other = r->ctx;
            mc.n_ctx = llama_n_ctx(r->ctx);
            mc.n_rs_seq = 0;
            r->mtp_ctx = llama_init_from_model(sidecar ? r->draft_model : r->model, mc);
            if (!r->mtp_ctx) throw std::runtime_error("Cannot allocate context. Reduce context size, use FP16 cache, or choose a smaller model.");
            r->draft_max = std::clamp(s.value("draftMaxTokens", 6), 1, 32);
            r->draft_p_min = std::clamp(s.value("draftMinP", 0.0f), 0.0f, 1.0f);
            reset_mtp(r);
        }
        if (r->dflash) reset_mtp(r);
        r->effective["mtp"] = (bool)r->mtp && !r->dflash;
        r->effective["speculationMode"] = r->dflash ? "dflash" : r->mtp ? "mtp" : r->draft_ctx ? "draft" : "off";
        r->effective["draftMaxTokens"] = r->draft_max;
        r->effective["draftMinP"] = r->draft_p_min;
        r->forget();
        return json();
}
static mtmd_input_chunks * tokenize_media(Runtime * r, const std::string & text, const std::vector<std::string> & images, int & n_pos);
// One pooled, L2-normalised vector from the last decode, cut to [dims]
// (Matryoshka: EmbeddingGemma 2 is trained for 768/512/256/128) and
// normalised again so cosine similarity stays a dot product. [seq] is the
// sequence the vector is pooled for and [last] its last batch row (only used
// by last-token pooling; the pooled policies answer per sequence).
static std::vector<float> pooled_seq(Runtime * r, llama_seq_id seq, int last, int dims) {
    const int n_out = llama_model_n_embd_out(r->model);
    const float * embd = llama_pooling_type(r->ctx) == LLAMA_POOLING_TYPE_NONE
        ? llama_get_embeddings_ith(r->ctx, last)
        : llama_get_embeddings_seq(r->ctx, seq);
    if (!embd) throw std::runtime_error("The model produced no embedding.");
    const int n = dims > 0 ? std::min(dims, n_out) : n_out;
    std::vector<float> out((size_t)n);
    common_embd_normalize(embd, out.data(), n, 2);
    return out;
}
static std::vector<float> pooled(Runtime * r, int last, int dims) {
    return pooled_seq(r, 0, last, dims);
}
// Several texts in ONE decode, each on its own sequence: an encoder never
// mixes sequences, and the pooling step then answers one vector per sequence.
// The memory is cleared first, so every sequence starts at position 0 and a
// later batch never reads this one. [items] must fit n_batch in total.
static std::vector<std::vector<float>> pooled_batch(Runtime * r, const std::vector<std::vector<llama_token>> & items, int dims) {
    int total = 0;
    for (const auto & tokens : items) total += (int)tokens.size();
    llama_batch batch = llama_batch_init(total, 0, (int)items.size());
    std::vector<int> last(items.size(), -1);
    int row = 0;
    for (size_t s = 0; s < items.size(); ++s) {
        for (size_t i = 0; i < items[s].size(); ++i) {
            batch.token[row] = items[s][i];
            batch.pos[row] = (llama_pos)i;
            batch.n_seq_id[row] = 1;
            batch.seq_id[row][0] = (llama_seq_id)s;
            batch.logits[row] = false;
            last[s] = row;
            ++row;
        }
    }
    batch.n_tokens = row;
    for (const int at : last) if (at >= 0) batch.logits[at] = true;
    llama_memory_clear(llama_get_memory(r->ctx), true);
    const int rc = llama_decode(r->ctx, batch);
    if (rc != 0) { llama_batch_free(batch); throw std::runtime_error("Embedding batch decode failed."); }
    std::vector<std::vector<float>> out;
    out.reserve(items.size());
    try {
        for (size_t s = 0; s < items.size(); ++s) out.push_back(pooled_seq(r, (llama_seq_id)s, last[s], dims));
    } catch (...) {
        llama_batch_free(batch);
        throw;
    }
    llama_batch_free(batch);
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
// Embeds every item of request.texts with the loaded embedding model,
// truncated to the context, pooled by the model's policy and L2-normalised so
// cosine similarity is a dot product. Text items that fit n_batch share one
// decode as distinct sequences (audit E22); a media item is decoded alone. An
// item is a string, or (ABI 7) {"text": "...", "media": ["/path.jpg",
// "/note.wav"]} for photos and recordings through the loaded projector.
// Optional request.dims cuts every vector to its leading dimensions
// (Matryoshka). Returns {"dim": n, "vectors": [[...], ...]} or null (see
// od_error). With a reranker loaded, request.pairs ([{"query", "document"},
// ...]) returns {"labels": [...], "scores": [[raw outputs], ...]} instead
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
        // Text items: exact token counts (special tokens included) and the
        // limit one input may use, without decoding. Hosts refuse over-limit
        // input with these instead of letting it be truncated below.
        const auto count_tokens = [&](const std::string & text) {
            int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, true, false);
            return count < 0 ? -count : count;
        };
        if (req.value("countOnly", false)) {
            json counts = json::array();
            for (const auto & item : req.at("texts")) counts.push_back(count_tokens(item.is_string() ? item.get<std::string>() : item.value("text", std::string())));
            r->embedded = json{{"counts", counts}, {"limit", n_ctx}}.dump();
            return r->embedded.c_str();
        }
        json vectors = json::array();
        int dim = 0;
        // A few texts ride one decode as distinct sequences when they fit
        // n_batch (audit E22): an encoder never mixes sequences and the
        // pooling step answers one vector per sequence, so this makes the
        // same vectors with less per-call overhead. Any failure keeps the
        // old one-decode-per-text path.
        // Encoders need the whole batch in one micro-batch, so n_ubatch bounds it.
        const int n_batch = std::max(1, std::min({n_ctx, (int)llama_n_batch(r->ctx), (int)llama_n_ubatch(r->ctx)}));
        bool batching = true;
        std::vector<std::vector<llama_token>> pending;
        int pending_tokens = 0;
        const auto embed_one = [&](std::vector<llama_token> & tokens) {
            llama_memory_clear(llama_get_memory(r->ctx), true);
            if (llama_decode(r->ctx, llama_batch_get_one(tokens.data(), (int)tokens.size())) != 0) throw std::runtime_error("Embedding decode failed.");
            return pooled(r, (int)tokens.size() - 1, dims);
        };
        const auto flush = [&]() {
            if (pending.empty()) return;
            if (batching && pending.size() > 1) {
                try {
                    for (auto & v : pooled_batch(r, pending, dims)) {
                        dim = (int)v.size();
                        vectors.push_back(v);
                    }
                    pending.clear();
                    pending_tokens = 0;
                    return;
                } catch (const std::exception &) {
                    if (r->cancelled->load(std::memory_order_relaxed)) throw;
                    // A model, bridge or memory module that cannot take
                    // several sequences still gets its vectors, one by one.
                    batching = false;
                }
            }
            for (auto & tokens : pending) {
                if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Embedding cancelled.");
                auto v = embed_one(tokens);
                dim = (int)v.size();
                vectors.push_back(v);
            }
            pending.clear();
            pending_tokens = 0;
        };
        for (const auto & item : req.at("texts")) {
            if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Embedding cancelled.");
            std::string text;
            if (item.is_object()) {
                std::vector<std::string> media;
                for (const auto & m : item.value("media", json::array())) media.push_back(m.get<std::string>());
                text = item.value("text", std::string());
                if (!media.empty()) {
                    // A photo or recording pools one whole sequence of its own.
                    flush();
                    auto v = embed_media(r, text, media, dims);
                    dim = (int)v.size();
                    vectors.push_back(v);
                    continue;
                }
            } else {
                text = item.get<std::string>();
            }
            // Passage text is data: special-token syntax inside it stays literal.
            const int count = count_tokens(text);
            std::vector<llama_token> tokens((size_t)count);
            int n = llama_tokenize(vocab, text.data(), text.size(), tokens.data(), count, true, false);
            if (n <= 0) throw std::runtime_error("Tokenization failed.");
            tokens.resize((size_t)std::min(n, n_ctx));
            if (!pending.empty() && (pending_tokens + (int)tokens.size() > n_batch || (int)pending.size() >= kEmbedBatchSeqs)) flush();
            pending_tokens += (int)tokens.size();
            pending.push_back(std::move(tokens));
        }
        flush();
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
// What loading [path] with [settings] would use, without loading it (additive, looked up optionally):
// the planned context, GPU layers, RAM and VRAM, plus every device and the
// RAM free now. An empty path returns the devices alone. A scratch runtime
// plans it, so the handle's loaded model is untouched.
const char * od_estimate(void * h, const char * path, const char * settings) {
    MemoryAdmission memory_admission;
    auto * r = static_cast<Runtime *>(h);
    try {
        memory_admission.check();
        auto s = settings && *settings ? json::parse(settings) : json::object();
        json out = json::object();
        if (path && *path) {
            Runtime plan(0);
            plan.planning = true;
            out = load_with(&plan, path, s, s.value("backend", "auto"), true);
        }
        json devices = json::array();
        for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
            auto dev = ggml_backend_dev_get(i);
            const auto type = ggml_backend_dev_type(dev);
            size_t free = 0, total = 0;
            ggml_backend_dev_memory(dev, &free, &total);
            devices.push_back({{"name", ggml_backend_dev_name(dev)}, {"description", ggml_backend_dev_description(dev)},
                {"supportsFp8Kv", supports_fp8_kv(dev)},
                {"backend", ggml_backend_reg_name(ggml_backend_dev_backend_reg(dev))},
                {"type", type == GGML_BACKEND_DEVICE_TYPE_GPU ? "gpu" : type == GGML_BACKEND_DEVICE_TYPE_IGPU ? "igpu"
                    : type == GGML_BACKEND_DEVICE_TYPE_CPU ? "cpu" : "accel"},
                {"freeMb", (int64_t)(free >> 20)}, {"totalMb", (int64_t)(total >> 20)}});
        }
        const SystemMemory ram = system_memory();
        out["devices"] = devices;
        out["ramAvailableMb"] = ram.available >> 20;
        out["ramTotalMb"] = ram.total >> 20;
        std::lock_guard<std::mutex> use(r->use);
        // Free memory was read with this model still in it; a load frees
        // it first, so the app says the estimate is pessimistic.
        out["modelLoaded"] = r->model != nullptr;
        r->estimate = out.dump();
        return r->estimate.c_str();
    } catch (const std::exception & e) {
        std::lock_guard<std::mutex> use(r->use);
        r->error = e.what();
        return nullptr;
    }
}
int32_t od_load(void * h, const char * path, const char * settings) {
    MemoryAdmission memory_admission;
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    struct FinishProgress {
        std::atomic<float> & progress;
        ~FinishProgress() { progress.store(-1.0f, std::memory_order_relaxed); }
    } finish{*r->progress};
    try {
        memory_admission.check();
        if (r->released) throw std::runtime_error(released_message);
        r->unload(); r->error.clear(); r->prompt.clear(); r->generated = 0; r->trimmed = 0; r->first_ms = 0;
        r->progress->store(0.0f, std::memory_order_relaxed);
        auto s = json::parse(settings);
        const std::string requested = s.value("backend", "auto");
        if (requested == "qnn") throw std::runtime_error("QNN is not integrated in this build. Select Auto or CPU.");
        try {
            try {
                load_with(r, path, s, requested);
            } catch (const std::exception & e) {
                const std::string reason = e.what();
                const bool speculation_error = reason.find("OD_DRAFT_REQUIRED") != std::string::npos
                    || reason.find("OD_DFLASH_") != std::string::npos
                    || reason.find("OD_SPEC_MODE") != std::string::npos
                    || reason.find("Speculative decoding is off:") != std::string::npos
                    || reason.find("draft model could not be loaded") != std::string::npos
                    || reason.find("draft model's context") != std::string::npos;
                if (!speculation_error || r->cancelled->load(std::memory_order_relaxed)) throw;
                r->unload();
                s["speculationMode"] = "off"; s["draftModel"] = ""; s["mtp"] = false;
                load_with(r, path, s, requested);
                r->fallback_reason = "Speculative decoding disabled: " + reason + " Using normal decoding.";
            }
        } catch (const std::exception & e) {
            // A GPU driver can reject shaders while the device is enumerated or
            // the context is created (Adreno + Vulkan does). With Auto we retry
            // on the CPU and report why; if that also fails, the CPU error is
            // the real one and propagates.
            if (requested != "auto" || r->cancelled->load(std::memory_order_relaxed)) throw;
            std::string reason = e.what();
            r->unload();
            r->progress->store(0.0f, std::memory_order_relaxed);
            load_with(r, path, s, "cpu");
            r->fallback_reason = reason;
            r->backend = "CPU (GPU unavailable: " + reason + ")";
        }
        r->progress->store(1.0f, std::memory_order_relaxed);
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
                          const std::vector<common_chat_tool> & tools = {}, const std::string & tool_choice = "auto", common_chat_params * params_out = nullptr, const std::string & json_schema = "") {
    if (generation) { r->forced_open = false; r->think_start.clear(); r->think_ends.clear(); }
    // With no usable template or family fallback, let common choose ChatML.
    if (!r->templates && fallback.empty() && r->model) {
        r->templates = common_chat_templates_init(r->model, "");
    }
    if (r->templates) {
        common_chat_templates_inputs inputs;
        for (const auto & m : messages) inputs.messages.push_back(message_of(m));
        if (!json_schema.empty()) {
            auto schema = common_json::parse(json_schema);
            // Like llama-server, make JSON-object mode nonempty for handlers.
            if (schema.is_object() && schema.empty()) schema["type"] = "object";
            inputs.json_schema = schema.dump();
        }
        inputs.enable_thinking = thinking;
        inputs.reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK;
        inputs.add_generation_prompt = generation;
        if (!tools.empty()) {
            inputs.tools = tools;
            inputs.tool_choice = tool_choice == "required" ? COMMON_CHAT_TOOL_CHOICE_REQUIRED
                : tool_choice == "none" ? COMMON_CHAT_TOOL_CHOICE_NONE : COMMON_CHAT_TOOL_CHOICE_AUTO;
            inputs.parallel_tool_calls = false;
        }
        common_chat_params params;
        try { params = common_chat_templates_apply(r->templates.get(), inputs); }
        catch (const std::exception & e) {
            // Analysis can fail even when Jinja renders this conversation.
            const std::string why = e.what();
            inputs.force_pure_content = true;
            params = common_chat_templates_apply(r->templates.get(), inputs);
            r->template_probe_error = why;
        }
        const auto prompt = params.prompt.str();
        if (!generation) return prompt;
        r->think_start = params.thinking_start_tag; r->think_ends = params.thinking_end_tags;
        // Some templates open the reasoning block inside the prompt itself, so the
        // model never emits the opening tag. The output parser consumes it.
        r->forced_open = params.supports_thinking && ends_with_tag(params.generation_prompt, params.thinking_start_tag);
        if (params_out) *params_out = params;
        return prompt;
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
// [add_special] adds BOS/EOS as the tokenizer asks; text injected mid-turn
// passes false, or a Gemma answer gets a BOS in its middle.
static std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & text, bool add_special = true) {
    int count = llama_tokenize(vocab, text.data(), text.size(), nullptr, 0, add_special, true);
    if (count < 0) count = -count;
    std::vector<llama_token> out(count);
    int n = llama_tokenize(vocab, text.data(), text.size(), out.data(), count, add_special, true);
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
// After dropping the tail from position [keep], a sliding window must still
// hold the n_swa positions before the cut (same rule as llama-server). An
// emptied window reports -1, which is not "everything kept": a long answer
// pushes the start out of the window, and keeping the prefix anyway left the
// model without the question (2026-10-28: a new chat repeating an earlier
// question was answered as if nothing had been asked).
static bool window_holds(llama_memory_t mem, int n_swa, int keep) {
    const llama_pos lo = llama_memory_seq_pos_min(mem, 0);
    return lo >= 0 && lo <= std::max(0, keep - n_swa) && llama_memory_seq_pos_max(mem, 0) == keep - 1;
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
        if (ok && r->n_swa > 0 && !r->swa_full) ok = window_holds(mem, r->n_swa, keep_pos);
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
    r->media_keep = keep; r->media_keep_pos = keep_pos;
    // cachedPromptTokens is in KV positions, like promptTokens: the flat
    // prefix can be shorter or longer than the positions its images take.
    r->reused = (int)keep_pos; r->cursor = 0;
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
// Adds the time until scope exit to a counter, on success or exception.
struct AddElapsed {
    double & ms;
    Clock::time_point from = Clock::now();
    ~AddElapsed() { ms += std::chrono::duration<double, std::milli>(Clock::now() - from).count(); }
};
static void take_checkpoint(Runtime * r, int pos) {
    // Finish queued GPU work first so it counts as reading, not copying.
    llama_synchronize(r->ctx);
    AddElapsed timed{r->checkpoint_ms};
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
static int shared_prefix(const std::vector<llama_token> & a, const std::vector<llama_token> & b, int limit) {
    limit = std::min({limit, (int)a.size(), (int)b.size()});
    int n = 0;
    while (n < limit && a[n] == b[n]) ++n;
    return n;
}
// [pin] (tokens of the entry about to be restored) is never evicted (P3-09).
static void trim_store(Runtime * r, const std::vector<llama_token> * pin = nullptr) {
    size_t total = 0;
    for (const auto & s : r->store) total += s.bytes();
    auto used = [&](size_t i) { return r->store[i].used; };
    auto pinned = [&](size_t i) { return pin && r->store[i].tokens == *pin; };
    while (total > r->store_limit && !r->store.empty()) {
        const int oldest = od_prompt_store::lru_victim(r->store.size(), used, pinned);
        if (oldest < 0) break;
        total -= r->store[(size_t)oldest].bytes();
        r->store.erase(r->store.begin() + oldest);
    }
}
// Saves the resident sequence before a new prompt replaces it, with the
// MTP head's own sequence state (llama-server stores both). Photo turns
// (placeholder tokens) are not stored.
static void store_resident(Runtime * r, const std::vector<llama_token> * pin = nullptr) {
    if (r->store_limit == 0 || r->cached.size() < Runtime::store_min || !r->media_meta.empty()) return;
    if (std::find(r->cached.begin(), r->cached.end(), LLAMA_TOKEN_NULL) != r->cached.end()) return;
    // A stored sequence the resident one extends is superseded by it.
    r->store.erase(std::remove_if(r->store.begin(), r->store.end(), [&](const Runtime::Stored & s) {
        return s.tokens.size() <= r->cached.size() && std::equal(s.tokens.begin(), s.tokens.end(), r->cached.begin());
    }), r->store.end());
    const size_t size = llama_state_seq_get_size(r->ctx, 0);
    const size_t head = r->mtp_ctx ? llama_state_seq_get_size(r->mtp_ctx, 0) : 0;
    size_t marks = 0;
    for (const auto & checkpoint : r->checkpoints) marks += checkpoint.data.size();
    const size_t entry = od_prompt_store::entry_bytes(size, head, marks, r->cached.size());
    // Charge the whole entry, checkpoints and token ids included, and make room
    // before allocating its state: evicting after the copy would hold the old
    // entries and the new snapshot at once, above the cap. The store is only a
    // cache, so a copy that cannot join the process-wide allocation
    // transaction now, or that the live host budget cannot take, is skipped
    // rather than waited for behind an unrelated long allocation.
    if (size == 0 || !od_prompt_store::admits(r->store_limit, entry)) return;
    MemoryAdmission admission(false);
    if (!admission.held()) return;
    if (entry > MemoryAdmission::host_budget()) return;
    size_t total = 0;
    for (const auto & s : r->store) total += s.bytes();
    auto used = [&](size_t i) { return r->store[i].used; };
    auto pinned = [&](size_t i) { return pin && r->store[i].tokens == *pin; };
    while (!od_prompt_store::fits(r->store_limit, total, entry)) {
        const int oldest = od_prompt_store::lru_victim(r->store.size(), used, pinned);
        if (oldest < 0) return;
        total -= r->store[(size_t)oldest].bytes();
        r->store.erase(r->store.begin() + oldest);
    }
    Runtime::Stored s{r->cached, std::vector<uint8_t>(size), std::vector<uint8_t>(head), r->checkpoints, 0};
    if (s.bytes() > r->store_limit) return;
    if (llama_state_seq_get_data(r->ctx, s.state.data(), size, 0) != size) return;
    if (head && llama_state_seq_get_data(r->mtp_ctx, s.head.data(), head, 0) != head) return;
    s.used = ++r->store_clock;
    r->store.push_back(std::move(s));
}
// Decides how much of the resident sequence survives for the new prompt.
static void reuse_prefix(Runtime * r, bool enabled) {
    // Stored target snapshots do not contain DFlash's injected draft KV.
    // Replay prefill to capture every target feature for each new prompt.
    if (r->dflash) {
        llama_memory_clear(llama_get_memory(r->ctx), true);
        reset_mtp(r); r->forget(); r->store.clear();
        r->store_restored = r->cursor = r->reused = 0;
        return;
    }
    auto mem = llama_get_memory(r->ctx);
    const int limit = (int)r->prompt.size() - 1;
    int keep = enabled ? shared_prefix(r->cached, r->prompt, limit) : 0;
    r->store_restored = 0;
    if (enabled && r->store_limit > 0) {
        // A stored sequence sharing clearly more than the resident one is
        // swapped in (the resident one is stored first); otherwise the
        // resident one is stored when most of it is about to be dropped.
        int best = -1, best_len = keep + (int)Runtime::store_gain;
        for (size_t i = 0; i < r->store.size(); ++i) {
            const int n = shared_prefix(r->store[i].tokens, r->prompt, limit);
            if (n >= best_len) { best = (int)i; best_len = n; }
        }
        const auto chosen = best >= 0 ? r->store[best].tokens : std::vector<llama_token>();
        if (best >= 0 || keep + (int)Runtime::store_gain < (int)r->cached.size()) store_resident(r, best >= 0 ? &chosen : nullptr);
        if (best >= 0) {
            // store_resident may have reordered the store: find it again.
            auto it = std::find_if(r->store.begin(), r->store.end(), [&](const Runtime::Stored & s) { return shared_prefix(s.tokens, r->prompt, limit) == best_len; });
            if (r->mtp_ctx) llama_memory_clear(llama_get_memory(r->mtp_ctx), true);
            llama_memory_clear(mem, true);
            r->forget();
            if (it != r->store.end() && llama_state_seq_set_data(r->ctx, it->state.data(), it->state.size(), 0) == it->state.size()
                && (it->head.empty() || llama_state_seq_set_data(r->mtp_ctx, it->head.data(), it->head.size(), 0) == it->head.size())) {
                r->cached = it->tokens; r->checkpoints = it->marks; it->used = ++r->store_clock;
                keep = best_len; r->store_restored = keep;
            } else {
                llama_memory_clear(mem, true);
                keep = 0;
            }
        }
    }
    bool ok = keep > 0;
    if (ok) {
        // Plain KV caches drop a tail; recurrent/hybrid memories refuse unless a
        // bounded rollback covers it; a sliding window must still hold the
        // n_swa tokens before the cut (window_holds).
        ok = llama_memory_seq_rm(mem, 0, keep, -1);
        if (ok && r->n_swa > 0 && !r->swa_full) ok = window_holds(mem, r->n_swa, keep);
        // The MTP driver has no snapshot of its own to roll back with.
        if (!ok && !r->mtp) {
            const int pos = restore_checkpoint(r, keep);
            ok = pos > 0; if (ok) keep = pos;
        }
    }
    if (!ok) { llama_memory_clear(mem, true); keep = 0; }
    r->store_restored = std::min(r->store_restored, keep);
    if (r->mtp) {
        // The head reads the target's KV, and the suffix prefill refreshes
        // its hidden row, so the kept prefix stays valid (llama-server drops
        // the same tail from both contexts). Nothing kept: start it afresh.
        if (keep == 0 || !llama_memory_seq_rm(llama_get_memory(r->mtp_ctx), 0, keep, -1)) {
            if (keep > 0) { llama_memory_clear(mem, true); keep = 0; }
            reset_mtp(r);
        }
    }
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
// Requested output and prompt reservation are independent. The caller supplies
// the actual context left after tokenization (or the shift policy ceiling).
static int answer_limit(const json & s, int available, int default_maximum = 1024) {
    return std::min(std::clamp(s.value("maxTokens", default_maximum), 1, 1048576), std::max(1, available));
}

// Older callers send only maxTokens, retaining their original reservation.
static int response_reserve(const json & s, int context, int default_maximum = 1024) {
    return std::clamp(s.value("reservedTokens", s.value("maxTokens", default_maximum)), 1, context - 1);
}
// Thinking comes on top of the answer reserve, up to its budget and at most
// a quarter of the context.
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
        const int reserve = std::min(response_reserve(s, context) + think_room(s, context), context - 1);
        r->preview = json{{"formattedPrompt", text}, {"promptTokens", count}, {"contextSize", context},
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
    // Samplers llama.cpp can run on the backend; any other one keeps the chain on the CPU.
    r->sampler_offloadable = grammar.empty() && s.value("dryMultiplier", 0.0f) <= 0;
    std::vector<llama_logit_bias> biases;
    json effective_bias = json::object();
    const auto raw_bias = s.value("logitBias", json::object());
    if (raw_bias.is_object()) for (auto it = raw_bias.begin(); it != raw_bias.end(); ++it) {
        try {
            size_t used = 0;
            const int token = std::stoi(it.key(), &used);
            if (used != it.key().size() || token < 0 || token >= llama_vocab_n_tokens(vocab) || !it.value().is_number()) continue;
            const float bias = it.value().get<float>();
            if (!std::isfinite(bias)) continue;
            biases.push_back({token, bias}); effective_bias[it.key()] = bias;
        } catch (const std::exception &) {}
    }
    if (!biases.empty()) llama_sampler_chain_add(r->sampler,
        llama_sampler_init_logit_bias(llama_vocab_n_tokens(vocab), (int)biases.size(), biases.data()));
    r->effective["logitBias"] = effective_bias;
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
        // A disabled penalty still refuses backend initialization when the
        // context supports multiple output rows (speculative verification).
        // Omit the no-op so greedy sampling stays entirely on the device.
        if (last_n == 0 || (s.value("repetitionPenalty", 1.0f) == 1.0f &&
            s.value("frequencyPenalty", 0.0f) == 0.0f && s.value("presencePenalty", 0.0f) == 0.0f)) return;
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
        else if (name == "top_n_sigma") { if (s.value("topNSigma", -1.0f) > 0) r->sampler_offloadable = false, llama_sampler_chain_add(r->sampler, llama_sampler_init_top_n_sigma(s.value("topNSigma", -1.0f))); }
        else if (name == "top_k") { if (s.value("topK", 40) > 0) llama_sampler_chain_add(r->sampler, llama_sampler_init_top_k(s.value("topK", 40))); }
        else if (name == "typ_p") { if (s.value("typicalP", 1.0f) < 1.0f) r->sampler_offloadable = false, llama_sampler_chain_add(r->sampler, llama_sampler_init_typical(s.value("typicalP", 1.0f), 1)); }
        else if (name == "top_p") llama_sampler_chain_add(r->sampler, llama_sampler_init_top_p(s.value("topP", .95f), 1));
        else if (name == "min_p") llama_sampler_chain_add(r->sampler, llama_sampler_init_min_p(s.value("minP", .05f), 1));
        else if (name == "xtc") { if (s.value("xtcProbability", 0.0f) > 0) r->sampler_offloadable = false, llama_sampler_chain_add(r->sampler, llama_sampler_init_xtc(s.value("xtcProbability", 0.0f), s.value("xtcThreshold", 0.1f), 1, seed)); }
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
    AddElapsed timed{r->sample_ms};
    if (r->backend_sampled) {
        const llama_token t = llama_get_sampled_token_ith(r->ctx, idx);
        if (t != LLAMA_TOKEN_NULL) { llama_sampler_accept(r->sampler, t); return t; }
    }
    AddElapsed cpu_timed{r->sample_cpu_ms};
    ++r->sample_cpu_tokens;
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
// Some template handlers render JSON requests without supplying a grammar.
// This grammar constrains generated text only, without template prefill/triggers.
static std::string json_grammar_fallback(const common_chat_params & params, const std::string & schema) {
    if (schema.empty() || !params.grammar.empty()) return "";
    try {
        auto parsed = common_json::parse(schema);
        if (parsed.is_object() && parsed.empty()) parsed["type"] = "object";
        return json_schema_to_grammar(parsed, true);
    } catch (const std::exception & e) {
        throw std::runtime_error(std::string("The JSON schema could not be turned into a grammar: ") + e.what());
    }
}
// Reasoning-budget tracking shared by the chat context and helper sequences
// (audit E08): the block is recognised from the emitted text with the model's
// own delimiters, so the budget only counts thinking.
static void track_reasoning(const std::string & start, const std::vector<std::string> & ends,
                            const std::string & piece, int & tokens, int & counted, bool & in_think, std::string & tail) {
    tail += piece;
    const std::string opening = start.empty() ? "<think>" : start;
    if (!in_think && tail.find(opening) != std::string::npos) { in_think = true; tail.clear(); ++counted; }
    else if (in_think) {
        ++tokens; ++counted;
        bool closed = ends.empty() && tail.find("</think>") != std::string::npos;
        for (const auto & end : ends) closed = closed || tail.find(end) != std::string::npos;
        if (closed) { in_think = false; tail.clear(); }
    }
    if (tail.size() > 64) tail.erase(0, tail.size() - 64);
}
// What the model sees when its reasoning budget is spent: a closing sentence
// (a bare tag left small models reasoning on, owner, 2026-09-24) and the
// template's own end tag. Helper sequences write the same hand-off (audit E08).
static std::string reasoning_handoff(const std::vector<std::string> & ends) {
    return "\n\nConsidering the limited time by the user, I have to give the solution based on the thinking directly now.\n"
        + (ends.empty() ? std::string("</think>") : ends.front()) + "\n\n";
}
#include "side_batch.inc"

// Drops [steps] of the oldest exchanges after the system prompt, but
// never the current question or anything after it: in a tool round
// the tail is [user, assistant(tool_calls), tool...] and a chat
// template refuses a conversation without a user message. False
// when that many cannot be dropped.
// Scan exchange boundaries once, then compact the array once. On failure,
// preserve the old behavior of dropping every exchange that was available.
static bool drop_oldest_exchanges(json & m, int steps, int & erased) {
    const size_t head = !m.empty() && m[0].value("role", "") == "system" ? 1 : 0;
    size_t last_user = m.size();
    for (size_t i = m.size(); i-- > 0;)
        if (m[i].value("role", "") == "user") { last_user = i; break; }
    size_t end = head;
    int dropped = 0;
    while (dropped < steps && last_user != m.size() && end < last_user) {
        ++end;
        while (end < last_user && m[end].value("role", "") != "user") ++end;
        ++dropped;
    }
    if (end > head) {
        m.erase(m.begin() + head, m.begin() + end);
        erased += static_cast<int>(end - head);
    }
    return dropped >= steps;
}

int32_t od_begin(void * h, const char * request) {
    const auto begin_started = Clock::now();
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> use(r->use);
    // Reset first so a rejected request never shows the previous turn's times.
    r->begin_ms = r->prefill_ms = r->checkpoint_ms = r->sample_ms = r->sample_cpu_ms = 0;
    r->sample_cpu_tokens = 0;
    AddElapsed setup{r->begin_ms, begin_started};
    try {
        if (r->released) throw std::runtime_error(released_message);
        if (!r->ctx) throw std::runtime_error("No model loaded.");
        if (r->embedding) throw std::runtime_error("This is an embedding model; it cannot chat.");
        auto req = json::parse(request); auto s = req.at("settings"); auto messages = req.at("messages");
        r->reset(); r->error.clear(); r->trimmed = 0; r->generated = 0; r->first_ms = 0;
        r->held.clear(); r->flush_only = false; r->finish.clear(); r->stops.clear();
        r->tools_active = false; r->generated_text.clear(); r->tool_calls = json::array(); r->tool_format.clear(); r->tool_content.clear();
        r->draft_proposed = r->draft_accepted = r->draft_rounds = 0; r->draft_replays = 0;
        r->draft_disabled = r->draft_losses >= Runtime::draft_give_up;
        r->plain_ms = r->spec_ms = r->draft_ms = 0; r->plain_steps = r->spec_tokens = 0;
        r->parser = common_chat_parser_params();
        r->parser_active = false; r->parser_finished = false; r->output_thinking = false;
        r->generated_input = {}; r->parsed_msg = {}; r->parsed_output.clear(); r->parse_error.clear();
        r->parsed_raw_length = r->streamed_raw_length = 0; r->parsed_at = {};
        const int n_ctx = (int)llama_n_ctx(r->ctx);
        r->context_overflow = s.value("contextOverflow", "trim");
        if (r->context_overflow != "shift" && r->context_overflow != "stop") r->context_overflow = "trim";
        if (r->context_overflow == "shift" && (llama_model_is_recurrent(r->model) || llama_model_is_hybrid(r->model)
            || !images_of(messages).empty() || !llama_memory_can_shift(llama_get_memory(r->ctx)))) r->context_overflow = "trim";
        r->keep_tokens = std::clamp(s.value("keepTokens", 0), 0, n_ctx - 2);
        r->effective["contextOverflow"] = r->context_overflow;
        r->effective["keepTokens"] = r->keep_tokens;
        if (r->context_overflow == "shift") r->draft_disabled = true;
        r->maximum = answer_limit(s, r->context_overflow == "shift" ? 1048576 : n_ctx - 1);
        const int answer_reserve = response_reserve(s, n_ctx);
        // Raw GBNF constrains generated bytes; JSON uses the template protocol.
        const std::string format = s.value("responseFormat", "text");
        const auto tools = tools_of(req);
        const std::string tool_choice = req.value("toolChoice", "auto");
        const bool thinking = s.value("thinkingModeEnabled", false) && format != "gbnf";
        const std::string json_schema = format == "json" || format == "json_schema"
            ? (format == "json" || s.value("jsonSchema", "").empty() ? "{}" : s.value("jsonSchema", "")) : "";
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
        r->prompt_positions = r->media_positions = r->shifted_positions = 0;
        std::vector<std::string> images;
        common_chat_params chat_params;
        // The cut is searched (doubling, then halving) instead of dropping
        // one exchange per render: O(log n) renders on a long chat (P3-08).
        int fail = -1, fit = -1, steps = 0;
        while (true) {
            auto text = render(r, messages, fallback, thinking, true, tools, tool_choice, &chat_params, json_schema);
            const auto rendered = text;
            text = with_prefix(r, std::move(text), prefix);
            if (r->templates) chat_params.generation_prompt += text.substr(rendered.size());
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
            const bool fits = count + (r->context_overflow == "trim" ? std::min(answer_reserve + thinking_room, n_ctx - 1) : 1) <= n_ctx;
            if (fits) fit = steps; else fail = steps;
            if (fits && fit == fail + 1) { r->media_tokens = images.empty() ? 0 : count; prompt_count = count; break; }
            int next = fit < 0 ? std::max(1, fail * 2) : fit == fail + 1 ? fit : fail + (fit - fail) / 2;
            json cut = original;
            int erased = 0;
            if (fit < 0 && !drop_oldest_exchanges(cut, next, erased)) {
                // Fewer than [next] exchanges can be dropped: try the most.
                cut = original; erased = 0;
                int most = 0;
                const size_t head = !original.empty() && original[0].value("role", "") == "system" ? 1 : 0;
                for (size_t i = head + 1; i < original.size(); ++i)
                    if (original[i].value("role", "") == "user") ++most;
                cut = original; erased = 0;
                if (most > fail) { next = most; drop_oldest_exchanges(cut, next, erased); }
                else next = -1;
            } else if (fit >= 0) {
                drop_oldest_exchanges(cut, next, erased);
            }
            if (next >= 0) { steps = next; messages = std::move(cut); r->trimmed = erased; continue; }
            {
                if (thinking_room > 0) { thinking_room = 0; messages = original; r->trimmed = 0; fail = -1; fit = -1; steps = 0; continue; }
                const bool tools_in_play = std::any_of(messages.begin(), messages.end(), [](const json & m) { return m.value("role", "") == "tool"; });
                throw std::runtime_error(tools_in_play
                    ? "Tool results plus the response budget exceed the context. Raise the context size, lower the per-tool output budget or reduce max tokens."
                    : "Message plus response budget exceeds context. Shorten the message or reduce max tokens.");
            }
        }
        // Rendered prompt size in KV positions, not flat tokens: tokenization
        // returns the media position count for a photo turn (audit E26).
        r->prompt_positions = prompt_count;
        // Trim and stop end at the context limit; shift can reclaim KV space.
        // The reasoning ends at its budget, or where only the answer's room
        // (plus the hand-off) is left: an unlimited budget still leaves the
        // answer its reserved room.
        r->total_cap = r->context_overflow == "shift" ? 1048576 + 65536 : std::max(1, n_ctx - prompt_count - 1);
        if (r->context_overflow != "shift") r->maximum = std::min(r->maximum, r->total_cap);
        if (thinking) {
            const int left = std::max(1, r->total_cap - answer_reserve - 64);
            const int budget = std::max(0, s.value("thinkingBudgetTokens", 0));
            r->think_budget = budget > 0 ? std::min(budget, left) : left;
        }
        if (!images.empty()) {
            reuse_media_prefix(r, s.value("promptCache", true));
            // Positions the image/audio chunks take, apart from the text
            // tokens sharing the rendered prompt (audit E26).
            for (const auto & m : r->media_meta_next) r->media_positions += (int)m.n_pos;
            r->media_positions = std::min(r->media_positions, r->prompt_positions);
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
#ifdef __ANDROID__
            constexpr int store_default = 0;
#else
            constexpr int store_default = 1024;
#endif
            int store_mb = s.value("promptStoreMb", -1);
            if (store_mb < 0) store_mb = store_default;
            r->store_limit = (size_t)std::clamp(store_mb, 0, 65536) << 20;
            trim_store(r);
            reuse_prefix(r, s.value("promptCache", true));
        }
        r->checkpoint_at.clear();
        // reuse_prefix cannot restore these partial snapshots with an active
        // MTP driver (its hidden-state carryover is not in the snapshot).
        // Avoid copying unusable recurrent/SWA state before the first token.
        if (r->needs_checkpoints && !r->mtp && images.empty()) {
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
        else if (!json_schema.empty() && chat_params.grammar.empty()) {
            grammar = json_grammar_fallback(chat_params, json_schema);
        } else if (r->templates && !chat_params.grammar.empty()) {
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
        if (r->templates) {
            r->tools_active = !tools.empty();
            r->parser_active = format != "gbnf";
            r->parser = common_chat_parser_params(chat_params);
            r->parser.parser = chat_params.parser;
            r->parser.generation_prompt = common_chat_input_tokenize(vocab, chat_params.generation_prompt);
            // A continuation's existing answer must not be streamed again.
            if (r->parser_active && !prefix.empty()) {
                try { r->parsed_msg = common_chat_parse({}, true, r->parser); }
                catch (const std::exception &) {} // Retry with generated text.
            }
            r->tool_format = common_chat_format_name(chat_params.format);
            for (const auto & st : chat_params.additional_stops) if (!st.empty()) r->stops.push_back(st);
        }
        build_sampler(r, s, grammar, lazy, patterns, trigger_tokens, chat_params.generation_prompt, prefill);
        // The prompt primes the repetition penalties only. The grammar must
        // not see it: chat templates quote tool-call examples in the system
        // prompt, which would fire a lazy grammar's trigger mid-prompt.
        for (auto token : r->prompt) llama_sampler_accept(r->sampler, token);
#ifdef __ANDROID__
        const bool backend_sampling = s.value("backendSampling", false);   // not yet measured on phone GPUs
#else
        const bool backend_sampling = s.value("backendSampling", true);    // RTX 3070: +2.4% plain, +1.6% MTP, same tokens
#endif
        // Verification samples rows sequentially, accepting each token before
        // applying history-dependent samplers to the next row. A backend
        // sampler runs the whole batch before those accepts and can consume
        // RNG state for rejected rows. Use host sampling for every spec mode.
        r->backend_sampled = backend_sampling && !r->draft_ctx && !r->mtp
            && r->sampler_offloadable && llama_set_sampler(r->ctx, 0, r->sampler);
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
static bool emit_piece(Runtime * r, const std::string & piece, llama_token token = LLAMA_TOKEN_NULL) {
    if (r->think_budget > 0)
        // Track the reasoning block from the emitted text so the budget only
        // counts thinking; models that open the block themselves included.
        track_reasoning(r->think_start, r->think_ends, piece, r->think_tokens, r->reasoning, r->in_think, r->tail);
    // [held] is always a suffix of [generated_text], so a stop found in one
    // is cut from both by the same amount.
    r->held += piece;
    r->generated_text += piece;
    if (r->parser_active) r->generated_input.append(piece, token);
    for (const auto & st : r->stops) {
        const size_t at = r->held.find(st);
        if (at != std::string::npos) {
            const size_t cut = r->held.size() - at;
            r->held.erase(at);
            r->generated_text.erase(r->generated_text.size() - cut);
            if (r->parser_active) r->generated_input.truncate(r->generated_text.size());
            return false;
        }
    }
    return true;
}
// Keep protocol text in the native parser; Dart receives canonical channels.
static void parse_output(Runtime * r, bool final) {
    if (!r->parser_active || r->parser_finished) return;
    const size_t keep = final ? 0 : hold_length(r);
    const size_t length = r->generated_input.size() - keep;
    // An unchanged buffer is never reparsed (callers drain small buffers).
    // Each parse reads the whole answer, so ordinary text waits for 64 bytes
    // or 30 ms, whichever comes first; the first visible text, protocol
    // boundaries and the end parse at once. Byte-only batching delayed the
    // first words from 95 to 336 ms and streamed slow models in lumps; full
    // parsing on every token cost under 1% at 60 tok/s.
    if (!final && length == r->parsed_raw_length) return;
    const auto now = Clock::now();
    if (!final && !r->parsed_msg.empty() && length > r->parsed_raw_length &&
        length - r->parsed_raw_length < 64 && now - r->parsed_at < std::chrono::milliseconds(30) &&
        r->generated_text.find_first_of("\n<>{}", r->parsed_raw_length) >= length) return;
    r->parsed_raw_length = length;
    r->parsed_at = now;
    try {
        auto msg = common_chat_parse(r->generated_input.substr(0, length), !final, r->parser);
        if (final && msg.empty() && !r->generated_text.empty())
            throw std::runtime_error("Template parser returned no message for nonempty output.");
        if (!msg.empty()) {
            auto cover_raw = [&](const std::string & delta) {
                // Deltas omit protocol markers. Locate their raw bytes rather
                // than counting canonical <think> tags or a continuation's
                // prefill. Only visible deltas advance the fallback boundary;
                // a partial parser can leave an unparsed tail in this input.
                const auto at = r->generated_text.find(delta, r->streamed_raw_length);
                r->streamed_raw_length = at != std::string::npos && at + delta.size() <= length
                    ? at + delta.size() : length; // A mapper may sanitize text.
            };
            for (const auto & diff : common_chat_msg_diff::compute_diffs(r->parsed_msg, msg)) {
                if (!diff.reasoning_content_delta.empty()) {
                    if (!r->output_thinking) { r->parsed_output += "<think>"; r->output_thinking = true; }
                    r->parsed_output += diff.reasoning_content_delta;
                    cover_raw(diff.reasoning_content_delta);
                }
                if (!diff.content_delta.empty()) {
                    if (r->output_thinking) { r->parsed_output += "</think>"; r->output_thinking = false; }
                    r->parsed_output += diff.content_delta;
                    cover_raw(diff.content_delta);
                }
            }
            r->parsed_msg = std::move(msg);
        }
    } catch (const std::exception & e) {
        // A partial prefix can be incomplete. Retry with the finished turn.
        if (!final) return;
        r->parse_error = e.what();
        if (r->output_thinking) { r->parsed_output += "</think>"; r->output_thinking = false; }
        r->parsed_output += r->generated_text.substr(std::min(r->streamed_raw_length, r->generated_text.size()));
    }
    if (final) {
        if (r->output_thinking) { r->parsed_output += "</think>"; r->output_thinking = false; }
        r->parser_finished = true;
        r->tool_calls = json::array();
        if (r->parse_error.empty()) for (const auto & c : r->parsed_msg.tool_calls)
            r->tool_calls.push_back({{"id", c.id}, {"name", c.name}, {"arguments", c.arguments}});
        r->tool_content = r->parse_error.empty() ? r->parsed_msg.content : r->generated_text;
    }
    r->held.erase(0, r->held.size() - keep);
}
// Moves the sendable text to the caller's buffer, retaining partial stops.
static int flush(Runtime * r, uint8_t * output, int32_t capacity, bool all) {
    if (r->parser_active) {
        parse_output(r, all);
        const size_t n = std::min(r->parsed_output.size(), (size_t)capacity);
        std::copy_n(r->parsed_output.begin(), n, reinterpret_cast<char *>(output));
        r->parsed_output.erase(0, n);
        return (int)n;
    }
    const size_t keep = all ? 0 : hold_length(r);
    const size_t n = std::min(r->held.size() - keep, (size_t)capacity);
    std::copy(r->held.begin(), r->held.begin() + n, reinterpret_cast<char *>(output));
    r->held.erase(0, n);
    return (int)n;
}
static void finish_tools(Runtime * r) { parse_output(r, true); }
// Preserve the prefix and compact the oldest remaining KV entries.
static bool make_context_room(Runtime * r, int required) {
    const int size = (int)r->cached.size(), context = (int)llama_n_ctx(r->ctx);
    if (r->context_overflow != "shift" || size + required < context) return true;
    const int keep = std::min(r->keep_tokens, size - 1);
    const int discard = std::max(size + required - context + 1, std::max(1, (size - keep) / 2));
    if (discard > size - keep) return false;
    auto mem = llama_get_memory(r->ctx);
    if (!llama_memory_seq_rm(mem, 0, keep, keep + discard)) return false;
    llama_memory_seq_add(mem, 0, keep + discard, -1, -discard);
    if (r->mtp_ctx) {
        // The MTP head keeps its own cache at the target's positions.
        auto head = llama_get_memory(r->mtp_ctx);
        if (!llama_memory_seq_rm(head, 0, keep, keep + discard)) { llama_memory_clear(head, true); reset_mtp(r); }
        else llama_memory_seq_add(head, 0, keep + discard, -1, -discard);
    }
    r->cached.erase(r->cached.begin() + keep, r->cached.begin() + keep + discard);
    r->checkpoints.clear();
    // od_info reports the positions still resident, so a shifted turn must
    // not keep counting what this dropped from the KV cache (audit E26).
    r->shifted_positions += discard;
    return true;
}
// Decodes [tokens] into the target one batch at a time and records them.
static void decode_into_target(Runtime * r, const std::vector<llama_token> & tokens) {
    for (size_t i = 0; i < tokens.size(); i += (size_t)r->batch) {
        int n = std::min((int)(tokens.size() - i), r->batch);
        if (decode_target(r, llama_batch_get_one(const_cast<llama_token *>(tokens.data()) + i, n)) != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
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
    if (r->mtp) {
        if (!r->ctx || !r->model || !r->mtp_ctx) return false;
        auto & dp = common_speculative_get_draft_params(r->mtp.get(), 0);
        dp = {};
        dp.drafting = true; dp.n_max = limit; dp.pos0 = (llama_pos)r->cached.size();
        dp.id_last = last; dp.prompt = &r->cached; dp.result = &out;
        const auto t0 = Clock::now();
        common_speculative_draft(r->mtp.get());
        r->draft_ms += std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
        // Verification re-evaluates the draft against the target's hidden rows.
        if (!llama_memory_seq_rm(llama_get_memory(r->mtp_ctx), 0, dp.pos0, -1))
            throw std::runtime_error("Generation decode failed.");
        if ((int)out.size() > limit) out.resize(limit);
        return !out.empty();
    }
    if (!r->draft_model || !r->draft_ctx || !r->draft_sampler) return false;
    auto & q = r->draft_queue; q.push_back(last);
    auto fail_draft = [&] {
        llama_memory_clear(llama_get_memory(r->draft_ctx), true);
        r->draft_cached.clear(); q.clear(); r->draft_max = 0; return false;
    };
    // Where a rejected round rolls the draft back to: the state before this
    // proposal, which a recurrent draft cannot recover with seq_rm alone.
    r->draft_undo_pos = (int)r->draft_cached.size();
    r->draft_undo = r->draft_needs_checkpoints ? partial_state(r->draft_ctx) : std::vector<uint8_t>{};
    // The draft context may accept fewer tokens than the target batch.
    const int draft_batch = std::max(1, (int)llama_n_batch(r->draft_ctx));
    for (size_t i = 0; i < q.size(); i += (size_t)draft_batch) {
        if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Generation cancelled.");
        int n = std::min((int)(q.size() - i), draft_batch);
        if (llama_decode(r->draft_ctx, llama_batch_get_one(q.data() + i, n)) != 0) return fail_draft();
    }
    for (auto t : q) r->draft_cached.push_back(t);
    q.clear();
    const auto * vocab = llama_model_get_vocab(r->draft_model);
    for (int i = 0; i < limit; ++i) {
        if (r->cancelled->load(std::memory_order_relaxed)) throw std::runtime_error("Generation cancelled.");
        llama_token t = llama_sampler_sample(r->draft_sampler, r->draft_ctx, -1);
        if (t < 0 || t >= llama_vocab_n_tokens(vocab) || llama_vocab_is_eog(vocab, t)) break;
        if (r->draft_p_min > 0) {
            const float * logits = llama_get_logits_ith(r->draft_ctx, -1);
            if (!logits) return fail_draft();
            double sum = 0;
            for (int j = 0; j < llama_vocab_n_tokens(vocab); ++j) sum += std::exp(double(logits[j]) - logits[t]);
            if (1.0 / sum < r->draft_p_min) break;
        }
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
        if (r->cancelled->load(std::memory_order_relaxed)) {
            r->finish = "cancelled"; r->done = true; return 2;
        }
        if (r->flush_only) {
            // The answer ended with text still held back for a possible stop
            // sequence: send it, then report the end.
            *length = flush(r, output, capacity, true);
            if (r->held.empty() && r->parsed_output.empty()) { r->flush_only = false; r->done = true; }
            return *length > 0 ? 1 : 2;
        }
        if (r->done) return 2;
        const auto * vocab = llama_model_get_vocab(r->model);
        if (r->media_pending) {
            AddElapsed timed{r->prefill_ms};
            try { eval_media(r); } catch (...) { r->drop_chunks(); throw; }
            llama_synchronize(r->ctx);
            return 0;
        }
        if (r->cursor < (int)r->prompt.size()) {
            AddElapsed timed{r->prefill_ms};
            int n = std::min(r->batch, (int)r->prompt.size() - r->cursor);
            for (const int at : r->checkpoint_at) if (at > r->cursor && at < r->cursor + n) { n = at - r->cursor; break; }
            auto batch = llama_batch_get_one(r->prompt.data() + r->cursor, n);
            if (decode_target(r, batch) != 0) { r->forget(); throw std::runtime_error("Prompt evaluation failed. Try a smaller context/model."); }
            r->cursor += n;
            r->cached.assign(r->prompt.begin(), r->prompt.begin() + r->cursor);
            if (r->mtp && r->cursor == (int)r->prompt.size()) common_speculative_begin(r->mtp.get(), 0, r->prompt);
            while (!r->checkpoint_at.empty() && r->checkpoint_at.front() <= r->cursor) {
                if (r->checkpoint_at.front() == r->cursor) take_checkpoint(r, r->cursor);
                r->checkpoint_at.erase(r->checkpoint_at.begin());
            }
            // GPU decodes return before they finish: the last chunk waits so
            // prompt reading is not under-counted.
            if (r->cursor == (int)r->prompt.size()) llama_synchronize(r->ctx);
            return 0;
        }
        auto end = [&](const char * why) {
            r->finish = why; finish_tools(r);
            if (r->held.empty() && r->parsed_output.empty()) { r->done = true; return 2; }
            r->flush_only = true; *length = flush(r, output, capacity, true);
            if (r->held.empty() && r->parsed_output.empty()) { r->flush_only = false; r->done = true; }
            return 1;
        };
        if (!make_context_room(r, 2)) return end("length");
        if (out_of_room(r)) return end("length");
        if (r->in_think && r->think_budget > 0 && r->think_tokens >= r->think_budget) {
            // Budget spent: close the reasoning block on the model's behalf, let
            // it see the closing tokens, then sample the answer.
            if (r->pending >= 0) { decode_into_target(r, {(llama_token)r->pending}); r->pending = -1; }
            // A bare close tag left small models reasoning on in the answer
            // ("Wait, I need to check…" in every Qwen3.5 0.8B goal step on
            // the phone, 2026-09-24). Qwen's recommended hand-off sentence
            // before the tag makes them answer.
            std::string close = reasoning_handoff(r->think_ends);
            auto tokens = tokenize(vocab, close, false);
            if (tokens.empty()) throw std::runtime_error("Cannot close the reasoning block.");
            if (r->grammar) {
                // A tool grammar may refuse part of the hand-off (Gemma 4's
                // rejected the newline after its close tag: "empty grammar
                // stack", 2026-11-02); only what it allows is written.
                std::vector<llama_token> kept;
                for (auto t : tokens) {
                    llama_token_data single = {t, 1.0f, 0.0f};
                    llama_token_data_array one = {&single, 1, -1, false};
                    llama_sampler_apply(r->grammar, &one);
                    if (one.data[0].logit == -INFINITY) continue;
                    llama_sampler_accept(r->grammar, t);
                    kept.push_back(t);
                }
                if (kept.empty()) throw std::runtime_error("Cannot close the reasoning block.");
                tokens = kept;
                close.clear();
                for (auto t : tokens) close += common_token_to_piece(vocab, t, true);
            }
            if (!make_context_room(r, (int)tokens.size())) return end("length");
            decode_into_target(r, tokens);
            for (auto t : tokens) llama_sampler_accept(r->sampler, t);
            r->generated += (int)tokens.size(); r->reasoning += (int)tokens.size(); r->in_think = false; r->tail.clear();
            r->held += close; r->generated_text += close;
            if (r->parser_active) for (auto token : tokens) r->generated_input.append(common_token_to_piece(vocab, token, true), token);
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
        if ((r->draft_ctx || r->mtp) && r->draft_max > 0 && !r->draft_disabled && r->plain_steps >= Runtime::draft_warm
            && r->pending >= 0 && room > 0 && !r->media_tokens
            && (!r->mtp || (int)r->cached.size() + (r->dflash ? r->dflash_block : r->draft_max + 1) < (int)llama_n_ctx(r->ctx))
            && propose(r, (llama_token)r->pending, std::min(r->draft_max, room), drafts)) {
            // Speculative round: the target verifies [pending, d0, d1, ...] in
            // one decode and every draft token it would have sampled itself is
            // kept; the first disagreement replaces the draft and ends the round.
            // Invariant before and after: draft KV == cached ++ draft_queue.
            const llama_token last = (llama_token)r->pending;
            const int n = 1 + (int)drafts.size();
            const int base = (int)r->cached.size();
            // A rollback snapshot only for recurrent state: Gemma 4's sliding
            // window drops the tail with seq_rm, and copying it off the GPU
            // every round cost more than the drafts saved (llama-server skips
            // it the same way).
            // Rollback slots (n_rs_seq) cover drafts up to their count.
            const bool rollback_state = (llama_model_is_recurrent(r->model) || llama_model_is_hybrid(r->model))
                && llama_n_rs_seq(r->ctx) < (uint32_t)drafts.size();
            const auto undo = rollback_state ? partial_state(r->ctx) : std::vector<uint8_t>{};
            llama_batch batch = llama_batch_init(n, 0, 1);
            for (int i = 0; i < n; ++i) {
                batch.token[i] = i == 0 ? last : drafts[i - 1]; batch.pos[i] = (llama_pos)(base + i);
                batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0; batch.logits[i] = true;
            }
            batch.n_tokens = n;
            const int rc = decode_target(r, batch);
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
                if (r->mtp) {
                    if (!llama_memory_seq_rm(llama_get_memory(r->mtp_ctx), 0, (llama_pos)keep, -1))
                        throw std::runtime_error("Generation decode failed.");
                } else if (!llama_memory_seq_rm(llama_get_memory(r->draft_ctx), 0, (llama_pos)keep, -1)) {
                    if (!drop_tail(r->draft_ctx, r->draft_undo_pos, r->draft_undo)) {
                        llama_memory_clear(llama_get_memory(r->draft_ctx), true); r->draft_undo_pos = 0;
                    }
                    r->draft_cached.resize((size_t)r->draft_undo_pos);
                    r->draft_queue.assign(r->cached.begin() + r->draft_undo_pos, r->cached.end());
                } else {
                    r->draft_cached.resize((size_t)keep);
                }
            }
            if (r->mtp) common_speculative_accept(r->mtp.get(), 0, (uint16_t)matched);
            r->pending = eog ? -1 : next;
            const long settle = r->mtp ? Runtime::mtp_settle : 0;
            if (r->draft_rounds > settle) {
                r->spec_ms += std::chrono::duration<double, std::milli>(Clock::now() - step_started).count();
                r->spec_tokens += (long)accepted.size();
            }
            if (r->draft_rounds >= settle + (r->mtp ? Runtime::mtp_probe : Runtime::draft_probe)) {
                const bool missing = !r->mtp && r->draft_proposed > 0 && (double)r->draft_accepted / (double)r->draft_proposed < Runtime::draft_floor;
                const double margin = r->mtp ? Runtime::mtp_margin : 1.0;
                // Both intervals are one decode plus the tokens sampled from
                // it, so compare milliseconds per token.
                const bool slower = r->plain_ms > 0 && r->spec_ms > 0 && r->plain_steps > 0 && r->spec_tokens > 0
                    && r->spec_ms / (double)r->spec_tokens > (r->plain_ms / (double)r->plain_steps) / margin;
                if (missing || slower) {
                    r->draft_disabled = true;
                    ++r->draft_losses;
                } else {
                    r->draft_losses = 0;
                }
            }
        } else {
            const bool decoded = r->pending >= 0;
            if (decoded) {
                auto token = (llama_token)r->pending;
                auto batch = llama_batch_get_one(&token, 1);
                if (decode_target(r, batch) != 0) { r->forget(); throw std::runtime_error("Generation decode failed."); }
                r->cached.push_back(token); r->pending = -1;
                if (r->draft_ctx) r->draft_queue.push_back(token);
            }
            auto token = sample(r, -1);
            // A plain step is the yardstick for a speculative round: both are
            // one decode plus the tokens sampled from it, so sampling is
            // inside the measured interval here too (a CPU sampler used to be
            // left out and made speculation look slower than it is).
            if (decoded && (r->draft_ctx || r->mtp)) {
                r->plain_ms += std::chrono::duration<double, std::milli>(Clock::now() - step_started).count();
                ++r->plain_steps;
            }
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
            if (!emit_piece(r, std::string(piece.data(), (size_t)std::max(n, 0)), token)) { stopped = true; break; }
            if (out_of_room(r)) break;
        }
        r->last = Clock::now();
        if (stopped) { r->pending = -1; return end("stop"); }
        if (eog) { r->pending = -1; return end("eog"); }
        *length = flush(r, output, capacity, false);
        return 1;
    } catch (const std::exception & e) { return fail(r, e); }
}
