import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/dating_hour/sync_date.dart';

/// Die Vorfreude in der Chat-Kopfzeile (Plan 0.11.0).
///
/// DER WEG (Plan 0.11.0, "Begegnung statt Bildschirm"): "Sobald der
/// Meet-Intent terminiert ist, zeigt der Chat-Header die Vorfreude
/// ('Treffen am Samstag!') statt Chat-Metriken." Der Termin ist das,
/// worauf man sich freut.
///
/// DIE DATEI: Sie steht hier (und nicht im Chat-Screen), weil der
/// Chat-Screen sonst über die 1000-Zeilen-Grenze käme (der Test
/// code_datei_groessen_test.dart).
class SyncDateAntizipation extends StatelessWidget {
  const SyncDateAntizipation({super.key, required this.date});

  /// Das Sync-Date (null = es gibt keins, dann wird nichts angezeigt).
  final SyncDate? date;

  /// Die Zeile unter der Kopfzeile (null, wenn es keinen Termin gibt).
  ///
  /// DER WEG: Die Kopfzeile soll nicht höher werden, wenn kein Termin
  /// steht - deshalb kommt ohne Termin gar nichts hinein.
  static PreferredSizeWidget? unten(SyncDate? date) {
    if (date == null) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(30),
      child: SyncDateAntizipation(date: date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    if (date == null) return const SizedBox.shrink();
    final text = date.laeuft
        ? L10n.t(context, 'sync.anticipationNow')
        : L10n.tf(context, 'sync.anticipation', {
            'zeit': DateFormat('dd.MM. HH:mm').format(date.startAt.toLocal()),
          });

    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
