import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/services/guardian_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Der Service fuer die elterliche Freigabe.
final guardianServiceProvider = Provider<GuardianService>((ref) {
  return GuardianService(SupabaseService.client);
});

/// Haelt den Stand der elterlichen Aufsicht.
///
/// Der Server entscheidet; dieser Provider laedt, schreibt und meldet
/// weiter. Wichtig: Der Anfangszustand ist [GuardianStatus.unknown] -
/// "unbekannt" ist nicht "keine Aufsicht".
class GuardianNotifier extends StateNotifier<GuardianStatus> {
  GuardianNotifier(this._ref) : super(GuardianStatus.unknown) {
    unawaited(load());
  }

  final Ref _ref;

  GuardianService get _service => _ref.read(guardianServiceProvider);

  /// Laedt den Stand vom Server.
  ///
  /// Supabase kann noch nicht initialisiert sein (App-Start, Testlauf).
  /// Der Stand bleibt dann "unbekannt" - nicht "keine Aufsicht". Ein
  /// Fehler darf hier niemals nach aussen schlagen: ein unbehandelter
  /// Fehler im Provider wuerde den ganzen Bildschirm mitreissen.
  Future<void> load() async {
    GuardianStatus status;
    try {
      if (!SupabaseService.isInitialized) {
        status = GuardianStatus.unknown;
      } else {
        status = await _service.fetchStatus();
      }
    } catch (e) {
      debugPrint('[Guardian] Stand nicht ladbar: $e');
      status = GuardianStatus.unknown;
    }
    if (!mounted) return;
    state = status;
  }

  /// Fordert die Freigabe eines Elternteils an.
  Future<GuardianResult> requestConsent(String guardianEmail) async {
    final result = await _service.requestConsent(guardianEmail);
    if (result.isOk) {
      await load();
    }
    return result;
  }

  /// Beendet die Freigabe.
  Future<GuardianResult> revoke() async {
    final result = await _service.revoke();
    if (result.isOk) {
      await load();
    }
    return result;
  }

  /// Die Entscheidung mit 18.
  Future<GuardianResult> setAccessPolicy(
    String policy, {
    int? graceMonths,
  }) async {
    final result = await _service.setAccessPolicy(
      policy,
      graceMonths: graceMonths,
    );
    if (result.isOk) {
      await load();
    }
    return result;
  }

  /// Prueft die PIN (serverseitig).
  Future<bool> verifyPin(String pin) => _service.verifyPin(pin);

  /// Aendert die Einstellungen der Aufsicht - nur mit der PIN.
  ///
  /// Der PIN-Vergleich laeuft auf dem Server (Migration 167). Ohne die
  /// richtige PIN aendert sich nichts.
  Future<GuardianResult> updateSettingsWithPin({
    required String pin,
    String? notifyFrequency,
    bool? usageLimitEnabled,
    int? usageStartMin,
    int? usageEndMin,
  }) async {
    final result = await _service.updateSettingsWithPin(
      pin: pin,
      notifyFrequency: notifyFrequency,
      usageLimitEnabled: usageLimitEnabled,
      usageStartMin: usageStartMin,
      usageEndMin: usageEndMin,
    );
    if (result.isOk) {
      await load();
    }
    return result;
  }

  /// Markiert den Uebergang als erledigt.
  Future<void> markTransitionDone() async {
    await _service.markTransitionDone();
    await load();
  }
}

/// Der Stand der elterlichen Aufsicht.
final guardianProvider =
    StateNotifierProvider<GuardianNotifier, GuardianStatus>((ref) {
      return GuardianNotifier(ref);
    });
