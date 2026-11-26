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
            // Die Tastatur (0.11.0): sie übersteht damit eine
            // Neuinstallation und ist auf dem zweiten Gerät da.
            'tastaturBelegung': settings.tastaturBelegung,
            'tastaturStil': settings.tastaturStil,
            'tastaturFarbe': settings.tastaturFarbe,
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

/// Die serverseitig gespiegelten UI-Einstellungen übernehmen.
///
/// DER WEG: Das Übernehmen liegt in einer Erweiterung, weil die
/// Hauptdatei sonst über der Grenze von 1000 Zeilen läge. Der Zustand
/// kommt über die zwei Zugänge der Klasse (`stand` und `setzeStand`) -
/// `state` selbst ist geschützt.
extension SettingsUiPrefsServer on SettingsNotifier {
  /// Übernimmt die serverseitig gespiegelten UI-Einstellungen
  /// (profiles.ui_prefs, Migration 074) nach Login/Neuinstallation.
  /// Server gewinnt bei vorhandenen Schlüsseln; fehlende Schlüssel
  /// (alter Serverstand) lassen den lokalen Stand unangetastet.
  Future<void> applyServerUiPrefs(Map<String, dynamic>? ui) async {
    if (ui == null || ui.isEmpty) return;
    var next = stand;
    var changed = false;

    T? read<T>(String key) => ui[key] is T ? ui[key] as T : null;

    // 'blindModeEnabled' wird vom Server bewusst NICHT mehr
    // übernommen: der Blind Mode ist fest AN. Ohne das würde ein
    // alter Serverstand (Blind Mode aus) die App wieder ausblenden -
    // der Wert wird beim nächst Sync auf true gesetzt und
    // heilt damit auch die Bestandskonten.
    final reveal = read<bool>('revealPhotosAfterMatch');
    if (reveal != null && reveal != next.revealPhotosAfterMatch) {
      next = next.copyWith(revealPhotosAfterMatch: reveal);
      changed = true;
    }
    final visibilityRaw = read<String>('profileVisibility');
    if (visibilityRaw != null) {
      final v = ProfileVisibility.fromValue(visibilityRaw);
      if (v != next.profileVisibility) {
        next = next.copyWith(profileVisibility: v);
        changed = true;
      }
    }
    final dark = read<bool>('useDarkMode');
    if (dark != null && dark != next.useDarkMode) {
      next = next.copyWith(useDarkMode: dark);
      changed = true;
    }
    final master = read<bool>('notificationsEnabled');
    if (master != null && master != next.notificationsEnabled) {
      next = next.copyWith(notificationsEnabled: master);
      changed = true;
    }
    final notifyMatches = read<bool>('notifyMatches');
    final notifyLikes = read<bool>('notifyLikes');
    final notifyMessages = read<bool>('notifyMessages');
    final notifyDatingHour = read<bool>('notifyDatingHour');
    final blur = read<bool>('blurChatImages');
    if (notifyMatches != null && notifyMatches != next.notifyMatches) {
      next = next.copyWith(notifyMatches: notifyMatches);
      changed = true;
    }
    final chatBg = read<String>('chatBackground');
    if (chatBg != null &&
        ChatBackgrounds.isValid(chatBg) &&
        chatBg != next.chatBackground) {
      next = next.copyWith(chatBackground: chatBg);
      changed = true;
    }
    final paused = read<bool>('paused');
    if (paused != null && paused != next.paused) {
      var vis = next.profileVisibility;
      if (paused) {
        vis = ProfileVisibility.hidden;
      } else if (vis == ProfileVisibility.hidden) {
        vis = ProfileVisibility.everyone;
      }
      next = next.copyWith(paused: paused, profileVisibility: vis);
      changed = true;
    }
    final icebreaker = read<bool>('contextIcebreakerEnabled');
    if (icebreaker != null && icebreaker != next.contextIcebreakerEnabled) {
      next = next.copyWith(contextIcebreakerEnabled: icebreaker);
      changed = true;
    }
    final dealbreaker = read<bool>('habitsDealbreaker');
    if (dealbreaker != null && dealbreaker != next.habitsDealbreaker) {
      next = next.copyWith(habitsDealbreaker: dealbreaker);
      changed = true;
    }
    if (notifyLikes != null && notifyLikes != next.notifyLikes) {
      next = next.copyWith(notifyLikes: notifyLikes);
      changed = true;
    }
    if (notifyMessages != null && notifyMessages != next.notifyMessages) {
      next = next.copyWith(notifyMessages: notifyMessages);
      changed = true;
    }
    if (notifyDatingHour != null && notifyDatingHour != next.notifyDatingHour) {
      next = next.copyWith(notifyDatingHour: notifyDatingHour);
      changed = true;
    }
    if (blur != null && blur != next.blurChatImages) {
      next = next.copyWith(blurChatImages: blur);
      changed = true;
    }
    // Die Tastatur (0.11.0): sie übersteht damit eine Neuinstallation.
    final belegung = read<String>('tastaturBelegung');
    if (belegung != null && belegung != next.tastaturBelegung) {
      next = next.copyWith(tastaturBelegung: belegung);
      changed = true;
    }
    final stil = read<String>('tastaturStil');
    if (stil != null && stil != next.tastaturStil) {
      next = next.copyWith(tastaturStil: stil);
      changed = true;
    }
    final tastaturFarbe = read<int>('tastaturFarbe');
    if (tastaturFarbe != null && tastaturFarbe != next.tastaturFarbe) {
      next = next.copyWith(tastaturFarbe: tastaturFarbe);
      changed = true;
    }

    if (changed) {
      setzeStand(next);
      await _persist();
    }
  }
}
