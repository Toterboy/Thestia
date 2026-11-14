// Unit-Tests fuer den Standort im Keystore.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Speichern, Lesen und Loeschen des Verifikations-Standorts,
//   * die Halb-Besetzung (nur Breite, nur Laenge),
//   * die einmalige Migration aus den Klartext-SharedPreferences in den
//     Keystore (inklusive Idempotenz und Fehlerfall).
//
// WIE DER KEYSTORE ERSETZT WIRD:
//   Der Dienst spricht den Keystore ueber den Method-Channel von
//   flutter_secure_storage an. Der Test beantwortet diesen Kanal mit
//   einem In-Memory-Speicher - so bleibt der Test offline und
//   deterministisch und greift nicht auf den echten Keystore des
//   Rechners zu.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thestia/services/secure_location_storage.dart';

/// Der Kanal von flutter_secure_storage.
const MethodChannel _keystoreKanal = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Der In-Memory-Keystore des Tests.
final Map<String, String> _keystore = <String, String>{};

/// Wenn true, schlaegt jeder Schreibvorgang fehl (Fehlersimulation).
bool _schreibenSchlaegtFehl = false;

/// Beantwortet die Keystore-Aufrufe.
Future<Object?> _keystoreAntwort(MethodCall anfrage) async {
  final args = (anfrage.arguments as Map?)?.cast<String, dynamic>() ?? {};
  switch (anfrage.method) {
    case 'read':
      return _keystore[args['key'] as String?];
    case 'write':
      if (_schreibenSchlaegtFehl) {
        throw PlatformException(
          code: 'KEystore_dicht',
          message: 'Der Keystore ist gesperrt.',
        );
      }
      _keystore[args['key'] as String] = args['value'] as String;
      return null;
    case 'delete':
      _keystore.remove(args['key']);
      return null;
    case 'containsKey':
      return _keystore.containsKey(args['key']);
    case 'readAll':
      return Map<String, String>.from(_keystore);
    case 'deleteAll':
      _keystore.clear();
      return null;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _keystore.clear();
    _schreibenSchlaegtFehl = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystoreKanal, _keystoreAntwort);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_keystoreKanal, null);
  });

  group('SecureLocationStorage.save/readAll', () {
    test('der Standort landet vollstaendig im Keystore', () async {
      await SecureLocationStorage.instance.save(
        latitude: '52.5200',
        longitude: '13.4050',
        timestamp: '2026-11-01T10:00:00Z',
        accuracy: '12.5',
      );

      final gelesen = await SecureLocationStorage.instance.readAll();

      expect(gelesen, isNotNull);
      expect(gelesen!['latitude'], '52.5200');
      expect(gelesen['longitude'], '13.4050');
      expect(gelesen['timestamp'], '2026-11-01T10:00:00Z');
      expect(gelesen['accuracy'], '12.5');
    });

    test('ohne gespeicherten Standort liefert readAll null', () async {
      // DER GRUND: Die App unterscheidet "kein Standort" (null) von
      // "Standort ohne Zeitstempel" (Map mit leerem Zeitstempel). Beide
      // Faelle muessen unterschieden werden.
      final gelesen = await SecureLocationStorage.instance.readAll();

      expect(gelesen, isNull);
    });

    test(
      'fehlender Zeitstempel und Accuracy werden zu leeren Strings',
      () async {
        // DER GRUND: Der Keystore kann teilweise gefuellt sein (z. B. nach
        // einem abgebrochenen Schreibvorgang). readAll darf dann nicht
        // crashen - der Aufrufer braucht eine Map.
        _keystore['thestia_loc_lat'] = '52.5200';
        _keystore['thestia_loc_lng'] = '13.4050';

        final gelesen = await SecureLocationStorage.instance.readAll();

        expect(gelesen, isNotNull);
        expect(gelesen!['timestamp'], '');
        expect(gelesen['accuracy'], '');
      },
    );

    test('nur die Haelfte des Standorts liefert null', () async {
      // DER GRUND: Ein Standort ohne Laenge (oder ohne Breite) ist
      // unbrauchbar - der Aufrufer soll "kein Standort" sehen und den
      // Nutzer neu fragen, statt mit einer halben Koordinate zu rechnen.
      _keystore['thestia_loc_lat'] = '52.5200';

      expect(await SecureLocationStorage.instance.readAll(), isNull);
    });
  });

  group('SecureLocationStorage.hasLocation', () {
    test('nach dem Speichern ist ein Standort vorhanden', () async {
      await SecureLocationStorage.instance.save(
        latitude: '52.5200',
        longitude: '13.4050',
        timestamp: '2026-11-01T10:00:00Z',
        accuracy: '12.5',
      );

      expect(await SecureLocationStorage.instance.hasLocation(), isTrue);
    });

    test('ohne Standort: false', () async {
      expect(await SecureLocationStorage.instance.hasLocation(), isFalse);
    });

    test('leere Werte zaehlen nicht als Standort', () async {
      // DER GRUND: Ein leerer String ist "kein Wert" - sonst wuerde die
      // App einen Standort annehmen und danach eine Verifikation gegen
      // 0,0 rechnen.
      _keystore['thestia_loc_lat'] = '';
      _keystore['thestia_loc_lng'] = '13.4050';

      expect(await SecureLocationStorage.instance.hasLocation(), isFalse);
    });
  });

  group('SecureLocationStorage.clear', () {
    test('loescht alle vier Eintraege', () async {
      await SecureLocationStorage.instance.save(
        latitude: '52.5200',
        longitude: '13.4050',
        timestamp: '2026-11-01T10:00:00Z',
        accuracy: '12.5',
      );

      await SecureLocationStorage.instance.clear();

      expect(_keystore.containsKey('thestia_loc_lat'), isFalse);
      expect(_keystore.containsKey('thestia_loc_lng'), isFalse);
      expect(_keystore.containsKey('thestia_loc_ts'), isFalse);
      expect(_keystore.containsKey('thestia_loc_acc'), isFalse);
      expect(await SecureLocationStorage.instance.hasLocation(), isFalse);
    });
  });

  group('SecureLocationStorage.migrateFromSharedPreferences', () {
    test('der Klartext-Standort wandert in den Keystore', () async {
      SharedPreferences.setMockInitialValues({
        'verification_latitude': '52.5200',
        'verification_longitude': '13.4050',
        'verification_location_timestamp': '2026-10-01T08:00:00Z',
        'verification_location_accuracy': '8.0',
      });
      final prefs = await SharedPreferences.getInstance();

      await SecureLocationStorage.migrateFromSharedPreferences(prefs);

      final gelesen = await SecureLocationStorage.instance.readAll();
      expect(gelesen, isNotNull);
      expect(gelesen!['latitude'], '52.5200');
      expect(gelesen['longitude'], '13.4050');
      expect(gelesen['timestamp'], '2026-10-01T08:00:00Z');
      expect(gelesen['accuracy'], '8.0');

      expect(
        prefs.getString('verification_latitude'),
        isNull,
        reason:
            'Der Klartext-Eintrag liegt noch in SharedPreferences - genau '
            'das soll die Migration beseitigen.',
      );
      expect(prefs.getString('verification_longitude'), isNull);
      expect(prefs.getString('verification_location_timestamp'), isNull);
      expect(prefs.getString('verification_location_accuracy'), isNull);
      expect(
        prefs.getBool('thestia_loc_migrated_v1'),
        isTrue,
        reason: 'Nach der Migration muss der Marker gesetzt sein.',
      );
    });

    test('zweiter Lauf: nichts wird erneut geschrieben', () async {
      SharedPreferences.setMockInitialValues({
        'verification_latitude': '52.5200',
        'verification_longitude': '13.4050',
      });
      final prefs = await SharedPreferences.getInstance();

      await SecureLocationStorage.migrateFromSharedPreferences(prefs);
      // Der Klartext kommt danach wieder zurueck (z. B. weil ein
      // Backup eingespielt wurde) - die Migration darf ihn NICHT noch
      // einmal uebernehmen.
      await prefs.setString('verification_latitude', '48.1372');
      await prefs.setString('verification_longitude', '11.5756');

      await SecureLocationStorage.migrateFromSharedPreferences(prefs);

      final gelesen = await SecureLocationStorage.instance.readAll();
      expect(
        gelesen!['latitude'],
        '52.5200',
        reason:
            'Die Migration ist einmalig - der alte Standort muss unveraendert '
            'im Keystore bleiben.',
      );
    });

    test('ohne Klartext-Eintraege: nichts wird geschrieben', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await SecureLocationStorage.migrateFromSharedPreferences(prefs);

      expect(
        _keystore.containsKey('thestia_loc_lat'),
        isFalse,
        reason: 'Es gab nichts zu migrieren - der Keystore bleibt leer.',
      );
      expect(
        prefs.getBool('thestia_loc_migrated_v1'),
        isTrue,
        reason:
            'Auch ohne Klartext-Daten muss der Marker gesetzt werden - '
            'sonst prueft die App bei jedem Start erneut nach.',
      );
    });

    test('ein Schreibfehler: der Marker bleibt weg, die Migration versucht '
        'es erneut', () async {
      SharedPreferences.setMockInitialValues({
        'verification_latitude': '52.5200',
        'verification_longitude': '13.4050',
      });
      final prefs = await SharedPreferences.getInstance();
      _schreibenSchlaegtFehl = true;

      await SecureLocationStorage.migrateFromSharedPreferences(prefs);

      expect(
        prefs.getBool('thestia_loc_migrated_v1'),
        isNull,
        reason:
            'Nach einem Fehler darf der Marker NICHT gesetzt sein - sonst '
            'waere der Klartext-Standort fuer immer gesperrt.',
      );
      expect(
        prefs.getString('verification_latitude'),
        '52.5200',
        reason:
            'Der Klartext-Eintrag muss erhalten bleiben, damit die '
            'Migration beim naechsten Start erneut laufen kann.',
      );
    });
  });
}
