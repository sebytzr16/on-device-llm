"""Smoke-test a staged bridge DLL in a fresh process (never replaces app DLLs)."""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import re
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dll', type=Path, required=True)
p.add_argument('--backend', choices=['cpu', 'cuda', 'vulkan'], required=True)
p.add_argument('--models', type=Path, nargs='+', required=True)
p.add_argument('--tokens', type=int, default=32)
a = p.parse_args()
dll_dir = os.add_dll_directory(str(a.dll.resolve().parent))
lib = c.CDLL(str(a.dll.resolve()))
lib.od_create.argtypes = [c.c_char_p]
lib.od_create.restype = c.c_void_p
for name in ['od_info', 'od_error']:
    f = getattr(lib, name)
    f.argtypes = [c.c_void_p]
    f.restype = c.c_char_p
lib.od_load.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p]
lib.od_begin.argtypes = [c.c_void_p, c.c_char_p]
lib.od_step.argtypes = [c.c_void_p, c.c_void_p, c.c_int32, c.POINTER(c.c_int32)]
lib.od_destroy.argtypes = [c.c_void_p]
for model in a.models:
    handle = lib.od_create(b'{}')
    if not handle:
        raise SystemExit('od_create failed')
    try:
        settings = {'backend': a.backend, 'nGpuLayers': 0 if a.backend == 'cpu' else 99,
                    'contextSize': 512, 'effectiveThreads': 8, 'effectiveBatchThreads': 8,
                    'effectiveBatchSize': 128, 'effectiveMicroBatchSize': 128, 'mtp': False}
        start = time.perf_counter()
        if lib.od_load(handle, str(model).encode('utf-8'), json.dumps(settings).encode()):
            raise RuntimeError(lib.od_error(handle).decode())
        loaded = time.perf_counter()-start
        req = {'messages': [{'role': 'user', 'content': 'What is 17 + 25? Answer with just the number.'}],
               'settings': {'temperature': 0, 'seed': 42, 'maxTokens': a.tokens, 'thinkingModeEnabled': False}}
        if lib.od_begin(handle, json.dumps(req).encode()):
            raise RuntimeError(lib.od_error(handle).decode())
        output = bytearray()
        buf = c.create_string_buffer(65536)
        n = c.c_int32()
        start = time.perf_counter()
        while True:
            status = lib.od_step(handle, buf, len(buf), c.byref(n))
            if status < 0:
                raise RuntimeError(lib.od_error(handle).decode())
            if n.value:
                output.extend(buf.raw[:n.value])
            if status == 2:
                break
        elapsed = time.perf_counter()-start
        info = json.loads(lib.od_info(handle))
        info.pop('embeddedChatTemplate', None)
        print(json.dumps({'dll': str(a.dll), 'model': str(model), 'load_seconds': loaded,
                          'generation_wall_seconds': elapsed, 'output': output.decode('utf-8'),
                          'info': info}), flush=True)
        if not re.search(r'\b42\b', output.decode('utf-8')):
            raise RuntimeError('Arithmetic smoke test did not return 42')
        if a.backend != 'cpu' and a.backend.upper() not in info['backend'].upper():
            raise RuntimeError('Requested GPU backend was not selected')
    finally:
        lib.od_destroy(handle)
