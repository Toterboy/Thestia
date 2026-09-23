import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/global_relay_inbox.dart';
import 'package:wisp/services/notification_service.dart';
import 'package:wisp/services/unified_push_service.dart';
import 'package:wisp/theme/app_theme.dart';

/// Laufende Instanz des globalen Relay-Eingangs (für [App.dispose]).
final globalRelayInboxProvider = StateProvider<GlobalRelayInbox?>((ref) => null);

/// Wurzel-Widget der App.
///
/// Baut das Theme (Light/Dark je nach Einstellung) und den Router auf.
/// Registriert ZUSÄTZLICH den FCM-Foreground-Handler: Notification-
/// Messages werden bei geöffneter App NICHT vom System angezeigt
/// (Android/iOS übergeben sie an onMessage) - früher zeigte die App bei
/// offenem Screen GAR KEINE Benachrichtigung (Nutzerfeedback: "keine
/// Benachrichtigung in der App und auch nicht in Android"). Jetzt zeigt
/// der Handler eine Lokal-Benachrichtigung - außer der Absender-Chat ist
/// gerade offen (dann ist die Nachricht sichtbar und es soll keiner
/// kommen, NUTZERWUNSCH).
class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  /// Verhindert doppeltes Registrieren des Splash-Remove-Callbacks.
  static bool _splashRemoveScheduled = false;
  bool _fcmListenerRegistered = false;
  GlobalRelayInbox? _inbox;

  @override
  void initState() {
    super.initState();
    _setupFcmForegroundListener();
    // NUTZERWUNSCH: UnifiedPush-Path mit derselben Chat-offen-
    // Unterdrückung verdrahten (F-Droid-Variante).
    UnifiedPushService.suppressCheck = (peerId) =>
        shouldSuppressNotificationForPeer(ref, peerId);
    // NUTZERWUNSCH "Nachrichten außerhalb des Chats": Globaler Relay-
    // Eingang - verteilt entschlüsselte Nachrichten app-weit, solange
    // die App im Vordergrund ist und kein Chat-Screen selbst pollt.
    GlobalRelayInbox.notifier = _showRelayInboxNotification;
    final inbox = GlobalRelayInbox(ref);
    _inbox = inbox;
    ref.read(globalRelayInboxProvider.notifier).state = inbox;
    inbox.start();
  }

  /// Lokale Benachrichtigung für Relay-Nachrichten, die außerhalb des
  /// Chats zugestellt wurden. L10n-Fallback über den App-Kontext.
  Future<void> _showRelayInboxNotification({
    required int id,
    String? title,
    required String body,
    required String senderId,
  }) async {
    // Chat mit dem Absender offen -> Nachricht ist sichtbar (kein Ping).
    if (shouldSuppressNotificationForPeer(ref, senderId)) return;
    await ref.read(notificationServiceProvider).showMessageNotification(
      id: id,
      title: title ?? L10n.t(context, 'random.fallbackPartnerName'),
      body: body,
      ref: ref,
    );
  }

  @override
  void dispose() {
    _inbox?.stop();
    super.dispose();
  }

  /// FCM im Vordergrund: Metadaten-Push in eine Lokal-Benachrichtigung
  /// übersetzen (gleiche Kanäle/Icon wie der System-Pfad). Die Server-
  /// Metadaten enthalten `kind` + `from_user_id` (seit notify-user-Fix).
  void _setupFcmForegroundListener() {
    if (_fcmListenerRegistered) return;
    try {
      FirebaseMessaging.onMessage.listen((message) {
        _handleForegroundMessage(
          Map<String, String>.from(message.data),
          message.notification?.title,
          message.notification?.body,
        );
      });
      _fcmListenerRegistered = true;
    } catch (e) {
      // Firebase nicht initialisiert (z. B. Build ohne google-services):
      // Push läuft dann über den System-/UnifiedPush-Pfad weiter.
      debugPrint('[App] FCM-Foreground-Listener nicht verfügbar: $e');
    }
  }

  Future<void> _handleForegroundMessage(
    Map<String, String> data,
    String? title,
    String? body,
  ) async {
    final kind = data['kind'] ?? '';
    final from = data['from_user_id'] ?? '';
    // NUTZERWUNSCH: Chat mit dem Absender offen + App im Vordergrund ->
    // die Nachricht ist gerade sichtbar, keine Benachrichtigung nötig.
    if (shouldSuppressNotificationForPeer(ref, from)) return;

    final kindIndex = switch (kind) {
      'messages' => 0,
      'likes' => 1,
      'matches' => 2,
      'dating_hour' => 3,
      _ => 0,
    };
    const fallbacks = [
      ('Du hast eine neue Nachricht erhalten.', 'messages'),
      ('Jemand hat deine Vorstellung entdeckt.', 'likes'),
      ('Neuer Funke!', 'matches'),
      ('Dating Hour Erinnerung.', 'events'),
    ];
    // Serverseitig generierte Titel (notify-user) stehen in der
    // notification-Sektion; Fallback: feste Servertexte.
    await ref.read(notificationServiceProvider).show(
      id: DateTime.now().millisecondsSinceEpoch & 0xFFFFFF,
      title: title ?? 'WispDating',
      body: body ?? fallbacks[kindIndex].$1,
      channelId: fallbacks[kindIndex].$2,
      payload: null,
      ref: ref,
      type: switch (kindIndex) {
        0 => NotificationType.messages,
        1 => NotificationType.likes,
        2 => NotificationType.matches,
        _ => NotificationType.datingHour,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fallback: Nativen Splash entfernen, falls das Bootstrap (main.dart)
    // noch nicht entfernt hat. Der Übergang zum Lade-Screen (initialRoute
    // /loading) ist optisch identisch -> nahtlos ohne Flackern.
    if (!_splashRemoveScheduled) {
      _splashRemoveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final theme = WispTheme.fromName(settings.themeName);
    final locale = ref.watch(localeProvider);

    final brightness = settings.useDarkMode == null
        ? null
        : (settings.useDarkMode! ? Brightness.dark : Brightness.light);

    return L10nScope(child: MaterialApp.router(
      title: 'WispDating',
      debugShowCheckedModeBanner: false,
      locale: locale,
      // Audit/Fix: Delegates fuer de+en PFLICHT. Ohne sie unterstuetzt
      // Flutters DefaultMaterialLocalizations nur 'en' - bei gesetzter
      // Locale 'de' wurde gar kein MaterialLocalizations geladen und
      // Material-Widgets (AppBar, PopupMenuButton, Tooltips) crashten
      // mit "No MaterialLocalizations found" (grauer Fehler-Screen).
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de'), Locale('en')],
      theme: AppTheme.light(theme: theme),
      darkTheme: AppTheme.dark(theme: theme),
      themeMode: brightness == null
          ? ThemeMode.system
          : (brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light),
      routerConfig: router,
      ),
    );
  }
}
