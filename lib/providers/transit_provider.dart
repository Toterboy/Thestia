import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/transit_models.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/transit_ble_service.dart';
import 'package:wisp/services/transit_encounter_service.dart';

/// Transit-Aktivitätsdauer (Session-Fenster).
const Duration kTransitSessionDuration = Duration(minutes: 45);

/// Zustand des Transit-Radars (v0.9.0).
class TransitState {
  const TransitState({
    this.active = false,
    this.mode = TransitMode.transit,
    this.endsAt,
    this.encounterCount = 0,
    this.busy = false,
    this.lastResult,
    this.selfTags = const [],
    this.selfNote = '',
    this.lastError,
  });

  /// Taegliche Selbst-Angaben (v0.9.0): 1-3 Merkmale zu sich selbst,
  /// werden mit jedem Signal mitgeschickt - andere finden dich darueber.
  final List<String> selfTags;

  /// Freie Ergänzung zur Selbstbeschreibung (v0.9.1, max. 140 Zeichen).
  final String selfNote;

  final bool active;

  /// Bahn/Café vs. Messe/Event (steuert die RSSI-Schärfe clientseitig).
  final TransitMode mode;

  /// Wann die Session endet (Auto-Stop + Countdown-Anzeige).
  final DateTime? endsAt;

  final int encounterCount;
  final bool busy;

  /// Ergebnis des letzten "Blicke getauscht"-Versands.
  final TransitSparkResult? lastResult;

  /// Fehlerursache des letzten Signal-Versands (Snackbar-Diagnose).
  final String? lastError;

  TransitState copyWith({
    bool? active,
    TransitMode? mode,
    DateTime? endsAt,
    int? encounterCount,
    bool? busy,
    TransitSparkResult? lastResult,
    bool clearResult = false,
    List<String>? selfTags,
    String? selfNote,
    String? lastError,
  }) {
    return TransitState(
      active: active ?? this.active,
      mode: mode ?? this.mode,
      endsAt: endsAt ?? this.endsAt,
      encounterCount: encounterCount ?? this.encounterCount,
      busy: busy ?? this.busy,
      lastResult:
          clearResult ? null : (lastResult ?? this.lastResult),
      selfTags: selfTags ?? this.selfTags,
      selfNote: selfNote ?? this.selfNote,
      lastError: lastError,
    );
  }
}

/// Provider für Transit Spark: aktiviert BLE (Advertising + Scanning),
/// rotiert Tokens, hält den Encounter-Cache warm und sendet Signale
/// mit 1-3 Merkmal-Tags.
class TransitNotifier extends StateNotifier<TransitState> {
  TransitNotifier(this._storage) : super(const TransitState()) {
    _encounters.load();
  }

  final LocalStorage _storage;

  TransitEncounterService? _encountersField;
  TransitEncounterService get _encounters =>
      _encountersField ??= TransitEncounterService(_storage);

  Timer? _countdownTimer;
  Timer? _rotateTimer;
  Timer? _persistTimer;

  void _recordEncounter(String token, int rssi) {
    // Messe-Modus (v0.9.0): nur starke Signale = echter Sichtkontakt
    // (dichte BLE-Umgebungen fluten sonst den Cache).
    if (state.mode.rssiThreshold > rssi) return;
    _encounters.recordEncounter(token);
    state = state.copyWith(encounterCount: _encounters.count);
    // Persist entprellt (nicht bei jedem Treffer schreiben).
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 5), () {
      _encounters.persist();
    });
  }

  /// Modus setzen (nur bei inaktivem Radar umschaltbar).
  void setMode(TransitMode mode) {
    if (!state.active) state = state.copyWith(mode: mode);
  }

  /// Taegliche Selbst-Angaben setzen (v0.9.0, beim Radar-Start).
  void setSelfTags(List<String> tags) {
    state = state.copyWith(selfTags: tags);
  }

  /// Freie Ergänzung zur Selbstbeschreibung setzen (v0.9.1).
  void setSelfNote(String note) {
    state = state.copyWith(selfNote: note.trim());
  }

  /// Aktiviert das Radar (BLE + Cache). Gibt false zurück, wenn BLE
  /// nicht starten konnte (z. B. Bluetooth aus / Berechtigung fehlt).
  Future<bool> activate() async {
    if (state.active) return true;
    final token = TransitEncounterService.generateToken();
    final ok = await TransitBleService.instance.start(
      token: token,
      onEncounter: _recordEncounter,
    );
    if (!ok) return false;

    final endsAt = DateTime.now().add(kTransitSessionDuration);
    state = state.copyWith(active: true, endsAt: endsAt);

    // Presence-Heartbeat (v0.9.1 Soft-Ping): Das aktuelle Token wird
    // serverseitig hinterlegt (TTL 45 min, Auto-Purge) - NUR so kann
    // ein nachtraeglicher Gruß die Person ueberhaupt erreichen. Im
    // Privacy-Hinweis des Radars transparent genannt.
    if (SupabaseService.isInitialized) {
      unawaited(() async {
        try {
          await SupabaseDatabaseService(SupabaseService.client)
              .transitPresenceHeartbeat(token);
        } catch (e) {
          debugPrint('[Transit] Presence-Heartbeat fehlgeschlagen: ');
        }
      }());
    }

    // Token-Rotation alle 10 Minuten (ephemere Tokens).
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      if (!state.active) return;
      final newToken = TransitEncounterService.generateToken();
      await TransitBleService.instance.rotateToken(
        newToken: newToken,
        onEncounter: _recordEncounter,
      );
      if (SupabaseService.isInitialized) {
        try {
          await SupabaseDatabaseService(SupabaseService.client)
              .transitPresenceHeartbeat(newToken);
        } catch (_) {}
      }
    });

    // Countdown/Ende-Überwachung.
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.active) return;
      final endsAt = state.endsAt;
      if (endsAt != null && DateTime.now().isAfter(endsAt)) {
        deactivate();
      }
    });

    return true;
  }

  /// Deaktiviert Radar + räumt serverseitig die Präsenz ab (Privacy).
  ///
  /// v0.9.0-Nutzerwunsch: Die lokal gesehene Personen-Liste bleibt
  /// NOCH 2 STUNDEN bestehen ( zum Nachschauen/Anschreiben in Ruhe) -
  /// die Tokens sind ephemere Zufallswerte ohne Positionsdaten und
  /// verfallen lokael; die eigenen PRESENCE-Tokens werden weiterhin
  /// sofort entfernt (Radar aus = nicht mehr adressierbar).
  Future<void> deactivate() async {
    _rotateTimer?.cancel();
    _countdownTimer?.cancel();
    _persistTimer?.cancel();
    await TransitBleService.instance.stop();
    // Presence-Token entfernen (Privacy - Radar aus = nicht mehr
    // adressierbar).
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseDatabaseService(SupabaseService.client)
            .transitPresenceLeave();
      } catch (e) {
        debugPrint('[Transit] Presence-Leave fehlgeschlagen: ');
      }
    }
    await _encounters.persist();
    // FIX "Button verschwindet / Ansicht wie davor": Ein blanker Reset
    // warf auch Selbstbeschreibung und Encounter-Stand weg - der
    // "Gesehene Geräte"-Button und die Ergänzungs-Karte verschwanden
    // plötzlich. Jetzt: nur das AKTIVE Radar zurücksetzen, alles andere
    // (Selbst-Tags, Notiz, Encounter-Anzeige) bleibt bestehen.
    state = state.copyWith(
      active: false,
      endsAt: null,
      encounterCount: _encounters.count,
      busy: false,
      clearResult: true,
    );
  }

  /// Liste der NOCH SICHTBAREN Encounters (2-Stunden-Fenster, v0.9.0)
  /// fuer die Gruessen-Sektion im Radar.
  List<TransitEncounter> softEncounters() => _encounters.softList();

  /// True, wenn gesehene Personen noch in der 2-Stunden-Ruhezeit sind.
  bool get hasSoftEncounters => _encounters.softList().isNotEmpty;

  /// Countdown der Rest-Sichtbarkeit (2 h Fenster) für die Liste; null,
  /// wenn nichts mehr sichtbar ist.
  DateTime? softUntil() {
    final list = _encounters.softList();
    if (list.isEmpty) return null;
    var latest = list.first.seenAt;
    for (final e in list) {
      if (e.seenAt.isAfter(latest)) latest = e.seenAt;
    }
    return latest.add(TransitEncounter.softRetention);
  }

  /// Soft-Ping an ein Encounter-Token senden (1x pro Token, 48 h).
  Future<bool> sendSoftPing({
    required String token,
    required String messageKey,
    String? customLine,
  }) async {
    try {
      if (!SupabaseService.isInitialized) return false;
      await SupabaseDatabaseService(SupabaseService.client).sendSoftPing(
        token: token,
        messageKey: messageKey,
        customLine: customLine,
      );
      return true;
    } catch (e) {
      debugPrint('[Transit] sendSoftPing fehlgeschlagen: ');
      return false;
    }
  }

  /// "Blicke getauscht": frische Encounter-Tokens + 1-3 Merkmal-Tags
  /// an den Server senden. Match = beidseitiges Signal MIT gemeinsamen
  /// Merkmalen -> Bestandspipeline (Likes -> Match -> Push) erzeugt den
  /// Funke. Ohne Gegensignal wird das eigene Signal 45 Minuten
  /// vorgehalten.
  Future<TransitSparkResult?> sendSpark(List<String> tags) async {
    if (!state.active || state.busy) return null;
    state = state.copyWith(busy: true, clearResult: true);
    try {
      final tokens = _encounters.freshTokens();
      final res = await SupabaseDatabaseService(SupabaseService.client)
          .matchProximitySpark(
        tokens: tokens,
        tags: tags,
        mode: state.mode.value,
        selfTags: state.selfTags,
        selfNote: state.selfNote.isEmpty ? null : state.selfNote,
      );
      final result = TransitSparkResult.fromJson(res);
      state = state.copyWith(busy: false, lastResult: result, lastError: null);
      return result;
    } catch (e) {
      debugPrint('[Transit] sendSpark fehlgeschlagen: $e');
      state = state.copyWith(busy: false, lastError: _shortError(e));
      return null;
    }
  }

  String _shortError(Object e) {
    var t = e.toString();
    t = t.replaceFirst('AppException: ', '').replaceFirst('Exception: ', '');
    if (t.length > 160) t = t.substring(0, 160);
    return t;
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _countdownTimer?.cancel();
    _persistTimer?.cancel();
    TransitBleService.instance.stop();
    super.dispose();
  }
}

/// Provider für Transit Spark.
final transitProvider =
    StateNotifierProvider<TransitNotifier, TransitState>((ref) {
  return TransitNotifier(ref.read(localStorageProvider));
});
