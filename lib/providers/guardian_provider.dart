import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/guardian_status.dart';
import 'package:thestia/providers/auth_provider.dart';
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
    // BEFUND (06.11.2026, Betreiber): "Der Elternbereich laedt ewig
    // lang." Ursache: Dieser Provider wird beim App-Start erzeugt (der
    // UsageTimeGate schaut ihn an) - zu einem Zeitpunkt, zu dem die
    // Sitzung noch nicht wiederhergestellt sein muss. Der RPC antwortet
    // dann "not_authenticated", das Ergebnis war "unbekannt", und
    // NIEMAND hat je wieder nachgesehen: der Ladekreis drehte bis zum
    // Ende des Lebens.
    //
    // Deshalb: Bei jeder Anmeldung wird neu geladen. Das ist genau der
    // Zeitpunkt, an dem der Stand gebraucht wird.
    _ref.listen<AsyncValue<bool>>(authProvider, (prev, next) {
      // Nur beim UEBERGANG zu "angemeldet" neu laden. Sonst wuerde
      // jedes Token-Refresh (stuendlich) einen Serveraufruf ausloesen.
      final jetztAngemeldet = next.valueOrNull ?? false;
      final vorherAngemeldet = prev?.valueOrNull ?? false;
      if (jetztAngemeldet && !vorherAngemeldet) {
        unawaited(load());
      }
    });
  }

  final Ref _ref;

  GuardianService get _service => _ref.read(guardianServiceProvider);

  /// Wie oft wurde erfolglos neu versucht (fuer die Diagnose).
  int _versuche = 0;

  /// Der geplante Wiederholungsversuch (null = keiner).
  Timer? _wiederholung;

  /// Die Wartezeiten zwischen den Wiederholungen.
  ///
  /// Kurz am Anfang (die Sitzung ist oft schon da), dann gestreckt.
  static const List<Duration> _wartezeiten = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 12),
    Duration(seconds: 30),
  ];

  /// Laedt den Stand vom Server.
  ///
  /// Supabase kann noch nicht initialisiert sein (App-Start, Testlauf).
  /// Der Stand bleibt dann "unbekannt" - nicht "keine Aufsicht". Ein
  /// Fehler darf hier niemals nach aussen schlagen: ein unbehandelter
  /// Fehler im Provider wuerde den ganzen Bildschirm mitreissen.
  ///
  /// Schlaegt der Abruf fehl, wird es mit wachsender Wartezeit erneut
  /// versucht - und der Zustand traegt den Fehler, damit der
  /// Bildschirm einen Ausweg anbietet (erneut versuchen) statt ewig zu
  /// drehen.
  Future<void> load() async {
    _wiederholung?.cancel();
    _wiederholung = null;
    GuardianStatus status;
    try {
      // Der Dienst prueft selbst, ob Supabase bereit ist (und wirft
      // dann "not_ready") - so bleibt der Fehlerpfad testbar.
      status = await _service.fetchStatus();
      _versuche = 0;
    } catch (e) {
      debugPrint('[Guardian] Stand nicht ladbar: $e');
      status = GuardianStatus(loadError: _codeOf(e));
      _planeWiederholung();
    }
    if (!mounted) return;
    state = status;
  }

  /// Plant den naechsten Versuch (nach einem Fehler).
  void _planeWiederholung() {
    _wiederholung?.cancel();
    if (_versuche >= _wartezeiten.length) return;
    final wartezeit = _wartezeiten[_versuche];
    _versuche++;
    _wiederholung = Timer(wartezeit, () {
      if (!mounted) return;
      unawaited(load());
    });
  }

  /// Der Fehlercode des letzten gescheiterten Abrufs.
  static String _codeOf(Object e) {
    if (e is GuardianServiceException) return e.code;
    final text = e.toString().toLowerCase();
    if (text.contains('not_authenticated')) return 'not_authenticated';
    if (text.contains('timeout')) return 'timeout';
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'network';
    }
    return 'server';
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

  @override
  void dispose() {
    // Der Timer muss weg, wenn der Provider endet - sonst weckt er den
    // Prozess weiter, obwohl niemand mehr zuhört. (Der Widget-Test
    // "A Timer is still pending even after the widget tree was disposed"
    // hat das gefunden.)
    _wiederholung?.cancel();
    _wiederholung = null;
    super.dispose();
  }
}

/// Der Stand der elterlichen Aufsicht.
final guardianProvider =
    StateNotifierProvider<GuardianNotifier, GuardianStatus>((ref) {
      return GuardianNotifier(ref);
    });
