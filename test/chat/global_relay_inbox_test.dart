// Der globale Relay-Eingang (die Nachrichten, die ohne offenen Chat
// ankommen).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/chat/global_relay_inbox.dart 60 offene Zeilen.
//
// DER WEG: Der Dienst hat einen Test-Haken (`debugPollOnce`), der
// denselben Weg laeuft wie ein echter Poll-Durchlauf - mit beliebigem
// Fetch-Ergebnis und ohne Supabase. Damit laesst sich die
// Zustellungs-Logik pruefen, ohne den Timer zu brauchen.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Relay-Nachricht landet in der passenden Session,
//   * ein Eisbrecher wird als solcher markiert,
//   * eine Nachricht von einem Unbekannten bleibt liegen (sie wird
//     NICHT quittiert - sonst waere sie weg, ohne dass jemand sie gelesen
//     hat),
//   * ein Fehler beim Abholen streckt das Intervall (sonst pollt der
//     Eingang bei totem Netz dauerhaft alle 6 Sekunden),
//   * im Hintergrund pollt der Eingang nicht, im Vordergrund wieder.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/services/chat/chat_service.dart';
// Der Praefix: 'appInForeground' gibt es auch im Chat-Provider.
import 'package:thestia/services/chat/global_relay_inbox.dart' as relay;
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  late FakeSupabaseServer server;
  late ProviderContainer container;
  late relay.GlobalRelayInbox inbox;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();

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
    server.rpcAufrufe.clear();
    server.rpcAntworten.clear();

    final service = ChatService();
    // EIN MATCH: Die Relay-Nachricht des Partners wird ihm zugeordnet.
    service.createMatch(
      const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
    );

    container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
        chatProvider.overrideWith((ref) => ChatNotifier(service)),
      ],
    );
    inbox = relay.GlobalRelayInbox(container);
  });

  tearDown(() {
    inbox.stop();
    container.dispose();
  });

  /// Eine Relay-Nachricht vom Partner.
  RelayMessage nachricht({
    int id = 1,
    String senderId = 'partner-1',
    String text = 'Hallo aus dem Relay',
    String kind = 'text',
  }) => RelayMessage(
    id: id,
    senderId: senderId,
    text: text,
    kind: kind,
    createdAt: DateTime(2026, 11, 25),
  );

  group('Die Zustellung', () {
    test('eine Nachricht landet in der passenden Session', () async {
      await inbox.debugPollOnce(pending: <RelayMessage>[nachricht()]);

      final nachrichten = container
          .read(chatProvider.notifier)
          .messagesFor(container.read(chatProvider).first.id);
      expect(
        nachrichten.map((m) => m.text),
        contains('Hallo aus dem Relay'),
        reason:
            'Die Relay-Nachricht muss im Chat landen - der Nutzer hat sie '
            'sonst nie gesehen.',
      );
    });

    test('ein Eisbrecher wird als solcher markiert', () async {
      await inbox.debugPollOnce(
        pending: <RelayMessage>[nachricht(kind: 'icebreaker')],
      );

      final nachrichten = container
          .read(chatProvider.notifier)
          .messagesFor(container.read(chatProvider).first.id);
      expect(
        nachrichten.first.type,
        MessageType.icebreaker,
        reason:
            'Ein Eisbrecher wird in der Mitte angezeigt - mit eigenem '
            'Aussehen. Ohne die Markierung saehe er wie eine Nachricht aus.',
      );
    });

    test('eine fremde Nachricht bleibt liegen', () async {
      await inbox.debugPollOnce(
        pending: <RelayMessage>[nachricht(senderId: 'unbekannt')],
      );

      final nachrichten = container
          .read(chatProvider.notifier)
          .messagesFor(container.read(chatProvider).first.id);
      expect(
        nachrichten,
        isEmpty,
        reason:
            'Eine Nachricht von einem Unbekannten gehoert nicht in diesen '
            'Chat - der zustaendige Screen holt sie ab.',
      );
    });
  });

  group('Das Intervall', () {
    test('ein Fehler beim Abholen streckt das Intervall', () async {
      final vorher = inbox.debugBackoffStep;

      await inbox.debugPollOnce(
        pending: <RelayMessage>[],
        throwBeforeHandling: true,
      );

      expect(
        inbox.debugBackoffStep,
        greaterThan(vorher),
        reason:
            'Bei totem Netz muss der Eingang langsamer werden - sonst pollt '
            'er dauerhaft alle 6 Sekunden und produziert Last ohne '
            'Gegenwert.',
      );
    });

    test('eine leere Runde streckt das Intervall ebenfalls', () async {
      final vorher = inbox.debugBackoffStep;

      await inbox.debugPollOnce(pending: <RelayMessage>[]);

      expect(inbox.debugBackoffStep, greaterThan(vorher));
    });
  });

  group('Der Lebenszyklus', () {
    testWidgets('im Vordergrund pollt der Eingang', (tester) async {
      expect(relay.appInForeground(), isTrue);

      inbox.start();
      // Der erste Poll laeuft sofort. Die Test-Uhr muss dabei laufen -
      // ein Future.delayed wartet im Widget-Test ewig.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        server.pfade.where((p) => p.contains('relay')).isNotEmpty,
        isTrue,
        reason:
            'Solange kein Chat offen ist, holt der Eingang die Nachrichten '
            'selbst - sonst kaeme im Chat nichts an.',
      );
      inbox.stop();
    });

    testWidgets('im Hintergrund pollt der Eingang nicht', (tester) async {
      // Der App-Wechsel: Das Fenster geht in den Hintergrund.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));

      inbox.start();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        server.pfade.where((p) => p.contains('relay')),
        isEmpty,
        reason:
            'Im Hintergrund soll der Eingang nicht laufen - das kostet '
            'Akku und bringt nichts, wenn der Bildschirm aus ist.',
      );
      inbox.stop();
    });
  });
}
