// Die Einstellung "Nachricht überdenken" - das Modell (26.11.2026).
//
// WAS HIER GEPRÜFT WIRD:
//   * der Modus kommt aus dem gespeicherten Text zurück (und ein
//     unbekannter Text bedeutet "aus" - kein Absturz),
//   * die Ausnahme für einen Kontakt schlägt den globalen Wert,
//   * der Dialog kommt nur, wenn er soll: nie bei "aus", immer bei
//     "immer", ab der Schwelle bei "ab Zeichen" und nie bei "manuell"
//     (dort fragt nur der Extra-Knopf).
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/settings/nachricht_ueberdenken.dart';

void main() {
  group('Der Modus', () {
    test('roundet über den gespeicherten Text', () {
      for (final modus in NachrichtPruefModus.values) {
        expect(NachrichtPruefModusWert.ausWert(modus.wert), modus);
      }
    });

    test('ein unbekannter Text bedeutet "aus"', () {
      expect(
        NachrichtPruefModusWert.ausWert('gibtesnicht'),
        NachrichtPruefModus.aus,
      );
      expect(NachrichtPruefModusWert.ausWert(null), NachrichtPruefModus.aus);
    });
  });

  group('Die Einstellung', () {
    const aus = NachrichtPruefEinstellung();
    const immer = NachrichtPruefEinstellung(modus: NachrichtPruefModus.immer);
    const abZeichen = NachrichtPruefEinstellung(
      modus: NachrichtPruefModus.abZeichen,
      schwelle: 250,
    );
    const manuell = NachrichtPruefEinstellung(
      modus: NachrichtPruefModus.manuell,
    );

    test('ohne Einstellung wird nicht nachgefragt', () {
      expect(aus.prueftNach('Hallo', 'kontakt-1'), isFalse);
      // Auch bei einer langen Nachricht nicht.
      expect(aus.prueftNach('x' * 500, 'kontakt-1'), isFalse);
    });

    test('bei "immer" wird immer nachgefragt', () {
      expect(immer.prueftNach('Hallo', 'kontakt-1'), isTrue);
      expect(immer.prueftNach('x' * 500, 'kontakt-1'), isTrue);
    });

    test('bei "ab Zeichen" erst ab der Schwelle', () {
      expect(abZeichen.prueftNach('x' * 249, 'kontakt-1'), isFalse);
      expect(abZeichen.prueftNach('x' * 250, 'kontakt-1'), isTrue);
      expect(abZeichen.prueftNach('x' * 251, 'kontakt-1'), isTrue);
    });

    test('bei "manuell" fragt nur der Extra-Knopf', () {
      expect(manuell.prueftNach('Hallo', 'kontakt-1'), isFalse);
      expect(manuell.prueftNach('x' * 500, 'kontakt-1'), isFalse);
    });

    test('die Ausnahme für den Kontakt schlägt den globalen Wert', () {
      const einstellung = NachrichtPruefEinstellung(
        modus: NachrichtPruefModus.immer,
        ausnahmen: <String, NachrichtPruefModus>{
          'kontakt-2': NachrichtPruefModus.aus,
        },
      );
      // Für alle anderen Kontakte gilt der globale Wert.
      expect(einstellung.modusFuer('kontakt-1'), NachrichtPruefModus.immer);
      expect(einstellung.prueftNach('Hallo', 'kontakt-1'), isTrue);
      // Für den Kontakt mit der Ausnahme gilt die Ausnahme.
      expect(einstellung.modusFuer('kontakt-2'), NachrichtPruefModus.aus);
      expect(einstellung.prueftNach('Hallo', 'kontakt-2'), isFalse);
    });

    test('der Extra-Knopf steht nur da, wenn er etwas zu tun hat', () {
      expect(aus.zeigtKnopf('kontakt-1'), isFalse);
      expect(immer.zeigtKnopf('kontakt-1'), isFalse);
      expect(abZeichen.zeigtKnopf('kontakt-1'), isTrue);
      expect(manuell.zeigtKnopf('kontakt-1'), isTrue);
    });
  });
}
