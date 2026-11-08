// Separate contexts own their scheduler and CUDA streams/cuBLAS handles; only
// immutable model tensors are shared (ggml-cuda/common.cuh, owner, 2026-11-02).
struct SideSequence {
    Runtime formatting{0, false};
    std::vector<llama_token> prompt;
    int position = 0, generated = 0, maximum = 512;
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
    std::string model_path;
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
    const auto rows = common_fit_measure(side.model_path.c_str(), &side.model_params, &cp, &train, &measured_context, GGML_LOG_LEVEL_ERROR);
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
    side.ctx = llama_init_from_model(side.model, cp);
    if (!side.ctx && cp.offload_kqv) {
        cp.offload_kqv = false;
        side.ctx = llama_init_from_model(side.model, cp);
    }
    if (!side.ctx) throw std::runtime_error("Cannot allocate helper batch context");
    side.offload_kv = cp.offload_kqv;
    side.allocated_context = context; side.allocated_sequences = count;
}

void * od_side_open(void * h, const char * options) {
    auto * r = static_cast<Runtime *>(h);
    std::lock_guard<std::mutex> lock(r->use);
    try {
        if (!r->model || !r->ctx || r->released || r->embedding) throw std::runtime_error("chat model changed");
        auto s = json::parse(options);
        auto side = std::make_shared<SideBatch>();
        const int count = std::clamp(s.value("n_seq", 4), 1, 4);
        side->context = std::clamp(s.value("n_ctx_per_seq", 4096), 512, 65536);
        side->model = r->model;
        side->backend = r->backend;
        side->gpu_layers = r->effective.value("gpuLayers", 0);
        auto cp = llama_context_default_params();
        cp.n_seq_max = count; cp.n_ctx = count * side->context;
        cp.n_batch = cp.n_ubatch = 512;
        // Four threads beat six/eight for measured host attention; do not inherit chat tuning (owner, 2026-11-02).
        cp.n_threads = std::clamp(s.value("threads", std::min(4, int(od_cpu_cores()))), 1, std::max(1, int(od_cpu_cores())));
        cp.n_threads_batch = cp.n_threads;
        cp.n_ubatch = std::clamp(s.value("ubatch", 512), 32, 512);
        cp.kv_unified = false; cp.n_rs_seq = 0;
        cp.type_k = cp.type_v = cache_type(s.value("kvCacheType", "q8_0"));
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        cp.offload_kqv = s.value("offload_kv", true);
        side->adaptive = s.value("adaptive", false);
        side->prefill_chunk = std::clamp(s.value("prefill_chunk", 512), 32, 512);
        side->params = cp;
        side->devices = r->devices;
        side->model_params = llama_model_default_params();
        side->model_params.devices = side->devices.data();
        side->model_params.n_gpu_layers = side->gpu_layers;
        side->model_path = r->model_path;
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
        seq.maximum = answer_limit(settings, side.context, 512) + thinking;
        const int reserve = std::min(response_reserve(settings, side.context, 512) + thinking, side.context - 1);
        const auto prompt = tokenize(llama_model_get_vocab(side.model), render(&seq.formatting, req.at("messages"), req.value("fallbackTemplate", ""), settings.value("thinkingModeEnabled", false), true));
        if (prompt.empty() || prompt.size() + reserve > size_t(side.context)) throw std::runtime_error("Helper prompt exceeds context");
        seq.maximum = std::min(seq.maximum, side.context - (int)prompt.size());
        // Allocate capacity for the full possible output, even when admission
        // reserves less room. The generation limit must not shrink with it.
        if (side.adaptive && (id >= side.allocated_sequences ||
            side_required_context(side, prompt.size(), seq.maximum) > side.allocated_context) && side_has_running_kv(side))
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
    auto & side = side_of(h);
    std::lock_guard<std::mutex> lock(side.use);
    json events = json::array();
    try {
        if (!side.model) throw std::runtime_error("chat model changed");
        if (!side.error.empty()) { const auto error = side.error; side.error.clear(); throw std::runtime_error(error); }
        if (side.adaptive) {
            int needed = std::min(side.context, 1024), count = 0;
            for (size_t id = 0; id < side.sequences.size(); ++id) {
                const auto & seq = *side.sequences[id];
                if (!seq.active) continue;
                needed = std::max(needed, side_required_context(side, seq.prompt.size(), seq.maximum));
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
                side_required_context(side, seq.prompt.size(), seq.maximum) > side.allocated_context)) continue;
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
                    seq.held += common_token_to_piece(llama_model_get_vocab(side.model), token, false);
                    size_t stop_at = std::string::npos;
                    for (const auto & stop : seq.stops) stop_at = std::min(stop_at, seq.held.find(stop));
                    if (stop_at != std::string::npos) { text = seq.held.substr(0, stop_at); seq.held.clear(); seq.active = false; }
                    else {
                        size_t hold = 0;
                        for (const auto & stop : seq.stops) for (size_t n = 1; n < stop.size() && n <= seq.held.size(); ++n)
                            if (seq.held.compare(seq.held.size() - n, n, stop, 0, n) == 0) hold = std::max(hold, n);
                        text = seq.held.substr(0, seq.held.size() - hold); seq.held.erase(0, text.size());
                    }
                    if (seq.generated >= seq.maximum || seq.position >= side.context) { seq.active = false; text += seq.held; seq.held.clear(); }
                }
            }
            const double seconds = seq.first == Clock::time_point{} ? 0 : std::chrono::duration<double>(now - seq.first).count();
            json metrics = {{"tokens", seq.generated}, {"promptTokens", seq.prompt.size()},
                {"backend", side.backend + " (shared)"}, {"gpuLayers", side.gpu_layers}, {"sharedGpu", true},
                {"sideContext", side.allocated_context}, {"sideSequences", side.allocated_sequences},
                {"threads", llama_n_threads(side.ctx)}, {"microBatchSize", llama_n_ubatch(side.ctx)},
                {"kvCacheType", side.params.type_k == GGML_TYPE_F16 ? "f16" : "q8_0"},
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
