// "Nachricht fuer alle loeschen" im 1:1-Chat (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Funktion ist eine Anforderung des
// Betreibers (11.11.2026) - und sie ist heikel: wer fremde Nachrichten
// loeschen koennte, waere eine Rechteausweitung.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein langer Druck auf eine EIGENE Textnachricht fragt nach,
//   * "Abbrechen" loescht nicht,
//   * "Fuer alle loeschen" meldet es an den Server UND ersetzt die
//     Nachricht durch den Hinweis,
//   * eine FREMDE Nachricht laesst sich gar nicht erst loeschen.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart - so ist sichtbar, OB der
// Server wirklich angerufen wurde.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/utils/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

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

    // HIVE: die verschluesselten Schluessel (Signal-Protokoll) liegen in
    // Hive-Boxen. Ohne initialisierten Hive schlaegt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_chat');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    server.pfade.clear();
    // DIE EIGENE ID: Ohne sie kennt der Screen seine eigenen Nachrichten
    // nicht (und wuerde sie gar nicht erst zum Loeschen anbieten).
    AppConstants.registerUserIdGetter(() => 'ich');
  });

  /// Baut den Chat mit einem Funke (numerische ID) und zwei Nachrichten.
  ///
  /// Die ID muss eine Zahl sein - nur bei einem echten Funke gibt es
  /// "Fuer alle loeschen" (lokale QR-Kontakte haben keine Server-ID).
  ({ChatNotifier notifier, ChatService service}) chat() {
    final service = ChatService();
    service.restoreMatch('42', 'partner-1', 'Mira');
    service.addMessage(
      '42',
      Message(
        id: 'm_eigen',
        senderId: 'ich',
        receiverId: 'partner-1',
        text: 'Meine eigene Nachricht',
        timestamp: DateTime.now(),
      ),
    );
    service.addMessage(
      '42',
      Message(
        id: 'm_fremd',
        senderId: 'partner-1',
        receiverId: 'ich',
        text: 'Nachricht der Partnerin',
        timestamp: DateTime.now(),
      ),
    );
    return (notifier: ChatNotifier(service), service: service);
  }

  /// Pumpt den Chat.
  Future<void> zeigeScreen(WidgetTester tester, ChatNotifier notifier) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _FakeLocalStorage();
    // Der Hinweis auf den Chat-Hintergrund (v0.10.0) kommt beim ersten
    // Chat - im Test stoert er nur, also ist er als "gesehen" markiert.
    storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final n = ProfileNotifier(storage, _FakeSecureProfileStore());
            n.setProfile(const UserProfile(id: 'ich', name: 'Lena', bio: ''));
            return n;
          }),
          chatProvider.overrideWith((ref) => notifier),
        ],
        child: const MaterialApp(home: ChatDetailScreen(matchId: '42')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Nachricht fuer alle loeschen', () {
    testWidgets('ein langer Druck auf die eigene Nachricht fragt nach', (
      tester,
    ) async {
      final c = chat();
      await zeigeScreen(tester, c.notifier);

      expect(tester.takeException(), isNull);
      expect(find.text('Meine eigene Nachricht'), findsOneWidget);

      // Lang druecken (wie bei Whatsapp).
      await tester.longPress(find.text('Meine eigene Nachricht'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.deleteForAllTitle')),
        findsOneWidget,
      );
    });

    testWidgets('"Abbrechen" loescht nicht', (tester) async {
      final c = chat();
      await zeigeScreen(tester, c.notifier);

      await tester.longPress(find.text('Meine eigene Nachricht'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Die Nachricht steht noch da.
      expect(find.text('Meine eigene Nachricht'), findsOneWidget);
      // Und der Server wurde nicht gefragt.
      expect(
        server.pfade.any((p) => p.contains('delete_message_for_all')),
        isFalse,
      );
    });

    testWidgets('"Fuer alle loeschen" meldet es an den Server', (tester) async {
      final c = chat();
      await zeigeScreen(tester, c.notifier);

      await tester.longPress(find.text('Meine eigene Nachricht'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.text(L10n.tWithoutContext('chat.deleteForAllAction')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich gefragt ...
      expect(
        server.pfade.any((p) => p.contains('delete_message_for_all')),
        isTrue,
        reason: 'Das Loeschen muss dem Server gemeldet werden.',
      );
      // ... und die Nachricht ist durch den Hinweis ersetzt.
      expect(find.text('Meine eigene Nachricht'), findsNothing);
      expect(
        find.text(L10n.tWithoutContext('chat.deletedNotice')),
        findsOneWidget,
      );
    });

    testWidgets('eine fremde Nachricht laesst sich nicht loeschen', (
      tester,
    ) async {
      final c = chat();
      await zeigeScreen(tester, c.notifier);

      // Lang druecken auf die Nachricht der Partnerin: es passiert
      // nichts - fremde Nachrichten sind nicht loeschbar.
      await tester.longPress(find.text('Nachricht der Partnerin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Nachricht der Partnerin'), findsOneWidget);
    });

    testWidgets('die Loeschung des Partners kommt beim Empfaenger an', (
      tester,
    ) async {
      // Der Server meldet, dass eine Nachricht "fuer alle geloescht"
      // wurde - der Empfaenger ersetzt sie durch den Hinweis
      // (BEFUND 11.11.2026).
      server.rpcAntworten['list_message_deletions'] = [
        <String, dynamic>{
          'messageId': 'm_fremd',
          'deletedAt': '2026-11-14T10:00:00Z',
        },
      ];

      final c = chat();
      await zeigeScreen(tester, c.notifier);

      expect(tester.takeException(), isNull);
      // Die Nachricht ist durch den Hinweis ersetzt.
      expect(find.text('Nachricht der Partnerin'), findsNothing);
      expect(
        find.text(L10n.tWithoutContext('chat.deletedNotice')),
        findsOneWidget,
        reason:
            'Der Empfaenger muss sehen, dass die Nachricht geloescht wurde - '
            'sonst denkt er, sie sei noch da.',
      );
    });
  });
}
