// Die Methoden '_EinrichtungAbschluss'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_privacy_once_screen.dart';

extension _EinrichtungAbschluss on _SettingsPrivacyOnceScreenState {
  void _acceptAndFinish() async {
    // Zuerst Community-Richtlinien akzeptieren, dann Setup abschließen –
    // mit dringender Sicherheitsempfehlung (Passkey/2FA), falls fehlend.
    await ref.read(settingsProvider.notifier).acceptCommunityGuidelines();
    await _finishWithSecurityNudge();
  }

  Widget _buildCommunityGuidelines(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'setupp.guidelinesIntroTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(L10n.t(context, 'setupp.guidelinesIntroBody')),
        const SizedBox(height: 16),
        _RuleItem('1', L10n.t(context, 'cg.1.titleShort')),
        _RuleItem('2', L10n.t(context, 'cg.2.titleShort')),
        _RuleItem('3', L10n.t(context, 'cg.3.titleShort')),
        _RuleItem('4', L10n.t(context, 'cg.4.titleShort')),
        _RuleItem('5', L10n.t(context, 'cg.5.titleShort')),
        _RuleItem('6', L10n.t(context, 'setupp.guidelinesBan')),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'setupp.guidelinesWarn'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  Future<void> _detectLocation() async {
    // Doppelaufruf verhindern: setState wirkt erst naechsten Frame,
    // daher ist _isDetectingLocation hier noch false.
    if (_isDetectingLocation) return;
    _setzeState(() {
      _isDetectingLocation = true;
      _locationError = null;
    });

    try {
      // Die prominente Standort-Offenlegung (Google Play verlangt sie
      // vor der Anfrage einer empfindlichen Berechtigung).
      if (!await ensureLocationDisclosure(context, ref) || !mounted) return;

      final locationService = ref.read(locationVerificationServiceProvider);
      final position = await locationService.getCurrentLocation();
      if (!mounted) return;

      if (position == null) {
        _setzeState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'setup.locationDetectFail');
        });
        return;
      }

      // Plausibilitaets-Check gegen die BISHERIGEN Standorte dieses
      // Geraets (lokal). Ein serverseitiger Abgleich mit fremden Accounts
      // existiert bewusst nicht - der Server prueft separat eigene
      // Positions-Spruenge (>15 km / >300 km/h) via process-location-check.
      // isLocationSuspicious liest den Secure Storage (async) - in dieser
      // Zeit kann der Screen verlassen worden sein.
      final suspicious = await locationService.isLocationSuspicious(position);
      if (!mounted) return;
      if (suspicious) {
        _setzeState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'setup.locationSuspicious');
        });
        return;
      }

      // v0.10.0: Nur noch das Bundesland als Anzeige. Frueher stand hier
      // der ORTSNAME (via der Geocoder-Hilfe in geo_names.dart) und wurde
      // nach profiles.city geschrieben - damit war der Aufenthaltsort
      // bis auf ~11 km genau oeffentlich, auch direkt per PostgREST
      // (Migration 135).
      //
      // Die Koordinaten werden auf 5-km-Raster gerundet, BEVOR sie
      // gespeichert werden. Der Server rundet ebenfalls; identisch zu
      // sein ist wichtig, sonst springt die Entfernungsanzeige.
      final snapped = LocationPrivacy.snapToGrid(
        position.latitude,
        position.longitude,
      );
      // Bundesland fuer die Anzeige. Ohne Treffer wird NICHT geraten -
      // der Nutzer waehlt es dann von Hand aus der Liste.
      final detectedState = await describeStateFor(snapped.lat, snapped.lng);
      if (!mounted) return;

      // Koordinaten lokal UND serverseitig persistieren - sonst koennen
      // Entfernungen zu anderen Nutzern nicht berechnet werden.
      await ref
          .read(profileProvider.notifier)
          .update(
            stateStr: detectedState,
            locationLat: snapped.lat,
            locationLng: snapped.lng,
          );
      if (SupabaseService.isInitialized) {
        // Best-Effort: Standort-Sync darf den Flow nicht blockieren.
        await bestEffort(
          'supabaseDatabaseServiceProvider.saveOwnLocation',
          () async {
            final userId = SupabaseService.client.auth.currentUser?.id;
            if (userId != null) {
              unawaited(
                ref
                    .read(locationCheckServiceProvider)
                    .processLocationCheck(
                      userId: userId,
                      newLatitude: snapped.lat,
                      newLongitude: snapped.lng,
                    ),
              );
              // Bundesland serverseitig sichern, damit ein späterer
              // Profil-Sync (fetchOwnProfile) den Wert nicht mit leer
              // überschreibt. Kein city: den gibt es nicht mehr.
              unawaited(
                ref.read(supabaseDatabaseServiceProvider).updateOwnProfile({
                  'state': detectedState,
                }),
              );

              // v0.10.0: Die Koordinaten gehoeren nach profile_locations -
              // die einzige Tabelle, in der die exakten Werte liegen und
              // die nur der Eigentuemer lesen kann. Ohne diesen Schritt
              // bleibt die Tabelle leer und die Entfernungsanzeige
              // entfaellt (Migration 135 hatte sie nur befuellt fuer
              // Bestandsprofile, nicht fuer neue Accounts).
              await ref
                  .read(supabaseDatabaseServiceProvider)
                  .saveOwnLocation(snapped.lat, snapped.lng);
            }
          },
        );
      }

      // Der Nutzer kann den Schritt inzwischen verlassen haben - dann
      // waere das setState ein Absturz.
      if (!mounted) return;
      _setzeState(() {
        _isDetectingLocation = false;
        _locationError = null;
        // Das erkannte Bundesland in die Auswahl uebernehmen, damit der
        // Nutzer es bestaetigen oder korrigieren kann. Ohne Treffer
        // bleibt die bisherige Wahl stehen.
        if (detectedState != null) _selectedState = detectedState;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detectedState == null
                  ? L10n.t(context, 'setup.locationStateUnknown')
                  : L10n.t(context, 'setup.locationDone'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _setzeState(() {
        _isDetectingLocation = false;
        _locationError = L10n.tf(context, 'setup.locationError', {
          'error': e.toString(),
        });
      });
    }
  }

  Future<void> _finish() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final accepted = ref.read(settingsProvider).communityGuidelinesAccepted;
    if (!accepted) {
      await settingsNotifier.acceptCommunityGuidelines();
    }
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    // v0.10.0: Der Stadt-Sync ist entfallen. Der Ortsname war das
    // eigentlich sensible Datum - oeffentlich lesbar fuer jeden
    // angemeldeten Nutzer (Migration 135). Das Bundesland wird ueber
    // _saveProfileExtras geschrieben, die Koordinaten ueber
    // _detectLocation.
    await _saveHabitudes();
    await _saveBirthdayStyle();
    await _saveMusicTaste();
    await settingsNotifier.completeOneTimeSettings();
    // UI-Einstellungen (Blind Mode, Sichtbarkeit, Dark Mode, ...) einmalig
    // serverseitig spiegeln (v0.8.0, ui_prefs) - best effort.
    scheduleUiPrefsServerSync(ref.read(settingsProvider));
    // Setup-Stand serverseitig sichern, damit die Einrichtung nach
    // Neuinstallation/neuem Login nicht erneut erscheint. Fehlschlag wird
    // ANGEZEIGT (bisher: stiller debugPrint, weshalb die Einrichtung
    // bei der nächsten Anmeldung wieder kam, obwohl sie "fertig" war).
    final flagsSaved = await _persistSetupFlagsToServer();
    // Präferenzen (Entfernung, "Ich suche", Bundesland, Altersspanne)
    // zusätzlich serverseitig sichern ("Nichts geht verloren"-Garantie,
    // Migration 066). Kein city mehr - die Spalte ist mit Migration 138
    // entfernt.
    if (SupabaseService.isInitialized) {
      // Best-Effort: Blockiert den Abschluss nicht.
      await bestEffort('prefsNotifier.savePreferencesToServer', () async {
        final s = ref.read(settingsProvider);
        final profileState = ref.read(profileProvider).state;
        await prefsNotifier.savePreferencesToServer(
          ageRangeMin: s.ageRangeMin,
          ageRangeMax: s.ageRangeMax,
          stateStr: profileState,
        );
      });
    }
    if (mounted && !flagsSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'setup.flagsWarn')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (mounted) context.go(AppRoutes.home);
  }

  /// Dringende Empfehlung: Wenn weder Passkey noch 2FA eingerichtet sind,
  /// vor dem Abschluss ein deutlicher Hinweis mit Direkt-Sprüngen.
  Future<void> _finishWithSecurityNudge() async {
    final mfaActive =
        ref.read(mfaStatusProvider).hasVerifiedFactors ||
        ref.read(mfaStatusProvider).hasAnyFactor;
    if (_passkeyCreated || mfaActive) {
      await _finish();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.shield_outlined,
          color: Theme.of(ctx).colorScheme.primary,
          size: 40,
        ),
        title: Text(L10n.t(ctx, 'setup.nudgeTitle')),
        content: Text(L10n.t(ctx, 'setup.nudgeBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(L10n.t(ctx, 'setup.nudgeSkip')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('mfa'),
            child: Text(L10n.t(ctx, 'setup.nudgeMfa')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('passkey'),
            child: Text(L10n.t(ctx, 'setup.nudgePasskey')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (choice) {
      case 'passkey':
        // v0.10.0: Zwei neue Seiten (Geburtstag, Musik) sitzen vor
        // Passkey/MFA, deshalb sind die Zielseiten um zwei gewandert.
        _pageController.jumpToPage(7); // Passkey-Seite
      case 'mfa':
        _pageController.jumpToPage(8); // 2FA-Seite
      default:
        await _finish();
    }
  }

  /// Schreibt die Setup-Flags in die profiles-Tabelle und verifiziert das
  /// Ergebnis per Zurücklesen (stille 0-Zeilen-Updates und transiente
  /// Netzfehler werden dadurch erkennbar und retries).
  /// Rückgabe: true bei Erfolg (false = fehlgeschlagen, Aufrufer zeigt
  /// einen Hinweis).
  Future<bool> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final settings = ref.read(settingsProvider);
      // WICHTIG: onboarding_done wird hier bewusst NICHT mitgeschickt -
      // es ist in diesem Moment noch false (der Persönlichkeitstest als
      // letzter Schritt setzt es) und würde sonst einen etwaigen
      // serverseitigen true-Stand (Backfill, Migration 065) überschreiben.
      return await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateSetupFlagsAndVerify({
        'one_time_settings_completed': settings.oneTimeSettingsCompleted,
        'community_guidelines_accepted': settings.communityGuidelinesAccepted,
      });
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Server-Flags fehlgeschlagen: $e');
      return false;
    }
  }
}
