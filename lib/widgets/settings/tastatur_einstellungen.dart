import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/providers/settings/settings_provider.dart';

/// Die Einstellungen der eigenen Tastatur (0.11.0).
///
/// DER WEG: Zwei Stellschrauben - die **Belegung** (QWERTZ, QWERTY oder
/// wie die App) und die **Farbe** (wie die App, in der Akzentfarbe der
/// Farbwelt oder eine eigene). Die Vorschau unten zeigt die Wirkung,
/// ohne dass man dafür in den Chat gehen muss.
class TastaturEinstellungen extends ConsumerWidget {
  const TastaturEinstellungen({super.key});

  /// Die Farben, die der Nutzer wählen kann (eigene Farbe).
  ///
  /// DER WEG: Ein freies Farbfeld wäre auf dem Handy umständlich (die
  /// Farbwahl des Systems ist je nach Gerät verschieden). Diese
  /// Auswahl deckt die bunten Tasten ab - und der Text darauf bleibt
  /// in beiden Helligkeiten lesbar.
  static const List<int> _farben = <int>[
    0xFFE91E63,
    0xFF6750A4,
    0xFF1E88E5,
    0xFF00897B,
    0xFF43A047,
    0xFFF9A825,
    0xFFF4511E,
    0xFF546E7A,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final belegung = TastaturBelegungWert.ausWert(settings.tastaturBelegung);
    final stil = TastaturStilWert.ausWert(settings.tastaturStil);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          L10n.t(context, 'settings.keyboard'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          L10n.t(context, 'settings.keyboardSub'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'settings.keyboardLayout'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        RadioGroup<TastaturBelegung>(
          groupValue: belegung,
          onChanged: (v) {
            if (v != null) notifier.setTastaturBelegung(v);
          },
          child: Column(
            children: <Widget>[
              RadioListTile<TastaturBelegung>(
                value: TastaturBelegung.wieApp,
                title: Text(L10n.t(context, 'settings.keyboardLayoutApp')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<TastaturBelegung>(
                value: TastaturBelegung.deutsch,
                title: Text(L10n.t(context, 'settings.keyboardLayoutDe')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<TastaturBelegung>(
                value: TastaturBelegung.englisch,
                title: Text(L10n.t(context, 'settings.keyboardLayoutEn')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'settings.keyboardStyle'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        RadioGroup<TastaturStil>(
          groupValue: stil,
          onChanged: (v) {
            if (v != null) notifier.setTastaturStil(v);
          },
          child: Column(
            children: <Widget>[
              RadioListTile<TastaturStil>(
                value: TastaturStil.wieApp,
                title: Text(L10n.t(context, 'settings.keyboardStyleApp')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<TastaturStil>(
                value: TastaturStil.appFarbe,
                title: Text(L10n.t(context, 'settings.keyboardStyleAccent')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<TastaturStil>(
                value: TastaturStil.eigeneFarbe,
                title: Text(L10n.t(context, 'settings.keyboardStyleOwn')),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
        if (stil == TastaturStil.eigeneFarbe) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            L10n.t(context, 'settings.keyboardColor'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final farbe in _farben)
                _FarbKreis(
                  farbe: farbe,
                  gewaehlt: settings.tastaturFarbe == farbe,
                  onTap: () => notifier.setTastaturFarbe(farbe),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // DIE VORSCHAU: Man soll die Wahl ohne Chat ausprobieren können.
        Text(
          L10n.t(context, 'settings.keyboardPreview'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _TastaturVorschau(
          layout: belegung,
          stil: stil,
          farbe: settings.tastaturFarbe,
        ),
      ],
    );
  }
}

/// Ein Farbkreis für die eigene Tastaturfarbe.
class _FarbKreis extends StatelessWidget {
  const _FarbKreis({
    required this.farbe,
    required this.gewaehlt,
    required this.onTap,
  });

  final int farbe;
  final bool gewaehlt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: gewaehlt,
      label: L10n.t(context, 'settings.keyboardColor'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(farbe),
            border: Border.all(
              width: gewaehlt ? 3.5 : 1.5,
              color: gewaehlt
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Vorschau der Tastatur (ein kleines Tastaturmotiv).
///
/// DER WEG: Die echte Tastatur wäre hier zu groß (und sie gehört in
/// den Chat). Das Motiv zeigt aber genau das: die Tasten in der
/// gewählten Farbe und - bei QWERTZ - das "z" oben.
class _TastaturVorschau extends StatelessWidget {
  const _TastaturVorschau({
    required this.layout,
    required this.stil,
    required this.farbe,
  });

  final TastaturBelegung layout;
  final TastaturStil stil;
  final int? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eigene = stil == TastaturStil.eigeneFarbe && farbe != null;
    final flaeche = eigene ? Color(farbe!) : scheme.primary;
    // DER KONTRAST: Hell auf dunkel und umgekehrt - das rechnet die
    // Helligkeit, geraten wäre hier ein Fehler, den der Nutzer sieht.
    final helligkeit = flaeche.computeLuminance();
    final text = helligkeit > 0.5 ? Colors.black87 : Colors.white;

    final zeilen = layout == TastaturBelegung.englisch
        ? const <List<String>>[
            <String>['q', 'w', 'e', 'r', 't'],
            <String>['a', 's', 'd', 'f', 'g'],
            <String>['z', 'x', 'c', 'v', 'b'],
          ]
        : const <List<String>>[
            <String>['q', 'w', 'e', 'r', 't'],
            <String>['a', 's', 'd', 'f', 'g'],
            <String>['y', 'x', 'c', 'v', 'b'],
          ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final zeile in zeilen)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final z in zeile)
                  Container(
                    margin: const EdgeInsets.all(2),
                    width: 30,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: eigene ? flaeche : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      z,
                      style: TextStyle(
                        fontSize: 12,
                        color: eigene ? text : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
