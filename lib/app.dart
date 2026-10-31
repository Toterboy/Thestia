import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart'
    show sharedPrefsProvider;
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/core/update_required_screen.dart';
import 'package:thestia/services/app_config_service.dart';
import 'package:thestia/services/global_relay_inbox.dart';
import 'package:thestia/services/notification_service.dart';
import 'package:thestia/services/unified_push_service.dart';
import 'package:thestia/theme/app_theme.dart';

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

  /// Der Server verlangt inzwischen einen neueren Build, als der
  /// installierte ist.
  ///
  /// PERFORMANCE (31.10.2026): Der Mindest-Build stand beim Start auf
  /// dem kritischen Pfad - der erste Frame wartete auf einen
  /// Server-Roundtrip. Jetzt wird der beim Start aus dem lokalen
  /// Cache gelesen (siehe main.dart), und der Serverwert laeuft hier
  /// im Hintergrund nach. Ist er strenger geworden, erscheint der
  /// Update-Hinweis als Deckschicht - ohne dass der Start gewartet
  /// hat.
  bool _lateUpdateRequired = false;

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
    _checkMinBuildInBackground();
  }

  /// Prueft den serverseitigen Mindest-Build im Hintergrund.
  ///
  /// Der Wert beim Start kam aus dem lokalen Cache. Ist der Server
  /// inzwischen strenger geworden, faellt das hier auf - der
  /// Update-Hinweis erscheint dann als Deckschicht ueber der laufenden
  /// App.
  ///
  /// Fail-open: ein Fehler beim Lesen bleibt ohne Folgen - der
  /// Cache gilt weiter, und der naechste Start fragt wieder.
  void _checkMinBuildInBackground() {
    unawaited(() async {
      try {
        final prefs = ref.read(sharedPrefsProvider);
        final frisch = await AppConfigService.fetchMinAppVersionBuild();
        if (frisch == null) return;
        if (prefs != null) {
          await AppConfigService.cacheMinAppVersionBuild(prefs, frisch);
        }
        final build = await AppConfigService.currentBuildNumber();
        if (!mounted) return;
        if (!AppConfigService.isBuildBelowMinBuild(build, frisch)) return;
        setState(() => _lateUpdateRequired = true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[App] Mindest-Build-Pruefung fehlgeschlagen: $e');
        }
      }
    }());
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
      title: title ?? 'Thestia',
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
    final theme = ThestiaTheme.fromName(settings.themeName);
    final locale = ref.watch(localeProvider);

    final brightness = settings.useDarkMode == null
        ? null
        : (settings.useDarkMode! ? Brightness.dark : Brightness.light);

    return L10nScope(child: MaterialApp.router(
      title: 'Thestia',
      debugShowCheckedModeBanner: false,
      locale: locale,
      // Audit/Fix: Delegates fuer de+en PFLICHT. Ohne sie unterstuetzt
      // Flutters DefaultMaterialLocalizations nur 'en' - bei gesetzter
      // Locale 'de' wurde gar kein MaterialLocalizations geladen und
      // Material-Widgets (AppBar, PopupMenuButton, Tooltips) crashten
      // mit "No MaterialLocalizations found" (grauer Fehler-Screen).
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de'), Locale('en')],
      // Gecachte Themes (AppTheme.of): stabile Identitaet, kein Neubau von
      // ColorScheme.fromSeed bei jedem Settings-Change.
      theme: AppTheme.of(theme, Brightness.light),
      darkTheme: AppTheme.of(theme, Brightness.dark),
      // Sofort umschalten. Mit der Standard-Animation (200 ms) lief die
      // ganze Oberflaeche inkl. Chat-Hintergruende erst sichtbar hinterher -
      // der Wechsel wirkt dadurch "verzögert".
      themeAnimationDuration: Duration.zero,
      themeMode: brightness == null
          ? ThemeMode.system
          : (brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light),
      routerConfig: router,
      // Der Update-Hinweis als Deckschicht ueber der laufenden App.
      // Er erscheint, wenn der Server strenger geworden ist, seitdem
      // der Cache gefuellt wurde (siehe _checkMinBuildInBackground).
      //
      // "Trotzdem fortfahren" ist hier aktiv - die App laeuft ja
      // bereits. Beim Start (main.dart) ist derselbe Bildschirm eine
      // Sperre; dort bleibt der Knopf ohne Wirkung.
      builder: (context, child) {
        if (!_lateUpdateRequired) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned.fill(
              child: UpdateRequiredScreen(
                onDismiss: () => setState(() => _lateUpdateRequired = false),
              ),
            ),
          ],
        );
      },
      ),
    );
  }
}
