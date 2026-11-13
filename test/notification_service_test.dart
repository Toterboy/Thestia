// Unit-Tests fuer den Benachrichtigungs-Dienst.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Initialisierung (Plugin, Zeitzone, Idempotenz),
//   * die Einzel-Schalter aus den Einstellungen (Master + je Kategorie),
//   * die lokalen Benachrichtigungen (Channel, Payload, Sichtbarkeit),
//   * die geplanten Benachrichtigungen (Dating Hour),
//   * der Tap auf eine Benachrichtigung (Payload landet beim Handler).
//
// WIE DAS PLUGIN ERSETZT WIRD:
//   `flutter_local_notifications` ruft die Plattform ueber
//   `FlutterLocalNotificationsPlatform.instance` auf. Der Test setzt
//   dort einen handgeschriebenen Android-Fake - so werden echte
//   MethodChannel-Aufrufe abgeschnitten, ohne dass am Produktivcode
//   etwas geaendert werden muss. `debugDefaultTargetPlatformOverride`
//   sorgt dafuer, dass der Dienst den Android-Zweig nimmt.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/notification_service.dart';

/// Der Kanal, ueber den das Plugin die Zeitzone des Geraetes liefert.
const MethodChannel _zeitzoneKanal = MethodChannel('flutter_timezone');

/// In-Memory-Speicher fuer die Einstellungen (kein Plugin, kein Geraet).
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
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

/// Eine Benachrichtigung, die das Plugin zeigen sollte.
class _Gezeigt {
  _Gezeigt({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.details,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
  final AndroidNotificationDetails? details;
}

/// Eine Benachrichtigung, die das Plugin planen sollte.
class _Geplant {
  _Geplant({
    required this.id,
    required this.title,
    required this.body,
    required this.termin,
    required this.details,
  });

  final int id;
  final String? title;
  final String? body;
  final tz.TZDateTime termin;
  final AndroidNotificationDetails? details;
}

/// Der Android-Fake des Benachrichtigungs-Plugins.
///
/// DER GRUND: Der Dienst ruft das Plugin ueber die Plattform-Schnittstelle
/// auf. Ein Fake dort ersetzt den echten Geraete-Aufruf - und laesst uns
/// zusehen, WAS der Dienst dem Plugin uebergibt (Channel, Payload,
/// Sichtbarkeit). Das ist genau das, was spaeter im System-Tray landet.
class _FakeNotificationsPlugin extends AndroidFlutterLocalNotificationsPlugin {
  /// Wie oft das Plugin initialisiert wurde.
  int initializeAufrufe = 0;

  /// Die Benachrichtigungen, die gezeigt wurden.
  final List<_Gezeigt> gezeigt = [];

  /// Die Benachrichtigungen, die geplant wurden.
  final List<_Geplant> geplant = [];

  /// Die IDs der abgebrochenen Benachrichtigungen.
  final List<int> abgebrochen = [];

  /// Was der Plugin beim Start als "per Benachrichtigung gestartet"
  /// meldet (null = normaler Appstart).
  NotificationAppLaunchDetails? launchDetails;

  /// Wenn gesetzt, wirft `show()` diesen Fehler.
  Object? fehlerBeimZeigen;

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeAufrufe++;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    return launchDetails;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (fehlerBeimZeigen != null) throw fehlerBeimZeigen!;
    gezeigt.add(
      _Gezeigt(
        id: id,
        title: title,
        body: body,
        payload: payload,
        details: notificationDetails,
      ),
    );
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    AndroidNotificationDetails? notificationDetails,
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exact,
  }) async {
    geplant.add(
      _Geplant(
        id: id,
        title: title,
        body: body,
        termin: scheduledDate,
        details: notificationDetails,
      ),
    );
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    abgebrochen.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNotificationsPlugin plugin;

  setUp(() {
    plugin = _FakeNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = plugin;

    // Die Zeitzone kommt vom Geraet. Im Test gibt es kein Geraet -
    // deshalb liefert der Kanal eine feste Zone. Ohne diesen Mock
    // wuerde der Dienst auf eine Antwort der Engine warten, die im
    // Test nie kommt.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_zeitzoneKanal, (anfrage) async {
          return 'Europe/Berlin';
        });
  });

  tearDown(() {
    NotificationService.tapHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_zeitzoneKanal, null);
  });

  /// Fuehrt den Testkoerper im Android-Zweig des Plugins aus.
  ///
  /// DER GRUND: Der Dienst spricht das Android-Plugin an - im Test gibt
  /// es kein Geraet, also muss der Zweig umgeleitet werden. Und:
  /// `debugDefaultTargetPlatformOverride` muss am Ende eines Tests wieder
  /// auf null stehen (das prueft das Test-Framework), deshalb wird es
  /// hier im `finally` zurueckgesetzt - auch wenn der Test vorher
  /// fehlgeschlagen ist.
  Future<void> alsAndroid(Future<void> Function() koerper) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await koerper();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Baut die Einstellungen und liefert einen [WidgetRef] fuer den Dienst.
  ///
  /// DER GRUND: `NotificationService.show` liest die Schalter ueber einen
  /// [WidgetRef] (der Aufrufer ist ein Widget). Der Test baut deshalb ein
  /// winziges Widget, das sich den Ref schnappt.
  Future<WidgetRef> mitEinstellungen(
    WidgetTester tester, {
    bool notificationsEnabled = true,
    bool notifyMessages = true,
    bool notifyLikes = true,
    bool notifyMatches = true,
    bool notifyDatingHour = true,
  }) async {
    final container = ProviderContainer(
      overrides: [localStorageProvider.overrideWithValue(_FakeLocalStorage())],
    );
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.setNotificationsEnabled(notificationsEnabled);
    await notifier.setNotifyMessages(notifyMessages);
    await notifier.setNotifyLikes(notifyLikes);
    await notifier.setNotifyMatches(notifyMatches);
    await notifier.setNotifyDatingHour(notifyDatingHour);

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

  // WICHTIG: Der Dienst ist ein Singleton. Sein "_initialized"-Flag bleibt
  // fuer den ganzen Testprozess gesetzt - deshalb prueft der ERSTE Test
  // die Initialisierung. Alle folgenden Tests nutzen den Dienst
  // uninitialisiert weiter (das Flag ist dann bereits gesetzt).
  testWidgets(
    'initialize(): Plugin genau einmal einrichten, Start-Payload wird '
    'zugestellt',
    (tester) async {
      await alsAndroid(() async {
        // Die App wurde per Tap auf eine Benachrichtigung gestartet.
        plugin.launchDetails = const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '/interessen',
          ),
        );
        final empfangene = <String>[];
        NotificationService.tapHandler = empfangene.add;

        await NotificationService.instance.initialize();
        await NotificationService.instance.initialize();

        expect(
          plugin.initializeAufrufe,
          1,
          reason:
              'Das Plugin darf nur einmal eingerichtet werden - sonst '
              'werden die Callback-Handler doppelt registriert.',
        );
        expect(
          empfangene,
          ['/interessen'],
          reason:
              'Startet die App per Tap auf eine Benachrichtigung, muss der '
              'Payload trotzdem zugestellt werden.',
        );
        expect(
          tz.local.name,
          'Europe/Berlin',
          reason:
              'Die Zeitzone des Geraetes wird uebernommen - geplante '
              'Benachrichtigungen (Dating Hour) sollen zur lokalen Zeit '
              'erscheinen.',
        );
      });
    },
  );

  testWidgets('show(): der Master-Schalter unterdrueckt alles', (tester) async {
    await alsAndroid(() async {
      final ref = await mitEinstellungen(tester, notificationsEnabled: false);

      await NotificationService.instance.showMessageNotification(
        id: 1,
        title: 'Neue Nachricht',
        body: 'Hallo',
        ref: ref,
      );

      expect(
        plugin.gezeigt,
        isEmpty,
        reason: 'Der Master-Schalter muss jede Benachrichtigung unterdruecken',
      );
    });
  });

  testWidgets('show(): der Einzel-Schalter unterdrueckt nur seine Kategorie', (
    tester,
  ) async {
    await alsAndroid(() async {
      final ref = await mitEinstellungen(tester, notifyMessages: false);

      await NotificationService.instance.showMessageNotification(
        id: 1,
        title: 'Neue Nachricht',
        body: 'Hallo',
        ref: ref,
      );
      expect(
        plugin.gezeigt,
        isEmpty,
        reason: 'Der Schalter "Chatnachrichten" ist aus',
      );

      await NotificationService.instance.showLikeNotification(
        id: 2,
        title: 'Neuer Like',
        body: 'Jemand mag dich',
        ref: ref,
      );
      expect(
        plugin.gezeigt.length,
        1,
        reason:
            'Der Schalter "Likes" ist an - die Benachrichtigung muss kommen',
      );
    });
  });

  testWidgets('showMessageNotification(): Channel, Payload und Sichtbarkeit', (
    tester,
  ) async {
    await alsAndroid(() async {
      final ref = await mitEinstellungen(tester);

      await NotificationService.instance.showMessageNotification(
        id: 7,
        title: 'Neue Nachricht',
        body: 'Hallo',
        ref: ref,
      );

      expect(plugin.gezeigt.length, 1);
      final nachricht = plugin.gezeigt.single;
      expect(nachricht.id, 7);
      expect(nachricht.title, 'Neue Nachricht');
      expect(nachricht.body, 'Hallo');
      expect(
        nachricht.details?.channelId,
        'messages',
        reason: 'Nachrichten gehoeren in den Channel "messages"',
      );
      expect(
        nachricht.payload,
        '/interessen',
        reason:
            'Der Payload steuert die Navigation: ueber den '
            'Interessen-Screen ist der Partner sicher bekannt.',
      );
      expect(
        nachricht.details?.visibility,
        NotificationVisibility.private,
        reason:
            'Audit N-16: Nachrichteninhalte duerfen nicht auf dem '
            'Sperrbildschirm stehen.',
      );
    });
  });

  testWidgets('die uebrigen Kategorien haben eigene Channels und Payloads', (
    tester,
  ) async {
    await alsAndroid(() async {
      final ref = await mitEinstellungen(tester);

      await NotificationService.instance.showLikeNotification(
        id: 1,
        title: 'Like',
        body: 'Mag dich',
        ref: ref,
      );
      await NotificationService.instance.showMatchNotification(
        id: 2,
        title: 'Match',
        body: 'Neuer Match',
        ref: ref,
      );
      await NotificationService.instance.showEventNotification(
        id: 3,
        title: 'Event',
        body: 'Dating Hour startet',
        ref: ref,
      );

      expect(plugin.gezeigt.length, 3);
      expect(plugin.gezeigt[0].details?.channelId, 'likes');
      expect(plugin.gezeigt[0].payload, '/interessen');
      expect(plugin.gezeigt[1].details?.channelId, 'matches');
      expect(plugin.gezeigt[1].payload, '/interessen');
      expect(plugin.gezeigt[2].details?.channelId, 'events');
      expect(
        plugin.gezeigt[2].payload,
        '/dating-hour',
        reason: 'Die Event-Erinnerung gehoert zum Dating-Hour-Screen',
      );
    });
  });

  testWidgets('showSystemNotice(): wird von keinem Schalter unterdrueckt', (
    tester,
  ) async {
    await alsAndroid(() async {
      // Alle Schalter aus - die Meldung muss trotzdem kommen.
      await mitEinstellungen(
        tester,
        notificationsEnabled: false,
        notifyMessages: false,
      );

      await NotificationService.instance.showSystemNotice(
        id: 99,
        title: 'Alter bestaetigt',
        body: 'Dein Alter ist freigegeben.',
      );

      expect(
        plugin.gezeigt.length,
        1,
        reason:
            'Systemmeldungen ueber den eigenen Zustand (z. B. die '
            'Altersfreigabe) sind niemandem abgeschaltet.',
      );
      expect(plugin.gezeigt.single.details?.channelId, 'system');
    });
  });

  testWidgets('scheduleAt(): plant eine Benachrichtigung in der Zukunft', (
    tester,
  ) async {
    await alsAndroid(() async {
      // Die Planung rechnet in der lokalen Zeitzone - der Test setzt sie
      // fest, damit das Ergebnis unabhaengig vom Geraet ist.
      tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
      final wann = DateTime.now().add(const Duration(hours: 2));

      await NotificationService.instance.scheduleAt(
        id: 42,
        when: wann,
        title: 'Dating Hour',
        body: 'Es geht los',
        channelId: 'events',
      );

      expect(plugin.geplant.length, 1);
      final geplant = plugin.geplant.single;
      expect(geplant.id, 42);
      expect(geplant.title, 'Dating Hour');
      expect(geplant.details?.channelId, 'events');
      expect(
        geplant.termin.millisecondsSinceEpoch,
        tz.TZDateTime.from(wann, tz.local).millisecondsSinceEpoch,
        reason: 'Der geplante Zeitpunkt muss unveraendert bleiben',
      );
    });
  });

  testWidgets(
    'scheduleAt(): ein Zeitpunkt in der Vergangenheit wird nicht geplant',
    (tester) async {
      await alsAndroid(() async {
        await NotificationService.instance.scheduleAt(
          id: 43,
          when: DateTime.now().subtract(const Duration(hours: 2)),
          title: 'Vergangen',
          body: 'Nicht mehr',
          channelId: 'events',
        );

        expect(
          plugin.geplant,
          isEmpty,
          reason:
              'Eine Benachrichtigung in der Vergangenheit wuerde sofort und '
              'sinnlos erscheinen.',
        );
      });
    },
  );

  testWidgets('cancel(): entfernt die geplante Benachrichtigung', (
    tester,
  ) async {
    await alsAndroid(() async {
      await NotificationService.instance.cancel(42);

      expect(plugin.abgebrochen, [42]);
    });
  });

  testWidgets('ein Fehler des Plugins wird nicht verschluckt', (tester) async {
    await alsAndroid(() async {
      final ref = await mitEinstellungen(tester);
      plugin.fehlerBeimZeigen = PlatformException(code: 'INTERN');

      await expectLater(
        NotificationService.instance.showMessageNotification(
          id: 1,
          title: 'Neue Nachricht',
          body: 'Hallo',
          ref: ref,
        ),
        throwsA(isA<PlatformException>()),
        reason:
            'Der Dienst darf Fehler nicht schlucken - die UI muss sie dem '
            'Nutzer zeigen koennen.',
      );
    });
  });

  testWidgets('Tap auf eine Benachrichtigung: der Payload kommt an', (
    tester,
  ) async {
    await alsAndroid(() async {
      final empfangene = <String>[];
      NotificationService.tapHandler = empfangene.add;

      NotificationService.onNotificationTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '/interessen',
        ),
      );
      await tester.pump();

      expect(
        empfangene,
        ['/interessen'],
        reason:
            'Ohne Handler passiert beim Tippen NICHTS - der Tap muss zum '
            'Interessen-Screen fuehren.',
      );
    });
  });

  testWidgets('Tap ohne verdrahteten Handler: verwaessert ohne Absturz', (
    tester,
  ) async {
    await alsAndroid(() async {
      NotificationService.tapHandler = null;

      NotificationService.onNotificationTap(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '/interessen',
        ),
      );
      // Der Dienst wartet 20 x 50 ms auf den Hook und verwirft dann den
      // Payload. In der Testuhr geht das schnell.
      await tester.pump(const Duration(seconds: 2));

      expect(
        tester.takeException(),
        isNull,
        reason: 'Ein fehlender Hook darf die App nicht zum Absturz bringen',
      );
    });
  });
}
