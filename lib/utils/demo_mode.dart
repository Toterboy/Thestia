/// Reine Funktion zur Demo-Modus-Entscheidung (G-01, PLAN_ERWEITERUNGEN.md).
///
/// Testbar ohne Flutter-/Rückende-Abhängigkeiten. Prioritäten:
///   1. Release-Build: immer kein Demo-Modus.
///   2. Aktive Supabase-Session: immer kein Demo-Modus (echtes Backend).
///   3. Explizites Build-Time-Flag (`--dart-define=DEMO_MODE=true`): aktiv.
///   4. Ohne Flag: URL-Heuristik (Platzhalter-Config => lokaler Modus).
bool resolveDemoMode({
  required bool isReleaseMode,
  required bool isSupabaseInitialized,
  required bool demoModeFlag,
  required String baseUrl,
}) {
  if (isReleaseMode) return false;
  if (isSupabaseInitialized) return false;
  if (demoModeFlag) return true;
  return baseUrl.contains('example.com') ||
      baseUrl.contains('localhost') ||
      baseUrl.isEmpty;
}
