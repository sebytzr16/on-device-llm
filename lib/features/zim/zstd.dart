import 'dart:typed_data';

/// A Zstandard decoder (RFC 8878) in Dart, for the compressed clusters of
/// Kiwix ZIM files. Decoding only, no dictionaries; the content checksum
/// is skipped. Frames are decoded whole into memory, which suits ZIM
/// clusters (a few MB at most).
class Zstd {
  static const _magic = 0xFD2FB528;

  /// Every frame in [src], concatenated. Skippable frames are skipped.
  static Uint8List decode(Uint8List src) {
    final out = _Out(src.length * 4);
    var p = 0;
    while (p + 4 <= src.length) {
      final magic = _u32(src, p);
      if ((magic & 0xFFFFFFF0) == 0x184D2A50) {
        p += 8 + _u32(src, p + 4);
        continue;
      }
      if (magic != _magic) throw const FormatException('Not a zstd frame');
      p = _Frame(src, p + 4, out).decode();
    }
    return out.bytes();
  }

  static int _u32(Uint8List b, int p) =>
      b[p] | b[p + 1] << 8 | b[p + 2] << 16 | b[p + 3] << 24;
}

class _Out {
  Uint8List buf;
  int length = 0;
  _Out(int capacity) : buf = Uint8List(capacity < 1024 ? 1024 : capacity);

  void _ensure(int extra) {
    if (length + extra <= buf.length) return;
    var size = buf.length * 2;
    while (size < length + extra) {
      size *= 2;
    }
    buf = Uint8List(size)..setRange(0, length, buf);
  }

  void addAll(Uint8List src, int start, int end) {
    _ensure(end - start);
    buf.setRange(length, length + end - start, src, start);
    length += end - start;
  }

  void fill(int byte, int count) {
    _ensure(count);
    buf.fillRange(length, length + count, byte);
    length += count;
  }

  /// Copies [count] bytes from [offset] back; overlapping copies repeat.
  void match(int offset, int count) {
    if (offset <= 0 || offset > length) {
      throw const FormatException('zstd: offset outside the output');
    }
    _ensure(count);
    var from = length - offset;
    if (offset >= count) {
      buf.setRange(length, length + count, buf, from);
      length += count;
      return;
    }
    for (var i = 0; i < count; i++) {
      buf[length++] = buf[from++];
    }
  }

  Uint8List bytes() => Uint8List.sublistView(buf, 0, length);
}

/// A decoding table: symbol, bits to read and the baseline per state.
class _Fse {
  final int log;
  final Uint8List symbol;
  final Uint8List bits;
  final Int32List base;
  _Fse(this.log, this.symbol, this.bits, this.base);

  factory _Fse.rle(int s) =>
      _Fse(0, Uint8List(1)..[0] = s, Uint8List(1), Int32List(1));

  factory _Fse.build(List<int> norm, int log) {
    final size = 1 << log;
    final symbol = Uint8List(size);
    final bits = Uint8List(size);
    final base = Int32List(size);
    final next = List<int>.filled(norm.length, 0);
    var high = size - 1;
    for (var s = 0; s < norm.length; s++) {
      if (norm[s] == -1) {
        symbol[high--] = s;
        next[s] = 1;
      } else {
        next[s] = norm[s];
      }
    }
    final step = (size >> 1) + (size >> 3) + 3;
    final mask = size - 1;
    var pos = 0;
    for (var s = 0; s < norm.length; s++) {
      for (var i = 0; i < norm[s]; i++) {
        symbol[pos] = s;
        do {
          pos = (pos + step) & mask;
        } while (pos > high);
      }
    }
    if (pos != 0) throw const FormatException('zstd: bad FSE table');
    for (var u = 0; u < size; u++) {
      final n = next[symbol[u]]++;
      final b = log - _highBit(n);
      bits[u] = b;
      base[u] = (n << b) - size;
    }
    return _Fse(log, symbol, bits, base);
  }
}

int _highBit(int v) {
  var n = -1;
  while (v > 0) {
    v >>= 1;
    n++;
  }
  return n;
}

/// Reads an FSE table description (forward bit stream). Returns the
/// normalised counts and the bytes it used.
(List<int>, int, int) _readCounts(
  Uint8List d,
  int start,
  int end,
  int maxSymbol,
  int maxLog,
) {
  var bitPos = 0;
  int read(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      final at = start + ((bitPos + i) >> 3);
      final bit = at < end ? (d[at] >> ((bitPos + i) & 7)) & 1 : 0;
      v |= bit << i;
    }
    return v;
  }

  int peek(int n) {
    final v = read(n);
    return v;
  }

  final log = read(4) + 5;
  bitPos = 4;
  if (log > maxLog) throw const FormatException('zstd: accuracy log too big');
  final norm = <int>[];
  var remaining = (1 << log) + 1;
  var threshold = 1 << log;
  var nbBits = log + 1;
  var previous0 = false;
  while (remaining > 1 && norm.length <= maxSymbol) {
    if (previous0) {
      while (true) {
        final r = read(2);
        bitPos += 2;
        for (var i = 0; i < r; i++) {
          norm.add(0);
        }
        if (r != 3) break;
      }
      if (norm.length > maxSymbol) break;
    }
    final max = (2 * threshold - 1) - remaining;
    final bitsVal = peek(nbBits);
    int count;
    if ((bitsVal & (threshold - 1)) < max) {
      count = bitsVal & (threshold - 1);
      bitPos += nbBits - 1;
    } else {
      count = bitsVal & (2 * threshold - 1);
      if (count >= threshold) count -= max;
      bitPos += nbBits;
    }
    count--;
    remaining -= count < 0 ? -count : count;
    norm.add(count);
    previous0 = count == 0;
    while (remaining < threshold) {
      nbBits--;
      threshold >>= 1;
    }
  }
  if (remaining != 1) throw const FormatException('zstd: bad FSE counts');
  return (norm, log, (bitPos + 7) >> 3);
}

/// A bit stream read backwards from its end, as zstd writes entropy
/// streams. Reading past the start yields zeros and sets [overflow].
class _Back {
  final Uint8List d;
  final int start, end;
  int pos;
  _Back(this.d, this.start, this.end) : pos = 0 {
    if (end <= start) throw const FormatException('zstd: empty bit stream');
    final last = d[end - 1];
    if (last == 0) throw const FormatException('zstd: bit stream marker');
    pos = (end - start - 1) * 8 + _highBit(last);
  }

  bool get overflow => pos < 0;
  bool get finished => pos == 0;

  int _extract(int p, int n) {
    var at = start + (p >> 3);
    final shift = p & 7;
    var v = 0;
    for (var i = 0; i < 6 && at < end; i++, at++) {
      v |= d[at] << (8 * i);
    }
    return (v >> shift) & ((1 << n) - 1);
  }

  int peek(int n) {
    if (n == 0) return 0;
    if (pos >= n) return _extract(pos - n, n);
    if (pos <= 0) return 0;
    return _extract(0, pos) << (n - pos);
  }

  int read(int n) {
    final v = peek(n);
    pos -= n;
    return v;
  }
}

class _Huffman {
  final int log;
  final Uint8List symbol;
  final Uint8List bits;
  _Huffman(this.log, this.symbol, this.bits);

  /// The tree description at [p]; returns the table and the bytes used.
  static (_Huffman, int) read(Uint8List d, int p, int end) {
    final header = d[p];
    final weights = <int>[];
    var used = 1;
    if (header < 128) {
      final (norm, log, n) = _readCounts(d, p + 1, p + 1 + header, 255, 6);
      final fse = _Fse.build(norm, log);
      final bits = _Back(d, p + 1 + n, p + 1 + header);
      var s1 = bits.read(log), s2 = bits.read(log);
      while (true) {
        weights.add(fse.symbol[s1]);
        s1 = fse.base[s1] + bits.read(fse.bits[s1]);
        if (bits.overflow) {
          weights.add(fse.symbol[s2]);
          break;
        }
        weights.add(fse.symbol[s2]);
        s2 = fse.base[s2] + bits.read(fse.bits[s2]);
        if (bits.overflow) {
          weights.add(fse.symbol[s1]);
          break;
        }
        if (weights.length > 255) {
          throw const FormatException('zstd: too many weights');
        }
      }
      used += header;
    } else {
      final n = header - 127;
      for (var i = 0; i < n; i++) {
        final b = d[p + 1 + (i >> 1)];
        weights.add(i.isEven ? b >> 4 : b & 15);
      }
      used += (n + 1) >> 1;
    }
    var total = 0;
    for (final w in weights) {
      if (w > 0) total += 1 << (w - 1);
    }
    if (total == 0) throw const FormatException('zstd: empty Huffman tree');
    final maxBits = _highBit(total) + 1;
    final left = (1 << maxBits) - total;
    if (left & (left - 1) != 0) {
      throw const FormatException('zstd: bad Huffman weights');
    }
    weights.add(_highBit(left) + 1);
    if (maxBits > 11) throw const FormatException('zstd: Huffman too deep');
    final size = 1 << maxBits;
    final symbol = Uint8List(size), bits = Uint8List(size);
    final rank = List<int>.filled(maxBits + 2, 0);
    for (final w in weights) {
      if (w > 0) rank[w]++;
    }
    var next = 0;
    for (var w = 1; w <= maxBits; w++) {
      final current = next;
      next += rank[w] << (w - 1);
      rank[w] = current;
    }
    for (var s = 0; s < weights.length; s++) {
      final w = weights[s];
      if (w == 0) continue;
      final len = 1 << (w - 1);
      final at = rank[w];
      symbol.fillRange(at, at + len, s);
      bits.fillRange(at, at + len, maxBits + 1 - w);
      rank[w] += len;
    }
    return (_Huffman(maxBits, symbol, bits), used);
  }

  void decodeStream(
    Uint8List d,
    int start,
    int end,
    Uint8List out,
    int o,
    int n,
  ) {
    final b = _Back(d, start, end);
    for (var i = 0; i < n; i++) {
      final idx = b.peek(log);
      out[o + i] = symbol[idx];
      b.pos -= bits[idx];
    }
    if (b.pos != 0) throw const FormatException('zstd: Huffman stream size');
  }
}

const _llBase = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, //
  24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384,
  32768, 65536,
];
const _llBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, //
  4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
];
const _mlBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, //
  23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37, 39, 41, 43, 47,
  51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771,
  65539,
];
const _mlBits = [
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11,
  12, 13, 14, 15, 16,
];
const _llDefault = [
  4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, //
  2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
];
const _mlDefault = [
  1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
  -1, -1, -1, -1, -1,
];
const _ofDefault = [
  1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, //
  -1, -1, -1, -1, -1,
];

class _Frame {
  final Uint8List d;
  int p;
  final _Out out;
  _Huffman? huffman;
  _Fse? ll, of, ml;
  final rep = [1, 4, 8];
  _Frame(this.d, this.p, this.out);

  static final _llPredef = _Fse.build(_llDefault, 6);
  static final _mlPredef = _Fse.build(_mlDefault, 6);
  static final _ofPredef = _Fse.build(_ofDefault, 5);

  int decode() {
    final fhd = d[p++];
    final fcsFlag = fhd >> 6;
    final single = (fhd >> 5) & 1 == 1;
    final checksum = (fhd >> 2) & 1 == 1;
    final dictFlag = fhd & 3;
    if (!single) p++; // window descriptor: the whole frame stays in memory
    p += const [0, 1, 2, 4][dictFlag];
    p += switch (fcsFlag) {
      0 => single ? 1 : 0,
      1 => 2,
      2 => 4,
      _ => 8,
    };
    while (true) {
      final h = d[p] | d[p + 1] << 8 | d[p + 2] << 16;
      p += 3;
      final last = h & 1 == 1;
      final type = (h >> 1) & 3;
      final size = h >> 3;
      switch (type) {
        case 0:
          out.addAll(d, p, p + size);
          p += size;
        case 1:
          out.fill(d[p], size);
          p += 1;
        case 2:
          _block(p, p + size);
          p += size;
        default:
          throw const FormatException('zstd: reserved block type');
      }
      if (last) break;
    }
    if (checksum) p += 4;
    return p;
  }

  void _block(int start, int end) {
    var q = start;
    // Literals.
    final b0 = d[q];
    final ltype = b0 & 3;
    final sf = (b0 >> 2) & 3;
    late Uint8List lit;
    if (ltype < 2) {
      int regen;
      if (sf == 0 || sf == 2) {
        regen = b0 >> 3;
        q += 1;
      } else if (sf == 1) {
        regen = (b0 >> 4) + (d[q + 1] << 4);
        q += 2;
      } else {
        regen = (b0 >> 4) + (d[q + 1] << 4) + (d[q + 2] << 12);
        q += 3;
      }
      if (ltype == 0) {
        lit = Uint8List.sublistView(d, q, q + regen);
        q += regen;
      } else {
        lit = Uint8List(regen)..fillRange(0, regen, d[q]);
        q += 1;
      }
    } else {
      int regen, comp, streams;
      if (sf < 2) {
        final v = d[q] | d[q + 1] << 8 | d[q + 2] << 16;
        regen = (v >> 4) & 0x3FF;
        comp = (v >> 14) & 0x3FF;
        streams = sf == 0 ? 1 : 4;
        q += 3;
      } else if (sf == 2) {
        final v = d[q] | d[q + 1] << 8 | d[q + 2] << 16 | d[q + 3] << 24;
        regen = (v >> 4) & 0x3FFF;
        comp = (v >> 18) & 0x3FFF;
        streams = 4;
        q += 4;
      } else {
        final v =
            d[q] |
            d[q + 1] << 8 |
            d[q + 2] << 16 |
            d[q + 3] << 24 |
            d[q + 4] << 32;
        regen = (v >> 4) & 0x3FFFF;
        comp = (v >> 22) & 0x3FFFF;
        streams = 4;
        q += 5;
      }
      final litEnd = q + comp;
      if (ltype == 2) {
        final (h, used) = _Huffman.read(d, q, litEnd);
        huffman = h;
        q += used;
      }
      final h = huffman;
      if (h == null) throw const FormatException('zstd: no Huffman table');
      lit = Uint8List(regen);
      if (streams == 1) {
        h.decodeStream(d, q, litEnd, lit, 0, regen);
      } else {
        final s1 = d[q] | d[q + 1] << 8;
        final s2 = d[q + 2] | d[q + 3] << 8;
        final s3 = d[q + 4] | d[q + 5] << 8;
        final part = (regen + 3) >> 2;
        var a = q + 6;
        final bounds = [a, a += s1, a += s2, a += s3, litEnd];
        for (var i = 0; i < 4; i++) {
          final n = i < 3 ? part : regen - 3 * part;
          h.decodeStream(d, bounds[i], bounds[i + 1], lit, i * part, n);
        }
      }
      q = litEnd;
    }
    // Sequences.
    if (q >= end) {
      out.addAll(lit, 0, lit.length);
      return;
    }
    var nbSeq = d[q++];
    if (nbSeq == 0) {
      out.addAll(lit, 0, lit.length);
      return;
    }
    if (nbSeq == 255) {
      nbSeq = d[q] + (d[q + 1] << 8) + 0x7F00;
      q += 2;
    } else if (nbSeq >= 128) {
      nbSeq = ((nbSeq - 128) << 8) + d[q++];
    }
    final modes = d[q++];
    _Fse table(int mode, _Fse predef, _Fse? previous, int maxSym, int maxLog) {
      switch (mode) {
        case 0:
          return predef;
        case 1:
          return _Fse.rle(d[q++]);
        case 2:
          final (norm, log, used) = _readCounts(d, q, end, maxSym, maxLog);
          q += used;
          return _Fse.build(norm, log);
        default:
          if (previous == null) {
            throw const FormatException('zstd: no table to repeat');
          }
          return previous;
      }
    }

    ll = table(modes >> 6, _llPredef, ll, 35, 9);
    of = table((modes >> 4) & 3, _ofPredef, of, 31, 8);
    ml = table((modes >> 2) & 3, _mlPredef, ml, 52, 9);
    final llT = ll!, ofT = of!, mlT = ml!;
    final bits = _Back(d, q, end);
    var sl = bits.read(llT.log);
    var so = bits.read(ofT.log);
    var sm = bits.read(mlT.log);
    var litPos = 0;
    for (var i = 0; i < nbSeq; i++) {
      final ofCode = ofT.symbol[so];
      final llCode = llT.symbol[sl];
      final mlCode = mlT.symbol[sm];
      if (llCode > 35 || mlCode > 52 || ofCode > 31) {
        throw const FormatException('zstd: bad sequence code');
      }
      final offsetValue = (1 << ofCode) + bits.read(ofCode);
      final matchLen = _mlBase[mlCode] + bits.read(_mlBits[mlCode]);
      final litLen = _llBase[llCode] + bits.read(_llBits[llCode]);
      int offset;
      if (offsetValue > 3) {
        offset = offsetValue - 3;
        rep[2] = rep[1];
        rep[1] = rep[0];
        rep[0] = offset;
      } else {
        final r = offsetValue - 1 + (litLen == 0 ? 1 : 0);
        if (r == 0) {
          offset = rep[0];
        } else if (r == 1) {
          offset = rep[1];
          rep[1] = rep[0];
          rep[0] = offset;
        } else if (r == 2) {
          offset = rep[2];
          rep[2] = rep[1];
          rep[1] = rep[0];
          rep[0] = offset;
        } else {
          offset = rep[0] - 1;
          rep[2] = rep[1];
          rep[1] = rep[0];
          rep[0] = offset;
        }
      }
      if (litPos + litLen > lit.length) {
        throw const FormatException('zstd: literals overrun');
      }
      out.addAll(lit, litPos, litPos + litLen);
      litPos += litLen;
      out.match(offset, matchLen);
      if (i < nbSeq - 1) {
        sl = llT.base[sl] + bits.read(llT.bits[sl]);
        sm = mlT.base[sm] + bits.read(mlT.bits[sm]);
        so = ofT.base[so] + bits.read(ofT.bits[so]);
      }
    }
    out.addAll(lit, litPos, lit.length);
  }
}
