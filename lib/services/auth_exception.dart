/// App-weiter Fehler bei Authentifizierung oder Berechtigung
/// (z. B. falsche Zugangsdaten, nicht eingeloggt, fehlende Rechte).
///
/// Wird einheitlich von Auth-, Datenbank- und Storage-Services genutzt,
/// damit das UI konsistent via `catch (e is AppException)` reagiert.
///
/// Services haben KEINEN BuildContext - die Nachricht kann dort nicht
/// lokalisiert werden. Darum können Fehler optional einen L10n-Key
/// ([messageKey]) mit {platzhalter}-Params mitliefern; die Anzeige-Stellen
/// lokalisieren dann via [L10n.exc] (Fallschlüssel: [message]).
class AppException implements Exception {
  AppException(this.message, {this.messageKey, this.params = const {}});

  /// Deutsch (Fallback): wird angezeigt, wenn [messageKey] leer ist.
  final String message;

  /// Optionaler L10n-Key; Anzeige-Stellen lösen ihn mit der aktiven
  /// Locale auf und ersetzen die {platzhalter} aus [params].
  final String? messageKey;
  final Map<String, String> params;

  @override
  String toString() => 'AppException: $message';
}

/// Die E-Mail-Adresse ist auf der Plattform gesperrt (public.banned_emails,
/// Migration 045): Registrierung und Login sind nicht möglich. Der Nutzer
/// kann stattdessen einen Entsperrungsantrag senden.
class EmailBannedException extends AppException {
  EmailBannedException({required this.email, this.reason})
    : super(
        reason != null && reason.isNotEmpty
            ? 'Dieser Account wurde gesperrt: $reason'
            : 'Dieser Account wurde gesperrt. Du kannst einen '
                  'Entsperrungsantrag senden.',
      );

  final String email;
  final String? reason;
}
