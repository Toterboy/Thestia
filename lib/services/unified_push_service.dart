import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Google-freier Push über UnifiedPush (F-Droid-Variante, Roadmap-Spike).
///
/// Funktionsweise:
///  1. Nutzer aktiviert den Schalter in den Einstellungen und braucht eine
///     "Distributor"-App (z. B. ntfy) auf dem Gerät.
///  2. [UnifiedPushService.enable] meldet die App beim Distributor an; der
///     Distributor liefert einen Endpunkt (z. B. `https://ntfy.sh/up-xyz`),
///     der serverseitig im Profil gespeichert wird (`profiles.up_endpoint`,
///     Migration 054).
///  3. Die Edge Function `notify-user` POSTet Metadaten (`{title, message}`)
///     an diesen Endpunkt; der Distributor reicht sie an onMessage weiter.
///  4. Diese Klasse zeigt die lokale Benachrichtigung (gleiches Icon/Channel
///     wie bei FCM) - Inhalte selbst bleiben weiterhin E2E im Chat.
class UnifiedPushService {
  UnifiedPushService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;
  static const String _channelId = 'messages';

  /// Letzter Registrierungsfehler für die UI (z. B. „kein Distributor").
  static String? lastError;

  static Future<void> _ensurePlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('notification_icon'),
      ),
    );
    _pluginReady = true;
  }

  /// Ist UnifiedPush aktuell aktiv? (Serverstand = Endpunkt vorhanden.)
  static Future<bool> isEnabled() async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final raw = await SupabaseService.client
          .from('profiles')
          .select('up_endpoint')
          .eq('user_id', SupabaseService.currentUser?.id ?? '')
          .maybeSingle();
      final endpoint = (raw?['up_endpoint'] as String?) ?? '';
      return endpoint.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Aktiviert UnifiedPush: Registriert beim Distributor, speichert den
  /// Endpunkt serverseitig und zeigt eingehende Pushes lokal an.
  ///
  /// Wirft [StateError] mit nutzerlesbarer Meldung, wenn kein Distributor
  /// installiert ist (Fehlermeldung für die UI).
  static Future<void> enable() async {
    lastError = null;
    await _ensurePlugin();

    final hasDistributor = await UnifiedPush.initialize(
        onNewEndpoint: _onNewEndpoint,
        onUnregistered: (_) {},
        onMessage: _onMessage);

    if (!hasDistributor) {
      final distributors = await UnifiedPush.getDistributors();
      if (distributors.isEmpty) {
        lastError =
            'Keine Push-Distributor-App gefunden (z. B. ntfy von F-Droid '
            'installieren).';
        throw StateError(lastError!);
      }
      await UnifiedPush.saveDistributor(distributors.first);
    }

    await UnifiedPush.register();
  }

  /// Deaktiviert: Abmeldung + Endpunkt serverseitig entfernen.
  static Future<void> disable() async {
    try {
      await UnifiedPush.unregister();
    } catch (_) {}
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseDatabaseService(SupabaseService.client)
            .updateOwnProfile({'up_endpoint': null});
      } catch (_) {}
    }
  }
  static Future<void> _onNewEndpoint(
      PushEndpoint endpoint, String instance) async {
    final url = endpoint.url;
    if (url.isEmpty || !SupabaseService.isInitialized) return;
    try {
      await SupabaseDatabaseService(SupabaseService.client)
          .updateOwnProfile({'up_endpoint': url});
      debugPrint('[UnifiedPush] Endpunkt gespeichert.');
    } catch (e) {
      debugPrint('[UnifiedPush] Endpunkt-Sync fehlgeschlagen: $e');
    }
  }

  /// Optionaler Unterdrückungs-Hook (NUTZERWUNSCH: keine Benachrichtigung,
  /// wenn der Absender-Chat gerade offen ist). Wird von [App] mit dem
  /// Riverpod-Ref verdrahtet (der Server liefert `from_user_id` seit
  /// Build 25 in den Push-Metadaten mit).
  static bool Function(String fromUserId)? suppressCheck;

  static Future<void> _onMessage(
      PushMessage message, String instance) async {
    String title = 'Thestia';
    String body = 'Du hast eine neue Nachricht erhalten.';
    String? kind;
    String? from;
    try {
      final text = utf8.decode(message.content);
      if (text.startsWith('{')) {
        final map = jsonDecode(text) as Map<String, dynamic>;
        title = map['title'] as String? ?? title;
        body = map['message'] as String? ?? body;
        kind = map['kind'] as String?;
        from = map['from_user_id'] as String?;
      } else {
        body = text;
      }
    } catch (_) {}
    // Chat offen + Vordergrund -> unterdrücken (wie im FCM-Pfad).
    if (kind == 'messages' &&
        from != null &&
        suppressCheck?.call(from) == true) {
      return;
    }
    await _showLocalNotification(title: title, message: body);
  }

  static Future<void> _showLocalNotification(
      {required String title, required String message}) async {
    await _ensurePlugin();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 0x7fffffff,
      title: title,
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelId,
          channelDescription: 'Neue Chat Nachrichten',
          icon: 'notification_icon',
          color: Color(0xFFFF6B9D),
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
