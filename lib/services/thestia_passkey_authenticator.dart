import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_platform_interface/types/types.dart';

/// Thestia-eigener Authenticator für die WebAuthn-Zeremonie.
///
/// Unterschied zum `PasskeyAuthenticator` des `passkeys`-Packages: Hier
/// wird VOR der Zeremonie NICHT `cancelCurrentAuthenticatorOperation()`
/// aufgerufen. Das vorzeitige Abbrechen kann auf einigen Geräten die
/// FOLGENDE eigene Anfrage mit abwürgen - Android zeigt dann
/// "Anfrage abgebrochen von Thestia" und die Registrierung schlägt fehl
/// ("credential verification failed"), obwohl der Nutzer nichts
/// abgebrochen hat. Zwei parallel laufende Zeremonien werden stattdessen
/// in [PasskeyAuth] über einen Busy-Guard verhindert.
class ThestiaPasskeyAuthenticator implements PasskeyAuthenticatorInterface {
  final PasskeysPlatform _platform = PasskeysPlatform.instance;

  /// Diagnose (nur Debug-Builds): Dekodiert die clientDataJSON und loggt
  /// Typ + ORIGIN. Der Origin MUSS in GoTrue `GOTRUE_WEBAUTHN_RP_ORIGINS`
  /// stehen, sonst lehnt der Server die Registrierung ab ("credential
  /// verification failed") - siehe docs/PASSKEYS_SERVER_SETUP.md.
  void _logClientData(String clientDataJsonB64) {
    if (!kDebugMode) return;
    try {
      final normalized = base64Url.normalize(clientDataJsonB64);
      final json = utf8.decode(base64Url.decode(normalized));
      final type = RegExp(r'"type"\s*:\s*"([^"]+)"').firstMatch(json)?.group(1);
      final origin =
          RegExp(r'"origin"\s*:\s*"([^"]+)"').firstMatch(json)?.group(1);
      debugPrint('[Passkey] clientDataJSON: type=$type origin=$origin');
      debugPrint('[Passkey] ^ dieser Origin muss in GOTRUE_WEBAUTHN_RP_ORIGINS '
          'enthalten sein (auth.thestia.de)!');
    } catch (_) {
      // Diagnose ist best-effort.
    }
  }

  @override
  Future<RegisterResponseType> register(RegisterRequestType request) async {
    final response = await _platform.register(request);
    _logClientData(response.clientDataJSON);
    return response;
  }

  @override
  Future<AuthenticateResponseType> authenticate(
    AuthenticateRequestType request,
  ) async {
    final response = await _platform.authenticate(request);
    _logClientData(response.clientDataJSON);
    return response;
  }

  @override
  Future<void> signalUnknownCredential(
    SignalUnknownCredentialRequestType request,
  ) =>
      _platform.signalUnknownCredential(request);

  @override
  Future<void> signalAllAcceptedCredentials(
    SignalAllAcceptedCredentialsRequestType request,
  ) =>
      _platform.signalAllAcceptedCredentials(request);
}

