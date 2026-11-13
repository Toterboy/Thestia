// Test gegen die Enumeration im Transit Spark (Migration 215).
//
// BEFUND (13.11.2026, Sicherheits-Review): Die Kandidatenliste
// (list_transit_candidates) und der Soft-Ping im Empfaenger-Weg
// (send_soft_ping) haben die BESCHREIBUNG vom Client uebernommen, ohne
// sie zu pruefen:
//
//     and (s.tags && coalesce(p_tags, '{}'::text[]) ...)
//
// Der Merkmals-Katalog ist fuer jeden angemeldeten Nutzer lesbar. Wer
// ihn vollstaendig uebergibt, traf damit JEDES aktive Signal - die
// Kandidatenliste lieferte dann alle Personen im 45-Minuten-Fenster mit
// echter user_id, freier Notiz und selbst genanntem Ort, und der Zuwink
// war an beliebige nahe Erwachsene moeglich.
//
// DER TEST: Die Migration 215 muss die Beschreibung aus dem EIGENEN
// Signal des Aufrufers holen und die Client-Argumente nicht mehr
// auswerten. Das ist statisch pruefbar - und genau das ist der Punkt:
// ein Fehler, den erst ein echter Angreifer findet, ist zu teuer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transit Spark: die Beschreibung kommt vom Server', () {
    late String migration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/215_transit_candidate_binding.sql',
      ).readAsStringSync();
    });

    /// Der Rumpf einer Funktion (ohne Kommentare - die erwaehnen alte
    /// Parameternamen nur in der Erklaerung).
    String rumpf(String funktion) {
      final start = migration.indexOf('function public.$funktion');
      expect(
        start,
        greaterThan(-1),
        reason: '$funktion fehlt in der Migration',
      );
      // Es ist der RUMPF, nicht die ganze Funktion: die Parameterliste
      // steht in der Signatur, im Datenbank-Rumpf (`prosrc`) aber nicht.
      // Genau so sieht es der Fail-Fast-Beweis in der Migration.
      final asMarker = migration.indexOf(r'as $$', start);
      expect(
        asMarker,
        greaterThan(start),
        reason: '$funktion ist nicht zu Ende',
      );
      final ende = migration.indexOf('\$\$;', asMarker);
      expect(
        ende,
        greaterThan(asMarker),
        reason: '$funktion ist nicht zu Ende',
      );
      return migration
          .substring(asMarker, ende)
          .replaceAll(RegExp(r'--[^\n]*'), '');
    }

    test('die Kandidatenliste wertet die Client-Argumente nicht aus', () {
      final code = rumpf('list_transit_candidates');
      expect(
        code.contains(RegExp(r'p_tags|p_self_tags')),
        isFalse,
        reason:
            'list_transit_candidates() darf p_tags/p_self_tags nicht mehr '
            'auswerten - damit waere die Enumeration wieder moeglich',
      );
    });

    test(
      'die Kandidatenliste holt die Beschreibung aus dem eigenen Signal',
      () {
        final code = rumpf('list_transit_candidates');
        expect(
          code.contains('v_own_tags'),
          isTrue,
          reason: 'die Beschreibung muss aus dem eigenen Signal kommen',
        );
        expect(code.contains('transit_signals'), isTrue);
        // Und sie muss ohne eigenes Signal leer bleiben.
        expect(code.contains("return '[]'::jsonb"), isTrue);
      },
    );

    test('die Kandidatenliste begrenzt auf 20 (im Inner-Subselect)', () {
      final code = rumpf('list_transit_candidates');
      expect(
        RegExp(r'limit\s+20').hasMatch(code),
        isTrue,
        reason: 'die zugesagte Obergrenze von 20 Kandidaten fehlt',
      );
      // Das Limit muss im Inner-Subselect stehen - hinter einem jsonb_agg
      // ohne GROUP BY begrenzt es nichts. Das Subselect beginnt bei der
      // Klammer nach dem FROM.
      final limit = code.indexOf('limit 20');
      final subselect = code.lastIndexOf('from (');
      expect(limit, greaterThan(-1), reason: 'kein LIMIT gefunden');
      expect(
        limit,
        greaterThan(subselect),
        reason:
            'das LIMIT muss im Inner-Subselect stehen - hinter dem Aggregat '
            'ist es wirkungslos (BEFUND 13.11.2026)',
      );
    });

    test('der Soft-Ping wertet die Client-Argumente nicht aus', () {
      final code = rumpf('send_soft_ping');
      expect(
        code.contains(RegExp(r'p_tags|p_self_tags')),
        isFalse,
        reason:
            'send_soft_ping() darf p_tags/p_self_tags nicht mehr auswerten '
            '- ein Zuwink an eine beliebige nahe Person waere wieder moeglich',
      );
      expect(code.contains('v_own_tags'), isTrue);
    });

    test('die Schutzregeln bleiben erhalten', () {
      for (final funktion in ['list_transit_candidates', 'send_soft_ping']) {
        final code = rumpf(funktion);
        expect(
          code.contains('transit_spark_adult'),
          isTrue,
          reason: '$funktion verliert das 18+-Gate',
        );
        expect(
          code.contains('blocked_users'),
          isTrue,
          reason: '$funktion verliert den Blockierschutz',
        );
      }
    });

    test('die Migration bringt einen Fail-Fast-Beweis mit', () {
      expect(
        migration.contains('Sicherheitscheck fehlgeschlagen'),
        isTrue,
        reason:
            'die Migration muss sich selbst pruefen - eine halb '
            'angekommene Migration waere still falsch',
      );
    });
  });
}
