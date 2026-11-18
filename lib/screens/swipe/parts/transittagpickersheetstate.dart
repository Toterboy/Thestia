// Der Teil '_TransitTagPickerSheetState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _TransitTagPickerSheetState extends State<_TransitTagPickerSheet> {
  /// Grenzen (v0.10.0). Gespiegelt in Migration 149 - der Server
  /// lehnt mit "Bitte 2-8 Merkmale waehlen" ab, wenn der Client mehr
  /// oder weniger schickt.
  static const int minMerkmale = 2;
  static const int maxMerkmale = 8;

  final Set<String> _selected = <String>{};
  final Map<String, String?> _colors = <String, String?>{};
  // Die gewaehlten Werte der Merkmale mit Werteliste (v0.10.0,
  // Migration 187): Slug -> Wert (z. B. hair_style -> lockig).
  final Map<String, String> _values = <String, String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _customCtrl = TextEditingController(text: '');
  String _query = '';
  String _kategorie = '';

  @override
  void initState() {
    super.initState();
    _customCtrl.text = widget.initialCustomText;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  /// Merkmale, die der Suche und dem Kategoriefilter entsprechen.
  ///
  /// Gesucht wird im Slug, in den Schreibweisen UND in der Uebersetzung.
  /// Die Uebersetzung braucht den Kontext, deshalb kann sie nicht im
  /// Modell passieren.
  List<TransitTag> _gefiltert() {
    final q = _query.trim().toLowerCase();
    final ohneSuche = TransitTag.catalog.where((t) {
      if (_kategorie.isNotEmpty && t.category != _kategorie) return false;
      if (q.isEmpty) return true;
      if (t.slug.toLowerCase().contains(q)) return true;
      for (final a in t.searchAliases) {
        if (a.toLowerCase().contains(q)) return true;
      }
      final label = L10n.t(context, t.labelKey).toLowerCase();
      return label.contains(q);
    }).toList();
    return ohneSuche;
  }

  void _waehlen(TransitTag tag, bool gewaehlt) {
    setState(() {
      if (gewaehlt) {
        // Maximal EIN Wert je Kategorie: ein neuer Wert in einer
        // belegten Kategorie ersetzt den bisherigen.
        _selected.removeWhere((s) {
          final t = TransitTag.bySlug(s);
          return t != null && t.category == tag.category;
        });
        _colors.removeWhere((slug, _) {
          final t = TransitTag.bySlug(slug);
          return t != null && t.category == tag.category;
        });
        _values.removeWhere((slug, _) {
          final t = TransitTag.bySlug(slug);
          return t != null && t.category == tag.category;
        });
        if (_selected.length < maxMerkmale) {
          _selected.add(tag.slug);
          if (tag.colorizable) _colors[tag.slug] = null;
        }
      } else {
        _selected.remove(tag.slug);
        _colors.remove(tag.slug);
        _values.remove(tag.slug);
      }
    });
  }

  /// Ein Wert eines Merkmals mit Werteliste waehlen (z. B. "lockig").
  ///
  /// BEFUND (07.11.2026, Betreiber): "also Hairstyle und so" - als
  /// blosse Merkmale waren Haarlaenge und Frisur wertlos. Migration 187
  /// hat die Wertelisten eingefuehrt; hier werden sie gesetzt.
  ///
  /// Das Merkmal bleibt gewaehlt, nur der Wert aendert sich. Und es
  /// gilt wie bei den Farben: ein Wert je Kategorie.
  void _wertWaehlen(TransitTag tag, String wert) {
    setState(() {
      _values.removeWhere((slug, _) {
        final t = TransitTag.bySlug(slug);
        return t != null && t.category == tag.category;
      });
      _values[tag.slug] = wert;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theming = Theme.of(context);
    final treffer = _gefiltert();
    final kategorien = TransitTagCategory.values
        .where((k) => TransitTag.byCategory(k.slug).isNotEmpty)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, widget.titleKey),
              style: theming.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, widget.hintKey),
              style: theming.textTheme.bodySmall?.copyWith(
                color: theming.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // ---- Suche
            TextField(
              enableIMEPersonalizedLearning: false,
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: L10n.t(context, 'transit.searchHint'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ---- Kategoriefilter: EIN Chip statt einem Band.
            //
            // BEFUND (07.11.2026, Betreiber): "es so schon echt voll,
            // braucht es schon fast ein Redesign vom wie siehst du aus
            // screen."
            //
            // Vorher standen hier acht Filter-Chips in einer Reihe
            // (alle + sieben Kategorien) - ein ganzes Band, das die
            // halbe Bildschirmhoehe brauchte und trotzdem nur wiederholte,
            // was die Gruppierung der Merkmale unten schon zeigt. Jetzt
            // ist es ein Chip, der ein Menue aufmacht.
            PopupMenuButton<String>(
              initialValue: _kategorie,
              onSelected: (wert) => setState(() => _kategorie = wert),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: '',
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 16),
                      const SizedBox(width: 8),
                      Text(L10n.t(context, 'transit.categoryAll')),
                    ],
                  ),
                ),
                for (final k in kategorien)
                  PopupMenuItem<String>(
                    value: k.slug,
                    child: Row(
                      children: [
                        Icon(k.icon, size: 16),
                        const SizedBox(width: 8),
                        Text(L10n.t(context, k.labelKey)),
                      ],
                    ),
                  ),
              ],
              child: Chip(
                avatar: Icon(
                  _kategorie.isEmpty
                      ? Icons.tune
                      : TransitTagCategory.bySlug(_kategorie)?.icon ??
                            Icons.tune,
                  size: 16,
                ),
                label: Text(
                  _kategorie.isEmpty
                      ? L10n.t(context, 'transit.categoryAll')
                      : L10n.t(
                          context,
                          TransitTagCategory.bySlug(_kategorie)?.labelKey ??
                              'transit.categoryAll',
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ---- Fortschritt: Zaehler und Balken.
            //
            // BEFUND (07.11.2026, Betreiber): "es so schon echt voll".
            // Die Zahl allein sagt nicht, ob man fertig ist - der Balken
            // zeigt es. Und er zeigt auch, wie viele Merkmale ueberhaupt
            // noetig sind (mindestens zwei, hoechstens acht).
            //
            // BEFUND (14.11.2026, gefunden von einem Test): Das war eine
            // Row mit einem Expanded (Zaehler) und einem Text daneben
            // ("Je Kategorie nur ein Merkmal."). Der zweite Text wurde
            // unbeschraenkt gesetzt - passt er nicht mehr in die Zeile
            // (grosse Schrift, die App verspricht bis 3,2x), laeuft er
            // ueber und der Zaehler wird in einen 1-Spalten-Einzeiler
            // gepresst. Ein Wrap statt einer Row: passt beides in eine
            // Zeile, steht es nebeneinander, passt es nicht, rutscht der
            // Hinweis in die naechste Zeile - und nichts laeuft ueber.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  L10n.tf(context, 'transit.selectedCount', {
                    'count': '${_selected.length}',
                  }),
                  style: theming.textTheme.bodySmall,
                ),
                if (_selected.isNotEmpty)
                  Text(
                    L10n.t(context, 'transit.limitHint'),
                    style: theming.textTheme.bodySmall?.copyWith(
                      color: theming.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_selected.length / maxMerkmale).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: theming.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            if (treffer.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    L10n.tf(context, 'transit.searchEmpty', {'query': _query}),
                    style: theming.textTheme.bodyMedium?.copyWith(
                      color: theming.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              // ---- Merkmale, gruppiert nach Kategorie
              for (final kategorie in kategorien) ...[
                if (treffer.any((t) => t.category == kategorie.slug)) ...[
                  // Die Ueberschrift entfaellt bei einer Kategorie mit
                  // nur EINEM Merkmal: sie wuerde dasselbe sagen wie der
                  // Chip darunter ("Frisur" als Kategorie und "Frisur" als
                  // Merkmal - zweimal dasselbe Wort auf dem Bildschirm).
                  //
                  // BEFUND (07.11.2026, Betreiber): "es so schon echt
                  // voll" - eine Zeile weniger pro Einzelgruppe hilft
                  // mehr als ein weiterer Filter.
                  if (treffer
                          .where((t) => t.category == kategorie.slug)
                          .length >
                      1) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          kategorie.icon,
                          size: 16,
                          color: theming.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          L10n.t(context, kategorie.labelKey),
                          style: theming.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theming.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in treffer.where(
                        (t) => t.category == kategorie.slug,
                      ))
                        FilterChip(
                          avatar: Icon(tag.icon, size: 18),
                          label: Text(L10n.t(context, tag.labelKey)),
                          selected: _selected.contains(tag.slug),
                          onSelected: (sel) => _waehlen(tag, sel),
                        ),
                    ],
                  ),
                  // ---- WERT-AUSWAHL: direkt unter dem Merkmal, das
                  // einen Wert braucht (Haarlaenge, Frisur).
                  //
                  // BEFUND (07.11.2026, Betreiber): "also Hairstyle und
                  // so." Die Werte stehen nicht in einer eigenen
                  // Liste weiter unten - sie stehen da, wo man das
                  // Merkmal auswaehlt. Wer "Haarlaenge" waehlt, sieht
                  // direkt danach "kurz / mittellang / lang ...".
                  for (final tag in treffer.where(
                    (t) => t.category == kategorie.slug && t.hasValues,
                  )) ...[
                    if (_selected.contains(tag.slug)) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final wert in tag.availableValues)
                              ChoiceChip(
                                label: Text(
                                  L10n.t(context, 'transit.value.$wert'),
                                ),
                                selected: _values[tag.slug] == wert,
                                onSelected: (sel) => sel
                                    ? _wertWaehlen(tag, wert)
                                    : setState(() => _values.remove(tag.slug)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            // ---- Farbschritt: nur fuer gewaehlte farbige Merkmale
            for (final tag
                in _selected
                    .map(TransitTag.bySlug)
                    .whereType<TransitTag>()
                    .where((t) => t.colorizable)) ...[
              const SizedBox(height: 12),
              Text(
                '${L10n.t(context, tag.labelKey)}: '
                '${L10n.t(context, 'transit.colorOptional')}',
                style: theming.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              // Die gewaehlte Farbe steht als Text dabei - man soll
              // nicht raten muessen, welcher Kreis gerade gewaehlt ist.
              if (_colors[tag.slug] != null) ...[
                Text(
                  L10n.t(context, TransitTag.colorLabelKey(_colors[tag.slug]!)),
                  style: theming.textTheme.bodySmall?.copyWith(
                    color: theming.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              // Die Farben als Raster statt als Reihe.
              //
              // BEFUND (07.11.2026, Betreiber): "Vielleicht kann man das
              // auch schoener als eine Reihe an Farben machen." Bei 18
              // Haarfarben (Migration 186) bricht eine Wrap-Reihe in
              // mehrere Reihen um, und die Reihen sitzen nicht auf
              // einer Linie - das sah unordentlich aus.
              //
              // Ein Raster mit gleich grossen Kreisen ist geordneter,
              // und die Kacheln behalten ihre Groesse (die Haarfarben
              // werden sonst zu klein, um sie sicher zu treffen).
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tag.availableColors.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemBuilder: (context, i) {
                  final color = tag.availableColors[i];
                  final gewaehlt = _colors[tag.slug] == color;
                  return Tooltip(
                    message: L10n.t(context, TransitTag.colorLabelKey(color)),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _colors[tag.slug] = gewaehlt ? null : color;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: TransitTag.swatchOf(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            // BEFUND (07.11.2026, Betreiber): "Wenn man
                            // eine Farbe auswaehlt, welche am Rand ist, ist
                            // die Markierung ... abgeschnitten."
                            //
                            // Die Markierung war ein Schatten mit
                            // spreadRadius: 3 - der ragt NACH AUSSEN
                            // ueber die Kachel hinaus und wurde am
                            // Rand des Rasters abgeschnitten.
                            //
                            // Ein Rahmen wird INNERHALB der Kachel
                            // gezeichnet: er ist nie abgeschnitten.
                            // Die weisse Farbe braucht zusaetzlich einen
                            // dunklen Rand, sonst sieht man sie nicht.
                            color: gewaehlt
                                ? theming.colorScheme.primary
                                : (color == 'white'
                                      ? theming.colorScheme.outline
                                      : Colors.transparent),
                            width: gewaehlt ? 3 : 1,
                          ),
                        ),
                        child: gewaehlt
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ],
            // ---- Eigenes Textfeld zur Ergaenzung (optional)
            if (widget.customHintKey != null) ...[
              const SizedBox(height: 16),
              TextField(
                enableIMEPersonalizedLearning: false,
                autocorrect: false,
                enableSuggestions: false,
                controller: _customCtrl,
                maxLength: 140,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: L10n.t(context, widget.customHintKey!),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (widget.requireSelection && _selected.length < minMerkmale)
                    ? null
                    : () {
                        final out = <String>[];
                        for (final slug in _selected) {
                          // Drei Arten von Angaben (Migration 187):
                          //   'hemd'              - Ja/Nein-Merkmal
                          //   'hemd:weiss'        - Merkmal mit Farbe
                          //   'hair_style:lockig' - Merkmal mit Wert
                          final c = _colors[slug];
                          final w = _values[slug];
                          if (w != null && w.isNotEmpty) {
                            out.add('$slug:$w');
                          } else if (c != null && c.isNotEmpty) {
                            out.add('$slug:$c');
                          } else {
                            out.add(slug);
                          }
                        }
                        Navigator.of(
                          context,
                        ).pop((tags: out, note: _customCtrl.text.trim()));
                      },
                child: Text(L10n.t(context, 'transit.sheetSend')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
