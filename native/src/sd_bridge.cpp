#include "sd_bridge.h"
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

// The original API lives at the source root; current releases use include/.
#if __has_include("../stable-diffusion.cpp/include/stable-diffusion.h")
#include "../stable-diffusion.cpp/include/stable-diffusion.h"
#define OD_SD_AVAILABLE 1
#ifndef OD_SD_MODERN_API
#define OD_SD_MODERN_API 1
#endif
// The build script compiles upstream's media writer in to save videos.
#if defined(OD_SD_MEDIA_IO)
#include "common/media_io.h"
#define OD_SD_HAS_MEDIA_IO 1
#endif
#elif __has_include("../stable-diffusion.cpp/stable-diffusion.h")
#include "../stable-diffusion.cpp/stable-diffusion.h"
#define OD_SD_AVAILABLE 1
#elif __has_include("stable-diffusion.h")
#include "stable-diffusion.h"
#define OD_SD_AVAILABLE 1
#else
#define OD_SD_AVAILABLE 0
struct sd_ctx_t;
#endif

struct od_sd_ctx_t {
    sd_ctx_t* sd_ctx = nullptr;
    std::string error_msg;
    std::atomic<bool> cancelled{false};
    int clip_skip = -1;
    bool vae_tiling = false;
    std::string schedule = "default";
#if OD_SD_AVAILABLE && OD_SD_MODERN_API
    // The ESRGAN upscaler stays loaded between upscales of one path (P3-14).
    upscaler_ctx_t* upscaler = nullptr;
    std::string upscaler_path;
    void drop_upscaler() {
        if (upscaler) free_upscaler_ctx(upscaler);
        upscaler = nullptr;
        upscaler_path.clear();
    }
#endif
};

namespace {
constexpr const char* unavailable = "stable-diffusion.cpp is unavailable; fetch and rebuild the SD bridge";

// Keep exceptions, including allocation failures, inside the C ABI.
void error(od_sd_ctx_t* ctx, const char* message) noexcept {
    if (ctx) { try { ctx->error_msg = message; } catch (...) {} }
}

#if OD_SD_AVAILABLE
// Upstream progress callbacks are process-global. Serialize backend operations
// across contexts so callback data cannot be replaced during a generation.
// Callbacks may call od_sd_cancel, but must not reenter load/generate/destroy.
std::mutex backend_mutex;

// The last upstream error line, so a failed load can say why (wrong file,
// unknown tensors) instead of only "failed". Written under backend_mutex.
std::string last_log_error;

// OD_SD_VERBOSE=1 prints stable-diffusion.cpp's info and debug lines too.
const bool verbose_log = [] {
    const char* v = std::getenv("OD_SD_VERBOSE");
    return v && *v && *v != '0';
}();

void log_line(enum sd_log_level_t level, const char* text, void*) {
    if ((level < SD_LOG_WARN && !verbose_log) || !text) return;
    std::fputs(text, stderr);
    if (level == SD_LOG_ERROR) {
        last_log_error = text;
        while (!last_log_error.empty() && std::isspace(static_cast<unsigned char>(last_log_error.back())))
            last_log_error.pop_back();
    }
}

std::string with_cause(const char* message) {
    return last_log_error.empty() ? message : std::string(message) + ": " + last_log_error;
}

void watch_log() {
    static std::once_flag once;
    std::call_once(once, [] { sd_set_log_callback(log_line, nullptr); });
    last_log_error.clear();
}

struct Value { char kind = 0; std::string text; };

// Small JSON reader: validates the entire object, decodes JSON string escapes
// (including UTF-16 surrogate pairs), and retains only top-level fields.
class Json {
    const char* p;
    std::map<std::string, Value> fields;
    static bool digit(char c) { return c >= '0' && c <= '9'; }
    void ws() { while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') ++p; }
    void expect(char c) { ws(); if (*p != c) fail(); ++p; }
    [[noreturn]] static void fail() { throw std::runtime_error("Invalid JSON"); }
    unsigned hex4() {
        unsigned n = 0;
        for (int i = 0; i < 4; ++i) {
            const char c = *p;
            if (!c) fail();
            ++p;
            n <<= 4;
            if (c >= '0' && c <= '9') n += c - '0';
            else if (c >= 'a' && c <= 'f') n += c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') n += c - 'A' + 10;
            else fail();
        }
        return n;
    }
    std::string string() {
        expect('"');
        std::string s;
        while (*p && *p != '"') {
            unsigned char c = static_cast<unsigned char>(*p++);
            if (c < 32) fail();
            if (c != '\\') { s += static_cast<char>(c); continue; }
            const char escape = *p;
            if (!escape) fail();
            ++p;
            switch (escape) {
                case '"': s += '"'; break;
                case '\\': s += '\\'; break;
                case '/': s += '/'; break;
                case 'b': s += '\b'; break;
                case 'f': s += '\f'; break;
                case 'n': s += '\n'; break;
                case 'r': s += '\r'; break;
                case 't': s += '\t'; break;
                case 'u': {
                    unsigned n = hex4();
                    if (n >= 0xd800 && n <= 0xdbff) {
                        if (*p++ != '\\') fail();
                        if (*p++ != 'u') fail();
                        unsigned low = hex4();
                        if (low < 0xdc00 || low > 0xdfff) fail();
                        n = 0x10000 + ((n - 0xd800) << 10) + low - 0xdc00;
                    } else if (n >= 0xdc00 && n <= 0xdfff) fail();
                    // Embedded NUL cannot be represented by the backend C API.
                    if (!n) throw std::runtime_error("JSON strings cannot contain NUL");
                    if (n < 0x80) s += static_cast<char>(n);
                    else {
                        if (n >= 0x10000) s += static_cast<char>(0xf0 | (n >> 18));
                        if (n >= 0x800) s += static_cast<char>((n >= 0x10000 ? 0x80 : 0xe0) | ((n >> 12) & 0x3f));
                        s += static_cast<char>((n >= 0x800 ? 0x80 : 0xc0) | ((n >> 6) & 0x3f));
                        s += static_cast<char>(0x80 | (n & 0x3f));
                    }
                    break;
                }
                default: fail();
            }
        }
        expect('"');
        return s;
    }
    Value value(int depth) {
        if (depth > 32) fail();
        ws();
        if (*p == '"') return {'s', string()};
        if (*p == '{' || *p == '[') {
            const bool object = *p++ == '{';
            const char end = object ? '}' : ']';
            ws();
            if (*p != end) {
                for (;;) {
                    if (object) { string(); expect(':'); }
                    value(depth + 1); ws();
                    if (*p != ',') break;
                    ++p;
                }
            }
            expect(end); return {'x', {}};
        }
        for (const char* literal : {"true", "false", "null"}) {
            const char* q = p;
            const char* l = literal;
            while (*l && *q == *l) { ++q; ++l; }
            if (!*l) { p = q; return {literal[0] == 'n' ? 'x' : 'b', literal}; }
        }
        const char* start = p;
        if (*p == '-') ++p;
        if (*p == '0') ++p;
        else { if (!digit(*p)) fail(); while (digit(*p)) ++p; }
        if (*p == '.') { ++p; if (!digit(*p)) fail(); while (digit(*p)) ++p; }
        if (*p == 'e' || *p == 'E') {
            ++p; if (*p == '+' || *p == '-') ++p;
            if (!digit(*p)) fail(); while (digit(*p)) ++p;
        }
        return {'n', std::string(start, p)};
    }
    const Value* get(const char* key, char kind) const {
        auto it = fields.find(key);
        if (it == fields.end()) return nullptr;
        if (it->second.kind != kind) throw std::runtime_error(std::string("Wrong JSON type for ") + key);
        return &it->second;
    }
public:
    explicit Json(const char* text) : p(text && *text ? text : "{}") {
        expect('{'); ws();
        if (*p != '}') for (;;) {
            std::string key = string(); expect(':');
            fields[key] = value(0); ws();
            if (*p != ',') break;
            ++p;
        }
        expect('}'); ws(); if (*p) fail();
    }
    std::string str(const char* key, const char* fallback) const {
        auto v = get(key, 's'); return v ? v->text : fallback;
    }
    int64_t integer(const char* key, int64_t fallback) const {
        auto v = get(key, 'n'); if (!v) return fallback;
        size_t used = 0;
        const auto n = std::stoll(v->text, &used);
        if (used != v->text.size()) throw std::runtime_error(std::string("Expected integer for ") + key);
        return n;
    }
    int number(const char* key, int fallback) const {
        auto n = integer(key, fallback);
        if (n < INT32_MIN || n > INT32_MAX) throw std::runtime_error(std::string("Integer out of range: ") + key);
        return static_cast<int>(n);
    }
    float real(const char* key, float fallback) const {
        auto v = get(key, 'n'); if (!v) return fallback;
        float n = std::stof(v->text);
        if (!std::isfinite(n)) throw std::runtime_error("Non-finite JSON number");
        return n;
    }
    bool has(const char* key) const { return fields.count(key) > 0; }
    bool boolean(const char* key, bool fallback) const {
        auto v = get(key, 'b'); return v ? v->text == "true" : fallback;
    }
};

sd_type_t weight_type(const std::string& name) {
    if (name == "default" || name == "auto") return SD_TYPE_COUNT;
    for (int i = 0; i < SD_TYPE_COUNT; ++i) {
        const char* n = sd_type_name(static_cast<sd_type_t>(i));
        if (n && name == n) return static_cast<sd_type_t>(i);
    }
    throw std::runtime_error("Unknown wType: " + name);
}

#if OD_SD_MODERN_API
sample_method_t sampler(const std::string& name) {
    auto method = str_to_sample_method(name.c_str());
    if (method == SAMPLE_METHOD_COUNT) throw std::runtime_error("Unknown sampler: " + name);
    return method;
}
scheduler_t scheduler(const std::string& name) {
    if (name == "default" || name == "auto") return SCHEDULER_COUNT;
    auto schedule = str_to_scheduler(name.c_str());
    if (schedule == SCHEDULER_COUNT) throw std::runtime_error("Unknown schedule: " + name);
    return schedule;
}
// Sampler fields shared by images and videos. flowShift keeps the model's
// default unless the request sets it.
// [sigmas] owns the custom schedule ("1.0,0.99,...,0.0", as distilled models
// are trained on) and must outlive the generation call.
void sample_settings(const Json& json, const od_sd_ctx_t* ctx, sd_sample_params_t& s,
                     int steps, float cfg, sample_method_t method,
                     std::vector<float>& sigmas) {
    s.sample_steps = steps;
    s.guidance.txt_cfg = cfg;
    s.sample_method = method;
    s.scheduler = scheduler(ctx->schedule);
    if (json.has("flowShift")) s.flow_shift = json.real("flowShift", 3.0f);
    std::string list = json.str("sigmas", "");
    for (size_t at = 0; at < list.size();) {
        size_t end = list.find(',', at);
        if (end == std::string::npos) end = list.size();
        sigmas.push_back(std::stof(list.substr(at, end - at)));
        at = end + 1;
    }
    if (!sigmas.empty()) {
        s.custom_sigmas = sigmas.data();
        s.custom_sigmas_count = static_cast<int>(sigmas.size());
        s.sample_steps = static_cast<int>(sigmas.size()) - 1;
    }
}
#else
sample_method_t sampler(const std::string& name) {
    const std::map<std::string, sample_method_t> methods = {
        {"euler_a", EULER_A}, {"euler", EULER}, {"heun", HEUN}, {"dpm2", DPM2},
        {"dpm++2s_a", DPMPP2S_A}, {"dpm++2m", DPMPP2M}, {"dpm++2mv2", DPMPP2Mv2},
        {"ipndm", IPNDM}, {"ipndm_v", IPNDM_V}, {"lcm", LCM}};
    auto it = methods.find(name);
    if (it == methods.end()) throw std::runtime_error("Unknown sampler: " + name);
    return it->second;
}
schedule_t scheduler(const std::string& name) {
    const std::map<std::string, schedule_t> schedules = {
        {"default", DEFAULT}, {"auto", DEFAULT}, {"discrete", DISCRETE},
        {"karras", KARRAS}, {"exponential", EXPONENTIAL}, {"ays", AYS}, {"gits", GITS}};
    auto it = schedules.find(name);
    if (it == schedules.end()) throw std::runtime_error("Unknown schedule: " + name);
    return it->second;
}
#endif

size_t pixels(int64_t width, int64_t height) {
    if (width <= 0 || height <= 0 || width > INT32_MAX || height > INT32_MAX ||
        static_cast<uint64_t>(width) > std::numeric_limits<size_t>::max() / 4 / static_cast<uint64_t>(height))
        throw std::runtime_error("Invalid image dimensions");
    return static_cast<size_t>(width) * static_cast<size_t>(height);
}

struct Progress {
    od_sd_ctx_t* ctx;
    od_sd_progress_fn callback;
    void* user;
    static void forward(int step, int total, float, void* data) noexcept {
        auto& p = *static_cast<Progress*>(data);
        try {
            if (!p.ctx->cancelled.load() && p.callback) p.callback(step, total, p.user);
        } catch (...) { p.ctx->cancelled.store(true); }
#if OD_SD_MODERN_API
        if (p.ctx->cancelled.load()) sd_cancel_generation(p.ctx->sd_ctx, SD_CANCEL_ALL);
#endif
    }
    Progress(od_sd_ctx_t* c, od_sd_progress_fn cb, void* u) : ctx(c), callback(cb), user(u) {
        sd_set_progress_callback(forward, this);
    }
    ~Progress() { sd_set_progress_callback(nullptr, nullptr); }
};

uint8_t* rgba(const sd_image_t& image, int32_t* width, int32_t* height) {
    const size_t count = pixels(image.width, image.height);
    if (!image.data || image.channel < 1 || image.channel > 4)
        throw std::runtime_error("Backend returned invalid image data");
    auto out = std::make_unique<uint8_t[]>(count * 4);
    for (size_t i = 0; i < count; ++i) {
        const uint8_t* src = image.data + i * image.channel;
        out[i * 4] = src[0];
        out[i * 4 + 1] = image.channel <= 2 ? src[0] : src[1];
        out[i * 4 + 2] = image.channel <= 2 ? src[0] : src[2];
        out[i * 4 + 3] = image.channel == 4 ? src[3] : image.channel == 2 ? src[1] : 255;
    }
    *width = static_cast<int32_t>(image.width);
    *height = static_cast<int32_t>(image.height);
    return out.release();
}

uint8_t* generate(od_sd_ctx_t* ctx, const char* request, const uint8_t* init,
                  int32_t iw, int32_t ih, bool image_to_image, od_sd_progress_fn cb,
                  void* user, int32_t* width, int32_t* height) {
    if (width) *width = 0;
    if (height) *height = 0;
    if (!ctx) return nullptr;
    try {
        std::lock_guard<std::mutex> lock(backend_mutex);
        ctx->error_msg.clear();
        if (ctx->cancelled.load()) throw std::runtime_error("Generation cancelled");
        if (!ctx->sd_ctx) throw std::runtime_error("No SD model loaded");
        if (!width || !height) throw std::runtime_error("Output dimension pointers are required");
        Json json(request);
        std::string prompt = json.str("prompt", "");
        std::string negative = json.str("negativePrompt", "");
        int w = json.number("width", 512), h = json.number("height", 512);
        pixels(w, h);
        if (w % 8 || h % 8) throw std::runtime_error("Width and height must be multiples of 8");
        int steps = json.number("steps", 20), batch = json.number("batchCount", 1);
        float cfg = json.real("cfgScale", 7.0f);
        float strength = json.real("strength", 0.75f);
        if (steps <= 0 || batch <= 0 || cfg < 0 || strength < 0 || strength > 1)
            throw std::runtime_error("Invalid steps, batchCount, cfgScale or strength");
        int64_t seed = json.integer("seed", -1);
        auto method = sampler(json.str("sampler", "euler_a"));
        std::vector<uint8_t> rgb;
        sd_image_t input{};
        if (image_to_image) {
            if (!init) throw std::runtime_error("An RGBA init_image is required");
            size_t count = pixels(iw, ih);
            rgb.resize(count * 3);
            for (size_t i = 0; i < count; ++i)
                for (size_t c = 0; c < 3; ++c) rgb[i * 3 + c] = init[i * 4 + c];
            input = {static_cast<uint32_t>(iw), static_cast<uint32_t>(ih), 3, rgb.data()};
        }
        Progress progress(ctx, cb, user);
#if OD_SD_MODERN_API
        sd_cancel_generation(ctx->sd_ctx, SD_CANCEL_RESET);
        sd_img_gen_params_t params;
        sd_img_gen_params_init(&params);
        params.prompt = prompt.c_str();
        params.negative_prompt = negative.c_str();
        params.clip_skip = ctx->clip_skip;
        params.width = w; params.height = h;
        std::vector<float> sigmas;
        sample_settings(json, ctx, params.sample_params, steps, cfg, method, sigmas);
        params.seed = seed; params.batch_count = batch;
        params.init_image = input;
        params.strength = strength;
        params.vae_tiling_params.enabled = ctx->vae_tiling;
        sd_image_generation_result_t* raw = nullptr;
        bool ok = generate_image(ctx->sd_ctx, &params, &raw);
        std::unique_ptr<sd_image_generation_result_t, decltype(&free_sd_image_generation_result)>
            result(raw, free_sd_image_generation_result);
        if (ctx->cancelled.load()) throw std::runtime_error("Generation cancelled");
        if (ctx->cancelled.load()) throw std::runtime_error("Upscaling cancelled");
        if (!ok || !result || result->count < 1 || !result->items)
            throw std::runtime_error("Image generation failed");
        // ABI v1 returns the first image; the complete backend batch is freed.
        return rgba(result->items[0].image, width, height);
#else
        sd_image_t* raw = image_to_image
            ? img2img(ctx->sd_ctx, input, prompt.c_str(), negative.c_str(), ctx->clip_skip,
                      cfg, 3.5f, w, h, method, steps, strength, seed, batch, nullptr, 0.9f, 20.0f, false, "")
            : txt2img(ctx->sd_ctx, prompt.c_str(), negative.c_str(), ctx->clip_skip,
                      cfg, 3.5f, w, h, method, steps, seed, batch, nullptr, 0.9f, 20.0f, false, "");
        auto cleanup = [batch](sd_image_t* images) {
            if (images) { for (int i = 0; i < batch; ++i) std::free(images[i].data); std::free(images); }
        };
        std::unique_ptr<sd_image_t, decltype(cleanup)> result(raw, cleanup);
        // The original API has no abort hook; discard output after cancellation.
        if (ctx->cancelled.load()) throw std::runtime_error("Generation cancelled");
        if (!result) throw std::runtime_error("Image generation failed");
        return rgba(*result, width, height);
#endif
    } catch (const std::exception& e) { error(ctx, e.what()); }
      catch (...) { error(ctx, "Image generation failed"); }
    return nullptr;
}

#if OD_SD_MODERN_API
// Returns every frame as packed RGBA, one frame after another.
uint8_t* generate_frames(od_sd_ctx_t* ctx, const char* request, const uint8_t* init,
                         int32_t iw, int32_t ih, od_sd_progress_fn cb, void* user,
                         int32_t* width, int32_t* height, int32_t* frames, int32_t* fps) {
    if (width) *width = 0;
    if (height) *height = 0;
    if (frames) *frames = 0;
    if (fps) *fps = 0;
    if (!ctx) return nullptr;
    try {
        std::lock_guard<std::mutex> lock(backend_mutex);
        ctx->error_msg.clear();
        if (ctx->cancelled.load()) throw std::runtime_error("Generation cancelled");
        if (!ctx->sd_ctx) throw std::runtime_error("No SD model loaded");
        if (!width || !height || !frames || !fps) throw std::runtime_error("Output pointers are required");
        if (!sd_ctx_supports_video_generation(ctx->sd_ctx))
            throw std::runtime_error("This model cannot make videos");
        Json json(request);
        std::string prompt = json.str("prompt", "");
        std::string negative = json.str("negativePrompt", "");
        int w = json.number("width", 832), h = json.number("height", 480);
        pixels(w, h);
        if (w % 16 || h % 16) throw std::runtime_error("Width and height must be multiples of 16");
        int steps = json.number("steps", 20);
        int count = json.number("frames", 33), rate = json.number("fps", 16);
        float cfg = json.real("cfgScale", 6.0f);
        if (steps <= 0 || cfg < 0 || count <= 0 || count > 241 || rate <= 0 || rate > 60)
            throw std::runtime_error("Invalid steps, cfgScale, frames or fps");
        auto method = sampler(json.str("sampler", "euler"));
        std::vector<uint8_t> rgb;
        sd_image_t input{};
        if (init) {
            size_t n = pixels(iw, ih);
            rgb.resize(n * 3);
            for (size_t i = 0; i < n; ++i)
                for (size_t c = 0; c < 3; ++c) rgb[i * 3 + c] = init[i * 4 + c];
            input = {static_cast<uint32_t>(iw), static_cast<uint32_t>(ih), 3, rgb.data()};
        }
        Progress progress(ctx, cb, user);
        sd_cancel_generation(ctx->sd_ctx, SD_CANCEL_RESET);
        sd_vid_gen_params_t params;
        sd_vid_gen_params_init(&params);
        params.prompt = prompt.c_str();
        params.negative_prompt = negative.c_str();
        params.clip_skip = ctx->clip_skip;
        params.init_image = input;
        params.width = w; params.height = h;
        std::vector<float> sigmas;
        sample_settings(json, ctx, params.sample_params, steps, cfg, method, sigmas);
        params.seed = json.integer("seed", -1);
        params.video_frames = count;
        params.fps = rate;
        params.vae_tiling_params.enabled = ctx->vae_tiling;
        sd_video_generation_result_t* raw = nullptr;
        bool ok = generate_video(ctx->sd_ctx, &params, &raw);
        std::unique_ptr<sd_video_generation_result_t, decltype(&free_sd_video_generation_result)>
            result(raw, free_sd_video_generation_result);
        if (ctx->cancelled.load()) throw std::runtime_error("Generation cancelled");
        if (!ok || !result || result->frame_count < 1 || !result->frames)
            throw std::runtime_error("Video generation failed");
        const sd_image_t& first = result->frames[0];
        const size_t frame_pixels = pixels(first.width, first.height);
        const size_t n = static_cast<size_t>(result->frame_count);
        if (frame_pixels > std::numeric_limits<size_t>::max() / 4 / n)
            throw std::runtime_error("Video is too large");
        auto out = std::make_unique<uint8_t[]>(frame_pixels * 4 * n);
        for (size_t f = 0; f < n; ++f) {
            const sd_image_t& frame = result->frames[f];
            if (frame.width != first.width || frame.height != first.height)
                throw std::runtime_error("Frames differ in size");
            int32_t fw = 0, fh = 0;
            std::unique_ptr<uint8_t[]> one(rgba(frame, &fw, &fh));
            std::copy(one.get(), one.get() + frame_pixels * 4, out.get() + f * frame_pixels * 4);
        }
        *width = static_cast<int32_t>(first.width);
        *height = static_cast<int32_t>(first.height);
        *frames = result->frame_count;
        *fps = result->fps > 0 ? result->fps : rate;
        return out.release();
    } catch (const std::exception& e) { error(ctx, e.what()); }
      catch (...) { error(ctx, "Video generation failed"); }
    return nullptr;
}
#endif
#endif
} // namespace

od_sd_ctx_t* od_sd_create(const char* options) {
    (void)options; // Reserved for future context options.
    try { return new od_sd_ctx_t; } catch (...) { return nullptr; }
}

void od_sd_destroy(od_sd_ctx_t* ctx) {
    if (!ctx) return;
#if OD_SD_AVAILABLE
    std::lock_guard<std::mutex> lock(backend_mutex);
    if (ctx->sd_ctx) free_sd_ctx(ctx->sd_ctx);
#if OD_SD_MODERN_API
    ctx->drop_upscaler();
#endif
#endif
    delete ctx;
}

int32_t od_sd_load(od_sd_ctx_t* ctx, const char* model_path, const char* vae_path,
                   const char* clip_l_path, const char* settings) {
    if (!ctx) return 0;
#if OD_SD_AVAILABLE
    try {
        std::lock_guard<std::mutex> lock(backend_mutex);
        watch_log();
        ctx->error_msg.clear();
        if (ctx->cancelled.load()) throw std::runtime_error("Loading cancelled");
        Json json(settings);
        // Diffusion transformers (Qwen-Image, Wan) load the main file as the
        // diffusion model, with the text encoder given separately.
        std::string diffusion = json.str("diffusionModelPath", "");
        std::string llm = json.str("llmPath", ""), llm_vision = json.str("llmVisionPath", "");
        std::string t5 = json.str("t5xxlPath", ""), audio_vae = json.str("audioVaePath", "");
        std::string taesd = json.str("taesdPath", "");
        std::string connectors = json.str("embeddingsConnectorsPath", "");
        bool offload = json.boolean("offloadToCpu", false);
        bool flash = json.boolean("flashAttn", false);
        bool vae_cpu = json.boolean("vaeOnCpu", false);
        bool te_cpu = json.boolean("textEncoderOnCpu", false);
        bool mmap = json.boolean("mmap", false);
        if ((!model_path || !*model_path) && diffusion.empty())
            throw std::runtime_error("model_path or diffusionModelPath is required");
        auto type = weight_type(json.str("wType", "auto"));
        std::string schedule = json.str("schedule", "default");
        auto schedule_enum = scheduler(schedule);
        int clip_skip = json.number("clipSkip", -1);
        bool tiling = json.boolean("vaeTiling", false);
        // Release the previous model before loading another to avoid doubling VRAM.
        if (ctx->sd_ctx) { free_sd_ctx(ctx->sd_ctx); ctx->sd_ctx = nullptr; }
#if OD_SD_MODERN_API
        ctx->drop_upscaler();
        (void)schedule_enum; // Current upstream applies scheduling per generation.
        sd_ctx_params_t params;
        sd_ctx_params_init(&params);
        params.model_path = model_path ? model_path : "";
        params.vae_path = vae_path ? vae_path : "";
        params.clip_l_path = clip_l_path ? clip_l_path : "";
        params.diffusion_model_path = diffusion.c_str();
        params.llm_path = llm.c_str();
        params.llm_vision_path = llm_vision.c_str();
        params.t5xxl_path = t5.c_str();
        params.audio_vae_path = audio_vae.c_str();
        params.taesd_path = taesd.c_str();
        params.embeddings_connectors_path = connectors.c_str();
        params.wtype = type;
        // Map the files instead of copying them: LTX-2.3 is 25 GB of weights,
        // and mapped pages can be dropped and re-read under memory pressure.
        params.enable_mmap = mmap;
        // Weights stay in RAM and stream to the GPU as needed: an 8 GB card
        // cannot hold a 4 GB DiT, a 5 GB text encoder and the VAE at once.
        if (offload) params.params_backend = "*=cpu";
        std::string backends = vae_cpu ? (te_cpu ? "te=cpu,vae=cpu" : "vae=cpu") : (te_cpu ? "te=cpu" : "");
        if (!backends.empty()) params.backend = backends.c_str();
        params.flash_attn = flash;
        params.diffusion_flash_attn = flash;
        struct LoadCancellation {
            LoadCancellation(od_sd_ctx_t* ctx) {
                sd_set_load_cancel_callback([](void* data) {
                    return static_cast<od_sd_ctx_t*>(data)->cancelled.load();
                }, ctx);
            }
            ~LoadCancellation() { sd_set_load_cancel_callback(nullptr, nullptr); }
        } cancellation(ctx);
        ctx->sd_ctx = new_sd_ctx(&params);
#else
        if (!model_path || !*model_path) throw std::runtime_error("model_path is required");
        ctx->sd_ctx = new_sd_ctx(model_path, clip_l_path ? clip_l_path : "", "", "",
            vae_path ? vae_path : "", "", "", "", "", "", false, tiling, false,
            get_num_physical_cores(), type, STD_DEFAULT_RNG, schedule_enum, false, false, false);
#endif
        if (ctx->cancelled.load()) {
            if (ctx->sd_ctx) { free_sd_ctx(ctx->sd_ctx); ctx->sd_ctx = nullptr; }
            throw std::runtime_error("Loading cancelled");
        }
        if (!ctx->sd_ctx) throw std::runtime_error(with_cause("Failed to load SD model"));
        ctx->clip_skip = clip_skip; ctx->vae_tiling = tiling; ctx->schedule = schedule;
        return 1;
    } catch (const std::exception& e) { error(ctx, e.what()); }
      catch (...) { error(ctx, "Failed to load SD model"); }
#else
    (void)model_path; (void)vae_path; (void)clip_l_path; (void)settings;
    error(ctx, unavailable);
#endif
    return 0;
}

const char* od_sd_error(od_sd_ctx_t* ctx) {
    return ctx ? ctx->error_msg.c_str() : "Invalid SD context";
}

uint8_t* od_sd_txt2img(od_sd_ctx_t* ctx, const char* request, od_sd_progress_fn cb,
                      void* user, int32_t* width, int32_t* height) {
#if OD_SD_AVAILABLE
    return generate(ctx, request, nullptr, 0, 0, false, cb, user, width, height);
#else
    (void)request; (void)cb; (void)user;
    if (width) *width = 0;
    if (height) *height = 0;
    error(ctx, unavailable); return nullptr;
#endif
}

uint8_t* od_sd_img2img(od_sd_ctx_t* ctx, const char* request, const uint8_t* init_image,
                      int32_t init_width, int32_t init_height, od_sd_progress_fn cb,
                      void* user, int32_t* width, int32_t* height) {
#if OD_SD_AVAILABLE
    return generate(ctx, request, init_image, init_width, init_height, true, cb, user, width, height);
#else
    (void)request; (void)init_image; (void)init_width; (void)init_height; (void)cb; (void)user;
    if (width) *width = 0;
    if (height) *height = 0;
    error(ctx, unavailable); return nullptr;
#endif
}

uint8_t* od_sd_txt2vid(od_sd_ctx_t* ctx, const char* request, const uint8_t* init_image,
                      int32_t init_width, int32_t init_height, od_sd_progress_fn cb,
                      void* user, int32_t* width, int32_t* height, int32_t* frames,
                      int32_t* fps) {
#if OD_SD_AVAILABLE && OD_SD_MODERN_API
    return generate_frames(ctx, request, init_image, init_width, init_height, cb, user,
                           width, height, frames, fps);
#else
    (void)request; (void)init_image; (void)init_width; (void)init_height; (void)cb; (void)user;
    if (width) *width = 0;
    if (height) *height = 0;
    if (frames) *frames = 0;
    if (fps) *fps = 0;
    error(ctx, unavailable); return nullptr;
#endif
}

int32_t od_sd_save_video(const char* path, const uint8_t* rgba, int32_t width,
                         int32_t height, int32_t frames, int32_t fps) {
#if OD_SD_HAS_MEDIA_IO
    try {
        if (!path || !*path || !rgba || frames <= 0 || fps <= 0) return 0;
        const size_t n = pixels(width, height);
        std::vector<std::vector<uint8_t>> rgb(frames, std::vector<uint8_t>(n * 3));
        std::vector<sd_image_t> images(frames);
        for (int32_t f = 0; f < frames; ++f) {
            const uint8_t* src = rgba + static_cast<size_t>(f) * n * 4;
            for (size_t i = 0; i < n; ++i)
                for (size_t c = 0; c < 3; ++c) rgb[f][i * 3 + c] = src[i * 4 + c];
            images[f] = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 3, rgb[f].data()};
        }
        return create_mjpg_avi_from_sd_images(path, images.data(), frames, fps) == 0 ? 1 : 0;
    } catch (...) { return 0; }
#else
    (void)path; (void)rgba; (void)width; (void)height; (void)frames; (void)fps;
    return 0;
#endif
}

uint8_t* od_sd_upscale(od_sd_ctx_t* ctx, const char* model_path, const uint8_t* image,
                       int32_t width, int32_t height, int32_t factor,
                       int32_t* out_width, int32_t* out_height) {
    if (out_width) *out_width = 0;
    if (out_height) *out_height = 0;
    if (!ctx) return nullptr;
#if OD_SD_AVAILABLE && OD_SD_MODERN_API
    try {
        std::lock_guard<std::mutex> lock(backend_mutex);
        watch_log();
        ctx->error_msg.clear();
        if (ctx->cancelled.load()) throw std::runtime_error("Upscaling cancelled");
        if (!model_path || !*model_path || !image || factor < 1 || !out_width || !out_height)
            throw std::runtime_error("Invalid upscale request");
        const size_t n = pixels(width, height);
        std::vector<uint8_t> rgb(n * 3);
        for (size_t i = 0; i < n; ++i)
            for (size_t c = 0; c < 3; ++c) rgb[i * 3 + c] = image[i * 4 + c];
        // Tiles keep a 4K output inside 8 GB of VRAM.
        if (!ctx->upscaler || ctx->upscaler_path != model_path) {
            ctx->drop_upscaler();
            ctx->upscaler = new_upscaler_ctx(model_path, false, sd_get_num_physical_cores(), 256, nullptr, nullptr);
            if (!ctx->upscaler) throw std::runtime_error(with_cause("Failed to load the upscaler"));
            ctx->upscaler_path = model_path;
        }
        upscaler_ctx_t* up = ctx->upscaler;
        sd_image_t input = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 3, rgb.data()};
        sd_image_generation_result_t* raw = nullptr;
        bool ok = upscale(up, input, static_cast<uint32_t>(factor), &raw);
        std::unique_ptr<sd_image_generation_result_t, decltype(&free_sd_image_generation_result)>
            result(raw, free_sd_image_generation_result);
        if (ctx->cancelled.load()) throw std::runtime_error("Upscaling cancelled");
        if (!ok || !result || result->count < 1 || !result->items)
            throw std::runtime_error("Upscaling failed");
        std::unique_ptr<uint8_t[]> big(rgba(result->items[0].image, out_width, out_height));
        // The model enlarges by its own scale (RealESRGAN_x4plus: ×4) and
        // ignores the factor; average whole blocks down to the factor asked.
        const int32_t k = *out_width / (width * factor);
        if (k <= 1 || *out_width != width * factor * k || *out_height != height * factor * k)
            return big.release();
        const int32_t w = width * factor, h = height * factor, src_w = *out_width;
        auto out = std::make_unique<uint8_t[]>(pixels(w, h) * 4);
        for (int32_t y = 0; y < h; ++y)
            for (int32_t x = 0; x < w; ++x)
                for (int c = 0; c < 4; ++c) {
                    uint32_t sum = 0;
                    for (int32_t dy = 0; dy < k; ++dy)
                        for (int32_t dx = 0; dx < k; ++dx)
                            sum += big[((static_cast<size_t>(y) * k + dy) * src_w + x * k + dx) * 4 + c];
                    out[(static_cast<size_t>(y) * w + x) * 4 + c] = static_cast<uint8_t>((sum + k * k / 2) / (k * k));
                }
        *out_width = w;
        *out_height = h;
        return out.release();
    } catch (const std::exception& e) { error(ctx, e.what()); }
      catch (...) { error(ctx, "Upscaling failed"); }
#else
    (void)model_path; (void)image; (void)width; (void)height; (void)factor;
    error(ctx, "Upscaling needs a current stable-diffusion.cpp build");
#endif
    return nullptr;
}

void od_sd_free_image(uint8_t* image) { delete[] image; }
void od_sd_cancel(od_sd_ctx_t* ctx) { if (ctx) ctx->cancelled.store(true); }
void od_sd_reset_cancel(od_sd_ctx_t* ctx) { if (ctx) ctx->cancelled.store(false); }
int32_t od_sd_version(void) { return 4; }
