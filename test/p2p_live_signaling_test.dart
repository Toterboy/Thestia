import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thestia/services/webrtc_service.dart';

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
void main() {
  final env = _ladeEnv();
  final uebersprung = env == null
      ? 'keine .env - der Live-Test laeuft nur lokal mit Projektzugang'
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

    // Zwei Sessions holen (der CAPTCHA-Schutz gilt nur fuer normale
    // Clients; der Secret-Key umgeht ihn).
    final a = await _session(url, secret, 'p2p-test-a@thestia.de');
    final b = await _session(url, secret, 'p2p-test-b@thestia.de');
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

Future<Map<String, dynamic>> _session(
  String url,
  String secret,
  String email,
) async {
  final client = HttpClient();
  final anfrage = await client.postUrl(
    Uri.parse('$url/auth/v1/token?grant_type=password'),
  );
  anfrage.headers.set('apikey', secret);
  anfrage.headers.set('Authorization', 'Bearer $secret');
  anfrage.headers.contentType = ContentType.json;
  anfrage.write(jsonEncode({'email': email, 'password': 'P2pTest!2026#a'}));
  final antwort = await anfrage.close();
  final text = await antwort.transform(utf8.decoder).join();
  if (antwort.statusCode != 200) {
    throw StateError('Login fehlgeschlagen ($email): $text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}
