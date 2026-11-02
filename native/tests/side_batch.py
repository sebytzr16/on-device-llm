"""Offline bridge integration test; reads an existing GGUF without modifying it.

Run: python native/tests/side_batch.py DLL MODEL [--tokens 128] [--host-kv]
"""
import argparse
import concurrent.futures
import ctypes as c
import json
import os
from pathlib import Path
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('library', type=Path)
    parser.add_argument('model', type=Path)
    parser.add_argument('--tokens', type=int, default=128)
    parser.add_argument('--host-kv', action='store_true')
    parser.add_argument('--threads', type=int, default=4)
    parser.add_argument('--main-threads', type=int, default=8)
    parser.add_argument('--slots', type=int, default=3)
    parser.add_argument('--main-context', type=int, default=4096)
    parser.add_argument('--context', type=int, default=4096)
    parser.add_argument('--kv-type', default='q8_0')
    parser.add_argument('--ubatch', type=int, default=512)
    parser.add_argument('--prompt-repeat', type=int, default=0)
    parser.add_argument('--idle-main', action='store_true')
    parser.add_argument('--adaptive', action='store_true')
    parser.add_argument('--gpu-layers', type=int, default=999)
    parser.add_argument('--prefill-chunk', type=int, default=512)
    parser.add_argument('--jobs', type=int, choices=(1, 2, 3), default=3)
    parser.add_argument('--benchmark-only', action='store_true')
    args = parser.parse_args()
    if os.name == 'nt':
        dll_dir = os.add_dll_directory(str(args.library.resolve().parent))
    api = c.CDLL(str(args.library.resolve()))
    signatures = {
        'od_create': ([c.c_char_p], c.c_void_p),
        'od_load': ([c.c_void_p, c.c_char_p, c.c_char_p], c.c_int),
        'od_error': ([c.c_void_p], c.c_char_p),
        'od_info': ([c.c_void_p], c.c_char_p),
        'od_begin': ([c.c_void_p, c.c_char_p], c.c_int),
        'od_step': ([c.c_void_p, c.c_void_p, c.c_int, c.POINTER(c.c_int)], c.c_int),
        'od_side_open': ([c.c_void_p, c.c_char_p], c.c_void_p),
        'od_side_submit': ([c.c_void_p, c.c_int, c.c_char_p], c.c_int),
        'od_side_step': ([c.c_void_p], c.c_char_p),
        'od_side_cancel': ([c.c_void_p, c.c_int], None),
        'od_side_close': ([c.c_void_p], None),
        'od_destroy': ([c.c_void_p], None),
        'od_release_owner': ([c.c_int64], c.c_int),
    }
    for name, (inputs, output) in signatures.items():
        function = getattr(api, name)
        function.argtypes, function.restype = inputs, output

    def encode(value):
        return json.dumps(value).encode()

    def request(task, tokens):
        return encode({'messages': [{'role': 'user', 'content': task}],
                       'settings': {'maxTokens': tokens, 'temperature': 0.3,
                                    'thinkingModeEnabled': False}})

    runtime = api.od_create(encode({'owner': 20261102}))
    side = None
    try:
        started = time.perf_counter()
        settings = {'backend': 'cuda' if args.gpu_layers else 'cpu', 'nGpuLayers': args.gpu_layers, 'contextSize': args.main_context,
                    'kvCacheType': 'q8_0', 'vCacheType': 'q8_0',
                    'effectiveThreads': args.main_threads, 'effectiveBatchThreads': args.main_threads,
                    'mtp': False, 'vramReserveMb': 256}
        assert api.od_load(runtime, str(args.model).encode(), encode(settings)) == 0, api.od_error(runtime)
        info = json.loads(api.od_info(runtime))
        print(json.dumps({'loadSeconds': time.perf_counter() - started,
                          'backend': info.get('backend'),
                          'effectiveSettings': info.get('effectiveSettings') }), flush=True)
        primary = request('Write a numbered list of ten practical tips for writing clear documents.', 32)
        assert api.od_begin(runtime, primary) == 0, api.od_error(runtime)
        side = api.od_side_open(runtime, encode({'n_seq': args.slots, 'n_ctx_per_seq': args.context,
                                                'adaptive': args.adaptive, 'threads': args.threads,
                                                'kvCacheType': args.kv_type, 'ubatch': args.ubatch,
                                                'prefill_chunk': args.prefill_chunk,
                                                'offload_kv': not args.host_kv}))
        assert side, api.od_error(runtime)
        assert api.od_side_submit(side, 0, request('hello ' * 5000, 512)) < 0
        assert 'error' in json.loads(api.od_side_step(side))
        for seq in range(args.jobs):
            assert api.od_side_submit(side, seq, request(
                f'Write a detailed numbered list of twenty practical tips for document section {seq + 1}.' + ' Be concrete.' * args.prompt_repeat, args.tokens)) == 0

        def drive_main():
            buffer, length = c.create_string_buffer(65536), c.c_int()
            while True:
                rc = api.od_step(runtime, buffer, len(buffer), c.byref(length))
                assert rc >= 0, api.od_error(runtime)
                if rc == 2:
                    return json.loads(api.od_info(runtime))

        started = time.perf_counter()
        text = [bytearray() for _ in range(args.jobs)]
        completed, last = set(), {}
        with concurrent.futures.ThreadPoolExecutor() as pool:
            main_result = None if args.idle_main else pool.submit(drive_main)
            while len(completed) < args.jobs:
                result = json.loads(api.od_side_step(side))
                assert 'error' not in result, result
                for event in result['events']:
                    seq = event['seq']
                    text[seq].extend(event['bytes'])
                    last[seq] = event['metrics']
                    if event['done']:
                        completed.add(seq)
            seconds = time.perf_counter() - started
            primary_info = main_result.result() if main_result else drive_main()
        assert all(value.decode('utf-8').strip() for value in text)
        assert json.loads(api.od_info(runtime))['tokens'] == primary_info['tokens']
        print(json.dumps({'batchSeconds': seconds, 'sequences': last,
                          'aggregateTokensPerSecond': sum(m['tokens'] for m in last.values()) / seconds,
                          'replyBytes': [len(t) for t in text]}), flush=True)
        if args.benchmark_only:
            return
        # A later arrival must share decode steps without resetting the first KV (owner, 2026-11-02).
        late = request('Write twenty document writing tips.', 32)
        assert api.od_side_submit(side, 0, late) == 0
        first = json.loads(api.od_side_step(side))['events'][0]
        assert api.od_side_submit(side, 1, late) == 0
        second = json.loads(api.od_side_step(side))
        assert {e['seq'] for e in second['events']} == {0, 1}, second
        assert second['events'][0]['metrics']['tokens'] > first['metrics']['tokens'], second
        assert api.od_side_submit(side, 2, late) == 0
        third = json.loads(api.od_side_step(side))
        assert {e['seq'] for e in third['events']} == {0, 1, 2}, third
        for seq in range(3):
            api.od_side_cancel(side, seq)
        print('PASS: arrivals one and two steps apart decode together; earlier KV advances', flush=True)
        if args.adaptive:
            assert api.od_side_submit(side, 0, late) == 0
            assert 'error' not in json.loads(api.od_side_step(side))
            growth = request('Explain these notes: ' + 'hello ' * 3000, 8)
            assert api.od_side_submit(side, 1, growth) == 1
            assert 'error' not in json.loads(api.od_side_step(side))
            api.od_side_cancel(side, 0)
            # Growth must happen between rounds, without touching the chat cache (owner, 2026-11-02).
            assert api.od_side_submit(side, 0, request('Explain these notes: ' + 'hello ' * 1100, 8)) == 0
            while True:
                grown = json.loads(api.od_side_step(side))
                assert 'error' not in grown, grown
                event = grown['events'][0]
                assert event['metrics']['sideContext'] >= 1280, event
                assert event['metrics']['sideSequences'] >= 3, event
                if event['done']:
                    break
        # Reuse and cancellation must not corrupt another sequence or the chat cache (owner, 2026-11-02).
        assert api.od_side_submit(side, 0, request('Say hello.', 8)) == 0
        api.od_side_cancel(side, 0)
        assert json.loads(api.od_side_step(side))['events'] == []
        assert api.od_begin(runtime, primary) == 0
        cache = json.loads(api.od_info(runtime))
        assert cache['cachedPromptTokens'] > 0, cache
        drive_main()
        assert api.od_release_owner(20261102) == 1
        assert 'chat model changed' in json.loads(api.od_side_step(side))['error']
        print('PASS: three concurrent sequences, independent main decode/cache, rejection, cancellation, reuse, owner release', flush=True)
    finally:
        if side:
            api.od_side_close(side)
        api.od_destroy(runtime)


if __name__ == '__main__':
    main()
