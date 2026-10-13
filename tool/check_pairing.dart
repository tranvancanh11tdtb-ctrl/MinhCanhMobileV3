// Run with dart tool/check_pairing.dart; no Flutter bootstrap.
import '../lib/lan/pairing_service.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}
void rejects(void Function() action, String description) {
  try { action(); } on StateError { return; }
  throw StateError(description);
}
void main() {
  var now = DateTime.utc(2026, 10, 6);
  final pairing = PairingService(now: () => now);
  final code = pairing.newCode();
  check(RegExp(r'^\d{6}$').hasMatch(code), 'six digit code');
  final token = pairing.exchange(code, 'device-a');
  check(RegExp(r'^[0-9a-f]{64}$').hasMatch(token), '256 bit session token');
  check(pairing.valid(token), 'paired session is valid');
  rejects(() => pairing.exchange(code, 'device-b'), 'code is single use');
  now = now.add(const Duration(hours: 8));
  check(!pairing.valid(token), 'session expires at exactly eight hours');
  final expired = pairing.newCode();
  now = now.add(const Duration(minutes: 5));
  rejects(() => pairing.exchange(expired, 'device-c'), 'code expires after five minutes');
  final limited = pairing.newCode();
  for (var i = 0; i < 5; i++) {
    rejects(() => pairing.exchange('invalid', 'device-d'), 'wrong code rejected');
  }
  rejects(() => pairing.exchange(limited, 'device-d'), 'five failed attempts block pairing');
  now = now.add(const Duration(seconds: 61));
  final second = pairing.exchange(limited, 'device-d');
  check(pairing.valid(second), 'pairing resumes after cooldown');
  final third = pairing.exchange(pairing.newCode(), 'device-e');
  check(pairing.deviceCount == 2, 'expired sessions excluded from device count');
  pairing.revokeAll();
  check(!pairing.valid(second) && !pairing.valid(third), 'stop revokes all sessions');
  check(pairing.code == null && pairing.deviceCount == 0, 'stop clears pairing code');
  print('PASS: pairing code, single use, expiry, throttling, session expiry and revocation');
}
