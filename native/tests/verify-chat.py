"""Read-only model smoke tests or a deterministic bridge throughput probe.

Example: python native/tests/verify-chat.py --dll native/out/windows-x64/ondevice_llm_cuda.dll
    --model C:/path/model.gguf --output build/bridge-chat-check/results.json
Add --benchmark for one warmup and three 1500-token turns. Use the same settings
and a quiet GPU for both DLLs. Model files and application settings are never written.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import statistics
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dll", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dll-dir", type=Path, default=Path("native/out/windows-x64"))
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--load-json", default="{}")
    args = parser.parse_args()
    dll_dirs = [os.add_dll_directory(str(p.resolve())) for p in {args.dll.parent, args.dll_dir}]
    lib = ctypes.CDLL(str(args.dll.resolve()))
    for name, result, arguments in [
        ("od_create", ctypes.c_void_p, [ctypes.c_char_p]),
        ("od_load", ctypes.c_int32, [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]),
        ("od_begin", ctypes.c_int32, [ctypes.c_void_p, ctypes.c_char_p]),
        ("od_step", ctypes.c_int32, [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_int32)]),
        ("od_error", ctypes.c_char_p, [ctypes.c_void_p]),
        ("od_info", ctypes.c_char_p, [ctypes.c_void_p]),
        ("od_destroy", None, [ctypes.c_void_p]),
    ]:
        function = getattr(lib, name)
        function.restype, function.argtypes = result, arguments
    handle = lib.od_create(b"{}")
    settings = dict(backend="cuda", contextSize=4096, nGpuLayers=999,
                    flashAttention=True, kvCacheType="f16")
    settings.update(json.loads(args.load_json))
    report = dict(dll=str(args.dll), model=str(args.model), loadSettings=settings,
                  dllSha256=hashlib.sha256(args.dll.read_bytes()).hexdigest(), results=[])

    def generate(label, prompt, thinking=False, extra=None, tools=None, capacity=8192):
        request = dict(messages=[dict(role="user", content=prompt)], fallbackTemplate="",
                       settings=dict(maxTokens=512, temperature=0.0, seed=1,
                                     thinkingModeEnabled=thinking, responseFormat="text"))
        request["settings"].update(extra or {})
        if tools:
            request.update(tools=tools, toolChoice="required")
        started = time.perf_counter()
        if lib.od_begin(handle, json.dumps(request).encode()) < 0:
            raise RuntimeError(lib.od_error(handle).decode())
        buffer, count, chunks = ctypes.create_string_buffer(capacity), ctypes.c_int32(), []
        first_visible = None
        while True:
            status = lib.od_step(handle, buffer, capacity, ctypes.byref(count))
            if status < 0:
                raise RuntimeError(lib.od_error(handle).decode())
            if count.value:
                chunks.append(buffer.raw[:count.value])
                if first_visible is None:
                    first_visible = time.perf_counter() - started
            if status == 2:
                break
        info = json.loads(lib.od_info(handle))
        text = b"".join(chunks).decode("utf-8", "strict")
        result = dict(case=label, wallSeconds=time.perf_counter() - started,
                      firstVisibleSeconds=first_visible, text=text,
                      textSha256=hashlib.sha256(text.encode()).hexdigest(),
                      info={key: info.get(key) for key in (
                          "parseError", "templateError", "templateProbeError", "toolFormat",
                          "toolCalls", "toolContent", "finishReason", "tokens", "thinkingTokens",
                          "tokensPerSecond", "beginMs", "prefillMs", "firstTokenMs", "backendSampling")})
        report["results"].append(result)
        print(json.dumps({key: value for key, value in result.items() if key not in ("text", "info")}, ensure_ascii=True), flush=True)
        assert not info["parseError"], result
        return result

    try:
        started = time.perf_counter()
        if lib.od_load(handle, str(args.model.resolve()).encode(), json.dumps(settings).encode()) < 0:
            raise RuntimeError(lib.od_error(handle).decode())
        info = json.loads(lib.od_info(handle))
        report.update(loadSeconds=time.perf_counter() - started, backend=info["backend"],
                      effectiveSettings=info["effectiveSettings"])
        print("LOADED", report["backend"], flush=True)
        assert "CUDA" in info["backend"], info["backend"]
        if args.benchmark:
            story = ("Write a detailed story of at least 3000 words about a traveller exploring an ancient city. "
                     "Include dialogue, architecture, food and discoveries. Continue the story without a conclusion.")
            generate("warmup", story, extra=dict(maxTokens=128, seed=1234, promptCache=False))
            for index in range(args.rounds):
                result = generate(f"benchmark_{index + 1}", story,
                                  extra=dict(maxTokens=1500, seed=1234, promptCache=False))
                assert result["info"]["tokens"] == 1500, result["info"]
            measured = report["results"][1:]
            report["medianTokensPerSecond"] = statistics.median(r["info"]["tokensPerSecond"] for r in measured)
            print("MEDIAN_TOK_S", report["medianTokensPerSecond"], flush=True)
        else:
            prompt = "What is 2 + 2? Answer briefly."
            generate("thinking_on", prompt, True)
            generate("thinking_off", prompt)
            assert generate("plain", "Reply with only the word Hello.", capacity=7)["text"].strip() == "Hello"
            tools = [dict(name="get_weather", description="Get current weather for a city",
                          parameters=dict(type="object", properties=dict(city=dict(type="string")), required=["city"]))]
            result = generate("tool", "Call get_weather for Toronto now. Use the tool; do not answer from memory.", tools=tools)
            calls = result["info"]["toolCalls"]
            assert not result["text"].strip() and len(calls) == 1, result
            assert calls[0]["name"] == "get_weather" and json.loads(calls[0]["arguments"]) == {"city": "Toronto"}, result
            schema = dict(type="object", properties=dict(answer=dict(type="integer", const=4)),
                          required=["answer"], additionalProperties=False)
            result = generate("json_schema", "Return an object whose answer is the number 4.",
                              extra=dict(responseFormat="json_schema", jsonSchema=json.dumps(schema)))
            assert json.loads(result["text"]) == {"answer": 4}, result
            result = generate("json", "Return a JSON object with answer equal to 4.", extra=dict(responseFormat="json"))
            assert isinstance(json.loads(result["text"]), dict), result
        report["passed"] = True
    finally:
        lib.od_destroy(handle)
        args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
        for directory in dll_dirs:
            directory.close()


if __name__ == "__main__":
    main()
