/// The multimodal projector (mmproj) that lets a model see photos
/// through llama.cpp's libmtmd. Same publisher revision as the weights.
class VisionProjector {
  final String fileName, downloadUrl, sha256;
  final int sizeBytes;
  const VisionProjector({
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
  });
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
  factory VisionProjector.fromJson(Map<String, dynamic> json) =>
      VisionProjector(
        fileName: json['fileName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        sha256: json['sha256'] as String,
        sizeBytes: json['sizeBytes'] as int,
      );
}

// GGUF names are persisted verbatim.
// ignore_for_file: constant_identifier_names
enum ModelFamily { gemma, qwen, deepseek, phi, llama, mistral, other }

extension ModelFamilyTemplate on ModelFamily {
  /// The chat template used when a GGUF ships none. Remote turns are
  /// rendered by the server and ignore it.
  String get fallbackTemplate => switch (this) {
    ModelFamily.llama => 'llama3',
    ModelFamily.gemma => 'gemma',
    ModelFamily.qwen => 'chatml',
    ModelFamily.phi => 'phi3',
    ModelFamily.mistral => 'mistral-v3',
    ModelFamily.deepseek || ModelFamily.other => '',
  };
}

enum ModelQuantization {
  unknown,
  q2_k,
  q3_k_m,
  q4_0,

  /// Non-linear 4-bit: about Q4_K_M quality at Q4_0 bytes, and the 4-bit
  /// format both the OpenCL and Hexagon backends accept natively.
  iq4_nl,
  q4_k_m,
  q5_k_m,
  q6_k,
  q8_0,
  fp16,

  /// llama.cpp's 2-bit type; Prism ML publishes Bonsai 2 in it. Runs on
  /// CUDA and Vulkan with no patch.
  q2_0,

  /// Prism ML ternary, dense trit packing (~1.75 bpw). Requires the
  /// ternary runtime patch in native/patches/bonsai-ternary.patch.
  ptq1_0,

  /// Prism ML ternary, 2-bit slot storage (~2.13 bpw). Faster prompt
  /// processing than PTQ1_0 at a ~1.3 GB size penalty.
  pq2_0;

  static final _tag = RegExp(
    r'(?:^|[^A-Z0-9])((?:IQ|Q|PTQ|PQ)\d(?:_[A-Z0-9]+)*|BF16|FP16|F16|F32|MXFP4)(?=[^A-Z0-9]|$)',
  );

  /// The quant as the publisher names it in a GGUF file name: Q8_K_P,
  /// Q4_K_XL (from UD-Q4_K_XL), IQ3_XS, BF16. Null when the name has none.
  static String? tagOf(String fileName) {
    final base = fileName.split(RegExp(r'[/\\]')).last.toUpperCase();
    final stem = base.endsWith('.GGUF')
        ? base.substring(0, base.length - 5)
        : base;
    // The last match: a stem like "Qwen3-4B-Q8_0" names the quant last.
    return _tag.allMatches(stem).lastOrNull?.group(1);
  }

  /// A readable model name from a GGUF file name: the trailing quant tag
  /// (and Unsloth's "UD" before it) goes, since rows show the quant on
  /// their own, and dashes become spaces.
  /// "Gemma-4-E4B-Uncensored-Q8_K_P.gguf" → "Gemma 4 E4B Uncensored".
  static String tidyName(String fileName) {
    var stem = fileName.split(RegExp(r'[/\\]')).last;
    if (stem.toLowerCase().endsWith('.gguf')) {
      stem = stem.substring(0, stem.length - 5);
    }
    final tag = tagOf(stem);
    if (tag != null && stem.toUpperCase().endsWith(tag)) {
      stem = stem
          .substring(0, stem.length - tag.length)
          .replaceAll(RegExp(r'[-_.]?UD[-_.]?$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[-_.]+$'), '');
    }
    final name = stem.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    return name.isEmpty ? fileName : name;
  }

  /// The nearest member for [fileName]'s quant, by bits per weight, so
  /// names outside the enum (Q8_K_P, Q4_K_S, Q5_K_XL) are not mistaken for
  /// Q4_K_M.
  static ModelQuantization of(String fileName) {
    final tag = tagOf(fileName);
    if (tag == null) return unknown;
    if (tag == 'BF16' || tag == 'FP16' || tag == 'F16' || tag == 'F32') {
      return fp16;
    }
    if (tag == 'MXFP4') return q4_k_m;
    if (tag == 'PTQ1_0') return ptq1_0;
    if (tag == 'PQ2_0') return pq2_0;
    if (tag == 'Q2_0') return q2_0;
    final bits = int.parse(RegExp(r'\d').firstMatch(tag)!.group(0)!);
    return switch (bits) {
      <= 2 => q2_k,
      3 => q3_k_m,
      4 when tag == 'Q4_0' => q4_0,
      4 when tag.startsWith('IQ4') => iq4_nl,
      4 => q4_k_m,
      5 => q5_k_m,
      6 || 7 => q6_k,
      _ => q8_0,
    };
  }
}

/// One independently verified file of a split model, in loader order.
class ModelDownloadPart {
  final String fileName, downloadUrl, sha256;
  final int sizeBytes;
  const ModelDownloadPart({
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  factory ModelDownloadPart.fromJson(Map<String, dynamic> json) =>
      ModelDownloadPart(
        fileName: json['fileName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        sha256: json['sha256'] as String,
        sizeBytes: json['sizeBytes'] as int,
      );
}

class ModelInfo {
  final List<ModelDownloadPart> parts;
  final VisionProjector? projector;
  final String id;
  final String displayName;
  final String fileName;
  final String? downloadUrl;
  final String? sha256;
  final String license;
  final int sizeBytes;
  final int? parameterCountB;
  final ModelFamily family;
  final ModelQuantization quantization;
  final bool isDownloaded;
  final String? localPath;
  final DateTime? downloadedAt;

  const ModelInfo({
    this.parts = const [],
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.sizeBytes,
    required this.family,
    required this.quantization,
    this.projector,
    this.downloadUrl,
    this.sha256,
    this.license = 'See publisher model card',
    this.parameterCountB,
    this.isDownloaded = false,
    this.localPath,
    this.downloadedAt,
  });

  /// The quant to show: the file name's own tag (Q8_K_P, Q4_K_XL), else
  /// the member, else "GGUF".
  String get quantLabel =>
      ModelQuantization.tagOf(fileName) ??
      (quantization == ModelQuantization.unknown
          ? 'GGUF'
          : quantization.name.toUpperCase());

  String get sizeLabel {
    final gb = sizeBytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  ModelInfo copyWith({
    VisionProjector? projector,
    bool clearProjector = false,
    bool? isDownloaded,
    String? localPath,
    DateTime? downloadedAt,
  }) => ModelInfo(
    parts: parts,
    projector: clearProjector ? null : projector ?? this.projector,
    id: id,
    displayName: displayName,
    fileName: fileName,
    downloadUrl: downloadUrl,
    sha256: sha256,
    license: license,
    sizeBytes: sizeBytes,
    parameterCountB: parameterCountB,
    family: family,
    quantization: quantization,
    isDownloaded: isDownloaded ?? this.isDownloaded,
    localPath: localPath ?? this.localPath,
    downloadedAt: downloadedAt ?? this.downloadedAt,
  );
}
