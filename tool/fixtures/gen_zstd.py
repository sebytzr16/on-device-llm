import os, random, zstandard
out = 'test/fixtures/zstd'  # run from the repo root
os.makedirs(out, exist_ok=True)
rnd = random.Random(7)
words = ('the river city museum tower bridge history paris lyon wine '
         'mountain population century built king war north south').split()
text = ' '.join(rnd.choice(words) for _ in range(12000)).encode()
html = (b'<html><head><title>Eiffel Tower</title></head><body>' +
        b''.join(b'<p>The Eiffel Tower is %d metres tall and was built in %d.</p>' % (300 + i % 30, 1880 + i % 20)
                 for i in range(3000)) + b'</body></html>')
noise = bytes(rnd.getrandbits(8) for _ in range(5000))
cases = {
    'tiny': b'hello zstd',
    'empty': b'',
    'text': text,
    'html': html,
    'noise': noise,
    'mixed': html[:20000] + noise[:2000] + text[:20000],
    'rle': b'a' * 100000,
}
for name, data in cases.items():
    open(os.path.join(out, name + '.bin'), 'wb').write(data)
    for level in (1, 3, 19):
        c = zstandard.ZstdCompressor(level=level, write_checksum=True)
        open(os.path.join(out, f'{name}-{level}.zst'), 'wb').write(c.compress(data))
# Two frames back to back, like a cluster written in pieces.
c = zstandard.ZstdCompressor(level=3)
open(os.path.join(out, 'two.bin'), 'wb').write(b'first frame ' + text[:1000])
open(os.path.join(out, 'two-3.zst'), 'wb').write(c.compress(b'first frame ') + c.compress(text[:1000]))
print(sorted(os.listdir(out)))
print(sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out)))
