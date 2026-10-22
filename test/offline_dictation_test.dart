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
