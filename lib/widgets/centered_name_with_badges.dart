import 'package:flutter/material.dart';

/// Name mittig, Abzeichen direkt daneben - ohne den Namen zu verschieben.
///
/// NUTZERWUNSCH (31.10.2026): "Namen im Profil sollen trotz der
/// Verifizierung mittig bleiben und durch die Badge nicht verschoben
/// werden."
///
/// DER TRICK: Links steht eine unsichtbare Kopie der Abzeichen. Damit
/// ist die Zeile symmetrisch - der Name sitzt genau in der Mitte, auch
/// wenn rechts ein Abzeichen steht. Ohne diesen Gegenpart schiebt das
/// Abzeichen den Namen nach links.
///
/// Die Kopie ist fuer Screenreader unsichtbar ([ExcludeSemantics]) und
/// nicht antippbar ([IgnorePointer]) - sonst wuerden die Abzeichen
/// zweimal vorgelesen und ein Tooltip waere doppelt vorhanden.
class CenteredNameWithBadges extends StatelessWidget {
  const CenteredNameWithBadges({
    required this.name,
    required this.badges,
    this.style,
    this.textAlign = TextAlign.center,
    super.key,
  });

  /// Der Name (bereits der Anzeigetext, z. B. mit Alter).
  final String name;

  /// Die Abzeichen, die rechts neben dem Namen stehen.
  final List<Widget> badges;

  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return Text(name, style: style, textAlign: textAlign);
    }

    final echte = Row(
      mainAxisSize: MainAxisSize.min,
      children: badges,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Unsichtbarer Gegenpart - haelt den Namen mittig.
        IgnorePointer(
          child: ExcludeSemantics(child: Opacity(opacity: 0, child: echte)),
        ),
        Flexible(
          child: Text(name, style: style, textAlign: textAlign),
        ),
        echte,
      ],
    );
  }
}
