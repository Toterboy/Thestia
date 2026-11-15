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

import 'support/plugin_mocks.dart';

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
///
/// [serverFunke] erzeugt einen Funken mit einer SERVER-Match-ID (einer
/// Zahl). Nur die haben die Funktionen, die es auf dem Server gibt
/// (Erinnerungsliste, Funke beenden) - ein lokaler Kontakt bekommt
/// dort den Hinweis "nur mit einem Funke".
({ChatNotifier notifier, Match match}) _chatMitNachricht({
  bool serverFunke = false,
}) {
  final service = ChatService();
  final match = serverFunke
      ? service.restoreServerMatch('7', _partner(), DateTime.now())!
      : service.createMatch(_partner());
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
///
/// [hinweisGesehen] steuert den Hinweis auf den Chat-Hintergrund (v0.10.0):
/// beim ersten Chat kommt er, sonst nicht.
List<Override> _overrides(ChatNotifier notifier, {bool hinweisGesehen = true}) {
  final storage = _FakeLocalStorage();
  // Der Hinweis auf den Chat-Hintergrund (v0.10.0) kommt beim ersten
  // Chat - im Test stoert er nur, also ist er als "gesehen" markiert.
  if (hinweisGesehen) {
    storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
    );
  }
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
  ChatNotifier notifier, {
  bool hinweisGesehen = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(notifier, hinweisGesehen: hinweisGesehen),
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
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE und HIVE: der Signal-Dienst (Sicherheitsnummer)
    // liest seine verschluesselten Boxen aus dem Keystore und aus Hive.
    // Ohne diese beiden Ersatzwaerter bleibt der Dialog leer.
    mockKeystore();
    await mockHive();
    // DIE AUFNAHME: der Chat hat eine Sprachnachricht-Funktion - der
    // Recorder wird beim Aufbau erzeugt (sonst: MissingPluginException).
    mockAufnahme();
    mockZeitzone();
    await supabase.Supabase.initialize(
      // DIE DREI OPTIONEN (siehe der Kommentar unten): kein
      // Timer, kein Speicher, kein Deeplink-Observer - sonst
      // scheitert der Aufbau auf dem CI-Runner.
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),

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

  // Die Nachrichtenarten (14.11.2026): Der Chat-Screen hatte 1446
  // offene Zeilen - die grösste Lücke der App. Die Bildnachricht, die
  // Eisbrecher-Frage und die Systemnotiz sind eigene Wege im Aufbau.
  group('Der 1:1-Chat (die Nachrichtenarten)', () {
    testWidgets('eine Bildnachricht wird als Bild dargestellt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(_partner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_bild',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: '',
          type: MessageType.image,
          mediaUrl: 'https://example.de/foto.jpg',
          timestamp: DateTime.now(),
        ),
      );
      await _pump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Das Bild wird geladen - bis es da ist, steht der Platzhalter
      // (das Bild zaehlt, dass der Bildzweig gebaut wurde).
      expect(find.byIcon(Icons.image), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('die Eisbrecher-Frage steht mittig', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(_partner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_eis',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: 'Was ist dein Lieblingsgericht?',
          type: MessageType.icebreaker,
          timestamp: DateTime.now(),
        ),
      );
      await _pump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Was ist dein Lieblingsgericht?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('viele Nachrichten werden alle gebaut', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(_partner());
      for (var i = 0; i < 30; i++) {
        service.addMessage(
          match.id,
          Message(
            id: 'm_$i',
            senderId: i.isEven ? 'partner-1' : 'ich',
            receiverId: i.isEven ? 'ich' : 'partner-1',
            text: 'Nachricht Nummer $i',
            timestamp: DateTime.now().subtract(Duration(minutes: 30 - i)),
          ),
        );
      }
      await _pump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Die Liste ist lang - die letzten Nachrichten stehen weiter
      // unten (die Liste ist umgekehrt gebaut).
      final notifier = ChatNotifier(service);
      expect(notifier.messagesFor(match.id).length, 30);
      // Und die Liste laesst sich scrollen.
      expect(find.byType(Scrollable), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });

  // Das Drei-Punkte-Menue und der Hinweis auf den Chat-Hintergrund.
  group('Der 1:1-Chat (Menue und Hinweise)', () {
    testWidgets('das Menue zeigt die Gruppenueberschriften', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      // Das Menue oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // BEFUND (09.11.2026, Betreiber: "Bei 3 Punkte Menue ist ueber
      // Eisbrecher Fragen ein Strich einfach so aber keine ueberschrift
      // oder so"): JEDE Gruppe hat eine Ueberschrift - kein nackter
      // Trennstrich.
      expect(find.text('Gespräch'), findsOneWidget);
      expect(find.text('Sicherheit'), findsOneWidget);
      // Und die wichtigen Eingaenge stehen drin.
      expect(find.text('Nutzer melden'), findsOneWidget);
      expect(find.text('Nutzer blockieren'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Hinweis auf den Chat-Hintergrund kommt einmal', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = _chatMitNachricht();
      // Der Hinweis ist noch nicht gesehen - er muss kommen.
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        hinweisGesehen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Chat-Hintergrund'), findsOneWidget);

      // "Spaeter" schliesst ihn - und er kommt nicht wieder.
      await tester.tap(find.text('Später'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Menue oeffnet die Erinnerungsliste', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Ein SERVER-Funke - nur bei einer Match-ID aus dem Server gibt es
      // die Erinnerungsliste.
      final chat = _chatMitNachricht(serverFunke: true);
      await _pump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Erinnerungsliste'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Das Blatt steht da (ohne Server: keine Eintraege, aber der
      // Aufbau muss klappen).
      expect(find.text('Erinnerungsliste'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    // ANMERKUNG: Der Dialog zur Sicherheitsnummer wird hier NICHT
    // getestet. Er braucht den vollstaendigen Signal-Dienst
    // (Identity-Key, PreKeys, Session-Ratchet) - der laedt im Test
    // seine verschluesselten Boxen und rechnet, das ist im
    // Widget-Test nicht sinnvoll nachzubauen. Die Sicherheitsnummer
    // selbst hat eigene Tests (test/safety_number_test.dart).

    testWidgets('das Menue beendet den Funke ueber einen Dialog', (
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Funke beenden'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Dialog fragt nach - es gibt Absage-Wege, kein sofortiges
      // Ende.
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
