import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/data/intro_prompt_catalog.dart';

void main() {
  group('IntroPromptCatalog - Struktur', () {
    test('hat vier Themen (ein Chip-Leiste-Eintrag je Thema)', () {
      expect(IntroPromptCatalog.themes, hasLength(4));
    });

    test('jedes Thema hat drei Prompts, damit Rotation etwas bewirkt', () {
      for (final t in IntroPromptCatalog.themes) {
        expect(t.promptKeys.length, greaterThanOrEqualTo(3),
            reason: 'Thema ${t.id} hat zu wenige Prompts fuer Rotation');
      }
    });

    test('jedes Thema hat mindestens DREI DISTINKTE Keys', () {
      for (final t in IntroPromptCatalog.themes) {
        expect(t.promptKeys.toSet().length, t.promptKeys.length,
            reason: 'Thema ${t.id} hat doppelte Keys - Rotation liefert Lücken');
      }
    });

    test('Themen-IDs sind eindeutig', () {
      final ids = IntroPromptCatalog.themes.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('alle Keys sind global eindeutig', () {
      final all = IntroPromptCatalog.allPromptKeys;
      expect(all.toSet().length, all.length,
          reason: 'doppelte Keys über Themen hinweg');
    });
  });

  group('IntroPromptCatalog - Rotation', () {
    test('liefert pro Thema genau eine Vorgabe', () {
      expect(IntroPromptCatalog.rotated(seed: 0), hasLength(4));
      expect(IntroPromptCatalog.rotated(seed: 7), hasLength(4));
    });

    test('perTheme steigert die Auswahl', () {
      expect(IntroPromptCatalog.rotated(seed: 0, perTheme: 2), hasLength(8));
      expect(IntroPromptCatalog.rotated(seed: 0, perTheme: 3), hasLength(12));
    });

    test('KRITISCH: gleicher Seed -> gleiches Ergebnis (Chips springen nicht)', () {
      // Wenn der Seed pro build neu gewuerfelt wuerde, wuerde der Chip unter
      // dem Finger weiterspringen. Deshalb muss die Funktion bei gleichem
      // Seed exakt dasselbe liefern.
      for (int seed = 0; seed < 50; seed++) {
        expect(IntroPromptCatalog.rotated(seed: seed),
            IntroPromptCatalog.rotated(seed: seed));
      }
    });

    test('rotiert ueber die Seeds', () {
      // Es gibt so viele distinkte Auswahlen wie ein Theme Prompts hat
      // (3). Wichtig ist, dass es MEHR als eine ist.
      final sets = <String>{
        for (int seed = 0; seed < 12; seed++)
          IntroPromptCatalog.rotated(seed: seed).join('|')
      };
      expect(sets.length, greaterThanOrEqualTo(3),
          reason: 'nahezu konstante Auswahl - Rotation wirkungslos');
    });

    test('Themen rotieren NICHT im Gleichtakt', () {
      // Ohne Theme-Offset bekäme man immer "den ersten Prompt aus jedem
      // Thema" - drei Varianten, aber keine echte Mischung.
      final idx = <List<int>>[];
      for (int seed = 0; seed < 6; seed++) {
        final picks = IntroPromptCatalog.rotated(seed: seed);
        final offsets = <int>[];
        for (var t = 0; t < IntroPromptCatalog.themes.length; t++) {
          final keys = IntroPromptCatalog.themes[t].promptKeys;
          offsets.add(keys.indexOf(picks[t]));
        }
        idx.add(offsets);
      }
      // In mindestens einer Auswahl unterscheiden sich die Themen-Indizes.
      final mixed = idx.where((o) => o.toSet().length > 1).length;
      expect(mixed, greaterThan(0),
          reason: 'alle Themen zeigen stets denselben Index - Gleichtakt');
    });

    test('jeder Seed liefert nur Keys, die es wirklich gibt', () {
      final known = IntroPromptCatalog.allPromptKeys.toSet();
      for (int seed = 0; seed < 30; seed++) {
        for (final k in IntroPromptCatalog.rotated(seed: seed)) {
          expect(known, contains(k));
        }
      }
    });

    test('perTheme 0 ergibt leere Liste statt Absturz', () {
      expect(IntroPromptCatalog.rotated(seed: 3, perTheme: 0), isEmpty);
    });
  });

  group('IntroPromptCatalog - Seed', () {
    test('seedFor wechselt ueber den Tag', () {
      final a = IntroPromptCatalog.seedFor(DateTime(2026, 9, 26, 9));
      final b = IntroPromptCatalog.seedFor(DateTime(2026, 9, 27, 9));
      expect(a, isNot(b));
    });

    test('seedFor ist stabil innerhalb derselben Stunde', () {
      final a = IntroPromptCatalog.seedFor(DateTime(2026, 9, 26, 14, 5));
      final b = IntroPromptCatalog.seedFor(DateTime(2026, 9, 26, 14, 58));
      expect(a, b);
    });

    test('seedFor wechselt ueber die Stunde (Thema wandert mit)', () {
      final a = IntroPromptCatalog.seedFor(DateTime(2026, 9, 26, 14));
      final b = IntroPromptCatalog.seedFor(DateTime(2026, 9, 26, 15));
      expect(a, isNot(b));
    });

    test('seedFor bleibt im gueltigen Bereich fuer alle Themen', () {
      for (int d = 1; d <= 28; d++) {
        final s = IntroPromptCatalog.seedFor(DateTime(2026, 9, d, 12));
        expect(s, greaterThanOrEqualTo(0));
        final keys = IntroPromptCatalog.rotated(seed: s);
        expect(keys, hasLength(4));
      }
    });
  });

  group('L10n-Parität: jeder Prompt existiert in DE und EN', () {
    // Die Maps werden wie in test/l10n_test.dart statisch geparst: es gibt
    // keine Laufzeit-API `t(key, sprache)` - `L10n.t` braucht einen
    // BuildContext.
    //
    // WICHTIG: der Datei-Read passiert INNERHALB des Test-Bodys. Ein Read
    // schon bei der Gruppendeklaration wirft in flutter_test ein
    // OutsideTestException.
    ({String de, String en}) readBlocks() {
      final src = File('lib/l10n/app_strings.dart').readAsStringSync();
      final deIdx = src.indexOf("'de': {");
      final enIdx = src.indexOf("'en': {");
      expect(deIdx, greaterThan(0), reason: "Marker 'de' nicht gefunden");
      expect(enIdx, greaterThan(deIdx), reason: "Marker 'en' nicht gefunden");
      return (de: src.substring(deIdx, enIdx), en: src.substring(enIdx));
    }

    String valueOf(String block, String key) {
      final m = RegExp("'$key':\\s*'([^']*)'").firstMatch(block);
      return m?.group(1) ?? '';
    }

    test('alle Katalog-Keys sind in DE definiert', () {
      final b = readBlocks();
      for (final key in IntroPromptCatalog.allPromptKeys) {
        expect(b.de.contains("'$key':"), isTrue, reason: 'DE fehlt: $key');
      }
    });

    test('alle Katalog-Keys sind in EN definiert', () {
      final b = readBlocks();
      for (final key in IntroPromptCatalog.allPromptKeys) {
        expect(b.en.contains("'$key':"), isTrue, reason: 'EN fehlt: $key');
      }
    });

    test('DE-Texte sind nicht leer und nicht identisch mit EN', () {
      final b = readBlocks();
      for (final key in IntroPromptCatalog.allPromptKeys) {
        expect(valueOf(b.de, key), isNotEmpty, reason: 'DE leer: $key');
        expect(valueOf(b.en, key), isNotEmpty, reason: 'EN leer: $key');
        expect(valueOf(b.de, key), isNot(valueOf(b.en, key)),
            reason: 'DE == EN bei $key');
      }
    });

    test('die vier Alt-Prompts aus 0.9.0 sind weiterhin enthalten', () {
      for (final key in const [
        'intro.prompt.weekend',
        'intro.prompt.friends',
        'intro.prompt.laugh',
        'intro.prompt.dream',
      ]) {
        expect(IntroPromptCatalog.allPromptKeys, contains(key));
      }
    });
  });
}
