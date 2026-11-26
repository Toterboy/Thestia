// Die Methoden '_TransitRadarKandidaten'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

extension _TransitRadarKandidaten on _TransitRadarScreenState {
  /// Ersatzansicht für Nutzende unter 18 bzw. ohne hinterlegtes
  /// Geburtsdatum. Erklärt die Sperre, statt sie kommentarlos zu
  /// zeigen - und verlinkt auf die Profildaten, damit der Weg zur
  /// Lösung sichtbar ist.
  Widget _adultOnlyNotice({required bool missingBirthDate}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cake, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(
              L10n.t(context, 'transit.adultOnly.title'),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              L10n.t(
                context,
                missingBirthDate
                    ? 'transit.adultOnly.missingAge'
                    : 'transit.adultOnly.body',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Radar läuft: Beim Verlassen der Seite nachfragen, ob es gestoppt
  /// oder weiterlaufen soll - mit Merk-Checkbox ("zukünftig automatisch
  /// so beibehalten"). Gespeicherte Entscheidung wird ohne Dialog
  /// angewendet; Abbrechen bleibt auf der Seite.
  Future<bool> _confirmExitWhileActive() async {
    return confirmTransitExit(context, ref, onStopped: _maybeOfferRadioCleanup);
  }

  /// Die Ortsangabe: wo bin ich gerade (ungefähr)?
  ///
  /// BEFUND (11.11.2026, Betreiber): "Man soll auch seinen ungefähren
  /// Standort angeben können, also wenn man im Zug ist z.B. Wagen 3 oder
  /// so oder wenn man auf ner Messe ist z.B. Halle 2 und da dann vielleicht
  /// bei den Toiletten oder Stand xy und so."
  ///
  /// DER PRIVATHEITSAUFLAS: Der Ort wird NICHT ermittelt - der Nutzer
  /// nennt ihn selbst. Die App weiß danach nur, was er freiwillig
  /// geschrieben hat. Das steht auch im Text, damit niemand etwas anderes
  /// vermutet.
  Widget _placePicker(BuildContext context) {
    final transit = ref.watch(transitProvider);
    final notifier = ref.read(transitProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'transit.placeLabel'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final art in _TransitRadarScreenState._placeArten)
              ChoiceChip(
                selected: transit.placeKind == art,
                label: Text(L10n.t(context, 'transit.place.$art')),
                onSelected: (v) => notifier.setPlace(
                  kind: v ? art : '',
                  text: transit.placeText,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          enableIMEPersonalizedLearning: false,
          autocorrect: false,
          enableSuggestions: false,
          key: const Key('transit.placeText'),
          maxLength: 60,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: L10n.t(context, 'transit.placeHint'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => notifier.setPlace(kind: transit.placeKind, text: v),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            L10n.t(context, 'transit.placePrivacy'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _radarPulse(BuildContext context) {
    return [
      const _PulseCircle(size: 180, opacity: 0.10),
      const _PulseCircle(size: 140, opacity: 0.16),
    ];
  }

  /// Zeigt die Personen in der Nähe, deren Beschreibung passt.
  ///
  /// BEFUND (11.11.2026, Betreiber): "wenn es bei Transit Spark mehrere mit
  /// der selben Beschreibung geben sollte, dass man dann alle dafür
  /// vorgeschlagen bekommt und die Möglichkeit hat auch mehrere
  /// anzuschreiben."
  Future<void> _showCandidates(List<String> tags) async {
    final notifier = ref.read(transitProvider.notifier);
    final kandidaten = await notifier.listCandidates(
      tags: tags,
      selfTags: ref.read(transitProvider).selfTags,
    );
    if (!mounted) return;
    if (kandidaten.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CandidateSheet(
        kandidaten: kandidaten,
        onWave: (kandidat) async {
          final ok = await notifier.sendSoftPing(
            token: '',
            messageKey: 'wave',
            recipientId: kandidat.id,
            placeKind: ref.read(transitProvider).placeKind,
            placeText: ref.read(transitProvider).placeText,
            tags: tags,
            selfTags: ref.read(transitProvider).selfTags,
          );
          if (!ctx.mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                ok
                    ? L10n.t(ctx, 'transit.candidateWaved')
                    : L10n.t(ctx, 'transit.candidateWaveFailed'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  /// Der Schalter „Namen beim Zuwinken zeigen" (v0.10.1).
  ///
  /// BEFUND (10.11.2026, Betreiber): Der Name beim Zuwinken soll
  /// abschaltbar sein. Der Server entscheidet (transit_show_name,
  /// Migration 208) - ein Schalter nur im Gerät wäre wertlos.
  ///
  /// Der Hinweis darunter nennt die GRENZE: Wer neben einem steht,
  /// erkennt einen trotzdem. Das steht hier, weil ein Schalter ohne
  /// diese Erklärung eine falsche Sicherheit erzeugt.
  Widget _showNameSwitch(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final an = settings.transitShowName;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: an,
          onChanged: (v) => notifier.setTransitShowName(v),
          contentPadding: EdgeInsets.zero,
          title: Text(
            L10n.t(context, 'transit.showNameTitle'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            an
                ? L10n.t(context, 'transit.showNameSub')
                : L10n.t(context, 'transit.showNameSubOff'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(
            L10n.t(context, 'transit.showNameBoundary'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  /// v0.9.0: Nachgeschaute Personen der 2-Stunden-Ruhezeit - Bottom
  /// Sheet mit der gewohnten Grüßen-Liste (Pingen nach 45-min-TTL
  /// kann serverseitig ins Leere laufen; das Sheet erklärt das).
  Future<void> _showRetainedEncounters() async {
    final until = ref.read(transitProvider.notifier).softUntil();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.t(ctx, 'transit.retainedTitle'),
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                until == null
                    ? L10n.t(ctx, 'transit.retainedHint')
                    : L10n.tf(ctx, 'transit.retainedUntil', {
                        'time':
                            '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}',
                      }),
                style: Theme.of(ctx).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Expanded(child: _EncounterGreetList()),
            ],
          ),
        ),
      ),
    );
  }
}
