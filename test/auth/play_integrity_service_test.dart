// Die Play-Integrity-Attestierung.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/services/auth/play_integrity_service.dart nur 37,5 % Abdeckung.
//
// DER WEG: Der Aufruf geht über einen MethodChannel
// ('thestia/integrity') - der Test beantwortet ihn selbst.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Aufruf liefert das Token des Geräts,
//   * die Nonce kommt beim Gerät an (sie bindet das Token an diesen
//     einen Aufruf - sonst kännte ein Token wiederverwendet werden),
//   * ein Fehler des Kanals ergibt null (der Aufrufer fällt dann auf
//     die manuelle Prüfung zurück - ein harter Fehler würde die
//     Verifizierung blockieren).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/auth/play_integrity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Der Kanal des Geräts.
  const kanal = MethodChannel('thestia/integrity');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
  });

  /// Beantwortet den Kanal mit [antwort].
  void mockKanal(Object? antwort, {Object? fehler}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, (anfrage) async {
          if (fehler != null) throw fehler;
          return antwort;
        });
  }

  group('Das Token', () {
    test('kommt vom Geraet', () async {
      mockKanal('das-token');

      expect(
        await PlayIntegrityService.fetchViaChannel('die-nonce'),
        'das-token',
        reason: 'Das Token ist die Grundlage der Attestierung.',
      );
    });

    test('die Nonce kommt beim Geraet an', () async {
      String? gesendeteNonce;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, (anfrage) async {
            gesendeteNonce = (anfrage.arguments as Map)['nonce'] as String?;
            return 'das-token';
          });

      await PlayIntegrityService.fetchViaChannel('die-nonce');

      expect(
        gesendeteNonce,
        'die-nonce',
        reason:
            'Die Nonce bindet das Token an diesen Aufruf - ohne sie '
            'koennte ein altes Token erneut eingeschickt werden.',
      );
    });

    test('ohne Token gibt es null', () async {
      mockKanal(null);

      expect(await PlayIntegrityService.fetchViaChannel('die-nonce'), isNull);
    });

    test('ein Fehler des Kanals gibt null', () async {
      // DER FEHLER: Das Gerät hat die Play-Bibliothek nicht (der
      // F-Droid-Build zum Beispiel).
      mockKanal(null, fehler: PlatformException(code: 'nicht_verfuegbar'));

      expect(
        await PlayIntegrityService.fetchViaChannel('die-nonce'),
        isNull,
        reason:
            'Ein fehlender Kanal darf die Verifizierung nicht blockieren - '
            'der Aufrufer faellt auf die manuelle Pruefung zurueck.',
      );
    });

    test('ein unerwarteter Fehler gibt null', () async {
      mockKanal(null, fehler: StateError('kaputt'));

      expect(await PlayIntegrityService.fetchViaChannel('die-nonce'), isNull);
    });
  });
}
