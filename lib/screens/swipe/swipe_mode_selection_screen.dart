import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/widgets/mode_icons.dart';
import 'package:thestia/providers/profile_provider.dart';
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
    // Verifikationsstatus fuer die Modus-Sperren (v0.10.0).
    //
    // Der Status wird BEWACHTET, nicht gelesen: nach der Freigabe
    // durch den Admin soll die Sperre ohne Neustart verschwinden.
    final verificationState = ref.watch(profileProvider).verificationState;

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
            verificationState: verificationState,
            modes: [
              (DiscoveryMode.findMatch,
                  () => _openMode(context, ref, DiscoveryMode.findMatch,
                          AppRoutes.findYourMatch)),
              (DiscoveryMode.datingHour,
                  () => _openMode(context, ref, DiscoveryMode.datingHour,
                          AppRoutes.datingHourEvent)),
            ],
          ),
          const SizedBox(height: 16),
          _ModeGroup(
            headerKey: 'dm.groupDirect',
            verificationState: verificationState,
            modes: [
              (DiscoveryMode.randomChat,
                  () => _openMode(context, ref, DiscoveryMode.randomChat,
                          AppRoutes.randomChat)),
            ],
          ),
          const SizedBox(height: 16),
          _ModeGroup(
            headerKey: 'dm.groupOnTheGo',
            verificationState: verificationState,
            modes: [
              (DiscoveryMode.qrScan,
                  () => _openMode(context, ref, DiscoveryMode.qrScan,
                          AppRoutes.qrScan)),
              (DiscoveryMode.transitSpark,
                  () => _openMode(context, ref, DiscoveryMode.transitSpark,
                          AppRoutes.transitRadar)),
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
///
/// Transit Spark (v0.9.2) zusaetzlich nur ab 18: Der Eintrag wird vor
/// dem Absprung geprueft, damit die Sperre nicht erst auf der
/// Radarseite sichtbar wird. Fail-closed - ohne Geburtsdatum bleibt
/// der Modus zu, genau wie in der Datenbank (Migration 131).
void _openMode(BuildContext context, WidgetRef ref, DiscoveryMode mode,
    String route) {
  // Verifikationssperre (v0.10.0).
  //
  // Geprueft wird der DREISTUFIGE Zustand: wer "wird geprueft" ist,
  // hat die Pruefung bereits beantragt und wartet - das ist kein
  // Mangel, sondern ein laufender Vorgang. Gesperrt ist nur, wer
  // noch gar nicht geprueft hat.
  if (_modeNeedsVerification(mode)) {
    final state = ref.read(profileProvider).verificationState;
    if (state != VerificationState.verified) {
      _showVerificationRequiredDialog(context, state);
      return;
    }
  }
  if (route == AppRoutes.transitRadar) {
    final age = ref.read(profileProvider).age;
    if (age == null || age < 18) {
      _showAdultOnlyDialog(context, missingBirthDate: age == null);
      return;
    }
  }
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

/// Dialog bei Alterssperre fuer Transit Spark.
///
/// Bewusst ein Dialog und kein stilles Verschwinden der Kachel: der
/// Nutzer soll wissen, WARUM der Modus nicht aufgeht - sonst tippt er
/// wiederholt darauf und meldet es als Fehler.
void _showAdultOnlyDialog(
  BuildContext context, {
  required bool missingBirthDate,
}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.cake,
        color: Theme.of(ctx).colorScheme.primary,
        size: 40,
      ),
      title: Text(L10n.t(ctx, 'transit.adultOnly.title')),
      content: Text(L10n.t(ctx, missingBirthDate
          ? 'transit.adultOnly.missingAge'
          : 'transit.adultOnly.body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.ok')),
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
  findMatch('Find your Spark', 'dm.findMatch', 'dm.findMatchDesc'),
  datingHour('Dating Hour (Event)', 'dm.datingHour', 'dm.datingHourDesc'),
  randomChat('Zufallschat', 'dm.randomChat', 'dm.randomChatDesc'),
  qrScan('QR Code scannen', 'dm.qrScan', 'dm.qrScanDesc'),
  transitSpark('Transit Spark', 'dm.transitSpark', 'dm.transitSparkDesc');

  const DiscoveryMode(this.label, this.labelKey, this.descriptionKey);

  final String label;

  /// L10n-Schluessel (EN-Uebersetzung der Entdecken-Modi).
  final String labelKey;
  final String descriptionKey;

  /// Zeigt den NEU-Badge (frischer Modus in 0.9.0).
  ///
  /// ENTFERNT (Nutzerwunsch, 27.10.2026): der Badge wird nicht mehr
  /// angezeigt. Transit Spark ist kein neuer Modus mehr, sondern ein
  /// etablierter - ein dauerhaft stehendes "NEU" ist nur noch Dekor.
  /// Die Eigenschaft bleibt erhalten, damit der Aufrufer sie nicht
  /// umbauen muss, wenn sie wieder gebraucht wird; sie wird aber
  /// nirgends mehr ausgewertet.
  @Deprecated('Der NEU-Badge wird nicht mehr angezeigt (27.10.2026).')
  bool get isNew => false;
}

/// Modi, die eine verifizierte Person voraussetzen (v0.10.0).
///
/// WAEHLREGEL: QR-Code-Scannen und Zufallschat bleiben ohne
/// Verifizierung zugaenglich. Beide sind "direkt" - man verbindet sich
/// mit einer Person, die man kennt oder deren Code man hat. Alle
/// anderen Modi setzen voraus, dass man alt genug und wirklich die
/// Person ist, die man behauptet: Find your Spark (Vorstellung),
/// Dating Hour (Gespraech mit einer fremden Person) und Transit Spark
/// (Begegnung unterwegs, ohne dass man sich vorher sieht).
///
/// Ohne diese Sperre waere die Alterspruefung an einer Stelle, an der
/// niemand sie prueft - die Verifizierung waere dann nur noch Dekoration.
const Set<DiscoveryMode> _modesRequiringVerification = {
  DiscoveryMode.findMatch,
  DiscoveryMode.datingHour,
  DiscoveryMode.transitSpark,
};

/// Braucht dieser Modus eine verifizierte Person?
bool _modeNeedsVerification(DiscoveryMode mode) =>
    _modesRequiringVerification.contains(mode);

/// Symbole der Modi (v0.10.0).
///
/// Drei eigene [CustomPainter] fuer Transit Spark, Find your Spark und
/// Zufallschat; Dating Hour und QR-Scan bleiben bei den Material-Symbolen.
///
/// Als Extension und nicht als Feld im Enum: ein Enum-Konstruktor ist
/// immer const, und ein Funktionsaufruf wie `_material(Icons.event)` ist
/// darin nicht erlaubt - der erste Versuch lag genau daran. Die
/// Extension hat ausserdem den Vorteil, dass das Symbol nur dort gebaut
/// wird, wo es gebraucht wird; im Enum stand vorher ein Painter, der
/// auch dann erzeugt wurde, wenn das Symbol nicht angezeigt wurde.
extension DiscoveryModeSymbol on DiscoveryMode {
  Widget symbol(Color color, {double size = 28}) => switch (this) {
        DiscoveryMode.findMatch => ModeSymbol((c) => FindSparkPainter(c),
            size: size, color: color),
        DiscoveryMode.transitSpark => ModeSymbol(
            (c) => TransitSparkPainter(c),
            size: size,
            color: color),
        DiscoveryMode.randomChat => ModeSymbol(
            (c) => QuestionChatPainter(c),
            size: size,
            color: color),
        DiscoveryMode.datingHour =>
          Icon(Icons.event, color: color, size: size),
        DiscoveryMode.qrScan =>
          Icon(Icons.qr_code_scanner, color: color, size: size),
      };
}

/// Gruppenkopf + Karten einer Zweck-Gruppe (v0.9.0).
class _ModeGroup extends StatelessWidget {
  const _ModeGroup({
    required this.headerKey,
    required this.modes,
    required this.verificationState,
  });

  final String headerKey;
  final List<(DiscoveryMode, VoidCallback)> modes;

  /// Status des Betrachtenden - entscheidet, welche Kachel gesperrt ist.
  ///
  /// PRO MODUS, nicht pro Gruppe: die Gruppe "Unterwegs" enthaelt
  /// QR-Scan (offen) und Transit Spark (gesperrt). Eine Gruppen-Sperre
  /// wuerde den QR-Scan mitsperren, obwohl er ohne Verifizierung
  /// bleiben soll.
  final VerificationState verificationState;

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
            isLocked: _modeNeedsVerification(mode) &&
                verificationState != VerificationState.verified,
            onTap: onTap,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Erklaert, warum ein Modus gesperrt ist, und bietet den Weg zur
/// Verifizierung an.
void _showVerificationRequiredDialog(
    BuildContext context, VerificationState state) {
  final router = GoRouter.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.verified_user_outlined,
        color: Theme.of(ctx).colorScheme.primary,
        size: 40,
      ),
      title: Text(L10n.t(ctx, 'dm.lockedTitle')),
      content: Text(state == VerificationState.underReview
          ? L10n.t(ctx, 'dm.lockedBodyReview')
          : L10n.t(ctx, 'dm.lockedBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.close')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            router.push(AppRoutes.verificationInfo);
          },
          child: Text(L10n.t(ctx, 'dm.lockedAction')),
        ),
      ],
    ),
  );
}

/// Karte für einen Entdeckungs-Modus.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
  });

  final DiscoveryMode mode;
  final bool isSelected;

  /// Gesperrt mangels Verifizierung (v0.10.0).
  ///
  /// Gesperrt heisst: der Modus ist sichtbar, aber nicht bedienbar.
  /// Die Kachel wird ausgegraut und traegt ein Schloss - ein
  /// voelliges Verstecken wuerde den Nutzer raten lassen, ob es den
  /// Modus ueberhaupt gibt.
  final bool isLocked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      // Key fuer den Store-Screenshot-Renderer: er exportiert jede
      // Modus-Kachel einzeln. Ohne eindeutigen Key muss er die Kachel
      // ueber ihr Layout erraten, und ein Fehler dort faellt erst
      // beim Sichten des fertigen Bildes auf - nicht im Test.
      // Ausserdem nuetzlich fuer gezielte Widget-Tests.
      key: ValueKey('mode-tile-${mode.name}'),
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
        child: Opacity(
          // Ausgegraut: die Kachel bleibt sichtbar, wirkt aber nicht
          // bedienbar. 0,45 ist der Wert, bei dem Text noch lesbar
          // bleibt - bei 0,38 verschwinden die Details.
          opacity: isLocked ? 0.45 : 1.0,
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
                child: mode.symbol(
                  isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isLocked) ...[
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 6),
                        ],
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
                        // Der NEU-Badge ist entfernt (Nutzerwunsch,
                        // 27.10.2026): "Das neu bei Transit Spark kann weg."
                        // Der Modus ist seit dem Release nicht mehr neu,
                        // und ein Badge, der dauerhaft steht, ist keiner
                        // mehr - er wird zum Dekor und stoert nur.
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
      ),
    );
  }
}
