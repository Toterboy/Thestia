// Die Methoden '_ProfilEditSpeichern'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_edit_screen.dart';

extension _ProfilEditSpeichern on _ProfileEditScreenState {
  /// Fragt nach, was mit ungespeicherten Änderungen passieren soll.
  /// Rückgabe: 'save' | 'discard' | 'cancel' | null (Dialog abgebrochen).
  Future<String?> _confirmUnsavedChanges() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'profile.edit.unsavedTitle')),
        content: Text(L10n.t(context, 'profile.edit.unsavedBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: Text(L10n.t(ctx, 'profile.edit.unsavedDiscard')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text(L10n.t(ctx, 'common.save')),
          ),
        ],
      ),
    );
  }

  Future<void> _detectLocation() async {
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
          _locationError = L10n.t(context, 'profile.edit.locationFailed');
        });
        return;
      }

      // Plausibilitäts-Check gegen die BISHERIGEN Standorte dieses
      // Geräts (lokal) - keine Cross-Account-Erkennung.
      // isLocationSuspicious liest den Secure Storage (async) - in dieser
      // Zeit kann der Screen verlassen worden sein.
      final suspicious = await locationService.isLocationSuspicious(position);
      if (!mounted) return;
      if (suspicious) {
        _setzeState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'profile.edit.locationSuspicious');
        });
        return;
      }

      // v0.10.0: Nur noch das Bundesland, keine Ortsangabe. Vorher stand
      // hier der Ortsname aus dem Reverse-Geocoder und landete in
      // profiles.city - für jeden angemeldeten Nutzer lesbar.
      //
      // Die Koordinaten werden auf 5-km-Raster gerundet, BEVOR sie
      // gespeichert werden. Der Server rastet ebenfalls; identisch zu
      // sein ist wichtig, sonst springt die Entfernungsanzeige.
      final snapped = LocationPrivacy.snapToGrid(
        position.latitude,
        position.longitude,
      );
      final detectedState = await describeStateFor(snapped.lat, snapped.lng);
      if (!mounted) return;

      // Profil mit den neuen Koordinaten und dem Bundesland aktualisieren.
      await ref
          .read(profileProvider.notifier)
          .update(
            stateStr: detectedState,
            locationLat: snapped.lat,
            locationLng: snapped.lng,
          );

      // Koordinaten serverseitig persistieren (Basis für die
      // Distanzberechnung zu anderen Nutzern).
      if (SupabaseService.isInitialized) {
        // v0.10.0: In profiles landen nur noch das Bundesland und die
        // Flags. Die Koordinaten gehen in profile_locations - dort ist
        // die RLS auf den Eigentümer begrenzt, in profiles kann sie
        // das nicht (die Spalte wäre für jeden angemeldeten Nutzer
        // über PostgREST lesbar).
        try {
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).updateOwnProfile({'state': detectedState});
        } catch (e) {
          debugPrint('[ProfileEdit] Bundesland-Sync fehlgeschlagen: $e');
        }

        // Der eigentliche Ort für die Koordinaten.
        try {
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).saveOwnLocation(snapped.lat, snapped.lng);
        } catch (e) {
          debugPrint('[ProfileEdit] Standort-Tabelle fehlgeschlagen: $e');
        }
      }

      // Serverseitigen Standort-Check via Edge Function auslösen.
      final auth = SupabaseService.currentUser;
      if (auth != null) {
        unawaited(
          ref
              .read(locationCheckServiceProvider)
              .processLocationCheck(
                userId: auth.id,
                newLatitude: snapped.lat,
                newLongitude: snapped.lng,
              ),
        );
      }

      // Der Nutzer kann inzwischen zurückgegangen sein - dann wäre
      // das setState ein Absturz.
      if (!mounted) return;
      _setzeState(() {
        _isDetectingLocation = false;
        _locationError = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'profile.edit.locationDetected')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _setzeState(() {
        _isDetectingLocation = false;
        _locationError = 'Fehler bei der Standortermittlung: $e';
      });
    }
  }

  // v0.10.0: _validateLocationAgainstGps ist entfallen. Die Methode
  // verglich einen von Hand getippten Ortsnamen mit der GPS-Position
  // und meldete Abweichungen über 15 km. Mit dem Wegfall der
  // Ortsangabe gibt es nichts mehr zu vergleichen; sinnvollerweise
  // bleibt stattdessen die Abweichung zum Bundesland, und die fällt
  // ohnehin weg, weil _detectLocation das Bundesland selbst setzt.
  Widget _field({required Widget child, String? Function()? validate}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: FormField<String>(
            validator: (_) => validate?.call(),
            builder: (field) => field.errorText == null
                ? const SizedBox.shrink()
                : Text(
                    field.errorText!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
          ),
        ),
      ],
    );
  }

  /// Prüft, ob das Formular vom Stand beim Öffnen abweicht
  /// (Grundlage für den ungespeicherte-Änderungen-Schutz).
  ///
  /// Umfasst auch die Regler/Dropdowns, die direkt in die Provider
  /// schreiben (Altersspanne, Entfernung, Suchradius-Modus, Bundesland-
  /// Filter) und das Geburtsdatum - früher lösten diese KEINE Nachfrage
  /// aus und wurden still übernommen.
  bool _isDirty() {
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    final settings = ref.read(settingsProvider);
    // v0.10.0: Die Ortsangabe ist entfallen, damit auch kein Dirty-Vergleich
    // mehr nötig ist. Das Bundesland wird weiterhin verglichen.
    return _pendingAvatarBytes != null ||
        _pendingExtraBytes.isNotEmpty ||
        _removedPhotoSlots.isNotEmpty ||
        _nameCtrl.text.trim() != p.name ||
        _bioCtrl.text.trim() != p.bio ||
        _stateCtrl.text.trim() != (p.state ?? '').trim() ||
        _countryValue != (p.country.isEmpty ? 'Deutschland' : p.country) ||
        _gender != (Gender.fromValue(p.gender) ?? Gender.diverse) ||
        _relationshipType !=
            (prefs.relationshipType ?? RelationshipType.open) ||
        _introTextValue.trim() != p.introText ||
        _introAudioPath != p.introAudioPath ||
        _smoking != p.smoking ||
        _alcohol != p.alcohol ||
        _drugs != p.drugs ||
        !_ProfileEditScreenState._listEq(_musicLiked, p.musicLiked) ||
        !_ProfileEditScreenState._listEq(_musicDisliked, p.musicDisliked) ||
        _songCtrl.text.trim() != (p.favoriteSong ?? '') ||
        _bandCtrl.text.trim() != (p.favoriteBand ?? '') ||
        _birthdayStyle != p.birthdayStyle ||
        // Regler / Auswahl-Snapshot-Vergleiche:
        _birthDate != _initialBirthDate ||
        settings.ageRangeMin != _initialAgeMin ||
        settings.ageRangeMax != _initialAgeMax ||
        prefs.maxDistanceKm != _initialMaxDistanceKm ||
        prefs.distanceFilterMode != _initialDistanceMode ||
        prefs.preferredState != _initialPreferredState;
  }

  /// Setzt Regler-/Auswahl-Änderungen auf den Stand beim Öffnen zurück
  /// ("Verwerfen"-Zweig des Dialogs).
  Future<void> _revertSliderChanges() async {
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await prefsNotifier.setMaxDistanceKm(_initialMaxDistanceKm);
    await prefsNotifier.setDistanceFilterMode(_initialDistanceMode);
    await prefsNotifier.setPreferredState(_initialPreferredState);
    await settingsNotifier.setAgeRange(_initialAgeMin, _initialAgeMax);
  }

  Future<void> _save() async {
    await _saveInternal();
  }

  /// Speichert das Profil. [redirectTo] erlaubt eine Ziel-Route nach dem
  /// erfolgreichen Speichern (Tab-Wechsel-Flow). Rückgabe: true bei Erfolg.
  Future<bool> _saveInternal({String? redirectTo}) async {
    if (_saving) return false;
    _setzeState(() => _saving = true);
    _lastSyncError = null;
    try {
      if (!_formKey.currentState!.validate()) {
        // Feedback (Nutzerwunsch): Der Hinweis erscheint direkt am
        // Speichern-Button, damit off-screen-Fehler nicht übersehen werden.
        _setzeState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'profile.edit.missingFields')),
          ),
        );
        return false;
      }
      final age = Validators.ageFromBirthDate(_birthDate);
      if (age == null) {
        _setzeState(() => _showValidationError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'profile.edit.birthDateMissing')),
          ),
        );
        return false;
      }

      // Profilbilder-Upload (v0.8.1/v0.9.0): Die vorgehaltenen Bilder
      // (Slot 0 = primär, Slot 1/2 = zusätzliche) werden JETZT hochgeladen.
      // Fehler verhindern das Speichern nicht (Bilder bleiben vorgehalten,
      // nächster Speicherklick versucht es erneut).
      //
      // Slot-Modell (max. 3): Slot 0 -> {userId}/avatar.jpg (match-media-
      // kompatibel), Slot 1/2 -> {userId}/photos/2.jpg|3.jpg. Entfernte
      // Slots fallen aus profiles.photos; vorhandene Objekte werden im
      // Storage aufgeräumt (Owner-Policy).
      // Die fertige Fotoliste. Sie wird VOR dem try festgelegt, damit das
      // Update weiter unten (Fotos und Texte in einem Aufruf) sie
      // benutzen kann - auch wenn der Foto-Teil scheitert (dann bleiben
      // die bisherigen Fotos stehen).
      var finalPhotos = List<String>.from(ref.read(profileProvider).photos);
      try {
        final storageService = ref.read(supabaseStorageServiceProvider);
        final current = List<String>.from(ref.read(profileProvider).photos);
        final slots = List<String?>.filled(
          SupabaseStorageService.maxPhotos,
          null,
        );
        for (var i = 0; i < slots.length && i < current.length; i++) {
          slots[i] = current[i];
        }
        if (_removedPhotoSlots.contains(0)) slots[0] = null;
        if (_removedPhotoSlots.contains(1)) slots[1] = null;
        if (_removedPhotoSlots.contains(2)) slots[2] = null;

        if (_pendingAvatarBytes != null) {
          slots[0] = await storageService.uploadAvatar(_pendingAvatarBytes!);
        }
        for (final slot in const [1, 2]) {
          final pending = _pendingExtraBytes[slot];
          if (pending != null) {
            slots[slot] = await storageService.uploadPhoto(
              pending,
              index: slot,
            );
          }
        }

        finalPhotos = slots.whereType<String>().toList(growable: false);

        // Storage-Aufräumen für entfernte Slots (best effort).
        //
        // BEFUND (09.11.2026, Betreiber): "Die Bilder sind nicht sichtbar,
        // wenn hochgeladen." Zwei Ursachen, beide hier:
        //
        // 1) DIE ALTEN DATEIEN LAGEN ALS WRACK IM SPEICHER. Wird ein
        //    Bild ersetzt (nicht nur entfernt), blieb die alte Datei
        //    liegen. Das passiert, weil die Liste in profiles.photos
        //    eine GALERIE ist: sie ist lückenlos. Wird die mittlere
        //    Kachel entfernt, rücken die hinteren eine Position nach
        //    vorn - und der Pfad der Datei passt dann nicht mehr zum
        //    Kachel-Index. Genau dann trifft der Pfad des neuen Uploads
        //    nicht mehr den der ersetzten Datei.
        //
        //    Deshalb wird die alte Datei jetzt GELÖSCHT, wenn ihr Pfad
        //    nicht der des neuen Uploads ist. Ist er derselbe, wurde
        //    die Datei gerade überschrieben - dann wäre ein Löschen
        //    ein Datenverlust.
        final zuLoeschen = <String>{};
        for (final i in _removedPhotoSlots) {
          final oldRef = i < current.length ? current[i] : null;
          if (oldRef != null && oldRef.isNotEmpty) {
            zuLoeschen.add(oldRef.split('|').first);
          }
        }
        for (final slot in const [1, 2]) {
          if (_pendingExtraBytes[slot] == null) continue;
          if (slot >= current.length) continue;
          final altPfad = current[slot].split('|').first;
          final neuPfad = slots[slot]?.split('|').first ?? '';
          if (altPfad.isEmpty || neuPfad.isEmpty) continue;
          if (altPfad != neuPfad) zuLoeschen.add(altPfad);
        }
        for (final pfad in zuLoeschen) {
          await storageService.deleteOwnObject(pfad);
        }

        if (!mounted) return false;
        // BEFUND (14.11.2026, gefunden von einem Test): Vorher stand hier
        // ein Update NUR für die Fotos und weiter unten ein zweites für
        // die Texte. Das erste Update lüste im Screen den "Profil
        // nachziehen"-Zuhörer aus - der setzt die Textfelder auf den
        // Serverstand zurück (siehe _profileSub). Der Name, den der
        // Nutzer gerade getippt hatte, war damit weg, BEVOR er
        // gespeichert wurde: das Speichern meldete "Profil gespeichert"
        // und speicherte den ALTEN Namen. Das Gleiche galt für Bio,
        // Bundesland und Geburtsdatum.
        //
        // DESHALB: Es gibt jetzt nur noch EIN Update - weiter unten -
        // das Fotos und Texte zusammen schreibt. Der Zuhörer sieht dann
        // den neuen Stand und fasst die Felder nicht an.
        //
        // Server-Write (v0.8.1-Fix): Der photos-Pfad MUSSTE vorher immer
        // nur lokal landen - der Server kannte das Bild nie. Jetzt sofort
        // + bestätigt schreiben (verifiziert per Read-Back).
        if (SupabaseService.isInitialized) {
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).updateSetupFlagsAndVerify({'photos': finalPhotos});
        }
        if (!mounted) return false;
        _setzeState(() {
          _pendingAvatarBytes = null;
          _pendingExtraBytes.clear();
          _removedPhotoSlots.clear();
          _extraBytesFutures.clear();
          _avatarBytesFuture = finalPhotos.isNotEmpty
              ? storageService.loadAvatarBytes(finalPhotos.first)
              : null;
          // UND DIE WEITEREN BILDER NEU LADEN (BEFUND 09.11.2026:
          // "Die Bilder sind nicht sichtbar, wenn hochgeladen.").
          //
          // DER GRUND: `_extraBytesFutures.clear()` löschte die Future
          // der Kacheln 1 und 2. Die Kachel zeichnet aber genau diesen
          // Future - ohne ihn fiel sie auf das Platzhalter-Symbol
          // zurück. Das erste Bild (Slot 0) wurde oben neu geladen,
          // die beiden weiteren wurden es nicht: sie waren nach dem
          // Speichern unsichtbar, bis die App neu gestartet wurde.
          for (
            var slot = 1;
            slot < finalPhotos.length &&
                slot < SupabaseStorageService.maxPhotos;
            slot++
          ) {
            _extraBytesFutures[slot] = storageService.loadAvatarBytes(
              finalPhotos[slot],
            );
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'profile.edit.photoUploadError', {
                  'error': e.toString(),
                }),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        // Nicht abbrechen: die Textänderungen trotzdem speichern.
      }

      // v0.10.0: Die GPS-Gegenprüfung des Ortsnamens ist entfallen. Sie
      // verglich den getippten Ort mit der GPS-Position - ohne Ortseingabe
      // gibt es nichts zu vergleichen. Die Plausibilität wird jetzt beim
      // Ermitteln des Standorts selbst geprüft (isLocationSuspicious in
      // _detectLocation).

      // Intro-Guard (v0.9.0-Fix): Intro-Felder nur übernehmen/schreiben,
      // wenn sie in DIESEM Screen geändert wurden. Ein veralteter Zustand
      // (null/leer) darf die Vorstellung weder lokal noch serverseitig
      // überschreiben ("Vorstellung verschwindet bei Aktualisierung").
      final introTextChanged =
          _introTextValue.trim() != _initialIntroText.trim();
      final introAudioChanged = _introAudioPath != _initialIntroAudioPath;

      await ref
          .read(profileProvider.notifier)
          .update(
            // Die Fotos gehören in DIESES Update (siehe den Kommentar
            // weiter oben): zwei Updates würden den "Profil
            // nachziehen"-Zuhörer auslösen und die Textfelder auf den
            // alten Stand zurückersetzen.
            photos: finalPhotos,
            name: _nameCtrl.text.trim(),
            birthDate: _birthDate,
            bio: _bioCtrl.text.trim(),
            stateStr: _stateCtrl.text.trim().isEmpty
                ? null
                : _stateCtrl.text.trim(),
            country: _countryValue,
            gender: _gender.value,
            introText: introTextChanged ? _introTextValue.trim() : null,
            introAudioPath: introAudioChanged ? _introAudioPath : null,
            clearIntroAudio: introAudioChanged && _introAudioPath == null,
            smoking: _smoking,
            alcohol: _alcohol,
            drugs: _drugs,
            musicLiked: _musicLiked,
            musicDisliked: _musicDisliked,
            favoriteSong: _songCtrl.text.trim().isEmpty
                ? null
                : _songCtrl.text.trim(),
            favoriteBand: _bandCtrl.text.trim().isEmpty
                ? null
                : _bandCtrl.text.trim(),
            birthdayStyle: _birthdayStyle,
          );
      await ref
          .read(userPreferencesProvider.notifier)
          .setRelationshipType(_relationshipType);

      // Server-Sync: Bewusst ABWARTEN (Nutzerwunsch "Suchradius soll wie
      // der Name gespeichert werden") - der frühere fire-and-forget lief
      // bei schnellem App-Ende ins Leere. Bei Fehlschlag: klar melden
      // (lokale Werte bleiben erhalten, nächstes Speichern/der
      // entprellte Auto-Sync holt es nach).
      var serverSyncOk = true;
      if (SupabaseService.isInitialized) {
        try {
          await SupabaseDatabaseService(
            SupabaseService.client,
          ).updateOwnProfile({
            'bio': _bioCtrl.text.trim(),
            'name': _nameCtrl.text.trim(),
            'state': _stateCtrl.text.trim().isEmpty
                ? null
                : _stateCtrl.text.trim(),
            'interests': ref.read(profileProvider).interests,
            if (introTextChanged) 'intro_text': _introTextValue.trim(),
            if (introAudioChanged) 'intro_audio_path': _introAudioPath,
            'country': _countryValue,
            'smoking': _smoking?.toServer(),
            'alcohol': _alcohol?.toServer(),
            'drugs': _drugs?.toServer(),
            'music_liked': _musicLiked,
            'music_disliked': _musicDisliked,
            'favorite_song': _songCtrl.text.trim(),
            'favorite_band': _bandCtrl.text.trim(),
            'birthday_style': _birthdayStyle,
            'habits_dealbreaker': _habitsDealbreaker,
            'photos': ref.read(profileProvider).photos,
            // Radius-Modus VOLLSTÄNDIG mitschicken (v0.9.1-Fix): vorher wurde
            // nur max_distance_km geschrieben - Modus (Km/Bundesland/Land)
            // und Bundesland gingen serverseitig verloren.
            'max_distance_km': ref.read(userPreferencesProvider).maxDistanceKm,
            // BEFUND (13.11.2026): Hier stand `distanceFilterMode.name` -
            // der Dart-Enum-Name 'distanceKm'. Die Spalte akzeptiert nur
            // 'distance_km', 'state' oder 'germany' (CHECK-Constraint).
            // Ein PostgREST-UPDATE ist atomar: EIN verletztes Feld hat das
            // GANZE Update gekippt - der Betreiber sah "Server-Sync
            // fehlgeschlagen" und KEINE seiner Profiländerungen wurde
            // gespeichert. Die Abbildung liegt jetzt an EINER Stelle:
            // [DistanceFilterModeLabel.dbValue].
            'distance_filter_mode': ref
                .read(userPreferencesProvider)
                .distanceFilterMode
                .dbValue,
            'preferred_state': dbPreferredState(
              ref.read(userPreferencesProvider).preferredState,
            ),
          });
          // Dealbreaker-Schalter in die Settings spiegeln (Restore-Pfad).
          await ref
              .read(settingsProvider.notifier)
              .setHabitsDealbreaker(_habitsDealbreaker);
        } catch (e) {
          serverSyncOk = false;
          debugPrint('[ProfileEdit] Server-Sync fehlgeschlagen: $e');
        }
        // Präferenzen (Entfernung, "Ich suche", Bundesland, Altersspanne)
        // zusätzlich serverseitig sichern ("Nichts geht verloren"-
        // Garantie, Migration 066).
        if (serverSyncOk) {
          try {
            final s = ref.read(settingsProvider);
            serverSyncOk = await ref
                .read(userPreferencesProvider.notifier)
                .savePreferencesToServer(
                  ageRangeMin: s.ageRangeMin,
                  ageRangeMax: s.ageRangeMax,
                  stateStr: _stateCtrl.text.trim().isEmpty
                      ? null
                      : _stateCtrl.text.trim(),
                );
            if (!serverSyncOk) {
              _lastSyncError =
                  'Präferenz-Sync: Server-Verifikation '
                  'fehlgeschlagen (möglicherweise fehlt die Migration 066 '
                  'auf dem Server)';
            }
          } catch (e) {
            serverSyncOk = false;
            _lastSyncError = e.toString();
            debugPrint('[ProfileEdit] Präferenz-Sync fehlgeschlagen: $e');
          }
        }
      }

      if (!mounted) return true;
      // Dirty-Referenzen nachführen: alles ist jetzt gespeichert.
      _setzeState(() => _showValidationError = false);
      _initialAgeMin = ref.read(settingsProvider).ageRangeMin;
      _initialAgeMax = ref.read(settingsProvider).ageRangeMax;
      final prefsNow = ref.read(userPreferencesProvider);
      _initialMaxDistanceKm = prefsNow.maxDistanceKm;
      _initialDistanceMode = prefsNow.distanceFilterMode;
      _initialPreferredState = prefsNow.preferredState;
      ref.read(profileEditDirtyProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            serverSyncOk
                ? L10n.t(context, 'profile.edit.saved')
                : '${L10n.t(context, 'profile.edit.savedNoSync')} '
                      '(${_lastSyncError ?? 'unbekannt'})',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      if (redirectTo != null) {
        context.go(redirectTo);
      } else if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.profile);
      }
      return true;
    } finally {
      if (mounted) _setzeState(() => _saving = false);
    }
  }

  /// Hält den globalen Dirty-Flag für die Navigation aktuell.
  void _syncDirtyFlag() {
    if (!mounted) return;
    ref.read(profileEditDirtyProvider.notifier).state = _isDirty();
  }
}
