// Der Aufbau des Bildschirms '_SettingsPrivacyOnceScreenState'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Der Aufbau
// liegt in einer ERWEITERUNG auf dieselbe Klasse - die lokalen
// Variablen des Aufbaus wandern mit, das Verhalten bleibt also
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_privacy_once_screen.dart';

extension _SettingsPrivacyOnceScreenBuild on _SettingsPrivacyOnceScreenState {
  Widget _baueEinrichtung(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final userPrefs = ref.watch(userPreferencesProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final userPrefsNotifier = ref.read(userPreferencesProvider.notifier);
    final profile = ref.watch(profileProvider);

    // Altersbasierte Sicherheits-Regeln.
    // WICHTIG: Solange das Profil (Geburtsdatum) noch nicht geladen ist,
    // wird NICHT als Minderjähriger geklemmt (Fallback 18 = Erwachsen).
    // Vorher führte der Fallback 16 dazu, dass die Altersspanne dauerhaft
    // auf 16-19 gespeichert wurde ("Alter falsch gemerkt").
    final userAge = profile.age;
    final effectiveAge = userAge ?? 18;
    final allowedAgeMin = AgeSafetyRules.minFilterAge(effectiveAge);
    final allowedAgeMax = AgeSafetyRules.maxFilterAge(effectiveAge);
    final clampedAgeMin = settings.ageRangeMin.clamp(
      allowedAgeMin,
      allowedAgeMax,
    );
    final clampedAgeMax = settings.ageRangeMax.clamp(
      clampedAgeMin,
      allowedAgeMax,
    );

    // Falls Werte außerhalb erlaubtem Bereich: asynchron korrigieren –
    // aber NUR, wenn das Alter tatsächlich bekannt ist.
    if (userAge != null &&
        (settings.ageRangeMin != clampedAgeMin ||
            settings.ageRangeMax != clampedAgeMax)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setAgeRange(clampedAgeMin, clampedAgeMax);
      });
    }

    // Suchradius für Minderjährige (BETREIBER-ENTSCHEIDUNG 03.11.2026):
    // höchstens 25 km ODER nur das gleiche Bundesland. "Ganz Deutschland"
    // ist gesperrt.
    //
    // Der SERVER entscheidet (Migration 164) - hier geht es nur darum,
    // das Angebot passend zu zeigen. Ein gepatchter Client kommt an der
    // Grenze nicht vorbei: der Server behandelt "Ganz Deutschland" für
    // Minderjährige wie 25 km.
    //
    // Der Fallback ist hier 18 (wie bei der Altersspanne oben): solange
    // das Geburtsdatum nicht geladen ist, wird nichts geklemmt. Das
    // verhindert, dass ein Erwachsender während des Einrichtens
    // plötzlich auf 25 km springt.
    final radiusGesperrt = AgeSafetyRules.isDiscoveryRadiusCapped(effectiveAge);
    final radiusMaxKm = AgeSafetyRules.maxDiscoveryRadiusKm(effectiveAge);
    // Der Slider darf keinen Wert ausserhalb [min, max] bekommen - sonst
    // wirft die Flutter-Assertion. Deshalb wird geklemmt angezeigt.
    final radiusWert = userPrefs.maxDistanceKm.clamp(1, radiusMaxKm);

    // Gespeicherte Werte korrigieren (nur wenn das Alter bekannt ist):
    // ein gespeicherter Modus "Ganz Deutschland" oder ein Radius über
    // 25 km wird für Minderjährige zurückgesetzt.
    if (userAge != null && radiusGesperrt) {
      if (userPrefs.distanceFilterMode == DistanceFilterMode.germany) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          userPrefsNotifier.setDistanceFilterMode(
            DistanceFilterMode.distanceKm,
          );
        });
      }
      if (userPrefs.maxDistanceKm != radiusWert) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          userPrefsNotifier.setMaxDistanceKm(radiusWert);
        });
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final leave = await _onWillPop();
        if (leave && mounted) router.go(AppRoutes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t(context, 'setup.appbarTitle')),
          leading: _currentPage > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: L10n.t(context, 'common.back'),
                  onPressed: _prevPage,
                )
              : null,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fortschrittsanzeige (Schritt X von Y).
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          L10n.tf(context, 'setup.stepOf', {
                            'n': '${_currentPage + 1}',
                            'of':
                                '${_SettingsPrivacyOnceScreenState._pageCount}',
                          }),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(_SettingsPrivacyOnceScreenState._pageCount == 0 ? 0 : ((_currentPage + 1) / _SettingsPrivacyOnceScreenState._pageCount * 100).round())}%',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value:
                          (_currentPage + 1) /
                          _SettingsPrivacyOnceScreenState._pageCount,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  // Nutzerwunsch: Swipen DEAKTIVIERT. Die Buttons führen die
                  // pro Schritt erforderlichen Aktionen (Validierung, Speichern)
                  // aus - Wer swipe-te, übersprang sie, wodurch Angaben nicht ins
                  // Profil übernommen wurden.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => _setzeState(() => _currentPage = i),
                  children: [
                    // Page 1: Filter & Präferenzen
                    _Page(
                      questionKey: 'setupq.filter',
                      subtitle: L10n.t(context, 'setup.filterSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t(context, 'setupp.lookingFor'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          // Mehrfachauswahl per Chips (inkl. "Alle"-Kurzform).
                          // Ein einzelnes Geschlecht kann nicht abgewählt
                          // werden, solange es das letzte aktive ist.
                          const GenderPreferenceSelector(),
                          const SizedBox(height: 20),
                          // Kein Doppel-Titel: Die Frage steht bereits in
                          // der Bubble oben (setupq.filter).
                          DropdownButtonFormField<RelationshipType>(
                            initialValue: userPrefs.relationshipType,
                            // BREITES FELD (14.11.2026, gefunden von einem
                            // Test): Ohne `isExpanded` misst das Feld das
                            // breiteste Label ("Lockere Bekanntschaft") -
                            // bei grosser Schrift (oder schmalem Geraet)
                            // laeuft der Text rechts aus der Karte
                            // ("RenderFlex overflowed by 25 pixels").
                            // Mit `isExpanded` nimmt das Feld die volle
                            // Breite und der Text wird gekuerzt.
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.relType'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: RelationshipType.casual,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.casual'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.dating,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.dating'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.relationship,
                                child: Text(
                                  L10n.t(
                                    context,
                                    'profile.edit.rel.relationship',
                                  ),
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
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.open'),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                userPrefsNotifier.setRelationshipType(v);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(
                            L10n.t(context, 'setupp.distance'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<DistanceFilterMode>(
                            initialValue: userPrefs.distanceFilterMode,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.filterLabel'),
                            ),
                            items: DistanceFilterMode.values.map((mode) {
                              // "Ganz Deutschland" ist für Minderjährige
                              // gesperrt - ausgegraut, aber sichtbar
                              // (nicht versteckt: sonst wüsste niemand,
                              // warum die Auswahl fehlt).
                              final gesperrt =
                                  mode == DistanceFilterMode.germany &&
                                  !AgeSafetyRules.isWholeGermanyAllowed(
                                    effectiveAge,
                                  );
                              return DropdownMenuItem(
                                value: mode,
                                enabled: !gesperrt,
                                child: Text(
                                  mode.label,
                                  style: gesperrt
                                      ? const TextStyle(color: Colors.grey)
                                      : null,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                userPrefsNotifier.setDistanceFilterMode(v);
                              }
                            },
                          ),
                          if (radiusGesperrt) ...[
                            const SizedBox(height: 8),
                            Text(
                              L10n.t(context, 'setupp.radiusMinorHint'),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.distanceKm) ...[
                            Text(
                              // Gleiche Quelle wie "Profil bearbeiten"
                              // (userPreferences), damit beide Screens
                              // immer denselben Wert zeigen.
                              L10n.tf(context, 'setupp.maxDistance', {
                                'km': '$radiusWert',
                              }),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: radiusWert.toDouble(),
                              min: 1,
                              max: radiusMaxKm.toDouble(),
                              divisions: radiusMaxKm - 1,
                              label: '$radiusWert km',
                              onChanged: (v) =>
                                  userPrefsNotifier.setMaxDistanceKm(v.round()),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.state) ...[
                            const SizedBox(height: 20),
                            // v0.10.0: Auswahl statt Freitext.
                            //
                            // Vorher stand hier ein Textfeld. Damit konnte
                            // jeder beliebige String gespeichert werden -
                            // "Bayern", "bayrn", "Bayern " oder "Irgendwas".
                            // Der Filter vergleicht danach exakt, also
                            // funktionierte die Entfernungsfilterung dann
                            // einfach nicht, ohne dass man es merkte.
                            //
                            // Eine Liste aus kGermanStates kann keinen
                            // Tippfehler produzieren. Und sie ist neben der
                            // Dropdown-Auswahl auf der Profilseite derselbe
                            // Katalog - vorher standen hier Vollnamen
                            // ("Bayern") und im Profil-Edit Kuerzel ("BY"),
                            // was die Filterung ebenfalls aushebte.
                            // v0.10.0: Der Wert ist das Bundesland des
                            // Profils (_selectedState) - es wird beim
                            // Speichern in profiles.state geschrieben, und
                            // genau diesen Wert vergleicht der Server
                            // (Migration 169).
                            //
                            // Vorher stand hier preferredState - eine Spalte
                            // mit CHECK-Constraint, der das Bundesland gar
                            // nicht zulaesst. Die Auswahl wurde also
                            // stillschweigend verworfen, und der Modus
                            // "Bundesland" filterte ueberhaupt nichts.
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _selectedState?.trim().isEmpty ?? true
                                  ? null
                                  : _selectedState!.trim(),
                              // isExpanded: siehe Kommentar beim
                              // Geschlecht-Feld - ohne das laeuft der
                              // Text des Bundeslands aus dem Feld
                              // heraus (BEFUND 24.11.2026: 41 Pixel
                              // auf einem 390-px-Bildschirm).
                              isExpanded: true,
                              borderRadius: BorderRadius.circular(16),
                              decoration: InputDecoration(
                                labelText: L10n.t(context, 'setupp.stateLabel'),
                              ),
                              hint: Text(L10n.t(context, 'setup.pleasePick')),
                              items: kGermanStates
                                  .map(
                                    (st) => DropdownMenuItem(
                                      value: st,
                                      child: Text(st),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) async {
                                // Kein Fehlerhinweis mehr noetig: eine
                                // Liste kann nicht falsch getippt werden.
                                //
                                // v0.10.0: Der Wert geht in das Bundesland
                                // des Profils - dort vergleicht der Server
                                // ihn (profiles.state). Die tote Spalte
                                // preferred_state wird nicht mehr benutzt.
                                if (v != null) {
                                  _setzeState(() => _selectedState = v);
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.germany) ...[
                            const SizedBox(height: 20),
                            Text(
                              L10n.t(context, 'setupp.germanyNote'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                          ],
                          // v0.10.0: Standort. Kein Ort-Textfeld mehr.
                          //
                          // Vorher stand hier ein Freitextfeld fuer die
                          // Stadt, mit 600-ms-Debounce, Geokodierung und
                          // 15-km-Abgleich zur GPS-Position. Das ergab einen
                          // Ort mit ~11 km Genauigkeit - oeffentlich, weil
                          // profiles.city fuer jeden angemeldeten Nutzer
                          // lesbar war (Migration 135).
                          //
                          // Jetzt gibt es nur noch die GPS-Erkennung, und
                          // die liefert ausschliesslich das Bundesland. Das
                          // Bundesland steht bereits auf der naechsten Seite
                          // (Profil) zur Auswahl - doppelt fragen waere
                          // nur eine weitere Pflichtangabe.
                          OutlinedButton.icon(
                            onPressed: _isDetectingLocation
                                ? null
                                : _detectLocation,
                            icon: _isDetectingLocation
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                            label: Text(L10n.t(context, 'setupp.detectState')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                          if (_locationError != null) ...[
                            const SizedBox(height: 8),
                            _LocationNotice(text: _locationError!),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Bevorzugte Altersspanne: '
                            '$clampedAgeMin bis $clampedAgeMax Jahre',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          // Zwei gekoppelte Slider statt RangeSlider:
                          // Bei identischen Werten (z. B. 18-18) friert
                          // ein RangeSlider ein (End-Regler nicht greif-
                          // bar). Die Grenzen sind die STATISCHEN
                          // Sicherheitsgrenzen - nicht die Auswahl selbst.
                          AgeRangeSliders(
                            minValue: clampedAgeMin,
                            maxValue: clampedAgeMax,
                            boundsMin: allowedAgeMin,
                            boundsMax: allowedAgeMax,
                            minLabelPrefix: L10n.t(
                              context,
                              'profile.edit.minAgeLabel',
                            ),
                            maxLabelPrefix: L10n.t(
                              context,
                              'profile.edit.maxAgeLabel',
                            ),
                            labelSuffix: L10n.t(context, 'common.years'),
                            onChanged: (min, max) {
                              notifier.setAgeRange(min, max);
                              // Entprellter Server-Sync (Regler feuern
                              // kontinuierlich) - siehe Profile-Editor.
                              ref
                                  .read(userPreferencesProvider.notifier)
                                  .queueServerSync(
                                    ageRangeMin: min,
                                    ageRangeMax: max,
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                    // Page 2: Profil & Interessen (Bio, Bundesland, Bild)
                    _Page(
                      questionKey: 'setupq.profile',
                      subtitle: L10n.t(context, 'setupp.profileSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---- Profilbild ----
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 44,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      backgroundImage: _avatarBytes != null
                                          ? MemoryImage(_avatarBytes!)
                                          : null,
                                      child: _avatarBytes == null
                                          ? const Icon(Icons.person, size: 44)
                                          : null,
                                    ),
                                    SizedBox(
                                      height: 32,
                                      width: 32,
                                      child: IconButton.filledTonal(
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        onPressed: _uploadingAvatar
                                            ? null
                                            : _pickAvatar,
                                        icon: _uploadingAvatar
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.add_a_photo),
                                        tooltip: L10n.t(
                                          context,
                                          'setup.photoTooltip',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ---- Bio ----
                          TextFormField(
                            enableIMEPersonalizedLearning: false,
                            controller: _bioCtrl,
                            maxLines: 3,
                            maxLength: 300,
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.bioLabel'),
                              hintText: L10n.t(context, 'setupp.bioHint'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // ---- Land ----
                          // Das Land war bisher nirgends in der
                          // Einrichtung erfragt - nur im Profil-Edit.
                          // Fuer neue Konten blieb es damit fest auf
                          // 'Deutschland', obwohl die App 23 Laender
                          // anbietet. Die Erklaerung nennt das Land
                          // als erhobene Daten, also wird es hier
                          // erfragt.
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCountry ?? 'Deutschland',
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.countryLabel'),
                            ),
                            items: kSupportedCountries
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                _setzeState(() => _selectedCountry = v),
                          ),
                          const SizedBox(height: 12),
                          // ---- Bundesland ----
                          DropdownButtonFormField<String>(
                            initialValue:
                                (_selectedState == null ||
                                    _selectedState!.isEmpty)
                                ? null
                                : _selectedState,
                            // BREITES FELD (14.11.2026, gefunden von einem
                            // Test): Ohne `isExpanded` misst das Feld das
                            // breiteste Bundesland ("Nordrhein-Westfalen")
                            // - bei grosser Schrift laeuft der Text rechts
                            // aus der Karte. Mit `isExpanded` nimmt das
                            // Feld die volle Breite.
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(
                                context,
                                'setupp.stateOptional',
                              ),
                            ),
                            hint: Text(L10n.t(context, 'setup.pleasePick')),
                            items: kGermanStates
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                _setzeState(() => _selectedState = v),
                          ),
                          const SizedBox(height: 20),
                          // ---- Interessen (ohne Doppel-Titel: Frage steht
                          // in der Bubble oben) ----
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppConstants.presetInterests.map((i) {
                              final selected = _selectedInterests.contains(i);
                              return FilterChip(
                                label: Text(i),
                                selected: selected,
                                onSelected: (on) => _setzeState(() {
                                  on
                                      ? _selectedInterests.add(i)
                                      : _selectedInterests.remove(i);
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    // Page 3: Deine Vorstellung (Text + Audio, überspringbar)
                    _Page(
                      questionKey: 'setupq.intro',
                      subtitle: L10n.t(context, 'setupp.introSub'),
                      child: IntroEditor(
                        initialText: _introText,
                        initialAudioPath: _introAudioPath,
                        required: false,
                        onChanged: (text, audioPath) {
                          _setzeState(() {
                            _introText = text;
                            _introAudioPath = audioPath;
                          });
                        },
                      ),
                    ),
                    // Page 4 (v0.10.0): Geburtstags-Stil mit GROSSER Vorschau.
                    // Eigene Seite, weil die 128-px-Kacheln aus dem
                    // Wrap als "nur ein kleines Bild" gemeldet wurden -
                    // und der Stil eine Entscheidung ist, keine
                    // Nebenheit.
                    _Page(
                      questionKey: 'setupq.birthday',
                      subtitle: L10n.t(context, 'setup.birthdaySub'),
                      child: SingleChildScrollView(
                        child: BirthdayStylePicker(
                          selected: _birthdayStyle,
                          large: true,
                          // Kein echtes Profilbild in der Vorschau:
                          // das Bild liegt verschluesselt als
                          // "pfad|key|iv" im Storage und laesst sich ohne
                          // Signier-URL hier nicht laden. Die Vorschau
                          // zeigt deshalb das Person-Symbol. Die Ausgabe
                          // "nur ein kleines Bild" bezog sich auf die
                          // Groesse der Kachel, nicht aufs Motiv.
                          avatarPath: null,
                          onSelected: (v) => _setzeState(() {
                            _birthdayStyle = v;
                          }),
                        ),
                      ),
                    ),
                    // Page 5 (v0.10.0): Musik-Geschmack. War im toten
                    // onboarding_screen und wurde dort mit deutschen
                    // Labels statt Slugs gespeichert, sodass das
                    // Matching nichts dazu fand.
                    _Page(
                      questionKey: 'setupq.music',
                      subtitle: L10n.t(context, 'setup.musicSub'),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MusicTasteEditor(
                              liked: _musicLiked.toList(),
                              disliked: _musicDisliked.toList(),
                              onChanged: (liked, disliked) {
                                _setzeState(() {
                                  _musicLiked = liked.toSet();
                                  _musicDisliked = disliked.toSet();
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              enableIMEPersonalizedLearning: false,
                              controller: _songCtrl,
                              maxLength: 120,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                              decoration: InputDecoration(
                                labelText: L10n.t(
                                  context,
                                  'profile.edit.favoriteSong',
                                ),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              enableIMEPersonalizedLearning: false,
                              controller: _bandCtrl,
                              maxLength: 120,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                              decoration: InputDecoration(
                                labelText: L10n.t(
                                  context,
                                  'profile.edit.favoriteBand',
                                ),
                                counterText: '',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Page 6: Gewohnheiten (Rauchen, Alkohol, Drogen)
                    _Page(
                      questionKey: 'setupq.habits',
                      subtitle: L10n.t(context, 'setupp.habitsSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t(context, 'setupp.habitsHint'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Dealbreaker (wie in "Profil bearbeiten"): harter
                          // Filter - Kandidaten mit höherem Konsum werden
                          // serverseitig ausgeschlossen.
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
                            onChanged: (v) =>
                                _setzeState(() => _habitsDealbreaker = v),
                          ),
                          const SizedBox(height: 8),
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
                    // Page 5: Privatsphäre & Theme
                    _Page(
                      questionKey: 'setupq.visibility',
                      subtitle: L10n.t(context, 'setupp.visibilitySub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Kein Doppel-Titel: Die Frage steht bereits in
                          // der Bubble oben (setupq.visibility).
                          for (final v in ProfileVisibility.values)
                            SelectableTile<ProfileVisibility>(
                              value: v,
                              groupValue: settings.profileVisibility,
                              title: L10n.t(context, v.labelKey),
                              onChanged: (val) {
                                if (val != null) {
                                  notifier.setProfileVisibility(val);
                                }
                              },
                            ),
                          const Divider(),
                          Text(
                            L10n.t(context, 'setupp.appearance'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          // v0.9.2: dieselbe Auswahl wie in den
                          // Einstellungen, damit beide Stellen nicht
                          // unterschiedlich aussehen. String-Keys statt
                          // bool? bleibt: Radio mit null-Value
                          // verschluckt Taps. Mapping: 'system' -> null,
                          // 'light' -> false, 'dark' -> true.
                          AppearanceSelector(
                            value: settings.useDarkMode == null
                                ? 'system'
                                : (settings.useDarkMode! ? 'dark' : 'light'),
                            onChanged: (mode) {
                              switch (mode) {
                                case 'light':
                                  notifier.setDarkMode(false);
                                case 'dark':
                                  notifier.setDarkMode(true);
                                default:
                                  notifier.setDarkMode(null);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            L10n.t(context, 'setupp.colorWorld'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ThemePicker(
                            selectedName: settings.themeName,
                            onChanged: (t) => notifier.setThemeName(t.name),
                          ),
                        ],
                      ),
                    ),
                    // Page 6: Passkey (überspringbar)
                    _Page(
                      questionKey: 'setupq.passkey',
                      subtitle: L10n.t(context, 'setupp.passkeySub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.key, size: 48),
                          const SizedBox(height: 16),
                          Text(L10n.t(context, 'setupp.passkeyBody')),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _passkeyBusy || _passkeyCreated
                                ? null
                                : _setupPasskey,
                            icon: _passkeyBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _passkeyCreated
                                        ? Icons.check_circle
                                        : Icons.fingerprint,
                                  ),
                            label: Text(
                              _passkeyCreated
                                  ? L10n.t(context, 'setupp.passkeyDone')
                                  : L10n.t(context, 'setupp.passkeyStart'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            L10n.t(context, 'setupp.laterHint'),
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // Page 7: Zwei-Faktor-Schutz (überspringbar)
                    _Page(
                      questionKey: 'setupq.mfa',
                      subtitle:
                          'Melde dich künftig zusätzlich mit einem Code aus '
                          'einer Authenticator-App an. Optional, du kannst '
                          'diesen Schritt überspringen.',
                      child: Builder(
                        builder: (context) {
                          final mfaActive = ref
                              .watch(mfaStatusProvider)
                              .hasVerifiedFactors;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                mfaActive
                                    ? Icons.verified_user
                                    : Icons.shield_outlined,
                                size: 48,
                                color: mfaActive
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                mfaActive
                                    ? L10n.t(context, 'setupp.mfaActive')
                                    : L10n.t(context, 'setupp.mfaBody'),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: mfaActive
                                    ? null
                                    : () => context.push(AppRoutes.mfaSetup),
                                icon: Icon(
                                  mfaActive
                                      ? Icons.check_circle
                                      : Icons.qr_code,
                                ),
                                label: Text(
                                  mfaActive
                                      ? L10n.t(context, 'setupp.mfaDone')
                                      : L10n.t(context, 'setupp.mfaStart'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                L10n.t(context, 'setupp.laterHint'),
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Page 8: Community Richtlinien
                    _Page(
                      questionKey: 'setupq.guidelines',
                      subtitle: L10n.t(context, 'setupp.guidelinesSub'),
                      child: _buildCommunityGuidelines(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_currentPage <
                        _SettingsPrivacyOnceScreenState._pageCount - 1)
                      PrimaryButton(
                        label: L10n.t(context, 'onb.next'),
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _nextPage,
                      )
                    else
                      PrimaryButton(
                        label: L10n.t(context, 'setupp.finish'),
                        icon: const Icon(Icons.check),
                        onPressed: _acceptAndFinish,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.t(context, 'setupp.changeLater'),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
