import 'dart:io';

import 'package:flutter/material.dart'
    show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:thestia/providers/settings_provider.dart';

/// Kategorie einer Benachrichtigung – für die Einzel-Schalter in den
/// Einstellungen (Matches, Likes, Chatnachrichten, Dating Hour).
enum NotificationType {
  matches,
  likes,
  messages,
  datingHour,
}

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
  Future<void> initialize() async {
    if (_initialized) return;

    // Zeitzonen für geplante Benachrichtigungen (Dating Hour).
    tzdata.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fallback: UTC bleibt aktiv.
    }

    // Small Icon: rundes notification_icon (drawable) statt ic_launcher -
    // das Launcher-Icon ist ein voll opakes Adaptive-Icon und erscheint
    // in der Statusleiste als VIERECK. Die rund maskierte Silhouette
    // (tool/generate_branding.dart) bleibt in der Statusleiste ein Kreis.
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

    await _plugin.initialize(settings: initSettings);

    // Berechtigung für Android 13+ (POST_NOTIFICATIONS).
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'messages',
            'Nachrichten',
            description: 'Neue Chat Nachrichten',
            importance: Importance.high,
          ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'likes',
            'Likes',
            description: 'Jemand hat dein Profil geliked',
            importance: Importance.defaultImportance,
          ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'matches',
            'Matches',
            description: 'Neue Matches',
            importance: Importance.high,
          ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'events',
            'Event Erinnerungen',
            description: 'Erinnerung an Events oder Start bald',
            importance: Importance.defaultImportance,
          ));
    }

    _initialized = true;
  }

  /// Prüft Master-Schalter + Einzel-Schalter für [type].
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
          // tool/generate_notification_icon.dart).
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
                  : 'Event Erinnerungen',
      icon: 'notification_icon',
      color: const Color(0xFFFF6B9D),
      importance: Importance.high,
      priority: Priority.high,
      // Audit N-16: Nachrichteninhalte nicht auf dem Sperrbildschirm
      // zeigen (privat = nur entsperrent sichtbar). Andere Kategorien
      // enthalten ohnehin nur Metadaten.
      visibility:
          channelId == 'messages' ? NotificationVisibility.private : null,
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
      payload: '/chat/$id',
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
