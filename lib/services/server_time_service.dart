import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:thestia/services/supabase_service.dart';

/// Service für Serverzeit-Synchronisation.
///
/// WICHTIG: Alle sicherheitsrelevanten Zeit-/Datumsprüfungen (Dating-Hour-Fenster,
/// Altersberechnung, Jugendschutz) SOLLEN diese Zeitquelle nutzen statt
/// `DateTime.now()`. Die lokale Gerätezeit ist manipulierbar (manuelle Einstellung,
/// falsche Zeitzone, etc.).
///
/// Funktionsweise (ohne Firebase):
/// - Nutzt einen einfachen HTTP-Call an eine vertrauenswürdige Zeit-API,
///   um den Offset zwischen Server- und lokaler Zeit zu ermitteln.
/// - Da wir Firebase entfernt haben, ist der initiale Sync jetzt optional.
/// - Fallback: Wenn keine externe Zeitquelle verfügbar ist, wird die lokale Zeit
///   verwendet. Sicherheitskritische Features sollten in diesem Fall
///   [isVerified] prüfen und ggf. blockieren oder warnen.
///
/// Batterie-Schonung: Der Re-Sync-Timer wird bei App-Pause gestoppt und bei
/// Rückkehr in den Vordergrund neu gestartet.
class ServerTimeService with WidgetsBindingObserver {
  ServerTimeService._() {
    // In Unit-Tests ohne initialisiertes WidgetsBinding würde
    // `WidgetsBinding.instance` werfen - Observer ist dort auch unnötig.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Kein Binding (Unit-Test): Lifecycle-Beobachtung entfällt.
    }
  }

  static final ServerTimeService instance = ServerTimeService._();

  /// Aktueller Offset in Millisekunden (Serverzeit - lokale Zeit).
  int _offsetMs = 0;

  /// Ob der Offset mindestens einmal erfolgreich vom Server geholt wurde.
  bool _hasVerifiedOffset = false;

  /// Timer für regelmäßige Re-Synchronisation.
  Timer? _syncTimer;

  /// Schutz gegen parallele/doppelte Initialisierung.
  bool _initializing = false;

  /// Stream-Controller für Offset-Änderungen (für UI-Reaktionen).
  StreamController<int> _offsetController = StreamController<int>.broadcast();

  /// Stream von Offset-Änderungen.
  Stream<int> get offsetStream => _offsetController.stream;

  /// Ob ein verifizierter Offset vorliegt.
  bool get isVerified => _hasVerifiedOffset;

  /// Aktuelle verifizierte Zeit (Serverzeit = lokale Zeit + Offset).
  DateTime get now => DateTime.now().add(Duration(milliseconds: _offsetMs));

  /// Liefert die verifizierte Serverzeit. Ist noch KEIN verifizierter Offset
  /// vorhanden (z.B. offline beim App-Start), wird die lokale Zeit zurückgegeben,
  /// aber [isVerified] ist dann `false`.
  DateTime getVerifiedNow() => now;

  /// Initialisiert den Service und führt einen ersten Sync durch.
  /// Ist idempotent: mehrfache Aufrufe werden ignoriert, solange ein
  /// Initialisierungslauf läuft.
  Future<void> initialize({Duration syncInterval = const Duration(minutes: 5)}) async {
    if (_initializing) return;
    _initializing = true;
    try {
      // Fallback-Härtung (Zeit-Regression 0.7.2 → Fix 0.7.3): Bis zu 3
      // Sync-Versuche mit Backoff, bis ein verifizierter Offset vorliegt.
      // Schlägt der ERSTE Versuch fehl (z. B. kein Netz beim Start), bleibt
      // die App sonst minutenlang auf der unsicheren Gerätezeit - und die
      // Dating-Hour-Anzeige hängt dann von der Geräte-Zeitzone ab.
      await _syncWithRetry();
      _startSyncTimer(syncInterval);
    } finally {
      _initializing = false;
    }
  }

  void _startSyncTimer(Duration syncInterval) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) => syncNow());
  }

  /// Bis zu 3 Versuche mit Backoff, bis ein verifizierter Offset vorliegt.
  Future<void> _syncWithRetry() async {
    const backoffs = [Duration(seconds: 0), Duration(seconds: 3), Duration(seconds: 8)];
    for (var attempt = 0; attempt < backoffs.length; attempt++) {
      if (backoffs[attempt] > Duration.zero) {
        await Future<void>.delayed(backoffs[attempt]);
      }
      await syncNow();
      if (_hasVerifiedOffset) return;
    }
  }

  /// Führt einen Sync mit der Supabase Edge Function `server-time` durch.
  Future<void> syncNow() async {
    if (!SupabaseService.isInitialized) {
      if (kDebugMode) {
        debugPrint('[ServerTimeService] Supabase nicht initialisiert, Sync übersprungen');
      }
      return;
    }

    try {
      // Timeout gegen hängende Netzwerkaufrufe beim Start (ANR-Vermeidung):
      // ein toter Edge-Function-Endpunkt darf den Sync nie unbegrenzt blockieren.
      final response = await SupabaseService.client.functions
          .invoke('server-time')
          .timeout(const Duration(seconds: 8));

      if (response.data is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint('[ServerTimeService] Unerwartetes Antwortformat');
        }
        return;
      }

      final data = response.data as Map<String, dynamic>;
      final serverIso = data['serverTime'] as String?;
      if (serverIso == null) {
        if (kDebugMode) {
          debugPrint('[ServerTimeService] serverTime fehlt in Antwort');
        }
        return;
      }

      final serverTime = DateTime.tryParse(serverIso)?.toUtc();
      if (serverTime == null) {
        if (kDebugMode) {
          debugPrint('[ServerTimeService] serverTime konnte nicht geparst werden');
        }
        return;
      }

      final localBefore = DateTime.now().toUtc();
      final serverMs = serverTime.millisecondsSinceEpoch;
      final localMs = localBefore.millisecondsSinceEpoch;

      final newOffset = serverMs - localMs;

      if (newOffset.abs() < 24 * 60 * 60 * 1000) {
        _offsetMs = newOffset;
        _hasVerifiedOffset = true;
        _offsetController.add(_offsetMs);
        if (kDebugMode) {
          debugPrint('[ServerTimeService] Offset aktualisiert: ${_offsetMs}ms');
        }
      } else {
        if (kDebugMode) {
          debugPrint('[ServerTimeService] Offset implausibel ($newOffset ms), ignoriere');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ServerTimeService] Sync fehlgeschlagen: $e');
      }
    }
  }

  Future<bool> syncNowWithResult() async {
    final before = _offsetMs;
    await syncNow();
    return _offsetMs != before || _hasVerifiedOffset;
  }

  DateTime corrected(DateTime local) => local.add(Duration(milliseconds: _offsetMs));

  bool isToday(DateTime localDate) {
    final serverNow = now;
    final correctedDate = corrected(localDate);
    return correctedDate.year == serverNow.year &&
        correctedDate.month == serverNow.month &&
        correctedDate.day == serverNow.day;
  }

  /// Test-Hooks: Offset setzen bzw. Service-Zustand zurücksetzen, ohne
  /// einen echten Sync durchzuführen (Singleton zwischen Tests isolieren).
  @visibleForTesting
  void setOffsetForTesting(int offsetMs) {
    if (_offsetController.isClosed) {
      _offsetController = StreamController<int>.broadcast();
    }
    _offsetMs = offsetMs;
    _hasVerifiedOffset = true;
    _offsetController.add(_offsetMs);
  }

  @visibleForTesting
  void resetForTesting() {
    _offsetMs = 0;
    _hasVerifiedOffset = false;
    _syncTimer?.cancel();
    _syncTimer = null;
    if (_offsetController.isClosed) {
      _offsetController = StreamController<int>.broadcast();
    }
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Unit-Test ohne Binding.
    }
    _syncTimer?.cancel();
    _offsetController.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kein Netzverkehr im Hintergrund: Timer pausieren, bei Rückkehr in den
    // Vordergrund sofort synchronisieren (mit Retry, falls der erste Versuch
    // ins Leere geht) und den Timer neu starten.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _syncTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_syncWithRetry());
      _startSyncTimer(const Duration(minutes: 5));
    }
  }
}
