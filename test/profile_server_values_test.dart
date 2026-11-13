// Regressionstest: die Werte, die der Server kennt (Befund vom 13.11.2026).
//
// BEFUND (Betreiber): "Server Sync schlaegt fehl, wenn ich mein Profil
// anpasse."
//
// DIE URSACHE: Der Profil-Editor schickte `distance_filter_mode` mit dem
// Dart-Enum-Namen `distanceKm`. Die Spalte akzeptiert aber nur
// `distance_km`, `state` oder `germany` (CHECK-Constraint
// `profiles_distance_filter_mode_check`). Ein PostgREST-UPDATE ist
// ATOMAR: EIN verletztes Feld macht das GANZE Update unmoeglich - der
// Nutzer sah "Server-Sync fehlgeschlagen" und KEINE seiner
// Profilaenderungen wurde gespeichert.
//
// ZWEITER FUND DERSELBEN KLASSE: `preferred_state` wird fuer zwei
// Dinge benutzt (Beziehungsform und gewuenschtes Bundesland). Der
// CHECK-Constraint kennt nur die Beziehungswerte - das Bundesland
// "Bremen" faellt durch und hat das Update ebenfalls gekippt.
//
// DIESER TEST haelt beides fest:
//   1. Jeder Wert, den die App schickt, liegt in der DB-Domaene.
//      Die Domaene wird aus den MIGRATIONEN gelesen - nicht hart
//      im Test wiederholt (sonst waere der Test blind fuer
//      Aenderungen am Server).
//   2. Die beiden Stellen, die auf den Server schreiben, benutzen die
//      Abbildungen und nicht die Dart-Namen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/providers/user_preferences_provider.dart';

/// Die erlaubten Werte einer CHECK-Constraint - aus den Migrationen.
Set<String> dbDomain(String constraintName) {
  final muster = RegExp(
    '$constraintName[^;]*?IN\\s*\\(([^)]*)\\)',
    dotAll: true,
  );
  for (final datei in Directory('supabase/migrations').listSync()) {
    if (!datei.path.endsWith('.sql')) continue;
    final text = File(datei.path).readAsStringSync();
    final treffer = muster.firstMatch(text);
    if (treffer == null) continue;
    return RegExp(
      r"'([^']*)'",
    ).allMatches(treffer.group(1)!).map((m) => m.group(1)!).toSet();
  }
  fail(
    'Die CHECK-Constraint $constraintName wurde in keiner Migration gefunden.',
  );
}

/// Der Dart-Code ohne Kommentare (sonst schlaegt der eigene
/// Erklaerungskommentar den Test an).
String codeOhneKommentare(String text) => text
    .split('\n')
    .map((zeile) {
      final index = zeile.indexOf('//');
      return index == -1 ? zeile : zeile.substring(0, index);
    })
    .join('\n');

/// Die beiden Stellen, die in die Spalten `distance_filter_mode` und
/// `preferred_state` schreiben.
const Map<String, String> schreibStellen = {
  'lib/screens/profile/profile_edit_screen.dart': 'Profil-Editor',
  'lib/providers/user_preferences_provider.dart': 'Praeferenz-Provider',
};

void main() {
  group('Die Werte, die der Server kennt', () {
    test('distance_filter_mode: jeder Enum-Wert liegt in der DB-Domaene', () {
      final erlaubt = dbDomain('profiles_distance_filter_mode_check');
      expect(erlaubt, isNotEmpty, reason: 'Domaene nicht gelesen');
      for (final mode in DistanceFilterMode.values) {
        expect(
          erlaubt,
          contains(mode.dbValue),
          reason:
              'Der Wert fuer $mode liegt nicht in der DB-Domaene $erlaubt - '
              'das Update waere komplett gescheitert.',
        );
      }
    });

    test('preferred_state: nur die Beziehungswerte werden geschickt', () {
      final erlaubt = dbDomain('profiles_preferred_state_check');
      expect(erlaubt, isNotEmpty, reason: 'Domaene nicht gelesen');
      expect(dbPreferredState('single'), 'single');
      expect(dbPreferredState('polyamory'), 'polyamory');
      // Ein Bundesland ist KEIN erlaubter Wert - es wird verworfen
      // (und darf das Update nicht kippen).
      for (final bundesland in ['Bremen', 'Berlin', 'Bayern']) {
        expect(
          dbPreferredState(bundesland),
          isNull,
          reason: 'Ein Bundesland darf nicht in preferred_state landen.',
        );
      }
      for (final wert in erlaubt) {
        expect(dbPreferredState(wert), wert);
      }
    });

    test(
      'beide Schreibstellen benutzen die Abbildung (nicht den Enum-Namen)',
      () {
        final treffer = <String>[];
        schreibStellen.forEach((pfad, name) {
          final datei = File(pfad);
          expect(
            datei.existsSync(),
            isTrue,
            reason: '$pfad fehlt - der Test muss angepasst werden.',
          );
          final code = codeOhneKommentare(datei.readAsStringSync());
          // Jeder Schreibvorgang auf `distance_filter_mode` muss die
          // Abbildung benutzen - NICHT den Dart-Enum-Namen
          // (`distanceFilterMode.name` = 'distanceKm'; die Spalte
          // akzeptiert nur 'distance_km', 'state', 'germany').
          for (final m in RegExp(
            r"'distance_filter_mode':(.{0,200})",
            dotAll: true,
          ).allMatches(code)) {
            final teil = m.group(1)!;
            if (!teil.contains('dbValue') && !teil.contains('dbMode')) {
              treffer.add('$name ($pfad): distance_filter_mode ohne dbValue');
            }
          }
          // Und `preferred_state` nur durch dbPreferredState (sonst kippt
          // ein Bundesland das ganze Update).
          for (final m in RegExp(
            r"'preferred_state':(.{0,200})",
            dotAll: true,
          ).allMatches(code)) {
            final teil = m.group(1)!;
            if (!teil.contains('dbPreferredState')) {
              treffer.add(
                '$name ($pfad): preferred_state ohne dbPreferredState',
              );
            }
          }
        });
        expect(
          treffer,
          isEmpty,
          reason:
              'Diese Stellen schicken einen Wert, den der CHECK-Constraint '
              'ablehnt - das GANZE Profil-Update scheitert daran:\n'
              '${treffer.join('\n')}',
        );
      },
    );
  });
}
