// Das Funk-Radio hinter Transit Spark.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/transit/transit_ble_service.dart 76 offene Zeilen. Die
// Berechtigungswege sind schon getestet
// (test/transit/transit_ble_berechtigungen_test.dart) - offen war das
// RADIO selbst: Advertising starten, das Token rotieren, den Funk
// pausieren und wieder aufnehmen.
//
// DER WEG: Der Dienst hat eine Test-Naht (`TransitPlattform`), und im
// Test gibt es den Ersatz fuer das Bluetooth
// (test/support/ble_mocks.dart) - der zaehlt, wie oft das Advertising
// wirklich gestartet wurde.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Advertising startet wirklich (nicht nur "die Anzeige sagt
//     aktiv"),
//   * ein zu langes Token startet das Radio nicht (es wuerde nativ mit
//     ADVERTISE_FAILED_DATA_TOO_LARGE scheitern - eine stille
//     Funkstille),
//   * lehnt das Geraet das Advertising ab, wird das gemeldet (und das
//     Radio sauber beendet),
//   * das Token wird auch dann gemerkt, wenn gar kein Funk laeuft (die
//     Rotation darf nicht verloren gehen),
//   * mit laufendem Funk wird das neue Token gesendet,
//   * suspendieren beendet den Funk, resume startet ihn wieder,
//   * ohne Token kann der Funk nicht fortgesetzt werden,
//   * stoppen vergisst das Token.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/transit/transit_encounter_service.dart';
import 'package:thestia/services/transit/transit_ble_service.dart';

import '../support/ble_mocks.dart';

/// Der Ersatz fuer die Plattform (Android 13 - die Berechtigungswege
/// stehen in `transit_ble_berechtigungen_test.dart`).
class _FakePlattform extends TransitPlattform {
  @override
  bool get istWeb => false;

  @override
  bool get istAndroid => true;

  @override
  bool get istIOS => false;

  @override
  Future<int> androidSdkInt() async => 33;
}

void main() {
  /// Der Dienst (der Singleton - der Test spricht ihn direkt an).
  final dienst = TransitBleService.instance;

  /// Ein gueltiges Token (20 Hexzeichen).
  final token = TransitEncounterService.generateToken();

  setUp(() {
    // DER BINDING: Der Bluetooth-Ersatz antwortet auf dem Kanal des
    // Test-Bindings - ohne ihn gibt es keine Antworten.
    TestWidgetsFlutterBinding.ensureInitialized();
    TransitPlattform.instance = _FakePlattform();
    mockBluetooth();
    resetAdvertisingZaehler();
  });

  tearDown(() {
    unmockBluetooth();
  });

  group('Das Starten', () {
    test('das Radio startet mit einem gueltigen Token', () async {
      await dienst.stop();

      final ok = await dienst.start(token: token, onEncounter: (_, _) {});

      expect(ok, isTrue);
      expect(
        advertisingStarts,
        1,
        reason:
            'Das Advertising muss wirklich gestartet werden - der Dienst '
            'sagt "aktiv", sonst behauptet nur die Anzeige, es laeufe.',
      );
      expect(dienst.currentToken, token);
      expect(dienst.isActive, isTrue);

      await dienst.stop();
    });

    test('ein zu langes Token startet das Radio nicht', () async {
      await dienst.stop();

      final ok = await dienst.start(
        // 200 Hexzeichen: das passt nicht in ein BLE-Paket.
        token: 'a' * 200,
        onEncounter: (_, _) {},
      );

      expect(ok, isFalse);
      expect(
        advertisingStarts,
        0,
        reason:
            'Ein zu langes Token wuerde nativ mit '
            'ADVERTISE_FAILED_DATA_TOO_LARGE scheitern - eine stille '
            'Funkstille, die der Nutzer nicht bemerkt.',
      );
      expect(dienst.lastError, 'advertise_failed');

      await dienst.stop();
    });

    test('lehnt das Geraet das Advertising ab, wird das gemeldet', () async {
      await dienst.stop();
      // Das Geraet verweigert das Advertising (z. B. zu viele
      // Sende-Slots belegt).
      mockBluetooth(advertisingMoeglich: false);

      final ok = await dienst.start(token: token, onEncounter: (_, _) {});

      expect(ok, isFalse);
      expect(
        dienst.lastError,
        'advertise_failed',
        reason:
            'Der Bildschirm muss einen Grund nennen - "startFailed" ohne '
            'Ursache hilft dem Nutzer nicht.',
      );
      expect(
        dienst.isActive,
        isFalse,
        reason: 'Nach dem Scheitern darf das Radio nicht als aktiv gelten.',
      );

      await dienst.stop();
    });
  });

  group('Die Token-Rotation', () {
    test('das neue Token wird auch ohne Funk gemerkt', () async {
      await dienst.stop();
      final neuesToken = 'b' * TransitEncounterService.tokenLaenge;

      await dienst.rotateToken(newToken: neuesToken, onEncounter: (_, _) {});

      expect(
        dienst.currentToken,
        neuesToken,
        reason:
            'Die Rotation darf nicht verloren gehen, wenn der App '
            'zwischendurch im Hintergrund war - sonst sendet die App '
            'wieder das alte Token.',
      );
    });

    test('mit laufendem Funk wird das neue Token gesendet', () async {
      await dienst.stop();
      await dienst.start(token: token, onEncounter: (_, _) {});
      final startsNachStart = advertisingStarts;
      final neuesToken = 'c' * TransitEncounterService.tokenLaenge;

      await dienst.rotateToken(newToken: neuesToken, onEncounter: (_, _) {});

      expect(advertisingStarts, startsNachStart + 1);
      expect(dienst.currentToken, neuesToken);

      await dienst.stop();
    });
  });

  group('Das Pausieren', () {
    test('suspendieren beendet den Funk, resume startet ihn wieder', () async {
      await dienst.stop();
      await dienst.start(token: token, onEncounter: (_, _) {});

      await dienst.suspend();

      expect(
        dienst.isActive,
        isFalse,
        reason:
            'Im Hintergrund darf das Radio nicht weiterlaufen - das war '
            'der Akku- und Datenschutz-Fund (03.11.2026).',
      );
      expect(
        dienst.currentToken,
        token,
        reason: 'Das Token bleibt erhalten - der Funk wird fortgesetzt.',
      );

      final ok = await dienst.resume();

      expect(ok, isTrue);
      expect(dienst.isActive, isTrue);

      await dienst.stop();
    });

    test('ohne Token kann der Funk nicht fortgesetzt werden', () async {
      await dienst.stop();

      expect(
        await dienst.resume(),
        isFalse,
        reason:
            'Ohne Token gibt es nichts zu senden - der Aufruf muss das '
            'sagen, statt still zu nichts zu tun.',
      );
    });

    test('stoppen vergisst das Token', () async {
      await dienst.stop();
      await dienst.start(token: token, onEncounter: (_, _) {});

      await dienst.stop();

      expect(dienst.currentToken, isNull);
      expect(dienst.isActive, isFalse);
    });
  });
}
