import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Zentrale Instanz des Supabase-Clients.
///
/// WICHTIG:
/// - Der Client wird in [main.dart] initialisiert und verwendet NUR Umgebungsvariablen
///   aus der `.env`-Datei. Niemals URLs, Keys oder Tokens hier hartkodieren.
/// - Auth-State-Änderungen (Login/Logout/Session-Replace) kannst du hier abonnieren.
class SupabaseService {
  SupabaseService._();

  /// Supabase-Client für Auth, PostgREST und Realtime.
  static SupabaseClient get client => Supabase.instance.client;

  /// Aktueller Benutzer (null = nicht eingeloggt).
  static User? get currentUser => Supabase.instance.client.auth.currentUser;

  /// Aktive Session (null = keine gültige Session).
  static Session? get currentSession =>
      Supabase.instance.client.auth.currentSession;

  /// Prüft, ob der Supabase-Client erfolgreich initialisiert wurde.
  static bool get isInitialized {
    try {
      // Wenn Supabase nicht initialisiert wurde, kann ein Fehler auftreten.
      // Wir prüfen nur die Verfügbarkeit des Clients, nicht den Auth-Status.
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Provider für den [SupabaseClient] (Singleton). Nutzbar für Auth und DB.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
