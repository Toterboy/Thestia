// Routen-Wiederherstellung nach Prozesstod (v0.9.1).
//
// Android beendet Hintergrund-Apps bei Speichermangel; beim Zurückkehren
// startet die App kalt auf dem Lade-Screen und landete bisher immer auf
// Home ("App startet neu, Chat ist weg"). Deshalb wird die letzte
// wiederherstellbare Route in den Prefs gesichert (siehe MainNavigation)
// und vom Router EINMALIG nach abgeschlossenem Login + Setup konsumiert.
//
// Eigene Datei (statt app_router.dart), damit kein Import-Zyklus mit
// auth_provider entsteht. Pfade sind bewusst als Literale dupliziert
// (vgl. AppRoutes) - bei Routen-Änderungen hier mitpflegen.

/// Schlüssel in SharedPreferences.
const String lastRoutePrefsKey = 'last_route';

/// In main() aus den Prefs geladen, vom Router genau einmal verbraucht.
String? _pendingRouteRestore;

/// Legt die beim nächsten Kaltstart wiederherzustellende Route fest.
void setPendingRouteRestore(String? route) {
  _pendingRouteRestore = route;
}

/// Holt und verbraucht die ausstehende Wiederherstellung (einmalig).
String? consumePendingRouteRestore() {
  final route = _pendingRouteRestore;
  _pendingRouteRestore = null;
  return route;
}

/// Routen, die nach einem Neustart wiederhergestellt werden dürfen.
/// Keine Setup-/Auth-/Dialog-Routen und keine transienten Screens
/// (Quiz/Spice laufen im Chat-Kontext, nicht allein).
bool isRestorableRoute(String path) {
  if (path.isEmpty) return false;
  if (path == '/' ||
      path == '/interessen' ||
      path == '/profile' ||
      path == '/find-your-match' ||
      path == '/swipe-mode-selection' ||
      path == '/transit/radar' ||
      path == '/random-chat') {
    return true;
  }
  if (path.startsWith('/chat/') && path.length > '/chat/'.length) {
    return true;
  }
  if (path.startsWith('/profile/') &&
      path != '/profile/edit' &&
      path.length > '/profile/'.length) {
    return true;
  }
  return false;
}
