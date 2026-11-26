import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Kategorie einer Benachrichtigung – für die Einzel-Schalter in den
/// Einstellungen (Matches, Likes, Chatnachrichten, Dating Hour).
///
/// [verification] hat keinen eigenen Schalter: die Freigabe der
/// Altersprüfung betrifft den Vollzugang - dafür reicht der
/// Master-Schalter ("Benachrichtigungen").
enum NotificationType { matches, likes, messages, datingHour, verification }

/// Zentraler Benachrichtigungs-Dienst.
///
/// Kapselt die Lokal-Benachrichtigungen in iOS und Android und sorgt
/// dafür, dass die Betriebssystem-Berechtigungen vor der ersten Nutzung
/// eingeholt werden. Jede Benachrichtigung wird gegen die Einzel-Schalter
/// der Einstellungen geprüft.
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialisiert den Dienst, legt die Standard-Kanäle an und holt die
  /// Benachrichtigungs-Berechtigung (Android 13+).
  /// Der Tap-Handler für lokale Benachrichtigungen (BEFUND 09.11.2026).
  ///
  /// Statisch, weil `initialize` eine statische Funktion braucht.
  static void onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    unawaited(_deliverTapPayload(payload));
  }

  Future<void> initialize() async {
    if (_initialized) return;

    // Zeitzonen für geplante Benachrichtigungen (Dating Hour).
    tzdata.initializeTimeZones();
    // Fallback: UTC bleibt aktiv.
    await bestEffort('getLocation', () async {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    });

    // Small Icon: rundes notification_icon (drawable) statt ic_launcher -
    // das Launcher-Icon ist ein voll opakes Adaptive-Icon und erscheint
    // in der Statusleiste als VIERECK. Die rund maskierte Silhouette
    // (tool/images/generate_branding.dart) bleibt in der Statusleiste ein Kreis.
    const androidSettings = AndroidInitializationSettings('notification_icon');
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // DER TAP (BEFUND 09.11.2026, Betreiber): "Wenn man auf die
    // Benachrichtigung drückt, dass man eine neue Nachricht erhalten
    // hat, soll man zum Interessen Screen kommen."
    //
    // DER GRUND (live geprüft): Der Payload wurde gesetzt
    // (payload: '/interessen'), aber es gab KEINEN Handler dafür - der
    // Tap öffnete die App und sonst nichts.
    //
    // `onDidReceiveNotificationResponse` feuert bei einem Tap auf eine
    // LOKALE Benachrichtigung (im Vordergrund oder aus dem Hintergrund).
    // `getNotificationAppLaunchDetails` liefert den Payload, mit dem die
    // App per Tap auf die Benachrichtigung GESTARTET wurde (App war
    // beendet) - das wird hier einmalig ausgewertet.
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );

    // App per Tap auf die Benachrichtigung gestartet (App war zu)?
    final startDetails = await _plugin.getNotificationAppLaunchDetails();
    if (startDetails?.didNotificationLaunchApp == true) {
      final payload = startDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        // Der Hook wird evtl. erst später verdrahtet (App-Root) - dann
        // wartet die Navigation kurz.
        await _deliverTapPayload(payload);
      }
    }

    // Berechtigung für Android 13+ (POST_NOTIFICATIONS).
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'messages',
              'Nachrichten',
              description: 'Neue Chat Nachrichten',
              importance: Importance.high,
            ),
          );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'likes',
              'Likes',
              description: 'Jemand hat dein Profil geliked',
              importance: Importance.defaultImportance,
            ),
          );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'matches',
              'Matches',
              description: 'Neue Matches',
              importance: Importance.high,
            ),
          );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'events',
              'Event Erinnerungen',
              description: 'Erinnerung an Events oder Start bald',
              importance: Importance.defaultImportance,
            ),
          );
      // Der Kanal für die Freigabe der Altersprüfung. Wichtig, damit
      // die Meldung nicht stumm bleibt (Importance.defaultImportance
      // reicht, aber sie soll als eigener Kanal einstellbar sein).
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'verification',
              'Verifizierung',
              description: 'Freigabe deiner Alterspruefung',
              importance: Importance.high,
            ),
          );
    }

    _initialized = true;
  }

  /// Prüft Master-Schalter + Einzel-Schalter für [type].
  /// Wird aufgerufen, wenn der Nutzer auf eine lokale Benachrichtigung
  /// tippt.
  ///
  /// BEFUND (09.11.2026): Ohne diesen Handler passierte beim Tippen
  /// NICHTS - die App ging auf, aber nicht zum Chat. Der Payload
  /// (z. B. '/interessen') wird jetzt ausgewertet.
  static void Function(String payload)? tapHandler;

  /// Liefert den Tap an den Handler - mit kurzem Warten, falls die App
  /// den Hook noch nicht verdrahtet hat (Start aus der Benachrichtigung).
  static Future<void> _deliverTapPayload(String payload) async {
    for (var i = 0; i < 20; i++) {
      final handler = tapHandler;
      if (handler != null) {
        handler(payload);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    debugPrint(
      '[Notification] Kein Tap-Handler verdrahtet - Ziel $payload verwaessert.',
    );
  }

  bool _isEnabledFor(WidgetRef ref, NotificationType type) {
    final settings = ref.read(settingsProvider);
    if (!settings.notificationsEnabled) return false;
    switch (type) {
      case NotificationType.matches:
        return settings.notifyMatches;
      case NotificationType.likes:
        return settings.notifyLikes;
      case NotificationType.messages:
        return settings.notifyMessages;
      case NotificationType.datingHour:
        return settings.notifyDatingHour;
      case NotificationType.verification:
        // Kein eigener Schalter - der Master-Schalter reicht (die
        // Freigabe der Altersprüfung ist keine "Sonderwunsch"-Meldung,
        // sondern betrifft den Vollzugang).
        return true;
    }
  }

  /// Plant eine Benachrichtigung zu einem festen Zeitpunkt – funktioniert
  /// AUCH bei geschlossener App (lokale Planung, kein Push nötig).
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String channelId,
  }) async {
    if (!_initialized) await initialize();
    final scheduled = tz.TZDateTime.from(when, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          // Thestia-Silhouette statt weissem Punkt (siehe
          // tool/images/generate_notification_icon.dart).
          icon: 'notification_icon',
          color: const Color(0xFFFF6B9D),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: true,
          presentBadge: true,
          presentAlert: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Entfernt eine geplante Benachrichtigung.
  Future<void> cancel(int id) async {
    if (!_initialized) await initialize();
    await _plugin.cancel(id: id);
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? channelId,
    String? payload,
    required WidgetRef ref,
    required NotificationType type,
  }) async {
    // Einzel-Schalter: deaktivierte Kategorien werden nicht angezeigt.
    if (!_isEnabledFor(ref, type)) return;
    if (!_initialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId ?? 'messages',
      channelId ?? 'messages',
      channelDescription: channelId == 'messages'
          ? 'Neue Chat Nachrichten'
          : channelId == 'likes'
          ? 'Jemand hat dein Profil geliked'
          : channelId == 'matches'
          ? 'Neue Matches'
          : channelId == 'verification'
          ? 'Freigabe deiner Alterspruefung'
          : 'Event Erinnerungen',
      icon: 'notification_icon',
      color: const Color(0xFFFF6B9D),
      importance: Importance.high,
      priority: Priority.high,
      // Audit N-16: Nachrichteninhalte nicht auf dem Sperrbildschirm
      // zeigen (privat = nur entsperrent sichtbar). Andere Kategorien
      // enthalten ohnehin nur Metadaten.
      visibility: channelId == 'messages'
          ? NotificationVisibility.private
          : null,
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentAlert: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Eine systemeigene Meldung ohne Kategorie-Schalter und ohne
  /// WidgetRef.
  ///
  /// Wofür: Meldungen über den eigenen Zustand, die der Nutzer
  /// auslöst und die deshalb niemandem abgeschaltet werden sollen -
  /// z.B. die Freigabe der Altersverifizierung. Die Freigabe entsteht
  /// serverseitig durch einen Admin, und der Nutzer sieht sonst nichts
  /// davon, bis die App neu startet.
  ///
  /// Bewusst ohne die Kategorie-Schalter der [show]-Methode: ein
  /// Schalter "Likes" darf die Meldung "Dein Alter ist bestätigt"
  /// nicht unterdrücken. Und ohne WidgetRef, weil der Auslöser ein
  /// StateNotifier ist und dort kein WidgetRef zur Verfügung steht.
  Future<void> showSystemNotice({
    required int id,
    required String title,
    required String body,
    String channelId = 'system',
  }) async {
    if (!_initialized) await initialize();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Systemmeldungen',
        channelDescription: 'Meldungen ueber dein eigenes Konto',
        icon: 'notification_icon',
        color: const Color(0xFFFF6B9D),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentBadge: true,
        presentAlert: true,
      ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    required WidgetRef ref,
  }) async {
    await show(
      id: id,
      title: title,
      body: body,
      channelId: 'messages',
      // BEFUND (09.11.2026, Betreiber): "Wenn man auf die Benachrichtigung
      // drückt, dass man eine neue Nachricht erhalten hat, soll man zum
      // Interessen Screen kommen."
      //
      // DER GRUND: Der Chat braucht den Eintrag in der Partnerliste
      // (der Relay-Abruf läuft über `getMatchById`). Öffnet man den
      // Chat direkt aus der Benachrichtigung, ist der Partner dort
      // manchmal noch nicht geladen - der Chat bleibt dann leer, obwohl
      // die Nachricht zugestellt wurde. Über den Interessen-Screen ist
      // der Partner sicher bekannt.
      payload: '/interessen',
      ref: ref,
      type: NotificationType.messages,
    );
  }

  Future<void> showLikeNotification({
    required int id,
    required String title,
    required String body,
    required WidgetRef ref,
  }) async {
    await show(
      id: id,
      title: title,
      body: body,
      channelId: 'likes',
      payload: '/interessen',
      ref: ref,
      type: NotificationType.likes,
    );
  }

  Future<void> showMatchNotification({
    required int id,
    required String title,
    required String body,
    required WidgetRef ref,
  }) async {
    await show(
      id: id,
      title: title,
      body: body,
      channelId: 'matches',
      payload: '/interessen',
      ref: ref,
      type: NotificationType.matches,
    );
  }

  Future<void> showEventNotification({
    required int id,
    required String title,
    required String body,
    required WidgetRef ref,
  }) async {
    await show(
      id: id,
      title: title,
      body: body,
      channelId: 'events',
      payload: '/dating-hour',
      ref: ref,
      type: NotificationType.datingHour,
    );
  }
}
