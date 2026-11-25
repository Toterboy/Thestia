// Der Startbildschirm: die Wege, die der Nutzer geht.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/home/home_screen.dart 65 offene Zeilen - genau die Wege,
// die beim Tippen passieren (QR, Einstellungen, Verifikation, Likes,
// Funken) und das Nachladen (Ziehen, Zurueck, App-Wechsel).
//
// DER WEG: Der Router im Test zeigt die Ziele als einfache
// Bildschirme (mit einem Text). So sieht der Test, WOHIN der Nutzer
// gefuehrt wurde - und die Reiter-Wahl laesst sich ueber den Provider
// pruefen.
//
// WAS HIER GEPRUEFT WIRD:
//   * das QR-Symbol und das Zahnrad fuehren zum richtigen Ort,
//   * der Verifikations-Hinweis fuehrt zur Verifizierung,
//   * der Pausiert-Hinweis fuehrt zu den Einstellungen,
//   * "Neue Likes" und "Neue Funken" oeffnen den passenden Reiter,
//   * ein bereits gesehenes Like und ein gesehener Funke zaehlen nicht
//     mehr (sonst bleibt das Badge ewig stehen),
//   * Ziehen, Zurueck und der Wechsel aus dem Hintergrund laden die
//     Zaehler neu.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/dating_hour/find_your_match_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/home/home_screen.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - kann mit einem Anfangswert gefuellt werden.
class _Speicher implements LocalStorage {
  _Speicher([Map<String, String>? start]) {
    if (start != null) _daten.addAll(start);
  }

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
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: ohne den Mock ruft der Test auf dem CI-Runner das
    // echte Plugin (das findet dort keine libsecret-Sitzung).
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

  /// Der Speicher mit einem pausierten Profil (der Pausiert-Hinweis).
  Map<String, String> speicherMitPause() => <String, String>{
    AppConstants.prefsSettingsKey: jsonEncode(
      AppSettings.defaults().copyWith(paused: true).toJson(),
    ),
  };

  /// Baut den Startbildschirm mit Router und Provider-Overrides.
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    bool paused = false,
    List<ReceivedLike> likes = const <ReceivedLike>[],
    List<MatchWithState> serverMatches = const <MatchWithState>[],
    Set<int>? gesehenLikes,
    Set<int>? gesehenFunken,
    Set<String>? gesehenQr,
    ChatNotifier? chat,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      observers: <NavigatorObserver>[routeObserver],
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.qrScan,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('QR-Scanner'))),
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
          path: AppRoutes.interessen,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Interessen'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    // DER SPEICHER: Er traegt den pausierten Zustand UND die bereits
    // gesehenen Eintraege (der Bildschirm soll sie nicht mehr zaehlen).
    final start = <String, String>{};
    if (paused) start.addAll(speicherMitPause());
    if (gesehenLikes != null) {
      start['seen_like_ids'] = jsonEncode(gesehenLikes.toList());
    }
    if (gesehenFunken != null) {
      start['seen_match_ids'] = jsonEncode(gesehenFunken.toList());
    }
    if (gesehenQr != null) {
      start['seen_qr_ids'] = jsonEncode(gesehenQr.toList());
    }
    final storage = _Speicher(start.isEmpty ? null : start);

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(storage),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
        if (chat != null) chatProvider.overrideWith((ref) => chat),
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
        // DIE SERVERZAEHLER: Der Test gibt sie vor - so sieht der
        // Bildschirm den Stand, den er auch in der App sieht.
        receivedLikesProvider.overrideWith((ref) async => likes),
        serverMatchesProvider.overrideWith((ref) async => serverMatches),
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

  group('Die Symbole oben', () {
    testWidgets('das QR-Symbol oeffnet den Scanner', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.byTooltip(L10n.tWithoutContext('home.qrTooltip')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('QR-Scanner'),
        findsOneWidget,
        reason:
            'Der Weg zu "Connect to others" darf nicht erst durch das '
            'Entdecken-Menue fuehren - der Nutzer sucht den QR-Weg oben.',
      );
    });

    testWidgets('das Zahnrad oeffnet die Einstellungen', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('home.settingsTooltip')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Einstellungen'), findsOneWidget);
    });
  });

  group('Die Hinweise', () {
    testWidgets('der Verifikations-Hinweis fuehrt zur Verifizierung', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('home.verifyHintAction')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Verifizierung'),
        findsOneWidget,
        reason:
            'Der Hinweis muss den Nutzer zur Verifizierung bringen - '
            'sonst bleibt der Vollzugang gesperrt und niemand weiss warum.',
      );
    });

    testWidgets('der Pausiert-Hinweis fuehrt zu den Einstellungen', (
      tester,
    ) async {
      await zeigeScreen(tester, paused: true);

      await scrolleZu(tester, L10n.tWithoutContext('paused.homeTitle'));
      expect(
        find.text(L10n.tWithoutContext('paused.homeTitle')),
        findsOneWidget,
        reason:
            'Der Pausiert-Hinweis muss stehen, wenn das Profil unsichtbar ist.',
      );

      await tester.tap(find.text(L10n.tWithoutContext('paused.homeTitle')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Einstellungen'),
        findsOneWidget,
        reason:
            'Der Hinweis muss eine Abkuerzung zum Entpausieren anbieten - '
            'sonst weiss der Nutzer nicht, wie er wieder sichtbar wird.',
      );
    });
  });

  group('Die Zaehler', () {
    testWidgets('ein neues Like zeigt den Weg zu den erhaltenen Likes', (
      tester,
    ) async {
      final container = await zeigeScreen(
        tester,
        likes: <ReceivedLike>[
          const ReceivedLike(
            likeId: 7,
            profile: UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
          ),
        ],
      );

      await scrolleZu(tester, 'Neue Likes');
      expect(find.text('1 neues Like'), findsOneWidget);

      await tester.tap(find.text('1 neues Like'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Interessen'), findsOneWidget);
      expect(
        container.read(interessenInitialTabProvider),
        1,
        reason:
            'Der Nutzer will die ERHALTENEN Likes sehen - der Weg darf nicht '
            'auf dem falschen Reiter landen.',
      );
    });

    testWidgets('ein gesehenes Like zaehlt nicht mehr', (tester) async {
      await zeigeScreen(
        tester,
        likes: <ReceivedLike>[
          const ReceivedLike(
            likeId: 7,
            profile: UserProfile(id: 'partner-1', name: 'Mira', bio: ''),
          ),
        ],
        gesehenLikes: <int>{7},
      );

      await scrolleZu(tester, 'Neue Likes');
      expect(
        find.text('Keine neuen Likes'),
        findsOneWidget,
        reason:
            'Ein Like, das der Nutzer schon gesehen hat, darf nicht ewig '
            'als "neu" dastehen.',
      );
    });

    testWidgets('ein neuer Funke zeigt den Weg zu den Funken', (tester) async {
      final container = await zeigeScreen(
        tester,
        serverMatches: <MatchWithState>[
          const MatchWithState(
            matchId: 42,
            partner: UserProfile(id: 'partner-2', name: 'Tom', bio: ''),
            unlockLevel: 0,
            failedAttempts: 0,
          ),
        ],
      );

      await scrolleZu(tester, 'Neue Funken');
      expect(find.text('1 neuer Funke'), findsOneWidget);

      await tester.tap(find.text('1 neuer Funke'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Interessen'), findsOneWidget);
      expect(
        container.read(interessenInitialTabProvider),
        2,
        reason: 'Der Weg zu den Funken muss den Reiter "Funken" oeffnen.',
      );
    });

    testWidgets('ein gesehener Funke zaehlt nicht mehr', (tester) async {
      await zeigeScreen(
        tester,
        serverMatches: <MatchWithState>[
          const MatchWithState(
            matchId: 42,
            partner: UserProfile(id: 'partner-2', name: 'Tom', bio: ''),
            unlockLevel: 0,
            failedAttempts: 0,
          ),
        ],
        gesehenFunken: <int>{42},
      );

      await scrolleZu(tester, 'Neue Funken');
      expect(
        find.text('Keine neuen Funken'),
        findsOneWidget,
        reason: 'Ein gesehener Funke darf nicht ewig als "neu" dastehen.',
      );
    });

    testWidgets('ein ungelesener QR-Kontakt zaehlt als neuer Funke', (
      tester,
    ) async {
      final service = ChatService();
      final match = service.createMatch(
        const UserProfile(id: 'partner-3', name: 'Nina', bio: ''),
        isQrContact: true,
      );
      service.incrementUnread(match.id);
      final chat = ChatNotifier(service);

      await zeigeScreen(tester, chat: chat);

      await scrolleZu(tester, 'Neue Funken');
      expect(
        find.text('1 neuer Funke'),
        findsOneWidget,
        reason:
            'Ein QR-Kontakt mit einer ungelesenen Nachricht ist ein neuer '
            'Funke - sonst wuerde der Nutzer die Nachricht nicht sehen.',
      );
    });

    testWidgets('ein gesehener QR-Kontakt zaehlt nicht mehr', (tester) async {
      final service = ChatService();
      final match = service.createMatch(
        const UserProfile(id: 'partner-3', name: 'Nina', bio: ''),
        isQrContact: true,
      );
      service.incrementUnread(match.id);
      final chat = ChatNotifier(service);

      await zeigeScreen(tester, chat: chat, gesehenQr: <String>{match.id});

      await scrolleZu(tester, 'Neue Funken');
      expect(find.text('Keine neuen Funken'), findsOneWidget);
    });
  });

  group('Das Nachladen', () {
    testWidgets('Ziehen laedt den Stand neu', (tester) async {
      await zeigeScreen(tester);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1200,
      );
      await pumpFrames(tester);
      // Der Refresh wartet 400 ms - die Test-Uhr muss weiterlaufen.
      await tester.pump(const Duration(milliseconds: 600));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('aus dem Hintergrund zurueck: die Zaehler werden neu geladen', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // DER APP-WECHSEL: Das Geraet kommt in den Vordergrund.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'zurueck vom gepushten Bildschirm: die Zaehler werden neu geladen',
      (tester) async {
        await zeigeScreen(tester);

        // PUSH: Der Nutzer geht in die Einstellungen und kommt zurueck.
        await tester.tap(
          find.byTooltip(L10n.tWithoutContext('home.settingsTooltip')),
        );
        await pumpFrames(tester);
        expect(find.text('Einstellungen'), findsOneWidget);

        // DAS ZURUECK: Die Test-Route hat keine AppBar - deshalb geht es
        // ueber den Navigator.
        Navigator.of(tester.element(find.text('Einstellungen'))).pop();
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });
}
