import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:wisp/utils/constants.dart';

/// Play-Integrity-Attestierung für die Video-Verifizierung (v0.9.0,
/// Manipulationsschutz).
///
/// Nur Play-Builds auf Android fordern ein Token an (App + Gerät
/// echt?). Alles andere (F-Droid, iOS/Web, Fehler, Timeouts) liefert
/// null – der Aufrufer fällt dann auf die manuelle Queue zurück.
///
/// Wichtig: Clientseitig wird NICHTS entschieden. Token + Nonce gehen
/// an verify-account/action "auto", wo der Server das Verdict bei
/// Google prüft. Ein fehlgeschlagenes Verdict landet ebenfalls in
/// der manuellen Prüfung (fail-closed dorthin, nie harter Fehler).
class PlayIntegrityService {
  PlayIntegrityService._();

  static const MethodChannel _channel = MethodChannel('wisp/integrity');

  /// Fordert Token + Nonce an. Null = nicht verfügbar (kein harter
  /// Fehler, Aufrufer nutzt die manuelle Queue).
  static Future<({String token, String nonce})?> requestToken() async {
    try {
      if (kIsWeb || !Platform.isAndroid || AppConstants.fdroidBuild) {
        return null;
      }
      final nonce = _newNonce();
      final token = await fetchViaChannel(nonce)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      if (token == null || token.isEmpty) return null;
      return (token: token, nonce: nonce);
    } catch (_) {
      return null;
    }
  }

  /// Reiner Channel-Aufruf (testbar via gemocktem BinaryMessenger).
  static Future<String?> fetchViaChannel(String nonce) async {
    try {
      return await _channel.invokeMethod<String>(
        'requestToken',
        {'nonce': nonce},
      );
    } on PlatformException catch (e) {
      debugPrint('[Integrity] nicht verfügbar: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('[Integrity] Fehler: $e');
      return null;
    }
  }

  /// 32 Zufalls-Bytes, base64url (Nonce pro Verifizierung).
  static String _newNonce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
