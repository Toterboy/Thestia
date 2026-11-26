// Der Teil '_EventStatusCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Status-Karte für das Event.
class _EventStatusCard extends StatelessWidget {
  const _EventStatusCard({
    required this.event,
    required this.isRunning,
    required this.isEnded,
    required this.isParticipating,
    required this.minutesUntilStart,
    required this.minutesUntilEnd,
  });

  final DatingHourEvent event;
  final bool isRunning;
  final bool isEnded;
  final bool isParticipating;
  final int minutesUntilStart;
  final int minutesUntilEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = isRunning
        ? L10n.t(context, 'dh.event.liveNow')
        : isEnded
        ? L10n.t(context, 'dh.event.ended')
        : L10n.tf(context, 'dh.event.nextAt', {
            'date': _formatDate(event.eventDate),
          });

    return Card(
      color: isRunning ? colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.radio_button_checked : Icons.schedule,
                  color: isRunning
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isRunning ? colorScheme.onPrimaryContainer : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_pad(event.startHour)}:${_pad(event.startMinute)} bis ${_pad(event.endHour)}:${_pad(event.endMinute)} Uhr',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isRunning ? colorScheme.onPrimaryContainer : null,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InfoChip(
                  icon: Icons.people,
                  label: isParticipating
                      ? L10n.t(context, 'dh.event.chipParticipating')
                      : L10n.t(context, 'dh.event.chipNotParticipating'),
                  color: isRunning ? colorScheme.onPrimaryContainer : null,
                ),
                if (isRunning)
                  _InfoChip(
                    icon: Icons.timer,
                    label: L10n.tf(context, 'dh.event.remaining', {
                      'd': _formatDuration(context, minutesUntilEnd),
                    }),
                    color: colorScheme.onPrimaryContainer,
                  )
                else if (!isEnded && minutesUntilStart > 0)
                  _InfoChip(
                    icon: Icons.timer,
                    label: L10n.tf(context, 'dh.event.startIn', {
                      'd': _formatDuration(context, minutesUntilStart),
                    }),
                    color: colorScheme.primary,
                  ),
              ],
            ),
            if (!isRunning && !isEnded && minutesUntilStart > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 1 - (minutesUntilStart / (24 * 60)).clamp(0.0, 1.0),
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ],
            if (isParticipating) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRunning
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.1)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: isRunning
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isRunning
                            ? L10n.t(context, 'dh.event.participatingLive')
                            : L10n.t(context, 'dh.event.participatingWaiting'),
                        style: TextStyle(
                          color: isRunning
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
