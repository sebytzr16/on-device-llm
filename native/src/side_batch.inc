// Separate contexts own their scheduler and CUDA streams/cuBLAS handles; only
// immutable model tensors are shared (ggml-cuda/common.cuh, owner, 2026-11-02).
struct SideSequence {
    Runtime formatting{0, false};
    std::vector<llama_token> prompt;
    int position = 0, generated = 0, maximum = 512;
    // The chat path's reasoning budget: the answer keeps [maximum] and the
    // reasoning is counted separately, so a helper still answers within its
    // budget (audit E08).
    int total_cap = 0, reasoning = 0, think_budget = 0, think_tokens = 0;
    bool in_think = false;
    std::string tail;
    llama_token next = LLAMA_TOKEN_NULL;
    bool active = false;
    Clock::time_point started{}, first{};
    double prefill_ms = 0;
    std::vector<std::string> stops;
    std::string held;
    ~SideSequence() { formatting.model = nullptr; }
};
struct SideBatch {
    std::mutex use;
    llama_context * ctx = nullptr;
    llama_model * model = nullptr;
    int context = 4096, gpu_layers = 0, allocated_context = 0, allocated_sequences = 0;
    int prefill_chunk = 512;
    bool adaptive = false;
    llama_context_params params{};
    llama_model_params model_params{};
    std::vector<ggml_backend_dev_t> devices;
    // The chat model's adapters and scales: sharing the weights must also share
    // the adapter that changes them (audit E06).
    std::vector<llama_adapter_lora *> adapters;
    std::vector<float> adapter_scales;
    std::string model_path, rope_scaling;
    llama_batch batch = llama_batch_init(512, 0, 1);
    bool offload_kv = false;
    std::string backend, result, error;
    std::vector<std::unique_ptr<SideSequence>> sequences;
    void invalidate() {
        std::lock_guard<std::mutex> lock(use);
        error = "chat model changed";
        if (ctx) llama_free(ctx);
        ctx = nullptr;
        for (auto & seq : sequences) { seq->formatting.reset(); seq->formatting.model = nullptr; }
        model = nullptr;
    }
    ~SideBatch() { if (ctx) llama_free(ctx); llama_batch_free(batch); }
};
static void close_side_batches(Runtime * r) {
    for (auto & weak : r->sides) if (auto side = weak.lock()) side->invalidate();
    r->sides.clear();
}
static SideBatch & side_of(void * h) { return **static_cast<std::shared_ptr<SideBatch> *>(h); }
static bool side_has_running_kv(const SideBatch & side) {
    return std::any_of(side.sequences.begin(), side.sequences.end(), [](const auto & seq) {
        return seq->active && seq->position > 0;
    });
}
static int side_required_context(const SideBatch & side, size_t prompt, int maximum) {
    return std::min(side.context, std::max(1024, int((prompt + maximum + 255) / 256 * 256)));
}

// Allocate after rendering the round's prompts, so unused slots and history do
// not force host KV. Grow only between batches; retain the allocation for reuse (owner, 2026-11-02).
// Include SWA and compute buffers, preserving 256 MiB for chat (owner, 2026-11-02).
static bool side_fits_gpu(SideBatch & side, int context, int count) {
    auto cp = side.params;
    cp.n_ctx = context * count; cp.n_seq_max = count;
    std::lock_guard<std::mutex> measurement(measure_mutex);
    uint32_t train = 0, measured_context = 0;
    const auto rows = common_fit_measure({side.model_path}, &side.model_params, &cp, &train, &measured_context, GGML_LOG_LEVEL_ERROR);
    for (const auto & row : rows) if (row.kind == common_memory_breakdown_row::DEVICE &&
        int64_t(row.context + row.compute) + (256LL << 20) > row.free) return false;
    return true;
}

static void resize_side(SideBatch & side, int context, int count, bool measured_fit = false) {
    context = std::max(context, side.allocated_context);
    count = std::max(count, side.allocated_sequences);
    if (side.ctx && context == side.allocated_context && count == side.allocated_sequences) return;
    if (side_has_running_kv(side)) throw std::runtime_error("Cannot resize helper context while sequences hold KV");
    if (side.ctx) llama_free(side.ctx);
    side.ctx = nullptr;
    auto cp = side.params;
    cp.n_ctx = context * count; cp.n_seq_max = count;
    if (cp.offload_kqv && !measured_fit && !side_fits_gpu(side, context, count)) cp.offload_kqv = false;
    // Shared weights are already resident; admit only the new host context
    // and compute buffers, with the chat load's RAM reserve policy.
    int64_t host_weights = 0;
    const int64_t host_total = measure(side.model_path.c_str(), side.model_params, cp, nullptr, nullptr, nullptr, &host_weights);
    const int64_t host = host_total - host_weights;
    const auto ram = system_memory();
    if (ram.available > 0 && host > ram.available - std::max<int64_t>(1ll << 30, ram.total / 8))
        throw std::runtime_error("Cannot allocate helper batch context");
    side.ctx = llama_init_from_model(side.model, cp);
    if (!side.ctx && cp.offload_kqv) {
        cp.offload_kqv = false;
        const int64_t retry_total = measure(side.model_path.c_str(), side.model_params, cp, nullptr, nullptr, nullptr, &host_weights);
        const auto retry_ram = system_memory();
        if (retry_ram.available > 0 && retry_total - host_weights > retry_ram.available - std::max<int64_t>(1ll << 30, retry_ram.total / 8))
            throw std::runtime_error("Cannot allocate helper batch context");
        side.ctx = llama_init_from_model(side.model, cp);
    }
    if (!side.ctx) throw std::runtime_error("Cannot allocate helper batch context");
    // A helper context without the chat's adapters would answer as the base
    // model (audit E06).
    if (!side.adapters.empty() && llama_set_adapters_lora(side.ctx, side.adapters.data(), side.adapters.size(), side.adapter_scales.data()) != 0) {
        llama_free(side.ctx); side.ctx = nullptr;
        throw std::runtime_error("The LoRA adapters could not be applied to the helper context.");
    }
    side.offload_kv = cp.offload_kqv;
    side.allocated_context = context; side.allocated_sequences = count;
}

void * od_side_open(void * h, const char * options) {
    MemoryAdmission memory_admission;
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> lock(r->use);
    try {
        memory_admission.check();
        if (!r->model || !r->ctx || r->released || r->embedding) throw std::runtime_error("chat model changed");
        auto s = json::parse(options);
        auto side = std::make_shared<SideBatch>();
        const int count = std::clamp(s.value("n_seq", 4), 1, 4);
        side->context = std::clamp(s.value("n_ctx_per_seq", 4096), 512, 65536);
        side->model = r->model;
        side->backend = r->backend;
        side->gpu_layers = r->effective.value("gpuLayers", 0);
        // Helpers share the chat's weights, so they inherit what changes the
        // tokens those weights see: RoPE/YaRN, the cache and attention policy
        // (audit E06). Only the batch layout below stays their own.
        const auto defaults = llama_context_default_params();
        auto cp = r->context_params;
        // Helpers have their own contexts; do not duplicate the chat's device
        // expert cache budget for each helper batch.
        cp.moe_cache_size = 0;
        cp.n_seq_max = count; cp.n_ctx = count * side->context;
        cp.n_batch = cp.n_ubatch = 512;
        cp.abort_callback = nullptr; cp.abort_callback_data = nullptr;
        cp.n_outputs_max = defaults.n_outputs_max;
        cp.n_outputs_max_per_seq = defaults.n_outputs_max_per_seq;
        cp.embeddings = defaults.embeddings;
        // Four threads beat six/eight for measured host attention; do not inherit chat tuning (owner, 2026-11-02).
        cp.n_threads = std::clamp(s.value("threads", std::min(4, int(od_cpu_cores()))), 1, std::max(1, int(od_cpu_cores())));
        cp.n_threads_batch = cp.n_threads;
        cp.n_ubatch = std::clamp(s.value("ubatch", 512), 32, 512);
        cp.kv_unified = false; cp.n_rs_seq = 0;
        cp.type_k = cp.type_v = cache_type(s.value("kvCacheType", "q8_0"));
        if (cp.type_k == GGML_TYPE_F8_E4M3 && !r->effective.value("supportsFp8Kv", false)) {
            cp.type_k = cp.type_v = GGML_TYPE_Q8_0;
            std::fprintf(stderr, "odllm: helper FP8 KV cache unsupported by loaded model/backend; using q8_0.\n");
        }
        // A quantized V cache needs flash attention, as the chat load enforces.
        if (cp.type_v != GGML_TYPE_F16 && cp.type_v != GGML_TYPE_F32 && cp.type_v != GGML_TYPE_BF16
            && cp.flash_attn_type == LLAMA_FLASH_ATTN_TYPE_DISABLED) cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        cp.offload_kqv = s.value("offload_kv", true);
        side->adaptive = s.value("adaptive", false);
        side->prefill_chunk = std::clamp(s.value("prefill_chunk", 512), 32, 512);
        side->params = cp;
        side->devices = r->devices;
        side->model_params = llama_model_default_params();
        side->model_params.devices = side->devices.data();
        side->model_params.n_gpu_layers = side->gpu_layers;
        side->model_path = r->model_path;
        side->adapters = r->adapters;
        side->adapter_scales = r->adapter_scales;
        side->rope_scaling = r->effective.value("ropeScaling", "model");
        if (!side->adaptive) resize_side(*side, side->context, count);
        for (int i = 0; i < count; ++i) {
            auto seq = std::make_unique<SideSequence>();
            seq->formatting.model = r->model;
            if (r->templates) seq->formatting.templates = common_chat_templates_init(r->model, common_chat_templates_source(r->templates.get()));
            side->sequences.push_back(std::move(seq));
        }
        r->sides.erase(std::remove_if(r->sides.begin(), r->sides.end(), [](const auto & weak) { return weak.expired(); }), r->sides.end());
        r->sides.push_back(side);
        return new std::shared_ptr<SideBatch>(std::move(side));
    } catch (const std::exception & e) { r->error = e.what(); return nullptr; }
}

int32_t od_side_submit(void * h, int32_t id, const char * request) {
    auto & side = side_of(h);
    std::lock_guard<std::mutex> lock(side.use);
    try {
        if (!side.model) throw std::runtime_error("chat model changed");
        auto & seq = *side.sequences.at(id);
        if (seq.active) throw std::runtime_error("Helper sequence is busy");
        const auto req = json::parse(request), settings = req.at("settings");
        seq.formatting.reset();
        const int thinking = settings.value("thinkingModeEnabled", false) ? std::clamp(settings.value("thinkingBudgetTokens", 512), 0, 512) : 0;
        // The answer keeps its own allowance; the reasoning gets a separate
        // budget below, as in the chat path (audit E08).
        seq.maximum = answer_limit(settings, side.context, 512);
        const int reserve = std::min(response_reserve(settings, side.context, 512) + thinking, side.context - 1);
        const auto prompt = tokenize(llama_model_get_vocab(side.model), render(&seq.formatting, req.at("messages"), req.value("fallbackTemplate", ""), settings.value("thinkingModeEnabled", false), true));
        if (prompt.empty() || prompt.size() + reserve > size_t(side.context)) throw std::runtime_error("Helper prompt exceeds context");
        seq.maximum = std::min(seq.maximum, side.context - (int)prompt.size());
        seq.total_cap = std::max(1, side.context - (int)prompt.size() - 1);
        seq.reasoning = 0; seq.think_tokens = 0; seq.in_think = false; seq.tail.clear(); seq.think_budget = 0;
        if (thinking) {
            // The reasoning ends at its budget, or where only the answer's room
            // is left: an unlimited budget still leaves the answer its reserve.
            const int left = std::max(1, seq.total_cap - response_reserve(settings, side.context, 512) - 64);
            const int budget = std::max(0, settings.value("thinkingBudgetTokens", 0));
            seq.think_budget = budget > 0 ? std::min(budget, left) : left;
        }
        // Allocate capacity for the full possible output, even when admission
        // reserves less room. The generation limit must not shrink with it.
        if (side.adaptive && (id >= side.allocated_sequences ||
            side_required_context(side, prompt.size(), seq.maximum + seq.think_budget) > side.allocated_context) && side_has_running_kv(side))
            // Dart keeps this request queued and retries after running work drains.
            return 1;
        seq.prompt = prompt;
        if (side.ctx && id < side.allocated_sequences && !llama_memory_seq_rm(llama_get_memory(side.ctx), id, -1, -1)) throw std::runtime_error("Cannot reset helper sequence");
        build_sampler(&seq.formatting, settings, "", false, {}, {}, "", false);
        for (auto token : seq.prompt) llama_sampler_accept(seq.formatting.sampler, token);
        seq.position = seq.generated = 0; seq.next = LLAMA_TOKEN_NULL;
        seq.prefill_ms = 0; seq.first = {}; seq.held.clear(); seq.stops.clear();
        for (const auto & stop : settings.value("stopSequences", json::array())) if (stop.is_string() && !stop.get<std::string>().empty()) seq.stops.push_back(stop.get<std::string>());
        seq.started = Clock::now(); seq.active = true;
        side.error.clear();
        return 0;
    } catch (const std::exception & e) { side.error = e.what(); return -1; }
}

const char * od_side_step(void * h) {
    MemoryAdmission memory_admission;
    auto & side = side_of(h);
    std::lock_guard<std::mutex> lock(side.use);
    json events = json::array();
    try {
        memory_admission.check();
        if (!side.model) throw std::runtime_error("chat model changed");
        if (!side.error.empty()) { const auto error = side.error; side.error.clear(); throw std::runtime_error(error); }
        if (side.adaptive) {
            int needed = std::min(side.context, 1024), count = 0;
            for (size_t id = 0; id < side.sequences.size(); ++id) {
                const auto & seq = *side.sequences[id];
                if (!seq.active) continue;
                needed = std::max(needed, side_required_context(side, seq.prompt.size(), seq.maximum + seq.think_budget));
                count = int(id) + 1;
            }
            if (count && !side_has_running_kv(side) &&
                (!side.ctx || needed > side.allocated_context || count > side.allocated_sequences)) {
                // Prefer room for three capped helpers, so a later helper joins
                // instead of queueing; when only the running jobs fit on the GPU,
                // size to them, since GPU KV is ~5x faster than host (owner, 2026-11-02).
                const int roomy = std::min(side.context, std::max(needed, 2048));
                const int roomy_count = std::min(int(side.sequences.size()), std::max(count, 3));
                if (!side.params.offload_kqv) resize_side(side, roomy, roomy_count);
                else if (side_fits_gpu(side, roomy, roomy_count)) resize_side(side, roomy, roomy_count, true);
                else if (side_fits_gpu(side, needed, count)) resize_side(side, needed, count, true);
                else resize_side(side, roomy, roomy_count);
            }
        }
        auto & batch = side.batch;
        batch.n_tokens = 0;
        const int active = int(std::count_if(side.sequences.begin(), side.sequences.end(), [](const auto & seq) { return seq->active; }));
        // Fill the batch fairly without issuing four tiny decodes for one prompt (owner, 2026-11-02).
        const int prefill_chunk = std::min(side.prefill_chunk, 512 / std::max(1, active));
        std::vector<int> outputs(side.sequences.size(), -1);
        for (size_t id = 0; id < side.sequences.size(); ++id) {
            auto & seq = *side.sequences[id];
            if (!seq.active) continue;
            // A not-yet-decoded sequence can wait across steps. Never put it
            // in the batch until an idle-boundary allocation can accommodate it.
            if (seq.position == 0 && (int(id) >= side.allocated_sequences ||
                side_required_context(side, seq.prompt.size(), seq.maximum + seq.think_budget) > side.allocated_context)) continue;
            const int remaining = int(seq.prompt.size()) - seq.position;
            const int count = remaining > 0 ? std::min(prefill_chunk, remaining) : 1;
            for (int i = 0; i < count; ++i) {
                const int row = batch.n_tokens++;
                batch.token[row] = remaining > 0 ? seq.prompt[seq.position] : seq.next;
                batch.pos[row] = seq.position++; batch.n_seq_id[row] = 1; batch.seq_id[row][0] = (llama_seq_id)id;
                batch.logits[row] = seq.position >= int(seq.prompt.size());
                if (batch.logits[row]) outputs[id] = row;
            }
        }
        const int rc = batch.n_tokens ? llama_decode(side.ctx, batch) : 0;
        if (rc != 0) throw std::runtime_error("Helper batch decode failed");
        const auto now = Clock::now();
        for (size_t id = 0; id < side.sequences.size(); ++id) {
            auto & seq = *side.sequences[id];
            if (!seq.active) continue;
            std::string text;
            if (outputs[id] >= 0) {
                const auto token = llama_sampler_sample(seq.formatting.sampler, side.ctx, outputs[id]);
                llama_sampler_accept(seq.formatting.sampler, token);
                if (seq.first == Clock::time_point{}) {
                    seq.first = now;
                    seq.prefill_ms = std::chrono::duration<double, std::milli>(now - seq.started).count();
                }
                if (llama_vocab_is_eog(llama_model_get_vocab(side.model), token)) {
                    seq.active = false; text.swap(seq.held);
                } else {
                    ++seq.generated; seq.next = token;
                    const std::string piece = common_token_to_piece(llama_model_get_vocab(side.model), token, false);
                    // Count the reasoning block with the chat path's tracker, so
                    // the budget and the model's own delimiters are the same
                    // (audit E08).
                    if (seq.think_budget > 0)
                        track_reasoning(seq.formatting.think_start, seq.formatting.think_ends, piece,
                            seq.think_tokens, seq.reasoning, seq.in_think, seq.tail);
                    seq.held += piece;
                    size_t stop_at = std::string::npos;
                    for (const auto & stop : seq.stops) stop_at = std::min(stop_at, seq.held.find(stop));
                    if (stop_at != std::string::npos) { text = seq.held.substr(0, stop_at); seq.held.clear(); seq.active = false; }
                    else {
                        size_t hold = 0;
                        for (const auto & stop : seq.stops) for (size_t n = 1; n < stop.size() && n <= seq.held.size(); ++n)
                            if (seq.held.compare(seq.held.size() - n, n, stop, 0, n) == 0) hold = std::max(hold, n);
                        text = seq.held.substr(0, seq.held.size() - hold); seq.held.erase(0, text.size());
                    }
                    // The answer keeps its allowance; the combined total stays
                    // inside the window.
                    if (seq.generated - seq.reasoning >= seq.maximum || seq.generated >= seq.total_cap
                        || seq.position >= side.context) { seq.active = false; text += seq.held; seq.held.clear(); }
                }
                if (seq.active && seq.think_budget > 0 && seq.in_think && seq.think_tokens >= seq.think_budget) {
                    // Budget spent: close the reasoning block on the model's
                    // behalf, let it see the closing tokens, then let it answer
                    // within its own allowance (audit E08).
                    const std::string close = reasoning_handoff(seq.formatting.think_ends);
                    const auto tokens = tokenize(llama_model_get_vocab(side.model), close, false);
                    if (tokens.empty()) throw std::runtime_error("Cannot close the reasoning block.");
                    if (seq.position + 1 + (int)tokens.size() >= side.context) {
                        seq.active = false; text += seq.held; seq.held.clear();
                    } else {
                        // The token sampled this step is decoded first, then the
                        // hand-off: both ride the prompt path so their positions
                        // stay exact in the shared batch.
                        if (seq.next != LLAMA_TOKEN_NULL) { seq.prompt.push_back(seq.next); seq.next = LLAMA_TOKEN_NULL; }
                        for (const auto t : tokens) {
                            seq.prompt.push_back(t);
                            llama_sampler_accept(seq.formatting.sampler, t);
                        }
                        seq.generated += (int)tokens.size(); seq.reasoning += (int)tokens.size();
                        seq.in_think = false; seq.tail.clear();
                        text += close;
                    }
                }
            }
            const double seconds = seq.first == Clock::time_point{} ? 0 : std::chrono::duration<double>(now - seq.first).count();
            json metrics = {{"tokens", seq.generated}, {"reasoningTokens", seq.reasoning}, {"promptTokens", seq.prompt.size()},
                {"backend", side.backend + " (shared)"}, {"gpuLayers", side.gpu_layers}, {"sharedGpu", true},
                {"sideContext", side.allocated_context}, {"sideSequences", side.allocated_sequences},
                {"ropeScaling", side.rope_scaling}, {"ropeFreqScale", side.params.rope_freq_scale},
                {"adapters", (int)side.adapters.size()},
                {"threads", llama_n_threads(side.ctx)}, {"microBatchSize", llama_n_ubatch(side.ctx)},
                {"kvCacheType", ggml_type_name(side.params.type_k)},
                {"offloadKv", side.offload_kv}, {"sideKv", side.offload_kv ? "GPU" : "host"},
                {"prefillProgress", std::min(1.0, double(seq.position) / seq.prompt.size())}};
            if (seq.first != Clock::time_point{}) {
                metrics["prefillMs"] = metrics["firstTokenMs"] = seq.prefill_ms;
                metrics["tokensPerSecond"] = seconds > 0 ? std::max(0, seq.generated - 1) / seconds : 0;
            }
            events.push_back({{"seq", id}, {"bytes", std::vector<uint8_t>(text.begin(), text.end())}, {"done", !seq.active}, {"metrics", metrics}});
        }
        side.result = json({{"events", events}}).dump();
    } catch (const std::exception & e) { side.result = json({{"error", e.what()}}).dump(); }
    return side.result.c_str();
}
void od_side_cancel(void * h, int32_t id) {
    auto & side = side_of(h);
    std::lock_guard<std::mutex> lock(side.use);
    if (id >= 0 && size_t(id) < side.sequences.size()) side.sequences[id]->active = false;
}
void od_side_close(void * h) {
    if (!h) return;
    side_of(h).invalidate();
    delete static_cast<std::shared_ptr<SideBatch> *>(h);
}
