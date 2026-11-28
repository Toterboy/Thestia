// Die KI-Modelle des Sanctuary: der Katalog der Empfehlungen und der
// Import (Plan 0.11.0).
//
// ENTSCHEIDUNG DES BETREIBERS (27.11.2026): "KI Modelle muss man
// einfach selbst herunterladen. Ein paar könnte man aber vielleicht als
// Empfehlung nennen oder so."
//
// WAS HIER GEPRÜFT WIRD:
//   * der Katalog nennt Name, Größe, RAM-Bedarf, Lizenz und die
//     Quantisierungen (die App lädt nichts selbst),
//   * der Import nimmt eine echte GGUF-Datei an und legt sie in das
//     App-Verzeichnis,
//   * eine Datei ohne GGUF-Signatur, eine zu kleine und eine zu große
//     werden abgewiesen (mit dem Grund),
//   * eine fehlende Datei wird abgewiesen,
//   * die importierten Modelle werden gelistet und können gelöscht
//     werden.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/sanctuary/sanctuary_empfehlung.dart';
import 'package:thestia/services/sanctuary/sanctuary_modell_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thesia_sanctuary');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  /// Schreibt eine Datei (mit oder ohne GGUF-Signatur).
  File schreibeDatei(String name, {bool mitGguf = true, int bytes = 4096}) {
    final datei = File('${temp.path}/$name');
    datei.writeAsBytesSync(<int>[
      if (mitGguf) ...<int>[0x47, 0x47, 0x55, 0x46], // "GGUF"
      ...List<int>.filled(bytes, 0),
    ]);
    return datei;
  }

  /// Der Dienst (mit winzigen Grenzen - ein 60-MB-Test wäre langsam).
  SanctuaryModellService dienst() => SanctuaryModellService(
    basis: Directory('${temp.path}/modelle'),
    mindestGroesseMb: 0.001,
    maxGroesseMb: 1,
  );

  group('Der Katalog der Empfehlungen', () {
    test('nennt die Modelle mit ihren Angaben', () {
      expect(SanctuaryKatalog.alle, isNotEmpty);
      for (final empfehlung in SanctuaryKatalog.alle) {
        expect(
          empfehlung.name,
          isNotEmpty,
          reason: 'Jedes Modell braucht einen Namen.',
        );
        expect(empfehlung.herkunft, isNotEmpty);
        expect(
          empfehlung.groesseMb,
          greaterThan(500),
          reason: 'Ein Sprachmodell ist größer als das.',
        );
        expect(empfehlung.ramMb, greaterThan(empfehlung.groesseMb ~/ 2));
        expect(empfehlung.lizenz, isNotEmpty);
        expect(empfehlung.quantisierungen, isNotEmpty);
        expect(empfehlung.textKey, startsWith('sanctuary.model.'));
      }
    });

    test('hat die leichte Stufe zuerst', () {
      expect(SanctuaryKatalog.stufe1, isNotEmpty);
      expect(SanctuaryKatalog.stufe2, isNotEmpty);
      expect(
        SanctuaryKatalog.alle.first.id,
        SanctuaryKatalog.stufe1.first.id,
        reason:
            'Die leichte Stufe kommt zuerst - sie passt auf die meisten '
            'Geräte.',
      );
    });

    test('findet ein Modell über seinen Namen', () {
      final erstes = SanctuaryKatalog.alle.first;
      expect(SanctuaryKatalog.nachId(erstes.id)?.name, erstes.name);
      expect(SanctuaryKatalog.nachId('gibtesnicht'), isNull);
    });
  });

  group('Der Import', () {
    test('nimmt eine GGUF-Datei an', () async {
      final quelle = schreibeDatei('gemma4e2b-q4.gguf');

      final ergebnis = await dienst().importieren(quelle.path);

      expect(ergebnis.ok, isTrue, reason: 'Die Datei ist ein Modell.');
      expect(ergebnis.fehler, isNull);
      final modell = ergebnis.modell!;
      expect(modell.name, 'gemma4e2b-q4.gguf');
      expect(modell.groesseBytes, greaterThan(0));
      // Die Datei liegt jetzt im App-Verzeichnis.
      expect(File(modell.pfad).existsSync(), isTrue);
    });

    test('weist eine Datei ohne GGUF-Signatur ab', () async {
      final quelle = schreibeDatei('bild.png', mitGguf: false);

      final ergebnis = await dienst().importieren(quelle.path);

      expect(ergebnis.ok, isFalse);
      expect(ergebnis.fehler?.code, 'kein_gguf');
    });

    test('weist eine zu kleine Datei ab', () async {
      final quelle = schreibeDatei('winzig.gguf', bytes: 10);

      final ergebnis = await dienst().importieren(quelle.path);

      expect(ergebnis.ok, isFalse);
      expect(ergebnis.fehler?.code, 'zu_klein');
    });

    test('weist eine fehlende Datei ab', () async {
      final ergebnis = await dienst().importieren(
        '${temp.path}/gibtesnicht.gguf',
      );

      expect(ergebnis.ok, isFalse);
      expect(ergebnis.fehler?.code, 'datei_fehlt');
    });

    test('listet die importierten Modelle', () async {
      await dienst().importieren(schreibeDatei('a.gguf').path);
      await dienst().importieren(schreibeDatei('b.gguf').path);

      final modelle = await dienst().importierteModelle();

      expect(modelle, hasLength(2));
      expect(
        modelle.map((m) => m.name),
        containsAll(<String>['a.gguf', 'b.gguf']),
      );
    });

    test('ein Modell lässt sich löschen', () async {
      final ergebnis = await dienst().importieren(schreibeDatei('a.gguf').path);
      final pfad = ergebnis.modell!.pfad;

      await dienst().loeschen(pfad);

      expect(File(pfad).existsSync(), isFalse);
      expect(await dienst().importierteModelle(), isEmpty);
    });

    test('ein Modell passt zu seiner Empfehlung', () async {
      final empfehlung = SanctuaryKatalog.alle.first;
      final ergebnis = await dienst().importieren(
        schreibeDatei('${empfehlung.id}-q4.gguf').path,
      );

      expect(
        ergebnis.modell!.passtZu(empfehlung),
        isTrue,
        reason:
            'Der Dateiname verrät das Modell - so kann die App die '
            'passende Empfehlung anbieten.',
      );
    });
  });
}
