// Windows desktop only. stdout is exclusively UTF-8 JSONL; diagnostics use stderr.
#include "arg.h"
#include "chat.h"
#include "common.h"
#include "diffusion.h"
#include "ggml-backend.h"
#include "llama.h"
#include "nlohmann/json.hpp"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <queue>
#include <thread>

using json = nlohmann::ordered_json;
using Clock = std::chrono::steady_clock;
static double ms(Clock::time_point t) {
    return std::chrono::duration<double, std::milli>(Clock::now() - t).count();
}
static void emit(const json & j) {
    std::cout << j.dump(-1, ' ', false, json::error_handler_t::replace) << std::endl;
}
// A block boundary can split a multibyte character. Sent as is, JSON turns the
// partial bytes into U+FFFD, which the next block then contradicts; hold them
// back until the character is complete.
static std::string without_partial_utf8(std::string s) {
    size_t i = s.size(), tail = 0;
    while (i > 0 && tail < 3 && (static_cast<unsigned char>(s[i - 1]) & 0xC0) == 0x80) { --i; ++tail; }
    if (i == 0) return s;
    const unsigned char lead = static_cast<unsigned char>(s[i - 1]);
    const size_t need = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
    if (need > tail + 1) s.resize(i - 1);
    return s;
}
static std::string visible(const llama_vocab * vocab, const std::vector<llama_token> & tokens) {
    std::string text = common_detokenize(vocab, tokens, false);
    const auto thought = text.find("<|channel>thought");
    if (thought != std::string::npos) {
        const auto end = text.find("<channel|>", thought);
        return end == std::string::npos ? "" : without_partial_utf8(text.substr(end + 10));
    }
    return without_partial_utf8(text);
}
struct Progress {
    std::atomic<bool> * cancel;
    const llama_vocab * vocab;
    int prefix = 0, block = 0, steps = 0;
};
static bool progress(int32_t step, int32_t total, const llama_token * tokens, int32_t n, void * ptr) {
    auto & p = *static_cast<Progress *>(ptr);
    ++p.steps;
    // A canvas snapshot can revise previous positions. It is deliberately
    // separate from committed block text (the TextEngine stream is append-only).
    std::vector<llama_token> canvas;
    for (int i = p.prefix; i < n; ++i) {
        if (llama_vocab_is_eog(p.vocab, tokens[i])) break;
        if (tokens[i] != llama_vocab_mask(p.vocab)) canvas.push_back(tokens[i]);
    }
    emit({{"event", "progress"}, {"block", p.block}, {"step", step + 1},
          {"totalSteps", total}, {"canvas", visible(p.vocab, canvas)}});
    return !p.cancel->load();
}
int main(int argc, char ** argv) {
    try {
        common_init();
        common_params params;
        if (!common_params_parse(argc, argv, params, LLAMA_EXAMPLE_DIFFUSION)) return 1;
        llama_backend_init();
        const auto started = Clock::now();
        auto mp = llama_model_default_params();
        mp.n_gpu_layers = params.n_gpu_layers;
        mp.load_mode = params.load_mode;
        mp.tensor_buft_overrides = params.tensor_buft_overrides.empty() ? nullptr : params.tensor_buft_overrides.data();
        llama_model * model = llama_model_load_from_file(params.model.path.c_str(), mp);
        if (!model) throw std::runtime_error("Model load failed");
        if (!llama_model_is_diffusion(model)) throw std::runtime_error("Not a diffusion model");
        char buf[64];
        auto meta_i = [&](const char * key, int def) {
            return llama_model_meta_val_str(model, key, buf, sizeof(buf)) >= 0 ? std::stoi(buf) : def;
        };
        auto meta_f = [&](const char * key, float def) {
            return llama_model_meta_val_str(model, key, buf, sizeof(buf)) >= 0 ? std::stof(buf) : def;
        };
        const int canvas = meta_i("diffusion.canvas_length", 0);
        if (canvas <= 0) throw std::runtime_error("Missing diffusion canvas length");
        llama_diffusion_set_sc(model, nullptr, 0.0f, 1.0f, true);
        auto cp = llama_context_default_params();
        cp.n_ctx = params.n_ctx;
        cp.n_batch = cp.n_ubatch = params.n_ubatch;
        cp.flash_attn_type = params.flash_attn_type;
        auto * ctx = llama_init_from_model(model, cp);
        if (!ctx) throw std::runtime_error("Context allocation failed; reduce context/ubatch or GPU layers");
        llama_set_n_threads(ctx, params.cpuparams.n_threads, params.cpuparams_batch.n_threads);
        auto templates = common_chat_templates_init(model, "");
        auto * vocab = llama_model_get_vocab(model);
        const double load_ms = ms(started);
        emit({{"ready", true}, {"loadMs", load_ms}, {"canvasLength", canvas}, {"contextSize", cp.n_ctx}});

        // stdin must remain readable during synchronous denoising, so cancel
        // interrupts at the next step boundary without unloading the model.
        std::atomic<bool> cancel{false};
        std::mutex mutex;
        std::condition_variable wake;
        std::queue<json> requests;
        bool eof = false, active = false;
        std::thread reader([&] {
            std::string line;
            while (std::getline(std::cin, line)) {
                try {
                    auto request = json::parse(line);
                    std::lock_guard<std::mutex> guard(mutex);
                    if (request.value("cancel", false)) {
                        cancel = true;
                    } else {
                        // Single-flight protocol. Queue at most one request.
                        if (active || !requests.empty()) continue;
                        cancel = false;
                        requests.push(std::move(request));
                        wake.notify_one();
                    }
                } catch (const std::exception & e) {
                    std::lock_guard<std::mutex> guard(mutex);
                    if (!active && requests.empty()) {
                        requests.push({{"protocolError", e.what()}});
                        wake.notify_one();
                    }
                }
            }
            std::lock_guard<std::mutex> guard(mutex);
            eof = true;
            wake.notify_one();
        });
        for (;;) {
            json request;
            {
                std::unique_lock<std::mutex> guard(mutex);
                wake.wait(guard, [&] { return eof || !requests.empty(); });
                if (requests.empty()) break;
                request = std::move(requests.front()); requests.pop(); active = true;
            }
            const auto turn = Clock::now();
            try {
                if (request.contains("protocolError")) throw std::runtime_error(request["protocolError"].get<std::string>());
                std::vector<common_chat_msg> messages;
                for (const auto & item : request.at("messages")) {
                    common_chat_msg msg;
                    msg.role = item.at("role").get<std::string>();
                    msg.content = item.at("content").get<std::string>();
                    if (msg.role != "system" && msg.role != "user" && msg.role != "assistant")
                        throw std::runtime_error("Only system/user/assistant text messages are supported");
                    messages.push_back(std::move(msg));
                }
                common_chat_templates_inputs inputs;
                inputs.messages = messages;
                inputs.add_generation_prompt = true;
                inputs.enable_thinking = false;
                auto prefix = common_tokenize(vocab, common_chat_templates_apply(templates.get(), inputs).prompt.str(), true, true);
                const int budget = std::clamp(request.value("maxTokens", 512), 1, (int) cp.n_ctx);
                if (request.value("preview", false)) {
                    const int reserve = ((budget + canvas - 1) / canvas) * canvas;
                    { std::lock_guard<std::mutex> guard(mutex); active = false; }
                    emit({{"done", true}, {"promptTokens", prefix.size()}, {"contextSize", cp.n_ctx},
                          {"reservedTokens", reserve}, {"availableTokens", (int)cp.n_ctx - (int)prefix.size() - reserve},
                          {"fits", prefix.size() + reserve <= cp.n_ctx}});
                    continue;
                }
                if (prefix.size() + ((budget + canvas - 1) / canvas) * canvas > cp.n_ctx)
                    throw std::runtime_error("Prompt plus rounded canvas budget exceeds context/ubatch; shorten history or maxTokens");
                diffusion_eb_params eb;
                eb.max_denoising_steps = params.diffusion.eb_max_steps > 0 ? params.diffusion.eb_max_steps : meta_i("diffusion.eb_max_steps", 48);
                eb.t_min = meta_f("diffusion.eb_t_min", 0.4f);
                eb.t_max = meta_f("diffusion.eb_t_max", 0.8f);
                // temperature scales the reference schedule; zero approaches greedy.
                const float scale = std::clamp(request.value("temperature", 0.8f), 0.01f, 2.0f) / 0.8f;
                eb.t_min *= scale; eb.t_max *= scale;
                eb.entropy_bound = meta_f("diffusion.eb_entropy_bound", 0.1f);
                eb.stability_threshold = meta_i("diffusion.eb_stability_threshold", 1);
                eb.confidence_threshold = meta_f("diffusion.eb_confidence_threshold", 0.005f);
                eb.kv_cache = params.diffusion.eb_kv_cache != 2;
                eb.gpu_sampling = params.diffusion.eb_gpu_sampling != 2;
                eb.gpu_sample_reduce = eb.gpu_sampling && params.diffusion.eb_gpu_sample_reduce != 2;
                eb.seed = params.sampling.seed;
                Progress state{&cancel, vocab};
                eb.step_callback = progress; eb.step_callback_user_data = &state;
                std::vector<llama_token> output(cp.n_ctx), response;
                double first_block_ms = 0;
                bool ended = false;
                for (int b = 0; (int) response.size() < budget && !cancel; ++b) {
                    state.prefix = (int) prefix.size(); state.block = b;
                    eb.max_length = state.prefix + canvas;
                    int32_t generated = 0;
                    diffusion_generate_entropy_bound(ctx, prefix.data(), output.data(), state.prefix, eb, generated);
                    if (cancel) break;
                    if (generated < eb.max_length) throw std::runtime_error("Denoising failed");
                    std::vector<llama_token> block;
                    for (int i = state.prefix; i < generated && (int)(response.size() + block.size()) < budget; ++i) {
                        if (llama_vocab_is_eog(vocab, output[i])) { ended = true; break; }
                        bool loop = false;
                        for (int stride = 1; stride <= 2; ++stride) {
                            int reps = 0;
                            for (int j = i; j + stride < generated && output[j] == output[j + stride]; j += stride) ++reps;
                            if (reps >= 6) loop = true;
                        }
                        if (loop) { ended = true; break; }
                        block.push_back(output[i]);
                    }
                    response.insert(response.end(), block.begin(), block.end());
                    prefix.insert(prefix.end(), block.begin(), block.end());
                    if (b == 0) first_block_ms = ms(turn);
                    emit({{"event", "block"}, {"block", b}, {"text", visible(vocab, response)}});
                    if (ended) break;
                }
                const double elapsed = ms(turn);
                const auto text = visible(vocab, response);
                const auto answer_tokens = common_tokenize(vocab, text, false, false).size();
                { std::lock_guard<std::mutex> guard(mutex); active = false; }
                emit({{"done", true}, {"text", text},
                    {"stats", {{"loadMs", load_ms}, {"generationMs", elapsed}, {"firstBlockMs", first_block_ms},
                    {"answerTokens", answer_tokens}, {"generatedTokens", response.size()}, {"tokensPerSecond", answer_tokens * 1000.0 / std::max(1.0, elapsed)},
                    {"steps", state.steps}, {"finishReason", cancel ? "cancelled" : ended ? "eog" : "length"}}}});
            } catch (const std::exception & e) {
                { std::lock_guard<std::mutex> guard(mutex); active = false; }
                emit({{"done", true}, {"error", e.what()}, {"text", ""}});
            }
        }
        reader.join();
        llama_free(ctx); llama_model_free(model); llama_backend_free();
    } catch (const std::exception & e) {
        emit({{"error", e.what()}, {"done", true}}); return 1;
    }
    return 0;
}
