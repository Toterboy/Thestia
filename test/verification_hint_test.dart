// Die beiden offenen Verifikations-Aufgaben (15.11.2026):
//
//   1. Der HINWEIS auf "Aktuelles" (Startbildschirm), wenn die
//      Alterspruefung fehlt.
//   2. die BENACHRICHTIGUNG bei der Freigabe der Verifizierung.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Hinweis steht da, wenn das Profil nicht verifiziert ist (mit
//     einem Knopf, der zur Verifizierung fuehrt),
//   * im Zustand "Wird geprueft" steht der Wartetext da - und KEIN
//     Knopf (es gibt nichts zu tun),
//   * bei einem verifizierten Profil steht gar kein Hinweis da,
//   * die Freigabe-Meldung folgt dem Master-Schalter: ist er aus, kommt
//     nichts; ist er an, kommt sie (auch ohne eigenen Einzel-Schalter).
//
// WIE DAS PLUGIN ERSETZT WIRD: Muster aus notification_service_test.dart
// (ein handgeschriebener Android-Fake an der Plattform-Schnittstelle).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/home/home_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/notification_service.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/plugin_mocks.dart';

/// Der Kanal, ueber den das Plugin die Zeitzone des Geraetes liefert.
const MethodChannel _zeitzoneKanal = MethodChannel('flutter_timezone');

/// In-Memory-Speicher (kein Plugin, kein Geraet).
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

/// Der Android-Fake des Benachrichtigungs-Plugins.
class _FakeNotificationsPlugin extends AndroidFlutterLocalNotificationsPlugin {
  /// Die Benachrichtigungen, die gezeigt wurden.
  final List<Map<String, dynamic>> gezeigt = [];

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    gezeigt.add(<String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'channel': notificationDetails?.channelId,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {}

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel channel,
  ) async {}

  /// BEFUND (15.11.2026): Ohne diesen Override bleibt der Aufruf HANGEN.
  ///
  /// Das Plugin spricht die Plattform seit Version 23 ueber Pigeon an
  /// (kein MethodChannel mehr). Ohne Mock kommt keine Antwort - und die
  /// Future wartet endlos (der Test lief in den Zehn-Minuten-Timeout).
  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
}

void main() {
  late _FakeNotificationsPlugin plugin;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockZeitzone();
  });

  setUp(() {
    plugin = _FakeNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = plugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_zeitzoneKanal, (anfrage) async {
          return 'Europe/Berlin';
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  /// Baut den Startbildschirm mit einem Profil im angegebenen Zustand.
  Future<void> zeigeStart(
    WidgetTester tester, {
    VerificationState zustand = VerificationState.unverified,
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
          path: AppRoutes.verificationInfo,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Verifizierung'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _FakeLocalStorage();
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
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                verificationState: zustand,
              ),
            );
            return notifier;
          }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Fuehrt den Testkoerper im Android-Zweig des Plugins aus.
  ///
  /// DER GRUND: `debugDefaultTargetPlatformOverride` muss am ENDE des
  /// Testkoerpers wieder auf null stehen - das prueft das Test-Framework
  /// VOR dem tearDown. Deshalb wird es hier (nicht im tearDown)
  /// zurueckgesetzt.
  Future<void> alsAndroid(Future<void> Function() koerper) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await koerper();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Baut die Einstellungen und liefert einen [WidgetRef] fuer den Dienst.
  Future<WidgetRef> mitEinstellungen(
    WidgetTester tester, {
    bool notificationsEnabled = true,
  }) async {
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(_FakeLocalStorage())],
    );
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.setNotificationsEnabled(notificationsEnabled);

    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, widgetRef, _) {
            ref = widgetRef;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return ref;
  }

  group('Der Verifikations-Hinweis auf Aktuelles', () {
    testWidgets('ohne Verifizierung steht der Hinweis mit Knopf', (
      tester,
    ) async {
      await zeigeStart(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('home.verifyHintUnverifiedTitle')),
        findsOneWidget,
      );
      // Und der Knopf sagt, was er tut.
      expect(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('home.verifyHintAction'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('der Knopf fuehrt zur Verifizierung', (tester) async {
      await zeigeStart(tester);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('home.verifyHintAction'),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Verifizierung'), findsOneWidget);
    });

    testWidgets('waehrend der Pruefung steht der Wartetext ohne Knopf', (
      tester,
    ) async {
      await zeigeStart(tester, zustand: VerificationState.underReview);

      expect(
        find.text(L10n.tWithoutContext('home.verifyHintReviewTitle')),
        findsOneWidget,
      );
      // Es gibt nichts zu tun - also auch kein "Jetzt verifizieren".
      expect(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('home.verifyHintAction'),
        ),
        findsNothing,
      );
    });

    testWidgets('bei einem verifizierten Profil steht kein Hinweis', (
      tester,
    ) async {
      await zeigeStart(tester, zustand: VerificationState.verified);

      expect(
        find.text(L10n.tWithoutContext('home.verifyHintUnverifiedTitle')),
        findsNothing,
      );
      expect(
        find.text(L10n.tWithoutContext('home.verifyHintReviewTitle')),
        findsNothing,
      );
    });
  });

  group('Die Benachrichtigung bei der Freigabe', () {
    testWidgets('der Master-Schalter allein genuegt', (tester) async {
      await alsAndroid(() async {
        final ref = await mitEinstellungen(tester);

        await NotificationService.instance.show(
          id: 7,
          title: 'Alles geprueft!',
          body: 'Deine Alterspruefung wurde freigegeben.',
          channelId: 'verification',
          ref: ref,
          type: NotificationType.verification,
        );
      });

      expect(plugin.gezeigt, hasLength(1));
      expect(plugin.gezeigt.first['body'], contains('freigegeben'));
      // Der eigene Kanal - sonst landet sie bei den Ereignissen.
      expect(plugin.gezeigt.first['channel'], 'verification');
    });

    testWidgets('der Master-Schalter unterdrueckt sie', (tester) async {
      await alsAndroid(() async {
        final ref = await mitEinstellungen(tester, notificationsEnabled: false);

        await NotificationService.instance.show(
          id: 8,
          title: 'Alles geprueft!',
          body: 'Deine Alterspruefung wurde freigegeben.',
          channelId: 'verification',
          ref: ref,
          type: NotificationType.verification,
        );
      });

      expect(
        plugin.gezeigt,
        isEmpty,
        reason:
            'Der Master-Schalter muss auch die Freigabe-Meldung '
            'unterdruecken - sonst kommen Meldungen, die der Nutzer '
            'abgeschaltet hat.',
      );
    });
  });
}
