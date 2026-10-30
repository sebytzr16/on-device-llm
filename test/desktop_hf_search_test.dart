import 'dart:async';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/hf_discover.dart';
import 'package:flutter/services.dart';
import 'package:ondevice_llm/desktop/models_page.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/hf_repository_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

final _repo = HfRepo(
  id: 'publisher/Qwen-GGUF',
  downloads: 1853577,
  likes: 1162,
  lastModified: DateTime(2026, 9, 14),
);
final _other = HfRepo(
  id: 'studio/Small-GGUF',
  downloads: 10,
  likes: 8000,
  lastModified: DateTime.now().subtract(const Duration(days: 3)),
);
const _q4 = HfFile(name: 'model-Q4_K_M.gguf', size: 1073741824, sha256: 'abc');
const _q8 = HfFile(name: 'model-Q8_0.gguf', size: 2147483648, sha256: 'def');
const _files = HfRepoFiles(
  repo: 'publisher/Qwen-GGUF',
  revision: 'abcdef123456',
  license: 'apache-2.0',
  files: [
    _q4,
    _q8,
    HfFile(name: 'mmproj-F16.gguf', size: 100, sha256: 'proj'),
    HfFile(name: 'model-Q8_0-00001-of-00002.gguf', size: 100, sha256: 'split'),
  ],
);

class _Repository extends HfRepository {
  final queries = <String>[];
  final opened = <String>[];
  final pending = <String, Completer<List<HfRepo>>>{};
  final pendingFiles = <String, Completer<HfRepoFiles>>{};
  bool fail = false;

  @override
  Future<List<HfRepo>> search(String query) async {
    queries.add(query);
    if (fail) throw StateError('offline');
    return pending[query]?.future ?? [_other, _repo];
  }

  @override
  Future<HfRepoFiles> files(String repo) async {
    opened.add(repo);
    return pendingFiles[repo]?.future ?? _files;
  }
}

class _Models extends ModelManagerNotifier {
  final bool downloaded;
  _Models({this.downloaded = false});
  final saved = <ModelInfo>[];
  final started = <String>[];
  final cancelled = <String>[];

  void removeLocalFiles() => state = state.copyWith(catalog: []);
  @override
  ModelManagerState build() => ModelManagerState(
    vision: downloaded
        ? {HuggingFace.modelFor(_files, _q8, ModelFamily.qwen).id}
        : {},
    catalog: downloaded
        ? [
            HuggingFace.modelFor(
              _files,
              _q8,
              ModelFamily.qwen,
            ).copyWith(isDownloaded: true),
          ]
        : [],
  );

  @override
  Future<void> save(ModelInfo m, {String? localPath}) async {
    saved.add(m);
    state = state.copyWith(catalog: [...state.catalog, m]);
  }

  @override
  Future<void> downloadModel(ModelInfo info) async {
    started.add(info.id);
    state = state.copyWith(
      downloads: {
        ...state.downloads,
        info.id: DownloadProgress(
          modelId: info.id,
          status: DownloadStatus.downloading,
          received: 50,
          total: 100,
        ),
      },
    );
  }

  @override
  Future<void> pauseDownload(String id) async {
    cancelled.add(id);
    state = state.copyWith(
      downloads: {
        ...state.downloads,
        id: DownloadProgress(modelId: id, status: DownloadStatus.paused),
      },
    );
  }
}

Future<void> _host(
  WidgetTester tester,
  _Repository repository,
  _Models models, {
  Map<String, dynamic>? memory = const {
    'devices': [
      {'type': 'gpu', 'freeMb': 1600},
    ],
    'ramAvailableMb': 8192,
  },
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        desktopHfMemoryProvider.overrideWith((ref) async => memory),
        hfRepositoryProvider.overrideWithValue(repository),
        modelManagerProvider.overrideWith(() => models),
      ],
      child: MaterialApp(
        theme: DesktopTheme.of(AccentChoice.amber, dark: true),
        home: const Scaffold(body: DesktopModelsPage()),
      ),
    ),
  );
  await tester.tap(find.text('Discover'));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('desktop-hf-query')), 'qwen');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('debounces search, Enter searches once, results sort locally', (
    tester,
  ) async {
    final repository = _Repository();
    await _host(tester, repository, _Models());
    final query = find.byKey(const Key('desktop-hf-query'));
    await tester.enterText(query, 'q');
    await tester.pump(const Duration(milliseconds: 450));
    expect(repository.queries, isEmpty);
    await tester.enterText(query, 'qw');
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.queries, isEmpty);
    await tester.enterText(query, 'qwen');
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pumpAndSettle();
    expect(repository.queries, ['qwen']);
    expect(find.text('publisher'), findsOneWidget);
    expect(
      find.text(NumberFormat.compact(locale: 'en').format(_repo.downloads)),
      findsOneWidget,
    );
    expect(
      find.text(NumberFormat.compact(locale: 'en').format(_repo.likes)),
      findsOneWidget,
    );
    expect(find.text('Updated Sep 14, 2026'), findsOneWidget);
    expect(find.text('Updated 3 days ago'), findsOneWidget);
    final first = find.byKey(const Key('desktop-hf-repo-publisher/Qwen-GGUF'));
    final second = find.byKey(const Key('desktop-hf-repo-studio/Small-GGUF'));
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    await tester.tap(find.byKey(const Key('desktop-hf-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Likes').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(first).dy));
    await tester.enterText(query, 'llama');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    expect(repository.queries, ['qwen', 'llama']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quant groups show size, projector note, downloaded and progress/cancel',
    (tester) async {
      final repository = _Repository();
      final models = _Models(downloaded: true);
      await _host(tester, repository, models);
      await _search(tester);
      await tester.tap(find.text('Qwen-GGUF'));
      await tester.pumpAndSettle();
      expect(repository.opened, [_repo.id]);
      expect(find.text('Q4_K_M'), findsOneWidget);
      expect(find.text('Q8_0'), findsOneWidget);
      expect(find.text('1.00 GB'), findsOneWidget);
      expect(find.text('2.00 GB'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(
        find.textContaining('Includes vision projector (F16, 0.0 GB)'),
        findsOneWidget,
      );
      expect(
        find.text('Split GGUF files are not supported here.'),
        findsNothing,
      );
      expect(find.text('Fits GPU'), findsOneWidget);
      expect(find.text('Partial GPU'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(models.saved.single.sha256, _q4.sha256);
      expect(models.saved.single.projector?.sha256, 'proj');
      expect(models.started, [models.saved.single.id]);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(models.cancelled, models.started);
      expect(find.text('Download'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nested split weights appear once with the combined size', (
    tester,
  ) async {
    final repository = _Repository();
    final response = Completer<HfRepoFiles>();
    repository.pendingFiles[_repo.id] = response;
    final models = _Models();
    await _host(tester, repository, models);
    await _search(tester);
    await tester.tap(find.text('Qwen-GGUF'));
    response.complete(
      const HfRepoFiles(
        repo: 'publisher/Qwen-GGUF',
        revision: 'abcdef123456',
        license: 'apache-2.0',
        files: [
          HfFile(
            name: 'Q4_K_M/model-Q4_K_M-00002-of-00002.gguf',
            size: 1073741824,
            sha256: 'b',
          ),
          HfFile(
            name: 'Q4_K_M/model-Q4_K_M-00001-of-00002.gguf',
            size: 1073741824,
            sha256: 'a',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.00 GB'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.textContaining('00002-of-'), findsNothing);
    expect(find.text('Partial GPU'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(models.saved.single.parts, hasLength(2));
    expect(models.saved.single.sizeBytes, 2147483648);
    expect(models.saved.single.fileName, endsWith('-00001-of-00002.gguf'));
  });

  testWidgets(
    'older searches cannot replace a newer query or leave a spinner',
    (tester) async {
      final repository = _Repository();
      final old = Completer<List<HfRepo>>();
      repository.pending['old'] = old;
      await _host(tester, repository, _Models());
      final query = find.byKey(const Key('desktop-hf-query'));
      await tester.enterText(query, 'old');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await _search(tester);
      old.completeError(StateError('stale'));
      await tester.pumpAndSettle();
      expect(find.text('Qwen-GGUF'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Could not search Hugging Face. Try again.'),
        findsNothing,
      );
      await tester.enterText(query, 'x');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text('Qwen-GGUF'), findsNothing);
    },
  );

  testWidgets('changing repository ignores late file responses', (
    tester,
  ) async {
    final repository = _Repository();
    final old = Completer<HfRepoFiles>();
    repository.pendingFiles[_repo.id] = old;
    await _host(tester, repository, _Models());
    await _search(tester);
    await tester.tap(find.text('Qwen-GGUF'));
    await tester.pump();
    await tester.tap(find.text('Small-GGUF'));
    await tester.pumpAndSettle();
    old.completeError(StateError('stale'));
    await tester.pumpAndSettle();
    expect(find.text('Q4_K_M'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard selects and opens results and projector can be skipped',
    (tester) async {
      final repository = _Repository();
      final models = _Models();
      await _host(tester, repository, models);
      final field = tester.widget<TextField>(
        find.byKey(const Key('desktop-hf-query')),
      );
      expect(field.autofocus, isTrue);
      await _search(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(repository.opened, [_repo.id]);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download').first);
      await tester.pumpAndSettle();
      expect(models.saved.single.projector, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fit badges show measured limits and disappear without memory data',
    (tester) async {
      await _host(
        tester,
        _Repository(),
        _Models(),
        memory: {
          'devices': [
            {'type': 'gpu', 'freeMb': 128},
          ],
          'ramAvailableMb': 256,
        },
      );
      await _search(tester);
      await tester.tap(find.text('Qwen-GGUF'));
      await tester.pumpAndSettle();
      expect(find.text('Too large'), findsNWidgets(2));
      expect(
        tester
            .getSize(find.byKey(const Key('desktop-hf-file-model-Q4_K_M.gguf')))
            .height,
        44,
      );
      await tester.pumpWidget(const SizedBox());
      await _host(tester, _Repository(), _Models(), memory: null);
      await _search(tester);
      await tester.tap(find.text('Qwen-GGUF'));
      await tester.pumpAndSettle();
      expect(find.text('Too large'), findsNothing);
      expect(find.text('Fits GPU'), findsNothing);
      expect(find.text('Partial GPU'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed search gives a localized error and can be retried', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await _host(tester, repository, _Models());
    await _search(tester);
    expect(
      find.text('Could not search Hugging Face. Try again.'),
      findsOneWidget,
    );
    repository.fail = false;
    await tester.tap(find.byKey(const Key('desktop-hf-query')));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Qwen-GGUF'), findsOneWidget);
  });
}
