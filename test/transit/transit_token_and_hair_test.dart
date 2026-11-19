import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/transit_models.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/transit_encounter_service.dart';

/// Tests fuer die strenge Token-Pruefung und die Haarfarben.
///
/// WARUM (06.11.2026, Betreiber): "Android 16 erkennt praktisch
/// unendlich Thestia-Geraete (Es gibt maximal 1 anderes). Es werden
/// immer mehr (aktuell ueber 100 gefunden)."
///
/// Ursache: Die Hersteller-ID 0xFFFF ist die reservierte SIG-Nummer und
/// wird von vielen echten Geraeten benutzt. Die alte Pruefung las "irgendetwas
/// nach dem Marker" als Token - auf Android 16 kam deshalb jedes fremde
/// Bluetooth-Geraet als Thestia-Geraet in den Cache.
void main() {
  group('Das Token', () {
    test('ein erzeugtes Token ist wohlgeformt', () {
      final token = TransitEncounterService.generateToken();
      expect(token.length, TransitEncounterService.tokenLaenge);
      expect(TransitEncounterService.isValidToken(token), isTrue);
    });

    test('eine falsche Laenge wird abgelehnt', () {
      expect(TransitEncounterService.isValidToken('abc'), isFalse);
      expect(TransitEncounterService.isValidToken(''), isFalse);
      expect(
        TransitEncounterService.isValidToken('a' * 21),
        isFalse,
        reason: 'zu lang - das ist kein Token der App',
      );
      expect(
        TransitEncounterService.isValidToken('a' * 19),
        isFalse,
        reason: 'zu kurz - das ist kein Token der App',
      );
    });

    test('keine Hexzeichen werden abgelehnt', () {
      expect(
        TransitEncounterService.isValidToken('z' * 20),
        isFalse,
        reason:
            'fremde Geraete liefern beliebige Bytes - nur Hexzeichen '
            'kann ein Token der App sein',
      );
      expect(
        TransitEncounterService.isValidToken('${'WST1'}${'a' * 16}'),
        isFalse,
        reason: 'der Marker selbst ist kein Token',
      );
    });

    test('ein fremdes Geraet landet NICHT im Cache', () {
      // Das ist der Kern des Befunds: die Zahl "Thestia-Geraete in
      // Reichweite" darf nur echte Thestia-Tokens zaehlen.
      final cache = TransitEncounterService(_Speicher());
      cache.recordEncounter('z' * 20);
      cache.recordEncounter('kurz');
      cache.recordEncounter('');
      expect(
        cache.count,
        0,
        reason:
            'ein fremdes Bluetooth-Geraet wurde als Thestia-Geraet '
            'gezaehlt - genau der Befund vom 06.11.2026',
      );

      cache.recordEncounter(TransitEncounterService.generateToken());
      expect(cache.count, 1);
    });

    test('dasselbe Token wird nur einmal gezaehlt', () {
      final cache = TransitEncounterService(_Speicher());
      final token = TransitEncounterService.generateToken();
      cache.recordEncounter(token);
      cache.recordEncounter(token);
      cache.recordEncounter(token);
      expect(cache.count, 1);
    });
  });

  group('Die Haarfarben', () {
    test('jede Haarfarbe hat eine Farbe fuer die Anzeige', () {
      for (final farbe in TransitTag.hairColors) {
        expect(
          TransitTag.colorSwatch.containsKey(farbe),
          isTrue,
          reason: 'die Haarfarbe $farbe hat keine Anzeigefarbe',
        );
      }
    });

    test('die Haarfarben sind eigenstaendig zur Kleidung', () {
      // Die Merkmale sind eindeutig, weil der MERKMALS-Slug sie trennt:
      // "hair_color:purple" ist etwas anderes als "hemd:purple".
      //
      // Der alte Kommentar behauptete, die Farbe selbst traege ein
      // Praefix im Slug ("haar_black"). Das stimmt nicht (und stimmte
      // nie): die Farb-Slugs sind global und werden von mehreren
      // Merkmalen benutzt - lila ist bei den Haaren und bei der
      // Kleidung dieselbe Farbe.
      expect(
        TransitTag.hairColors.toSet().difference(
          TransitTag.clothingColors.toSet(),
        ),
        isNotEmpty,
        reason:
            'die Haarpalette enthaelt eigene Werte - sonst wuerde ein '
            'schwarzes Hemd mit schwarzem Haar gleichgesetzt',
      );
    });

    test('die ausgefallenen Haarfarben sind dabei (Migration 186)', () {
      // BEFUND (07.11.2026, Betreiber): "Zudem soll bei Haarfarben auch
      // noch sowas wie lila usw. sein."
      for (final farbe in const ['purple', 'pink', 'blue', 'green']) {
        expect(
          TransitTag.hairColors,
          contains(farbe),
          reason: 'die Haarfarbe $farbe fehlt in der Auswahl',
        );
      }
    });

    test('es sind mehr Haarfarben als vor dem 06.11.2026', () {
      // BEFUND: "Es muss mehr Haarfarben zur Auswahl geben." Vorher
      // waren es acht, nach Migration 184 vierzehn, nach Migration 186
      // achtzehn.
      expect(
        TransitTag.hairColors.length,
        greaterThanOrEqualTo(18),
        reason: 'die Haarfarben wurden nicht erweitert',
      );
    });

    test('die Haarfarben haben eindeutige Namen', () {
      expect(
        TransitTag.hairColors.toSet().length,
        TransitTag.hairColors.length,
        reason: 'eine Farbe steht zweimal in der Liste',
      );
    });
  });
}

/// Ein Speicher im Speicher (der echte waere der Keystore).
class _Speicher implements LocalStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';

  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);

  @override
  Future<void> remove(String key) async => map.remove(key);
}
