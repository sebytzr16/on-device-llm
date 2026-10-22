import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../data/storage/model_storage.dart';

/// One pinned, hash-checked download of the on-device voice.
class VoiceFile {
  final String fileName, url, sha256;
  final int sizeBytes;
  const VoiceFile({
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });
}

/// A voice component: its files, and for an archive the folder it unpacks
/// to.
class VoicePack {
  final String id;
  final List<VoiceFile> files;

  /// For an archive pack: the folder (under the models folder) it unpacks
  /// to; the archive is deleted once unpacked.
  final String? unpackTo;
  const VoicePack({required this.id, required this.files, this.unpackTo});

  String get downloadKey => 'voice:$id';
  int get sizeBytes => files.fold(0, (a, f) => a + f.sizeBytes);
}

/// The on-device voice (tester, 2026-10-07): Whisper for listening with
/// Silero voice-activity detection, Kokoro-82M for speaking, both through
/// sherpa-onnx. No account, key or network once downloaded.
class VoiceModels {
  static const _whisperRevision = 'bb53ee204431c90d314c1cc08d28d23e5b7927cc';
  static const _whisper =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/$_whisperRevision';

  /// Whisper base (multilingual, int8) + Silero VAD: 160 MB. Base is the
  /// largest that stays fast on a phone CPU (0.4 s for a 4 s sentence on a
  /// laptop); EN and ES were word-perfect in the 2026-10-07 check, FR close.
  static const listening = VoicePack(
    id: 'whisper-base',
    files: [
      VoiceFile(
        fileName: 'whisper-base-encoder.int8.onnx',
        url: '$_whisper/base-encoder.int8.onnx',
        sha256:
            '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
        sizeBytes: 29120534,
      ),
      VoiceFile(
        fileName: 'whisper-base-decoder.int8.onnx',
        url: '$_whisper/base-decoder.int8.onnx',
        sha256:
            '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
        sizeBytes: 130672026,
      ),
      VoiceFile(
        fileName: 'whisper-base-tokens.txt',
        url: '$_whisper/base-tokens.txt',
        sha256:
            'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
        sizeBytes: 816730,
      ),
      VoiceFile(
        fileName: 'silero_vad.onnx',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
        sha256:
            '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
        sizeBytes: 643854,
      ),
    ],
  );

  static const _parakeetRevision = '2bda32ec70b097a55adaa07d9a7173915b43cc78';
  static const _parakeet =
      'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/$_parakeetRevision';

  /// Parakeet TDT 0.6B v3 (NVIDIA, CC-BY-4.0, int8 through sherpa-onnx):
  /// 25 European languages, non-autoregressive, 670 MB. An optional
  /// listening model next to Whisper base, which is weak on French and
  /// Spanish (technology scan, 2026-10-11). It uses the voice pack's
  /// Silero detector, listed here too so it works on its own.
  static const parakeet = VoicePack(
    id: 'parakeet-tdt-0.6b-v3',
    files: [
      VoiceFile(
        fileName: 'parakeet-v3-encoder.int8.onnx',
        url: '$_parakeet/encoder.int8.onnx',
        sha256:
            'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
        sizeBytes: 652184281,
      ),
      VoiceFile(
        fileName: 'parakeet-v3-decoder.int8.onnx',
        url: '$_parakeet/decoder.int8.onnx',
        sha256:
            '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
        sizeBytes: 11845275,
      ),
      VoiceFile(
        fileName: 'parakeet-v3-joiner.int8.onnx',
        url: '$_parakeet/joiner.int8.onnx',
        sha256:
            '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
        sizeBytes: 6355277,
      ),
      VoiceFile(
        fileName: 'parakeet-v3-tokens.txt',
        url: '$_parakeet/tokens.txt',
        sha256:
            'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
        sizeBytes: 93939,
      ),
      VoiceFile(
        fileName: 'silero_vad.onnx',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
        sha256:
            '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
        sizeBytes: 643854,
      ),
    ],
  );

  /// The [InferenceSettings.listeningModel] id of [parakeet].
  static const parakeetSetting = 'parakeet-v3';

  /// Kokoro-82M v1.0: 54 voices including French (ff_siwis) and Spanish
  /// (ef_dora, em_alex); v1.1 has only English and Chinese. Full precision:
  /// on the phone the int8 model was the slower one (8.5 s for 6.2 s of
  /// speech, against 5.3 s; threads, XNNPACK and NNAPI changed nothing,
  /// 2026-10-07), and slower than speech means gaps between sentences.
  static const speaking = VoicePack(
    id: 'kokoro-v1.0',
    unpackTo: 'kokoro-multi-lang-v1_0',
    files: [
      VoiceFile(
        fileName: 'kokoro-multi-lang-v1_0.tar.bz2',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2',
        sha256:
            'c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298',
        sizeBytes: 349906910,
      ),
    ],
  );

  /// Where the int8 Kokoro of earlier versions was unpacked: still used
  /// until the full-precision one is downloaded.
  static const legacySpeakingDir = 'kokoro-int8-multi-lang-v1_0';

  /// The voice pack: one download row, both needed for Conversation.
  static const packs = [listening, speaking];

  /// Every pack the app can install, the optional ones included.
  static const all = [listening, speaking, parakeet];

  /// Marker written last when an archive is fully unpacked.
  static const readyMarker = '.ready';

  static Future<bool> isReady(VoicePack pack) async {
    if (pack.unpackTo != null) {
      final dir = await ModelStorage.modelsDir();
      bool ready(String folder) =>
          File(p.join(dir.path, folder, readyMarker)).existsSync();
      return ready(pack.unpackTo!) ||
          (pack.id == speaking.id && ready(legacySpeakingDir));
    }
    for (final f in pack.files) {
      if (!await ModelStorage.exists(f.fileName)) return false;
    }
    return true;
  }

  /// Unpacks a downloaded archive pack into its folder (in a background
  /// isolate: about 12 s on a laptop) and deletes the archive. Chinese
  /// text-processing files are skipped; the app speaks EN/FR/ES.
  static Future<void> unpack(VoicePack pack) async {
    final target = pack.unpackTo;
    if (target == null) return;
    final dir = await ModelStorage.modelsDir();
    final archive = (await ModelStorage.modelFile(
      pack.files.single.fileName,
    )).path;
    final out = p.join(dir.path, target);
    await Isolate.run(() => unpackArchive(archive, out));
    await File(archive).delete();
  }

  /// Files of the archive the app does not need.
  static bool skipped(String name) {
    final base = name.split('/').last;
    return name.contains('/dict/') ||
        base.endsWith('-zh.txt') ||
        base.endsWith('-zh.fst') ||
        base == 'README.md';
  }

  /// bz2 → tar (next to the archive) → files under [out], whose top folder
  /// replaces the archive's own; [readyMarker] is written last.
  static void unpackArchive(String archive, String out) {
    final tar = '$archive.tar';
    final input = InputFileStream(archive);
    final output = OutputFileStream(tar);
    try {
      BZip2Decoder().decodeStream(input, output);
    } finally {
      input.closeSync();
      output.closeSync();
    }
    final root = Directory(out);
    if (root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    final tarInput = InputFileStream(tar);
    try {
      for (final entry in TarDecoder().decodeStream(tarInput)) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final parts = p.posix.normalize(entry.name).split('/');
        if (parts.length < 2 || parts.contains('..')) continue;
        final relative = parts.skip(1).join('/');
        if (skipped('/$relative')) continue;
        final file = File(p.join(out, relative));
        file.parent.createSync(recursive: true);
        final sink = OutputFileStream(file.path);
        try {
          entry.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        if (file.lengthSync() != entry.size) {
          throw FileSystemException('Unpacked file is incomplete', file.path);
        }
      }
    } finally {
      tarInput.closeSync();
      File(tar).deleteSync();
    }
    File(p.join(out, readyMarker)).writeAsStringSync('ok');
  }

  static Future<void> delete(VoicePack pack) async {
    // A file another installed pack lists too (the Silero detector) stays.
    final shared = <String>{};
    for (final other in all) {
      if (other.id == pack.id || !await isReady(other)) continue;
      shared.addAll(other.files.map((f) => f.fileName));
    }
    for (final f in pack.files) {
      if (shared.contains(f.fileName)) continue;
      await ModelStorage.delete(f.fileName);
      await ModelStorage.deletePartial(f.fileName);
    }
    if (pack.unpackTo != null) {
      final root = (await ModelStorage.modelsDir()).path;
      for (final folder in [
        pack.unpackTo!,
        if (pack.id == speaking.id) legacySpeakingDir,
      ]) {
        final dir = Directory(p.join(root, folder));
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    }
  }

  /// Absolute paths the speech engine needs, or null when not installed.
  /// [preferred] is [InferenceSettings.listeningModel]: Parakeet when
  /// chosen and downloaded, else Whisper base, else Parakeet when it is the
  /// only one there.
  static Future<ListeningPaths?> listeningPaths({String preferred = ''}) async {
    Future<String> f(String name) async =>
        (await ModelStorage.modelFile(name)).path;
    Future<ListeningPaths> parakeetPaths() async => ListeningPaths(
      encoder: await f('parakeet-v3-encoder.int8.onnx'),
      decoder: await f('parakeet-v3-decoder.int8.onnx'),
      joiner: await f('parakeet-v3-joiner.int8.onnx'),
      tokens: await f('parakeet-v3-tokens.txt'),
      vad: await f('silero_vad.onnx'),
    );
    if (preferred == parakeetSetting && await isReady(parakeet)) {
      return parakeetPaths();
    }
    if (await isReady(listening)) {
      return ListeningPaths(
        encoder: await f('whisper-base-encoder.int8.onnx'),
        decoder: await f('whisper-base-decoder.int8.onnx'),
        tokens: await f('whisper-base-tokens.txt'),
        vad: await f('silero_vad.onnx'),
      );
    }
    if (await isReady(parakeet)) return parakeetPaths();
    return null;
  }

  static Future<SpeakingPaths?> speakingPaths() async {
    if (!await isReady(speaking)) return null;
    final root = (await ModelStorage.modelsDir()).path;
    var dir = p.join(root, speaking.unpackTo!);
    var model = 'model.onnx';
    if (!File(p.join(dir, readyMarker)).existsSync()) {
      dir = p.join(root, legacySpeakingDir);
      model = 'model.int8.onnx';
    }
    return SpeakingPaths(
      model: p.join(dir, model),
      voices: p.join(dir, 'voices.bin'),
      tokens: p.join(dir, 'tokens.txt'),
      dataDir: p.join(dir, 'espeak-ng-data'),
      lexiconUs: p.join(dir, 'lexicon-us-en.txt'),
      lexiconGb: p.join(dir, 'lexicon-gb-en.txt'),
    );
  }
}

class ListeningPaths {
  final String encoder, decoder, tokens, vad;

  /// Parakeet's joiner; null for Whisper.
  final String? joiner;
  const ListeningPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
    this.joiner,
  });

  bool get parakeet => joiner != null;
}

class SpeakingPaths {
  final String model, voices, tokens, dataDir, lexiconUs, lexiconGb;
  const SpeakingPaths({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.lexiconUs,
    required this.lexiconGb,
  });

  /// English voices read words from Kokoro's lexicon; other languages go
  /// through espeak-ng alone.
  String lexiconFor(String lang) => switch (lang) {
    'en-us' => lexiconUs,
    'en-gb' => lexiconGb,
    _ => '',
  };
}

/// A Kokoro speaker for a language: sid in voices.bin and the espeak-ng
/// language Kokoro's phonemizer is given.
class KokoroVoice {
  final int sid;
  final String lang;
  final String name;
  const KokoroVoice(this.sid, this.lang, this.name);

  /// Voices offered per app language (sids from the sherpa-onnx v1.0 table).
  static const byLanguage = {
    'en': [
      KokoroVoice(3, 'en-us', 'Heart'),
      KokoroVoice(2, 'en-us', 'Bella'),
      KokoroVoice(16, 'en-us', 'Michael'),
      KokoroVoice(21, 'en-gb', 'Emma'),
      KokoroVoice(26, 'en-gb', 'George'),
    ],
    'fr': [KokoroVoice(30, 'fr', 'Siwis')],
    'es': [KokoroVoice(28, 'es', 'Dora'), KokoroVoice(29, 'es', 'Alex')],
  };

  static KokoroVoice forLanguage(String code, {int? sid}) {
    final list = byLanguage[code] ?? byLanguage['en']!;
    return list.where((v) => v.sid == sid).firstOrNull ?? list.first;
  }
}
