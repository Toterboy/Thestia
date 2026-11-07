// Die Versionsfusszeile zeigt die BUILD-NUMMER mit.
//
// BEFUND (07.11.2026, Betreiber): "Aktuell ist bei Transit Spark bei
// der Aussehen auswahl die Schrift noch immer in der Statusleiste.
// Sind die APKs veraltet?" - Ja, die Admin-APKs waren Build 33, der
// Fix steckte im Build 38.
//
// Der Betreiber konnte es nicht erkennen: beide heissen "v0.10.0",
// und die App zeigte nirgends einen Build, mit dem man die Dateien
// haette unterscheiden koennen. Deshalb steht die Build-Nummer jetzt
// in der Fusszeile - sie ist das, was den Build unterscheidet.
//
// Der Test haelt beides fest: die Build-Nummer steht da, UND die
// Fusszeile nennt sie nicht mit einer leeren Klammer, wenn die
// Plattform keine Build-Nummer liefert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:thestia/widgets/app_version_footer.dart';

void main() {
  testWidgets('Die Fusszeile zeigt Version und Build-Nummer', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Thestia',
      packageName: 'com.thestia.app',
      version: '0.10.0',
      buildNumber: '39',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionFooter())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Version 0.10.0 (39)'),
      findsOneWidget,
      reason: 'die Build-Nummer steht nicht in der Fusszeile',
    );
  });

  testWidgets('Der Admin-Build ist an seiner Build-Nummer erkennbar', (
    tester,
  ) async {
    // So sieht der Admin-Build auf dem Geraet aus: Basis 39 + 9000.
    PackageInfo.setMockInitialValues(
      appName: 'Thestia',
      packageName: 'com.thestia.app',
      version: '0.10.0',
      buildNumber: '9039',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionFooter())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version 0.10.0 (9039)'), findsOneWidget);
    // Und er ist NICHT mit dem oeffentlichen Build zu verwechseln.
    expect(find.text('Version 0.10.0 (39)'), findsNothing);
  });

  testWidgets('Ohne Build-Nummer gibt es keine leere Klammer', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Thestia',
      packageName: 'com.thestia.app',
      version: '0.10.0',
      buildNumber: '',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionFooter())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version 0.10.0'), findsOneWidget);
    expect(find.textContaining('()'), findsNothing);
  });
}
