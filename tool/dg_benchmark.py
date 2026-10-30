"""Resident host placement probe (stdlib only, Windows desktop).

Run: python tool/dg_benchmark.py 26
Waits for a free GPU before loading. The argument is the number of CPU MoE layers.
"""
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
layers = int(sys.argv[1]) if len(sys.argv) > 1 else 30
while True:
    used = int(subprocess.check_output([
        'nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits',
    ], text=True).strip())
    if used < 1024:
        break
    print(f'Waiting for GPU ({used} MiB in use)', flush=True)
    time.sleep(5)

runtime = root / 'native/out/windows-x64/diffusiongemma'
with (root / f'build/dg-placement-{layers}.stderr').open('w', encoding='utf-8') as log:
    proc = subprocess.Popen([
        str(runtime / 'dg_host.exe'), '-m',
        str(root / 'build/dg-models/diffusiongemma-26B-A4B-it-Q4_K_M.gguf'),
        '-ngl', '999', '--n-cpu-moe', str(layers),
        '-c', '4096', '-b', '512', '-ub', '512', '--diffusion-eb-max-steps', '48',
    ], cwd=runtime, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
       stderr=log, text=True, encoding='utf-8')
    try:
        print(proc.stdout.readline().strip(), flush=True)
        messages = []
        for prompt in [
            'What is the capital of France? Answer in one sentence.',
            'Write two short paragraphs explaining why leaves change color in autumn.\n\nKeep it clear and factual.',
        ]:
            messages.append({'role': 'user', 'content': prompt})
            proc.stdin.write(json.dumps({'messages': messages, 'maxTokens': 512, 'temperature': .8}) + '\n')
            proc.stdin.flush()
            peak = 0
            for line in proc.stdout:
                event = json.loads(line)
                peak = max(peak, int(subprocess.check_output([
                    'nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits',
                ], text=True).strip()))
                if event.get('done'):
                    print(json.dumps({'cpuMoeLayers': layers, 'peakMiB': peak, **event}, ensure_ascii=False), flush=True)
                    if event.get('error'):
                        raise RuntimeError(event['error'])
                    messages.append({'role': 'assistant', 'content': event['text']})
                    break
            else:
                raise RuntimeError(f'Host exited: {proc.poll()}')
    finally:
        proc.kill()
        proc.wait()
