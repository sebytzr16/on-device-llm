import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/network/hugging_face.dart';
import 'domain/entities/image_gen_model.dart';

/// Where an imported model is picked in Create.
enum ImageGenMode {
  image,
  video,
  upscale;

  /// A single-file ESRGAN checkpoint upscales; a video model makes video;
  /// everything else makes pictures.
  static ImageGenMode of(ImageGenModel model) =>
      model.files.length == 1 &&
          model.files.single.role == ImageGenRole.upscaler
      ? ImageGenMode.upscale
      : model.kind == ImageGenKind.video
      ? ImageGenMode.video
      : ImageGenMode.image;
}

/// The file kinds stable-diffusion.cpp loads for an imported model.
const imageGenImportExtensions = hfImageGenerationExtensions;

bool isSupportedImageGenFile(String name) {
  final lower = name.toLowerCase();
  return imageGenImportExtensions.any(lower.endsWith);
}

/// A model built from one Hugging Face file. The built-in catalog stays
/// untouched: imported models live in preferences and are appended to it.
ImageGenModel importedImageGenModel({
  required String repo,
  required String revision,
  required HfFile file,
  required String license,
  required ImageGenMode mode,
}) {
  if (!isSupportedImageGenFile(file.name)) {
    throw const FormatException(
      'This is not a GGUF or safetensors file that stable-diffusion.cpp can load.',
    );
  }
  final base = file.name.split('/').last;
  final digest = sha256
      .convert(utf8.encode('$repo/${file.name}/${file.sha256}'))
      .toString();
  final short = digest.substring(0, 16);
  final url = HuggingFace.fileUrl(repo, revision, file.name);
  final video = mode == ImageGenMode.video;
  final upscale = mode == ImageGenMode.upscale;
  return ImageGenModel(
    id: 'imported:$short',
    displayName: base.replaceFirst(
      RegExp(r'\.(gguf|safetensors)$', caseSensitive: false),
      '',
    ),
    blurb: '$repo · ${file.name}',
    license: license,
    kind: video ? ImageGenKind.video : ImageGenKind.image,
    files: [
      ImageGenComponent(
        role: upscale ? ImageGenRole.upscaler : ImageGenRole.diffusion,
        fileName: 'hf-$short-$base',
        url: url,
        sha256: file.sha256,
        sizeBytes: file.size,
      ),
    ],
    width: upscale
        ? 0
        : video
        ? 832
        : 1024,
    height: upscale
        ? 0
        : video
        ? 480
        : 1024,
    steps: upscale ? 0 : 20,
    cfgScale: upscale ? 0 : 6,
    frames: video ? 33 : 0,
    fps: video ? 16 : 0,
    sourceRepo: repo,
    sourceRevision: revision,
  );
}

/// Resolve only compatible catalog families; never guess companions for Flux
/// or other architectures absent from our catalog.
ImageGenModel resolveImageGenCompanions(ImageGenModel model) {
  if (!model.imported || model.file(ImageGenRole.diffusion) == null) {
    return model;
  }
  final name = model.files
      .firstWhere((f) => f.role == ImageGenRole.diffusion)
      .fileName
      .toLowerCase()
      .replaceAll('_', '-');
  final family = name.contains('qwen-image-2.1')
      ? imageGenCatalog[0]
      : RegExp(r'wan2\.2.*(ti2v.*5b|5b)').hasMatch(name)
      ? imageGenCatalog[2]
      : name.contains('ltx-2.3')
      ? imageGenCatalog[3]
      : null;
  if (family == null) return model;
  return ImageGenModel(
    id: model.id,
    displayName: model.displayName,
    blurb: model.blurb,
    license: model.license,
    kind: family.kind,
    files: [
      ...model.files,
      ...family.files.where(
        (f) => f.role != ImageGenRole.diffusion && model.file(f.role) == null,
      ),
    ],
    width: family.width,
    height: family.height,
    steps: family.steps,
    cfgScale: family.cfgScale,
    frames: family.frames,
    fps: family.fps,
    flowShift: family.flowShift,
    sampler: family.sampler,
    sigmas: family.sigmas,
    mmap: family.mmap,
    textEncoderOnCpu: family.textEncoderOnCpu,
    sourceRepo: model.sourceRepo,
    sourceRevision: model.sourceRevision,
  );
}

bool imageGenNeedsCompanions(ImageGenModel model) =>
    model.imported &&
    model.file(ImageGenRole.diffusion) != null &&
    (model.file(ImageGenRole.vae) == null ||
        (model.file(ImageGenRole.llm) == null &&
            model.file(ImageGenRole.t5xxl) == null));

ImageGenModel? imageGenModelForDownload(
  String id,
  Iterable<ImageGenModel> imports,
) => imageGenManagedModels(imports)
    .where((m) => id == m.downloadKey || id.startsWith('${m.downloadKey}:'))
    .firstOrNull;

/// The JSON row persisted for an imported model.
Map<String, Object?> imageGenModelJson(ImageGenModel model) => {
  'id': model.id,
  'displayName': model.displayName,
  'blurb': model.blurb,
  'license': model.license,
  'kind': model.kind.name,
  'width': model.width,
  'height': model.height,
  'steps': model.steps,
  'cfgScale': model.cfgScale,
  'frames': model.frames,
  'fps': model.fps,
  'sourceRepo': model.sourceRepo,
  'sourceRevision': model.sourceRevision,
  'files': [
    for (final f in model.files)
      {
        'role': f.role.name,
        'fileName': f.fileName,
        'url': f.url,
        'sha256': f.sha256,
        'sizeBytes': f.sizeBytes,
      },
  ],
};

/// Reads a row written by [imageGenModelJson]. Malformed rows are skipped
/// rather than taking the whole imported list down.
ImageGenModel? imageGenModelFromJson(Object? raw) {
  try {
    if (raw is! Map) return null;
    final json = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) return null;
      json[entry.key as String] = entry.value;
    }
    final id = json['id'], displayName = json['displayName'];
    final filesRaw = json['files'];
    final sourceRepo = json['sourceRepo'];
    if (id is! String ||
        id.isEmpty ||
        displayName is! String ||
        displayName.isEmpty ||
        sourceRepo is! String ||
        sourceRepo.isEmpty ||
        filesRaw is! List ||
        filesRaw.isEmpty) {
      return null;
    }
    final files = <ImageGenComponent>[];
    for (final row in filesRaw) {
      if (row is! Map) return null;
      final role = ImageGenRole.values.asNameMap()[row['role']];
      final fileName = row['fileName'],
          url = row['url'],
          sha256 = row['sha256'];
      final size = row['sizeBytes'];
      final parsed = url is String ? Uri.tryParse(url) : null;
      if (role == null ||
          fileName is! String ||
          fileName.isEmpty ||
          // A stored name stays one file in the models folder.
          fileName.contains('/') ||
          fileName.contains(r'\') ||
          fileName.contains('..') ||
          parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host != 'huggingface.co' ||
          parsed.userInfo.isNotEmpty ||
          !isSupportedImageGenFile(fileName) ||
          sha256 is! String ||
          size is! num ||
          size <= 0) {
        return null;
      }
      files.add(
        ImageGenComponent(
          role: role,
          fileName: fileName,
          url: url as String,
          sha256: sha256,
          sizeBytes: size.toInt(),
        ),
      );
    }
    return ImageGenModel(
      id: id,
      displayName: displayName,
      blurb: json['blurb'] as String? ?? '',
      license: json['license'] as String? ?? '',
      kind: ImageGenKind.values.asNameMap()[json['kind']] ?? ImageGenKind.image,
      files: files,
      width: (json['width'] as num?)?.toInt() ?? 1024,
      height: (json['height'] as num?)?.toInt() ?? 1024,
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      cfgScale: (json['cfgScale'] as num?)?.toDouble() ?? 0,
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      fps: (json['fps'] as num?)?.toInt() ?? 0,
      sourceRepo: sourceRepo,
      sourceRevision: json['sourceRevision'] as String?,
    );
  } on Object {
    // A row from an older or newer build: skip it, keep the other models.
    return null;
  }
}

/// Built-in generators followed by the user's imported ones.
List<ImageGenModel> imageGenSelectableModels(
  Iterable<ImageGenModel> imported,
) => [
  ...imageGenCatalog,
  ...imported
      .map(resolveImageGenCompanions)
      .where((m) => ImageGenMode.of(m) != ImageGenMode.upscale),
];

/// The built-in upscalers followed by imported ones.
List<ImageGenModel> imageGenUpscalerModels(Iterable<ImageGenModel> imported) =>
    [
      ...upscalerTools,
      ...imported.where((m) => ImageGenMode.of(m) == ImageGenMode.upscale),
    ];

/// Every model whose files the download manager owns, built-in or imported.
List<ImageGenModel> imageGenManagedModels(Iterable<ImageGenModel> imported) => [
  ...imageGenCatalog,
  ...imported.map(resolveImageGenCompanions),
  ...upscalerTools,
];

/// The user's own image and video models, stored as a JSON list in
/// preferences so they survive restarts like the built-in catalog.
class ImageGenImportsNotifier extends Notifier<List<ImageGenModel>> {
  static const prefsKey = 'imageGenImportedModels';
  SharedPreferences? _prefs;
  Future<void>? _ready;
  bool _alive = true;

  Future<void> get ready {
    final pending = _ready;
    if (pending != null) return pending;
    return _ready = _load();
  }

  @override
  List<ImageGenModel> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _ready = _load();
    return const [];
  }

  Future<SharedPreferences> _store() async {
    final loaded = _prefs;
    if (loaded != null) return loaded;
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  Future<void> _load() async {
    try {
      final raw = (await _store()).getString(prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final models = <ImageGenModel>[];
      for (final row in decoded) {
        final model = imageGenModelFromJson(row);
        if (model != null) models.add(model);
      }
      if (_alive) state = models;
    } on Exception {
      // Unreadable preferences: the built-in catalog still works.
    }
  }

  Future<void> add(ImageGenModel model) async {
    await ready;
    if (!_alive) return;
    state = [...state.where((m) => m.id != model.id), model];
    await _save();
  }

  Future<void> remove(String id) async {
    await ready;
    if (!_alive) return;
    final models = state.where((m) => m.id != id).toList();
    if (models.length == state.length) return;
    state = models;
    await _save();
  }

  Future<void> _save() async {
    try {
      await (await _store()).setString(
        prefsKey,
        jsonEncode([for (final model in state) imageGenModelJson(model)]),
      );
    } on Exception {
      // Kept in memory for this session.
    }
  }
}

final imageGenImportsProvider =
    NotifierProvider<ImageGenImportsNotifier, List<ImageGenModel>>(
      ImageGenImportsNotifier.new,
    );
