import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/guardian/guardian_settings_screen.dart';

/// Der eigene Screen fuer die Elterneinstellungen (04.11.2026).
///
/// BISHER lage der Bereich "Kinderschutz & Elternzugriff" als grosse
/// Karte IN den Einstellungen, dazwischen zwischen Datenschutz und
/// Community-Regeln. Der Einstellungs-Screen war dadurch zugeballert.
void main() {
  testWidgets('der Screen zeigt den Titel im Kopf', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuardianSettingsScreen())),
    );
    await tester.pump();

    expect(
      find.text(L10n.tWithoutContext('guardian.sectionTitle')),
      findsOneWidget,
    );
  });

  testWidgets('der Screen zeigt den Elternbereich (das gemeinsame Widget)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuardianSettingsScreen())),
    );
    await tester.pump();

    // Der Abschnitt selbst kommt aus dem gemeinsamen Widget - es gibt
    // keine zweite, abweichende Darstellung.
    expect(
      find.text(L10n.tWithoutContext('guardian.sectionIntro')),
      findsOneWidget,
    );
  });

  test('die Route ist registriert', () {
    expect(AppRoutes.guardianSettings, '/guardian-settings');
  });
}
