import '../../features/settings/domain/entities/inference_settings.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/network/web_search/duckduckgo_scraper.dart';
import '../../data/network/web_search/wikipedia_client.dart';
import '../../data/network/web_search/instant_answers.dart';
import '../../data/network/web_search/web_page_reader.dart';
import '../../features/attachments/data/attachment_store.dart';
import '../../features/retrieval/news_desk.dart';
import '../../features/zim/zim_wikipedia.dart';
import '../../inference/engine/llama_engine.dart';
import '../../inference/engine/diffusiongemma_engine.dart';
import '../../inference/remote/remote_engine.dart';
import '../platform/device_info.dart';

final sessionBusyProvider = StateProvider<bool>((ref) => false);

final diffusionGemmaEngineProvider = Provider<DiffusionGemmaEngine>((ref) {
  final engine = DiffusionGemmaEngine();
  ref.onDispose(engine.close);
  return engine;
});

/// Neutral home for cross-feature singletons so that ModelManager and Chat
/// can both reach them without a circular import.
final llamaEngineProvider = Provider<LlamaEngine>((ref) {
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    owner: NativeOwner.id,
    onLibrary: (library) => unawaited(NativeOwner.report(library)),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Memory estimates (load settings, Discover fit badges) on their own
/// isolate: a GGUF header read and a fit pass can take seconds, and on the
/// chat engine they made Load wait for them.
final llamaEstimatorProvider = Provider<LlamaEngine>((ref) {
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Detected hardware info from the native probe: CPU name, cores, RAM, GPU(s),
/// VRAM, and backend. Used on the desktop Hardware settings page.
final detectedHardwareProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  try {
    // An estimate without a model path reports every backend device with
    // its memory, plus installed and free RAM; nothing is loaded.
    return await ref
        .read(llamaEstimatorProvider)
        .estimate(modelPath: '', settings: const InferenceSettings());
  } catch (_) {
    return null;
  }
});

/// A second native runtime for the knowledge library's embedding model
/// (FX-02): its own isolate, so indexing and query embedding never touch
/// the chat model's context.
final embeddingEngineProvider = Provider<LlamaEngine>((ref) {
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    owner: NativeOwner.id,
    onLibrary: (library) => unawaited(NativeOwner.report(library)),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// A third runtime for the optional source-check model (a reranker): its
/// own isolate, loaded after an answer and released when idle.
final supportEngineProvider = Provider<LlamaEngine>((ref) {
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    owner: NativeOwner.id,
    onLibrary: (library) => unawaited(NativeOwner.report(library)),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

LlamaEngine createHelperEngine() => LlamaEngine(
  cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
  owner: NativeOwner.id,
  onLibrary: (library) => unawaited(NativeOwner.report(library)),
);

/// Side jobs keep their own context without replacing the chat model.
final helperEngineProvider = Provider<LlamaEngine>((ref) {
  final engine = createHelperEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The local server's own runtime (desktop): the server shares the chat's
/// runtime until the chat loads another model, then its model moves here so
/// both stay loaded.
final serverEngineProvider = Provider<LlamaEngine>((ref) {
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    owner: NativeOwner.id,
    onLibrary: (library) => unawaited(NativeOwner.report(library)),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Makes a fresh runtime for each extra model the desktop server holds
/// (and the comparison's second model); the caller disposes it.
final engineFactoryProvider = Provider<LlamaEngine Function()>(
  (ref) =>
      () => LlamaEngine(
        cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
        owner: NativeOwner.id,
        onLibrary: (library) => unawaited(NativeOwner.report(library)),
      ),
);

/// Set while the desktop's local server runs: called with the model about
/// to replace the chat's, it keeps the server's models loaded (moving the
/// served one to [serverEngineProvider], or back when the chat loads it).
/// Null when nothing needs moving.
final engineHandoffProvider =
    StateProvider<Future<void> Function(String nextModelId)?>((ref) => null);

/// OpenAI-compatible client for the user's own server (Settings > Remote
/// server). Idle unless that setting is on.
final remoteEngineProvider = Provider<RemoteEngine>((ref) {
  final engine = RemoteEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Background extraction has its own cancellable client and shares the main
/// client's usage log. Keeping creation injectable also tests the full remote
/// memory path without contacting a hosted provider.
final remoteMemoryEngineFactoryProvider = Provider<RemoteEngine Function()>(
  (ref) =>
      () => RemoteEngine(usage: ref.read(remoteEngineProvider).usage),
);

/// Each helper owns cancellation and metrics while sharing chat usage logging.
final remoteHelperEngineFactoryProvider = Provider<RemoteEngine Function()>(
  (ref) =>
      () => RemoteEngine(usage: ref.read(remoteEngineProvider).usage),
);

final duckDuckGoScraperProvider = Provider<DuckDuckGoScraper>((ref) {
  final scraper = DuckDuckGoScraper();
  ref.onDispose(scraper.dispose);
  return scraper;
});

/// Wikipedia's article on a searched question's subject (Settings > Web
/// search > Wikipedia).
final wikipediaClientProvider = Provider<WikipediaClient>((ref) {
  final client = WikipediaClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Offline Wikipedia: the ZIM file imported in Settings > Web search, or
/// null. Invalidate after an import or a removal.
final zimWikipediaProvider = FutureProvider<ZimWikipedia?>((ref) async {
  final path = ZimWikipedia.fileIn(
    (await getApplicationSupportDirectory()).path,
  );
  if (!await ZimWikipedia.isZim(path)) return null;
  final zim = ZimWikipedia(path);
  ref.onDispose(zim.close);
  return zim;
});

/// Keyless structured answers from DuckDuckGo (weather) — the fast path
/// for questions that page reads answer slowly and badly.
final instantAnswersProvider = Provider<InstantAnswers>((ref) {
  final answers = InstantAnswers();
  ref.onDispose(answers.dispose);
  return answers;
});

final webPageReaderProvider = Provider<WebPageReader>(
  // Pages are kept in memory only (30 min fresh, 12 h for follow-ups): a
  // persistent copy in SQLite crashed release builds (2026-09-20) and was
  // removed.
  (ref) => WebPageReader(pdfText: AttachmentStore.pdfText),
);

/// News briefings: DuckDuckGo's news listing plus publisher feeds, merged
/// and ranked (see NewsDesk). Shares the scraper's pacing and the reader's
/// policy and memory.
final newsDeskProvider = Provider<NewsDesk>(
  (ref) => NewsDesk(
    scraper: ref.watch(duckDuckGoScraperProvider),
    reader: ref.watch(webPageReaderProvider),
  ),
);
