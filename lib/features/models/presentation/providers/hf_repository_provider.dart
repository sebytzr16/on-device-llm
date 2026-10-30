import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/network/hugging_face.dart';

class HfRepository {
  const HfRepository();

  Future<List<HfRepo>> search(String query) => HuggingFace.search(query);
  Future<HfRepoFiles> files(String repo) => HuggingFace.files(repo);
}

final hfRepositoryProvider = Provider<HfRepository>(
  (ref) => const HfRepository(),
);
