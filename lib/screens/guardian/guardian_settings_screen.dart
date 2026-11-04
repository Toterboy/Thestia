import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/guardian_section.dart';

/// Der eigene Screen fuer die Elterneinstellungen.
///
/// WARUM EIN EIGENER SCREEN (04.11.2026): Im Einstellungs-Screen lag
/// der ganze Bereich "Kinderschutz & Elternzugriff" als eine grosse
/// Karte zwischen Datenschutz und Community-Regeln - mit PIN-Dialog,
/// Benachrichtigungs-Rhythmus und Nutzungszeit. Das hat den
/// Einstellungs-Screen zugeballert und den Bereich schlecht auffindbar
/// gemacht.
///
/// Jetzt: In den Einstellungen steht ein Eintrag mit dem aktuellen
/// Status, und die eigentlichen Einstellungen liegen hier - weiterhin
/// durch die PIN des Elternteils geschuetzt. Wer die Freigabe
/// beendet (mit 18), findet den Weg weiterhin ohne PIN, denn das ist
/// eine Entscheidung des Jugendlichen selbst.
///
/// Der Inhalt ist das bewusst GEMEINSAME Widget [GuardianSection] -
/// kein zweiter Aufbau. Das Widget rendert je nach Zustand den Status
/// (keine Freigabe / wartet / aktiv) und die Einstellungen; im
/// Einstellungs-Screen steht davon nur die Statuszeile.
class GuardianSettingsScreen extends ConsumerWidget {
  const GuardianSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'guardian.sectionTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          GuardianSection(showTitle: false),
        ],
      ),
    );
  }
}
