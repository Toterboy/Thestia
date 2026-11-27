import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/models/settings/nachricht_ueberdenken.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/models/profile/profile_visibility.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/utils/chat/chat_backgrounds.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'settings_nachrichtpruefung.dart';
part 'settings_tastatur.dart';
part 'settings_ui_prefs.dart';

/// StateNotifier, der die App-Einstellungen verwaltet und sicher persistiert.
///
/// Zuständig für: Blind Mode, Foto-Freigabe, Sichtbarkeit, Theme, Onboarding, Swipe-Modus.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._storage, this._ref) : super(AppSettings.defaults()) {
    _load();
  }

  final LocalStorage _storage;
  final Ref _ref;

  /// Signalisiert, wann die Einstellungen aus dem Speicher da sind.
  ///
  /// WICHTIG: Die Einstellungen kommen ASYNCHRON aus dem Speicher. Wer
  /// sie vorher liest, sieht nur die Vorgabewerte - und kann damit eine
  /// Entscheidung treffen, die falsch ist (der Chat zeigte den
  /// Chat-Hintergrund-Dialog auch bei Personen, die ihn schon
  /// weggedrückt hatten). [whenLoaded] wartet auf den echten Stand.
  final Completer<void> _geladen = Completer<void>();

  /// Wartet, bis die Einstellungen geladen sind, und liefert sie.
  ///
  /// Nach dem ersten Aufruf kommt der Wert sofort (der Ladevorgang ist
  /// dann erledigt).
  Future<AppSettings> whenLoaded() async {
    await _geladen.future;
    return state;
  }

  /// Lädt die gespeicherten Einstellungen beim Start.
  Future<void> _load() async {
    try {
      final raw = await _storage.getString(AppConstants.prefsSettingsKey);
      if (raw != null) {
        // Bei korrupten Daten: Defaults beibehalten.
        bestEffortSync('fromJson', () {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          state = AppSettings.fromJson(map);
        });
      }
    } finally {
      // Router benachrichtigen, dass die Settings geladen sind.
      // Der Router wartet beim Start auf diesen Zustand (zusätzlich zum
      // Auth-Status), bevor die initiale Route bestimmt wird - sonst
      // Race Condition zwischen Onboarding-Flag- und Auth-Check und der
      // "Konto erstellen"-Screen blitzt vor den Willkommensscreens auf.
      _ref.read(settingsLoadedProvider.notifier).state = true;
      if (!_geladen.isCompleted) _geladen.complete();
    }
  }

  Future<void> _persist() async {
    // BEFUND (07.11.2026, Betreiber): "Der Hintergrund, den man
    // auswählt, wird nicht gespeichert."
    //
    // DIE URSACHE: Das Schreiben in den Keystore kann fehlschlagen (bei
    // gleichzeitigem Zugriff - der Picker schrieb zweimal hintereinander:
    // Pfad und Auswahl). Der Fehler wurde nur protokolliert: die
    // Oberfläche zeigte die neue Einstellung trotzdem an (der Zustand
    // ist optimistisch gesetzt), aber beim nächst Start war sie weg.
    // Der Nutzer sah keine Meldung - für ihn hat die App die Auswahl
    // einfach verworfen.
    //
    // DESHALB: Drei Versuche mit kurzer Pause (der Keystore ist nach
    // einem anderen Zugriff wieder frei) - und wenn es dann immer noch
    // nicht klappt, wird es GEMELDET statt still zu scheitern.
    final json = jsonEncode(state.toJson());
    // Doppelte Schreibvorgänge vermeiden: der Chat-Hintergrund-Picker ruft
    // ansonsten zweimal hintereinander (Pfad + Auswahl) und schreibt
    // zweimal den kompletten Stand in den Keystore.
    if (json == _lastPersisted) return;

    for (var versuch = 0; versuch < 3; versuch++) {
      try {
        await _storage.saveString(AppConstants.prefsSettingsKey, json);
        _lastPersisted = json;
        persistFehlgeschlagen = null;
        return;
      } catch (e) {
        if (versuch < 2) {
          // Kurze Pause: der Keystore ist nach einem anderen Zugriff
          // wieder frei.
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (versuch + 1)),
          );
          continue;
        }
        if (kDebugMode) {
          debugPrint('[Settings] Persist fehlgeschlagen: $e');
        }
        // Der Merker wird zurückgesetzt, damit der nächst Versuch
        // wieder schreibt - und der Nutzer bekommt eine Meldung.
        _lastPersisted = null;
        persistFehlgeschlagen = 'settings.saveFailed';
      }
    }
  }

  /// Der Text-Schlüssel des letzten Schreibfehlers (null = alles
  /// gespeichert).
  ///
  /// Die Oberfläche liest das nach einem Setzen und zeigt eine Meldung:
  /// eine Einstellung, die nicht gespeichert wurde, muss der Nutzer
  /// erfahren - sonst denkt er, sie wäre übernommen worden.
  String? persistFehlgeschlagen;

  /// Zuletzt erfolgreich geschriebener JSON-Stand (Deduplizierung).
  String? _lastPersisted;

  // Der Blind Mode wird nicht mehr umgeschaltet (NUTZERWUNSCH
  // 01.11.2026): "Persönlichkeit vor Aussehen" ist das Prinzip der
  // App, keinstellbar. Der Wert steht fest in AppSettings.

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
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).updateOwnProfile({'paused': isPause});
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
  /// der Server-Sync (syncSetupFlagsFromServer) überschreibt true nur
  /// für BESTEHende Konten.
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
  ///
  /// Wird auch serverseitig gespiegelt (profiles.theme_name, Migration
  /// 071). Das ist kein Luxus: der lokale Speicher liegt im Keystore und
  /// wird mit der App gelöscht - ohne den Server-Spiegel wäre die
  /// Farbe nach einer Neuinstallation weg.
  ///
  /// Der Sync stand vorher NUR im Einstellungs-Screen. Wer die Farbe im
  /// Onboarding wählte (der normale Weg beim ersten Start), kam dort
  /// nie vor - die Farbe wurde nie gespiegelt. Deshalb liegt er jetzt
  /// hier, im Provider: so gilt er für jeden Weg.
  Future<void> setThemeName(String name) async {
    if (state.themeName == name) return;
    state = state.copyWith(themeName: name);
    await _persist();
    unawaited(_syncThemeNameServer(name));
  }

  /// Spiegelt die Themefarbe auf den Server (Best effort).
  Future<void> _syncThemeNameServer(String name) async {
    try {
      if (!SupabaseService.isInitialized) return;
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'theme_name': name});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Settings] Theme-Sync fehlgeschlagen: $e');
      }
    }
  }

  /// Mikrofon-Offenlegung bestätigt (Google-Play-Richtlinie).
  ///
  /// Wird gesetzt, nachdem der Nutzer im Chat-Dialog gelesen hat, WARUM
  /// die App aufnimmt. Erst danach wird die Berechtigung angefragt.
  /// Ohne diesen Schalter würde die Offenlegung bei jeder einzelnen
  /// Sprachnachricht erneut erscheinen - nervend und für den Nutzer
  /// ein Grund, alles abzulehnen.
  Future<void> setMicDisclosureAccepted(bool value) async {
    state = state.copyWith(micDisclosureAccepted: value);
    await _persist();
  }

  /// Kamera-Offenlegung bestätigt (Google-Play-Richtlinie).
  ///
  /// Gegenteil von [setMicDisclosureAccepted]: wird gesetzt, nachdem der
  /// Nutzer im Verifikationsschritt gelesen hat, warum die Kamera
  /// genutzt wird. Die Verifikation öffnet die Kamera direkt beim
  /// Betreten - ohne diese Bestätigen wäre das ein Antrag, den der
  /// Nutzer nicht erwartet.
  Future<void> setCameraDisclosureAccepted(bool value) async {
    state = state.copyWith(cameraDisclosureAccepted: value);
    await _persist();
  }

  /// Die prominente Standort-Offenlegung wurde bestätigt.
  ///
  /// Google Play verlangt für empfindliche Berechtigungen eine
  /// sichtbare Begründung IN DER APP, bevor der Systemdialog erscheint
  /// (BEFUND 06.11.2026: für Kamera und Mikrofon gab es das bereits,
  /// für den Standort fehlte es).
  Future<void> setLocationDisclosureAccepted(bool value) async {
    state = state.copyWith(locationDisclosureAccepted: value);
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

  /// Eigenes Hintergrundbild UND Auswahl in EINEM Schritt setzen.
  ///
  /// Getrennte Aufrufe von [setChatBackgroundPath] + [setChatBackground]
  /// erzeugten zwei komplette JSON-Encodes und zwei Keystore-Writes pro Tap.
  /// [path] null entfernt das Bild und setzt auf "kein Hintergrund".
  Future<void> setCustomChatBackground(String? path) async {
    state = state.copyWith(
      chatBackgroundPath: path,
      chatBackground: path == null
          ? ChatBackgrounds.none
          : ChatBackgrounds.custom,
    );
    await _persist();
  }

  /// Der Ruhemodus: die App schweigt bis [bis] (null = der Ruhemodus
  /// ist vorbei).
  ///
  /// DER WEG (Plan 0.11.0, "Begegnung statt Bildschirm"): Nach einem
  /// Treffen, das beide bestätigt haben, kann der Nutzer die App für
  /// den Abend stumm schalten: "Genießt die Zeit - Thestia schweigt bis
  /// morgen." Die App feiert damit Abwesenheit statt Bindung zu erzeugen.
  ///
  /// LOKAL: Der Zustand bleibt auf diesem Gerät - er wird nicht auf den
  /// Server gespiegelt (das ist eine Sache zwischen dem Nutzer und
  /// seinem Telefon).
  Future<void> setzeRuhemodus(DateTime? bis) async {
    state = state.copyWith(ruhemodusBis: bis);
    await _persist();
  }

  /// Kurzer Willkommensscreen nach Registrierung wurde gezeigt.
  Future<void> markSignupWelcomeSeen() async {
    state = state.copyWith(signupWelcomeSeen: true);
    await _persist();
  }

  /// Sicherheits-Aufklärung vor der Einrichtung abgeschlossen.
  ///
  /// Nur-Upgrade: der Router erzwingt die Aufklärung danach nie wieder,
  /// auch wenn der lokale Fortschritt (der beim Schließen/Crash
  /// weiterläuft) fehlt.
  Future<void> completeDatingSafetyEducation() async {
    if (state.datingSafetyEducationCompleted) return;
    state = state.copyWith(datingSafetyEducationCompleted: true);
    await _persist();
  }

  /// Chat-Hintergrund-Auswahl beim ersten Chat wurde gezeigt (v0.10.0).
  Future<void> markChatBackgroundSeen() async {
    state = state.copyWith(chatBackgroundSeen: true);
    await _persist();
  }

  /// Entfernungs-Anzeige ein- oder ausschalten (v0.10.0).
  ///
  /// Über den Server gespiegelt, weil die Anzeegeräte fremd
  /// entscheiden: ein eingeschalteter Schalter muss auch auf einem
  /// anderen Gerät gelten.
  Future<void> setShowDistance(bool value) async {
    if (state.showDistance == value) return;
    state = state.copyWith(showDistance: value);
    await _persist();
    unawaited(_syncShowDistanceServer(value));
  }

  /// Zeigt meinen Namen bei Transit Spark? (v0.10.1)
  ///
  /// BEFUND (Betreiber, 10.11.2026): Der Name beim Zuwinken soll
  /// abschaltbar sein. Über den Server gespiegelt, weil die ANDERE
  /// Person entscheidet: sie sieht den Namen nur, wenn der Server ihn
  /// freigibt (Migration 208).
  Future<void> setTransitShowName(bool value) async {
    // BEFUND (10.11.2026): Jede Änderung am Schalter ist eine bewusste
    // Entscheidung - also wird das Flag mitgesetzt. Danach kommt der
    // Dialog beim Öffnen des Transit-Radars nicht mehr.
    //
    // (Und: ist der Wert gleich, wird trotzdem gespeichert - sonst
    // würde das Flag nie gesetzt, wenn der Wert schon passend steht.)
    if (state.transitShowName == value && state.transitShowNameSet) return;
    state = state.copyWith(transitShowName: value, transitShowNameSet: true);
    await _persist();
    unawaited(_syncTransitShowNameServer(value));
  }

  Future<void> _syncTransitShowNameServer(bool value) async {
    try {
      if (!SupabaseService.isInitialized) return;
      await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
        'transit_show_name': value,
        'transit_show_name_set': true,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Settings] transit_show_name-Sync fehlgeschlagen: $e');
      }
    }
  }

  Future<void> _syncShowDistanceServer(bool value) async {
    try {
      if (!SupabaseService.isInitialized) return;
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'show_distance': value});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Settings] show_distance-Sync fehlgeschlagen: $e');
      }
    }
  }

  /// NUTZERWUNSCH (22.11.2026): "Man soll diese Punkte und die
  /// Gewohnheiten einzeln fürs öffentliche Profil an und aus machen
  /// können."
  ///
  /// Je Punkt EIN Schalter. Der Server entscheidet (Migration 222): die
  /// öffentlich Projektion liefert die Angabe nur, wenn der Schalter
  /// an ist - ein Schalter nur im Gerät wäre wertlos.
  Future<void> setShowMusicLiked(bool value) => _setPublicSwitch(
    'show_music_liked',
    value,
    (s) => s.showMusicLiked,
    (s, v) => s.copyWith(showMusicLiked: v),
  );

  Future<void> setShowMusicDisliked(bool value) => _setPublicSwitch(
    'show_music_disliked',
    value,
    (s) => s.showMusicDisliked,
    (s, v) => s.copyWith(showMusicDisliked: v),
  );

  Future<void> setShowFavoriteSong(bool value) => _setPublicSwitch(
    'show_favorite_song',
    value,
    (s) => s.showFavoriteSong,
    (s, v) => s.copyWith(showFavoriteSong: v),
  );

  Future<void> setShowFavoriteBand(bool value) => _setPublicSwitch(
    'show_favorite_band',
    value,
    (s) => s.showFavoriteBand,
    (s, v) => s.copyWith(showFavoriteBand: v),
  );

  Future<void> setShowHabitsSmoking(bool value) => _setPublicSwitch(
    'show_habits_smoking',
    value,
    (s) => s.showHabitsSmoking,
    (s, v) => s.copyWith(showHabitsSmoking: v),
  );

  Future<void> setShowHabitsAlcohol(bool value) => _setPublicSwitch(
    'show_habits_alcohol',
    value,
    (s) => s.showHabitsAlcohol,
    (s, v) => s.copyWith(showHabitsAlcohol: v),
  );

  Future<void> setShowHabitsDrugs(bool value) => _setPublicSwitch(
    'show_habits_drugs',
    value,
    (s) => s.showHabitsDrugs,
    (s, v) => s.copyWith(showHabitsDrugs: v),
  );

  /// Setzt einen der öffentlich Schalter: lokal, in den Cache und auf
  /// dem Server.
  ///
  /// Der Server ist die Wahrheit - die ANDERE Person sieht das Profil
  /// über den Server. Deshalb wird der Wert auch dorthin geschrieben
  /// (best effort: der Server-Schalter entscheidet).
  Future<void> _setPublicSwitch(
    String spalte,
    bool wert,
    bool Function(AppSettings) lesen,
    AppSettings Function(AppSettings, bool) setzen,
  ) async {
    if (lesen(state) == wert) return;
    state = setzen(state, wert);
    await _persist();
    try {
      if (!SupabaseService.isInitialized) return;
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({spalte: wert});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Settings] $spalte-Sync fehlgeschlagen: $e');
      }
    }
  }

  /// Übernimmt die serverseitig gespiegelten Schalter, die in eigenen
  /// Spalten stehen (v0.10.0).
  ///
  /// BETROFFEN:
  ///   * show_distance - die Entfernungsanzeige. Der Schalter wurde
  ///     bisher NUR geschrieben, nie gelesen. Nach einer Neuinstallation
  ///     oder auf einem zweiten Gerät zeigte der Schalter "aus", während
  ///     der Server weiter true hatte: der Nutzer glaubte, die Entfernung
  ///     sei verborgen, und sie wurde trotzdem angezeigt.
  ///   * notifications_enabled, notify_matches, notify_likes,
  ///     notify_messages, notify_dating_hour - die Push-Schalter.
  ///
  /// "Server gewinnt" bei vorhandenen Werten. Fehlende Spalten (alter
  /// Serverstand) lassen den lokalen Stand unangetastet.
  Future<void> applyServerSwitches(Map<String, dynamic>? row) async {
    if (row == null || row.isEmpty) return;
    var next = state;
    var changed = false;

    T? read<T>(String key) => row[key] is T ? row[key] as T : null;

    final showDistance = read<bool>('show_distance');
    if (showDistance != null && showDistance != next.showDistance) {
      next = next.copyWith(showDistance: showDistance);
      changed = true;
    }

    // BEFUND (10.11.2026): Der Name beim Transit-Zuwinken muss auch auf
    // einem zweiten Gerät gelten - der SERVER entscheidet, ob der Name
    // ankommt. Ohne dieses Lesen würde der Schalter lokal "aus" sein,
    // während der Server weiter true hat: der Nutzer glaubt, sein Name
    // bleibe verborgen, und er wird trotzdem angezeigt.
    final transitShowName = read<bool>('transit_show_name');
    if (transitShowName != null && transitShowName != next.transitShowName) {
      next = next.copyWith(transitShowName: transitShowName);
      changed = true;
    }

    // BEFUND (10.11.2026): Das Flag "hat der Nutzer entschieden" kommt
    // vom Server - sonst fragt der Dialog auf dem zweiten Gerät nochmal,
    // obwohl die Entscheidung schon gefallen ist.
    final transitShowNameSet = read<bool>('transit_show_name_set');
    if (transitShowNameSet != null &&
        transitShowNameSet != next.transitShowNameSet) {
      next = next.copyWith(transitShowNameSet: transitShowNameSet);
      changed = true;
    }

    // NUTZERWUNSCH (22.11.2026): Die Schalter für Musik und
    // Gewohnheiten kommen auch vom Server - sie entscheiden, was andere
    // sehen. Fehlt eine Spalte (alter Serverstand), bleibt der lokale
    // Stand stehen.
    final showMusicLiked = read<bool>('show_music_liked');
    if (showMusicLiked != null && showMusicLiked != next.showMusicLiked) {
      next = next.copyWith(showMusicLiked: showMusicLiked);
      changed = true;
    }
    final showMusicDisliked = read<bool>('show_music_disliked');
    if (showMusicDisliked != null &&
        showMusicDisliked != next.showMusicDisliked) {
      next = next.copyWith(showMusicDisliked: showMusicDisliked);
      changed = true;
    }
    final showFavoriteSong = read<bool>('show_favorite_song');
    if (showFavoriteSong != null && showFavoriteSong != next.showFavoriteSong) {
      next = next.copyWith(showFavoriteSong: showFavoriteSong);
      changed = true;
    }
    final showFavoriteBand = read<bool>('show_favorite_band');
    if (showFavoriteBand != null && showFavoriteBand != next.showFavoriteBand) {
      next = next.copyWith(showFavoriteBand: showFavoriteBand);
      changed = true;
    }
    final showHabitsSmoking = read<bool>('show_habits_smoking');
    if (showHabitsSmoking != null &&
        showHabitsSmoking != next.showHabitsSmoking) {
      next = next.copyWith(showHabitsSmoking: showHabitsSmoking);
      changed = true;
    }
    final showHabitsAlcohol = read<bool>('show_habits_alcohol');
    if (showHabitsAlcohol != null &&
        showHabitsAlcohol != next.showHabitsAlcohol) {
      next = next.copyWith(showHabitsAlcohol: showHabitsAlcohol);
      changed = true;
    }
    final showHabitsDrugs = read<bool>('show_habits_drugs');
    if (showHabitsDrugs != null && showHabitsDrugs != next.showHabitsDrugs) {
      next = next.copyWith(showHabitsDrugs: showHabitsDrugs);
      changed = true;
    }

    final notif = read<bool>('notifications_enabled');
    if (notif != null && notif != next.notificationsEnabled) {
      next = next.copyWith(notificationsEnabled: notif);
      changed = true;
    }
    final matches = read<bool>('notify_matches');
    if (matches != null && matches != next.notifyMatches) {
      next = next.copyWith(notifyMatches: matches);
      changed = true;
    }
    final likes = read<bool>('notify_likes');
    if (likes != null && likes != next.notifyLikes) {
      next = next.copyWith(notifyLikes: likes);
      changed = true;
    }
    final messages = read<bool>('notify_messages');
    if (messages != null && messages != next.notifyMessages) {
      next = next.copyWith(notifyMessages: messages);
      changed = true;
    }
    final datingHour = read<bool>('notify_dating_hour');
    if (datingHour != null && datingHour != next.notifyDatingHour) {
      next = next.copyWith(notifyDatingHour: datingHour);
      changed = true;
    }

    if (changed) {
      state = next;
      await _persist();
    }
  }

  /// Lädt die servergehaltenen Schalter und wendet sie an.
  ///
  /// Liest die EIGENE Zeile - mit der verengten profiles-Policy
  /// (Migration 144) ist das genau die Zeile, die der Nutzer sehen darf.
  Future<void> refreshServerSwitches() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final userId = SupabaseService.currentUser?.id;
      if (userId == null || userId.isEmpty) return;
      final row = await SupabaseDatabaseService(
        SupabaseService.client,
      ).fetchOwnSwitches();
      await applyServerSwitches(row);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Settings] Server-Schalter nicht lesbar: $e');
      }
    }
  }

  /// Setzt den Modus der Nachrichten-Prüfung (für alle Kontakte).
  ///
  /// DER WEG: Die Erweiterung (settings_nachrichtpruefung.dart) kann den
  /// Zustand nicht selbst setzen - `state` ist geschützt. Deshalb
  /// gibt es hier diese Zugänge.
  Future<void> setzeNachrichtPruefModus(String modus) async {
    state = state.copyWith(nachrichtPruefModus: modus);
    await _persist();
  }

  /// Setzt die Schwelle der Nachrichten-Prüfung (die Zeichen-Zahl).
  ///
  /// Die Grenze liegt bei 50 bis 2000 Zeichen - darunter wäre die
  /// Prüfung sinnlos, darüber wäre sie unbenutzbar.
  Future<void> setzeNachrichtPruefSchwelle(int zeichen) async {
    state = state.copyWith(nachrichtPruefSchwelle: zeichen.clamp(50, 2000));
    await _persist();
  }

  /// Setzt die Ausnahme für einen Kontakt (null = keine Ausnahme).
  Future<void> setzeNachrichtPruefAusnahme(
    String kontaktId,
    String? modus,
  ) async {
    final ausnahmen = Map<String, String>.of(state.nachrichtPruefAusnahmen);
    if (modus == null) {
      ausnahmen.remove(kontaktId);
    } else {
      ausnahmen[kontaktId] = modus;
    }
    state = state.copyWith(nachrichtPruefAusnahmen: ausnahmen);
    await _persist();
  }

  /// Setzt die Werte der eigenen Tastatur (0.11.0).
  ///
  /// DER WEG: Das ist der einzige Zugang, den die Erweiterung im Teil
  /// braucht - `state` ist geschützt, von dort kommt man nicht heran.
  ///
  /// [farbeSetzen] unterscheidet "Farbe nicht anfassen" (null) von
  /// "Farbe löschen" (die eigene Farbe wieder verwerfen).
  Future<void> setzeTastaturWerte({
    String? belegung,
    String? stil,
    int? farbe,
    bool farbeSetzen = false,
  }) async {
    state = state.copyWith(
      tastaturBelegung: belegung,
      tastaturStil: stil,
      tastaturFarbe: farbeSetzen ? farbe : state.tastaturFarbe,
    );
    await _persist();
  }

  /// Der aktuelle Stand der Einstellungen.
  ///
  /// DER WEG: `state` ist geschützt - die Erweiterungen in den
  /// Teil-Dateien kommen nicht daran. Das ist ihr einziger Weg.
  AppSettings get stand => state;

  /// Setzt den Stand der Einstellungen (der Zugang für die Erweiterungen
  /// in den Teil-Dateien).
  void setzeStand(AppSettings neu) => state = neu;

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

/// Provider für die App-Einstellungen.
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final storage = ref.watch(localStorageProvider);
  return SettingsNotifier(storage, ref);
});
