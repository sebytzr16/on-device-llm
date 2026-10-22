import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/retrieval/domain/news_intent.dart';
import 'package:ondevice_llm/features/tools/domain/tool_aliases.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

void main() {
  // As text: records and lists compare maps by identity.
  List<String> calls(String answer) => [
    for (final c in TextToolProtocol.parse(answer, counter: 1))
      '${c.name} ${jsonEncode(c.args)}',
  ];
  List<String> want(String name, Map<String, Object> args) => [
    '$name ${jsonEncode(args)}',
  ];
  final search = want('search_web', {'query': 'flutter version'});

  test('the shapes models write a call in are all understood', () {
    for (final answer in [
      '```tool\n{"name": "search_web", "arguments": {"query": "flutter version"}}\n```',
      '<tool_call>\n{"name": "search_web", "arguments": {"query": "flutter version"}}\n</tool_call>',
      // Unclosed tag: generation stopped at the end of the call.
      '<tool_call>{"name": "search_web", "arguments": {"query": "flutter version"}}',
      // Llama 3.x.
      '<function=search_web>{"query": "flutter version"}</function>',
      '<|python_tag|>{"name": "search_web", "parameters": {"query": "flutter version"}}<|eom_id|>',
      // Mistral.
      '[TOOL_CALLS] [{"name": "search_web", "arguments": {"query": "flutter version"}}]',
      // Gemma tool_code.
      '```tool_code\nsearch_web(query="flutter version")\n```',
      // ReAct.
      'Thought: I should search.\nAction: search_web\nAction Input: flutter version',
      // The whole reply is the JSON.
      '{"name": "search_web", "arguments": {"query": "flutter version"}}',
      // OpenAI-style wrapper and LangChain keys.
      '```json\n{"function": {"name": "search_web", "arguments": {"query": "flutter version"}}}\n```',
      '```json\n{"action": "search_web", "action_input": "flutter version"}\n```',
    ]) {
      expect(calls(answer), search, reason: answer);
    }
    expect(
      calls("```tool_code\nprint(calculator(expression='2450*0.18'))\n```"),
      want('calculator', {'expression': '2450*0.18'}),
    );
  });

  test('tool and argument names are mapped to ours', () {
    expect(
      calls(
        '```tool\n{"name": "web_search", "arguments": {"q": "flutter version"}}\n```',
      ),
      want('search_web', {'q': 'flutter version', 'query': 'flutter version'}),
    );
    expect(
      calls(
        '```tool\n{"name": "open_url", "arguments": {"link": "https://a.example"}}\n```',
      ),
      want('read_url', {
        'link': 'https://a.example',
        'url': 'https://a.example',
      }),
    );
    expect(
      calls(
        '```tool\n{"name": "Calculate", "arguments": {"expr": "1+1"}}\n```',
      ),
      want('calculator', {'expr': '1+1', 'expression': '1+1'}),
    );
    expect(
      calls('```tool\n{"name": "functions.get_news", "arguments": {}}\n```'),
      want('search_news', {}),
    );
    // A string where an object belongs.
    expect(
      calls('```tool\n{"name": "google", "arguments": "flutter version"}\n```'),
      search,
    );
    // The runner maps native calls the same way.
    final native = ToolAliases.normalize(
      const ToolCall(
        id: 'x',
        name: 'fetch_url',
        arguments: '{"uri": "https://b.example"}',
      ),
    );
    expect(native.name, 'read_url');
    expect(native.args['url'], 'https://b.example');
    expect(
      ToolAliases.args('search_web', {
        'Search-Query': 'flutter version',
      })['query'],
      'flutter version',
    );
    // An unknown tool keeps its name (the runner refuses it as before).
    expect(ToolAliases.name('send_email'), 'send_email');
  });

  test('JSON that is not a call stays in the answer', () {
    const answer =
        'Here is the config:\n```json\n{"name": "my app", "version": 2}\n```';
    expect(calls(answer), isEmpty);
    expect(TextToolProtocol.strip(answer), answer);
    const withCall =
        'Let me check.\n<function=search_web>{"query": "x"}</function>';
    expect(TextToolProtocol.strip(withCall), 'Let me check.');
    // One call written in two shapes counts once.
    expect(
      calls(
        '<tool_call>```tool\n{"name": "search_web", "arguments": {"query": "x"}}\n```</tool_call>',
      ),
      hasLength(1),
    );
  });

  test('the instructions show examples for the offered tools', () {
    final text = TextToolProtocol.instructions(const [
      ToolSpec(name: 'calculator', description: 'Math.', parameters: {}),
    ]);
    expect(text, contains('"expression": "2450*0.18"'));
    expect(text, contains('Use the tool names exactly as listed'));
  });

  test('French and Spanish questions reach the web and the news desk', () {
    expect(
      RetrievalPlan.timeSensitive('¿Cuáles son las últimas noticias?'),
      true,
    );
    expect(
      RetrievalPlan.timeSensitive("Quelles sont les actualités aujourd'hui ?"),
      true,
    );
    expect(
      RetrievalPlan.timeSensitive('¿Cuál es el precio del oro hoy?'),
      true,
    );
    expect(RetrievalPlan.timeSensitive('Explícame la fotosíntesis'), false);
    expect(RetrievalPlan.greetingOnly('¡Hola!'), true);
    expect(RetrievalPlan.greetingOnly('Buenos días'), true);
    expect(RetrievalPlan.greetingOnly('Merci beaucoup'), true);
    expect(
      RetrievalPlan.localTask('Traduce esto al inglés: buenos días'),
      true,
    );
    expect(RetrievalPlan.localTask('Corrige ce texte : je suis aller'), true);
    expect(
      RetrievalPlan.of(
        'busca el horario del museo del Prado',
        webEnabled: true,
      ).mode,
      RetrievalMode.search,
    );
    expect(NewsIntent.of('¿Cuáles son las últimas noticias?'), isNotNull);
    expect(NewsIntent.of('¿Cuáles son las últimas noticias?')!.topic, isNull);
    expect(NewsIntent.of('noticias de fútbol hoy')!.topic, contains('fútbol'));
    expect(NewsIntent.of('quelles sont les actualités en France'), isNotNull);
  });
}
