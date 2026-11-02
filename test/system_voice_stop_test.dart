import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// flutter_tts on Windows dereferences the pending speak() result inside
/// stop(), so a stop() with nothing playing crashed the PC app (owner,
/// 2026-11-01). The system voice is only stopped mid-utterance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter_tts');
  late List<String> calls;
  Completer<void>? speaking;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    calls = [];
    speaking = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'speak' && speaking != null) await speaking!.future;
      if (call.method == 'stop' && speaking?.isCompleted == false) {
        speaking!.complete();
      }
      return 1;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('reading an answer never stops an idle system voice', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final voice = container.read(voiceProvider.notifier);
    await voice.speak('Hello there. How are you?', id: 'a');
    await voice.stopSpeaking();
    await voice.speak('Second answer.', id: 'b');
    expect(calls, contains('speak'));
    expect(calls, isNot(contains('stop')));
  });

  test('stopping mid-utterance stops the system voice once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final voice = container.read(voiceProvider.notifier);
    speaking = Completer<void>();
    unawaited(voice.speak('A long answer to read.', id: 'a'));
    await pumpEventQueue();
    expect(calls, contains('speak'));
    await voice.stopSpeaking();
    await voice.stopSpeaking();
    expect(calls.where((c) => c == 'stop'), hasLength(1));
  });
}
