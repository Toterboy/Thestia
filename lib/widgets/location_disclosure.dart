import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';

/// Die prominente Standort-Offenlegung.
///
/// WARUM (06.11.2026): Google Play verlangt fuer EMPFINDLICHE
/// Berechtigungen (Kamera, Mikrofon, Standort) eine sichtbare
/// Begruendung IN DER APP, bevor der Systemdialog erscheint. Die App
/// hatte das fuer Kamera und Mikrofon - fuer den Standort fehlte es.
///
/// Das ist relevant geworden, weil die App den genauen Standort auf
/// Android 11 und aelter fuer den BLE-Scan anfragt (dort ist er
/// Pflicht). Ohne Offenlegung kann die Play-Pruefung das ablehnen.
///
/// DIE REGEL: Die Offenlegung erscheint nur, wenn die Berechtigung
/// wirklich angefragt wird - also wenn sie noch nicht erteilt ist.
/// Wer die Berechtigung schon hat, wird nicht behelligt.
///
/// Rueckgabe: true = der Nutzer hat zugestimmt (oder die Berechtigung
/// war schon da), false = abgelehnt (der Aufrufer bricht ab).
Future<bool> ensureLocationDisclosure(
  BuildContext context,
  WidgetRef ref,
) async {
  // Ist die Berechtigung schon erteilt? Dann wird nichts angefragt und
  // es braucht auch keine Begruendung.
  final status = await Permission.location.status;
  if (status.isGranted || status.isLimited) return true;

  final settings = ref.read(settingsProvider);
  if (!settings.locationDisclosureAccepted) {
    // Der Kontext wird nach einem await benutzt - das Widget kann
    // dazwischen weg sein.
    if (!context.mounted) return false;
    final accepted = await showLocationDisclosureDialog(context);
    if (!accepted) return false;
    await ref
        .read(settingsProvider.notifier)
        .setLocationDisclosureAccepted(true);
  }
  return true;
}

/// Zeigt den Dialog der Standort-Offenlegung.
Future<bool> showLocationDisclosureDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.location_on_outlined,
        size: 40,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: Text(L10n.t(ctx, 'location.disclosureTitle')),
      content: Text(L10n.t(ctx, 'location.disclosureBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L10n.t(ctx, 'location.disclosureAccept')),
        ),
      ],
    ),
  );
  return result == true;
}
