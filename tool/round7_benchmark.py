"""Read-only round 7 benchmark against an existing bridge and downloaded GGUFs."""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dll', type=Path, required=True)
p.add_argument('--model', type=Path, required=True)
p.add_argument('--embedding', action='store_true')
p.add_argument('--draft', type=Path)
p.add_argument('--context', type=int, default=4096)
p.add_argument('--kv', default='fp16')
p.add_argument('--draft-max', type=int, default=2)
p.add_argument('--mtp-off', action='store_true')
p.add_argument('--prompt-repeat', type=int, default=0)
a = p.parse_args()
dll_dir = os.add_dll_directory(str(a.dll.resolve().parent))
lib = c.CDLL(str(a.dll.resolve()))
lib.od_create.argtypes = [c.c_char_p]
lib.od_create.restype = c.c_void_p
lib.od_destroy.argtypes = [c.c_void_p]
for name in ['od_info', 'od_error']:
    getattr(lib, name).argtypes = [c.c_void_p]
    getattr(lib, name).restype = c.c_char_p
lib.od_load.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p]
lib.od_embed.argtypes = [c.c_void_p, c.c_char_p]
lib.od_embed.restype = c.c_char_p
lib.od_estimate.argtypes = [c.c_void_p, c.c_char_p, c.c_char_p]
lib.od_estimate.restype = c.c_char_p
lib.od_begin.argtypes = [c.c_void_p, c.c_char_p]
lib.od_step.argtypes = [c.c_void_p, c.c_void_p, c.c_int32, c.POINTER(c.c_int32)]
h = lib.od_create(b'{}')
def encode(value):
    return json.dumps(value).encode()
def error():
    return RuntimeError(lib.od_error(h).decode())
settings = {'backend': 'cpu' if a.embedding else 'cuda',
    'nGpuLayers': 0 if a.embedding else 999, 'embedding': a.embedding,
    'contextSize': a.context, 'effectiveThreads': 8, 'effectiveBatchThreads': 8,
    'effectiveBatchSize': 512, 'effectiveMicroBatchSize': 512,
    'mtp': bool(a.draft) and not a.mtp_off, 'draftMaxTokens': a.draft_max,
    'kvCacheType': a.kv}
if a.draft:
    settings['draftModel'] = str(a.draft.resolve())
try:
    estimate = lib.od_estimate(h, str(a.model.resolve()).encode(), encode(settings))
    print(json.dumps({'estimate': json.loads(estimate) if estimate else str(error())}), flush=True)
    start = time.perf_counter()
    if lib.od_load(h, str(a.model.resolve()).encode(), encode(settings)):
        raise error()
    print(json.dumps({'load_seconds': time.perf_counter()-start}), flush=True)
    if a.embedding:
        texts = ['title: none | text: ' +
            f'Section {i}. The warranty covers repairs for two years. Keep the receipt. ' * 12
            for i in range(24)]
        def embed(batch):
            result = lib.od_embed(h, encode({'texts': batch, 'dims': 256}))
            if not result:
                raise error()
            return json.loads(result)['vectors']
        embed(texts[:1])
        for size in [1, 8, 1, 8]:
            start = time.perf_counter()
            vectors = []
            for i in range(0, len(texts), size):
                vectors.extend(embed(texts[i:i+size]))
            print(json.dumps({'batch': size, 'documents': len(texts),
                'seconds': time.perf_counter()-start, 'dimensions': len(vectors[0])}), flush=True)
    else:
        req = {'messages': [{'role': 'user', 'content':
            ('The lake feeds a river and the river flows into the sea. ' * a.prompt_repeat) +
            'Describe the water cycle in detail in about 300 words.'}],
            'settings': {'temperature': 0, 'seed': 42, 'maxTokens': 128,
                'thinkingModeEnabled': False, 'promptCache': False}}
        for trial in range(2):
            if lib.od_begin(h, encode(req)):
                raise error()
            buf = c.create_string_buffer(65536)
            n = c.c_int32()
            start = time.perf_counter()
            while True:
                status = lib.od_step(h, buf, len(buf), c.byref(n))
                if status < 0:
                    raise error()
                if status == 2:
                    break
            info = json.loads(lib.od_info(h))
            info.pop('embeddedChatTemplate', None)
            print(json.dumps({'trial': trial, 'wall_seconds': time.perf_counter()-start,
                'info': info}), flush=True)
finally:
    lib.od_destroy(h)
