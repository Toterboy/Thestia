// Die Passkey-Verwaltung: Liste, Loeschen, Umbenennen.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/auth/passkey_auth.dart 85 offene Zeilen. Betroffen war
// vor allem der Teil, der mit dem Server spricht - also genau der Weg,
// den der Nutzer braucht, wenn er auf einem neuen Geraet Passkeys
// wegschaufeln will ("Der Server konnte den Passkey nicht bestaetigen"
// - die Anleitung dafuer steht im Setup-Bildschirm).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Liste der registrierten Passkeys kommt vom Server,
//   * "ist ueberhaupt ein Passkey da?" - und die Regel dahinter: ein
//     FEHLER ist nicht "nein" (sonst wuerde die Einrichtung einen
//     zweiten Passkey anlegen, den der Server dann ablehnt),
//   * ein Passkey laesst sich loeschen (der Weg aus der Sackgasse),
//   * ein Passkey laesst sich umbenennen ("Pixel 8" statt "iCloud
//     Keychain").
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/auth/passkey_auth.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.passkeys.clear();
    server.fehlerAntworten.clear();
  });

  /// Zwei Passkeys auf dem Konto.
  void zweiPasskeys() {
    server.passkeys.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'passkey-1',
        'friendly_name': 'Pixel 8',
        'created_at': '2026-11-01T10:00:00.000Z',
      },
      <String, dynamic>{
        'id': 'passkey-2',
        'friendly_name': 'iCloud Keychain',
        'created_at': '2026-10-01T10:00:00.000Z',
      },
    ]);
  }

  group('Die Liste', () {
    test('kommt vom Server', () async {
      zweiPasskeys();

      final liste = await PasskeyAuth.listRegistered();

      expect(liste.length, 2);
      expect(liste.first.id, 'passkey-1');
      expect(liste.first.friendlyName, 'Pixel 8');
      expect(
        server.pfade.where((p) => p.endsWith('/auth/v1/passkeys')),
        isNotEmpty,
        reason: 'Der Server muss gefragt werden - die Liste steht nur dort.',
      );
    });

    test('ist leer, wenn der Account keine hat', () async {
      final liste = await PasskeyAuth.listRegistered();
      expect(liste, isEmpty);
    });
  });

  group('Die Frage "ist ein Passkey da?"', () {
    test('ja, wenn die Liste nicht leer ist', () async {
      zweiPasskeys();
      expect(await PasskeyAuth.hasRegisteredPasskey(), isTrue);
    });

    test('nein, wenn die Liste leer ist', () async {
      expect(await PasskeyAuth.hasRegisteredPasskey(), isFalse);
    });

    test('nein, wenn der Server nicht antwortet', () async {
      // DER FEHLER IST NICHT "NEIN": Wer hier faelschlich "nein" sagt,
      // legt im Setup einen zweiten Passkey an - den der Server dann
      // ablehnt ("bereits ein Passkey").
      server.fehlerAntworten['/auth/v1/passkeys'] = (
        status: 500,
        body: '{"message":"Serverfehler"}',
      );

      expect(
        await PasskeyAuth.hasRegisteredPasskey(),
        isFalse,
        reason:
            'Der Fehler darf nicht blockieren - der Aufrufer soll trotzdem '
            'registrieren duerfen.',
      );
    });
  });

  group('Das Loeschen', () {
    test('der Aufruf kommt beim Server an', () async {
      zweiPasskeys();

      await PasskeyAuth.delete(passkeyId: 'passkey-1');

      expect(
        server.pfade.where((p) => p.contains('/auth/v1/passkeys/passkey-1')),
        isNotEmpty,
        reason:
            'Der Passkey muss beim Server geloescht werden - nur lokal zu '
            'loeschen wuerde beim naechsten Geraetewechsel wiederkommen.',
      );
    });
  });

  group('Das Umbenennen', () {
    test('der neue Name kommt an', () async {
      zweiPasskeys();
      // DIE ANTWORT: Der Server antwortet mit dem Passkey - so kommt er
      // auch im Bildschirm an.
      server.fehlerAntworten['/auth/v1/passkeys/passkey-1'] = (
        status: 200,
        body:
            '{"id":"passkey-1","friendly_name":"Pixel 8 Pro",'
            '"created_at":"2026-11-01T10:00:00.000Z"}',
      );

      await PasskeyAuth.rename(
        passkeyId: 'passkey-1',
        friendlyName: 'Pixel 8 Pro',
      );

      expect(
        server.pfade.where((p) => p.contains('/auth/v1/passkeys/passkey-1')),
        isNotEmpty,
        reason: 'Der neue Name muss zum Server.',
      );
    });
  });
}
