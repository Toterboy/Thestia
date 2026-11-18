// Der Aufbau des Bildschirms '_ProfileEditScreenState'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Der Aufbau
// liegt in einer ERWEITERUNG auf dieselbe Klasse - die lokalen
// Variablen des Aufbaus wandern mit, das Verhalten bleibt also
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_edit_screen.dart';

extension _ProfileEditScreenBuild on _ProfileEditScreenState {
  Widget _baueProfil(BuildContext context) {
    final profile = ref.watch(profileProvider);

    // Suchradius fuer Minderjaehrige (BETREIBER-ENTSCHEIDUNG 03.11.2026):
    // hoechstens 25 km ODER nur das gleiche Bundesland; "Ganz Deutschland"
    // ist gesperrt. Der SERVER entscheidet (Migration 164) - hier wird
    // nur das Angebot angepasst.
    //
    // Fallback 18 (wie bei der Altersspanne weiter unten): solange das
    // Geburtsdatum nicht geladen ist, wird nichts geklemmt.
    final radiusViewerAge = profile.age ?? 18;
    final radiusGesperrt = AgeSafetyRules.isDiscoveryRadiusCapped(
      radiusViewerAge,
    );
    final radiusMaxKm = AgeSafetyRules.maxDiscoveryRadiusKm(radiusViewerAge);

    // Gespeicherte Werte korrigieren, die der Regel widersprechen.
    //
    // WICHTIG: Die Snapshot-Felder werden MITVERAENDERT. Sie sind der
    // Vergleichspunkt der Dirty-Erkennung - ohne dieses Mitschreiben
    // waere der Screen nach der Korrektur "veraendert" und der Nutzer
    // bekäme beim Zurueck eine "Aenderungen verwerfen?"-Nachfrage, die
    // gar nicht von ihm stammt.
    if (radiusGesperrt) {
      final prefs = ref.read(userPreferencesProvider);
      if (prefs.maxDistanceKm > radiusMaxKm) {
        _initialMaxDistanceKm = radiusMaxKm;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(userPreferencesProvider.notifier)
              .setMaxDistanceKm(radiusMaxKm);
        });
      }
      if (prefs.distanceFilterMode == DistanceFilterMode.germany) {
        _initialDistanceMode = DistanceFilterMode.distanceKm;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(userPreferencesProvider.notifier)
              .setDistanceFilterMode(DistanceFilterMode.distanceKm);
        });
      }
    }

    // Dirty-Flag BEOBACHTEN (nicht nur post-frame melden): Reine
    // Textfeld-/Regler-Änderungen triggern sonst KEINEN Rebuild des
    // PopScope - canPop blieb true und die "Speichern?"-Nachfrage beim
    // Zurück-GESTE (System-Navigation) kam nie.
    final isDirty = ref.watch(profileEditDirtyProvider);

    // Dirty-Zustand an die Navigation melden (post-frame, damit während
    // des Builds kein Provider geschrieben wird).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dirty = _isDirty();
      if (ref.read(profileEditDirtyProvider) != dirty) {
        ref.read(profileEditDirtyProvider.notifier).state = dirty;
      }
    });

    // Tab-Wechsel mit "Speichern": Navigation setzt die Ziel-Route, hier
    // wird gespeichert und danach navigiert (bei Fehler bleibt die App
    // im Formular und zeigt den Fehlerhinweis).
    ref.listen<String?>(profileEditNavigateAfterSaveProvider, (prev, next) {
      if (next == null) return;
      ref.read(profileEditNavigateAfterSaveProvider.notifier).state = null;
      Future.microtask(() => _saveInternal(redirectTo: next));
    });

    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final choice = await _confirmUnsavedChanges();
        if (!mounted || choice == null || choice == 'cancel') return;
        if (choice == 'save') {
          await _save();
          // _saveInternal poppt bei Erfolg selbst.
        } else {
          // Verwerfen: Regler-Änderungen zurücksetzen, Dirty-Marker
          // lösen und trotzdem verlassen.
          //
          // BEFUND (14.11.2026, gefunden von einem Test): Das
          // Zurücksetzen schreibt in den sicheren Speicher. Schlägt
          // dieser Schreibvorgang fehl (verschlüsselter Speicher auf
          // dem Gerät nicht verfügbar), blieb der Nutzer im Editor
          // STECKEN: das `await` warf, der Rest des Zweigs lief nicht,
          // der Dialog war schon zu - der Nutzer war festgefangen.
          // Deshalb ist das Zurücksetzen best-effort: es darf das
          // Verlassen niemals verhindern.
          await bestEffort('Regler zurücksetzen', _revertSliderChanges);
          ref.read(profileEditDirtyProvider.notifier).state = false;
          if (context.mounted) {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.profile);
            }
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t(context, 'profile.edit.title')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            // Explizite Dirty-Prüfung am Zurück-Button: Ein blinder
            // context.pop() wird vom blockierenden PopScope abgefangen und
            // wiederholte Dialoge bzw. verlorene Änderungen vermieden.
            onPressed: () async {
              if (_isDirty()) {
                final choice = await _confirmUnsavedChanges();
                if (!mounted || choice == null || choice == 'cancel') return;
                if (choice == 'save') {
                  await _save();
                  return; // _saveInternal navigiert bei Erfolg selbst.
                }
                // Best-effort (siehe der Zweig im PopScope): ein
                // fehlgeschlagener Schreibvorgang im sicheren Speicher
                // darf den Nutzer nicht im Editor festhalten.
                await bestEffort('Regler zurücksetzen', _revertSliderChanges);
                ref.read(profileEditDirtyProvider.notifier).state = false;
                if (!mounted || !context.mounted) return;
                context.go(AppRoutes.profile);
                return;
              }
              if (!mounted || !context.mounted) return;
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.profile);
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profilbilder (v0.9.0: bis zu 3, abgerundet-rechteckig -
                // nicht mehr nur rund). Slot 0 = primäres Bild.
                _PhotoSlotsRow(
                  pendingPrimary: _pendingAvatarBytes,
                  primaryFuture: _avatarBytesFuture,
                  pendingExtra: Map.of(_pendingExtraBytes),
                  existingExtraFutures: Map.of(_extraBytesFutures),
                  removedSlots: Set.of(_removedPhotoSlots),
                  existingPhotos: profile.photos,
                  onPickPrimary: _pickProfileImage,
                  onPickExtra: _pickExtraImage,
                  onRemove: _removePhoto,
                ),
                const SizedBox(height: 16),
                _field(
                  child: TextFormField(
                    enableIMEPersonalizedLearning: false,
                    controller: _nameCtrl,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.name'),
                    ),
                    validator: (v) => Validators.name(context, v),
                  ),
                ),
                // Geburtsdatum ist nach der Registrierung GESPERRT (v0.9.1,
                // Alters-Täuschungsschutz): Der Server lehnt Änderungen ab
                // (Trigger, 056), die Anzeige bleibt zur Kontrolle sichtbar.
                _field(
                  validate: () => Validators.birthDate(context, _birthDate),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'profile.edit.birthDate'),
                          hintText: L10n.t(
                            context,
                            'profile.edit.birthDateHint',
                          ),
                          errorText: Validators.birthDate(context, _birthDate),
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        ),
                        child: Text(
                          _birthDate == null
                              ? L10n.t(context, 'profile.edit.birthDatePick')
                              : '${_birthDate!.day}.${_birthDate!.month}.'
                                    '${_birthDate!.year}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.t(context, 'profile.edit.birthDateLocked'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _field(
                  child: DropdownButtonFormField<Gender>(
                    initialValue: _gender,
                    // isExpanded: der gewaehlte Text wird sonst in seiner
                    // vollen Breite neben dem Pfeil gesetzt und laeuft bei
                    // langen Labels (z. B. "Männlich (F to M)") aus dem
                    // Feld heraus.
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.gender'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    items: [
                      for (final g in Gender.values)
                        DropdownMenuItem(
                          value: g,
                          child: Text(L10n.t(context, g.labelKey)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _setzeState(() => _gender = v);
                    },
                  ),
                ),
                _field(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          L10n.t(context, 'profile.edit.lookingFor'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        // Mehrfachauswahl inkl. "Alle"-Kurzform; speichert
                        // lokal und in Supabase (profiles.gender_preferences).
                        const GenderPreferenceSelector(),
                      ],
                    ),
                  ),
                ),
                _field(
                  child: DropdownButtonFormField<RelationshipType>(
                    initialValue: _relationshipType,
                    // isExpanded: siehe Kommentar beim Geschlecht-Feld -
                    // ohne das laufen lange Labels aus dem Feld heraus.
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.relationship'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: RelationshipType.casual,
                        child: Text(L10n.t(context, 'profile.edit.rel.casual')),
                      ),
                      DropdownMenuItem(
                        value: RelationshipType.dating,
                        child: Text(L10n.t(context, 'profile.edit.rel.dating')),
                      ),
                      DropdownMenuItem(
                        value: RelationshipType.relationship,
                        child: Text(
                          L10n.t(context, 'profile.edit.rel.relationship'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: RelationshipType.friends,
                        child: Text(
                          L10n.t(context, 'profile.edit.rel.friends'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: RelationshipType.open,
                        child: Text(L10n.t(context, 'profile.edit.rel.open')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) _setzeState(() => _relationshipType = v);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  L10n.t(context, 'profile.edit.location'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                // v0.10.0: Das Stadtfeld ist entfallen. Uebrig bleibt ein
                // Knopf, der das Bundesland aus dem aktuellen GPS-Standort
                // ableitet. Er sitzt jetzt am Bundesland-Dropdown, weil ein
                // Knopf ohne Eingabefeld keinen Platz hat.
                if (_locationError != null) ...[
                  const SizedBox(height: 8),
                  _LocationNotice(text: _locationError!),
                ],
                // Land (statt nur Deutschland) + Bundesland nur bei DE.
                _field(
                  child: DropdownButtonFormField<String>(
                    initialValue: _countryValue,
                    // isExpanded: siehe Kommentar beim Geschlecht-Feld.
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.country'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    items: kSupportedCountries
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(_countryLabel(context, c)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        _setzeState(() => _countryValue = v);
                        if (v != 'Deutschland') {
                          // Bundesland nur für Deutschland sinnvoll.
                          _stateCtrl.clear();
                        }
                      }
                    },
                  ),
                ),
                if (_countryValue == 'Deutschland')
                  _field(
                    child: DropdownButtonFormField<String>(
                      initialValue: _stateCtrl.text.isEmpty
                          ? null
                          : _stateCtrl.text,
                      // isExpanded: siehe Kommentar beim Geschlecht-Feld.
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: L10n.t(context, 'profile.edit.state'),
                        hint: Text(L10n.t(context, 'profile.edit.stateHint')),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        suffixIcon: _isDetectingLocation
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: L10n.t(
                                  context,
                                  'profile.edit.gpsTooltip',
                                ),
                                onPressed: _detectLocation,
                                icon: const Icon(Icons.my_location),
                              ),
                      ),
                      items: kGermanStates
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_stateLabel(context, s)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _stateCtrl.text = v;
                      },
                    ),
                  )
                else
                  Text(
                    L10n.t(context, 'profile.edit.stateNotApplicable'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                const SizedBox(height: 16),
                Text(
                  L10n.t(context, 'profile.edit.filters'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  child: DropdownButtonFormField<DistanceFilterMode>(
                    initialValue: ref
                        .read(userPreferencesProvider)
                        .distanceFilterMode,
                    // isExpanded: siehe Kommentar beim Geschlecht-Feld.
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.radiusMode'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: DistanceFilterMode.distanceKm,
                        child: Text(L10n.t(context, 'profile.edit.distanceKm')),
                      ),
                      DropdownMenuItem(
                        value: DistanceFilterMode.state,
                        child: Text(L10n.t(context, 'profile.edit.state')),
                      ),
                      DropdownMenuItem(
                        value: DistanceFilterMode.germany,
                        // Fuer Minderjaehrige gesperrt (Migration 164) -
                        // ausgegraut statt versteckt, damit klar ist,
                        // dass es die Option gibt und warum sie nicht
                        // geht.
                        enabled: !radiusGesperrt,
                        child: Text(
                          L10n.t(context, 'profile.edit.modeGermany'),
                          style: radiusGesperrt
                              ? const TextStyle(color: Colors.grey)
                              : null,
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref
                            .read(userPreferencesProvider.notifier)
                            .setDistanceFilterMode(v);
                        _syncDirtyFlag();
                      }
                    },
                  ),
                ),
                if (radiusGesperrt) ...[
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'profile.edit.radiusMinorHint'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Consumer(
                  builder: (context, ref, _) {
                    final prefs = ref.watch(userPreferencesProvider);
                    if (prefs.distanceFilterMode == DistanceFilterMode.state) {
                      return DropdownButtonFormField<String>(
                        initialValue: _stateCtrl.text.isEmpty
                            ? null
                            : _stateCtrl.text,
                        // isExpanded: siehe Kommentar beim Geschlecht-Feld.
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'profile.edit.state'),
                        ),
                        // v0.10.0: Der Wert ist jetzt das Bundesland aus
                        // dem Profil - und damit genau der Wert, den der
                        // Server vergleicht (profiles.state, Migration 169).
                        //
                        // Vorher standen hier Kuerzel ("BY"), die in der
                        // Spalte preferred_state landeten. Die Spalte hat
                        // einen CHECK-Constraint, der Beziehungswerte
                        // erlaubt und keine Bundeslaender - die Auswahl
                        // wurde also stillschweigend verworfen. Der Modus
                        // "Bundesland" filterte dadurch ueberhaupt nichts.
                        items: kGermanStates
                            .map(
                              (st) => DropdownMenuItem(
                                value: st,
                                child: Text(_stateLabel(context, st)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            // Das Feld _stateCtrl ist das Bundesland des
                            // Profils - es wird mit dem Speichern-Botton
                            // mitgeschickt. Der Filter laeuft also ueber
                            // denselben Wert, den das Profil anzeigt.
                            _stateCtrl.text = v;
                            _syncDirtyFlag();
                          }
                        },
                      );
                    }
                    if (prefs.distanceFilterMode ==
                        DistanceFilterMode.germany) {
                      return Text(
                        L10n.t(context, 'profile.edit.noGeoLimit'),
                        style: const TextStyle(color: Colors.grey),
                      );
                    }
                    // Der Wert wird geklemmt angezeigt: ein gespeicherter
                    // Radius ueber der Grenze wuerde sonst die Slider-
                    // Assertion ausloesen (value muss zwischen min und max
                    // liegen).
                    final radiusWert = prefs.maxDistanceKm.clamp(
                      1,
                      radiusMaxKm,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.tf(context, 'profile.edit.maxDistance', {
                            'km': '$radiusWert',
                          }),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Slider(
                          value: radiusWert.toDouble(),
                          min: 1,
                          max: radiusMaxKm.toDouble(),
                          divisions: radiusMaxKm - 1,
                          label: L10n.tf(context, 'profile.edit.maxDistance', {
                            'km': '$radiusWert',
                          }),
                          onChanged: (v) {
                            final rounded = v.round();
                            ref
                                .read(userPreferencesProvider.notifier)
                                .setMaxDistanceKm(rounded);
                            _syncDirtyFlag();
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Altersspanne: ZWEI gekoppelte Slider (gemeinsames Widget).
                // WICHTIG: Die Grenzen sind die STATISCHEN Sicherheits-
                // grenzen (minFilterAge/maxFilterAge) - NICHT clampFilterAge
                // mit den aktuellen Filterwerten. Letzteres kollabierte den
                // Spielraum auf exakt die Auswahl: Bei 18-18 waren min=max=
                // 18, beide Regler "hingen" fest und wirkten ausgegraut
                // (User-Bericht).
                Consumer(
                  builder: (context, ref, _) {
                    final settings = ref.watch(settingsProvider);
                    final myAge = ref.watch(profileProvider).age;
                    // Fallback 18 (erwachsen), solange das Geburtsdatum noch
                    // nicht geladen ist - 16 wuerde Minderj.-Grenzen (16-19)
                    // erzwingen und die gespeicherte Spanne verhunzen.
                    final viewerAge = myAge ?? 18;
                    final boundsMin = AgeSafetyRules.minFilterAge(viewerAge);
                    final boundsMax = AgeSafetyRules.maxFilterAge(viewerAge);
                    // Werte in die erlaubten Grenzen einrasten (nur Anzeige;
                    // gespeichert wird via onChanged immer im Rahmen).
                    final min = settings.ageRangeMin.clamp(
                      boundsMin,
                      boundsMax,
                    );
                    final max = settings.ageRangeMax.clamp(min, boundsMax);
                    return AgeRangeSliders(
                      minValue: min,
                      maxValue: max,
                      boundsMin: boundsMin,
                      boundsMax: boundsMax,
                      minLabelPrefix: L10n.t(
                        context,
                        'profile.edit.minAgeLabel',
                      ),
                      maxLabelPrefix: L10n.t(
                        context,
                        'profile.edit.maxAgeLabel',
                      ),
                      labelSuffix: L10n.t(context, 'common.years'),
                      onChanged: (newMin, newMax) {
                        ref
                            .read(settingsProvider.notifier)
                            .setAgeRange(newMin, newMax);
                        // Altersspanne ebenfalls (entprellt) serverseitig
                        // sichern - Regler-Änderungen sollen dauerhaft
                        // überleben, auch ohne Speichern-Knopf.
                        ref
                            .read(userPreferencesProvider.notifier)
                            .queueServerSync(
                              ageRangeMin: newMin,
                              ageRangeMax: newMax,
                            );
                        _syncDirtyFlag();
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  child: TextFormField(
                    enableIMEPersonalizedLearning: false,
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: _bioCtrl,
                    maxLines: 4,
                    maxLength: 300,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: L10n.t(context, 'profile.edit.bio'),
                    ),
                    validator: (v) => Validators.bio(context, v),
                  ),
                ),
                const SizedBox(height: 16),
                IntroEditor(
                  initialText: _introTextValue,
                  initialAudioPath: _introAudioPath,
                  onChanged: (text, audioPath) {
                    _introTextValue = text;
                    _introAudioPath = audioPath;
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.t(context, 'profile.edit.habits'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L10n.t(context, 'profile.edit.habitsSub'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Dealbreaker (v0.8.0): harter Filter - Kandidaten
                        // mit hoeberem Konsum werden serverseitig
                        // ausgeschlossen.
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            L10n.t(context, 'profile.edit.habitsDealbreaker'),
                          ),
                          subtitle: Text(
                            L10n.t(
                              context,
                              'profile.edit.habitsDealbreakerSub',
                            ),
                          ),
                          value: _habitsDealbreaker,
                          onChanged: (v) {
                            _setzeState(() => _habitsDealbreaker = v);
                          },
                        ),
                        const SizedBox(height: 16),
                        HabitudeSelector(
                          topic: HabitudeTopic.smoking,
                          value: _smoking,
                          onChanged: (v) => _setzeState(() => _smoking = v),
                        ),
                        const SizedBox(height: 16),
                        HabitudeSelector(
                          topic: HabitudeTopic.alcohol,
                          value: _alcohol,
                          onChanged: (v) => _setzeState(() => _alcohol = v),
                        ),
                        const SizedBox(height: 16),
                        HabitudeSelector(
                          topic: HabitudeTopic.drugs,
                          value: _drugs,
                          onChanged: (v) => _setzeState(() => _drugs = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Musik-Geschmack (v0.8.0): fließt in den Matching-Score
                // ein (Migration 074) und ist im eigenen Profil sichtbar.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.t(context, 'profile.edit.music'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          L10n.t(context, 'profile.edit.musicSub'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        MusicTasteEditor(
                          liked: _musicLiked,
                          disliked: _musicDisliked,
                          onChanged: (liked, disliked) {
                            _setzeState(() {
                              _musicLiked = liked;
                              _musicDisliked = disliked;
                            });
                            _syncDirtyFlag();
                          },
                        ),
                        const SizedBox(height: 12),
                        // NUTZERWUNSCH: Song und Band getrennt erfasst.
                        TextField(
                          enableIMEPersonalizedLearning: false,
                          controller: _songCtrl,
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: L10n.t(
                              context,
                              'profile.edit.favoriteSong',
                            ),
                            hintText: L10n.t(
                              context,
                              'profile.edit.favoriteSongHint',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enableIMEPersonalizedLearning: false,
                          controller: _bandCtrl,
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: L10n.t(
                              context,
                              'profile.edit.favoriteBand',
                            ),
                            hintText: L10n.t(
                              context,
                              'profile.edit.favoriteBandHint',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Geburtstags-Stil (v0.9.1): 5 schicke Styles,
                        // wirksam nur am Geburtstag.
                        BirthdayStylePicker(
                          selected: _birthdayStyle,
                          // GROSSE Vorschau (v0.10.0). Ohne dieses Flag
                          // zeigt der Picker fuenf kleine Kacheln - das war
                          // die Beanstandung "nur ein kleines Bild". Die
                          // grosse Vorschau zeigt den Stil in voller
                          // Profilbreite, darunter die Segment-Reihe zum
                          // Wechseln.
                          large: true,
                          onSelected: (style) {
                            _setzeState(() => _birthdayStyle = style);
                            _syncDirtyFlag();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  L10n.t(context, 'profile.edit.interests'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppConstants.presetInterests
                      .map(
                        (i) => StableChip.filter(
                          label: Text(i),
                          selected: profile.interests.contains(i),
                          onSelected: (_) => ref
                              .read(profileProvider.notifier)
                              .toggleInterest(i),
                        ),
                      )
                      .toList(),
                ),
                if (profile.personalityResult != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    L10n.tf(context, 'pt.profileLine', {
                      'label': profile.personalityResult ?? '',
                    }),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                const SizedBox(height: 16),
                // Persönlichkeitstest (statt in den Einstellungen).
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          L10n.t(context, 'profile.edit.personality'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ref.watch(settingsProvider).personalityTestCompleted
                              ? L10n.t(context, 'profile.edit.personalityDone')
                              : L10n.t(context, 'profile.edit.personalityOpen'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label:
                              ref
                                  .watch(settingsProvider)
                                  .personalityTestCompleted
                              ? L10n.t(
                                  context,
                                  'profile.edit.personalityRetake',
                                )
                              : L10n.t(
                                  context,
                                  'profile.edit.personalityStart',
                                ),
                          onPressed: () =>
                              context.push(AppRoutes.personalityTest),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Nutzerwunsch: Direkter Hinweis am Speichern-Button, wenn
                // beim letzten Versuch Validierungsfehler vorlagen (rot
                // markierte Felder sind sonst leicht außer Sicht).
                if (_showValidationError) ...[
                  Text(
                    L10n.t(context, 'profile.edit.missingFieldsHint'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                PrimaryButton(
                  label: L10n.t(context, 'common.save'),
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
