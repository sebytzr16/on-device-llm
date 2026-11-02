import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/share/share_inbox.dart';

void main() {
  test('external scheduled-intent fallback stays a draft on the Dart side', () {
    // ShareInbox.kt strips the scheduled flag when the app token mismatches.
    // Exercise that bridge payload; caller authentication itself is native.
    final payload = SharedPayload.fromMap({'text': 'Run this prompt'});
    expect(payload.draft, 'Run this prompt');
    expect(payload.scheduled, isNull);
    expect(payload.launch, isNull);
    expect(payload.launchTrusted, isFalse);
  });

  test('voice launch trusts only the native boolean true', () {
    for (final value in <Object?>[null, false, 'true', 1]) {
      final payload = SharedPayload.fromMap({
        'launch': 'voice',
        'trusted': value,
      });
      expect(payload.launchTrusted, isFalse, reason: 'trusted=$value');
    }
    expect(
      SharedPayload.fromMap({'launch': 'voice', 'trusted': true}).launchTrusted,
      isTrue,
    );
  });

  test(
    'P0-01: forged Android intent cannot auto-submit a scheduled prompt',
    () {},
    skip:
        'Caller token verification lives in ShareInbox.kt, before Dart; '
        'ShareInbox and ScheduleStore have no Dart caller-identity seam. '
        'Requires an Android intent/instrumentation test.',
  );
}
