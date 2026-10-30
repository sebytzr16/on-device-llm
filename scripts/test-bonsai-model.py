"""Run reproducible greedy/PPL checks without modifying model files.

Example: python scripts/test-bonsai-model.py --tools build/bonsai-tests-cuda
  --model C:/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf --gpu-layers 99
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

SIZES = {
    'Ternary-Bonsai-2-2B-PTQ1_0.gguf': 429183456,
    'Ternary-Bonsai-2-2B-PQ2_0.gguf': 517312992,
    'Ternary-Bonsai-2-2B-Q2_0.gguf': 546689504,
    'Ternary-Bonsai-2-27B-PTQ1_0.gguf': 5946648928,
}
PROMPTS = [
    'What is 17 + 25? Answer with just the number.',
    'What is the capital of France? Answer with just the city name.',
    'Explain in one sentence why the sky is blue.',
]
TEXT = '''The morning train arrived at the station just after sunrise. A few travelers
stepped onto the platform carrying bags and folded newspapers. Across the street,
a small bakery opened its doors, and the smell of warm bread drifted into the cool
air. Maria bought a loaf for her family and walked home along the river. She had
lived in the town for many years, but the quiet water still gave her a reason to
stop and look. On the opposite bank, two children were watching a duck swim toward
the bridge. Their father pointed out the reflection of the trees in the water.

At home, Maria placed the bread on the kitchen table and opened a book. The book
described how people learned to measure time by observing the movement of the sun
and stars. Early clocks could be simple arrangements of shadows and marks on stone.
Later, water and mechanical wheels made it possible to divide a day more precisely.
Today, clocks help people coordinate travel, work, and conversations across the
world. Accurate measurement is useful, but it does not change how quickly a happy
afternoon seems to pass. Maria closed the book when her daughter came into the room.
They made tea and talked about their plans for the weekend.

The weather forecast promised rain on Saturday and clear skies on Sunday. They
decided to visit the museum first, then take a walk in the hills if the paths were
dry. The museum had a new exhibition about plants and insects. Each display showed
how a living thing depended on its surroundings. Flowers provided food for bees,
while bees carried pollen between flowers. Trees offered shelter for birds and
helped hold the soil in place. The exhibition reminded visitors that small changes
can affect many connected parts of a natural system. Understanding those connections
requires careful observation, clear questions, and evidence that others can check.
'''

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tools', type=Path, required=True)
    p.add_argument('--model', type=Path, required=True)
    p.add_argument('--gpu-layers', type=int, default=0)
    p.add_argument('--output', type=Path, default=Path('build/bonsai-results'))
    p.add_argument('--skip-ppl', action='store_true')
    p.add_argument('--tokens', type=int, default=64)
    p.add_argument('--threads', type=int, default=8)
    p.add_argument('--wait-for-gpu', action='store_true', help='Wait for less than 1024 MiB GPU use before each CUDA run')
    a = p.parse_args()
    actual_size = a.model.stat().st_size
    expected_size = SIZES.get(a.model.name)
    if expected_size and actual_size != expected_size:
        raise SystemExit(f'Incomplete model: {actual_size} != {expected_size}')
    sha = hashlib.file_digest(a.model.open('rb'), 'sha256').hexdigest()
    if a.model.name == 'Ternary-Bonsai-2-27B-PTQ1_0.gguf':
        assert sha == '53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3'
    env = os.environ.copy()
    cuda = Path(env.get('CUDA_PATH', 'C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.3'))
    env['PATH'] = str(cuda/'bin/x64') + os.pathsep + str(cuda/'bin') + os.pathsep + env['PATH']
    out = a.output / (a.model.stem + f'-ngl{a.gpu_layers}')
    out.mkdir(parents=True, exist_ok=True)
    result = {'model': str(a.model.resolve()), 'bytes': actual_size, 'sha256': sha, 'runs': []}
    def run(name, args):
        gpu_used = None
        if a.wait_for_gpu and a.gpu_layers > 0:
            while True:
                gpu_used = int(subprocess.check_output(
                    ['nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits'],
                    text=True).strip().splitlines()[0])
                print(f'{time.strftime("%Y-%m-%d %H:%M:%S")} GPU used: {gpu_used} MiB', flush=True)
                if gpu_used < 1024:
                    break
                time.sleep(10)
        start = time.perf_counter()
        cmd = [str(x) for x in args]
        print(subprocess.list2cmdline(cmd), flush=True)
        monitor = None
        gpu_log = None
        if a.gpu_layers > 0:
            gpu_log = (out/f'{name}.gpu.csv').open('wb')
            monitor = subprocess.Popen(
                ['nvidia-smi', '--query-gpu=timestamp,memory.used', '--format=csv,noheader,nounits', '--loop-ms=250'],
                stdout=gpu_log, stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            with (out/f'{name}.stdout.txt').open('wb') as stdout, (out/f'{name}.stderr.txt').open('wb') as stderr:
                proc = subprocess.run(cmd, env=env, stdout=stdout, stderr=stderr)
        finally:
            if monitor:
                monitor.terminate()
                monitor.wait(timeout=10)
                gpu_log.close()
        peak_gpu = None
        if gpu_log:
            readings = (out/f'{name}.gpu.csv').read_text().splitlines()
            values = [int(l.rsplit(',', 1)[1].strip()) for l in readings if ',' in l]
            peak_gpu = max(values, default=None)
        output = (out/f'{name}.stdout.txt').read_text(encoding='utf-8', errors='replace')
        log = (out/f'{name}.stderr.txt').read_text(encoding='utf-8', errors='replace')
        row = {'name': name, 'command': cmd, 'returncode': proc.returncode,
               'gpu_used_mib_before_run': gpu_used,
               'peak_gpu_used_mib': peak_gpu,
               'elapsed_seconds': time.perf_counter()-start, 'output': output,
               'performance': [l for l in log.splitlines() if 'tokens per second' in l or 'Final estimate' in l]}
        result['runs'].append(row)
        (out/'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(row, ensure_ascii=True), flush=True)
        if proc.returncode:
            raise SystemExit(f'{name} failed: see {out}')
    common = ['-m', a.model, '-ngl', a.gpu_layers, '-t', a.threads, '-tb', a.threads,
              '-c', 512, '-b', 128, '-ub', 128, '-fa', 'on', '--no-warmup']
    for i, prompt in enumerate(PROMPTS):
        raw = f'<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n'
        run(f'greedy-{i}', [a.tools/'llama-completion.exe', *common, '-p', raw, '-n', a.tokens,
                           '--temp', 0, '--seed', 42, '--no-conversation', '--no-display-prompt'])
    if not a.skip_ppl:
        corpus = out/'corpus.txt'
        corpus.write_text(TEXT*3, encoding='utf-8', newline='\n')
        run('ppl', [a.tools/'llama-perplexity.exe', *common, '-f', corpus, '--chunks', 2])
    print(f'Results: {out}', flush=True)

if __name__ == '__main__':
    main()
