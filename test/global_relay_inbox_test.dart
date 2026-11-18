// Der globale Relay-Eingang - die Zustellung war ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/global_relay_inbox.dart 117 offene Zeilen bei 128 Zeilen
// gesamt. Der Eingang ist DER Weg, ueber den eine Nachricht im
// Hintergrund bei einem Nutzer ankommt, der gerade keinen Chat offen
// hat.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Nachricht von einem bekannten Partner landet im richtigen Chat,
//   * sie wird quittiert (also vom Relay geloescht - sonst kommt sie
//     doppelt an),
//   * eine Nachricht von einem Unbekannten bleibt liegen (sie gehoert
//     einem Dating-Hour-Chat, den der Bildschirm selbst holt),
//   * ein Server-Funke, dessen lokales Match fehlt, wird wiederhergestellt
//     (BEfund vom 09.11.2026: "Nachrichten kommen nicht richtig an"),
//   * der Nutzer bekommt eine Benachrichtigung.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/match.dart' as model;
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/global_relay_inbox.dart';
import 'package:thestia/services/relay_service.dart' show RelayMessage;

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Der Ref-Ersatz: er reicht die Abfragen an den Container weiter.
class _FakeRef {
  _FakeRef(this._container);

  final ProviderContainer _container;

  T read<T>(Object provider) {
    // Der Notifier kommt als Objekt (nicht als Anbieter) - der Container
    // hat ihn mit dem Ersatz-Notifier beliefert.
    if (provider is ChatNotifier) return provider as T;
    return _container.read(provider as ProviderListenable<T>);
  }
}

void main() {
  /// Der Ersatz-Server.
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
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  /// Baut den Chat mit einem Match und den Eingang dazu.
  ({ProviderContainer container, ChatNotifier notifier, model.Match match})
  baueEingang() {
    final service = ChatService();
    final match = service.createMatch(
      const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
    );
    final notifier = ChatNotifier(service);
    final container = ProviderContainer(
      overrides: <Override>[chatProvider.overrideWith((ref) => notifier)],
    );
    addTearDown(container.dispose);
    // Das Element erzeugen - erst dann gibt es den Notifier.
    container.read(chatProvider);
    return (container: container, notifier: notifier, match: match);
  }

  /// Eine Relay-Nachricht.
  RelayMessage nachricht({int id = 1, String sender = 'partner-1'}) =>
      RelayMessage(
        id: id,
        senderId: sender,
        text: 'Hallo',
        kind: 'text',
        createdAt: DateTime.now(),
      );

  group('Der globale Relay-Eingang', () {
    test('eine Nachricht von einem bekannten Partner landet im Chat', () async {
      final chat = baueEingang();
      final inbox = GlobalRelayInbox(_FakeRef(chat.container));

      await inbox.debugPollOnce(pending: [nachricht()]);

      // Die Nachricht ist im Chat.
      final nachrichten = chat.notifier.messagesFor(chat.match.id);
      expect(
        nachrichten.any((m) => m.text == 'Hallo'),
        isTrue,
        reason:
            'Die Nachricht muss im Chat landen - der Nutzer sieht sie sonst '
            'nicht.',
      );
      // Und sie ist quittiert (sonst kommt sie immer wieder).
      final acks = server.rpcAufrufe.where((c) => c['funktion'] == 'relay_ack');
      expect(acks, isNotEmpty, reason: 'Die Zeile muss quittiert werden.');
      expect(acks.first['p_ids'], contains(1));
    });

    test('eine Nachricht von einem Unbekannten bleibt liegen', () async {
      final chat = baueEingang();
      final inbox = GlobalRelayInbox(_FakeRef(chat.container));

      await inbox.debugPollOnce(pending: [nachricht(sender: 'fremd-1')]);

      // Kein Chat bekommen...
      final nachrichten = chat.notifier.messagesFor(chat.match.id);
      expect(nachrichten.any((m) => m.text == 'Hallo'), isFalse);
      // ...und nichts quittiert (die Zeile gehoert einem anderen Chat).
      expect(
        server.rpcAufrufe.where((c) => c['funktion'] == 'relay_ack'),
        isEmpty,
        reason:
            'Eine fremde Zeile darf NICHT quittiert werden - sonst geht sie '
            'verloren.',
      );
    });

    test('der Nutzer bekommt eine Benachrichtigung', () async {
      final chat = baueEingang();
      final inbox = GlobalRelayInbox(_FakeRef(chat.container));

      // DER HAKEN: Der App-Wurzel setzt ihn (der Dienst hat kein WidgetRef).
      String? titel;
      String? koerper;
      GlobalRelayInbox.notifier =
          ({
            required int id,
            String? title,
            required String body,
            required String senderId,
          }) async {
            titel = title;
            koerper = body;
          };
      addTearDown(() => GlobalRelayInbox.notifier = null);

      await inbox.debugPollOnce(pending: [nachricht()]);

      expect(titel, 'Mira', reason: 'Die Benachrichtigung nennt den Namen.');
      expect(koerper, 'Hallo');
    });

    test('ein Server-Funke wird wiederhergestellt', () async {
      final chat = baueEingang();
      // Der Server kennt einen Funke, dessen lokales Match fehlt.
      server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[
        <String, dynamic>{
          'matchId': 7,
          'status': 'active',
          'createdAt': DateTime.now().toIso8601String(),
          'profile': <String, dynamic>{
            'id': 'partner-2',
            'name': 'Toni',
            'bio': 'Mag Musik',
          },
        },
      ];

      final inbox = GlobalRelayInbox(_FakeRef(chat.container));

      await inbox.debugPollOnce(
        pending: [nachricht(id: 5, sender: 'partner-2')],
      );

      // Der Funke wurde lokal wiederhergestellt...
      expect(
        chat.notifier.state.any((m) => m.id == '7'),
        isTrue,
        reason:
            'Der Server-Funke muss lokal wiederhergestellt werden - sonst '
            'bleibt die Nachricht unsichtbar.',
      );
      // ...und die Nachricht ist angekommen.
      final nachrichten = chat.notifier.messagesFor('7');
      expect(nachrichten.any((m) => m.text == 'Hallo'), isTrue);
      // Und quittiert.
      expect(
        server.rpcAufrufe.where((c) => c['funktion'] == 'relay_ack'),
        isNotEmpty,
      );
    });

    test('ohne passende Zuordnung bleibt die Zeile liegen', () async {
      final chat = baueEingang();
      final inbox = GlobalRelayInbox(_FakeRef(chat.container));

      // Der Server kennt keinen Funken -> nichts zu routen.
      server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[];

      await inbox.debugPollOnce(pending: [nachricht(sender: 'fremd-2')]);

      expect(
        server.rpcAufrufe.where((c) => c['funktion'] == 'relay_ack'),
        isEmpty,
      );
    });
  });
}
