// Der Teil '_CandidateSheet'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

/// Die Kandidatenliste: wer in der Naehe ist und zur Beschreibung passt.
///
/// BEFUND (11.11.2026, Betreiber): "wenn es bei Transit Spark mehrere mit
/// der selben Beschreibung geben sollte, dass man dann alle dafuer
/// vorgeschlagen bekommt".
///
/// Der Name erscheint nur, wenn die Person ihn freigegeben hat. Der Ort
/// ist ihre eigene Angabe ("Wagen 3") - er hilft, sie zu finden.
class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.kandidaten, required this.onWave});

  final List<TransitCandidate> kandidaten;
  final Future<void> Function(TransitCandidate kandidat) onWave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'transit.candidatesTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, 'transit.candidatesHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: kandidaten.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (context, i) {
                  final k = kandidaten[i];
                  final ort = k.place;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      // Der Name NUR, wenn die Person ihn freigegeben hat.
                      k.name?.isNotEmpty == true
                          ? k.name!
                          : L10n.t(context, 'transit.candidateAnonymous'),
                    ),
                    subtitle: Text(
                      [
                        if (k.tags.isNotEmpty) k.tags.join(', '),
                        ?ort,
                      ].join(' - '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => onWave(k),
                      child: Text(L10n.t(context, 'transit.candidateWave')),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
