import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Fängt System-Zurück/Geste auf Vollbild-Routen ab, die per `context.go`
/// erreicht werden (kein Navigator-Stack zum Poppen): Statt die App zu
/// beenden, navigiert Zurück zu [route] (Default: Haupt-Navigation '/').
class BackToRouteScope extends StatelessWidget {
  const BackToRouteScope({required this.route, required this.child, super.key});

  /// Zielroute der Zurück-Geste (z. B. die Seite, von der aus der Screen
  /// per context.go geöffnet wurde).
  final String route;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.mounted) context.go(route);
      },
      child: child,
    );
  }
}
