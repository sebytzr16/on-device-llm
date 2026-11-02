import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../features/models/domain/entities/model_info.dart';
import '../storage/gguf_split.dart';

/// A GGUF repository as the Hub search lists it (FX-12).
class HfRepo {
  final String id;
  final int downloads, likes;
  final DateTime? lastModified;
  final List<String> tags;
  const HfRepo({
    required this.id,
    required this.downloads,
    required this.likes,
    this.lastModified,
    this.tags = const [],
  });
}

/// One downloadable GGUF file in a repository, with the Hub's LFS digest so
/// the download can be verified like the bundled catalog.
class HfFile {
  final String name, sha256;
  final int size;
  const HfFile({required this.name, required this.size, required this.sha256});

  ModelQuantization get quantization => ModelQuantization.of(name);

  bool get isProjector => name.toLowerCase().contains('mmproj');
  bool get isSplit => GgufSplit.parse(name) != null;
  String get displayName => GgufSplit.parse(name)?.displayName ?? name;
}

/// A repository's revision pin and its GGUF files.
class HfRepoFiles {
  final String repo, revision, license;
  final List<HfFile> files;
  final List<String> tags;
  final int? contextLength;
  final num? parameterCount;
  const HfRepoFiles({
    required this.repo,
    required this.revision,
    required this.license,
    required this.files,
    this.tags = const [],
    this.contextLength,
    this.parameterCount,
  });

  /// One choice per complete set. Incomplete sets cannot be loaded.
  List<HfFile> get models => files.where((f) {
    if (f.isProjector) return false;
    final split = GgufSplit.parse(f.name);
    return split == null ||
        (split.index == 1 &&
            split.names.every((name) => files.any((f) => f.name == name)));
  }).toList()..sort((a, b) => totalSize(a).compareTo(totalSize(b)));

  List<HfFile> partsFor(HfFile file) {
    final split = GgufSplit.parse(file.name);
    if (split == null) return [file];
    return [
      for (final name in split.names)
        files.where((f) => f.name == name).firstOrNull ??
            (throw FormatException('Missing split GGUF part: $name.')),
    ];
  }

  int totalSize(HfFile file) =>
      partsFor(file).fold(0, (sum, f) => sum + f.size);
}

class HuggingFace {
  static Dio _dio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  /// GGUF repositories matching [query], most downloaded first.
  static Future<List<HfRepo>> search(String query, {int limit = 25}) async {
    final dio = _dio();
    try {
      final res = await dio.get<List<dynamic>>(
        'https://huggingface.co/api/models',
        queryParameters: {
          'search': query.trim(),
          'filter': 'gguf',
          'sort': 'downloads',
          'direction': -1,
          'limit': limit,
          'full': true,
        },
      );
      return [
        for (final m in res.data ?? const [])
          if (m is Map && m['id'] is String && m['private'] != true)
            HfRepo(
              id: m['id'] as String,
              tags: (m['tags'] as List? ?? const [])
                  .whereType<String>()
                  .toList(),
              downloads: (m['downloads'] as num?)?.toInt() ?? 0,
              likes: (m['likes'] as num?)?.toInt() ?? 0,
              lastModified: DateTime.tryParse(
                m['lastModified'] as String? ?? '',
              ),
            ),
      ];
    } on DioException catch (e) {
      throw FormatException(
        'Hugging Face search failed (${e.response?.statusCode ?? 'network error'}).',
      );
    } finally {
      dio.close();
    }
  }

  /// Hub `siblings` contains every file, including nested repository paths.
  /// Gated repositories fail with a clear message.
  /// [revision] (a branch, tag or commit) reads that version instead of
  /// the default branch.
  static Future<HfRepoFiles> files(
    String repo, {
    String? revision,
    Dio? client,
  }) async {
    final dio = client ?? _dio();
    try {
      final at = revision == null || revision == 'main'
          ? ''
          : '/revision/${Uri.encodeComponent(revision)}';
      final res = await dio.get<Map<String, dynamic>>(
        'https://huggingface.co/api/models/$repo$at',
        queryParameters: {'blobs': true},
      );
      final data = res.data!;
      if (data['gated'] != null && data['gated'] != false) {
        throw const FormatException(
          'This model is gated: accept its terms on huggingface.co, download in your browser and use Import.',
        );
      }
      final files = <HfFile>[];
      for (final e in (data['siblings'] as List? ?? const [])) {
        if (e is! Map) continue;
        final name = e['rfilename'] as String? ?? '';
        if (!name.toLowerCase().endsWith('.gguf')) continue;
        final lfs = e['lfs'] as Map?;
        final hash = lfs?['sha256'] as String?, size = lfs?['size'] as int?;
        if (hash == null || size == null) continue;
        files.add(HfFile(name: name, size: size, sha256: hash));
      }
      files.sort((a, b) => a.size.compareTo(b.size));
      return HfRepoFiles(
        repo: repo,
        revision: data['sha'] as String,
        license:
            '${(data['cardData'] as Map?)?['license'] ?? 'See publisher model card'}',
        files: files,
        tags: (data['tags'] as List? ?? const []).whereType<String>().toList(),
        contextLength:
            ((data['config'] as Map?)?['max_position_embeddings'] as num?)
                ?.toInt(),
        parameterCount: ((data['safetensors'] as Map?)?['total'] as num?),
      );
    } on DioException catch (e) {
      throw FormatException(
        'Cannot read this repository (${e.response?.statusCode ?? 'network error'}).',
      );
    } finally {
      if (client == null) dio.close();
    }
  }

  static String stripFrontMatter(String text) {
    final normalized = text.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return normalized;
    final end = RegExp(
      r'^---\s*$',
      multiLine: true,
    ).firstMatch(normalized.substring(4));
    return end == null
        ? normalized
        : normalized.substring(4 + end.end).trimLeft();
  }

  /// Only the selected repository's pinned card, through the download client.
  static Future<String> readme(
    String repo,
    String revision, {
    Dio? client,
  }) async {
    final dio = client ?? _dio();
    try {
      final response = await dio.get<String>(
        Uri(
          scheme: 'https',
          host: 'huggingface.co',
          pathSegments: [...repo.split('/'), 'resolve', revision, 'README.md'],
        ).toString(),
        options: Options(responseType: ResponseType.plain),
      );
      final text = response.data ?? '';
      return stripFrontMatter(
        text.length > 500000 ? text.substring(0, 500000) : text,
      );
    } finally {
      if (client == null) dio.close();
    }
  }

  /// The sampling a model's makers ship in `generation_config.json`,
  /// looked up next to a download (request 2026-10-04). GGUF
  /// repositories rarely carry one, so the repository they were converted
  /// from (`base_model` in the card) is tried too, at most [hops] deep.
  /// Null when none is found; never throws.
  static Future<Map<String, dynamic>?> generationConfig(
    String repo, {
    int hops = 2,
  }) async {
    final dio = _dio();
    try {
      var current = repo;
      final seen = <String>{};
      for (var i = 0; i <= hops && seen.add(current); i++) {
        try {
          final res = await dio.get<dynamic>(
            'https://huggingface.co/$current/resolve/main/generation_config.json',
            options: Options(responseType: ResponseType.json),
          );
          final data = res.data is String
              ? jsonDecode(res.data as String)
              : res.data;
          if (data is Map) return Map<String, dynamic>.from(data);
        } on DioException {
          // Missing here: try the repository it came from.
        }
        if (i == hops) break;
        final card = await dio.get<Map<String, dynamic>>(
          'https://huggingface.co/api/models/$current',
        );
        final base = (card.data?['cardData'] as Map?)?['base_model'];
        final next = base is String
            ? base
            : base is List && base.isNotEmpty && base.first is String
            ? base.first as String
            : null;
        if (next == null || !RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(next)) {
          break;
        }
        current = next;
      }
    } catch (_) {
      // Recommendations are a convenience; a failure leaves the built-in
      // table and the file's own values.
    } finally {
      dio.close();
    }
    return null;
  }

  /// Family for the template fallback, guessed from the repository name.
  static ModelFamily guessFamily(String repo) {
    final r = repo.toLowerCase();
    // A distill speaks its teacher's prompt (DeepSeek-R1-Distill-Qwen), and
    // "phi" must start a word ("dolphin-mistral" is Mistral).
    if (r.contains('deepseek')) return ModelFamily.deepseek;
    if (r.contains('qwen')) return ModelFamily.qwen;
    if (r.contains('gemma')) return ModelFamily.gemma;
    if (r.contains('llama')) return ModelFamily.llama;
    if (r.contains('mistral') || r.contains('mixtral')) {
      return ModelFamily.mistral;
    }
    if (RegExp(r'(^|[^a-z])phi').hasMatch(r)) return ModelFamily.phi;
    return ModelFamily.other;
  }

  /// Prefer the projector that belongs to [model] (same folder, most shared
  /// name words) when a repository holds several (audit P2-42), then half
  /// precision, then the smallest verified single file.
  static HfFile? selectProjector(Iterable<HfFile> files, {HfFile? model}) {
    final candidates = files.where((f) => f.isProjector && !f.isSplit).toList();
    String folder(HfFile f) => f.name.contains('/')
        ? f.name.substring(0, f.name.lastIndexOf('/'))
        : '';
    Set<String> words(HfFile f) => f.name
        .split('/')
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'\.gguf$'), '')
        .split(RegExp(r'[-_.\s]+'))
        .where(
          (w) =>
              w.isNotEmpty &&
              w != 'mmproj' &&
              w != 'model' &&
              !RegExp(r'^(i?q\d\w*|b?f\d+|fp\d+|[ksml]|xs|xxs)$').hasMatch(w),
        )
        .toSet();
    final modelWords = model == null ? const <String>{} : words(model);
    int fit(HfFile f) => model == null
        ? 0
        : (folder(f) == folder(model) ? 1000 : 0) +
              words(f).intersection(modelWords).length;
    int rank(HfFile f) {
      final name = f.name.toUpperCase();
      if (RegExp(r'(^|[^A-Z0-9])(F16|FP16)([^A-Z0-9]|$)').hasMatch(name)) {
        return 0;
      }
      if (name.contains('BF16')) return 1;
      return 2;
    }

    candidates.sort((a, b) {
      final match = fit(b).compareTo(fit(a));
      if (match != 0) return match;
      final order = rank(a).compareTo(rank(b));
      return order == 0 ? a.size.compareTo(b.size) : order;
    });
    return candidates.firstOrNull;
  }

  /// A catalog entry for [selected] at the repository's pinned revision.
  static ModelInfo modelFor(
    HfRepoFiles repo,
    HfFile selected,
    ModelFamily family, {
    bool includeProjector = true,
  }) {
    final files = repo.partsFor(selected);
    final file = files.first;
    final id = sha256
        .convert(utf8.encode('${repo.repo}/${file.name}/${file.sha256}'))
        .toString()
        .substring(0, 16);
    final base = file.name.split('/').last;
    String url(HfFile f) => Uri(
      scheme: 'https',
      host: 'huggingface.co',
      pathSegments: [
        ...repo.repo.split('/'),
        'resolve',
        repo.revision,
        ...f.name.split('/'),
      ],
    ).toString();
    final projectorFile = includeProjector && !file.isProjector
        ? selectProjector(repo.files, model: file)
        : null;
    final projector = projectorFile == null
        ? null
        : modelFor(repo, projectorFile, family, includeProjector: false);
    return ModelInfo(
      parts: file.isSplit
          ? [
              for (final f in files)
                ModelDownloadPart(
                  fileName: '$id-${f.name.split('/').last}',
                  downloadUrl: url(f),
                  sha256: f.sha256,
                  sizeBytes: f.size,
                ),
            ]
          : const [],
      projector: projector == null
          ? null
          : VisionProjector(
              fileName: projector.fileName,
              downloadUrl: projector.downloadUrl!,
              sha256: projector.sha256!,
              sizeBytes: projector.sizeBytes,
            ),
      id: 'hf-$id',
      displayName: ModelQuantization.tidyName(file.displayName),
      fileName: '$id-$base',
      sizeBytes: repo.totalSize(file),
      family: family,
      quantization: file.quantization,
      sha256: file.sha256,
      license: repo.license,
      downloadUrl: url(file),
    );
  }

  /// A pasted file link (Files and versions → a .gguf) as a catalog entry.
  /// The link's revision is kept: a `/resolve/v2/…` link no longer loads
  /// `main` (audit P2-41).
  static Future<ModelInfo> resolve(
    String input,
    ModelFamily family, {
    Dio? client,
  }) async {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'huggingface.co' ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Paste an https://huggingface.co file link.');
    }
    final parts = uri.pathSegments;
    if (parts.length < 5 ||
        !['blob', 'resolve'].contains(parts[2]) ||
        !parts.last.toLowerCase().endsWith('.gguf')) {
      throw const FormatException(
        'Open a GGUF file under Files and versions, then paste its link.',
      );
    }
    final repo = await files(
      '${parts[0]}/${parts[1]}',
      revision: parts[3],
      client: client,
    );
    final name = parts.skip(4).join('/');
    final file = repo.files.where((f) => f.name == name).firstOrNull;
    if (file == null) {
      throw const FormatException(
        'No verified GGUF metadata found. For gated models, download in your browser and use Import.',
      );
    }
    return modelFor(repo, file, family);
  }
}
