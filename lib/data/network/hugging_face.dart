import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../features/models/domain/entities/model_info.dart';

/// A GGUF repository as the Hub search lists it (FX-12).
class HfRepo {
  final String id;
  final int downloads, likes;
  final DateTime? lastModified;
  const HfRepo({
    required this.id,
    required this.downloads,
    required this.likes,
    this.lastModified,
  });
}

/// One downloadable GGUF file in a repository, with the Hub's LFS digest so
/// the download can be verified like the bundled catalog.
class HfFile {
  final String name, sha256;
  final int size;
  const HfFile({required this.name, required this.size, required this.sha256});

  ModelQuantization get quantization {
    final lower = name.toLowerCase();
    return ModelQuantization.values
            .where((q) => lower.contains(q.name))
            .firstOrNull ??
        (lower.contains('f16') || lower.contains('bf16')
            ? ModelQuantization.fp16
            : ModelQuantization.q4_k_m);
  }

  bool get isProjector => name.toLowerCase().contains('mmproj');
  bool get isSplit => RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(name);
}

/// A repository's revision pin and its GGUF files.
class HfRepoFiles {
  final String repo, revision, license;
  final List<HfFile> files;
  const HfRepoFiles({
    required this.repo,
    required this.revision,
    required this.license,
    required this.files,
  });
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
        },
      );
      return [
        for (final m in res.data ?? const [])
          if (m is Map && m['id'] is String && m['private'] != true)
            HfRepo(
              id: m['id'] as String,
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

  /// The GGUF files of [repo] at its current revision, projectors and split
  /// files listed but flagged. Gated repositories fail with a clear message.
  static Future<HfRepoFiles> files(String repo) async {
    final dio = _dio();
    try {
      final res = await dio.get<Map<String, dynamic>>(
        'https://huggingface.co/api/models/$repo',
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
      );
    } on DioException catch (e) {
      throw FormatException(
        'Cannot read this repository (${e.response?.statusCode ?? 'network error'}).',
      );
    } finally {
      dio.close();
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
    if (r.contains('qwen')) return ModelFamily.qwen;
    if (r.contains('gemma')) return ModelFamily.gemma;
    if (r.contains('llama')) return ModelFamily.llama;
    if (r.contains('phi')) return ModelFamily.phi;
    if (r.contains('mistral') || r.contains('mixtral')) {
      return ModelFamily.mistral;
    }
    if (r.contains('deepseek')) return ModelFamily.deepseek;
    return ModelFamily.other;
  }

  /// A catalog entry for [file] of [repo], pinned to [revision].
  static ModelInfo modelFor(HfRepoFiles repo, HfFile file, ModelFamily family) {
    final id = sha256
        .convert(utf8.encode('${repo.repo}/${file.name}/${file.sha256}'))
        .toString()
        .substring(0, 16);
    final base = file.name.split('/').last;
    return ModelInfo(
      id: 'hf-$id',
      displayName: base.replaceAll('.gguf', ''),
      fileName: '$id-$base',
      sizeBytes: file.size,
      family: family,
      quantization: file.quantization,
      sha256: file.sha256,
      license: repo.license,
      downloadUrl: Uri(
        scheme: 'https',
        host: 'huggingface.co',
        pathSegments: [
          ...repo.repo.split('/'),
          'resolve',
          repo.revision,
          ...file.name.split('/'),
        ],
      ).toString(),
    );
  }

  /// A pasted file link (Files and versions → a .gguf) as a catalog entry.
  static Future<ModelInfo> resolve(String input, ModelFamily family) async {
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
    if (RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(parts.last)) {
      throw const FormatException(
        'Split GGUF downloads are not yet supported. Choose a single-file model.',
      );
    }
    final repo = await files('${parts[0]}/${parts[1]}');
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
