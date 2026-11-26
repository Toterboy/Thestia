// Der Teil '_EventInfoCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

/// Event-Info Karte.
class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.info.title'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.favorite,
              title: L10n.t(context, 'dh.feature.realChat'),
              subtitle: L10n.t(context, 'dh.feature.noPhotos'),
            ),
            _InfoRow(
              icon: Icons.timer,
              title: L10n.t(context, 'dh.info.timeTitle'),
              subtitle: L10n.t(context, 'dh.info.timeSub'),
            ),
            _InfoRow(
              icon: Icons.lock,
              title: L10n.t(context, 'dh.feature.e2eTitle'),
              subtitle: L10n.t(context, 'dh.feature.e2eSub'),
            ),
            _InfoRow(
              icon: Icons.people,
              title: L10n.t(context, 'dh.info.liveTitle'),
              subtitle: L10n.t(context, 'dh.info.liveSub'),
            ),
            _InfoRow(
              icon: Icons.refresh,
              title: L10n.t(context, 'dh.info.retryTitle'),
              subtitle: L10n.t(context, 'dh.info.retrySub'),
            ),
          ],
        ),
      ),
    );
  }
}
