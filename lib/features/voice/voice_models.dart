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

  static const _parakeetUltraRevision =
      '402e1190ce85b9793118ee223db21fb0d12f52db';
  static const _parakeetUltra =
      'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-ultra-int8/resolve/$_parakeetUltraRevision';

  /// Parakeet Ultra (Moondream's post-trained Parakeet TDT 0.6B v3,
  /// CC-BY-4.0, int8 through sherpa-onnx): the same architecture and
  /// tokenizer as [parakeet], better on every benchmark. It is the
  /// Parakeet download now; [parakeet] stays so files downloaded earlier
  /// keep working until Ultra is in.
  static const parakeetUltra = VoicePack(
    id: 'parakeet-tdt-0.6b-ultra',
    files: [
      VoiceFile(
        fileName: 'parakeet-ultra-encoder.int8.onnx',
        url: '$_parakeetUltra/encoder.int8.onnx',
        sha256:
            'b43072e1b721f18a3df03fcfeb763ff7c4debdf29843598a3aba2f703e2780a3',
        sizeBytes: 652282345,
      ),
      VoiceFile(
        fileName: 'parakeet-ultra-decoder.int8.onnx',
        url: '$_parakeetUltra/decoder.int8.onnx',
        sha256:
            '1fab98fe6c12aded87d2da66272cc9e148d0a0044ce3850a12fe56302ec4a922',
        sizeBytes: 11845274,
      ),
      VoiceFile(
        fileName: 'parakeet-ultra-joiner.int8.onnx',
        url: '$_parakeetUltra/joiner.int8.onnx',
        sha256:
            '8a71aaccfdba3d451775507a889afd2257d2e754463fd81095a8c8f290f924c2',
        sizeBytes: 6355277,
      ),
      VoiceFile(
        fileName: 'parakeet-ultra-tokens.txt',
        url: '$_parakeetUltra/tokens.txt',
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

  /// The [InferenceSettings.listeningModel] id of both Parakeet packs: the
  /// saved value 'parakeet-v3' now means "Parakeet, best available files".
  static const parakeetSetting = 'parakeet-v3';

  /// Nemotron 3.5 ASR streaming 0.6B (NVIDIA, NVIDIA Open Model License,
  /// int8 through sherpa-onnx): running captions while the user speaks,
  /// word by word, in 25 languages (the model finds the language itself).
  /// An optional download: without it captions keep reading the last
  /// seconds with the listening model, and the final text is the same.
  static const liveCaptions = VoicePack(
    id: 'nemotron-3.5-streaming',
    unpackTo:
        'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11',
    files: [
      VoiceFile(
        fileName:
            'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11.tar.bz2',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11.tar.bz2',
        sha256:
            'c6bf5e0df765f9d5b43bc9e0536d4b4b3e7d40bdf5ecf13e45f134c51c05ae3a',
        sizeBytes: 475271763,
      ),
    ],
  );

  /// Kokoro-82M v1.0: 54 voices including French (ff_siwis) and Spanish
  /// (ef_dora, em_alex); v1.1 has only English and Chinese. Full precision:
  /// on the phone the int8 model was the slower one (8.5 s for 6.2 s of
  /// speech, against 5.3 s; threads, XNNPACK and NNAPI changed nothing,
  /// 2026-10-07), and slower than speech means gaps between sentences.
  /// The release asset was repacked on 2026-10-26 (same files and sizes,
  /// new archive hash); the old pin made resumes fail with HTTP 416.
  static const speaking = VoicePack(
    id: 'kokoro-v1.0',
    unpackTo: 'kokoro-multi-lang-v1_0',
    files: [
      VoiceFile(
        fileName: 'kokoro-multi-lang-v1_0.tar.bz2',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2',
        sha256:
            '60703707bc05ccd48d60e1eb723f38b07d6e474795a0b6a588d7220400e0f7a4',
        sizeBytes: 349886476,
      ),
    ],
  );

  /// Pinned official multilingual Supertonic 3 export (owner, 2026-11-02).
  /// Keep this separate so choosing a comparison voice never replaces Kokoro.
  /// Same v2-compatible ONNX interface and file names inside the archive.
  static const supertonic = VoicePack(
    id: 'supertonic-3',
    unpackTo: 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11',
    files: [
      VoiceFile(
        fileName: 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2',
        url:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2',
        sha256:
            '82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427',
        sizeBytes: 128774318,
      ),
    ],
  );

  /// The saved reading-voice id of Supertonic 2: it still selects
  /// [supertonic] (same interface) and is mapped to the new id on load.
  static const legacySupertonicSetting = 'supertonic-2';

  /// Where Supertonic 2 was unpacked: still used until Supertonic 3 is
  /// downloaded.
  static const legacySupertonicDir =
      'sherpa-onnx-supertonic-tts-int8-2026-03-06';

  /// Languages Supertonic 3 reads. The app's three are all here; a code
  /// outside the list falls back to English as before.
  static const supertonicLanguages = {
    'en',
    'ko',
    'ja',
    'ar',
    'bg',
    'cs',
    'da',
    'de',
    'el',
    'es',
    'et',
    'fi',
    'fr',
    'hi',
    'hr',
    'hu',
    'id',
    'it',
    'lt',
    'lv',
    'nl',
    'pl',
    'pt',
    'ro',
    'ru',
    'sk',
    'sl',
    'sv',
    'tr',
    'uk',
    'vi',
  };

  /// [preferred] is the saved reading voice; 'supertonic-2' still means
  /// [supertonic].
  static bool isSupertonic(String preferred) =>
      preferred == supertonic.id || preferred == legacySupertonicSetting;

  /// The language Supertonic should read for [code]: its own when
  /// Supertonic 3 supports it, else English (what the app falls back to).
  static String supertonicLanguage(String code) {
    final lang = code.split(RegExp('[-_]')).first.toLowerCase();
    return supertonicLanguages.contains(lang) ? lang : 'en';
  }

  static VoicePack speakingPack(String preferred) =>
      isSupertonic(preferred) ? supertonic : speaking;

  static List<VoicePack> packsFor(String preferred) => [
    listening,
    speakingPack(preferred),
  ];

  /// Where the int8 Kokoro of earlier versions was unpacked: still used
  /// until the full-precision one is downloaded.
  static const legacySpeakingDir = 'kokoro-int8-multi-lang-v1_0';

  /// The voice pack: one download row, both needed for Conversation.
  static const packs = [listening, speaking];

  /// Every pack the app can install, the optional ones included. The older
  /// Parakeet v3 pack stays so its files can still be found and deleted.
  static const all = [
    listening,
    speaking,
    parakeetUltra,
    parakeet,
    supertonic,
    liveCaptions,
  ];

  /// The packs the listening side loads: the Whisper/Parakeet recognizers
  /// and the streaming caption model.
  static bool hears(VoicePack pack) =>
      pack == listening ||
      pack == parakeet ||
      pack == parakeetUltra ||
      pack == liveCaptions;

  /// Marker written last when an archive is fully unpacked.
  static const readyMarker = '.ready';

  static Future<bool> isReady(VoicePack pack) async {
    if (pack.unpackTo != null) {
      Future<bool> ready(String folder) async => File(
        p.join(await ModelStorage.resourcePath(folder), readyMarker),
      ).exists();
      return await ready(pack.unpackTo!) ||
          (pack.id == speaking.id && await ready(legacySpeakingDir));
    }
    for (final f in pack.files) {
      if (!await ModelStorage.exists(f.fileName)) return false;
    }
    return true;
  }

  /// Ready from the folder an earlier Supertonic 2 unpacked, when the
  /// current Supertonic 3 pack is not: the same interface, used until the
  /// new pack is downloaded.
  static Future<bool> isLegacyReady(VoicePack pack) async {
    if (pack.id != supertonic.id) return false;
    return File(
      p.join(await ModelStorage.resourcePath(legacySupertonicDir), readyMarker),
    ).exists();
  }

  /// Installed in any form: the current pack, or the older files that still
  /// work (Supertonic 2's folder).
  static Future<bool> isUsable(VoicePack pack) async =>
      await isReady(pack) || await isLegacyReady(pack);

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
        name.contains('/test_wavs/') ||
        base.endsWith('-zh.txt') ||
        base.endsWith('-zh.fst') ||
        base == 'README.md';
  }

  /// bz2 → tar (next to the archive) → files under [out], whose top folder
  /// replaces the archive's own; [readyMarker] is written last.
  static void unpackArchive(String archive, String out) {
    // 1 GB expanded budget: the 475 MB Nemotron captions archive holds
    // int8 weights that bz2 barely shrinks.
    const maxTarBytes = 1024 * 1024 * 1024;
    const maxEntries = 10000;
    final tar = '$archive.tar';
    final input = InputFileStream(archive);
    final output = OutputFileStream(tar);
    var bz2Bytes = 0;
    try {
      BZip2Decoder().decodeStream(input, output);
      bz2Bytes = output.length;
      if (bz2Bytes > maxTarBytes) {
        throw const FileSystemException('TAR archive exceeds size budget');
      }
    } finally {
      input.closeSync();
      output.closeSync();
    }
    final root = Directory(out);
    if (root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    final tarInput = InputFileStream(tar);
    var entryCount = 0;
    try {
      for (final entry in TarDecoder().decodeStream(tarInput)) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        entryCount++;
        if (entryCount > maxEntries) {
          throw const FileSystemException('TAR entry count exceeds limit');
        }
        final parts = p.posix.normalize(entry.name).split('/');
        // Reject Windows path traversal: backslash, drive letter, UNC, absolute.
        for (final part in parts) {
          if (part.contains('\\') ||
              part.contains(':') ||
              part.startsWith('//') ||
              part.startsWith('\\\\')) {
            throw FileSystemException('Invalid path component: $part', out);
          }
        }
        if (parts.length < 2 || parts.contains('..')) continue;
        final relative = parts.skip(1).join('/');
        if (skipped('/$relative')) continue;
        final dest = File(p.join(out, relative));
        // Canonicalize and ensure containment under out.
        // The file does not exist yet, so resolve its (created) parent.
        dest.parent.createSync(recursive: true);
        final canonicalParent = dest.parent.resolveSymbolicLinksSync();
        final canonicalRoot = root.resolveSymbolicLinksSync();
        if (!p.isWithin(canonicalRoot, canonicalParent) &&
            !p.equals(canonicalRoot, canonicalParent)) {
          throw FileSystemException('Path escapes target directory', dest.path);
        }
        final sink = OutputFileStream(dest.path);
        try {
          entry.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        if (dest.lengthSync() != entry.size) {
          throw FileSystemException('Unpacked file is incomplete', dest.path);
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
      for (final folder in [
        pack.unpackTo!,
        if (pack.id == speaking.id) legacySpeakingDir,
        if (pack.id == supertonic.id) legacySupertonicDir,
      ]) {
        final dir = Directory(await ModelStorage.resourcePath(folder));
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    }
  }

  /// Absolute paths the speech engine needs, or null when not installed.
  /// [preferred] is [InferenceSettings.listeningModel]: Parakeet when
  /// chosen and downloaded (Ultra first, else the v3 files), else Whisper
  /// base, else whichever Parakeet is there.
  static Future<ListeningPaths?> listeningPaths({String preferred = ''}) async {
    Future<String> f(String name) async =>
        (await ModelStorage.modelFile(name)).path;
    Future<ListeningPaths> parakeetPaths(VoicePack pack) async {
      final prefix = pack.id == parakeetUltra.id
          ? 'parakeet-ultra'
          : 'parakeet-v3';
      return ListeningPaths(
        encoder: await f('$prefix-encoder.int8.onnx'),
        decoder: await f('$prefix-decoder.int8.onnx'),
        joiner: await f('$prefix-joiner.int8.onnx'),
        tokens: await f('$prefix-tokens.txt'),
        vad: await f('silero_vad.onnx'),
      );
    }

    final best = parakeetPackFor(
      ultraReady: await isReady(parakeetUltra),
      v3Ready: await isReady(parakeet),
    );
    if (preferred == parakeetSetting && best != null) {
      return parakeetPaths(best);
    }
    if (await isReady(listening)) {
      return ListeningPaths(
        encoder: await f('whisper-base-encoder.int8.onnx'),
        decoder: await f('whisper-base-decoder.int8.onnx'),
        tokens: await f('whisper-base-tokens.txt'),
        vad: await f('silero_vad.onnx'),
      );
    }
    if (best != null) return parakeetPaths(best);
    return null;
  }

  /// Which Parakeet files recognition uses: Ultra once it is downloaded,
  /// else the v3 files a user already has.
  static VoicePack? parakeetPackFor({
    required bool ultraReady,
    required bool v3Ready,
  }) {
    if (ultraReady) return parakeetUltra;
    if (v3Ready) return parakeet;
    return null;
  }

  /// The streaming captions model's files, or null when it is not
  /// unpacked: captions then keep the listening model's.
  static Future<LiveCaptionPaths?> liveCaptionPaths() async {
    if (!await isReady(liveCaptions)) return null;
    final dir = await ModelStorage.resourcePath(liveCaptions.unpackTo!);
    return LiveCaptionPaths(
      encoder: p.join(dir, 'encoder.int8.onnx'),
      decoder: p.join(dir, 'decoder.int8.onnx'),
      joiner: p.join(dir, 'joiner.int8.onnx'),
      tokens: p.join(dir, 'tokens.txt'),
    );
  }

  static Future<SpeakingPaths?> speakingPaths({
    String preferred = 'kokoro',
  }) async {
    if (speakingPack(preferred) == supertonic) {
      var dir = await ModelStorage.resourcePath(supertonic.unpackTo!);
      if (!File(p.join(dir, readyMarker)).existsSync()) {
        dir = await ModelStorage.resourcePath(legacySupertonicDir);
        if (!File(p.join(dir, readyMarker)).existsSync()) return null;
      }
      return SpeakingPaths(
        model: '',
        voices: '',
        tokens: '',
        dataDir: '',
        lexiconUs: '',
        lexiconGb: '',
        supertonicDir: dir,
      );
    }
    if (!await isReady(speaking)) return null;
    var dir = await ModelStorage.resourcePath(speaking.unpackTo!);
    var model = 'model.onnx';
    if (!File(p.join(dir, readyMarker)).existsSync()) {
      dir = await ModelStorage.resourcePath(legacySpeakingDir);
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

/// The streaming captions model's own files (Nemotron, a transducer).
class LiveCaptionPaths {
  final String encoder, decoder, joiner, tokens;
  const LiveCaptionPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });
}

class SpeakingPaths {
  final String? supertonicDir;
  final String model, voices, tokens, dataDir, lexiconUs, lexiconGb;
  const SpeakingPaths({
    required this.model,
    required this.voices,
    required this.tokens,
    required this.dataDir,
    required this.lexiconUs,
    required this.lexiconGb,
    this.supertonicDir,
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
