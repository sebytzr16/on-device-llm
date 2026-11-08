// Exercise the real scheduler without loading weights. Stop at decode so fake
// contexts are never passed into llama.cpp; count destructive reallocations.
#define llama_free test_llama_free
#define llama_init_from_model test_llama_init_from_model
#define llama_decode test_llama_decode
#include "../src/bridge.cpp"
#include "chat-peg-parser.h"
#include <iostream>

static int frees = 0, allocations = 0;
static std::vector<int> decoded;
void test_llama_free(llama_context *) { ++frees; }
llama_context * test_llama_init_from_model(llama_model *, llama_context_params) {
    ++allocations;
    return reinterpret_cast<llama_context *>(2);
}
int32_t test_llama_decode(llama_context *, llama_batch batch) {
    decoded.clear();
    for (int i = 0; i < batch.n_tokens; ++i) decoded.push_back(batch.seq_id[i][0]);
    return -1;
}
static void check(bool ok, const char * why) {
    if (!ok) throw std::runtime_error(why);
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
        seq->position = i == 0 ? 1 : 0;
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
    Runtime r(0); r.parser_active = true; r.finish = "eog";
    r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
        return p.content(p.literal("partial")) + p.literal("!");
    });
    r.parsed_msg.tool_calls.push_back({"get_weather", "{", "partial-id"});
    emit_piece(&r, "partialBROKEN");
    finish_tools(&r);
    const auto metrics = json::parse(od_info(&r));
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
        else { resize_regression(); parse_regression(); trim_regression(); }
    } catch (const std::exception & e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
}
