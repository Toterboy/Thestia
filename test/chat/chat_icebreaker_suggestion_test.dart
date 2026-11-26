// Der Eisbrecher-Vorschlag im 1:1-Chat (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/chat_detail_screen.dart 1.264 offene Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * nach fünf Minuten Stille kommt EIN Vorschlag (Nutzerwunsch:
//     "Icebreaker-Vorschlag an beide nach 5 Minuten ohne Nachricht"),
//   * hat der Nutzer schon geschrieben, kommt KEIN Vorschlag,
//   * der Vorschlag kommt nur EINMAL je Funke (nicht bei jedem
//     Öffnen) - sonst nervt er.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/data/icebreaker_catalog.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Schlüssel, unter dem die bereits vorgeschlagenen Funke stehen.
const String _vorgeschlagenKey = 'icebreaker_suggested_chats';

/// Der Speicher im RAM - der Vorschlag merkt sich seine Merkliste.
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

/// Der P2P-Service ohne WebRTC.
///
/// DER GRUND (15.11.2026): Die echte Direktverbindung braucht das
/// WebRTC-Plugin - im Test gibt es kein Gerät. Ohne diesen Ersatz
/// bleibt `connect()` im EventChannel des Plugins HANGEN, und damit
/// auch der ganze Bootstrap des Chat-Bildschirms (Relay-Abruf,
/// Partnerprofil, Eisbrecher-Vorschlag).
class _FakeP2PChatService extends P2PChatService {
  _FakeP2PChatService(super.webrtc, super.prekey);

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    // Nichts tun - es gibt keine Direktverbindung im Test.
  }

  @override
  Future<void> dispose() async {
    // Der echte Aufräumen würde das WebRTC-Plugin brauchen.
  }
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
    await mockHive();
    // DIE AUFNAHME: der Chat hat eine Sprachnachricht-Funktion - der
    // Recorder wird beim Aufbau erzeugt (sonst: MissingPluginException).
    mockAufnahme();
    mockZeitzone();

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

    // ANGEMELDET: Die eigene User-ID kommt aus der Sitzung - ohne sie
    // kennt der Chat nicht, was von mir kommt (und der Vorschlag
    // würde gar nicht erst starten).
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  /// Baut den Chat mit einem Funke und einer Nachricht.
  ///
  /// [eigeneNachricht] entscheidet, ob der Nutzer schon geschrieben hat
  /// (dann gibt es keinen Vorschlag). [bereitsVorgeschlagen] legt den
  /// Funke in die Merkliste - dann bleibt der Vorschlag aus, weil er
  /// für diesen Funke schon kam.
  Future<_FakeLocalStorage> zeigeChat(
    WidgetTester tester, {
    bool eigeneNachricht = false,
    bool bereitsVorgeschlagen = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _FakeLocalStorage();

    // Der Hinweis auf den Chat-Hintergrund kommt beim ersten Chat - im
    // Test stört er nur, also ist er als "gesehen" markiert (sonst
    // steht ein Dialog im Weg).
    await storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
    );

    final service = ChatService();
    final match = service.createMatch(
      const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
    );
    service.addMessage(
      match.id,
      Message(
        id: eigeneNachricht ? 'm_eigen' : 'm_fremd',
        senderId: eigeneNachricht ? 'ich' : 'partner-1',
        receiverId: eigeneNachricht ? 'partner-1' : 'ich',
        text: 'Hallo',
        timestamp: DateTime.now(),
      ),
    );

    // Die Merkliste muss VOR dem Aufbau stehen: der Screen liest sie
    // direkt beim Öffnen (nicht erst nach fünf Minuten).
    if (bereitsVorgeschlagen) {
      await storage.saveString(
        _vorgeschlagenKey,
        jsonEncode(<String>[match.id]),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            notifier.setProfile(
              const UserProfile(id: 'ich', name: 'Lena', bio: ''),
            );
            return notifier;
          }),
          chatProvider.overrideWith((ref) => ChatNotifier(service)),
          p2pChatServiceProvider.overrideWith((ref) {
            final dienst = _FakeP2PChatService(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            );
            ref.onDispose(dienst.dispose);
            return dienst;
          }),
        ],
        child: MaterialApp(home: ChatDetailScreen(matchId: match.id)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return storage;
  }

  group('Der Eisbrecher-Vorschlag', () {
    testWidgets('nach fuenf Minuten Stille kommt ein Vorschlag', (
      tester,
    ) async {
      await zeigeChat(tester);

      expect(tester.takeException(), isNull);
      // Vorher ist kein Dialog da.
      expect(find.byType(AlertDialog), findsNothing);

      // Fünf Minuten Stille. Der Bootstrap des Bildschirms braucht
      // echte Zeit (Hive-Zugriff) - deshalb erst das kurz warten, dann
      // die Zeit vorspulen. Sonst startet der Timer erst NACH dem
      // Zeitsprung.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      // Fünf Minuten Stille: Der Timer des Vorschlags startet, sobald
      // der Bildschirm fertig aufgebaut ist (das dauert echte Zeit -
      // Hive-Zugriff). Deshalb wird abwechselnd echte Zeit gegeben und
      // die Uhr vorgespult.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(minutes: 1));
        if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      }
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.icebreakerSuggestTitle')),
        findsOneWidget,
      );
      // Der Inhalt ist eine echte Frage aus dem Katalog.
      final fragen = [
        for (final c in icebreakerCatalog)
          ...c.questions.map((q) => q.textFor('de')),
        for (final c in icebreakerCatalog)
          ...c.questions.map((q) => q.textFor('en')),
      ];
      expect(
        fragen.any((f) => find.textContaining(f).evaluate().isNotEmpty),
        isTrue,
        reason: 'Der Vorschlag muss eine Frage aus dem Katalog sein.',
      );
    });

    testWidgets('wer selbst geschrieben hat, bekommt keinen Vorschlag', (
      tester,
    ) async {
      await zeigeChat(tester, eigeneNachricht: true);

      await tester.pump(const Duration(minutes: 5));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Wer schon geschrieben hat, braucht keinen Eisbrecher - das '
            'Gespräch laeuft.',
      );
    });

    testWidgets('der Vorschlag kommt nur einmal je Funke', (tester) async {
      await zeigeChat(tester, bereitsVorgeschlagen: true);

      await tester.pump(const Duration(minutes: 5));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Ein zweiter Vorschlag im selben Funke wuerde nerven - er '
            'kommt einmal.',
      );
    });
  });
}
