#include "../src/bridge.cpp"
#include "chat-peg-parser.h"
#include <iostream>

static void check(bool ok, const char * why) {
    if (!ok) throw std::runtime_error(why);
}
static void configure(Runtime & r, const common_chat_params & p) {
    r.parser_active = true;
    r.parser = common_chat_parser_params(p);
    r.parser.parser = p.parser;
    r.stops = p.additional_stops;
}
static std::string stream(Runtime & r, const std::string & raw) {
    std::string output;
    uint8_t buf[3];
    for (char c : raw) {
        const bool more = emit_piece(&r, std::string(1, c));
        if (!more) break;
        const int n = flush(&r, buf, sizeof buf, false);
        output.append((char *)buf, n);
    }
    finish_tools(&r);
    while (!r.held.empty() || !r.parsed_output.empty()) {
        const int n = flush(&r, buf, sizeof buf, true);
        output.append((char *)buf, n);
    }
    return output;
}
static common_chat_templates_ptr fixture(const char * name) {
    std::ifstream file(std::string("native/llama.cpp/models/templates/") + name);
    check(file.good(), "Missing template fixture");
    std::string source((std::istreambuf_iterator<char>(file)), {});
    return common_chat_templates_init(nullptr, source);
}
int main() {
    try {
        check(answer_limit(json{{"maxTokens", 128000}, {"reservedTokens", 16384}}, 200000) == 128000, "Custom answer limit was capped");
        check(answer_limit(json{{"maxTokens", 128000}}, 60000) == 60000, "Answer must fit remaining context");
        check(answer_limit(json{{"maxTokens", 32000}}, 60000, 512) == 32000, "Agent answer was capped at 4096");
        check(response_reserve(json{{"maxTokens", 65536}, {"reservedTokens", 2048}}, 8192) == 2048, "Explicit prompt reserve ignored");
        check(response_reserve(json{{"maxTokens", 1000}}, 8192) == 1000, "Legacy maxTokens fallback changed");
        check(response_reserve(json{{"maxTokens", 65536}}, 8192) == 8191, "Legacy reserve not clamped");
        check(response_reserve(json{{"reservedTokens", 0}}, 8192) == 1, "Zero reserve not clamped");
        check(response_reserve(json{{"reservedTokens", 65536}}, 8192) == 8191, "Oversized reserve not clamped");
        {
            Runtime r(0);
            r.maximum = 1000; r.total_cap = 8192; r.generated = 256;
            check(!out_of_room(&r), "Prompt reserve became generation limit");
            r.generated = 1000;
            check(out_of_room(&r), "Generation limit ignored");
        }
        std::cout << "PASS separate prompt reserve, legacy fallback and generation limit\n";
        common_chat_templates_inputs in;
        common_chat_msg user; user.role = "user"; user.content = "hi";
        in.messages = {user}; in.enable_thinking = false;
        in.reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK;
        auto harmony = fixture("openai-gpt-oss-120b.jinja");
        auto p = common_chat_templates_apply(harmony.get(), in);
        {
            Runtime r(0); configure(r, p);
            r.parser.generation_prompt = common_chat_input("<|start|>assistant<|channel|>analysis<|message|>");
            const auto out = stream(r, "reason<|end|><|start|>assistant<|channel|>final<|message|>answer");
            check(out == "<think>reason</think>answer", "Forced reasoning / Harmony header leak");
            check(r.parse_error.empty(), "Harmony parse failed");
            std::cout << "PASS Harmony forced-open with thinking off, byte chunks, 3-byte buffers\n";
        }
        {
            Runtime r(0); configure(r, p);
            r.parser.generation_prompt = common_chat_input("<|start|>assistant<|channel|>final<|message|>Hello");
            r.parsed_msg = common_chat_parse({}, true, r.parser);
            check(stream(r, " world") == " world", "Continuation prefix echoed");
            std::cout << "PASS continuation prefix does not echo\n";
        }
        {
            Runtime r(0); configure(r, p); r.stops.push_back("STOP");
            r.parser.generation_prompt = common_chat_input("<|start|>assistant<|channel|>final<|message|>");
            check(stream(r, "answerSTOPignored") == "answer", "Split stop leaked");
            check(r.generated_text == "answer", "Parser input retained stop");
            std::cout << "PASS stop holdback before structured parsing\n";
        }
        {
            auto tools = in;
            tools.tools.push_back({"get_weather", "Weather", R"({"type":"object","properties":{"city":{"type":"string"}},"required":["city"]})"});
            tools.tool_choice = COMMON_CHAT_TOOL_CHOICE_REQUIRED;
            auto tp = common_chat_templates_apply(harmony.get(), tools);
            Runtime r(0); configure(r, tp);
            const std::string full = "<|start|>assistant<|channel|>commentary to=functions.get_weather<|message|>{\"city\":\"Toronto\"}";
            check(full.find(tp.generation_prompt) == 0, "Unexpected Harmony prefill");
            check(stream(r, full.substr(tp.generation_prompt.size())).empty(), "Harmony tool markup leaked");
            check(r.parse_error.empty() && r.tool_calls.size() == 1, "Harmony tool parse failed");
            check(r.tool_calls[0]["name"] == "get_weather", "Wrong tool name");
            std::cout << "PASS Harmony structured tool call\n";
        }
        {
            auto gemma = fixture("google-gemma-4-31B-it.jinja");
            auto json_in = in; json_in.json_schema = R"({"type":"object","properties":{"answer":{"type":"integer"}},"required":["answer"]})";
            auto gp = common_chat_templates_apply(gemma.get(), json_in);
            check(!gp.grammar.empty(), "Gemma schema grammar missing");
            Runtime r(0); configure(r, gp);
            check(stream(r, "```json{\"answer\":4}```") == "{\"answer\":4}", "Gemma JSON wrapper leaked");
            check(r.parse_error.empty(), "Gemma JSON parse failed");
            std::cout << "PASS Gemma schema grammar and wrapper removal\n";
        }
        {
            Runtime r(0); r.templates = fixture("Qwen3.5-4B.jinja");
            common_chat_params jp;
            render(&r, json::array({{{"role", "user"}, {"content", "JSON please"}}}), "", false, true, {}, "auto", &jp, "{}");
            check(!jp.grammar.empty(), "Empty JSON schema disabled the template grammar");
            configure(r, jp);
            check(stream(r, "{\"answer\":4}") == "{\"answer\":4}" && r.parse_error.empty(), "JSON object parser failed");
            std::cout << "PASS JSON object mode normalizes empty schema like llama-server\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
                return p.content(p.literal("partial")) + p.literal("!");
            });
            // A failed final parse must not expose a call retained from a partial parse.
            r.parsed_msg.tool_calls.push_back({"get_weather", "{}", "partial-id"});
            const auto out = stream(r, "partialBROKEN");
            check(!r.parse_error.empty() && out.find("partialBROKEN") != std::string::npos, "Raw failure output lost");
            check(r.tool_calls.empty(), "Failed parse exposed partial tool call");
            std::cout << "PASS parse error preserves raw output and clears partial calls\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
                return p.content(p.literal("partial\n")) + p.literal("!");
            });
            // Queued bytes count as covered even with a tiny caller buffer.
            emit_piece(&r, "partial\n");
            uint8_t buf[3];
            const int n = flush(&r, buf, sizeof buf, false);
            std::string out((char *)buf, n);
            check(out == "par", "Expected content before final failure");
            emit_piece(&r, "BROKEN");
            finish_tools(&r);
            while (!r.held.empty() || !r.parsed_output.empty()) {
                const int count = flush(&r, buf, sizeof buf, true);
                out.append((char *)buf, count);
            }
            check(out == "partial\nBROKEN" && !r.parse_error.empty(), "Final failure duplicated content or lost raw tail");
            check(r.tool_calls.empty() && r.tool_content == "partial\nBROKEN", "Failure metadata changed");
            std::cout << "PASS final failure appends only unstreamed raw suffix, including queued bytes\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
                return p.literal("<r>") + p.reasoning(p.literal("reason\n")) + p.literal("!");
            });
            check(stream(r, "<r>reason\nBROKEN") == "<think>reason\n</think>BROKEN", "Failure repeated reasoning or left think tag open");
            check(!r.parse_error.empty(), "Expected malformed reasoning failure");
            std::cout << "PASS final failure closes reasoning before the unstreamed raw suffix\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            r.parser.generation_prompt = common_chat_input("Hello");
            r.parsed_msg = common_chat_parse({}, true, r.parser);
            r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) {
                return p.content(p.literal("Hello world\n")) + p.literal("!");
            });
            check(stream(r, " world\nBROKEN") == " world\nBROKEN", "Continuation failure repeated prefix or generated content");
            std::cout << "PASS continuation final failure tracks generated bytes only\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            uint8_t buf[256];
            emit_piece(&r, "short");
            check(flush(&r, buf, sizeof buf, false) == 5 && r.parsed_raw_length == 5, "First visible text waited for a batch");
            emit_piece(&r, "er");
            check(flush(&r, buf, sizeof buf, false) == 0 && r.parsed_raw_length == 5, "Ordinary text did not batch");
            emit_piece(&r, "\n");
            check(flush(&r, buf, sizeof buf, false) == 3 && r.parsed_raw_length == 8, "Newline did not trigger parsing");
            r.parsed_at -= std::chrono::milliseconds(40);
            emit_piece(&r, "ab");
            check(flush(&r, buf, sizeof buf, false) == 2 && r.parsed_raw_length == 10, "A 30 ms old parse held text back");
            check(stream(r, std::string(150, 'x')) == std::string(150, 'x'), "Byte batching or finalization lost text");
            std::cout << "PASS partial parsing shows the first text at once, batches by bytes or 30 ms, parses boundaries, and flushes the final short tail\n";
        }
        {
            common_chat_params no_grammar;
            check(!json_grammar_fallback(no_grammar, "{}").empty(), "JSON object grammar fallback missing");
            check(!json_grammar_fallback(no_grammar, R"({"type":"object","properties":{"answer":{"const":4}},"required":["answer"]})").empty(), "JSON schema grammar fallback missing");
            check(json_grammar_fallback(no_grammar, "").empty(), "Text mode unexpectedly constrained");
            no_grammar.grammar = "template grammar";
            check(json_grammar_fallback(no_grammar, "{}").empty(), "Template grammar replaced");
            bool rejected = false;
            try { json_grammar_fallback(common_chat_params(), "{invalid"); }
            catch (const std::exception &) { rejected = true; }
            check(rejected, "Invalid schema silently disabled grammar");
            std::cout << "PASS JSON/schema fallback only when template grammar is missing\n";
        }
        {
            Runtime r(0); r.parser_active = true;
            r.parsed_msg.content = "partial result";
            r.parser.parser = build_chat_peg_parser([](common_chat_peg_builder & p) { return p.literal("protocol"); });
            check(stream(r, "protocol").find("protocol") != std::string::npos && !r.parse_error.empty(), "Empty final parse kept stale partial result");
            std::cout << "PASS empty final parse reports error despite nonempty partial result\n";
        }
        {
            Runtime r(0);
            r.templates = common_chat_templates_init(nullptr,
                "{% if tools %}{{ raise_exception('tool capability probe rejected') }}{% endif %}{% for m in messages %}{{ m.content }}{% endfor %}{% if add_generation_prompt %}assistant:{% endif %}");
            check(!probe_tools(&r), "Tool probe unexpectedly succeeded");
            common_chat_params pure;
            const auto prompt = render(&r, json::array({{{"role", "user"}, {"content", "hi"}}}), "", false, true, {}, "auto", &pure);
            check(r.templates && !r.template_probe_error.empty() && prompt == "hiassistant:", "Probe failure discarded renderable template");
            configure(r, pure);
            check(stream(r, "answer") == "answer", "Rendering-only parser lost answer");
            std::cout << "PASS capability probe failure keeps renderable Jinja and reports diagnostic\n";
        }
        {
            Runtime r(0);
            r.templates = common_chat_templates_init(nullptr,
                R"({% if tools %}{{ raise_exception('test: force pure-content analysis fallback') }}{% endif %}{% for m in messages %}{{ '<|im_start|>' + m.role + '\n' + m.content + '<|im_end|>\n' }}{% endfor %}{% if add_generation_prompt %}{{ '<|im_start|>assistant\n<think>\n</think>\n\n' }}{% endif %})");
            auto json_in = in;
            json_in.force_pure_content = true;
            json_in.json_schema = "{}";
            const auto pure = common_chat_templates_apply(r.templates.get(), json_in);
            check(pure.grammar.empty() && !json_grammar_fallback(pure, "{}").empty(), "Pure-content analysis fallback lost JSON constraints");
            std::cout << "PASS missing-grammar pure-content template uses JSON fallback\n";
        }
        {
            Runtime r(0);
            const auto prompt = render(&r, json::array({{{"role", "user"}, {"content", "hi"}}}), "chatml", false);
            check(prompt == "<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n", "Legacy prompt changed");
            r.stops = {"STOP"};
            check(stream(r, "helloSTOPignored") == "hello", "Legacy streaming changed");
            std::cout << "PASS legacy fallback template and raw stream\n";
        }
    } catch (const std::exception & e) { std::cerr << "FAIL " << e.what() << '\n'; return 1; }
}
