// Die Funken-Liste gegen den echten Server (BEFUND 20.11.2026,
// Betreiber: "Die Funken beim Interessen-Screen können nicht geladen
// werden").
//
// DIE URSACHE: Der Aufruf von list_my_matches_with_state() antwortete
// mit HTTP 405 ("cannot execute INSERT in a read-only transaction").
// Die Funktion war STABLE und schrieb dabei (über den Rate-Limit-
// Zähler) in die Datenbank - PostgREST fährt STABLE-Aufrufe in
// einer READ-ONLY-Transaktion aus.
//
// WARUM DIESER TEST LIVE LÄUFT: Der Fehler ist im Quelltext nicht zu
// sehen. Die Funktion sah richtig aus, die Migrationen waren grün,
// die Unit-Tests kannten den Server nicht. Nur ein Aufruf gegen das
// echte System zeigt ihn.
//
// DER TEST LIEFERT KEINE TESTDATEN: Er liest nur. Er braucht eine
// echte Sitzung für ein Testkonto und ruft die RPC genau so auf, wie
// die App es tut.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/live_test_support.dart';

void main() {
  test('die Funken-Liste laesst sich laden (kein HTTP 405)', () async {
    final env = envLesen();
    if (!liveTestsLaufen(env)) {
      markTestSkipped(
        'Ohne Schluessel (oder THESTIA_SKIP_LIVE_TESTS=1) laeuft der '
        'Live-Test nicht - es wurde nichts geprueft.',
      );
      return;
    }

    final client = http.Client();
    addTearDown(client.close);

    final token = await sitzung(env, kontoA, client);
    expect(
      token,
      isNotNull,
      reason: 'Ohne Sitzung fuer das Testkonto wurde nichts geprueft.',
    );

    final antwort = await rpc(
      env,
      client,
      'list_my_matches_with_state',
      <String, dynamic>{},
      token!,
    );

    expect(
      antwort.statusCode,
      200,
      reason:
          'Die Funken-Liste muss antworten. HTTP ${antwort.statusCode} '
          'bedeutet: ${antwort.body}',
    );

    // Die Antwort ist eine Liste von Funken - und parsebar.
    final roh = jsonDecode(antwort.body);
    expect(roh, isA<List<dynamic>>());
    for (final eintrag in roh as List<dynamic>) {
      final funke = eintrag as Map<String, dynamic>;
      expect(funke['matchId'], isA<int>());
      expect(funke['status'], isA<String>());
    }
  });

  test('die Entfernung laesst sich abfragen (kein HTTP 405)', () async {
    final env = envLesen();
    if (!liveTestsLaufen(env)) {
      markTestSkipped(
        'Ohne Schluessel (oder THESTIA_SKIP_LIVE_TESTS=1) laeuft der '
        'Live-Test nicht - es wurde nichts geprueft.',
      );
      return;
    }

    final client = http.Client();
    addTearDown(client.close);

    final token = await sitzung(env, kontoA, client);
    expect(token, isNotNull);

    // Dieselbe Funktion, die auch die Funken-Liste aufruft - sie war
    // aus demselben Grund kaputt (Migration 221).
    final antwort = await rpc(
      env,
      client,
      'profile_distance_km',
      <String, dynamic>{'p_other': kontoB},
      token!,
    );

    expect(
      antwort.statusCode,
      200,
      reason:
          'Die Entfernung muss antworten (null ist erlaubt - ohne '
          'Koordinaten gibt es keine). HTTP ${antwort.statusCode} '
          'bedeutet: ${antwort.body}',
    );
  });
}
