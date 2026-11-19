// Der eigene Token muss zum Server - sonst kann kein Match entstehen.
//
// BEFUND (07.11.2026, Betreiber): "Beide Geraete suchen eine Person bei
// Transit Spark (Beide haben gleiche beschreibung und beide haben sich
// gegenseitig blicke getauscht/gefunkt, aber gibt keinen Funken.)"
//
// DIE URSACHE: Das Signal enthielt nur die Tokens der GERAETE, die der
// Absender gesehen hat. Gesucht wurde mit genau diesen - zwei
// Sichtungslisten. Zwei Personen, die nur einander sehen, haben aber
// disjunkte Sichtungslisten: A sieht B, B sieht A, und die Token-Mengen
// haben nichts gemeinsam. Mit genau zwei Geraeten war ein Match
// mathematisch unmoeglich.
//
// DIE LOESUNG: Der eigene Token wird mitgeschickt (Migration 185). Damit
// laesst sich die Frage beantworten, die die Sache ueberhaupt meint:
// "HAT DER ANDERE MICH GESEHEN?" - denn der eigene Token des anderen
// steht in dessen Sichtungsliste, wenn der andere mich gesehen hat.
//
// Diese Datei prueft die CLIENT-Seite. Die Server-Seite prueft der
// Selbsttest in der Migration selbst.

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/supabase_database_service.dart';

void main() {
  group('Transit Spark: der eigene Token (v0.10.0, Migration 185)', () {
    test('Der eigene Token wird mitgeschickt', () {
      final params = SupabaseDatabaseService.buildTransitSparkParams(
        tokens: const ['bbbbbbbbbbbbbbbbbbbb'],
        tags: const ['hair_color:brown', 'hemd:white'],
        mode: 'transit',
        selfTags: const ['hair_color:brown', 'hemd:white'],
        selfNote: 'Hallo',
        selfToken: 'aaaaaaaaaaaaaaaaaaaa',
      );

      expect(
        params['p_self_token'],
        'aaaaaaaaaaaaaaaaaaaa',
        reason:
            'der eigene Token fehlt im Aufruf - ohne ihn kann der '
            'Server keinen Match finden',
      );
    });

    test('Ohne den eigenen Token wird gar nicht erst gesendet', () {
      // Ein Versuch ohne den eigenen Token kann keinen Match finden.
      // Er wuerde den Nutzer mit einem stillen "kein Match" im Glauben
      // lassen, es sei niemand in der Naehe.
      expect(
        () => SupabaseDatabaseService.buildTransitSparkParams(
          tokens: const ['bbbbbbbbbbbbbbbbbbbb'],
          tags: const ['hair_color:brown', 'hemd:white'],
          mode: 'transit',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('transit_own_token_missing'),
          ),
        ),
      );
    });

    test('Ein leerer eigener Token wird auch abgelehnt', () {
      expect(
        () => SupabaseDatabaseService.buildTransitSparkParams(
          tokens: const ['bbbbbbbbbbbbbbbbbbbb'],
          tags: const ['hair_color:brown', 'hemd:white'],
          mode: 'transit',
          selfToken: '   ',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Die uebrigen Parameter bleiben unveraendert', () {
      final params = SupabaseDatabaseService.buildTransitSparkParams(
        tokens: const ['bbbbbbbbbbbbbbbbbbbb'],
        tags: const ['hair_color:brown', 'hemd:white'],
        mode: 'transit',
        selfTags: const ['hair_color:brown'],
        selfNote: '  Hallo  ',
        selfToken: 'aaaaaaaaaaaaaaaaaaaa',
      );

      expect(params['p_tokens'], ['bbbbbbbbbbbbbbbbbbbb']);
      expect(params['p_tags'], ['hair_color:brown', 'hemd:white']);
      expect(params['p_mode'], 'transit');
      expect(params['p_self_tags'], ['hair_color:brown']);
      // Der Hinweis wird getrimmt - wie bisher.
      expect(params['p_self_note'], 'Hallo');
    });
  });
}
