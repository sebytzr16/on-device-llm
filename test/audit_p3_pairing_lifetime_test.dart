import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';

void main() {
  test('codes expire at ten minutes and can be redeemed only once', () {
    var now = DateTime(2026);
    final session = PairingSession(now: () => now);
    expect(session.reserve(), isTrue);
    expect(session.accept(), isTrue);
    expect(session.reserve(), isFalse);
    expect(session.accept(), isFalse);
    final expiring = PairingSession(now: () => now);
    now = now.add(const Duration(minutes: 10));
    expect(expiring.expired, isTrue);
    expect(expiring.reserve(), isFalse);
  });
  test('concurrent reservations share the five-guess limit', () {
    final session = PairingSession();
    for (var i = 0; i < 5; i++) {
      expect(session.reserve(), isTrue);
    }
    expect(session.locked, isTrue);
    expect(session.reserve(), isFalse);
    expect(session.accept(), isTrue);
    expect(session.accept(), isFalse);
  });
}
