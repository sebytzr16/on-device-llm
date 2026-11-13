import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/network/hugging_face.dart';

class HfRepository {
  const HfRepository();

  Future<List<HfRepo>> search(String query) => HuggingFace.search(query);
  Future<List<HfRepo>> searchImageGeneration(
    String query, {
    required HfImagePipeline pipeline,
  }) => HuggingFace.searchImageGeneration(query, pipeline: pipeline);
  Future<HfRepoFiles> imageGenerationFiles(String repo) =>
      HuggingFace.files(repo, extensions: hfImageGenerationExtensions);
  Future<String> readme(String repo, String revision) =>
      HuggingFace.readme(repo, revision);
  Future<HfRepoFiles> files(String repo) => HuggingFace.files(repo);
}

final hfRepositoryProvider = Provider<HfRepository>(
  (ref) => const HfRepository(),
);

final hfReadmeProvider = FutureProvider.family<String, (String, String)>((
  ref,
  key,
) {
  return ref.watch(hfRepositoryProvider).readme(key.$1, key.$2);
});
