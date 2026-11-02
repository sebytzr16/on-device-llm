import 'dart:io' as io;

import 'package:archive/archive.dart';
import '../../../core/l10n/l10n.dart';

/// Reads ZIP metadata without the decoder's eager symlink inflation.
Archive readZipMetadata(
  InputStream input, {
  required int maxEntries,
  AppLocalizations? strings,
}) {
  final t = strings ?? stringsFor('');
  final directory = ZipDirectory()..read(input);
  if (directory.fileHeaders.length > maxEntries) {
    throw FormatException(t.documentArchiveManyFiles);
  }
  final archive = Archive();
  final names = <String>{};
  for (final header in directory.fileHeaders) {
    final file = header.file!;
    if (!names.add(file.filename) ||
        (file.flags & 1) != 0 ||
        (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
        (file.compressionMethod != CompressionType.none &&
            file.compressionMethod != CompressionType.deflate)) {
      throw FormatException(t.documentZipEntry);
    }
    final entry = ArchiveFile.file(file.filename, file.uncompressedSize, file)
      ..compression = file.compressionMethod
      ..crc32 = file.crc32
      ..isFile = !file.filename.endsWith('/');
    archive.addFile(entry);
  }
  return archive;
}

/// Counts actual output before handing each chunk to its destination.
int inflateZipEntry(
  ArchiveFile file,
  int limit,
  void Function(List<int>) write, {
  AppLocalizations? strings,
}) {
  final t = strings ?? stringsFor('');
  var count = 0;
  var crc = 0;
  final sink = _ZipSink((bytes) {
    if (bytes.length > limit - count) {
      throw FormatException(t.documentArchiveExpandedLarge);
    }
    count += bytes.length;
    crc = getCrc32(bytes, crc);
    write(bytes);
  });
  final raw = file.rawContent!.getStream(decompress: false);
  final decoder = file.compression == CompressionType.deflate
      ? io.ZLibDecoder(raw: true).startChunkedConversion(sink)
      : sink;
  final position = raw.position;
  try {
    while (!raw.isEOS) {
      decoder.add(
        raw.readBytes(raw.length < 16384 ? raw.length : 16384).toUint8List(),
      );
    }
    decoder.close();
  } finally {
    raw.setPosition(position);
  }
  if (count != file.size || (file.crc32 != null && crc != file.crc32)) {
    throw FormatException(t.documentZipChecksum);
  }
  return count;
}

class _ZipSink implements Sink<List<int>> {
  final void Function(List<int>) write;
  _ZipSink(this.write);
  @override
  void add(List<int> data) => write(data);
  @override
  void close() {}
}
