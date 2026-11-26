// Der Teil '_ParticipantProgress'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Teilnehmer-Anzeige (v0.9.1, Migration 096): Es gibt KEIN Mindestziel
/// mehr, die Dating Hour fällt nie wegen zu weniger Leute aus. Die Karte
/// zeigt nur, wie viele dabei sind.
class _ParticipantProgress extends ConsumerWidget {
  const _ParticipantProgress({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(datingHourServiceProvider).getParticipantCount(eventId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.groups,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        L10n.tf(context, 'dh.event.participants', {
                          'n': '$count',
                        }),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.t(context, 'dh.event.participantsSub'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
