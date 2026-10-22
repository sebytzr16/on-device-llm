"""Decode SuspendState candidates in Android tombstones of the Dart app.

For each tombstone: find libapp.so's r-x mapping (base.apk mapping that is
r-x and whose file offset is NOT the libflutter one), then scan the 'memory
near' dumps for the pattern [frame_size (< 64 KB)] [pc inside that mapping]
followed by three compressed pointers; print pc offset within the mapping and
the surrounding words.
"""
import re, sys, glob, os

root = sys.argv[1]
for path in sorted(glob.glob(os.path.join(root, 'tombstone_[0-9][0-9]'))):
    txt = open(path, encoding='utf-8', errors='replace').read()
    if 'ondevice_llm' not in txt[:2000]:
        continue
    ts = re.search(r'Timestamp: (\S+ \S+)', txt).group(1)
    sig = re.search(r'signal \d+ \([A-Z]+\), code \d+ \(([A-Z_]+)\), fault addr (\S+)', txt)
    # executable base.apk mappings: (start, end, fileoffset)
    maps = []
    for m in re.finditer(r"^\s+([0-9a-f']{17})-([0-9a-f']{17})\s+r-x\s+([0-9a-f]+)\s+([0-9a-f]+)\s+(.*)$", txt, re.M):
        s = int(m.group(1).replace("'", ''), 16); e = int(m.group(2).replace("'", ''), 16)
        maps.append((s, e, int(m.group(3), 16), m.group(5)))
    # memory dumps: address -> two qwords per line
    words = {}
    for m in re.finditer(r'^\s+([0-9a-f]{16}) ([0-9a-f]{16}) ([0-9a-f]{16})', txt, re.M):
        a = int(m.group(1), 16)
        words[a] = int(m.group(2), 16); words[a + 8] = int(m.group(3), 16)
    found = []
    for a, v in words.items():
        fs = words.get(a - 8)
        if fs is None or fs == 0 or fs > 0x10000 or fs % 8:
            continue
        for (s, e, off, name) in maps:
            if s <= v < e and 'flutter' not in name:
                nxt = words.get(a + 8, 0)
                found.append((a - 16, fs, v, v - s, off, nxt))
    print(f"{os.path.basename(path)} {ts} {sig.group(1) if sig else ''} {sig.group(2) if sig else ''}")
    for (obj, fs, pc, rel, off, nxt) in found:
        print(f"   SuspendState@{obj:x} frame_size={fs:#x} pc={pc:#x} pc-mapstart={rel:#x} map_fileoff={off:#x} next={nxt:#018x}")
