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

  /// Ruft eine Edge Function auf - mit Zeitlimit.
  ///
  /// DER GRUND (15.11.2026, gefunden von einem Test): Ein Aufruf ohne
  /// Zeitlimit blieb **stehen**, wenn die Function keine Antwort bekam
  /// (Server gestört, Mobilfunk voll, Funktion hängt intern). Der
  /// Bildschirm blieb dann mit dem Ladeindikator stehen, bis der
  /// Nutzer ihn verließ - im Admin-Bereich (Freigabe/Ablehnung einer
  /// Verifizierung) war das der gemeldete Fall.
  ///
  /// DER WEG: Der Aufruf bekommt ein Zeitlimit. Danach wirft er eine
  /// [TimeoutException] - der Aufrufer entscheidet, was er dem Nutzer
  /// zeigt (in der Regel eine Fehlermeldung; **nie** ein hängender
  /// Bildschirm).
  ///
  /// [zeitlimit] ist absichtlich großzügig: 20 Sekunden reichen für
  /// einen Function-Aufruf, der nur prüft und speichert.
  ///
  /// [client] ist für die Stellen, die mit einem eigenen Client arbeiten
  /// (z. B. die Löschdienste). Ohne ihn gilt der globale Client.
  static Future<FunctionResponse> rufeEdgeFunktion(
    String name, {
    required Map<String, dynamic> body,
    SupabaseClient? client,
    Duration zeitlimit = const Duration(seconds: 20),
  }) {
    final ziel = client ?? SupabaseService.client;
    return ziel.functions.invoke(name, body: body).timeout(zeitlimit);
  }
}

/// Provider für den [SupabaseClient] (Singleton). Nutzbar für Auth und DB.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
