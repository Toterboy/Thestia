// Der 1:1-Chat OHNE Server (v0.10.1).
//
// WARUM (13.11.2026): Der Chat-Screen ist die groesste Datei der App
// (rund 1.800 Zeilen) - und die Coverage-Messung zeigte: 0,1 %.
// Genau dort sitzt auch die eigene Tastatur (Build 54). Ein Screen, den
// niemand gerendert hat, ist geraten: der Absturz beim Wischen zwischen
// den Reitern (31.10.2026) war nur zufaellig im Screenshot-Render
// aufgefallen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Chat rendert mit seinen Nachrichten (kein Absturz, kein
//     Render-Overflow),
//   * ein Chat, den es nicht mehr gibt, zeigt den Hinweis statt eines
//     leeren Bildschirms,
//   * die EINGABE ist die eigene Tastatur: das Feld ist readOnly (die
//     Systemtastatur sieht nichts) und das Tippen oeffnet die
//     App-Tastatur,
//   * eine getippte Nachricht landet im Chat.
//
// OHNE SERVER: Die Supabase-Aufrufe des Bildschirms (P2P, Relay,
// Loeschen, Herz-Staerken) laufen ueber bestEffort/bestEffortOr und
// brechen ohne Client still ab. Genau das ist hier der Fall - es wird
// geprueft, was der Bildschirm ohne Server macht, nicht was er mit
// Server macht (das macht test/live_message_flow_test.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/match.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/mood_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/widgets/secure_composer.dart';
import 'package:thestia/widgets/secure_keyboard.dart';

/// In-Memory-Implementierung von [LocalStorage] fuer Tests.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

/// Keystore ohne Plugin: liefert kein Profil (wie auf einem frischen
/// Geraet).
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Die eigene Profilseite (als "ich").
UserProfile _eigenesProfil() => UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo',
  birthDate: DateTime(1995, 6, 1),
);

UserProfile _partner() => UserProfile(
  id: 'partner-1',
  name: 'Mira',
  bio: '',
  birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
);

/// Der Dummy-Client, den der Mood-Service braucht (er greift beim
/// Erzeugen auf den Supabase-Client zu).
late supabase.SupabaseClient _moodClient;

/// Baut den Chat mit einem Match und einer Nachricht.
({ChatNotifier notifier, Match match}) _chatMitNachricht() {
  final service = ChatService();
  final match = service.createMatch(_partner());
  service.addMessage(
    match.id,
    Message(
      id: 'm_1',
      senderId: 'partner-1',
      receiverId: 'ich',
      text: 'Hallo, magst du Kaffee?',
      timestamp: DateTime.now(),
    ),
  );
  return (notifier: ChatNotifier(service), match: match);
}

/// Die Overrides: Storage, Profil, Chat und der Mood-Client.
List<Override> _overrides(ChatNotifier notifier) {
  final storage = _FakeLocalStorage();
  // Der Hinweis auf den Chat-Hintergrund (v0.10.0) kommt beim ersten
  // Chat - im Test stoert er nur, also ist er als "gesehen" markiert.
  storage.saveString(
    AppConstants.prefsSettingsKey,
    jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
  );
  return [
    localStorageProvider.overrideWithValue(storage),
    secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
    profileProvider.overrideWith((ref) {
      final notifier = ProfileNotifier(storage, _FakeSecureProfileStore());
      notifier.setProfile(_eigenesProfil());
      return notifier;
    }),
    moodServiceProvider.overrideWithValue(MoodService(_moodClient)),
    chatProvider.overrideWith((ref) => notifier),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Widget kind,
  ChatNotifier notifier,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(notifier),
      child: MaterialApp(theme: ThemeData(useMaterial3: true), home: kind),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client muss initialisiert sein: der Sende-Weg holt
    // ihn ueber den Relay-Service, und `Supabase.instance` wirft ohne
    // Initialisierung eine Assertion. Der Client zeigt auf einen nicht
    // existierenden Server - im Test laufen alle HTTP-Anfragen ins Leere
    // (der Test-Binding liefert 400), und der Sende-Weg ist in
    // bestEffort gekapselt.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
  });

  tearDown(() async {
    // Sonst bleibt der Auto-Refresh-Timer des Clients stehen.
    await _moodClient.dispose();
  });

  group('Der 1:1-Chat (ohne Server)', () {
    testWidgets('rendert die Nachrichten ohne Absturz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(tester.takeException(), isNull);
      // Die Nachricht steht da.
      expect(find.text('Hallo, magst du Kaffee?'), findsOneWidget);
      // Die Name der Partnerin steht in der Kopfzeile.
      expect(find.text('Mira'), findsWidgets);
      // Und die Eingabeleiste ist die eigene Tastatur.
      expect(find.byType(SecureComposer), findsOneWidget);

      // Der Screen muss wieder abgeraeumt werden - sonst bleibt der
      // Relay-Timer stehen und der Test scheitert an "A Timer is still
      // pending".
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ein unbekannter Chat zeigt den Hinweis', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        const ChatDetailScreen(matchId: 'gibt-es-nicht'),
        chat.notifier,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dieser Chat existiert nicht mehr.'), findsOneWidget);
      // Und KEINE Eingabeleiste - es gibt nichts zu schreiben.
      expect(find.byType(SecureComposer), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Eingabefeld gibt der Systemtastatur nichts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      final feld = tester.widget<TextField>(find.byType(TextField));
      // `readOnly` ist der entscheidende Punkt: bei einem readOnly-Feld
      // entsteht auf Android und iOS keine Eingabeverbindung - die
      // Systemtastatur sieht also keinen Buchstaben.
      expect(feld.readOnly, isTrue);
      expect(feld.keyboardType, TextInputType.none);
      expect(feld.enableIMEPersonalizedLearning, isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Tippen oeffnet die eigene Tastatur', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(find.byType(SecureKeyboard), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.byType(SecureKeyboard), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine getippte Nachricht landet im Chat', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      // Die App-Tastatur oeffnen und "Hi" tippen.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('h'));
      await tester.tap(find.text('i'));
      await tester.pump();

      // Senden.
      await tester.tap(find.byIcon(Icons.send));
      // Der Neuaufbau passiert direkt nach dem Hinzufuegen (BEFUND
      // 13.11.2026) - die eigene Nachricht ist also sofort da.
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Die Nachricht steht im Chat - und der Verlauf ist nicht leer.
      expect(find.text('hi'), findsOneWidget);
      final nachrichten = chat.notifier.messagesFor(chat.match.id);
      expect(nachrichten.any((m) => m.text == 'hi'), isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
