// Die ICE-Konfiguration des WebRTC-Dienstes - der Abruf war ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/webrtc_service.dart 262 offene Zeilen. Der Abruf der
// ICE-Konfiguration ist der erste Schritt jeder Direktverbindung - und
// er ist genau der Teil, der im August 2026 schon einmal kaputt war
// (401, weil der Aufruf im PostgREST-Pfad landete).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Konfiguration kommt von der Edge Function,
//   * sie wird gecacht (der Aufruf laeuft nicht bei jedem Versuch),
//   * ohne Session / bei einem Fehler kommt die Ersatzliste (P2P bleibt
//     moeglich - die Verbindung darf nicht daran sterben).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der HTTP-Ersatz: er antwortet mit einer festen Antwort.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._antwort);

  final http.Response Function(http.Request anfrage) _antwort;

  /// Die Anfragen, die ankamen (in der Reihenfolge).
  final List<http.Request> anfragen = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final anfrage = request as http.Request;
    anfragen.add(anfrage);
    final antwort = _antwort(anfrage);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(antwort.body)),
      antwort.statusCode,
      headers: antwort.headers,
      request: anfrage,
    );
  }
}

void main() {
  /// Der Ersatz-Server (die Session des Nutzers).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() async {
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  /// Die Antwort der Edge Function.
  http.Response antwortOk(String body) => http.Response(
    body,
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  group('Die ICE-Konfiguration', () {
    test('kommt von der Edge Function', () async {
      final client = _FakeHttpClient(
        (_) => antwortOk(
          '{"iceServers":[{"urls":"stun:stun.example.com:3478"}],'
          '"ttlSeconds":3600}',
        ),
      );
      final service = WebRTCService(EncryptionService(), httpClient: client);

      final servers = await service.resolveIceServers();

      expect(servers, hasLength(1));
      expect(servers.first['urls'], 'stun:stun.example.com:3478');
      // Der Aufruf ging an die Edge Function (nicht in den PostgREST-Pfad -
      // genau dafuer gab es schon einmal eine 401).
      expect(client.anfragen, hasLength(1));
      expect(
        client.anfragen.first.url.path,
        endsWith('/functions/v1/ice-config'),
        reason:
            'Der Aufruf muss an die Edge Function gehen - im PostgREST-Pfad '
            'wurde er mit 401 abgelehnt.',
      );
      expect(
        client.anfragen.first.headers['Authorization'],
        startsWith('Bearer '),
        reason: 'Die Edge Function braucht das Session-Token.',
      );
    });

    test('wird gecacht (kein zweiter Aufruf)', () async {
      final client = _FakeHttpClient(
        (_) => antwortOk(
          '{"iceServers":[{"urls":"stun:stun.example.com:3478"}],'
          '"ttlSeconds":3600}',
        ),
      );
      final service = WebRTCService(EncryptionService(), httpClient: client);

      await service.resolveIceServers();
      await service.resolveIceServers();

      expect(
        client.anfragen,
        hasLength(1),
        reason:
            'Die Konfiguration wird gecacht - sonst fragt der Client bei '
            'jedem Verbindungsversuch den Server.',
      );
    });

    test('ohne Session kommt die Ersatzliste', () async {
      // Die Session weg: der Aufruf kann nicht laufen.
      await supabase.Supabase.instance.client.auth.signOut();
      final client = _FakeHttpClient((_) => antwortOk('{}'));
      final service = WebRTCService(EncryptionService(), httpClient: client);

      final servers = await service.resolveIceServers();

      expect(
        servers,
        isNotEmpty,
        reason:
            'Ohne ICE-Konfiguration muss die App trotzdem verbinden koennen '
            '- die Ersatzliste rettet den Aufbau.',
      );
      expect(client.anfragen, isEmpty);
    });

    test('bei einem Serverfehler kommt die Ersatzliste', () async {
      final client = _FakeHttpClient((_) => http.Response('Fehler', 500));
      final service = WebRTCService(EncryptionService(), httpClient: client);

      final servers = await service.resolveIceServers();

      expect(servers, isNotEmpty);
    });

    test('bei kaputter Antwort kommt die Ersatzliste', () async {
      final client = _FakeHttpClient((_) => antwortOk('kein-json'));
      final service = WebRTCService(EncryptionService(), httpClient: client);

      final servers = await service.resolveIceServers();

      expect(servers, isNotEmpty);
    });

    test('eine leere Serverliste kommt die Ersatzliste', () async {
      final client = _FakeHttpClient(
        (_) => antwortOk('{"iceServers":[],"ttlSeconds":3600}'),
      );
      final service = WebRTCService(EncryptionService(), httpClient: client);

      final servers = await service.resolveIceServers();

      expect(servers, isNotEmpty);
    });
  });

  group('Das Ende des Dienstes', () {
    test('dispose ohne Verbindung ist ein No-op (kein Crash)', () async {
      final service = WebRTCService(EncryptionService());
      await service.dispose();
      expect(service.isConnected, isFalse);
      expect(service.hasSignalingChannel, isFalse);
    });
  });
}
