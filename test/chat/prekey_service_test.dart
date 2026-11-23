// Der Aufbau der Ende-zu-Ende-Session (PreKey-Bundle).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/prekey_service.dart 61 offene Zeilen bei 18 %
// Abdeckung. Der Dienst holt das Schluessel-Bundle des Partners und baut
// daraus die Session - schlaegt das fehl, kommt keine Nachricht an.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine manipulierte Peer-ID wird abgewiesen (Audit M1: die ID landet
//     im Function-Pfad - ein "../" waere ein Pfad-Angriff),
//   * eine vorhandene Session wird verwendet (kein Bundle-Abruf - sonst
//     ueberschreiben sich die beiden Geraete),
//   * fehlt das Bundle, kommt eine verstaendliche Meldung statt einer
//     nackten Fehlermeldung,
//   * ein Serverfehler nennt den Deploy-Hinweis.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Die Verschluesselung als Ersatz: sie meldet, was der Test will.
class _FakeVerschluesselung extends EncryptionService {
  _FakeVerschluesselung({this.sitzungen = const <String>{}});

  /// Die Peers, mit denen schon eine Session besteht.
  final Set<String> sitzungen;

  /// Die gebauten Sessions (Peer -> TRUE).
  final List<String> gebaut = <String>[];

  @override
  Future<void> get initialized => Future<void>.value();

  @override
  Future<bool> hasSession(String peerId) async => sitzungen.contains(peerId);

  @override
  Future<void> buildSession(
    String peerId,
    String identityKeyPublic,
    String preKeyPublic,
    int preKeyId,
    String signedPreKeyPublic,
    int signedPreKeyId,
    String signedPreKeySignature,
    int registrationId,
  ) async {
    gebaut.add(peerId);
  }
}

/// Eine gueltige Peer-ID (UUID).
const String peerId = '11111111-2222-3333-4444-555555555555';

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
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
    server.fehlerAntworten.clear();
  });

  group('Der Aufbau der Ende-zu-Ende-Session', () {
    test('eine manipulierte Peer-ID wird abgewiesen', () async {
      final dienst = PreKeyService(_FakeVerschluesselung());

      // DER ANGRIFF: Die Peer-ID landet im Function-Pfad. Mit einem
      // "../" koennte ein manipulierter QR-Code aus dem Pfad ausbrechen.
      await expectLater(
        dienst.ensureSession('../../secrets'),
        throwsA(isA<StateError>()),
        reason:
            'Eine Peer-ID, die keine UUID ist, darf nie in den '
            'Function-Pfad - das ist der Pfad-Angriff aus Audit M1.',
      );
      expect(
        server.pfade.any((p) => p.contains('/functions/v1/prekeys')),
        isFalse,
        reason: 'Es darf gar kein Aufruf mit der manipulierten ID rausgehen.',
      );
    });

    test('eine vorhandene Session wird verwendet', () async {
      // DIE SITUATION: Die Session besteht schon (sie kam aus einer
      // empfangenen PreKey-Nachricht). Dann darf der Bundle-Abruf sie
      // NICHT ueberschreiben - sonst verschluesseln die beiden Geraete
      // mit unterschiedlichen Sessions und keine Nachricht kommt an.
      final verschluesselung = _FakeVerschluesselung(sitzungen: {peerId});
      final dienst = PreKeyService(verschluesselung);

      await dienst.ensureSession(peerId);

      expect(
        server.pfade.any((p) => p.contains('/functions/v1/prekeys')),
        isFalse,
        reason: 'Die vorhandene Session muss unangetastet bleiben.',
      );
      expect(verschluesselung.gebaut, isEmpty);
    });

    test('fehlt das Bundle, kommt eine verstaendliche Meldung', () async {
      // DER SERVER: Das Bundle ist noch nicht da (404).
      server.fehlerAntworten['/functions/v1/prekeys/'] = (
        status: 404,
        body: '{"error":"not found"}',
      );
      final dienst = PreKeyService(_FakeVerschluesselung());

      await expectLater(
        dienst.ensureSession(peerId),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'Meldung',
            contains('Schlüssel-Bundle'),
          ),
        ),
        reason:
            'Der Nutzer muss verstehen, was los ist - "PreKey Bundle fuer '
            'X konnte nicht geladen werden (Status: 404)" sagt ihm nichts.',
      );
    });

    test('ein Serverfehler nennt den Deploy-Hinweis', () async {
      // DER SERVERFEHLER: Die Edge Function ist veraltet (500).
      server.fehlerAntworten['/functions/v1/prekeys/'] = (
        status: 500,
        body: '{"error":"kaputt"}',
      );
      final dienst = PreKeyService(_FakeVerschluesselung());

      await expectLater(
        dienst.ensureSession(peerId),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'Meldung',
            contains('prekeys'),
          ),
        ),
        reason:
            'Bei einem 500er liegt es fast immer an der Function - der '
            'Hinweis auf das Deployen muss im Text stehen.',
      );
    });
  });
}
