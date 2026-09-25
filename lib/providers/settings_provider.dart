import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/app_settings.dart';
import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/utils/constants.dart';

/// StateNotifier, der die App-Einstellungen verwaltet und sicher persistiert.
///
/// Zuständig für: Blind Mode, Foto-Freigabe, Sichtbarkeit, Theme, Onboarding, Swipe-Modus.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._storage, this._ref) : super(AppSettings.defaults()) {
    _load();
  }

  final LocalStorage _storage;
  final Ref _ref;

  /// Lädt die gespeicherten Einstellungen beim Start.
  Future<void> _load() async {
    try {
      final raw = await _storage.getString(AppConstants.prefsSettingsKey);
      if (raw != null) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          state = AppSettings.fromJson(map);
        } catch (_) {
          // Bei korrupten Daten: Defaults beibehalten.
        }
      }
    } finally {
      // Router benachrichtigen, dass die Settings geladen sind.
      // Der Router wartet beim Start auf diesen Zustand (zusätzlich zum
      // Auth-Status), bevor die initiale Route bestimmt wird - sonst
      // Race Condition zwischen Onboarding-Flag- und Auth-Check und der
      // "Konto erstellen"-Screen blitzt vor den Willkommensscreens auf.
      _ref.read(settingsLoadedProvider.notifier).state = true;
    }
  }

  Future<void> _persist() async {
    await _storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(state.toJson()),
    );
  }

  /// Schaltet den Blind Mode um.
  Future<void> toggleBlindMode(bool value) async {
    state = state.copyWith(blindModeEnabled: value);
    await _persist();
  }

  /// Blendet den MFA-Einrichtungshinweis dauerhaft aus.
  Future<void> setMfaSetupDismissed(bool value) async {
    state = state.copyWith(mfaSetupDismissed: value);
    await _persist();
  }

  /// Legt fest, ob die eigenen Fotos erst nach Match sichtbar sind.
  Future<void> setRevealPhotosAfterMatch(bool value) async {
    state = state.copyWith(revealPhotosAfterMatch: value);
    await _persist();
  }

  /// Profil-Sichtbarkeit (Privatsphäre) - EINE zentrale Steuerung.
  /// 'hidden' IST der Pausenmodus: Der lokale Flag `paused` und der
  /// serverseitige Filter (profiles.paused, 076) werden mitgeführt, damit
  /// Discovery/Find-your-Match den Nutzer sofort ausblenden.
  Future<void> setProfileVisibility(ProfileVisibility value) async {
    final wasPause = state.profileVisibility == ProfileVisibility.hidden;
    final isPause = value == ProfileVisibility.hidden;
    if (value == state.profileVisibility) return;
    state = state.copyWith(profileVisibility: value, paused: isPause);
    await _persist();
    scheduleUiPrefsServerSync(state);
    // Serverseitige Umsetzung (076): die Kandidaten-RPCs lesen
    // profiles.paused. Nur bei echtem Wechsel schreiben.
    if (SupabaseService.isInitialized && isPause != wasPause) {
      unawaited(() async {
        try {
          await SupabaseDatabaseService(SupabaseService.client)
              .updateOwnProfile({'paused': isPause});
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Settings] Pause-Sync fehlgeschlagen: $e');
          }
        }
      }());
    }
  }

  /// Setzt das Theme (null = System).
  Future<void> setDarkMode(bool? value) async {
    state = state.copyWith(useDarkMode: value);
    await _persist();
  }

  /// Setzt die maximale Distanz (km) für den Entfernungsfilter.
  Future<void> setMaxDistanceKm(int value) async {
    state = state.copyWith(maxDistanceKm: value);
    await _persist();
  }

  /// Setzt die bevorzugte Alterspanne (Jahre).
  Future<void> setAgeRange(int min, int max) async {
    state = state.copyWith(ageRangeMin: min, ageRangeMax: max);
    await _persist();
  }

  /// Markiert den Persönlichkeitstest als abgeschlossen.
  ///
  /// Setzt zusätzlich onboardingDone ("Niemals-Einrichtung"-Garantie):
  /// Der Test ist der LETZTE Schritt der Einrichtungskette - ab jetzt
  /// erzwingt der Router Einrichtung/Test nie wieder.
  Future<void> completePersonalityTest() async {
    state = state.copyWith(
      personalityTestCompleted: true,
      onboardingDone: true,
    );
    await _persist();
  }

  /// Markiert das Onboarding als abgeschlossen.
  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingCompleted: true);
    await _persist();
  }

  /// Markiert die einmaligen Settings/Privacy nach Registrierung als abgeschlossen.
  Future<void> completeOneTimeSettings() async {
    state = state.copyWith(oneTimeSettingsCompleted: true);
    await _persist();
  }

  /// Markiert die Community-Richtlinien als akzeptiert.
  Future<void> acceptCommunityGuidelines() async {
    state = state.copyWith(communityGuidelinesAccepted: true);
    await _persist();
  }

  /// Pausenmodus (v0.8.0): Profil unsichtbar in Discovery/FYM, Funken
  /// und Chats bleiben. Serverseitig gespiegelt (profiles.paused, 076).
  /// Hält die Sichtbarkeit konsistent: paused == hidden (eine Steuerung).
  Future<void> setPaused(bool value) async {
    var vis = state.profileVisibility;
    if (value) {
      vis = ProfileVisibility.hidden;
    } else if (vis == ProfileVisibility.hidden) {
      vis = ProfileVisibility.everyone;
    }
    state = state.copyWith(profileVisibility: vis, paused: value);
    await _persist();
  }

  /// Habit-Dealbreaker (v0.8.0): nur Kandidaten mit <= eigenem Konsum.
  Future<void> setHabitsDealbreaker(bool value) async {
    state = state.copyWith(habitsDealbreaker: value);
    await _persist();
  }

  /// Kontext-Icebreaker-Chip im Chat ein-/ausschalten (v0.8.0).
  Future<void> setContextIcebreaker(bool value) async {
    state = state.copyWith(contextIcebreakerEnabled: value);
    await _persist();
  }

  /// Server-Flags (Migration 076) übernehmen: Pausenmodus und
  /// Habit-Dealbreaker. Server gewinnt (gleiche Logik wie ui_prefs).
  /// paused bleibt mit der Sichtbarkeit konsistent (paused == hidden).
  Future<void> applyServerFlags({bool? paused, bool? habitsDealbreaker}) async {
    var next = state;
    var changed = false;
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
    if (habitsDealbreaker != null &&
        habitsDealbreaker != next.habitsDealbreaker) {
      next = next.copyWith(habitsDealbreaker: habitsDealbreaker);
      changed = true;
    }
    if (changed) {
      state = next;
      await _persist();
    }
  }

  /// Übernimmt die serverseitig gespiegelten UI-Einstellungen
  /// (profiles.ui_prefs, Migration 074) nach Login/Neuinstallation.
  /// Server gewinnt bei vorhandenen Schlüsseln; fehlende Schlüssel
  /// (alter Serverstand) lassen den lokalen Stand unangetastet.
  Future<void> applyServerUiPrefs(Map<String, dynamic>? ui) async {
    if (ui == null || ui.isEmpty) return;
    var next = state;
    var changed = false;

    T? read<T>(String key) => ui[key] is T ? ui[key] as T : null;

    final blind = read<bool>('blindModeEnabled');
    if (blind != null && blind != next.blindModeEnabled) {
      next = next.copyWith(blindModeEnabled: blind);
      changed = true;
    }
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

    if (changed) {
      state = next;
      await _persist();
    }
  }

  /// Markiert die Einführung (Willkommens-Screen) als gesehen, damit sie
  /// beim nächsten Start nicht erneut erscheint.
  Future<void> markIntroSeen() async {
    state = state.copyWith(introSeen: true);
    await _persist();
  }

  /// Markiert das Dating Hour Intro (Regeln + Erklärung) als gesehen.
  Future<void> markDatingHourIntroSeen() async {
    state = state.copyWith(datingHourIntroSeen: true);
    await _persist();
  }

  /// Dating Hour: Automatische Teilnahme am nächsten Event aktivieren
  /// bzw. deaktivieren (Abfrage nach Ende eines Events).
  Future<void> setDatingHourAutoJoin(bool value) async {
    state = state.copyWith(datingHourAutoJoin: value);
    await _persist();
  }

  /// Übernimmt die Setup-Flags vom Server (nach Login/Session-Restore).
  ///
  /// Der Server gewinnt bei "abgeschlossen" – so erscheint die Einrichtung
  /// nach einer App-Neuinstallation NICHT erneut, nur weil die lokale
  /// Speicherung fehlt. Lokal wird der Stand ebenfalls gespiegelt.
  ///
  /// [themeName]: Gespeicherte Themefarbe (profiles.theme_name, Migration
  /// 071) - wird beim Login/Neuinstallation direkt wieder angewendet.
  /// Nur bei nicht-leerem Wert (null = Server kennt noch keine Farbe).
  ///
  /// [datingHourIntroSeen]: Dating-Hour-Regeln/Erklärung bereits gesehen
  /// (profiles.dating_hour_intro_seen, Migration 071). Nur-Upgrade: Das
  /// Intro erscheint pro Konto nur EINMAL, nicht bei jeder Neuinstallation.
  Future<void> syncSetupFlagsFromServer({
    required bool oneTimeSettingsCompleted,
    required bool communityGuidelinesAccepted,
    required bool personalityTestCompleted,
    required bool onboardingDone,
    String? themeName,
    bool? datingHourIntroSeen,
  }) async {
    var changed = false;
    var next = state;
    if (oneTimeSettingsCompleted && !next.oneTimeSettingsCompleted) {
      next = next.copyWith(oneTimeSettingsCompleted: true);
      changed = true;
    }
    if (communityGuidelinesAccepted && !next.communityGuidelinesAccepted) {
      next = next.copyWith(communityGuidelinesAccepted: true);
      changed = true;
    }
    if (personalityTestCompleted && !next.personalityTestCompleted) {
      next = next.copyWith(personalityTestCompleted: true);
      changed = true;
    }
    // onboardingDone ist das "Niemals-Einrichtung"-Flag (Migration 065):
    // Nur-Upgrade - ein einmaliger Abschluss wird NIE zurückgenommen.
    if (onboardingDone && !next.onboardingDone) {
      next = next.copyWith(onboardingDone: true);
      changed = true;
    }
    // Themefarbe: Server gewinnt bei bekanntem Wert ( Neuinstallation
    // soll die Farbe direkt wiederhaben - Nutzerwunsch).
    if (themeName != null &&
        themeName.isNotEmpty &&
        themeName != next.themeName) {
      next = next.copyWith(themeName: themeName);
      changed = true;
    }
    // Dating-Hour-Intro: Nur-Upgrade (gesehen bleibt gesehen).
    if (datingHourIntroSeen == true && !next.datingHourIntroSeen) {
      next = next.copyWith(datingHourIntroSeen: true);
      changed = true;
    }
    if (changed) {
      state = next;
      await _persist();
    }
  }

  /// Markiert die Einrichtungskette als abgeschlossen ("Niemals-Einrichtung"-
  /// Garantie, Migration 065). Nur-Upgrade.
  Future<void> markOnboardingDone() async {
    if (state.onboardingDone) return;
    state = state.copyWith(onboardingDone: true);
    await _persist();
  }

  /// Nach frischer Registrierung (v0.9.0-Fix): Die Einrichtung MUSS
  /// sofort kommen - nicht erst beim 2. Appstart, wenn der Server-Flag-
  /// Sync ggf. einen falschen Stand geliefert hat. Lokal forciert;
  /// der Server-Sync (syncSetupFlagsFromServer) ueberschreibt true nur
  /// fuer BESTEHende Konten.
  Future<void> markOnboardingPending() async {
    state = state.copyWith(onboardingDone: false, onboardingCompleted: false);
    await _persist();
  }

  /// Aktiviert oder deaktiviert Benachrichtigungen.
  Future<void> setNotificationsEnabled(bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei neuem Match.
  Future<void> setNotifyMatches(bool enabled) async {
    state = state.copyWith(notifyMatches: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei erhaltenem Like.
  Future<void> setNotifyLikes(bool enabled) async {
    state = state.copyWith(notifyLikes: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Benachrichtigung bei neuer Chat-Nachricht.
  Future<void> setNotifyMessages(bool enabled) async {
    state = state.copyWith(notifyMessages: enabled);
    await _persist();
  }

  /// Einzel-Schalter: Erinnerung, wenn die Dating Hour gleich beginnt.
  Future<void> setNotifyDatingHour(bool enabled) async {
    state = state.copyWith(notifyDatingHour: enabled);
    await _persist();
  }

  /// Bilder im Chat standardmäßig verpixelt anzeigen?
  Future<void> setBlurChatImages(bool enabled) async {
    state = state.copyWith(blurChatImages: enabled);
    await _persist();
  }

  /// Farbschema wechseln (ThestiaTheme-Name).
  Future<void> setThemeName(String name) async {
    state = state.copyWith(themeName: name);
    await _persist();
  }

  /// Chat-Hintergrund wählen (v0.9.1): 'none', Muster oder 'custom'.
  /// Unbekannte IDs fallen auf 'none' zurück.
  Future<void> setChatBackground(String id) async {
    final valid = ChatBackgrounds.isValid(id) ? id : ChatBackgrounds.none;
    state = state.copyWith(chatBackground: valid);
    await _persist();
  }

  /// Lokalen Pfad des eigenen Hintergrundbildes setzen/löschen (nur lokal).
  Future<void> setChatBackgroundPath(String? path) async {
    state = state.copyWith(chatBackgroundPath: path);
    await _persist();
  }

  /// Kurzer Willkommensscreen nach Registrierung wurde gezeigt.
  Future<void> markSignupWelcomeSeen() async {
    state = state.copyWith(signupWelcomeSeen: true);
    await _persist();
  }

  /// Setzt alle Einstellungen auf die Standardwerte zurück
  /// (z. B. nach Account-Löschung – keine Alt-Daten im neuen Account).
  Future<void> resetToDefaults() async {
    state = AppSettings.defaults();
    await _persist();
  }
}

/// Zeigt an, ob die Einstellungen aus dem Speicher geladen wurden.
///
/// Der Router wartet beim App-Start auf diesen Zustand (zusätzlich zum
/// Auth-Status), bevor die initiale Route bestimmt wird. Erst wenn beide
/// Checks abgeschlossen sind, wird weitergeleitet - so ist die
/// Screen-Reihenfolge beim Erststart garantiert (Willkommen vor Login).
final settingsLoadedProvider = StateProvider<bool>((ref) => false);

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
          await SupabaseDatabaseService(SupabaseService.client)
              .updateOwnProfile({
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

/// Provider für die App-Einstellungen.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(localStorageProvider);
  return SettingsNotifier(storage, ref);
});
