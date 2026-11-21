// Adapters for the pinned ik_llama.cpp API. Included only by the ik bridge.
#include "chat-peg-parser.h"
#include "common.h"
#include "json-schema-to-grammar.h"
#include "speculative.h"
#include "mtmd.h"
#include "mtmd-helper.h"

#include <algorithm>
#include <functional>
#include <map>
#include <memory>
#include <stdexcept>
#include <vector>

[[noreturn]] static void ik_unsupported(const char * feature) {
    throw std::runtime_error(std::string(feature) + " is unsupported on ik_llama.");
}

#define common_json nlohmann::ordered_json
#define common_cpu_get_num_math cpu_get_num_math
#define llama_tokenize llama_vocab_tokenize
#define llama_token_to_piece llama_token_to_piece_vocab
#define llama_model_free llama_free_model
#define llama_model_n_ctx_train llama_n_ctx_train
#define llama_model_n_layer llama_n_layer
#define llama_model_n_embd_out llama_model_n_embd
#define llama_model_rope_freq_scale_train llama_rope_freq_scale_train
#define llama_perf_context_reset llama_reset_timings
using llama_memory_t = llama_context *;
static llama_context * llama_get_memory(llama_context * ctx) { return ctx; }
#define llama_memory_seq_rm llama_kv_cache_seq_rm
#define llama_memory_seq_add llama_kv_cache_seq_add
#define llama_memory_seq_pos_min llama_kv_cache_seq_pos_min
#define llama_memory_seq_pos_max llama_kv_cache_seq_pos_max
#define llama_memory_can_shift llama_supports_ctx_shift
#define llama_memory_clear(ctx, clear_data) llama_kv_cache_clear(ctx)
// The bridge calls both names: the _ext variants pass the fork's flags
// argument through, and the plain 2/4-argument ones (prompt store) take 0.
#define llama_state_seq_get_size_ext llama_state_seq_get_size
#define llama_state_seq_get_data_ext llama_state_seq_get_data
#define llama_state_seq_set_data_ext llama_state_seq_set_data

static size_t llama_state_seq_get_size(llama_context * ctx, llama_seq_id seq) {
    return llama_state_seq_get_size(ctx, seq, 0);
}
static size_t llama_state_seq_get_data(llama_context * ctx, uint8_t * data, size_t size, llama_seq_id seq) {
    return llama_state_seq_get_data(ctx, data, size, seq, 0);
}
static size_t llama_state_seq_set_data(llama_context * ctx, const uint8_t * data, size_t size, llama_seq_id seq) {
    return llama_state_seq_set_data(ctx, data, size, seq, 0);
}

// The bridge's implicit single-sequence batches append to the live cache.
// ik uses explicit all_pos_0 for these batches, including after a rewind.
static llama_batch llama_batch_get_one(llama_token * tokens, int32_t count) {
    return llama_batch_get_one(tokens, count, -1, 0);
}
static int ik_decode(llama_context * ctx, llama_batch batch) {
    if (!batch.pos && batch.all_pos_0 == -1) {
        batch.all_pos_0 = llama_kv_cache_seq_pos_max(ctx, batch.all_seq_id) + 1;
    }
    return llama_decode(ctx, batch);
}
#define llama_decode ik_decode

using llama_adapter_lora = llama_lora_adapter;
#define llama_adapter_lora_init llama_lora_adapter_init
static int llama_set_adapters_lora(llama_context * ctx, llama_adapter_lora ** adapters, size_t count, const float * scales) {
    for (size_t i = 0; i < count; ++i) {
        if (llama_lora_adapter_set(ctx, adapters[i], scales[i]) != 0) {
            llama_lora_adapter_clear(ctx);
            return -1;
        }
    }
    return 0;
}

// The fork accepts text in its PEG parser. Keep byte offsets for stream
// truncation, and pass the original special-token spellings through as text.
struct common_chat_input {
    std::string text;
    size_t size() const { return text.size(); }
    void append(const std::string & value, llama_token = LLAMA_TOKEN_NULL) { text += value; }
    void truncate(size_t length) { text.resize(length); }
    std::string substr(size_t start, size_t count) const { return text.substr(start, count); }
};

// ik exposes sampling operations and grammar separately, rather than the
// upstream sampler chain. Keep both states local to their generation context.
struct IkSampler {
    explicit IkSampler(llama_context * context) : ctx(context) {}
    llama_context * ctx;
    std::vector<std::function<void(llama_token_data_array *)>> stages;
    std::vector<llama_token> history;
    size_t history_limit = 0;
    std::unique_ptr<llama_sampler_dry, decltype(&llama_sampler_dry_free)> dry{nullptr, llama_sampler_dry_free};
    std::unique_ptr<llama_grammar, decltype(&llama_grammar_free)> grammar{nullptr, llama_grammar_free};

    void accept(llama_token token) {
        if (grammar) llama_grammar_accept_token(grammar.get(), ctx, token);
        if (dry) llama_sampler_dry_accept(dry.get(), token);
        if (history_limit == 0) return;
        if (history.size() == history_limit) history.erase(history.begin());
        history.push_back(token);
    }

    void apply(llama_token_data_array * candidates) {
        if (grammar) llama_grammar_apply(grammar.get(), ctx, candidates);
        for (const auto & stage : stages) stage(candidates);
    }
};

static void ik_sampler_free(IkSampler * sampler) { delete sampler; }
static void ik_sampler_accept(IkSampler * sampler, llama_token token) { sampler->accept(token); }
static void ik_sampler_apply(IkSampler * sampler, llama_token_data_array * candidates) { sampler->apply(candidates); }

static std::unique_ptr<IkSampler> ik_make_sampler(llama_context * ctx, const common_json & s) {
    auto sampler = std::make_unique<IkSampler>(ctx);
    auto * state = sampler.get();
    const auto seed = s.value("seed", 0);
    llama_set_rng_seed(ctx, seed <= 0 ? LLAMA_DEFAULT_SEED : static_cast<uint32_t>(seed));

    std::map<llama_token, float> biases;
    const auto bias = s.value("logitBias", common_json::object());
    const auto * vocab = llama_model_get_vocab(llama_get_model(ctx));
    if (bias.is_object()) {
        for (auto it = bias.begin(); it != bias.end(); ++it) {
            if (!it.value().is_number()) continue;
            try {
                size_t used = 0;
                const auto token = std::stoi(it.key(), &used);
                if (used == it.key().size() && token >= 0 && token < llama_vocab_n_tokens(vocab))
                    biases.emplace(token, std::clamp(it.value().get<float>(), -100.0f, 100.0f));
            } catch (const std::exception &) {}
        }
    }
    if (!biases.empty()) sampler->stages.emplace_back([biases = std::move(biases)](auto * candidates) {
        for (size_t i = 0; i < candidates->size; ++i) {
            auto & candidate = candidates->data[i];
            const auto bias = biases.find(candidate.id);
            if (bias != biases.end()) candidate.logit += bias->second;
        }
        candidates->sorted = false;
    });

    const int last_n = s.value("repeatLastN", 64);
    const float repeat = s.value("repetitionPenalty", 1.0f);
    const float frequency = s.value("frequencyPenalty", 0.0f);
    const float presence = s.value("presencePenalty", 0.0f);
    // As in the bundled engine, a last-N of zero (or below) is the whole context.
    if (repeat != 1.0f || frequency != 0 || presence != 0)
        sampler->history_limit = last_n <= 0 ? llama_n_ctx(ctx) : std::min<uint32_t>(last_n, llama_n_ctx(ctx));
    const float dry = s.value("dryMultiplier", 0.0f);
    if (dry > 0) {
        const char * breakers[] = {"\n", ":", "\"", "*"};
        sampler->dry.reset(llama_sampler_init_dry(vocab, dry, s.value("dryBase", 1.75f),
            s.value("dryAllowedLength", 2), s.value("dryPenaltyLastN", -1), breakers, 4));
        if (!sampler->dry) throw std::runtime_error("Could not initialize ik_llama DRY sampling.");
    }

    const float temperature = s.value("temperature", 0.7f);
    const std::vector<std::string> defaults{"penalties", "dry", "top_n_sigma", "top_k", "typ_p", "top_p", "min_p", "xtc", "temperature"};
    std::vector<std::string> order;
    if (temperature > 0 && s.contains("samplerOrder") && s["samplerOrder"].is_array()) {
        for (const auto & name : s["samplerOrder"]) if (name.is_string()) order.push_back(name.get<std::string>());
    }
    for (const auto & name : defaults)
        if (std::find(order.begin(), order.end(), name) == order.end()) order.push_back(name);
    for (const auto & name : order) {
        if (name == "penalties" && sampler->history_limit) {
            sampler->stages.emplace_back([=](auto * candidates) {
                llama_sample_repetition_penalties(ctx, candidates, state->history.data(), state->history.size(), repeat, frequency, presence);
            });
        } else if (name == "dry" && sampler->dry) {
            sampler->stages.emplace_back([=](auto * candidates) { llama_sample_dry(ctx, state->dry.get(), candidates); });
        }
        if (temperature <= 0) continue;
        if (name == "top_k") {
            const int value = s.value("topK", 40);
            if (value > 0) sampler->stages.emplace_back([=](auto * candidates) { llama_sample_top_k(ctx, candidates, value, 1); });
        } else if (name == "typ_p" || name == "typical") {
            const float value = s.value("typicalP", 1.0f);
            if (value < 1.0f) sampler->stages.emplace_back([=](auto * candidates) { llama_sample_typical(ctx, candidates, value, 1); });
        } else if (name == "top_p") {
            const float value = s.value("topP", 0.95f);
            sampler->stages.emplace_back([=](auto * candidates) { llama_sample_top_p(ctx, candidates, value, 1); });
        } else if (name == "min_p") {
            const float value = s.value("minP", 0.05f);
            sampler->stages.emplace_back([=](auto * candidates) { llama_sample_min_p(ctx, candidates, value, 1); });
        } else if (name == "temperature" || name == "temp") {
            sampler->stages.emplace_back([=](auto * candidates) { llama_sample_temp(ctx, candidates, temperature); });
        } else if (name == "xtc") {
            const float probability = s.value("xtcProbability", 0.0f);
            const float threshold = s.value("xtcThreshold", 0.1f);
            if (probability > 0) sampler->stages.emplace_back([=](auto * candidates) { llama_sample_xtc(ctx, candidates, probability, threshold, 1); });
        } else if (name == "top_n_sigma") {
            const float value = s.value("topNSigma", -1.0f);
            if (value > 0) sampler->stages.emplace_back([=](auto * candidates) { llama_sample_top_n_sigma(ctx, candidates, value); });
        }
    }
    if (temperature <= 0) {
        sampler->stages.emplace_back([](auto * candidates) {
            const auto * end = candidates->data + candidates->size;
            const auto * best = std::max_element(candidates->data, candidates->data + candidates->size,
                [](const auto & a, const auto & b) { return a.logit < b.logit; });
            candidates->selected = best == end ? -1 : best - candidates->data;
        });
        return sampler;
    }
    sampler->stages.emplace_back([=](auto * candidates) {
        if (candidates->size == 0) { candidates->selected = -1; return; }
        // llama_sample_token() binary-searches cumulative probabilities, so
        // the array must be in descending order; a filtering stage only sorts
        // when it runs, and every one can be disabled.
        llama_sample_softmax(ctx, candidates);
        const auto token = llama_sample_token(ctx, candidates);
        const auto * end = candidates->data + candidates->size;
        const auto * chosen = std::find_if(candidates->data, candidates->data + candidates->size,
            [token](const auto & candidate) { return candidate.id == token; });
        candidates->selected = chosen == end ? -1 : chosen - candidates->data;
    });
    return sampler;
}

#define llama_sampler IkSampler
#define llama_sampler_free ik_sampler_free
#define llama_sampler_accept ik_sampler_accept
#define llama_sampler_apply ik_sampler_apply
