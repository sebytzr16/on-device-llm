// Android bridge embedding probe (ABI 7): loads an embedding GGUF (and an
// optional projector), embeds the items of a request file and prints the
// cosine similarity of every query against every item, plus timings.
// Usage: native_embed_probe /abs/library.so /abs/model.gguf /abs/request.json [/abs/mmproj.gguf] [threads]
// request.json: {"queries": ["task: search result | query: ..."],
//                "items": ["title: none | text: ...", {"media": ["/abs/cat.jpg"]}],
//                "dims": 0}
// No app settings or data are touched. Output is JSON lines.
#include <dlfcn.h>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include "json.hpp"

using json = nlohmann::ordered_json;
using Clock = std::chrono::steady_clock;

template<class T> T symbol(void * lib, const char * name) {
    auto address = dlsym(lib, name);
    if (!address) throw std::runtime_error(std::string("Missing symbol: ") + name);
    return reinterpret_cast<T>(address);
}

int main(int argc, char ** argv) {
    if (argc < 4) return 2;
    try {
        void * lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!lib) throw std::runtime_error(dlerror());
        const auto create = symbol<void * (*)(const char *)>(lib, "od_create");
        const auto destroy = symbol<void (*)(void *)>(lib, "od_destroy");
        const auto load = symbol<int32_t (*)(void *, const char *, const char *)>(lib, "od_load");
        const auto embed = symbol<const char * (*)(void *, const char *)>(lib, "od_embed");
        const auto info = symbol<const char * (*)(void *)>(lib, "od_info");
        const auto error = symbol<const char * (*)(void *)>(lib, "od_error");
        std::ifstream in(argv[3]);
        std::stringstream buf; buf << in.rdbuf();
        const json req = json::parse(buf.str());
        const std::string mmproj = argc > 4 ? argv[4] : "";
        const int threads = argc > 5 ? std::atoi(argv[5]) : 6;
        void * handle = create("{}");
        if (!handle) throw std::runtime_error("Could not create bridge");
        json settings = {{"embedding", true}, {"contextSize", req.value("context", 2048)}, {"effectiveThreads", threads},
            {"effectiveBatchThreads", threads}, {"backend", "cpu"}};
        if (!mmproj.empty()) settings["mmproj"] = mmproj;
        // Extra load settings from the request, e.g. {"imageMaxTokens": 280}.
        for (const auto & [k, v] : req.value("load", json::object()).items()) settings[k] = v;
        auto t0 = Clock::now();
        if (load(handle, argv[2], settings.dump().c_str()) != 0) throw std::runtime_error(std::string("load: ") + error(handle));
        const double load_ms = std::chrono::duration<double, std::milli>(Clock::now() - t0).count();
        const json loaded = json::parse(info(handle));
        std::cout << json{{"load_ms", load_ms}, {"dim", loaded.value("embeddingDim", 0)},
            {"vision", loaded.value("supportsVision", false)}, {"audio", loaded.value("supportsAudio", false)},
            {"visionError", loaded.value("visionError", "")}, {"rssMb", loaded.value("peakRssMb", 0)}}.dump() << "\n";
        auto run = [&](const json & texts) {
            json vectors = json::array();
            for (const auto & t : texts) {
                auto s = Clock::now();
                const char * out = embed(handle, json{{"texts", json::array({t})}, {"dims", req.value("dims", 0)}}.dump().c_str());
                if (!out) throw std::runtime_error(std::string("embed: ") + error(handle));
                const double ms = std::chrono::duration<double, std::milli>(Clock::now() - s).count();
                const json res = json::parse(out);
                vectors.push_back(res["vectors"][0]);
                std::cout << json{{"item", t}, {"ms", ms}, {"dim", res["dim"]}}.dump() << "\n";
            }
            return vectors;
        };
        const json q = run(req.at("queries"));
        const json d = run(req.at("items"));
        for (size_t i = 0; i < q.size(); ++i) {
            json row = json::array();
            for (size_t j = 0; j < d.size(); ++j) {
                double dot = 0;
                for (size_t k = 0; k < q[i].size(); ++k) dot += q[i][k].get<double>() * d[j][k].get<double>();
                row.push_back(std::round(dot * 1000) / 1000);
            }
            std::cout << json{{"query", req["queries"][i]}, {"cosine", row}}.dump() << "\n";
        }
        std::cout << json{{"peakRssMb", json::parse(info(handle)).value("peakRssMb", 0)}}.dump() << "\n";
        destroy(handle);
        return 0;
    } catch (const std::exception & e) {
        std::cout << json{{"error", e.what()}}.dump() << "\n";
        return 1;
    }
}
