import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/services/supabase_service.dart';

/// Alle Aufrufe rund um die elterliche Freigabe.
///
/// Die Regeln sitzen in der Datenbank (Migration 165/166). Diese Klasse
/// ist nur der Transport - sie entscheidet nichts selbst.
class GuardianService {
  GuardianService(this._client);

  final SupabaseClient _client;

  /// Liest den aktuellen Stand.
  ///
  /// FEHLER WERDEN WEITERGEGEBEN (BEFUND 06.11.2026): Vorher hat diese
  /// Methode jeden Fehler in "unbekannt" verwandelt. Der Bildschirm
  /// konnte dann nicht unterscheiden zwischen "laedt noch" und "der
  /// Abruf ist gescheitert" - und zeigte in beiden Faellen einen
  /// endlosen Ladekreis. Der Aufrufer entscheidet jetzt, was passiert.
  ///
  /// Zusaetzlich gibt es fuer beide Schritte eine Zeitgrenze: ein
  /// haengender Server darf den Elternbereich nicht blockieren.
  Future<GuardianStatus> fetchStatus() async {
    // Noch nicht bereit (App-Start, Testlauf): das ist KEIN Fehler des
    // Dienstes, sondern eine Lage - der Aufrufer darf sie von einem
    // echten Fehler unterscheiden und spaeter erneut versuchen.
    //
    // DIE PRUEFUNG STEHT HIER UND NICHT IM PROVIDER (06.11.2026): so
    // laesst sich der Fehlerpfad testen, ohne die Supabase-Verbindung
    // in einem Test aufbauen zu muessen.
    if (!SupabaseService.isInitialized) {
      throw const GuardianServiceException('not_ready');
    }
    // Die Zeitzone melden, BEVOR der Status gelesen wird.
    //
    // Der Server braucht sie, um die elterliche Nutzungszeit in der
    // LOKALEN Zeit des Geraets zu pruefen (Migration 176). Ohne sie
    // kann er die Beschraenkung nicht bewerten - und der Server
    // blockiert dann fail-closed.
    //
    // Das Melden ist ein eigener Schritt und darf den Status nicht
    // verhindern: schlaegt er fehl, lesen wir trotzdem den Status. Die
    // Zeitgrenze ist wichtig - ein haengender Aufruf wuerde den
    // Elternblock dauerhaft am Ladekreis festhalten (BEFUND 06.11.2026).
    await _meldeZeitzone();
    final res = await _client
        .rpc('get_my_guardian_status')
        .timeout(const Duration(seconds: 12));
    if (res is Map) {
      return GuardianStatus.fromJson(Map<String, dynamic>.from(res));
    }
    throw const GuardianServiceException('empty_response');
  }

  /// Meldet die Zeitzone des Geraets an den Server.
  ///
  /// BEOGRUENDUNG (04.11.2026): Die elterliche Nutzungszeit ist
  /// "Minuten seit Mitternacht in der Zeitzone des Geraets". Solange
  /// der Server die Zeitzone nicht kannte, war eine serverseitige
  /// Pruefung unmoglich - die Beschraenkung galt damit nur im
  /// Client, und der Client ist patchbar.
  ///
  /// Wir melden einen IANA-Namen ("Europe/Berlin"). Der Server rechnet
  /// damit selbst und bekommt die lokale Zeit inklusive Sommerzeit -
  /// es gibt keine Umrechnung, die er selbst machen muss.
  ///
  /// Fehler werden verschluckt: Die Zeitzone ist eine Verbesserung,
  /// kein Grund, den Status nicht zu lesen. Der Server blockiert in
  /// dem Fall fail-closed - der Jugendliche sieht dann die Sperre und
  /// kann sie ueber den Standort-Check (der die Zeitzone mitschickt)
  /// aufloesen.
  Future<void> _meldeZeitzone() async {
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      final name = tz.identifier;
      if (name.isEmpty) return;
      await _client
          .rpc('report_my_timezone', params: {'p_timezone': name})
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Guardian] Zeitzone nicht meldbar: $e');
      }
    }
  }

  /// Fordert die Freigabe eines Elternteils an.
  ///
  /// Die Adresse muss eine andere sein als die eigene Kontoadresse - das
  /// prueft der Server (`same_email`). Die Altersgrenze (16/17) prueft
  /// der Server ebenfalls (`not_eligible`).
  Future<GuardianResult> requestConsent(String guardianEmail) async {
    try {
      await _client.rpc(
        'request_guardian_consent',
        params: {'p_guardian_email': guardianEmail.trim().toLowerCase()},
      );
      return const GuardianResult.ok();
    } catch (e) {
      return GuardianResult.failed(_codeOf(e), e.toString());
    }
  }

  /// Beendet die Freigabe (der Jugendliche selbst).
  Future<GuardianResult> revoke() async {
    try {
      await _client.rpc(
        'revoke_guardian_consent',
        params: {'p_actor': 'youth'},
      );
      return const GuardianResult.ok();
    } catch (e) {
      return GuardianResult.failed(_codeOf(e), e.toString());
    }
  }

  /// Die Entscheidung mit 18: `ended`, `grace` oder `indefinite`.
  Future<GuardianResult> setAccessPolicy(
    String policy, {
    int? graceMonths,
  }) async {
    try {
      await _client.rpc(
        'set_guardian_access_policy',
        params: {'p_policy': policy, 'p_grace_months': graceMonths},
      );
      return const GuardianResult.ok();
    } catch (e) {
      return GuardianResult.failed(_codeOf(e), e.toString());
    }
  }

  /// Prueft die vierstellige PIN der Aufsicht.
  ///
  /// Der Vergleich laeuft auf dem SERVER - das Geraet kennt die PIN nie.
  /// Bei falschen Versuchen sperrt der Server die PIN (5 pro Stunde).
  Future<bool> verifyPin(String pin) async {
    try {
      final res = await _client.rpc(
        'verify_guardian_pin',
        params: {'p_pin': pin},
      );
      return res == true;
    } catch (e) {
      debugPrint('[Guardian] PIN-Pruefung fehlgeschlagen: $e');
      return false;
    }
  }

  /// Markiert den Screen zum 18. Geburtstag als gesehen.
  Future<void> markTransitionDone() async {
    try {
      await _client.rpc('mark_guardian_transition_done');
    } catch (e) {
      debugPrint('[Guardian] Übergang nicht markiert: $e');
    }
  }

  /// Aendert die Einstellungen der Aufsicht - nur mit der PIN.
  ///
  /// Der PIN-Vergleich laeuft auf dem Server (Migration 167). Ohne die
  /// richtige PIN aendert sich nichts; die PIN gehoert dem Elternteil,
  /// damit kann der Jugendliche die Nutzungszeit nicht selbst verschieben.
  Future<GuardianResult> updateSettingsWithPin({
    required String pin,
    String? notifyFrequency,
    bool? usageLimitEnabled,
    int? usageStartMin,
    int? usageEndMin,
  }) async {
    try {
      final res = await _client.rpc(
        'set_guardian_settings_with_pin',
        params: {
          'p_pin': pin,
          'p_notify_frequency': notifyFrequency,
          'p_usage_limit_enabled': usageLimitEnabled,
          'p_usage_start_min': usageStartMin,
          'p_usage_end_min': usageEndMin,
        },
      );
      final code = res is Map ? res['error'] as String? : null;
      if (code != null) {
        return GuardianResult.failed(code);
      }
      return const GuardianResult.ok();
    } catch (e) {
      return GuardianResult.failed(_codeOf(e), e.toString());
    }
  }

  /// Übersetzt die Fehlermeldung der RPC in einen Code.
  ///
  /// PostgREST liefert die Meldung der Ausnahme im Text. Die Codes
  /// stammen aus den Ausnahmetexten der Migration 165.
  static String? _codeOf(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('not_authenticated')) return 'not_authenticated';
    if (text.contains('not_eligible')) return 'not_eligible';
    if (text.contains('same_email')) return 'same_email';
    if (text.contains('invalid_email')) return 'invalid_email';
    if (text.contains('rate_limited')) return 'rate_limited';
    if (text.contains('invalid_policy')) return 'invalid_policy';
    if (text.contains('invalid_grace')) return 'invalid_grace';
    if (text.contains('no_consent')) return 'no_consent';
    if (text.contains('wrong_pin')) return 'wrong_pin';
    if (text.contains('no_pin')) return 'no_pin';
    if (text.contains('invalid_pin')) return 'invalid_pin';
    return null;
  }
}

/// Fehler beim Lesen des Aufsichtsstands.
///
/// Eigene Klasse, damit der Aufrufer "gescheitert" von "unbekannt"
/// unterscheiden kann: der Elternbereich zeigte sonst bei jedem Fehler
/// einen endlosen Ladekreis (BEFUND 06.11.2026).
class GuardianServiceException implements Exception {
  const GuardianServiceException(this.code, [this.cause]);

  /// Maschinenlesbarer Grund: 'empty_response' | 'timeout' | 'network' |
  /// 'not_authenticated' | 'server'.
  final String code;

  /// Die urspruengliche Ausnahme (fuer das Log).
  final Object? cause;

  @override
  String toString() =>
      'GuardianServiceException($code${cause == null ? '' : ': $cause'})';
}
