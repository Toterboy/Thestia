// Die Methoden '_EinrichtungSpeichern'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_privacy_once_screen.dart';

extension _EinrichtungSpeichern on _SettingsPrivacyOnceScreenState {
  /// Profilbild auswählen, quadratisch zuschneiden und in den privaten
  /// avatars-Bucket laden (identisch zu "Profil bearbeiten").
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    _setzeState(() => _uploadingAvatar = true);
    try {
      final bytes = await pickAndCropAvatar(context);
      if (bytes == null) return;

      // Lokale Vorschau sofort zeigen.
      if (mounted) _setzeState(() => _avatarBytes = bytes);
      final storage = ref.read(supabaseStorageServiceProvider);
      final path = await storage.uploadAvatar(bytes);
      await ref.read(profileProvider.notifier).update(photos: [path]);

      // v0.10.0: Serverseitiger Write fehlte hier vollständig. Das Bild
      // lag in Storage und lokal - aber `profiles.photos` wurde nie
      // gesetzt. Beim nächsten fetchOwnProfile stand dort wieder der
      // alte Stand, das Bild verschwand. Von außen sah es damit aus,
      // als frage die Einrichtung gar kein Profilbild ab.
      if (SupabaseService.isInitialized) {
        await ref.read(supabaseDatabaseServiceProvider).updateOwnProfile({
          'photos': [path],
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'setupp.photoDone'))),
        );
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Avatar-Upload fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'setupp.photoFail'))),
        );
      }
    } finally {
      if (mounted) _setzeState(() => _uploadingAvatar = false);
    }
  }

  /// Speichert den Geburtstags-Stil (v0.10.0). Eigene Seite, deshalb
  /// eigener Save - sonst müste die Style-Seite in [_saveProfileExtras]
  /// aufgewächt werden, obwohl sie an einem anderen Ort steht.
  Future<void> _saveBirthdayStyle() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(birthdayStyle: _birthdayStyle);
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(
          SupabaseService.client,
        ).updateOwnProfile({'birthday_style': _birthdayStyle});
      }
    } catch (e) {
      debugPrint(
        '[SettingsPrivacyOnce] Geburtstags-Stil speichern '
        'fehlgeschlagen: $e',
      );
    }
  }

  /// Speichert die Konsum-Präferenzen (Rauchen, Alkohol, Drogen) lokal
  /// und best-effort serverseitig. Beeinflusst den Find-your-Match-Filter.
  Future<void> _saveHabitudes() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(smoking: _smoking, alcohol: _alcohol, drugs: _drugs);
      await ref
          .read(settingsProvider.notifier)
          .setHabitsDealbreaker(_habitsDealbreaker);
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'smoking': _smoking?.toServer(),
          'alcohol': _alcohol?.toServer(),
          'drugs': _drugs?.toServer(),
          'habits_dealbreaker': _habitsDealbreaker,
        });
      }
    } catch (e) {
      debugPrint(
        '[SettingsPrivacyOnce] Habituden-Speichern fehlgeschlagen: $e',
      );
    }
  }

  /// Speichert Text + Audio der Vorstellung (best effort, optionaler
  /// Schritt). Identische Mechanik wie im Find-your Match-Screen.
  Future<void> _saveIntro() async {
    final text = _introText.trim();
    if (text.isEmpty && _introAudioPath == null) return;
    try {
      await ref
          .read(profileProvider.notifier)
          .update(
            introText: text,
            introAudioPath: _introAudioPath,
            clearIntroAudio: _introAudioPath == null,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'intro_text': text,
          'intro_audio_path': _introAudioPath,
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Intro-Speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert den Musik-Geschmack (v0.10.0).
  ///
  /// Gespeichert werden SLUGS. Der alte Onboarding-Screen hat hier
  /// deutsche Labels ("Hip-Hop") geschrieben; das Matching vergleicht
  /// aber Slugs (`hip_hop`) - die Angabe war damit wirkungslos.
  ///
  /// Leeres Lieblingssong/-band wird als leerer String gespeichert, weil
  /// die Spalten `NOT NULL DEFAULT ''` sind (Migration 092/119).
  Future<void> _saveMusicTaste() async {
    try {
      final song = _songCtrl.text.trim();
      final band = _bandCtrl.text.trim();
      await ref
          .read(profileProvider.notifier)
          .update(
            musicLiked: _musicLiked.toList(),
            musicDisliked: _musicDisliked.toList(),
            favoriteSong: song,
            favoriteBand: band,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'music_liked': _musicLiked.toList(),
          'music_disliked': _musicDisliked.toList(),
          'favorite_song': song,
          'favorite_band': band,
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Musik speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert Bio, Bundesland und Interessen der Profil-Seite lokal UND
  /// serverseitig (gleiche Felder wie "Profil bearbeiten").
  Future<void> _saveProfileExtras() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(
            bio: _bioCtrl.text.trim(),
            stateStr: _selectedState,
            country: _selectedCountry ?? 'Deutschland',
            interests: _selectedInterests.toList(),
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'bio': _bioCtrl.text.trim(),
          'state': _selectedState,
          'country': _selectedCountry ?? 'Deutschland',
          'interests': _selectedInterests.toList(),
        });
      }
    } catch (e) {
      debugPrint(
        '[SettingsPrivacyOnce] Profil-Extras speichern '
        'fehlgeschlagen: $e',
      );
    }
  }

  /// Richtet einen Passkey ein (überspringbarer Schritt). Fehler werden
  /// angezeigt, blockieren aber nicht – "Weiter" geht immer.
  Future<void> _setupPasskey() async {
    if (_passkeyBusy || _passkeyCreated) return;
    _setzeState(() => _passkeyBusy = true);
    try {
      // v0.10.0: Vorher ungeprüft registrieren. Bei einem Gerätewechsel
      // oder einem zweiten Durchlauf der Einrichtung lag schon ein
      // Passkey auf dem Konto - der native Dialog kam dann ein zweites
      // Mal und endete in einer Fehlermeldung, die nichts kaputtgemacht
      // hat. Der Schritt ist damit abgeschlossen, nicht gescheitert.
      if (await PasskeyAuth.hasRegisteredPasskey()) {
        if (!mounted) return;
        _setzeState(() => _passkeyCreated = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'setup.passkeyAlreadyThere')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // ERST OHNE Captcha-Token versuchen (NUTZERWUNSCH 31.10.2026:
      // "hat jetzt aber eine extra Captcha Abfrage"). GoTrue verlangt das
      // Token nur, wenn der Bot-Schutz wirklich greift.
      //
      // Lehnt der Server ohne Token ab (die Challenge-Antwort kommt, BEVOR
      // der native Dialog erscheint), wird der Sicherheitscheck gezeigt
      // und der Versuch mit Token wiederholt.
      if (!mounted) return;
      try {
        await PasskeyAuth.register();
      } catch (e) {
        if (!PasskeyAuth.requiresCaptcha(e)) rethrow;
        if (!mounted) return;
        final captchaToken = await showCaptchaChallenge(context);
        if (captchaToken == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.t(context, 'auth.captchaRegister')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await PasskeyAuth.register(captchaToken: captchaToken);
      }
      if (!mounted) return;
      _setzeState(() => _passkeyCreated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'setup.passkeyDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Passkey-Setup fehlgeschlagen: $e');
      // Konkrete Meldung statt der generischen - auch bei unerwarteten
      // Fehlern (NUTZERWUNSCH 31.10.2026).
      final msg = L10n.exc(context, PasskeyAuth.explainForUi(e, login: false));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) _setzeState(() => _passkeyBusy = false);
    }
  }
}
