// Die Spiegelung nach profiles.ui_prefs (v0.8.0, Migration 074).
//
// DER WEG: Sie steht in einer eigenen Datei, weil die Hauptdatei sonst
// über der Grenze von 1000 Zeilen läge (test/code_datei_groessen_test.dart).
//
// "Nach Neuinstallation ist ALLES wieder da". Sensible Inhalte (Chats,
// E2E-Identität) sind bewusst NICHT Teil davon.
//
// Entprellt (1,5 s): Schalter feuern schnell hintereinander; es geht
// maximal EIN Schreibvorgang pro Ruhe-Window raus. Fire-and-forget -
// Fehler blockieren die UI nicht (der Stand wird beim nächsten Aufruf
// bzw. Login erneut gespiegelt).
part of 'settings_provider.dart';

/// Spiegelt den Rest der UI-Einstellungen nach profiles.ui_prefs (v0.8.0,
/// Migration 074) - "Nach Neuinstallation ist ALLES wieder da". Sensible
/// Inhalte (Chats, E2E-Identität) sind bewusst NICHT Teil davon.
///
/// Entprellt (1,5 s): Schalter feuern schnell hintereinander; es geht
/// maximal EIN Schreibvorgang pro Ruhe-Window raus. Fire-and-forget -
/// Fehler blockieren die UI nicht (der Stand wird beim nächsten Aufruf
/// bzw. Login erneut gespiegelt).
Timer? _uiPrefsSyncTimer;

void scheduleUiPrefsServerSync(AppSettings settings) {
  if (!SupabaseService.isInitialized) return;
  _uiPrefsSyncTimer?.cancel();
  _uiPrefsSyncTimer = Timer(const Duration(milliseconds: 1500), () {
    unawaited(() async {
      try {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          // DIE ECHTEN SPALTEN (v0.10.0).
          //
          // Die Push-Einstellungen standen bisher NUR in ui_prefs.
          // Die Edge Function notify-user liest aber die fünf
          // Einzelspalten (notifications_enabled, notify_matches,
          // notify_likes, notify_messages, notify_dating_hour) - und
          // die blieben dauerhaft auf ihrem Default true.
          //
          // Folge: die fünf Schalter in den Einstellungen waren
          // sichtbar und bedienbar, hatten aber KEINE Wirkung. Wer
          // Push für "Likes" abgeschaltet hat, bekam weiter welche.
          //
          // ui_prefs bleibt unberührt - dort steht die Spiegelung
          // für den schnellen Zugriff, aber die Serverlogik wertet
          // die Spalten aus.
          'notifications_enabled': settings.notificationsEnabled,
          'notify_matches': settings.notifyMatches,
          'notify_likes': settings.notifyLikes,
          'notify_messages': settings.notifyMessages,
          'notify_dating_hour': settings.notifyDatingHour,
          'ui_prefs': {
            'blindModeEnabled': settings.blindModeEnabled,
            'revealPhotosAfterMatch': settings.revealPhotosAfterMatch,
            'profileVisibility': settings.profileVisibility.value,
            'paused': settings.paused,
            'useDarkMode': settings.useDarkMode,
            'notificationsEnabled': settings.notificationsEnabled,
            'notifyMatches': settings.notifyMatches,
            'notifyLikes': settings.notifyLikes,
            'notifyMessages': settings.notifyMessages,
            'notifyDatingHour': settings.notifyDatingHour,
            'blurChatImages': settings.blurChatImages,
            // Geräte-lokal gedrückt, nicht in ui_prefs: die
            // Mikrofon-Offenlegung gehört zur Einwilligung auf diesem
            // Gerät und soll nicht in andere Konten wandern.
            'micDisclosureAccepted': settings.micDisclosureAccepted,
            'cameraDisclosureAccepted': settings.cameraDisclosureAccepted,
            'chatBackground': settings.chatBackground,
          },
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Settings] ui_prefs-Sync fehlgeschlagen: $e');
        }
      }
    }());
  });
}
