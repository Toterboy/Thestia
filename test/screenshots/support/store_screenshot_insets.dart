/// System-Insets fuer den Store-Screenshot-Render.
///
/// Warum ein eigenes Modul
/// -------------------------
/// Der Render-Harness (test/screenshots/store_v091_shots_test.dart) ist
/// absichtlich gitignoriert - er ist ein Werkzeug, kein Test. Die
/// System-Insets sind aber KEIN Werkzeug-Detail, sondern die Bedingung
/// dafuer, dass der Screenshot ueberhaupt wie die App aussieht:
///
/// Die App setzt SafeArea in praktisch jedem Screen. In flutter_test
/// liefert TestFlutterView ViewPadding.zero, SafeArea setzt also NICHTS
/// und die App beginnt direkt am oberen Bildrand. Auf einem Geraet steht
/// dort die Statusleiste - der Render wirkt dadurch flach und abgeschnitten.
///
/// Weil der Harness nicht im Repository liegt, waere der Fix beim
/// naechsten Checkout verloren gewesen und niemand haette gemerkt.
/// Deshalb steht die Logik hier, in einer committeten Datei.
///
/// Aufruf im Harness:
///
/// ```dart
/// applyStoreInsets(tester.view);
/// addTearDown(() => resetStoreInsets(tester.view));
/// ```
library;

import 'package:flutter_test/flutter_test.dart';

/// Statusleisten-Hoehe in dp.
///
/// Android mit Uhr, Signal und Akku misst 24..32 dp; 24 ist der
/// untere, am haeufigsten gerenderte Wert.
const double storeStatusBarDp = 24;

/// System-Navigation am unteren Rand in dp (Gesture-Leiste: 24).
const double storeNavBarDp = 24;

/// Setzt die System-Insets auf der TestView.
///
/// Nur viewPadding ZUSAETZLICH zu padding gesetzt, nicht statt: Scaffold
/// und AppBar lesen MediaQuery.viewPadding und ziehen den oberen Rand
/// selbst ab. Mit beiden Werten verhaelt sich SafeArea wie auf einem
/// Geraet - SafeArea selbst aendert am AppBar nichts (das Scaffold
/// erledigt das), es wirkt erst auf den Body.
void applyStoreInsets(TestFlutterView view) {
  view.viewPadding = const FakeViewPadding(
    top: storeStatusBarDp,
    bottom: storeNavBarDp,
  );
  view.padding = const FakeViewPadding(
    top: storeStatusBarDp,
    bottom: storeNavBarDp,
  );
}

/// Setzt die Insets zurueck (in addTearDown zu uebergeben).
void resetStoreInsets(TestFlutterView view) {
  view.resetViewPadding();
  view.resetPadding();
}
