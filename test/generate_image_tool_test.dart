import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_aliases.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

ToolRunner _runner({GenerateImageTool? generateImage}) => ToolRunner(
  scraper: DuckDuckGoScraper(),
  reader: WebPageReader(),
  settings: const InferenceSettings(toolsEnabled: true),
  generateImage: generateImage,
);

ToolCall _call(String arguments) =>
    ToolCall(id: 'c1', name: 'generate_image', arguments: arguments);

void main() {
  test('generate_image is offered only when the host supplies it', () {
    expect(
      _runner().specs().map((s) => s.name),
      isNot(contains('generate_image')),
    );
    expect(
      _runner(
        generateImage: (_, _, _, _) async => 'ok',
      ).specs().map((s) => s.name),
      contains('generate_image'),
    );
  });

  test('the tool runs the host image generator with its arguments', () async {
    String? prompt;
    int? width, height, steps;
    final runner = _runner(
      generateImage: (p, w, h, s) async {
        prompt = p;
        width = w;
        height = h;
        steps = s;
        return 'Picture generated.';
      },
    );
    final result = await runner.run(
      _call(
        '{"prompt": "a cat on a bike", "width": 1024, "height": 768, '
        '"steps": 12}',
      ),
    );
    expect(result.ok, isTrue);
    expect(prompt, 'a cat on a bike');
    expect((width, height, steps), (1024, 768, 12));
    expect(result.output, 'Picture generated.');
    expect(runner.trace.single.call.name, 'generate_image');
  });

  test('a refusal reaches the model as the tool result', () async {
    final runner = _runner(
      generateImage: (_, _, _, _) async =>
          throw StateError('Image generation needs the desktop app.'),
    );
    final result = await runner.run(_call('{"prompt": "a cat"}'));
    expect(result.ok, isFalse);
    expect(result.output, contains('Image generation needs the desktop app.'));
  });

  test('a call without a prompt fails cleanly', () async {
    var ran = false;
    final runner = _runner(
      generateImage: (_, _, _, _) async {
        ran = true;
        return 'ok';
      },
    );
    final result = await runner.run(_call('{}'));
    expect(result.ok, isFalse, reason: result.output);
    expect(result.output, contains('prompt'));
    expect(ran, isFalse);
  });

  test('drawing words open the tools and are not sent to the web', () {
    for (final input in [
      'draw a cat on a bike',
      'make me a picture of the sea at night',
      'dessine un chat',
      'dibuja un gato',
    ]) {
      expect(RetrievalPlan.wantsImage(input), isTrue, reason: input);
      expect(RetrievalPlan.mayNeedTools(input), isTrue, reason: input);
      expect(RetrievalPlan.localTask(input), isTrue, reason: input);
    }
  });

  test('draw_image is understood as generate_image', () {
    expect(ToolAliases.name('draw_image'), 'generate_image');
    expect(ToolAliases.known('generate_image'), isTrue);
    expect(ToolAliases.args('generate_image', {'description': 'a red house'}), {
      'description': 'a red house',
      'prompt': 'a red house',
    });
  });
}
