import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/desktop/chat_image_generation.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_aliases.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';

ToolRunner _runner({EditImageTool? editImage}) => ToolRunner(
  scraper: DuckDuckGoScraper(),
  reader: WebPageReader(),
  settings: const InferenceSettings(toolsEnabled: true),
  editImage: editImage,
);

ToolCall _call(String arguments) =>
    ToolCall(id: 'c1', name: 'edit_image', arguments: arguments);

void main() {
  test('edit_image is offered only when the host supplies it', () {
    expect(_runner().specs().map((s) => s.name), isNot(contains('edit_image')));
    expect(
      _runner(editImage: (_, _, _) async => 'ok').specs().map((s) => s.name),
      contains('edit_image'),
    );
  });

  test('the tool passes the instruction, strength and steps on', () async {
    String? instruction;
    double? strength;
    int? steps;
    final runner = _runner(
      editImage: (i, s, n) async {
        instruction = i;
        strength = s;
        steps = n;
        return 'Picture edited.';
      },
    );
    final result = await runner.run(
      _call(
        '{"prompt": "the same photo, purple sky", "strength": 0.5, '
        '"steps": 12}',
      ),
    );
    expect(result.ok, isTrue);
    expect(instruction, 'the same photo, purple sky');
    expect(strength, 0.5);
    expect(steps, 12);
  });

  test('strength is optional, clamped, a percentage is understood', () async {
    final seen = <double?>[];
    final runner = _runner(
      editImage: (_, s, _) async {
        seen.add(s);
        return 'ok';
      },
    );
    await runner.run(_call('{"prompt": "x"}'));
    await runner.run(_call('{"prompt": "x", "strength": 0.01}'));
    await runner.run(_call('{"prompt": "x", "strength": 65}'));
    await runner.run(_call('{"prompt": "x", "strength": "0.8"}'));
    expect(seen, [null, 0.05, 0.65, 0.8]);
  });

  test('a missing prompt or a bad strength is a tool error', () async {
    var called = false;
    final runner = _runner(
      editImage: (_, _, _) async {
        called = true;
        return 'ok';
      },
    );
    expect((await runner.run(_call('{}'))).ok, isFalse);
    expect(
      (await runner.run(_call('{"prompt": "x", "strength": "a lot"}'))).ok,
      isFalse,
    );
    expect(called, isFalse);
  });

  test('a failing editor is reported as a tool error, not thrown', () async {
    final runner = _runner(
      editImage: (_, _, _) async => throw StateError('No picture'),
    );
    final result = await runner.run(_call('{"prompt": "x"}'));
    expect(result.ok, isFalse);
    expect(result.output, contains('No picture'));
  });

  test('model spellings map to edit_image and its prompt', () {
    expect(ToolAliases.name('modify_image'), 'edit_image');
    expect(ToolAliases.name('img2img'), 'edit_image');
    expect(ToolAliases.known('edit_image'), isTrue);
    expect(
      ToolAliases.args('edit_image', {'instruction': 'make it blue'})['prompt'],
      'make it blue',
    );
  });

  test('requests to change a picture are recognised in three languages', () {
    for (final input in [
      'make the sky purple',
      'Remove the background',
      'turn it into a watercolour',
      'rends le ciel violet',
      'enlève la personne à gauche',
      'haz el cielo morado',
      'quita el fondo',
    ]) {
      expect(RetrievalPlan.wantsImageEdit(input), isTrue, reason: input);
    }
    for (final input in ['thanks', 'what is in this picture?', 'merci']) {
      expect(RetrievalPlan.wantsImageEdit(input), isFalse, reason: input);
    }
  });

  group('edit size', () {
    test('keeps the picture shape near the model size, in 32s', () {
      final s = editSizeFor(4000, 3000, 1024, 1024);
      expect(s.width % 32, 0);
      expect(s.height % 32, 0);
      expect(s.width / s.height, closeTo(4 / 3, 0.05));
      expect(s.width * s.height, closeTo(1024 * 1024, 1024 * 1024 * 0.1));
    });

    test('a small picture is not enlarged and stays within limits', () {
      final s = editSizeFor(512, 512, 1024, 1024);
      expect((s.width, s.height), (512, 512));
      final tiny = editSizeFor(10, 10, 1024, 1024);
      expect(tiny.width, ChatImageGenerator.minSide);
      final wide = editSizeFor(20000, 100, 1024, 1024);
      expect(wide.width, lessThanOrEqualTo(ChatImageGenerator.maxSide));
      expect(wide.height, ChatImageGenerator.minSide);
    });
  });

  group('engine', () {
    test(
      'an edit goes to the image-to-image op with the start picture',
      () async {
        final ops = <String>[];
        List<Object?>? args;
        final engine = SdEngine(
          invoke: (op, a) async {
            ops.add(op);
            if (op == 'load') return 1;
            args = a;
            return [
              TransferableTypedData.fromList([Uint8List(2 * 2 * 4)]),
              2,
              2,
              1,
              0,
            ];
          },
        );
        await engine.load(key: 'm');
        final start = SdResult(Uint8List(2 * 2 * 4), 2, 2);
        final out = await engine.generate(
          {'prompt': 'x', 'strength': 0.5},
          edit: true,
          init: start,
        );
        expect(ops, ['load', 'edit']);
        expect(args![2], isA<TransferableTypedData>());
        expect(args![3], 2);
        expect((out.width, out.height), (2, 2));
        await expectLater(
          engine.generate({'prompt': 'x'}, edit: true),
          throwsArgumentError,
        );
      },
    );
  });
}
