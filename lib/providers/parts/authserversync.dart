// Die Methoden '_AuthServerSync'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../auth_provider.dart';

extension _AuthServerSync on AuthNotifier {
  /// Registriert das aktuelle FCM-Geräte-Token in der profiles-Tabelle,
  /// damit die Edge Function notify-user Push-Benachrichtigungen an
  /// dieses Gerät senden kann. Best effort – mit Timeout, damit
  /// getToken() (kann ohne Google-Dienste hängen) nie blockiert.
  Future<void> _syncFcmToken() async {
    // F-Droid-Build: kein Firebase, Push via UnifiedPush (falls aktiv).
    if (AppConstants.fdroidBuild) return;
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
      if (token == null) return;
      await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateOwnProfile({'fcm_token': token});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthNotifier] FCM-Token-Sync fehlgeschlagen: $e');
      }
    }
  }

  /// Lädt Profil + Setup-Flags vom Server (nach Login/Session-Restore).
  ///
  /// Ohne diese Synchronisierung fehlt nach der Anmeldung das Profil
  /// (u. a. das Geburtsdatum -> falsche Alters-Clamps in der Einrichtung)
  /// und die Einrichtung würde nach Neuinstallation erneut erscheinen.
  Future<void> _syncFromServer() async {
    try {
      if (!SupabaseService.isInitialized) return;
      // Ohne Session (z. B. direkt nach der Registrierung, bevor die
      // E-Mail bestätigt ist) gibt es nichts zu prüfen.
      if (SupabaseService.currentUser == null) return;
      // Chat-Besitzer setzen (Audit Kontowechsel): Trennt Verlauf,
      // Kontakte und State pro Konto, BEVOR irgendetwas nachlädt.
      // Gleicher Besitzer = No-op (kein Flackern bei Folge-Syncs).
      await bestEffort('read.setOwner', () async {
        await _ref
            .read(chatProvider.notifier)
            .setOwner(SupabaseService.currentUser?.id);
      });
      final database = SupabaseDatabaseService(SupabaseService.client);

      // FCM-Token-Registrierung NIE den kritischen Sync-Pfad blockieren
      // lassen (getToken kann auf Geräten ohne Google-Dienste hängen).
      unawaited(_syncFcmToken());

      // Geräte-Registrierung ("Wo bin ich eingeloggt?", Migration 071):
      // Dieses Gerät in auth_devices anlegen bzw. last_seen auffrischen.
      // Best effort mit Timeout - darf den Sync nie blockieren.
      unawaited(
        _ref
            .read(deviceSessionServiceProvider)
            .enrollCurrentDevice()
            .timeout(const Duration(seconds: 8))
            .catchError((Object e) {
              debugPrint(
                '[AuthNotifier] Geräte-Registrierung fehlgeschlagen: $e',
              );
            }),
      );

      // Audit H-7/E-3: Eigenes PreKey-Bundle veröffentlichen, falls noch
      // keines existiert (sonst schlägt jeder E2E-Session-Aufbau durch
      // Dritte fehl). Hintergrund, blockiert den Sync nicht.
      unawaited(_ref.read(preKeyServiceProvider).ensureOwnBundlePublished());

      // MFA-Status UNABHÄNGIG vom Profil-Fetch laden (eigener try-Block):
      // Schlägt der Profil-Fetch per Timeout fehl, darf die App trotzdem
      // wissen, ob 2FA aktiv ist - sonst zeigt sie nach einem Update fälsch-
      // lich "nicht eingerichtet".
      try {
        _ref.read(mfaStatusProvider.notifier).state =
            await MfaService(SupabaseService.client).loadStatus().timeout(
              const Duration(seconds: 5),
              onTimeout: () => const MfaStatus.initial(),
            );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[AuthNotifier] MFA-Status konnte nicht geladen werden: $e',
          );
        }
      }

      // Profil laden. Ein Timeout/Netzfehler wirft und behält die Session
      // (kein fälschlicher Logout) – nur ein SAUBERES "keine Zeile" bei
      // vorhandener Session bedeutet: Account wurde serverseitig gelöscht.
      // Eigener try-Block: Ein transienter Profil-Fehler darf den
      // Setup-Flags-Fetch (unten) nicht überspringen - sonst erscheint die
      // Einrichtung nach Neuinstallation erneut, obwohl der Server sie als
      // abgeschlossen hat.
      //
      // Serverseitige Themefarbe (Migration 071) - außerhalb der try-
      // Blöcke deklariert, weil der Flags-Sync unten sie übernimmt.
      String? serverThemeName;
      try {
        final profile = await database.fetchOwnProfile().timeout(
          const Duration(seconds: 5),
        );
        if (profile == null) {
          // Nur die SESSION verwerfen - lokale Daten (Profil, Einstellungen,
          // Praeferenzen) bleiben als Cache erhalten. Vorher wurden sie hier
          // komplett geloescht, was bei einem falsch-negativ (z. B. RLS-
          // Strohfeuer) den Nutzer alles neu eingeben liess. Nach erneutem
          // Login liefert der Server das Profil ohnehin wieder.
          debugPrint(
            '[AuthNotifier] Profil fehlt trotz Session - Session wird '
            'verworfen (lokale Daten bleiben erhalten).',
          );
          await _auth.logout();
          _ref.read(pendingVerificationEmailProvider.notifier).state = null;
          _ref.read(pendingVerificationCredentialsProvider.notifier).state =
              null;
          _setzeWert(const AsyncValue.data(false));
          return;
        }
        _profileNotifier.setProfile(profile);

        // Präferenzen (Entfernung, Altersspanne, "Ich suche", Bundesland,
        // Ort, Geschlechts-Filter) serverseitig nachziehen - "Nichts geht
        // verloren"-Garantie bei Neuinstallation (Migration 066). Best
        // effort: Ein Fehlschlag blockiert den Sync nicht.
        try {
          final prefsMap = await database.fetchOwnPreferencesWithRetry();
          if (prefsMap != null) {
            await _ref
                .read(userPreferencesProvider.notifier)
                .applyServerValues(prefsMap);
            final sMin = (prefsMap['age_range_min'] as num?)?.toInt();
            final sMax = (prefsMap['age_range_max'] as num?)?.toInt();
            if (sMin != null && sMax != null) {
              await _ref
                  .read(settingsProvider.notifier)
                  .setAgeRange(sMin, sMax);
            }
            // Entfernung auch in die AppSettings spiegeln (u. a. Dating
            // Hour liest sie von dort) - war bisher nur lokal, wurde also
            // nach Neuinstallation auf den Default zurückgesetzt.
            final sDist = (prefsMap['max_distance_km'] as num?)?.toInt();
            if (sDist != null) {
              await _ref
                  .read(settingsProvider.notifier)
                  .setMaxDistanceKm(sDist);
            }
            // Themefarbe (Migration 071): Mit dem Login direkt wieder
            // anwenden - auch nach Neuinstallation.
            serverThemeName = prefsMap['theme_name'] as String?;
          }
        } catch (e) {
          debugPrint('[AuthNotifier] Präferenz-Sync fehlgeschlagen: $e');
        }
      } catch (e) {
        debugPrint('[AuthNotifier] Profil-Fetch fehlgeschlagen: $e');
      }

      // Setup-Flags in EIGENEM try-Block mit Retry holen: Früher sprang ein
      // transienter Fehler (3-s-Timeout im Mobilnetz) in den äußeren catch
      // und die Einrichtung erschien nach Neuinstallation erneut, obwohl
      // der Server sie als abgeschlossen hatte. Der Flags-Fetch darf auch
      // durch einen Profil-Fehler NICHT übersprungen werden.
      Map<String, dynamic>? flags;
      try {
        flags = await database.fetchSetupFlagsWithRetry();
      } catch (e) {
        debugPrint('[AuthNotifier] Setup-Flags-Fetch fehlgeschlagen: $e');
      }
      if (flags != null) {
        _ref.read(setupFlagsKnownProvider.notifier).state = true;
        await _ref
            .read(settingsProvider.notifier)
            .syncSetupFlagsFromServer(
              oneTimeSettingsCompleted:
                  flags['one_time_settings_completed'] == true,
              communityGuidelinesAccepted:
                  flags['community_guidelines_accepted'] == true,
              personalityTestCompleted:
                  flags['personality_test_completed'] == true,
              onboardingDone: flags['onboarding_done'] == true,
              // Dating-Hour-Regeln nur EINMAL zeigen (Migration 071):
              // Der Stand hängt am Konto, nicht an der Installation.
              datingHourIntroSeen: flags['dating_hour_intro_seen'] == true,
              // Themefarbe (Migration 071): null/leer = Server kennt keine
              // Farbe -> lokaler Stand bleibt.
              themeName: serverThemeName,
            );
        // UI-Einstellungen (Blind Mode, Sichtbarkeit, Notify-Schalter,
        // Dark Mode, Blur) aus profiles.ui_prefs übernehmen (v0.8.0).
        final uiPrefs = flags['ui_prefs'] is Map
            ? Map<String, dynamic>.from(flags['ui_prefs'] as Map)
            : null;
        if (uiPrefs != null) {
          await _ref
              .read(settingsProvider.notifier)
              .applyServerUiPrefs(uiPrefs);
        }
        // Schalter in eigenen Spalten: show_distance (Entfernungsanzeige)
        // und die fuenf Push-Spalten (v0.10.0).
        //
        // BUG (still, seit langem): show_distance wurde NUR geschrieben,
        // nie gelesen. Nach einer Neuinstallation zeigte der Schalter
        // "aus", waehrend der Server weiter true hatte - der Nutzer
        // glaubte, die Entfernung sei verborgen, und sie wurde
        // angezeigt. Die Push-Schalter waren ueber ui_prefs gespiegelt,
        // aber notify-user wertet die Einzelspalten aus, die dauerhaft
        // auf true standen: die Schalter hatten keine Wirkung.
        await _ref.read(settingsProvider.notifier).refreshServerSwitches();

        // Pausenmodus + Habit-Dealbreaker (Migration 076): Server gewinnt.
        await _ref
            .read(settingsProvider.notifier)
            .applyServerFlags(
              paused: flags['paused'] is bool ? flags['paused'] as bool : null,
              habitsDealbreaker: flags['habits_dealbreaker'] is bool
                  ? flags['habits_dealbreaker'] as bool
                  : null,
            );

        // Selbstheilung (Fix "Einrichtung erscheint erneut"): Lokale
        // "erledigt"-Flags, die dem Server fehlen (z. B. weil das Speichern
        // bei der Einrichtung still fehlschlug), werden hier nachgezogen.
        // NUR nach dem ersten Sync – so werden lokale Restwerte (z. B. von
        // einem frueheren Test/Install) nicht zum Server gepusht und die
        // Einrichtung bei der allerersten Registrierung nicht uebersprungen.
        if (_initialServerSyncDone) {
          final s = _ref.read(settingsProvider);
          if ((s.oneTimeSettingsCompleted &&
                  flags['one_time_settings_completed'] != true) ||
              (s.communityGuidelinesAccepted &&
                  flags['community_guidelines_accepted'] != true)) {
            try {
              await database.updateSetupFlagsAndVerify({
                'one_time_settings_completed': s.oneTimeSettingsCompleted,
                'community_guidelines_accepted': s.communityGuidelinesAccepted,
              });
            } catch (e) {
              debugPrint(
                '[AuthNotifier] Setup-Flags-Nachzug fehlgeschlagen: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] Server-Sync fehlgeschlagen: $e');
    } finally {
      // Router freigeben: Setup-Flags sind geladen (oder der Sync ist
      // gescheitert - dann gilt der lokale Stand).
      _ref.read(serverSyncDoneProvider.notifier).state = true;
      // Ersten Sync abschliessen: Ab jetzt darf die Selbstheilung
      // lokale Flags zum Server nachziehen (siehe oben).
      _initialServerSyncDone = true;
    }
  }
}
