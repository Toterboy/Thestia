// Die Sperre während eines laufenden Sync-Dates (Plan 0.11.0).
//
// DER WEG (Betreiber, 27.11.2026): "Es darf nur dieser Chat während des
// Dates in der App genutzt werden (also alle anderen Chats und Modi sind
// nicht verfügbar, bis das Date zu Ende ist - sowas wie Einstellungen
// soll aber gehen)."
//
// Die Regel sitzt im Router: jeder andere Weg wird auf den Chat des
// Dates umgeleitet. Der Nutzer sitzt also im Date und nicht in einem
// anderen Chat.
//
// DIE DATEI: Sie steht hier (und nicht in app_router.dart), weil der
// Router sonst über die 1000-Zeilen-Grenze käme (der Test
// code_datei_groessen_test.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/providers/dating_hour/sync_date_provider.dart';

/// Führt die Sperre aus: der Ziel-Weg (null = nichts umleiten).
///
/// DER WEG: Der gesperrte Chat steht im Anbieter
/// (syncDateSperreProvider). Läuft kein Date, passiert nichts.
String? syncDateUmleitung(Ref ref, String pfad) {
  final gesperrterChat = ref.read(syncDateSperreProvider);
  if (gesperrterChat == null) return null;
  if (syncDateFrei(pfad, gesperrterChat)) return null;
  return '/chat/$gesperrterChat';
}

/// Darf der Weg während eines laufenden Sync-Dates benutzt werden?
///
/// DER WEG: Der Chat des Dates ja (das ist der Sinn), die Einstellungen
/// und die rechtlichen Seiten auch (der Betreiber: "sowas wie
/// Einstellungen soll aber gehen"). Alles andere - andere Chats, die
/// anderen Modi - ist gesperrt.
bool syncDateFrei(String pfad, String matchId) {
  if (pfad.startsWith('/chat/$matchId')) return true;
  if (pfad.startsWith('/settings')) return true;
  if (pfad.startsWith('/privacy')) return true;
  if (pfad.startsWith('/delete-data')) return true;
  if (pfad.startsWith('/login')) return true;
  return false;
}
