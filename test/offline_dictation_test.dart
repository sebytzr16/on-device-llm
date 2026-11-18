import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/voice/offline_dictation.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  late List<MethodCall> calls;
  late OfflineDictation dictation;

  Future<void> event(String method, Map<String, Object> args) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      OfflineDictation.channel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(OfflineDictation.channel, (call) async {
      calls.add(call);
      return null;
    });
    dictation = OfflineDictation();
  });
  tearDown(() async {
    await dictation.dispose();
    messenger.setMockMethodCallHandler(OfflineDictation.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'partial and final transcripts arrive; replaced session events are ignored',
    () async {
      final results = <String>[];
      final errors = <String>[];
      await dictation.listen(
        onResult: (text, finalResult) => results.add('$text/$finalResult'),
        onError: errors.add,
        localeId: 'fr_CA',
      );
      final old = (calls.last.arguments as Map)['session'] as int;
      expect((calls.last.arguments as Map)['localeId'], 'fr_CA');
      await event('result', {
        'session': old,
        'text': 'Bonjour',
        'final': false,
      });
      await dictation.listen(
        onResult: (text, finalResult) => results.add('$text/$finalResult'),
        onError: errors.add,
      );
      final current = (calls.last.arguments as Map)['session'] as int;
      await event('result', {'session': old, 'text': 'stale', 'final': true});
      await event('error', {'session': old, 'code': 'stale_error'});
      await event('result', {
        'session': current,
        'text': 'Salut',
        'final': true,
      });
      await event('result', {
        'session': current,
        'text': 'duplicate',
        'final': true,
      });
      expect(results, ['Bonjour/false', 'Salut/true']);
      expect(errors, isEmpty);
    },
  );

  test(
    'stop allows the final transcript; cancel discards later events',
    () async {
      final results = <String>[];
      await dictation.listen(
        onResult: (text, _) => results.add(text),
        onError: (_) {},
      );
      final first = (calls.last.arguments as Map)['session'] as int;
      await dictation.stop();
      expect(calls.last.method, 'stop');
      await event('result', {
        'session': first,
        'text': 'Finished',
        'final': true,
      });
      await dictation.listen(
        onResult: (text, _) => results.add(text),
        onError: (_) {},
      );
      final second = (calls.last.arguments as Map)['session'] as int;
      await dictation.cancel();
      expect(calls.last.method, 'cancel');
      await event('result', {
        'session': second,
        'text': 'discard',
        'final': true,
      });
      expect(results, ['Finished']);
    },
  );

  test(
    'discarding dictation drops late captions and finals until a new listen',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer();
      final voice = container.read(voiceProvider.notifier);
      final captions = <String>[], finals = <String>[];
      await voice.listen(onText: captions.add, onFinal: finals.add);
      final session = (calls.last.arguments as Map)['session'] as int;
      await event('result', {
        'session': session,
        'text': 'sent',
        'final': false,
      });
      voice.discardDictation();
      // Whisper can finish after stop; discarding must invalidate its callbacks
      // even while the native recognizer still has a pending result.
      await event('result', {
        'session': session,
        'text': 'late',
        'final': true,
      });
      expect(captions, ['sent']);
      expect(finals, isEmpty);
      await voice.listen(onText: captions.add, onFinal: finals.add);
      final next = (calls.last.arguments as Map)['session'] as int;
      await event('result', {
        'session': next,
        'text': 'next draft',
        'final': true,
      });
      expect(captions, ['sent', 'next draft']);
      expect(finals, ['next draft']);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'unavailable strict recognizer never invokes the general speech plugin',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const general = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final generalCalls = <String>[];
      messenger.setMockMethodCallHandler(general, (call) async {
        generalCalls.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(general, null));
      messenger.setMockMethodCallHandler(OfflineDictation.channel, (
        call,
      ) async {
        if (call.method == 'listen') {
          throw PlatformException(code: 'offline_unavailable');
        }
        return null;
      });
      final container = ProviderContainer();
      final notifier = container.read(voiceProvider.notifier);
      await notifier.listen(onText: (_) {});
      expect(container.read(voiceProvider).listening, false);
      expect(
        container.read(voiceProvider).error,
        contains('No network recognizer was started'),
      );
      expect(generalCalls, isEmpty);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'microphone denial is visible and does not retry another recognizer',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(OfflineDictation.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'listen') {
          throw PlatformException(code: 'error_permission');
        }
        return null;
      });
      final container = ProviderContainer();
      await container.read(voiceProvider.notifier).listen(onText: (_) {});
      expect(
        container.read(voiceProvider).error,
        contains('Microphone permission'),
      );
      expect(calls.where((c) => c.method == 'listen'), hasLength(1));
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'Stop updates state immediately and closes an Android start that completes late',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pending = Completer<void>();
      var stops = 0;
      messenger.setMockMethodCallHandler(OfflineDictation.channel, (
        call,
      ) async {
        if (call.method == 'listen') await pending.future;
        if (call.method == 'stop') stops++;
        return null;
      });
      final container = ProviderContainer();
      final voice = container.read(voiceProvider.notifier);
      final starting = voice.listen(onText: (_) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(voiceProvider).listening, isTrue);
      final stopping = voice.stop();
      expect(container.read(voiceProvider).listening, isFalse);
      await stopping;
      expect(stops, 1);
      pending.complete();
      await starting;
      expect(stops, 2);
      expect(container.read(voiceProvider).listening, isFalse);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'OS recognizer closes a late start and uses offline 3-second pause options',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final starting = Completer<void>();
      final ready = Completer<void>();
      var stops = 0;
      Map? options;
      messenger.setMockMethodCallHandler(speech, (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'listen') {
          options = call.arguments as Map;
          starting.complete();
          await ready.future;
          return true;
        }
        if (call.method == 'stop') stops++;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(speech, null));
      final container = ProviderContainer();
      final voice = container.read(voiceProvider.notifier);
      final listening = voice.listen(onText: (_) {});
      await starting.future;
      final stopping = voice.stop();
      expect(container.read(voiceProvider).listening, isFalse);
      await stopping;
      expect(stops, 1);
      ready.complete();
      await listening;
      expect(stops, 2);
      expect(options!['onDevice'], isTrue);
      expect(options!['pauseFor'], 3000);
      expect(options!['listenFor'], 60000);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('a fresh session waits for a stopped pending start to close', () async {
    await dictation.dispose();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final pending = Completer<void>();
    var starts = 0, stops = 0;
    var open = false;
    messenger.setMockMethodCallHandler(OfflineDictation.channel, (call) async {
      if (call.method == 'listen') {
        starts++;
        if (starts == 1) await pending.future;
        open = true;
      }
      if (call.method == 'stop') {
        stops++;
        open = false;
      }
      return null;
    });
    final container = ProviderContainer();
    final voice = container.read(voiceProvider.notifier);
    final first = voice.listen(onText: (_) {});
    await Future<void>.delayed(Duration.zero);
    await voice.stop();
    final second = voice.listen(onText: (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    pending.complete();
    await first;
    await second;
    expect(starts, 2);
    expect(stops, 2);
    expect(open, isTrue);
    expect(container.read(voiceProvider).listening, isTrue);
    await voice.stop();
    expect(open, isFalse);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'disposing while permission is pending ignores cancellation callbacks',
    () async {
      await dictation.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(OfflineDictation.channel, (
        call,
      ) async {
        if (call.method == 'listen') await pending.future;
        if (call.method == 'cancel' && !pending.isCompleted) {
          pending.completeError(PlatformException(code: 'cancelled'));
        }
        return null;
      });
      final container = ProviderContainer();
      final listening = container
          .read(voiceProvider.notifier)
          .listen(onText: (_) {});
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      await listening;
    },
  );
}
