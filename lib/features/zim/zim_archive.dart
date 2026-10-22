import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' show XZDecoder;

import 'zstd.dart';
import '../../core/utils/priority_work_queue.dart';

/// One directory entry of a ZIM file: an article, a redirect or metadata.
class ZimEntry {
  final int index;
  final String namespace, url, title, mime;

  /// For a redirect, the entry it points to; else null.
  final int? redirect;
  final int cluster, blob;

  const ZimEntry({
    required this.index,
    required this.namespace,
    required this.url,
    required this.title,
    required this.mime,
    this.redirect,
    this.cluster = 0,
    this.blob = 0,
  });

  bool get isArticle => redirect == null && mime.startsWith('text/html');
}

/// A Kiwix ZIM file (openzim.org/wiki/ZIM_file_format) read in place:
/// offline Wikipedia the tester downloaded or imported. Only the header and
/// MIME list are loaded; entries and clusters are read on demand, and the
/// last few decompressed clusters are kept. Clusters are zstd (current
/// files), xz (older files) or stored.
class ZimArchive {
  static const _magic = 72173914;

  final RandomAccessFile _file;
  final String identity;
  final int entryCount, clusterCount, mainPage;
  final int _urlPtrPos, _clusterPtrPos, _checksumPos;
  int _titlePtrPos;
  late int _titleCount = entryCount;
  final _queue = PriorityWorkQueue();
  Future<void>? _closed;
  final List<String> _mimes;
  final _clusters = <int, (Uint8List, bool)>{};

  ZimArchive._(
    this._file, {
    required this.identity,
    required this.entryCount,
    required this.clusterCount,
    required this.mainPage,
    required int urlPtrPos,
    required int titlePtrPos,
    required int clusterPtrPos,
    required int checksumPos,
    required List<String> mimes,
  }) : _urlPtrPos = urlPtrPos, // ignore: prefer_initializing_formals
       _titlePtrPos = titlePtrPos, // ignore: prefer_initializing_formals
       _clusterPtrPos = clusterPtrPos, // ignore: prefer_initializing_formals
       _checksumPos = checksumPos, // ignore: prefer_initializing_formals
       _mimes = mimes; // ignore: prefer_initializing_formals

  static Future<ZimArchive> open(String path) async {
    final file = await File(path).open();
    try {
      final header = await _readAt(file, 0, 80);
      if (header.length != 80) {
        throw const FormatException('ZIM: truncated header');
      }
      final h = ByteData.sublistView(header);
      if (h.getUint32(0, Endian.little) != _magic) {
        throw const FormatException('Not a ZIM file');
      }
      int u64(int at) => h.getUint64(at, Endian.little);
      final major = h.getUint16(4, Endian.little);
      if (major != 5 && major != 6) {
        throw FormatException('ZIM: unsupported format version $major');
      }
      final length = await file.length();
      final count = h.getUint32(24, Endian.little);
      final clusters = h.getUint32(28, Endian.little);
      final checksum = u64(72);
      if (checksum < 80 || checksum > length - 16) {
        throw const FormatException('ZIM: truncated content or checksum');
      }
      void table(int pos, int bytes) {
        if (pos < 80 || bytes < 0 || pos + bytes > checksum) {
          throw const FormatException('ZIM: table outside archive');
        }
      }

      table(u64(32), count * 8);
      table(u64(48), clusters * 8);
      // v6.3 writers use UINT64_MAX as well as zero for the removed table.
      final oldTitle = u64(40);
      final hasOldTitle = oldTitle != 0 && oldTitle != -1;
      if (hasOldTitle) table(oldTitle, count * 4);
      final mimePos = u64(56);
      final mimeBytes = await _readAt(file, mimePos, 4096);
      final mimes = <String>[];
      var start = 0;
      for (var i = 0; i < mimeBytes.length; i++) {
        if (mimeBytes[i] != 0) continue;
        if (i == start) break;
        mimes.add(utf8.decode(mimeBytes.sublist(start, i)));
        start = i + 1;
      }
      final archive = ZimArchive._(
        file,
        identity: header
            .sublist(8, 24)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        entryCount: h.getUint32(24, Endian.little),
        clusterCount: h.getUint32(28, Endian.little),
        urlPtrPos: u64(32),
        titlePtrPos: hasOldTitle ? oldTitle : 0,
        clusterPtrPos: u64(48),
        mainPage: h.getUint32(64, Endian.little),
        checksumPos: u64(72),
        mimes: mimes,
      );
      await archive._loadTitleListing();
      return archive;
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<T> _run<T>(Future<T> Function() action) {
    if (_closed != null) {
      return Future.error(StateError('ZIM archive is closed'));
    }
    return _queue.submit(action);
  }

  /// Finishes accepted operations before closing the shared file cursor.
  Future<void> close() => _closed ??= _queue.submit(() async {
    _clusters.clear();
    await _file.close();
  });

  int get titleCount => _titleCount;

  Future<void> _loadTitleListing() async {
    final listing = await _findPath('X', 'listing/titleOrdered/v1');
    if (listing != null && listing.redirect == null) {
      final start = await _u64At(_clusterPtrPos + 8 * listing.cluster);
      final info = await _readAt(_file, start, 1);
      if (info.isEmpty) throw const FormatException('ZIM: cut title listing');
      if ((info[0] & 15) <= 1) {
        final (data, extended) = await _cluster(listing.cluster);
        final size = extended ? 8 : 4;
        final d = ByteData.sublistView(data);
        int off(int i) => extended
            ? d.getUint64(i * size, Endian.little)
            : d.getUint32(i * size, Endian.little);
        final payload = await _content(listing);
        if (payload.length % 4 != 0 || payload.length ~/ 4 > entryCount) {
          throw const FormatException('ZIM: invalid title listing length');
        }
        _titlePtrPos = start + 1 + off(listing.blob);
        _titleCount = payload.length ~/ 4;
        return;
      }
    }
    if (_titlePtrPos == 0) {
      throw const FormatException('ZIM: missing title ordered listing');
    }
  }

  static Future<Uint8List> _readAt(RandomAccessFile f, int pos, int n) async {
    await f.setPosition(pos);
    return f.read(n);
  }

  Future<int> _u64At(int pos) async {
    final bytes = await _readAt(_file, pos, 8);
    if (bytes.length != 8) throw const FormatException('ZIM: cut pointer');
    return ByteData.sublistView(bytes).getUint64(0, Endian.little);
  }

  /// The entry at [index] in URL order.
  Future<ZimEntry> entry(int index) => _run(() => _entry(index));

  Future<ZimEntry> _entry(int index) async {
    if (index < 0 || index >= entryCount) {
      throw RangeError.range(index, 0, entryCount - 1, 'entry index');
    }
    final pos = await _u64At(_urlPtrPos + 8 * index);
    if (pos < 80 || pos >= _checksumPos) {
      throw const FormatException('ZIM: invalid entry offset');
    }
    var bytes = await _readAt(_file, pos, 512);
    while (true) {
      final parsed = _parseEntry(index, bytes);
      if (parsed != null) return parsed;
      if (bytes.length < 512 || bytes.length >= 65536) {
        throw const FormatException('ZIM: cut or oversized entry');
      }
      bytes = await _readAt(_file, pos, bytes.length * 4);
    }
  }

  ZimEntry? _parseEntry(int index, Uint8List b) {
    if (b.length < 12) return null;
    final d = ByteData.sublistView(b);
    final mime = d.getUint16(0, Endian.little);
    final paramLen = b[2];
    final ns = String.fromCharCode(b[3]);
    final redirect = mime == 0xffff;
    final p = redirect ? 12 : 16;
    if (b.length < p) return null;
    final urlEnd = b.indexOf(0, p);
    if (urlEnd < 0) return null;
    final titleEnd = b.indexOf(0, urlEnd + 1);
    if (titleEnd < 0 || titleEnd + paramLen > b.length) return null;
    final url = utf8.decode(b.sublist(p, urlEnd), allowMalformed: true);
    final title = titleEnd == urlEnd + 1
        ? url
        : utf8.decode(b.sublist(urlEnd + 1, titleEnd), allowMalformed: true);
    return ZimEntry(
      index: index,
      namespace: ns,
      url: url,
      title: title,
      mime: redirect || mime >= _mimes.length ? '' : _mimes[mime],
      redirect: redirect ? d.getUint32(8, Endian.little) : null,
      cluster: redirect ? 0 : d.getUint32(8, Endian.little),
      blob: redirect ? 0 : d.getUint32(12, Endian.little),
    );
  }

  /// The entry at [i] in title order.
  Future<ZimEntry> entryByTitleIndex(int i) =>
      _run(() => _entryByTitleIndex(i));
  Future<ZimEntry> _entryByTitleIndex(int i) async {
    if (i < 0 || i >= _titleCount) {
      throw RangeError.range(i, 0, _titleCount - 1, 'title index');
    }
    final idx = ByteData.sublistView(
      await _readAt(_file, _titlePtrPos + 4 * i, 4),
    ).getUint32(0, Endian.little);
    return _entry(idx);
  }

  /// The entry titled exactly [title] in [namespaces] (the first that has
  /// one), by binary search over the title list; redirects are followed.
  Future<ZimEntry?> findByTitle(
    String title, {
    List<String> namespaces = const ['C', 'A'],
  }) => _run(() => _findByTitle(title, namespaces));

  Future<ZimEntry?> _findByTitle(String title, List<String> namespaces) async {
    for (final ns in namespaces) {
      final want = utf8.encode('$ns$title');
      var lo = 0, hi = _titleCount - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final e = await _entryByTitleIndex(mid);
        final c = _compare(utf8.encode('${e.namespace}${e.title}'), want);
        if (c == 0) return _resolve(e);
        if (c < 0) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
    }
    return null;
  }

  static int _compare(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  /// [e], or the entry its redirects end at (at most five hops).
  Future<ZimEntry?> resolve(ZimEntry e) => _run(() => _resolve(e));
  Future<ZimEntry?> _resolve(ZimEntry e) async {
    var at = e;
    for (var hop = 0; hop < 5 && at.redirect != null; hop++) {
      if (at.redirect! >= entryCount) {
        throw const FormatException('ZIM: invalid redirect');
      }
      at = await _entry(at.redirect!);
    }
    return at.redirect == null ? at : null;
  }

  /// The bytes of a content entry.
  Future<Uint8List> content(ZimEntry e) => _run(() => _content(e));
  Future<Uint8List> _content(ZimEntry e) async {
    if (e.redirect != null) throw ArgumentError('A redirect has no content');
    final (data, extended) = await _cluster(e.cluster);
    final size = extended ? 8 : 4;
    final d = ByteData.sublistView(data);
    if (data.length < size * 2) {
      throw const FormatException('ZIM: truncated blob table');
    }
    int off(int i) => extended
        ? d.getUint64(i * size, Endian.little)
        : d.getUint32(i * size, Endian.little);
    final blobs = off(0) ~/ size - 1;
    if (blobs < 0 ||
        (blobs + 1) * size > data.length ||
        e.blob < 0 ||
        e.blob >= blobs) {
      throw const FormatException('ZIM: no such blob');
    }
    if (off(e.blob) < (blobs + 1) * size ||
        off(e.blob) > off(e.blob + 1) ||
        off(e.blob + 1) > data.length) {
      throw const FormatException('ZIM: invalid blob offset');
    }
    return Uint8List.sublistView(data, off(e.blob), off(e.blob + 1));
  }

  /// A cluster's blob area, decompressed; the last four are cached.
  Future<(Uint8List, bool)> _cluster(int i) async {
    final hit = _clusters.remove(i);
    if (hit != null) return _clusters[i] = hit;
    if (i < 0 || i >= clusterCount) {
      throw const FormatException('ZIM: no such cluster');
    }
    final start = await _u64At(_clusterPtrPos + 8 * i);
    final end = i + 1 < clusterCount
        ? await _u64At(_clusterPtrPos + 8 * (i + 1))
        : _checksumPos;
    if (start < 80 ||
        end <= start ||
        end > _checksumPos ||
        end - start > 64 * 1024 * 1024) {
      throw const FormatException('ZIM: invalid or oversized cluster');
    }
    final raw = await _readAt(_file, start, end - start);
    if (raw.length != end - start) {
      throw const FormatException('ZIM: cut cluster');
    }
    final info = raw[0];
    final body = Uint8List.sublistView(raw, 1);
    final kind = info & 0x0f;
    // A cluster is a few MB of text: decompressed off the UI isolate.
    final data = switch (kind) {
      0 || 1 => body,
      4 => await Isolate.run(
        () => Uint8List.fromList(XZDecoder().decodeBytes(body)),
      ),
      5 => await Isolate.run(() => Zstd.decode(body)),
      _ => throw FormatException('ZIM: compression $kind'),
    };
    final result = (data, info & 0x10 != 0);
    _clusters[i] = result;
    if (_clusters.length > 4) _clusters.remove(_clusters.keys.first);
    return result;
  }

  /// A metadata value ("Title", "Language", "Date"), or null.
  Future<ZimEntry?> _findPath(String ns, String name) async {
    var lo = 0, hi = entryCount - 1;
    final want = utf8.encode('$ns$name');
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final e = await _entry(mid);
      final c = _compare(utf8.encode('${e.namespace}${e.url}'), want);
      if (c == 0) return e;
      if (c < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  Future<String?> metadata(String name) => _run(() async {
    final e = await _findPath('M', name);
    if (e == null) return null;
    final resolved = await _resolve(e);
    return resolved == null
        ? null
        : utf8.decode(await _content(resolved), allowMalformed: true);
  });
}
