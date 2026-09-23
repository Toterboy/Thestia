import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/models/personality_type.dart';
import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/models/transit_models.dart';
import 'package:wisp/models/user_mood.dart';

/// Guard-Tests für das L10n-System (v0.9.1-Vollsweep).
///
/// Die Tests parsen `lib/l10n/app_strings.dart` statisch und prüfen:
/// DE/EN-Parität, Platzhalter-Konsistenz, keine Gedankenstriche,
/// kein Mojibake, alle verwendeten Keys definiert, alle
/// Modell-labelKeys abgedeckt.
({Map<String, Set<String>> placeholders, Set<String> keys}) _parseBlock(
  String block,
) {
  final keys = <String>{};
  final placeholders = <String, Set<String>>{};
  // Keys stehen am Zeilenanfang ODER nach "{"/"," (mehrere Keys pro Zeile).
  final keyRe =
      RegExp(r"(?:^|[{,]) *'([A-Za-z0-9_.]+)':", multiLine: true);
  final matches = keyRe.allMatches(block).toList();
  for (var i = 0; i < matches.length; i++) {
    final key = matches[i].group(1)!;
    keys.add(key);
    final start = matches[i].end;
    final end =
        i + 1 < matches.length ? matches[i + 1].start : block.length;
    final region = block.substring(start, end);
    placeholders[key] = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}')
        .allMatches(region)
        .map((m) => m.group(1)!)
        .toSet();
  }
  return (placeholders: placeholders, keys: keys);
}

bool _sameElements(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

Map<String, Map<String, Set<String>>> _loadStrings() {
  final src =
      File('lib/l10n/app_strings.dart').readAsStringSync();
  final deMarker = "  'de': {";
  final enMarker = "  'en': {";
  final deStart = src.indexOf(deMarker);
  final enStart = src.indexOf(enMarker);
  assert(deStart >= 0 && enStart > deStart, 'Locale-Blöcke nicht gefunden');
  // NACH der Marker-Zeile beginnen, sonst wird 'de'/'en' als Key geparst.
  final de = _parseBlock(
      src.substring(src.indexOf('\n', deStart) + 1, enStart));
  final en =
      _parseBlock(src.substring(src.indexOf('\n', enStart) + 1));
  return {'de': de.placeholders, 'en': en.placeholders};
}

/// Alle statischen + dynamischen L10n-Key-Verwendungen in lib/ (ohne
/// app_strings.dart selbst).
Set<String> _usedKeys() {
  final used = <String>{};
  final useRe =
      RegExp(r"L10n\.tf?\(\s*(?:context|ctx)\s*,\s*'([^']+)'");
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('app_strings.dart')) continue;
    final content = entity.readAsStringSync();
    for (final m in useRe.allMatches(content)) {
      used.add(m.group(1)!);
    }
  }
  return used;
}

void main() {
  late Set<String> deKeys;
  late Set<String> enKeys;
  late Map<String, Set<String>> dePlaceholders;
  late Map<String, Set<String>> enPlaceholders;

  setUpAll(() {
    final maps = _loadStrings();
    dePlaceholders = maps['de']!;
    enPlaceholders = maps['en']!;
    deKeys = dePlaceholders.keys.toSet();
    enKeys = enPlaceholders.keys.toSet();
  });

  group('L10n-Parität DE/EN', () {
    test('jede DE-Key existiert auch auf EN', () {
      expect(enKeys, containsAll(deKeys));
    });

    test('keine EN-Überhänge ohne DE', () {
      expect(deKeys, containsAll(enKeys));
    });

    test('Platzhalter sind pro Key in beiden Sprachen identisch', () {
      final problems = <String>[];
      for (final key in deKeys.intersection(enKeys)) {
        // Hinweis: Set-== ist Identität, daher elementweiser Vergleich.
        if (!_sameElements(
            dePlaceholders[key]!, enPlaceholders[key]!)) {
          problems.add(
              '$key: de=${dePlaceholders[key]} en=${enPlaceholders[key]}');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });

  group('L10n-Textqualität', () {
    test('keine Gedankenstriche (– —) in app_strings.dart', () {
      final src =
          File('lib/l10n/app_strings.dart').readAsStringSync();
      expect(src.contains('–'), isFalse);
      expect(src.contains('—'), isFalse);
    });

    test('kein Mojibake (Ã Â als Doppelkodierungs-Reste)', () {
      final src =
          File('lib/l10n/app_strings.dart').readAsStringSync();
      expect(src.contains('Ã'), isFalse, reason: 'U+00C3 gefunden');
      expect(src.contains('Â'), isFalse, reason: 'U+00C2 gefunden');
    });
  });

  group('L10n-Verwendung in lib/', () {
    test('alle statischen Keys sind definiert', () {
      final undefined = _usedKeys()
          .where((k) => !k.contains(r'$'))
          .where((k) => !deKeys.contains(k))
          .toList();
      expect(undefined, isEmpty, reason: undefined.join(', '));
    });

    test('nur bekannte dynamische Key-Familien', () {
      final dynamic =
          _usedKeys().where((k) => k.contains(r'$')).toList();
      final allowed = <String>{
        'chat.goodbye.\${index + 1}',
        'chat.goodbye.\$i',
        'transit.preset.\$key',
        'pt.q\$i',
        'pt.q\${i}a',
        'pt.q\${i}b',
        'pt.label.\$type',
        'pt.desc.\$type',
        'verify.challenge.gesture.\$data',
        'verify.challenge.direction.\$data',
        'verify.challenge.base.\${type.name}',
      };
      final unknown = dynamic
          .where((k) =>
              !allowed.contains(k) && !k.startsWith('transit.preset.\${'))
          .toList();
      expect(unknown, isEmpty, reason: unknown.join(', '));
    });

    test('dynamische Familien sind vollständig abgedeckt', () {
      // Goodbye-Texte 1..4 (end_spark_dialog, index 0..3).
      for (var i = 1; i <= 4; i++) {
        expect(deKeys, contains('chat.goodbye.$i'));
      }
      // Persönlichkeitstest: 10 Fragen mit je a/b-Antwort.
      for (var i = 1; i <= 10; i++) {
        expect(deKeys, contains('pt.q$i'));
        expect(deKeys, contains('pt.q${i}a'));
        expect(deKeys, contains('pt.q${i}b'));
      }
      // MBTI-Typen: Label + Beschreibung je Typ.
      for (final type in PersonalityType.allTypes) {
        expect(deKeys, contains('pt.label.$type'));
        expect(deKeys, contains('pt.desc.$type'));
      }
      // Transit-Presets aus transit_radar_screen (_presets + Fallback).
      for (final preset in ['wave', 'again', 'coffee']) {
        expect(deKeys, contains('transit.preset.$preset'));
      }
      // Challenge-Familien (verification_service, Codes aus
      // generateChallenge).
      for (final base in [
        'speakNumber',
        'makeGesture',
        'turnHead',
        'smile'
      ]) {
        expect(deKeys, contains('verify.challenge.base.$base'));
      }
      for (final gesture in ['tongue', 'blink', 'brows']) {
        expect(deKeys, contains('verify.challenge.gesture.$gesture'));
      }
      for (final direction in ['left_right', 'right_left']) {
        expect(deKeys, contains('verify.challenge.direction.$direction'));
      }
      expect(deKeys, contains('verify.challenge.action.smile'));
    });
  });

  group('Modell-labelKeys sind abgedeckt', () {
    test('ReportType', () {
      for (final t in ReportType.values) {
        expect(deKeys, contains(t.labelKey));
        expect(enKeys, contains(t.labelKey));
      }
    });

    test('Gender + GenderPreference', () {
      for (final g in Gender.values) {
        expect(deKeys, contains(g.labelKey));
      }
      for (final p in GenderPreference.values) {
        expect(deKeys, contains(p.labelKey));
        expect(enKeys, contains(p.labelKey));
      }
    });

    test('Mood', () {
      for (final m in Mood.values) {
        expect(deKeys, contains(m.labelKey));
        expect(enKeys, contains(m.labelKey));
      }
    });

    test('ProfileVisibility', () {
      for (final v in ProfileVisibility.values) {
        expect(deKeys, contains(v.labelKey));
      }
    });

    test('TransitTag-Katalog + Farben + Modi', () {
      for (final tag in TransitTag.catalog) {
        expect(deKeys, contains(tag.labelKey), reason: tag.slug);
      }
      for (final color in TransitTag.colors) {
        expect(deKeys, contains(TransitTag.colorLabelKey(color)),
            reason: color);
      }
      for (final mode in TransitMode.values) {
        expect(deKeys, contains(mode.labelKey));
      }
    });
  });
}
