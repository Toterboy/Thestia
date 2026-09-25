import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/supabase_service.dart';

/// Service für Entsperrungsanträge gesperrter E-Mail-Adressen.
///
/// Sendet den Antrag an die Edge Function `request-unban`, die ihrerseits
/// die Brevo-API aufruft. Der Nutzer ist bewusst NICHT eingeloggt (Konto
/// gesperrt) – die Funktion akzeptiert nur E-Mails, die wirklich in
/// public.banned_emails stehen, und ist serverseitig gedrosselt.
class UnbanRequestService {
  UnbanRequestService._();

  /// Sendet einen Entsperrungsantrag für [email] mit [reason].
  ///
  /// Wirft [AppException] bei Fehlern (ungültige Eingabe, Rate-Limit,
  /// Netzwerk/Server).
  Future<void> submitUnbanRequest({
    required String email,
    required String reason,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'request-unban',
        body: {
          'email': email.trim(),
          'reason': reason.trim(),
        },
      );

      if (response.status == 200) {
        debugPrint('[UNBAN] Entsperrungsantrag akzeptiert.');
        return;
      }

      final error = response.data is Map
          ? (response.data as Map)['error'] ?? 'Unbekannter Fehler'
          : 'Unbekannter Fehler';
      debugPrint('[UNBAN] Entsperrungsantrag abgelehnt: $error');
      throw AppException(error.toString());
    } on AppException {
      rethrow;
    } catch (e) {
      debugPrint('[UNBAN] Entsperrungsantrag fehlgeschlagen: $e');
      throw AppException(
        'Der Antrag konnte nicht gesendet werden. '
        'Bitte versuche es später erneut.',
      );
    }
  }
}

/// Provider für den Entsperrungsantrag-Service.
final unbanRequestServiceProvider = Provider<UnbanRequestService>((ref) {
  return UnbanRequestService._();
});