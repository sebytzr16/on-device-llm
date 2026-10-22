// Photos and documents through the whole chat path on a real model: real
// photos (with the model's vision projector, or OCR text only without one)
// and real files in every supported document format, built on the phone,
// imported through AttachmentStore and asked about. Prints one MEDIA: JSON
// line per turn. Run through scripts/test-android.ps1 -Model <gguf>
// -Family <gemma|qwen> [-Mmproj <mmproj.gguf>]
// -Media test-assets/media/{cat,dog,car,receipt}-768.jpg
// -Test integration_test/media_probe_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _mmprojPath = String.fromEnvironment('MMPROJ');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'gemma');

final _model = ModelInfo(
  id: 'media',
  displayName: 'Media probe model',
  fileName: _modelPath.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.values.byName(_family),
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _modelPath,
);

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      webMode: WebMode.off,
      contextSize: 8192,
      maxTokens: 384,
      temperature: 0,
      thinkingModeEnabled: false,
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_model], loadedModelId: null);
  }

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
  }) async {
    await ref
        .read(llamaEngineProvider)
        .loadModel(
          modelPath: info.localPath!,
          mmprojPath: _mmprojPath.isEmpty ? null : _mmprojPath,
          settings: ref.read(settingsProvider),
        );
    state = state.copyWith(loadedModelId: info.id);
  }
}

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A minimal workbook: a price list in shared strings and numbers.
Uint8List _xlsx() {
  const strings = ['Item', 'Price', 'Apples', 'Bread', 'Coffee beans'];
  String s(int i) => '<c t="s"><v>$i</v></c>';
  String n(String v) => '<c><v>$v</v></c>';
  return _zip({
    '[Content_Types].xml': '<Types/>',
    'xl/sharedStrings.xml':
        '<sst>${strings.map((t) => '<si><t>$t</t></si>').join()}</sst>',
    'xl/worksheets/sheet1.xml':
        '<worksheet><sheetData>'
        '<row>${s(0)}${s(1)}</row>'
        '<row>${s(2)}${n('3.2')}</row>'
        '<row>${s(3)}${n('4.75')}</row>'
        '<row>${s(4)}${n('12.9')}</row>'
        '</sheetData></worksheet>',
  });
}

Uint8List _pptx() {
  String slide(List<String> lines) =>
      '<p:sld>${lines.map((l) => '<a:p><a:r><a:t>$l</a:t></a:r></a:p>').join()}</p:sld>';
  return _zip({
    '[Content_Types].xml': '<Types/>',
    'ppt/slides/slide1.xml': slide(['Project Heron', 'Quarterly plan']),
    'ppt/slides/slide2.xml': slide([
      'Milestones',
      'Beta opens on October 30',
      'Public launch on November 14',
    ]),
  });
}

Uint8List _odt() => _zip({
  'mimetype': 'application/vnd.oasis.opendocument.text',
  'content.xml':
      '<office:document-content><office:body><office:text>'
      '<text:h>Garden notes</text:h>'
      '<text:p>The tomatoes go in the south bed.</text:p>'
      '<text:p>The rain barrel holds 200 litres.</text:p>'
      '</office:text></office:body></office:document-content>',
});

Uint8List _epub() => _zip({
  'mimetype': 'application/epub+zip',
  'OEBPS/chapter1.xhtml':
      '<html><body><h1>Chapter 1</h1><p>The storm reached the island at '
      'dusk. The lighthouse keeper, a quiet man named Elias, lit the lamp '
      'and waited for the supply boat.</p></body></html>',
});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('photos and documents through the chat path', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Media probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(await File(_modelPath).exists(), true);
    final vision = _mmprojPath.isNotEmpty;
    final media = Directory(
      '${(await getApplicationSupportDirectory()).path}/media',
    );
    final work = await (await getTemporaryDirectory()).createTemp('media-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = LlamaEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(_Models.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      engine.dispose();
      await db.close();
      await work.delete(recursive: true);
    });
    final failures = <String>[];

    Future<Attachment> import(String name, {Uint8List? bytes}) async {
      final clock = Stopwatch()..start();
      final a = await AttachmentStore.import(
        name: name,
        sourcePath: bytes == null ? '${media.path}/$name' : null,
        bytes: bytes,
      );
      // ignore: avoid_print
      print(
        'MEDIA-IMPORT: ${jsonEncode({'name': name, 'kind': a.kind.name, 'ms': clock.elapsedMilliseconds, 'chars': a.text?.length, 'error': a.error, 'ocrConfidence': a.ocrConfidence, 'text': (a.text ?? '').length > 160 && !a.isImage ? a.text!.substring(0, 160) : a.text})}',
      );
      return a;
    }

    Future<void> turn(
      String probe,
      String q, {
      List<Attachment> attachments = const [],
      List<Pattern> expectAny = const [],
      List<Pattern> expectAll = const [],
      List<Pattern> forbid = const [],
    }) async {
      final n = container.read(chatProvider.notifier);
      final clock = Stopwatch()..start();
      final ok = await n.send(q, attachments: attachments);
      clock.stop();
      final s = container.read(chatProvider);
      final text = s.messages.last.content;
      final lower = text.toLowerCase();
      bool has(Pattern p) => p is String
          ? lower.contains(p.toLowerCase())
          : p.allMatches(text).isNotEmpty;
      final problems = [
        if (!ok || s.error != null) 'error: ${s.error}',
        for (final p in expectAll)
          if (!has(p)) 'missing: $p',
        if (expectAny.isNotEmpty && !expectAny.any(has))
          'missing one of: ${expectAny.join(' / ')}',
        for (final p in forbid)
          if (has(p)) 'wrong: ${p.allMatches(text).first.group(0)}',
      ];
      if (problems.isNotEmpty) failures.add('$probe: ${problems.join('; ')}');
      // ignore: avoid_print
      print(
        'MEDIA: ${jsonEncode({
          'probe': probe,
          'family': _family,
          'vision': vision,
          'question': q,
          'pass': problems.isEmpty,
          'problems': problems,
          'seconds': clock.elapsed.inMilliseconds / 1000,
          'notice': s.notice,
          'metrics': {
            for (final k in ['firstTokenMs', 'mediaTokens', 'cachedPromptTokens', 'promptTokens', 'tokensPerSecond'])
              if (s.metrics[k] is num) k: s.metrics[k],
          },
          'answer': text,
        })}',
      );
    }

    final n = container.read(chatProvider.notifier);

    // 1. Photos. With a projector the model sees them; without one the
    // app sends only the text OCR found, so only the receipt applies.
    if (vision) {
      n.newChat();
      await turn(
        'photo-cat',
        'What animal is in this photo?',
        attachments: [await import('cat-768.jpg')],
        expectAny: ['cat', 'kitten'],
      );
      n.newChat();
      await turn(
        'photo-dog',
        'What animal is in this photo?',
        attachments: [await import('dog-768.jpg')],
        expectAny: ['dog', 'puppy'],
      );
      n.newChat();
      await turn(
        'photo-car',
        'What is in this photo?',
        attachments: [await import('car-768.jpg')],
        expectAny: ['car', 'hatchback', 'vehicle', 'toyota'],
      );
      // The follow-up keeps the encoded photo (prompt cache).
      await turn(
        'photo-car-follow-up',
        'What colour is it?',
        expectAll: ['red'],
      );
      n.newChat();
      await turn(
        'photo-fr',
        "Qu'est-ce qu'on voit sur cette photo ?",
        attachments: [await import('car-768.jpg')],
        expectAny: ['voiture', 'véhicule', 'automobile', 'toyota'],
      );
    }
    n.newChat();
    await turn(
      'photo-receipt',
      'What is the total on this receipt?',
      attachments: [await import('receipt-768.jpg')],
      expectAll: [RegExp(r'54[.,]50?\b')],
      // 54.50 named a subtotal under a made-up "Total: CHF 96.08" is wrong.
      forbid: [
        RegExp(
          r'total\W{0,12}(?:CHF\s*)?(?!54[.,]50?\b)\d',
          caseSensitive: false,
        ),
      ],
    );
    await turn(
      'photo-receipt-follow-up',
      'Which restaurant or hotel is it from?',
      expectAny: ['Scheidegg', 'Berghotel'],
    );

    // 2. Documents in every supported format, made here and imported the
    // way the picker imports them.
    final pdf = ChatDocument.select(
      title: 'Lease summary',
      messages: [
        ChatMessage(
          id: 'lease',
          role: ChatRole.assistant,
          content:
              '# Flat 4B lease\nThe lease for flat 4B starts on 1 March '
              '2027 and runs for twelve months. The monthly rent is 1,450 '
              'dollars, due on the 5th of each month. Pets are allowed '
              'with a 300 dollar deposit.',
          timestamp: DateTime.utc(2026, 10, 21),
        ),
      ],
    );
    final docx = ChatDocument.select(
      title: 'Team update',
      messages: [
        ChatMessage(
          id: 'meeting',
          role: ChatRole.assistant,
          content:
              '# Team update\nThe weekly team meeting moved to Thursday at '
              '3 pm in the Juniper room. Bring the budget draft.',
          timestamp: DateTime.utc(2026, 10, 21),
        ),
      ],
    );
    final docs = <(String, Uint8List, String, List<Pattern>)>[
      (
        'lease.pdf',
        Uint8List.fromList(await pdf.pdf()),
        'When does the lease start and how much is the rent?',
        ['March', RegExp(r'1,?450')],
      ),
      (
        'team-update.docx',
        Uint8List.fromList(docx.docx),
        'When and where is the team meeting now?',
        ['Thursday', 'Juniper'],
      ),
      (
        'prices.xlsx',
        _xlsx(),
        'How much do the coffee beans cost in this sheet?',
        [RegExp(r'12[.,]9')],
      ),
      (
        'plan.pptx',
        _pptx(),
        'When is the public launch according to these slides?',
        ['November', '14'],
      ),
      ('garden.odt', _odt(), 'How much does the rain barrel hold?', ['200']),
      (
        'storm.epub',
        _epub(),
        'What is the lighthouse keeper called?',
        ['Elias'],
      ),
      (
        'parcel.rtf',
        Uint8List.fromList(
          utf8.encode(
            r'{\rtf1\ansi{\fonttbl\f0 Arial;}\f0 Delivery note\par The parcel code is ZX-5521 and it arrives on Friday.\par}',
          ),
        ),
        'What is the parcel code?',
        ['ZX-5521'],
      ),
      (
        'sales.csv',
        Uint8List.fromList(
          utf8.encode(
            'month,region,sales\nJuly,North,1200\nJuly,South,950\n'
            'August,North,1430\nAugust,South,1010\n',
          ),
        ),
        'What were the North sales in August?',
        ['1430', '1,430'],
      ),
    ];
    for (final (name, bytes, q, expected) in docs) {
      final a = await import(name, bytes: bytes);
      if (a.text == null) failures.add('$name: not extracted (${a.error})');
      n.newChat();
      final any = name == 'sales.csv';
      await turn(
        'doc-${name.split('.').last}',
        q,
        attachments: [a],
        expectAll: any ? const [] : expected,
        expectAny: any ? expected : const [],
      );
    }

    // 3. Two files at once: the answer must use the right one.
    n.newChat();
    await turn(
      'doc-two-files',
      'Which of these two files mentions the Juniper room, and what is the '
          'rent in the other one?',
      attachments: [
        await import('lease-2.pdf', bytes: Uint8List.fromList(await pdf.pdf())),
        await import('team-2.docx', bytes: Uint8List.fromList(docx.docx)),
      ],
      expectAll: [RegExp(r'1,?450')],
      expectAny: ['team', 'docx', 'update'],
    );

    // ignore: avoid_print
    print('MEDIA-SUMMARY: ${jsonEncode({'failures': failures})}');
    expect(
      failures.where((f) => f.contains('error:')),
      isEmpty,
      reason: failures.join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 40)));
}
