import 'package:flutter/material.dart';

import 'package:thestia/widgets/app_logo.dart';

/// Neutraler Lade-Screen, der während der Startup-Checks (Auth-Status +
/// geladene Einstellungen + Server-Sync) angezeigt wird
/// (initialLocation des Routers).
///
/// Optisch identisch zum nativen Splash (weißer Hintergrund + zentriertes
/// Logo), zusätzlich mit Lade-Indikator (drehender Kreis), damit klar ist,
/// dass die App arbeitet. Sobald alle Checks abgeschlossen sind, leitet der
/// Router automatisch weiter.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 92),
            const SizedBox(height: 32),
            // Lade-Indikator (drehender Kreis, Windows-11-Stil).
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: isDark ? Colors.white70 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
