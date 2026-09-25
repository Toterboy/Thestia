import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';

/// Screen zur Auswahl des Entdeckungs-Modus (wird über "Entdecken" in der Bottom-Nav erreicht).
///
/// Der Bild-Swipe UND der Blind-Swipe wurden entfernt; Entdecken besteht aus
/// "Find your Match", Zufallschat, QR Code und Dating Hour.
class SwipeModeSelectionScreen extends ConsumerWidget {
  const SwipeModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        // K: "Entdecken" ist ein Haupt-Tab der Bottom-Navigation, kein
        // Unterscreen - daher bewusst KEINEN Zurück-Pfeil anzeigen. Die
        // untere Navigation bleibt sichtbar (Screen liegt in der ShellRoute).
        automaticallyImplyLeading: false,
        title: Text(L10n.t(context, 'dm.appbarTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // v0.9.0: Gruppierung nach Zweck - neue Modi rutschen ohne
          // Unübersichtlichkeit ein.
          _ModeGroup(
            headerKey: 'dm.groupMeet',
            modes: [
              (DiscoveryMode.findMatch,
                  () => _openMode(context, ref, AppRoutes.findYourMatch)),
              (DiscoveryMode.datingHour,
                  () => _openMode(context, ref, AppRoutes.datingHourEvent)),
            ],
          ),
          const SizedBox(height: 16),
          _ModeGroup(
            headerKey: 'dm.groupDirect',
            modes: [
              (DiscoveryMode.randomChat,
                  () => _openMode(context, ref, AppRoutes.randomChat)),
            ],
          ),
          const SizedBox(height: 16),
          _ModeGroup(
            headerKey: 'dm.groupOnTheGo',
            modes: [
              (DiscoveryMode.qrScan,
                  () => _openMode(context, ref, AppRoutes.qrScan)),
              (DiscoveryMode.transitSpark,
                  () => _openMode(context, ref, AppRoutes.transitRadar)),
            ],
          ),
          const SizedBox(height: 24),
          // Hinweis
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
Text(
L10n.t(context, 'common.hint'),
style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'dm.photosNote'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Modus nur bei aktivem Profil öffnen (v0.9.1): Ist das Profil
/// pausiert, blockt ein Popup die Auswahl und führt per Klick in die
/// Einstellungen zum Entpausieren.
void _openMode(BuildContext context, WidgetRef ref, String route) {
  final paused = ref.read(settingsProvider).paused;
  if (!paused) {
    context.push(route);
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.pause_circle_outline,
        color: Theme.of(ctx).colorScheme.primary,
        size: 40,
      ),
      title: Text(L10n.t(ctx, 'paused.popupTitle')),
      content: Text(L10n.t(ctx, 'paused.popupBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.push(AppRoutes.settings);
          },
          child: Text(L10n.t(ctx, 'paused.toSettings')),
        ),
      ],
    ),
  );
}

/// Enum für die Entdeckungs-Modi (v0.9.0: gruppiert nach Zweck).
enum DiscoveryMode {
  findMatch('Find your Match', 'dm.findMatch', 'dm.findMatchDesc', Icons.headphones),
  datingHour('Dating Hour (Event)', 'dm.datingHour', 'dm.datingHourDesc', Icons.event),
  randomChat('Zufallschat', 'dm.randomChat', 'dm.randomChatDesc', Icons.chat_bubble),
  qrScan('QR Code scannen', 'dm.qrScan', 'dm.qrScanDesc', Icons.qr_code_scanner),
  transitSpark('Transit Spark', 'dm.transitSpark', 'dm.transitSparkDesc', Icons.radar);

  const DiscoveryMode(this.label, this.labelKey, this.descriptionKey, this.icon);
  final String label;

  /// L10n-Schlüssel (EN-Übersetzung der Entdecken-Modi).
  final String labelKey;
  final String descriptionKey;
  final IconData icon;

  /// Zeigt den NEU-Badge (frischer Modus in 0.9.0).
  bool get isNew => this == DiscoveryMode.transitSpark;
}

/// Gruppenkopf + Karten einer Zweck-Gruppe (v0.9.0).
class _ModeGroup extends StatelessWidget {
  const _ModeGroup({
    required this.headerKey,
    required this.modes,
  });

  final String headerKey;
  final List<(DiscoveryMode, VoidCallback)> modes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, headerKey),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        for (final (mode, onTap) in modes) ...[
          _ModeCard(
            mode: mode,
            isSelected: false,
            onTap: onTap,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Karte für einen Entdeckungs-Modus.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final DiscoveryMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  mode.icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            L10n.t(context, mode.labelKey),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : null,
                            ),
                          ),
                        ),
                        if (mode.isNew) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              L10n.t(context, 'common.new'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.t(context, mode.descriptionKey),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.8)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Q: Bewusst KEIN Haken-Icon. Die Karten sind reine
              // Auswahl-Kacheln; ein Tap führt direkt in den Modus.
            ],
          ),
        ),
      ),
    );
  }
}
