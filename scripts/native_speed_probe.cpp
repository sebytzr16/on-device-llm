// Bridge A/B probe: identical model, prompt, sampler and threads.
// Usage: native_speed_probe /absolute/library /absolute/model.gguf [threads] [rounds] [context_words] [load_settings.json]
// No app settings or data are modified. Output is one JSON line per round.
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include "json.hpp"

using json = nlohmann::ordered_json;
using Clock = std::chrono::steady_clock;

template<class T> T symbol(void * lib, const char * name) {
#if defined(_WIN32)
    auto address = GetProcAddress(static_cast<HMODULE>(lib), name);
#else
    auto address = dlsym(lib, name);
#endif
    if (!address) throw std::runtime_error(std::string("Missing symbol: ") + name);
    return reinterpret_cast<T>(address);
}

int main(int argc, char ** argv) {
    if (argc < 3) return 2;
    try {
#if defined(_WIN32)
        void * lib = LoadLibraryExA(argv[1], nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!lib) throw std::runtime_error("LoadLibraryEx failed: " + std::to_string(GetLastError()));
#else
        void * lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!lib) throw std::runtime_error(dlerror());
#endif
        const auto create = symbol<void * (*)(const char *)>(lib, "od_create");
        const auto destroy = symbol<void (*)(void *)>(lib, "od_destroy");
        const auto load = symbol<int32_t (*)(void *, const char *, const char *)>(lib, "od_load");
        const auto begin = symbol<int32_t (*)(void *, const char *)>(lib, "od_begin");
        const auto step = symbol<int32_t (*)(void *, uint8_t *, int32_t, int32_t *)>(lib, "od_step");
        const auto info = symbol<const char * (*)(void *)>(lib, "od_info");
        const auto error = symbol<const char * (*)(void *)>(lib, "od_error");
        const int threads = argc > 3 ? std::atoi(argv[3]) : 6;
        const int rounds = argc > 4 ? std::atoi(argv[4]) : 3;
        const int context_words = argc > 5 ? std::max(0, std::atoi(argv[5])) : 0;
        std::string context;
        for (int i = 0; i < context_words; ++i) context += "traveller city history ";
        void * handle = create("{}");
        if (!handle) throw std::runtime_error("Could not create bridge");
        json settings = {
            {"backend", "cpu"}, {"contextSize", 4096},
            {"effectiveThreads", threads}, {"effectiveBatchThreads", threads},
            {"effectiveBatchSize", 256}, {"effectiveMicroBatchSize", 256},
            {"flashAttention", true}, {"kvCacheType", "f16"}
        };
        if (argc > 6) {
            std::ifstream input(argv[6]);
            settings.update(json::parse(input));
        }
        if (load(handle, argv[2], settings.dump().c_str()) < 0)
            throw std::runtime_error(error(handle));
        for (int round = 0; round < rounds; ++round) {
            const json request = {
                {"messages", json::array({{{"role", "user"}, {"content",
                    context + "\nWrite a detailed story of at least 1000 words about a traveller exploring an ancient city. Continue the story without a conclusion."}}})},
                {"settings", {{"maxTokens", 256}, {"temperature", 0.0}, {"seed", 1234},
                    {"thinkingModeEnabled", false}, {"responseFormat", "text"}}},
                {"fallbackTemplate", ""}
            };
            const auto started = Clock::now();
            if (begin(handle, request.dump().c_str()) < 0)
                throw std::runtime_error(error(handle));
            uint8_t bytes[8192];
            int32_t length;
            for (;;) {
                const int rc = step(handle, bytes, sizeof(bytes), &length);
                if (rc < 0) throw std::runtime_error(error(handle));
                if (rc == 2) break;
            }
            auto metrics = json::parse(info(handle));
            metrics["libraryPath"] = argv[1];
            metrics["modelPath"] = argv[2];
            metrics["round"] = round;
            metrics["contextWords"] = context_words * 3;
            metrics["wallMs"] = std::chrono::duration<double, std::milli>(Clock::now() - started).count();
            std::cout << metrics.dump() << std::endl;
        }
        destroy(handle);
#if defined(_WIN32)
        FreeLibrary(static_cast<HMODULE>(lib));
#else
        dlclose(lib);
#endif
        return 0;
    } catch (const std::exception & e) {
        std::cerr << e.what() << std::endl;
        return 1;
    }
}
