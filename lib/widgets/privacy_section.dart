import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/widgets/selectable_tile.dart';

/// Schwarzflaeche fuer den Entfernungs-Schalter.
///
/// Fast schwarz statt #000: reines Schwarz neben dem warmen
/// Markenlila wirkt wie ein Loch im Bild. Der Wert liegt auch im
/// Theme-nahen Bereich des Dunkelmodus, damit der Kasten in beiden
/// Erscheinungsbildern nicht aufällt.
const Color _abgesetzterKasten = Color(0xFF17141C);

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
    final scheme = Theme.of(context).colorScheme;

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

            // v0.10.0: Entfernungs-Anzeige als schwarze Kachel.
            // ...
            //
            // Die Schalterfarben kommen aus dem Theme (`scheme.primary`,
            // `scheme.onPrimary`, `scheme.outline`, `scheme.outlineVariant`)
            // und nicht aus eigenen Werten. Der erste Entwurf hatte die
            // Markenmagenta direkt als Konstante verdrahtet - der
            // Schalter bekam damit eine Farbe, die es sonst nirgends in
            // der App gibt, und bei einem anderen Farbschema fug er
            // heraus. Jetzt wechselt er mit denselben Farben wie jeder
            // andere Schalter der App.
            //
            // Outline statt surfaceVariant fuer den ausgeschalteten
            // Zustand: die Kachel ist immer dunkel, auch im hellen
            // Erscheinungsbild. `surfaceVariant` waere dort fast
            // unsichtbar.
            SwitchListTile.adaptive(
              tileColor: _abgesetzterKasten,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
              activeThumbColor: scheme.onPrimary,
              activeTrackColor: scheme.primary,
              thumbColor: WidgetStateProperty.resolveWith(
                (zustaende) => zustaende.contains(WidgetState.selected)
                    ? scheme.onPrimary
                    : scheme.outline,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (zustaende) => zustaende.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
              // Auf schwarzem Grund muss der Text hell sein - die
              // Theme-Farben sind fuer den hellen Modus gesetzt.
              title: Text(
                L10n.t(context, 'settings.showDistance'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                L10n.t(context, 'settings.showDistanceSub'),
                style: const TextStyle(
                  color: Color(0xFFC9C4D2),
                  height: 1.35,
                ),
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