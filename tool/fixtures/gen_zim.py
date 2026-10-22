import os, struct, zstandard
# A small ZIM (format 6) with a zstd cluster, a stored cluster, a
# redirect and metadata, for test/zim_test.dart.
out = 'test/fixtures/zim'  # run from the repo root
os.makedirs(out, exist_ok=True)
lead = ('The Eiffel Tower is a wrought-iron lattice tower on the Champ de Mars '
        'in Paris, France. It is named after the engineer Gustave Eiffel.')
articles = {
    'Eiffel_Tower': ('Eiffel Tower', '<html><head><title>Eiffel Tower</title></head><body>'
                     '<h1>Eiffel Tower</h1><p>%s</p><p>The tower is 330 metres tall, '
                     'about the same height as an 81-storey building.</p></body></html>' % lead),
    'Paris': ('Paris', '<html><body><h1>Paris</h1><p>Paris is the capital and largest city of '
              'France, with an estimated population of 2,102,650 residents in January 2023.</p>'
              '</body></html>'),
    'Nikon_Z30': ('Nikon Z30', '<html><body><h1>Nikon Z30</h1><p>The Nikon Z30 is an entry-level '
                  'mirrorless camera announced by Nikon in June 2022. It weighs 405 g with '
                  'battery and memory card.</p></body></html>'),
    'Mercury': ('Mercury', '<html><body><p>Mercury may refer to:</p><ul><li>Mercury (planet)</li>'
                '</ul></body></html>'),
}
mimes = [b'text/html', b'text/plain']
# Entries: (ns, url, title, mime|None for redirect, cluster, blob, redirect_target_url)
entries = []
for i, (url, (title, html)) in enumerate(sorted(articles.items())):
    entries.append(['C', url, title, 0, 0, i, None])
entries.append(['C', 'La_tour_Eiffel', 'Tour Eiffel', None, 0, 0, 'Eiffel_Tower'])
entries.append(['M', 'Title', '', 1, 1, 0, None])
entries.append(['M', 'Language', '', 1, 1, 1, None])
entries.sort(key=lambda e: (e[0] + e[1]).encode())
index = {e[0] + e[1]: i for i, e in enumerate(entries)}
blobs0 = [html.encode() for _, (title, html) in sorted(articles.items())]
blobs1 = [b'Wikipedia test', b'eng']

def cluster(blobs, comp, extended=False):
    size = 8 if extended else 4
    offs, pos = [], size * (len(blobs) + 1)
    for b in blobs:
        offs.append(pos); pos += len(b)
    offs.append(pos)
    fmt = '<Q' if extended else '<I'
    data = b''.join(struct.pack(fmt, o) for o in offs) + b''.join(blobs)
    info = comp | (0x10 if extended else 0)
    if comp == 5:
        data = zstandard.ZstdCompressor(level=19).compress(data)
    return bytes([info]) + data

clusters = [cluster(blobs0, 5), cluster(blobs1, 1, extended=True)]
mime_list = b''.join(m + b'\0' for m in mimes) + b'\0'

def dirent(e):
    ns, url, title, mime, cl, blob, target = e
    t = b'' if title == url else title.encode()
    if mime is None:
        head = struct.pack('<HBcI', 0xffff, 0, ns.encode(), 0) + struct.pack('<I', index['C' + target])
    else:
        head = struct.pack('<HBcI', mime, 0, ns.encode(), 0) + struct.pack('<II', cl, blob)
    return head + url.encode() + b'\0' + t + b'\0'

header_len = 80
pos = header_len
mime_pos = pos; pos += len(mime_list)
dirs = [dirent(e) for e in entries]
dir_pos = []
for d in dirs:
    dir_pos.append(pos); pos += len(d)
url_ptr_pos = pos; pos += 8 * len(entries)
title_order = sorted(range(len(entries)), key=lambda i: (entries[i][0] + (entries[i][2] or entries[i][1])).encode())
title_ptr_pos = pos; pos += 4 * len(entries)
cl_pos = []
for c in clusters:
    cl_pos.append(pos); pos += len(c)
cluster_ptr_pos = pos; pos += 8 * len(clusters)
checksum_pos = pos
# Cluster pointer list sits after clusters; the last cluster ends where it starts.
# The reader uses checksumPos for the end, so put the pointer list before clusters.
body = bytearray()
body += mime_list
for d in dirs: body += d
body += b''.join(struct.pack('<Q', p) for p in dir_pos)
body += b''.join(struct.pack('<I', i) for i in title_order)
cluster_ptr_pos = header_len + len(body)
cl_start = cluster_ptr_pos + 8 * len(clusters)
cl_pos, p = [], cl_start
for c in clusters:
    cl_pos.append(p); p += len(c)
body += b''.join(struct.pack('<Q', x) for x in cl_pos)
for c in clusters: body += c
checksum_pos = header_len + len(body)
main = index['CEiffel_Tower']
header = struct.pack('<IHH16sIIQQQQIIQ', 72173914, 6, 1, b'\x01' * 16, len(entries), len(clusters),
                     url_ptr_pos, title_ptr_pos, cluster_ptr_pos, mime_pos, main, 0xffffffff, checksum_pos)
assert len(header) == 80
data = header + bytes(body) + b'\0' * 16
open(os.path.join(out, 'mini.zim'), 'wb').write(data)
print(len(data), [e[0] + '/' + e[1] for e in entries])
