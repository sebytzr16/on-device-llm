// Exercise the real scheduler without loading weights. Stop at decode so fake
// contexts are never passed into llama.cpp; count destructive reallocations.
#if defined(_WIN32)
#include "../src/memory_admission.h"
static BOOL WINAPI test_windows_memory(LPMEMORYSTATUSEX status) {
    // Keep the fake scheduler allocation independent of the host's free RAM.
    status->ullTotalPhys = 8ull << 30;
    status->ullAvailPhys = 4ull << 30;
    return TRUE;
}
#define GlobalMemoryStatusEx test_windows_memory
#endif
#define llama_free test_llama_free
#define llama_init_from_model test_llama_init_from_model
#define llama_decode test_llama_decode
#define llama_model_get_vocab test_llama_model_get_vocab
#define llama_vocab_get_attr test_llama_vocab_get_attr
#define common_token_to_piece test_common_token_to_piece
#define common_get_device_memory_data test_common_get_device_memory_data
#include "../src/bridge.cpp"
#include "chat-peg-parser.h"
#include <future>
#include <iostream>
#include <thread>

static int frees = 0, allocations = 0;
static std::vector<int> decoded;
struct BlockedDecode {
    std::promise<void> entered, resume;
    std::future<void> resumed = resume.get_future();
    std::shared_ptr<std::atomic<bool>> cancelled;
    bool observed_cancel = false;
    bool side = false;
};
static BlockedDecode * blocked_decode = nullptr;
static llama_context_params allocated_params{};
void test_llama_free(llama_context *) { ++frees; }
llama_context * test_llama_init_from_model(llama_model *, llama_context_params params) {
    ++allocations;
    allocated_params = params;
    return reinterpret_cast<llama_context *>(2);
}
const llama_vocab * test_llama_model_get_vocab(const llama_model *) { return nullptr; }
llama_token_attr test_llama_vocab_get_attr(const llama_vocab *, llama_token token) {
    return token <= 2 ? LLAMA_TOKEN_ATTR_CONTROL : LLAMA_TOKEN_ATTR_NORMAL;
}
std::string test_common_token_to_piece(const llama_vocab *, llama_token token, bool special) {
    if (token == 1) return special ? "</think>" : "";
    if (token == 2) return special ? "<|unused|>" : "";
    return "answer";
}
common_device_memory_data_vec test_common_get_device_memory_data(
    const std::vector<std::string> &, const llama_model_params *, const llama_context_params *,
    std::vector<ggml_backend_dev_t> &, uint32_t &, uint32_t &, uint32_t &, uint32_t &, ggml_log_level) {
    return {};
}
int32_t test_llama_decode(llama_context *, llama_batch batch) {
    if (auto * decode = blocked_decode) {
        decode->entered.set_value();
        decode->resumed.wait();
        if (decode->side) {
            decode->observed_cancel = allocated_params.abort_callback &&
                allocated_params.abort_callback(allocated_params.abort_callback_data);
        } else {
            decode->observed_cancel = cancelled_callback(decode->cancelled.get());
        }
        return -1;
    }
    decoded.clear();
    for (int i = 0; i < batch.n_tokens; ++i) decoded.push_back(batch.seq_id[i][0]);
    return -1;
}
static void check(bool ok, const char * why) {
    if (!ok) throw std::runtime_error(why);
}
static void destroy_regression() {
    using namespace std::chrono_literals;
    auto * handle = od_create(nullptr);
    check(handle != nullptr, "failed to create lifetime test runtime");
    const auto session = od_session_id(handle);
    od_cancel_session(session);
    od_reset_cancel(handle);
    check(!od_cancelled(handle), "reset failed while runtime was open");
    const char * info = od_info(handle);
    BlockedDecode decode;
    {
        RuntimeCall call(handle);
        auto * r = call.get();
        r->done = false;
        r->batch = 1;
        r->prompt = {1};
        decode.cancelled = r->cancelled;
    }
    blocked_decode = &decode;
    std::thread step([&] {
        uint8_t output[32];
        int32_t length;
        od_step(handle, output, sizeof(output), &length);
    });
    const bool entered = decode.entered.get_future().wait_for(5s) == std::future_status::ready;
    void * side = nullptr;
    std::thread open([&] { side = od_side_open(handle, "{}"); });
    auto deadline = Clock::now() + 5s;
    bool queued = false;
    while (!queued && Clock::now() < deadline) {
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            queued = registry.at(handle)->active_calls == 2;
        }
        if (!queued) std::this_thread::sleep_for(1ms);
    }
    auto destroy = std::async(std::launch::async, [=] { od_destroy(handle); });
    deadline = Clock::now() + 5s;
    while (od_session_id(handle) != 0 && Clock::now() < deadline) std::this_thread::sleep_for(1ms);
    const bool closed = od_session_id(handle) == 0;
    const bool waited = destroy.wait_for(0s) == std::future_status::timeout;
    od_reset_cancel(handle);
    const bool closing_cancelled = decode.cancelled->load(std::memory_order_relaxed);
    auto cancel = std::async(std::launch::async, [=] { od_cancel_session(session); });
    const bool prompt_cancel = cancel.wait_for(1s) == std::future_status::ready;
    decode.resume.set_value();
    step.join();
    open.join();
    destroy.get();
    cancel.get();
    blocked_decode = nullptr;
    auto * next = od_create(nullptr);
    const bool stale = next && next != handle && od_side_open(handle, "{}") == nullptr;
    od_destroy(handle);
    od_destroy(next);
    check(entered && queued && closed && waited && side == nullptr, "07.1 destroy did not drain in-flight calls and close admission");
    check(prompt_cancel && decode.observed_cancel, "07.1 cancellation was blocked by step or destroy");
    check(closed && closing_cancelled, "a reset cleared cancellation after destroy closed admission");
    check(stale && json::parse(info).at("abiVersion") == 7, "07.1 stale handle or returned string outlived its backing storage");
    std::cout << "PASS 07.1 destroy drains step and side open while cancellation stays live\n";
}
static void side_shutdown_regression() {
    using namespace std::chrono_literals;
    auto * handle = od_create(nullptr);
    check(handle != nullptr, "failed to create helper lifetime test runtime");
    auto side = std::make_shared<SideBatch>();
    side->model = reinterpret_cast<llama_model *>(1);
    side->params = llama_context_default_params();
    side->params.offload_kqv = false;
    const auto previous_allocations = allocations;
    const auto previous_frees = frees;
    resize_side(*side, 1024, 1);
    const bool callback_live = allocated_params.abort_callback &&
        !allocated_params.abort_callback(allocated_params.abort_callback_data);
    side->sequences.push_back(std::make_unique<SideSequence>());
    side->sequences.front()->active = true;
    side->sequences.front()->prompt = {1};
    {
        RuntimeCall call(handle);
        call.get()->sides.push_back(side);
    }
    BlockedDecode decode;
    decode.side = true;
    blocked_decode = &decode;
    auto step = std::async(std::launch::async, [&] { return json::parse(od_side_step(&side)); });
    const bool entered = decode.entered.get_future().wait_for(5s) == std::future_status::ready;
    auto destroy = std::async(std::launch::async, [=] { od_destroy(handle); });
    const auto deadline = Clock::now() + 5s;
    while (!side->shutdown.load() && Clock::now() < deadline) std::this_thread::sleep_for(1ms);
    decode.resume.set_value();
    const auto interrupted = step.get();
    destroy.get();
    blocked_decode = nullptr;
    check(entered && callback_live && decode.observed_cancel, "helper decode did not observe shutdown during destroy");
    check(interrupted.at("error") == "chat model changed" && !side->ctx && !side->model,
          "helper context survived shutdown or returned a decode error");
    check(od_side_submit(&side, 0, "{}") == -1 && json::parse(od_side_step(&side)).contains("error"),
          "closed helper admitted work");
    allocations = previous_allocations;
    frees = previous_frees;
    std::cout << "PASS helper decode aborts on shutdown and rejects new work\n";
}
static void side_control_regression() {
    SideSequence seq;
    seq.formatting.forced_open = true;
    seq.formatting.think_start = "<think>";
    seq.formatting.think_ends = {"</think>"};
    seq.active = true;
    check(side_stream_text(seq, "private") == "<think>private", "lost prompt-open reasoning");
    for (llama_token token : {1, 2, 3}) side_hold_token(seq, nullptr, token);
    seq.active = false;
    check(side_stream_text(seq, seq.held, seq.held_controls) == "</think>answer",
          "helper lost its natural control-token delimiter or exposed another control token");
    std::cout << "PASS helper normalizes the natural control-token delimiter\n";
}
static void harmony_cursor_regression() {
    for (bool repeat_prefix : {false, true}) {
        Runtime r(0);
        r.parser_active = true;
        r.parser.generation_prompt = common_chat_input(std::string(harmony_assistant));
        r.think_start = harmony_analysis;
        r.think_ends = {std::string(harmony_end)};
        r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
            const auto start = p.literal(std::string(harmony_assistant));
            const auto analysis = p.literal(std::string(harmony_analysis)) +
                p.reasoning(p.until(std::string(harmony_end))) + p.literal(std::string(harmony_end));
            return p.zero_or_more(start + analysis) + start +
                p.literal(std::string(harmony_final)) + p.content(p.rest()) + p.end();
        });
        const auto fetch = [&](const std::string & piece) {
            emit_piece(&r, piece);
            r.parsed_at -= std::chrono::milliseconds(40);
            parse_output(&r, false);
        };
        const std::string prefix = (repeat_prefix ? std::string(harmony_assistant) : "") + std::string(harmony_analysis);
        fetch(prefix + "analysis");
        check(r.parsed_output == "<think>analysis" && r.streamed_raw_length == prefix.size() + 8,
              "Harmony raw cursor matched the channel header");
        fetch("<|end|>\n\n<|start|>assistant<|channel|>analysis<|message|>analysis again");
        check(r.parsed_output == "<think>analysisanalysis again" &&
              r.streamed_raw_length == r.generated_input.size(), "Harmony raw cursor lost padding offsets");
        emit_piece(&r, "<|end|><|start|>assistant<|channel|>final<|mess");
        r.finish = "length";
        finish_tools(&r);
        check(r.parsed_output == "<think>analysisanalysis again</think>",
              "truncated Harmony output exposed reasoning or protocol");
        check(r.streamed_raw_length >= prefix.size() + 8, "Harmony cursor moved backwards at finalization");
    }
    std::cout << "PASS Harmony cursor follows PEG source offsets through a truncated turn\n";
}
static void side_tags_regression() {
    SideSequence seq;
    seq.formatting.think_start = "<|channel>thought\n";
    seq.formatting.think_ends = {"<channel|>", "<|turn>"};
    seq.active = true;
    check(side_stream_text(seq, "before<|chan") == "before", "07.2 leaked split start tag");
    check(side_stream_text(seq, "nel>thought\nprivate<chan") == "<think>private", "07.2 failed to normalize start tag");
    check(side_stream_text(seq, "nel|>answer<|tur") == "</think>answer", "07.2 failed to normalize split end tag");
    check(side_stream_text(seq, "n>") == "</think>", "07.2 failed to normalize alternate end tag");
    seq.formatting.forced_open = true;
    check(side_stream_text(seq, "private<chan") == "<think>private", "07.2 lost forced open tag");
    check(side_stream_text(seq, "nel|>answer<chan") == "</think>answer", "07.2 repeated forced open tag");
    seq.active = false;
    check(side_stream_text(seq, "") == "<chan", "07.2 dropped literal tail at end of stream");
    std::cout << "PASS 07.2 helper reasoning markers across chunks\n";
}
static void resize_regression() {
    auto side = std::make_shared<SideBatch>();
    side->adaptive = true;
    side->model = reinterpret_cast<llama_model *>(1);
    side->ctx = reinterpret_cast<llama_context *>(1);
    // The second request fits the unrounded 1,200-token allocation, but its
    // rounded step requirement is 1,280 (the old submit/step mismatch).
    side->allocated_context = 1200; side->allocated_sequences = 2;
    for (int i = 0; i < 2; ++i) {
        auto seq = std::make_unique<SideSequence>();
        seq->active = true; seq->prompt = {1, 2};
        seq->position = seq->prompt_cursor = i == 0 ? 1 : 0;
        if (i == 1) { seq->prompt.resize(800, 1); seq->maximum = 300; }
        side->sequences.push_back(std::move(seq));
    }
    auto handle = side;
    od_side_step(&handle);
    check(frees == 0 && allocations == 0, "M01: resized a context holding running KV");
    check(decoded == std::vector<int>{0}, "M01: decoded queued work without capacity");
    side->sequences[0]->active = false;
    od_side_step(&handle);
    check(frees == 1 && allocations == 1 && side->allocated_context >= 1280,
          "M01: did not grow at the idle boundary");
    check(!decoded.empty() && std::all_of(decoded.begin(), decoded.end(), [](int id) { return id == 1; }),
          "M01: queued work did not resume");
    std::cout << "PASS M01 deferred growth and queued decode\n";
}
static void parse_regression() {
    auto handle = std::unique_ptr<void, decltype(&od_destroy)>(od_create(nullptr), od_destroy);
    check(handle != nullptr, "failed to create parser runtime");
    RuntimeCall call(handle.get());
    auto & r = *call.get();
    r.parser_active = true; r.finish = "eog";
    r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
        return p.content(p.literal("partial")) + p.literal("!");
    });
    r.parsed_msg.tool_calls.push_back({"get_weather", "{", "partial-id"});
    emit_piece(&r, "partialBROKEN");
    finish_tools(&r);
    const auto metrics = json::parse(od_info(handle.get()));
    check(!metrics["parseError"].get<std::string>().empty(), "N02: missing parseError");
    check(metrics["toolContent"] == "partialBROKEN", "N02: raw tool content lost");
    check(metrics["toolCalls"].empty(), "N02: incomplete call exposed for execution");
    std::cout << "PASS N02 explicit parse failure and raw tool content\n";
}
static void trim_regression() {
    // Compare message order, erased count and partial failure against the old
    // implementation, including system prefixes and unfinished tool rounds.
    const auto reference = [](json & m, int steps, int & erased) {
        const size_t head = !m.empty() && m[0].value("role", "") == "system" ? 1 : 0;
        for (int k = 0; k < steps; ++k) {
            size_t last_user = m.size();
            for (size_t i = m.size(); i-- > 0;)
                if (m[i].value("role", "") == "user") { last_user = i; break; }
            if (last_user == m.size() || last_user <= head) return false;
            m.erase(m.begin() + head); ++erased;
            while (m.size() > head + 1 && m[head].value("role", "") != "user") {
                m.erase(m.begin() + head); ++erased;
            }
        }
        return true;
    };
    const char * roles[] = {"user", "assistant", "tool"};
    for (bool system : {false, true}) {
        // Every role ordering up to six messages, with unique payloads.
        for (int length = 0, combinations = 1; length <= 6; ++length, combinations *= 3) {
            for (int pattern = 0; pattern < combinations; ++pattern) {
                json original = json::array();
                if (system) original.push_back({{"role", "system"}, {"content", "keep"}});
                int code = pattern;
                for (int i = 0; i < length; ++i, code /= 3)
                    original.push_back({{"role", roles[code % 3]}, {"content", std::to_string(i)}});
                for (int steps = 0; steps <= length + 1; ++steps) {
                    auto expected = original, actual = original;
                    int expected_erased = 7, actual_erased = 7;
                    const bool ok = reference(expected, steps, expected_erased);
                    check(drop_oldest_exchanges(actual, steps, actual_erased) == ok &&
                          actual == expected && actual_erased == expected_erased,
                          "N75: exchange trimming changed behavior");
                }
            }
        }
    }
    json long_chat = json::array({{{"role", "system"}}});
    for (int i = 0; i < 10000; ++i) {
        long_chat.push_back({{"role", "user"}});
        long_chat.push_back({{"role", "assistant"}, {"tool_calls", json::array()}});
        long_chat.push_back({{"role", "tool"}});
    }
    int erased = 0;
    check(!drop_oldest_exchanges(long_chat, 10000, erased) && erased == 29997 &&
          long_chat.size() == 4 && long_chat[0]["role"] == "system" &&
          long_chat[1]["role"] == "user" && long_chat[3]["role"] == "tool",
          "N75: long history lost the current tool round");
    std::cout << "PASS N75 exchange trimming equivalence and long history\n";
}
int main(int argc, char ** argv) {
    try {
        if (argc > 1 && std::string(argv[1]) == "parse") parse_regression();
        else {
            destroy_regression();
            side_shutdown_regression();
            side_tags_regression();
            side_control_regression();
            harmony_cursor_regression();
            resize_regression();
            parse_regression();
            trim_regression();
        }
    } catch (const std::exception & e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
}
