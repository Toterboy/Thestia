import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thestia/services/webrtc_service.dart';

import 'support/live_test_support.dart' show liveTestsLaufen;

/// LIVE-TEST gegen das echte Supabase-Realtime.
///
/// WARUM (06.11.2026): Der P2P-Bug war, dass das realtime_client die
/// Broadcast-HÜLLE liefert und die App die Nutzlast las. Der
/// Unit-Test [webrtc_signaling_broadcast_test.dart] belegt die Form -
/// aber gegen eine NACHGESTELLTE Nachricht.
///
/// Dieser Test geht auf den ECHTEN Server: zwei Clients (die beiden
/// Testkonten), ein privater Kanal, eine echte Broadcast-Nachricht.
/// Damit ist belegt, dass die Hülle auf dem Server genauso aussieht
/// wie im Paket-Test - und dass [WebRTCService.unwrapBroadcast] sie
/// richtig auspackt.
///
/// DER TEST LÄUFT NUR, WENN .env DA IST: Er braucht das echte Projekt
/// (Zugangsdaten, zwei Konten, Netz). Ohne .env wird er übersprungen -
/// die CI bleibt davon unberührt.
///
/// UND NUR, WENN DIE ZWEI KONTEN EXISTIEREN (06.11.2026): Der Betreiber
/// hat die Testkonten gelöscht lassen (sie sollten nicht dauerhaft auf
/// dem Produktivsystem liegen). Ohne sie würde der Test fehlschlagen und
/// jeden lokalen Testlauf rot machen - das ist ein Testaufbau-Problem,
/// kein Befund. Deshalb überspringt er in dem Fall mit einer klaren
/// Meldung.
///
/// WIE MAN IHN WIEDER AKTIVIERT: Zwei Konten anlegen und ihre Daten in
/// die .env schreiben:
///
///   P2P_TEST_EMAIL_A=...
///   P2P_TEST_EMAIL_B=...
///   P2P_TEST_PASSWORD=...
///
/// Ohne diese drei Eintraege werden die alten Adressen
/// p2p-test-a@thestia.de / p2p-test-b@thestia.de benutzt.
void main() {
  final env = _ladeEnv();
  // BEFUND (13.11.2026): Der Test sprang nur ueber, wenn es gar keine
  // .env gab. Nach der Wiederherstellung der .env (mit Werten, aber ohne
  // den Secret-Key) lief er und scheiterte. Er braucht echte Schluessel
  // UND darf sich abschalten lassen (THESTIA_SKIP_LIVE_TESTS) - wie die
  // beiden anderen Live-Tests.
  final uebersprung =
      (env == null ||
          !liveTestsLaufen(env) ||
          (env['SUPABASE_SECRET_KEY_NEW'] ?? '').trim().isEmpty)
      ? 'keine Schluessel (oder THESTIA_SKIP_LIVE_TESTS) - der Live-Test '
            'laeuft nur lokal mit Projektzugang'
      : null;

  test('die Broadcast-Nachricht kommt beim Peer in der Huelle an', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Das Test-Binding ersetzt HttpClient durch einen Mock, der immer
    // 400 liefert. Fuer diesen Live-Test brauchen wir das echte HTTP -
    // deshalb den Override wieder entfernen.
    HttpOverrides.global = null;
    final e = env!;
    final url = e['SUPABASE_URL']!;
    final key = e['SUPABASE_PUBLISHABLE_KEY']!;
    final secret = e['SUPABASE_SECRET_KEY_NEW']!;
    final emailA = e['P2P_TEST_EMAIL_A'] ?? 'p2p-test-a@thestia.de';
    final emailB = e['P2P_TEST_EMAIL_B'] ?? 'p2p-test-b@thestia.de';
    final passwort = e['P2P_TEST_PASSWORD'] ?? 'P2pTest2026_a';

    // Zwei Sessions holen (der CAPTCHA-Schutz gilt nur fuer normale
    // Clients; der Secret-Key umgeht ihn).
    final a = await _session(url, secret, emailA, passwort);
    if (a == null) {
      markTestSkipped(
        'das Testkonto $emailA ist nicht vorhanden oder das Passwort '
        'stimmt nicht - der Live-Test braucht zwei existierende Konten '
        '(siehe Kommentar oben)',
      );
      return;
    }
    final b = await _session(url, secret, emailB, passwort);
    if (b == null) {
      markTestSkipped(
        'das Testkonto $emailB ist nicht vorhanden oder das Passwort '
        'stimmt nicht - der Live-Test braucht zwei existierende Konten '
        '(siehe Kommentar oben)',
      );
      return;
    }
    final idA = a['user']['id'] as String;
    final idB = b['user']['id'] as String;

    final clientA = SupabaseClient(url, key);
    final clientB = SupabaseClient(url, key);
    await clientA.auth.setSession(
      a['refresh_token'] as String,
      accessToken: a['access_token'] as String,
    );
    await clientB.auth.setSession(
      b['refresh_token'] as String,
      accessToken: b['access_token'] as String,
    );

    // Der private Signaling-Kanal - genau wie in der App.
    final ids = [idA, idB]..sort();
    final topic = 'signaling:${ids[0]}:${ids[1]}';
    final channelA = clientA.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true, self: true),
    );
    final channelB = clientB.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true, self: true),
    );

    final empfangen = Completer<Map<String, dynamic>>();
    channelB.onBroadcast(
      event: 'signal',
      callback: (payload) {
        if (!empfangen.isCompleted) {
          empfangen.complete(Map<String, dynamic>.from(payload));
        }
      },
    );

    var statusA = 'offen';
    var statusB = 'offen';
    final joinA = Completer<String>();
    final joinB = Completer<String>();
    channelA.subscribe((status, error) {
      statusA = '${status.name}${error != null ? ' ($error)' : ''}';
      if (!joinA.isCompleted) joinA.complete(statusA);
    });
    channelB.subscribe((status, error) {
      statusB = '${status.name}${error != null ? ' ($error)' : ''}';
      if (!joinB.isCompleted) joinB.complete(statusB);
    });

    // WICHTIG (wie in der App, webrtc_service.dart:341-351): Der Socket
    // braucht das User-JWT im Join-Payload. Ohne setAuth bleibt der
    // ANON-Key stehen, der Join wird gegen die 'to authenticated'-
    // Policy abgelehnt und der Kanal bleibt zu.
    await clientA.realtime.setAuth(a['access_token'] as String);
    await clientB.realtime.setAuth(b['access_token'] as String);

    // Warten, bis BEIDE wirklich gejoint sind. Sonst geht die
    // Broadcast-Nachricht raus, bevor der Empfaenger im Kanal ist -
    // genau das war die Fehlerquelle in diesem Test.
    await joinA.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('A ist nicht gejoint: $statusA'),
    );
    await joinB.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('B ist nicht gejoint: $statusB'),
    );

    // A sendet die Nachricht - so wie die App es tut.
    await channelA.sendBroadcastMessage(
      event: 'signal',
      payload: {'kind': 'relay-ping', 'from': idA},
    );

    final roh = await empfangen.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError(
        'keine Broadcast-Nachricht erhalten (A: $statusA, B: $statusB)',
      ),
    );

    // Die echte Form, wie sie vom Server ankommt.
    // ignore: avoid_print
    print('LIVE: die empfangene Nachricht: $roh');

    // 1) Der Realtime-Client hat 'type' mit 'broadcast' ueberschrieben.
    //    Genau darum benutzt die App 'kind' fuer ihre Nachrichtenart:
    //    'type' waere beim Empfaenger IMMER 'broadcast'.
    expect(roh['type'], 'broadcast');
    expect(roh['event'], 'signal');

    // 2) Die eigene Nachrichtenart und der Absender kommen unveraendert
    //    an - 'kind' und 'from' fasst der Client nicht an.
    expect(roh['kind'], 'relay-ping');
    expect(roh['from'], idA);

    await channelA.unsubscribe();
    await channelB.unsubscribe();
    await clientA.dispose();
    await clientB.dispose();
  }, skip: uebersprung);
}

Map<String, String>? _ladeEnv() {
  final datei = File('.env');
  if (!datei.existsSync()) return null;
  final werte = <String, String>{};
  for (final zeile in datei.readAsLinesSync()) {
    if (zeile.contains('=') && !zeile.trimLeft().startsWith('#')) {
      final teile = zeile.split('=');
      werte[teile.first.trim()] = teile.sublist(1).join('=').trim();
    }
  }
  if (werte['SUPABASE_URL'] == null ||
      werte['SUPABASE_PUBLISHABLE_KEY'] == null ||
      werte['SUPABASE_SECRET_KEY_NEW'] == null) {
    return null;
  }
  return werte;
}

/// Holt eine Session fuer das Testkonto.
///
/// Gibt null zurueck, wenn das Konto nicht existiert oder das Passwort
/// nicht stimmt - das ist ein Testaufbau-Problem (der Test ueberspringt
/// dann) und kein Fehler der App. Jeder andere Fehler (Netz, Server)
/// wirft - das IST ein Befund.
Future<Map<String, dynamic>?> _session(
  String url,
  String secret,
  String email,
  String passwort,
) async {
  final client = HttpClient();
  final anfrage = await client.postUrl(
    Uri.parse('$url/auth/v1/token?grant_type=password'),
  );
  anfrage.headers.set('apikey', secret);
  anfrage.headers.set('Authorization', 'Bearer $secret');
  anfrage.headers.contentType = ContentType.json;
  anfrage.write(jsonEncode({'email': email, 'password': passwort}));
  final antwort = await anfrage.close();
  final text = await antwort.transform(utf8.decoder).join();
  if (antwort.statusCode == 200) {
    return jsonDecode(text) as Map<String, dynamic>;
  }
  if (antwort.statusCode == 400 && text.contains('invalid_credentials')) {
    // Das Konto gibt es nicht (oder das Passwort ist falsch).
    return null;
  }
  throw StateError('Login fehlgeschlagen ($email): $text');
}
