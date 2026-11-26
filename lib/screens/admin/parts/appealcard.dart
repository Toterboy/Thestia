// Der Teil '_AppealCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _AppealCard extends ConsumerWidget {
  const _AppealCard({
    required this.appeal,
    required this.busy,
    required this.onDecide,
  });

  final Map<String, dynamic> appeal;
  final bool busy;
  final void Function(bool approve) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = appeal['storagePath'] as String? ?? '';
    final status = appeal['status'] as String? ?? 'pending';
    final label = appeal['localLabel'] as String? ?? '';
    final score = (appeal['localScore'] as num?)?.toDouble() ?? 0;
    final userName =
        appeal['userName'] as String? ?? L10n.t(context, 'admin.unknown');
    final createdAt =
        DateTime.tryParse(appeal['createdAt'] as String? ?? '') ??
        DateTime.now();

    // Rahmen kommt von _AsyncList; hier nur der Inhalt.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: _SignedAppealImage(path: path),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.tf(context, 'admin.appealSubmitted', {
                        'time': createdAt.toLocal().toString().substring(0, 16),
                      }),
                    ),
                    Text(
                      L10n.tf(context, 'admin.appealFinding', {
                        'label': label.isEmpty ? 'n/a' : label,
                        'score': (score * 100).toStringAsFixed(0),
                      }),
                    ),
                    // KI-Transparenz (Nutzerwunsch): Dieser Befund stammt
                    // aus der lokalen On-Device-KI.
                    const SizedBox(height: 4),
                    const AiBadge.localCompact(),
                    const SizedBox(height: 4),
                    _StatusChip(status: status),
                  ],
                ),
              ),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 10),
            // DER UMBRUCH (18.11.2026, gefunden von einem Test): Die beiden
            // Knopfe standen in einer festen Reihe - bei großer Schrift
            // lief die Reihe über den Rand ("RenderFlex overflowed").
            //
            // DER WEG: Ein "Wrap" bricht die Reihe um, statt zu
            // überlaufen. Bei normaler Schrift steht alles nebeneinander.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onDecide(false),
                  icon: const Icon(Icons.close),
                  label: Text(L10n.t(context, 'admin.rejectTooltip')),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : () => onDecide(true),
                  icon: const Icon(Icons.check),
                  label: Text(L10n.t(context, 'admin.approve')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
