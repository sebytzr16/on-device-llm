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
}

class ModelInfo {
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
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.sizeBytes,
    required this.family,
    required this.quantization,
    this.downloadUrl,
    this.sha256,
    this.license = 'See publisher model card',
    this.parameterCountB,
    this.isDownloaded = false,
    this.localPath,
    this.downloadedAt,
  });

  String get sizeLabel {
    final gb = sizeBytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  ModelInfo copyWith({
    bool? isDownloaded,
    String? localPath,
    DateTime? downloadedAt,
  }) => ModelInfo(
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
