import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Wählt den Zeitpunkt für ein Sync-Date.
///
/// DER WEG (Betreiber, 27.11.2026): "Die annehmende Person oder die,
/// die das Date vorschlägt, kann auch direkt einen Zeitvorschlag
/// machen." Deshalb stehen hier zwei fertige Vorschläge (heute 20 Uhr,
/// morgen 18 Uhr) - und wer etwas anderes will, wählt selbst.
///
/// DIE UHRZEIT: Die Vorschläge sind auf die Stunde genau (20:00, 18:00),
/// weil sich beide sonst auf zwei verschiedene Zeiten einigen müssten.
Future<DateTime?> zeigeSyncDateZeitwahl(BuildContext context) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.today),
            title: Text(L10n.t(ctx, 'sync.timeToday')),
            subtitle: Text(_zeitText(_heute(20))),
            onTap: () => Navigator.of(ctx).pop(_heute(20)),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(L10n.t(ctx, 'sync.timeTomorrow')),
            subtitle: Text(_zeitText(_morgen(18))),
            onTap: () => Navigator.of(ctx).pop(_morgen(18)),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(L10n.t(ctx, 'sync.timePick')),
            onTap: () async {
              // Der eigene Zeitpunkt: erst der Tag, dann die Uhrzeit.
              final jetzt = DateTime.now();
              final tag = await showDatePicker(
                context: ctx,
                initialDate: jetzt.add(const Duration(days: 1)),
                firstDate: jetzt,
                lastDate: jetzt.add(const Duration(days: 90)),
              );
              if (tag == null || !ctx.mounted) return;
              final uhrzeit = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(_morgen(18)),
              );
              if (uhrzeit == null || !ctx.mounted) return;
              Navigator.of(ctx).pop(
                DateTime(
                  tag.year,
                  tag.month,
                  tag.day,
                  uhrzeit.hour,
                  uhrzeit.minute,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Heute um [stunde] Uhr.
DateTime _heute(int stunde) {
  final jetzt = DateTime.now();
  return DateTime(jetzt.year, jetzt.month, jetzt.day, stunde);
}

/// Morgen um [stunde] Uhr.
DateTime _morgen(int stunde) {
  final jetzt = DateTime.now();
  return DateTime(jetzt.year, jetzt.month, jetzt.day + 1, stunde);
}

/// Der Zeitpunkt in lesbarer Form ("heute, 20:00").
String _zeitText(DateTime zeit) {
  final jetzt = DateTime.now();
  final istHeute =
      zeit.year == jetzt.year &&
      zeit.month == jetzt.month &&
      zeit.day == jetzt.day;
  final tag = istHeute
      ? L10n.tWithoutContext('sync.timeToday')
      : L10n.tWithoutContext('sync.timeTomorrow');
  final uhrzeit =
      '${zeit.hour.toString().padLeft(2, '0')}:'
      '${zeit.minute.toString().padLeft(2, '0')}';
  return '$tag, $uhrzeit';
}
