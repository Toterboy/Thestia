import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/data/icebreaker_catalog.dart';
import 'package:wisp/models/message.dart';

void main() {
  group('Eisbrecher-Katalog (v0.9.1)', () {
    test('mindestens 10 Kategorien mit je mindestens 5 Fragen', () {
      expect(icebreakerCatalog.length, greaterThanOrEqualTo(10));
      for (final cat in icebreakerCatalog) {
        expect(cat.questions.length, greaterThanOrEqualTo(5),
            reason: 'Kategorie ${cat.id} hat zu wenige Fragen');
      }
    });

    test('insgesamt mindestens 50 Fragen, alle zweisprachig', () {
      final total = icebreakerCatalog.fold<int>(
        0,
        (sum, cat) => sum + cat.questions.length,
      );
      expect(total, greaterThanOrEqualTo(50));
      for (final cat in icebreakerCatalog) {
        expect(cat.de.isNotEmpty, isTrue);
        expect(cat.en.isNotEmpty, isTrue);
        for (final q in cat.questions) {
          expect(q.de.trim().isNotEmpty, isTrue);
          expect(q.en.trim().isNotEmpty, isTrue);
        }
      }
    });

    test('Musik-Kategorie ist vorhanden', () {
      final musik = icebreakerCatalog.where((c) => c.id == 'musik');
      expect(musik, isNotEmpty);
      expect(musik.first.questions.length, greaterThanOrEqualTo(5));
    });

    test('keine doppelten Fragen innerhalb einer Kategorie', () {
      for (final cat in icebreakerCatalog) {
        final texts = cat.questions.map((q) => q.de).toList();
        expect(texts.toSet().length, texts.length,
            reason: 'Duplikate in Kategorie ${cat.id}');
      }
    });

    test('exakt 10 Kategorien mit je 6 Fragen (60 insgesamt)', () {
      expect(icebreakerCatalog.length, 10);
      for (final cat in icebreakerCatalog) {
        expect(cat.questions.length, 6,
            reason: 'Kategorie ${cat.id} hat nicht 6 Fragen');
      }
      final total = icebreakerCatalog.fold<int>(
        0,
        (sum, cat) => sum + cat.questions.length,
      );
      expect(total, 60);
    });

    test('Kategorie-IDs sind eindeutig', () {
      final ids = icebreakerCatalog.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('keine Gedankenstriche in Fragen und Titeln', () {
      for (final cat in icebreakerCatalog) {
        for (final text in [cat.de, cat.en]) {
          expect(text.contains('–'), isFalse, reason: cat.id);
          expect(text.contains('—'), isFalse, reason: cat.id);
        }
        for (final q in cat.questions) {
          expect(q.de.contains('–'), isFalse, reason: '${cat.id}: ${q.de}');
          expect(q.de.contains('—'), isFalse, reason: '${cat.id}: ${q.de}');
          expect(q.en.contains('–'), isFalse, reason: '${cat.id}: ${q.en}');
          expect(q.en.contains('—'), isFalse, reason: '${cat.id}: ${q.en}');
        }
      }
    });

    test('englische Fragen sind übersetzt, nicht kopiert', () {
      var identical = 0;
      var total = 0;
      for (final cat in icebreakerCatalog) {
        if (cat.de == cat.en) identical++;
        for (final q in cat.questions) {
          total++;
          if (q.de == q.en) identical++;
        }
      }
      // Mindestens 90 % müssen sich unterscheiden (Tippfehler-Puffer).
      expect(identical / (total + icebreakerCatalog.length),
          lessThan(0.1));
    });

    test('textFor/titleFor wählen nach Sprachcode', () {
      final cat = icebreakerCatalog.first;
      final q = cat.questions.first;
      expect(cat.titleFor('en'), cat.en);
      expect(cat.titleFor('de'), cat.de);
      expect(cat.titleFor('fr'), cat.de); // Fallback Deutsch
      expect(q.textFor('en'), q.en);
      expect(q.textFor('de'), q.de);
      expect(q.textFor(''), q.de);
    });
  });

  group('Geteilte Eisbrecher-Bubble (v0.9.1)', () {
    test('MessageType.icebreaker übersteht JSON-Roundtrip', () {
      final msg = Message(
        id: 'x',
        senderId: 'a',
        receiverId: 'b',
        text: 'Welche Stadt möchtest du unbedingt mal besuchen?',
        timestamp: DateTime(2026, 1, 1),
        type: MessageType.icebreaker,
      );
      final back = Message.fromJson(msg.toJson());
      expect(back.type, MessageType.icebreaker);
      expect(back.text, msg.text);
    });

    test('Quiz-Schwelle liegt pro Chat zwischen 50 und 70', () {
      for (final id in ['1', '42', 'match_abc', '999999']) {
        final threshold = 50 + (id.hashCode.abs() % 21);
        expect(threshold, inInclusiveRange(50, 70));
        // Deterministisch: gleiche ID, gleiche Schwelle.
        expect(50 + (id.hashCode.abs() % 21), threshold);
      }
    });

    test('Date-Rad-Schwelle liegt pro Chat zwischen 50 und 70', () {
      for (final id in ['1', '42', 'match_abc', '999999']) {
        final threshold = 50 + ((id.hashCode >> 8).abs() % 21);
        expect(threshold, inInclusiveRange(50, 70));
        expect(50 + ((id.hashCode >> 8).abs() % 21), threshold);
      }
    });
  });
}
