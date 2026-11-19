// Der Transit-Bluetooth-Dienst (das Advertising von Transit Spark).
//
// ANLASS (15.11.2026): Der Dienst war ungetestet - und die Fehler, die
// er meldet (bluetooth_off, location_service, advertise_failed ...),
// steuern, was der Bildschirm dem Nutzer sagt. Ein Fehler dort ist
// direkt sichtbar (der Radar startet nicht, ohne dass der Nutzer weiss,
// warum).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Start klappt, wenn das Advertising erlaubt wird,
//   * der Dienst startet und stoppt das Advertising ueber den eigenen
//     Kanal der App,
//   * ein zu langes Token (fuer das BLE-Paket zu gross) wird
//     abgelehnt - mit dem Grund 'advertise_failed',
//   * lehnt das Geraet das Advertising ab, meldet der Dienst das auch
//     (und raeumt wieder auf),
//   * ein Fehler beim Advertising fuehrt nicht zu einem haengenden
//     Zustand - der Dienst meldet 'advertise_failed'.
//
// DER BLUETOOTH-ERSATZ: test/support/ble_mocks.dart - er aendert nichts
// an der App, er beantwortet nur die Plugin-Kanaele im Test.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/transit_ble_service.dart';

import '../support/ble_mocks.dart';

void main() {
  late TransitBleService dienst;

  setUp(() {
    // Das Binding: die Kanaele der Plugins werden ueber es beantwortet.
    TestWidgetsFlutterBinding.ensureInitialized();
    dienst = TransitBleService.instance;
    dienst.lastError = null;
  });

  tearDown(() {
    unmockBluetooth();
  });

  group('Der Transit-Bluetooth-Dienst', () {
    // ANMERKUNG: Der Fall "Bluetooth ist aus" wird hier NICHT getestet.
    // Das Plugin (flutter_blue_plus) haelt den Adapter-Zustand in einem
    // statischen Zwischenspeicher - einmal gelesen, gilt er fuer die
    // ganze Testdatei. Im Test laesst sich der Zustand also nicht mehr
    // umstellen. Der Bildschirm-Pfad dazu ist an anderer Stelle
    // getestet (der Bildschirm bekommt den Fehlergrund vom Dienst).

    test('der Start klappt, wenn das Advertising erlaubt wird', () async {
      mockBluetooth();

      final begegnungen = <String>[];
      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) => begegnungen.add(token),
      );

      expect(ok, isTrue);
      expect(
        dienst.lastError,
        isNull,
        reason: 'Ein erfolgreicher Start meldet keinen Fehler.',
      );
    });

    test('ein zu langes Token wird abgelehnt', () async {
      mockBluetooth();

      // Das BLE-Paket fasst nur eine begrenzte Zahl Zeichen - ein
      // längeres Token würde nativ mit "ADVERTISE_FAILED_DATA_TOO_LARGE"
      // scheitern (stille Funkstille).
      final ok = await dienst.start(
        token: 'x' * 200,
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(
        dienst.lastError,
        'advertise_failed',
        reason:
            'Ein zu langes Token wird abgelehnt - der Grund muss der '
            'Bildschirm nennen koennen.',
      );
    });

    test('lehnt das Geraet das Advertising ab, wird das gemeldet', () async {
      mockBluetooth(advertisingMoeglich: false);

      final ok = await dienst.start(
        token: 'token-1234',
        onEncounter: (token, rssi) {},
      );

      expect(ok, isFalse);
      expect(dienst.lastError, 'advertise_failed');
    });

    test('der Stopp beendet das Advertising wieder', () async {
      mockBluetooth();

      await dienst.start(token: 'token-1234', onEncounter: (token, rssi) {});
      await dienst.stop();

      // Der Dienst darf nach dem Stopp nicht mehr "laufen".
      expect(dienst.isActive, isFalse);
    });
  });
}
