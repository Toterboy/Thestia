// Der Transit-Katalog: Merkmale, Kategorien und die Suche.
//
// ANLASS (19.11.2026): `lib/models/transit/transit_models.dart` war nur zu 40 %
// abgedeckt. Gerade die Suche ist wichtig - der Nutzer tippt "pulli"
// und muss das richtige Merkmal finden.
//
// WAS HIER GEPRÜFT WIRD:
//   * das Ergebnis des Signal-Versands wird richtig gelesen (inkl.
//     leerer Notiz),
//   * die Kategorien sind über ihren Slug auffindbar,
//   * die Suche findet Slugs und Schreibweisen (Aliasse),
//   * die Suche versteht Umlaute ("mütze" findet "mütze"),
//   * ein leerer Suchbegriff liefert den ganzen Katalog.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/transit/transit_models.dart';

void main() {
  group('Das Ergebnis des Signal-Versands', () {
    test('ein Treffer wird richtig gelesen', () {
      final ergebnis = TransitSparkResult.fromJson(<String, dynamic>{
        'matched': true,
        'partner': 'nutzer-7',
        'partnerNote': 'Lass uns treffen',
        'alreadySpark': true,
      });
      expect(ergebnis.matched, isTrue);
      expect(ergebnis.partnerId, 'nutzer-7');
      expect(ergebnis.partnerNote, 'Lass uns treffen');
      expect(ergebnis.alreadySpark, isTrue);
    });

    test('ohne Treffer ist alles leer', () {
      final ergebnis = TransitSparkResult.fromJson(<String, dynamic>{});
      expect(ergebnis.matched, isFalse);
      expect(ergebnis.partnerId, isNull);
      expect(ergebnis.partnerNote, isNull);
      expect(ergebnis.alreadySpark, isFalse);
    });

    test('eine leere Notiz wird zu null (kein leerer Text im Dialog)', () {
      final ergebnis = TransitSparkResult.fromJson(<String, dynamic>{
        'matched': true,
        'partner': 'nutzer-7',
        'partnerNote': '   ',
      });
      expect(ergebnis.partnerNote, isNull);
    });
  });

  group('Die Kategorien der Merkmale', () {
    test('jede Kategorie ist ueber ihren Slug auffindbar', () {
      for (final kategorie in TransitTagCategory.values) {
        expect(
          TransitTagCategory.bySlug(kategorie.slug),
          isNotNull,
          reason: kategorie.slug,
        );
        expect(TransitTagCategory.bySlug(kategorie.slug)!.slug, kategorie.slug);
      }
    });

    test('ein unbekannter Slug liefert null', () {
      expect(TransitTagCategory.bySlug('gibt_es_nicht'), isNull);
    });

    test('die Kategorien haben eindeutige Slugs', () {
      final slugs = TransitTagCategory.values.map((k) => k.slug).toList();
      expect(slugs.toSet().length, slugs.length);
    });
  });

  group('Die Suche im Katalog', () {
    test('ein leerer Suchbegriff liefert den ganzen Katalog', () {
      expect(TransitTag.search('').length, TransitTag.catalog.length);
      expect(TransitTag.search('   ').length, TransitTag.catalog.length);
    });

    test('ein Slug wird gefunden', () {
      final treffer = TransitTag.search('hoodie');
      expect(treffer, isNotEmpty);
      expect(treffer.map((t) => t.slug), contains('hoodie'));
    });

    test('eine Schreibweise aus den Aliasen wird gefunden', () {
      // "t-shirt" ist ein Alias für "tshirt".
      final treffer = TransitTag.search('t-shirt');
      expect(treffer, isNotEmpty);
      expect(treffer.map((t) => t.slug), contains('tshirt'));
    });

    test('die Gross- und Kleinschreibung ist egal', () {
      final klein = TransitTag.search('hoodie');
      final gross = TransitTag.search('HOODIE');
      expect(gross.length, klein.length);
      expect(gross, isNotEmpty);
    });

    test('Umlaute werden umgeschrieben ("muetze" findet "muetze")', () {
      // DER WEG: Der Katalog schreibt die Slugs ohne Umlaute. Wer
      // "mütze" tippt, soll trotzdem finden.
      final treffer = TransitTag.search('mütze');
      expect(treffer, isNotEmpty);
      expect(treffer.map((t) => t.slug), contains('muetze'));
    });

    test('was es nicht gibt, liefert nichts', () {
      expect(TransitTag.search('xyzgibtesnicht'), isEmpty);
    });

    test('jeder Treffer passt zur Suchanfrage', () {
      for (final tag in TransitTag.search('pulli')) {
        final passt =
            tag.slug.toLowerCase().contains('pulli') ||
            tag.searchAliases.any((a) => a.toLowerCase().contains('pulli'));
        expect(passt, isTrue, reason: tag.slug);
      }
    });

    test('die Merkmale einer Kategorie werden gefunden', () {
      final haare = TransitTag.byCategory('hair');
      expect(haare, isNotEmpty);
      for (final tag in haare) {
        expect(tag.category, 'hair');
      }
    });
  });
}
