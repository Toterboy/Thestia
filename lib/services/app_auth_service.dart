import 'package:thestia/models/user_profile.dart';

/// Gemeinsame Schnittstelle für alle Auth-Backends.
///
/// Wird von [AuthNotifier] verwendet, um unabhängig vom konkret ausgewählten
/// Backend (Demo-Modus, Supabase) zu bleiben. Implementiert von:
/// - [AuthService]        (lokaler Demo-Modus)
/// - [SupabaseAuthService] (Supabase Auth + RLS-geschützte Datenbank)
///
/// Ermöglicht Multi-Backend-Support über einen einzigen typisierten
/// [AppAuthService]-Verweis, statt des bisherigen `dynamic _auth`.
abstract class AppAuthService {
  /// Stellt die Session wieder her und liefert `true`, wenn der Nutzer
  /// eingeloggt ist.
  Future<bool> restoreSession();

  /// Registriert einen neuen Nutzer und gibt das [UserProfile] des
  /// neu angelegten Accounts zurück.
  ///
  /// [captchaToken]: Optionales CAPTCHA-Token (Bot-Schutz bei der
  /// Registrierung). Wird aktuell nur von Supabase Auth ausgewertet,
  /// wenn im Dashboard CAPTCHA aktiviert ist.
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  });

  /// Loggt den Nutzer mit [email] und [password] ein.
  ///
  /// [captchaToken]: Optionales CAPTCHA-Token (Bot-Schutz beim Login).
  /// Wird aktuell nur von Supabase Auth ausgewertet.
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  });

  /// Loggt den Nutzer per Passkey (WebAuthn) ein.
  ///
  /// MUSS dieselben Nachlauf-Effekte wie [login] setzen (Token-Persistenz,
  /// Signal-User-ID) - früher fehlten sie im Passkey-Pfad, wodurch nach
  /// der Passkey-Anmeldung Profildaten nicht zuverlässig geladen wurden.
  ///
  /// [captchaToken]: Optionales CAPTCHA-Token (der Server verlangt es für
  /// den Passkey-Flow ebenfalls, wenn CAPTCHA aktiv ist).
  Future<void> loginWithPasskey({String? captchaToken});

  /// Loggt den Nutzer aus und löscht die lokale Session.
  Future<void> logout();

  /// Löscht den Account persistent und meldet den Nutzer ab.
  Future<void> deleteAccount();
}
