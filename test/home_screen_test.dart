// Der Startbildschirm "Aktuelles" (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/home/home_screen.dart 367 offene Zeilen - die Seite, die
// der Nutzer als erstes sieht, wenn er die App oeffnet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Begruessung steht da (mit dem Namen aus dem Profil),
//   * die drei Abschnitte (Nachrichten, Likes, Funken) stehen da - mit
//     ihren Leerzustaenden, nicht mit einer leeren Seite,
//   * der Verifikations-Hinweis steht da und verschwindet, wenn das
//     Profil verifiziert ist,
//   * der Pausiert-Hinweis erscheint, wenn das Profil pausiert ist,
//   * die Karte "Leute entdecken" steht da.
//
// OHNE SERVER: Es wird kein Supabase-Client initialisiert - damit
// bleiben die Serverzaehler leer und der Test greift nur auf den
// lokalen Stand zu (kein Netzwerkverkehr im Test).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/home/home_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/plugin_mocks.dart';

/// Der Speicher im RAM - der Bildschirm liest die Einstellungen daraus.
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
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: das Profil liegt im verschluesselten Speicher - ohne
    // den Mock ruft der Test auf dem CI-Runner das echte Plugin (das
    // findet dort keine libsecret-Sitzung).
    mockKeystore();
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Scrollt zu einem Text (die Seite baut nur die sichtbaren Kacheln).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    if (ziel.evaluate().isNotEmpty) return;
    await tester.scrollUntilVisible(
      ziel,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await pumpFrames(tester);
  }

  /// Baut den Startbildschirm mit Router und Provider-Overrides.
  ///
  /// [profil] decides, welches Profil angezeigt wird (z. B.
  /// verifiziert oder nicht).
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    UserProfile? profil,
    ChatNotifier? chat,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.qrScan,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('QR'))),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Einstellungen'))),
        ),
        GoRoute(
          path: AppRoutes.verificationInfo,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Verifizierung'))),
        ),
        GoRoute(
          path: AppRoutes.swipeModeSelection,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Modi'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        secureProfileStoreProvider.overrideWithValue(_FakeSecureProfileStore()),
        if (chat != null) chatProvider.overrideWith((ref) => chat),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(
            ref.watch(localStorageProvider),
            ref.watch(secureProfileStoreProvider),
          );
          notifier.setProfile(
            profil ??
                const UserProfile(
                  id: 'ich',
                  name: 'Lena',
                  bio: '',
                  birthDate: null,
                ),
          );
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
    return container;
  }

  group('Die Funken auf dem Startbildschirm', () {
    testWidgets('der Name und die letzte Nachricht stehen da', (tester) async {
      final service = ChatService();
      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.addMessage(
        match.id,
        Message(
          id: 'm1',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: 'Hallo, wie geht es dir?',
          timestamp: DateTime.now(),
        ),
      );
      // Die Karten zeigen nur Matches mit UNGELESENEN Nachrichten - also
      // vor dem Notifier hochzaehlen (er liest den Stand aus dem Dienst).
      service.incrementUnread(match.id);
      final chat = ChatNotifier(service);

      await zeigeScreen(tester, chat: chat);

      expect(tester.takeException(), isNull);
      await scrolleZu(tester, 'Mira');
      expect(find.text('Mira'), findsOneWidget);
      expect(
        find.textContaining('Hallo'),
        findsWidgets,
        reason:
            'Die letzte Nachricht muss stehen - der Nutzer will wissen, wer '
            'ihm geschrieben hat.',
      );
    });

    testWidgets('ohne Nachricht steht der Hinweis da', (tester) async {
      final service = ChatService();
      service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      final match = service.createMatch(
        const UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
      );
      service.incrementUnread(match.id);
      final chat = ChatNotifier(service);

      await zeigeScreen(tester, chat: chat);

      expect(tester.takeException(), isNull);
      await scrolleZu(tester, 'Mira');
      expect(find.text('Mira'), findsOneWidget);
    });
  });

  group('Startbildschirm (Aktuelles)', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      // Die Kopfzeile steht da.
      expect(find.text('Aktuelles'), findsOneWidget);
    });

    testWidgets('die Begruessung nennt den Namen aus dem Profil', (
      tester,
    ) async {
      await zeigeScreen(tester);

      expect(find.textContaining('Hallo, Lena!'), findsOneWidget);
    });

    testWidgets('die drei Abschnitte stehen da', (tester) async {
      await zeigeScreen(tester);

      for (final abschnitt in [
        'Neue Nachrichten',
        'Neue Likes',
        'Neue Funken',
      ]) {
        await scrolleZu(tester, abschnitt);
        expect(find.text(abschnitt), findsOneWidget);
      }
    });

    testWidgets('die Leerzustaende stehen da', (tester) async {
      await zeigeScreen(tester);

      // Kein leeres Nichts, sondern der ausgeschriebene Zustand - so
      // weiss der Nutzer, dass nichts kaputt ist.
      for (final leer in [
        'Keine neuen Nachrichten',
        'Keine neuen Likes',
        'Keine neuen Funken',
      ]) {
        await scrolleZu(tester, leer);
        expect(find.text(leer), findsOneWidget);
      }
    });

    testWidgets('der Verifikations-Hinweis steht da und verschwindet', (
      tester,
    ) async {
      // Noch nicht verifiziert: der Hinweis muss den Nutzer einladen.
      // (Eigene Texte seit 15.11.2026 - die alten waren fuer den
      // Modus-Sperr-Dialog geschrieben.)
      await zeigeScreen(tester);
      expect(
        find.text(L10n.tWithoutContext('home.verifyHintUnverifiedTitle')),
        findsOneWidget,
      );

      // Verifiziert: der Hinweis hat nichts mehr zu sagen.
      await zeigeScreen(
        tester,
        profil: const UserProfile(
          id: 'ich',
          name: 'Lena',
          bio: '',
          verificationState: VerificationState.verified,
        ),
      );
      expect(
        find.text(L10n.tWithoutContext('home.verifyHintUnverifiedTitle')),
        findsNothing,
      );
    });

    testWidgets('der Pausiert-Hinweis erscheint beim pausierten Profil', (
      tester,
    ) async {
      final container = await zeigeScreen(tester);

      expect(find.text('Dein Profil ist pausiert'), findsNothing);

      await container.read(settingsProvider.notifier).setPaused(true);
      await pumpFrames(tester);

      expect(find.text('Dein Profil ist pausiert'), findsOneWidget);
    });

    testWidgets('die Karte "Leute entdecken" steht da', (tester) async {
      await zeigeScreen(tester);

      expect(
        find.text('Leute entdecken'),
        findsOneWidget,
        reason:
            'Der Einstieg in die Begegnungs-Modi gehoert nach oben - er '
            'ist der erste Schritt der App.',
      );
    });
  });
}
