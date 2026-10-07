import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/widgets/selectable_tile.dart';

/// Datenschutz-Abschnitt der Einstellungen (Sichtbarkeit + Entfernung).
///
/// Ausgelagert aus `settings_screen.dart`, damit der Store-Screenshot
/// (6. Bild) **dasselbe** Widget rendert, das in der App laeuft. Ein im
/// Test nachgebautes Layout driftet sonst von der App weg - bei einem
/// Datenschutz-Versprechen ist genau das die falsche Richtung: Das Bild
/// zeigt dann etwas, das es in der App nicht gibt.
///
/// [readOnly] sperrt die Bedienung fuer den Screenshot-Render: dort wird
/// nicht getippt, und der Pause-Bestaetigungsdialog braucht einen
/// Navigator, den der Render nicht aufbaut.
class PrivacySectionCard extends ConsumerWidget {
  const PrivacySectionCard({
    super.key,
    this.readOnly = false,
    this.maxHeight,
  });

  final bool readOnly;

  /// Begrenzt die Hoehe. Im Store-Bild soll der Abschnitt als kompakte
  /// Kachel erscheinen und nicht als halber Bildschirm. `null` = wie in
  /// der App (unbegrenzt).
  final double? maxHeight;

  /// Wechselt die Sichtbarkeit - inklusive Rueckfrage vor dem Pausieren.
  ///
  /// Eigene Methode statt eines async-Closures im `onChanged`: der
  /// Parameter dort ist ein `ValueChanged`, also `void Function(T?)`.
  /// Ein `async`-Literal passt nur ueber Kontextableitung, und die geht
  /// durch `readOnly ? null : ...` verloren. Ausserdem gehoert in einen
  /// Callback kein `await` - der Aufrufer kann nicht darauf warten.
  Future<void> _handleVisibility(
    BuildContext context,
    WidgetRef ref,
    ProfileVisibility? val,
  ) async {
    if (readOnly) return;

    final settings = ref.read(settingsProvider);
    if (val == null || val == settings.profileVisibility) return;

    if (val == ProfileVisibility.hidden) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.pause_circle,
            color: Theme.of(ctx).colorScheme.primary,
            size: 40,
          ),
          title: Text(L10n.t(ctx, 'settings.pauseConfirmTitle')),
          content: Text(L10n.t(ctx, 'settings.pauseConfirmBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'settings.pauseConfirmBtn')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await ref.read(settingsProvider.notifier).setProfileVisibility(val);

    if (!context.mounted) return;
    // Meldung nur bei echten Pause-UEBERGAENGEn - der Wechsel
    // Jeder <-> Nur Funken hat mit der Pause nichts zu tun.
    final warPause = settings.profileVisibility == ProfileVisibility.hidden;
    final istPause = val == ProfileVisibility.hidden;
    if (istPause != warPause) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            istPause
                ? L10n.t(context, 'settings.pauseOn')
                : L10n.t(context, 'settings.pauseOff'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final karte = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.t(context, 'settings.whoCanSee'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final v in ProfileVisibility.values)
              SelectableTile<ProfileVisibility>(
                value: v,
                groupValue: settings.profileVisibility,
                title: L10n.t(context, v.labelKey),
                subtitle: switch (v) {
                  ProfileVisibility.everyone =>
                    L10n.t(context, 'settings.visEveryoneSub'),
                  ProfileVisibility.matchesOnly =>
                    L10n.t(context, 'settings.visMatchesSub'),
                  ProfileVisibility.hidden =>
                    L10n.t(context, 'settings.visHiddenSub'),
                },
                onChanged: (val) =>
                    unawaited(_handleVisibility(context, ref, val)),
              ),
            const SizedBox(height: 8),
            const Divider(),
            // v0.10.0: Entfernungs-Anzeige. Aus ist der Default und
            // bleibt es auch nach einem Geraetewechsel - der Schalter
            // wird serverseitig gespiegelt, nicht nur lokal.
            //
            // [readOnly] sperrt hier bewusst NICHT. Der Screenshot zeigt
            // den Schalter sonst ausgegraut, und das widerspricht der
            // Bildunterschrift ("bleibt aus, bis du sie einschaltest"):
            // Ein deaktivierter Schalter heisst "geht nicht", ein
            // ausgeschalteter heisst "war aus". Der Render tippt ohnehin
            // nichts an, und der Handler ist eine Provider-Methode, die
            // ohne Klick nicht feuert.
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(L10n.t(context, 'settings.showDistance')),
              subtitle: Text(
                L10n.t(context, 'settings.showDistanceSub'),
              ),
              value: settings.showDistance,
              onChanged: (v) => notifier.setShowDistance(v),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'settings.localDataNote'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    if (maxHeight == null) return karte;
    return SizedBox(height: maxHeight, child: karte);
  }
}

/// Überschrift des Abschnitts.
///
/// Von `_SectionTitle` in `settings_screen.dart` dupliziert statt
/// exportiert: der Screen hat rund ein Dutzend solcher Titel, und ein
/// `part`-Verhaeltnis waere fuer ein Screenshot-Widget die schlechtere
/// Loesung. Der Doppelpflege-Bereich ist eine Zeile Farbe.
class PrivacySectionTitle extends StatelessWidget {
  const PrivacySectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Titel + Karte, so wie es im Einstellungs-Screen steht.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key, this.readOnly = false, this.maxHeight});

  final bool readOnly;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PrivacySectionTitle(L10n.t(context, 'settings.privacySection')),
        PrivacySectionCard(readOnly: readOnly, maxHeight: maxHeight),
      ],
    );
  }
}