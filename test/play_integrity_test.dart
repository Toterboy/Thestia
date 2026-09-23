import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/services/play_integrity_service.dart';

/// Tests für Play Integrity (v0.9.0): Channel-Aufruf mit gemocktem
/// Messenger; echte Tokens kommen nur vom Gerät (Play-Build).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('wisp/integrity');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('fetchViaChannel liefert Token bei Erfolg', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestToken');
      expect((call.arguments as Map)['nonce'], isNotEmpty);
      return 'token-abc';
    });
    expect(
      await PlayIntegrityService.fetchViaChannel('nonce-xyz'),
      'token-abc',
    );
  });

  test('fetchViaChannel liefert null bei PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    expect(await PlayIntegrityService.fetchViaChannel('n'), isNull);
  });

  test('requestToken liefert null außerhalb Android (Test-VM)', () async {
    // Test-VM ist kein Android: fail-open zu null (manuelle Queue).
    expect(await PlayIntegrityService.requestToken(), isNull);
  });
}
