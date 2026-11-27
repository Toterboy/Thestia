import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/services/dating_hour/sync_date_service.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Verwaltet das Sync-Date eines einzelnen Matches.
class SyncDateNotifier extends StateNotifier<SyncDate?> {
  SyncDateNotifier(this._service, this._matchId) : super(null) {
    _load();
  }

  final SyncDateService _service;
  final String _matchId;

  Future<void> _load() async {
    // still null -> die UI zeigt nichts an.
    await bestEffort('syncDateService.get', () async {
      final value = await _service.get(_matchId);
      // Family-Elemente werden beim Routenwechsel disposed, während der
      // Server-Call noch läuft -> State-Zuweisung wäre ein Crash.
      if (mounted) state = value;
    });
  }

  /// Lädt den aktuellen Stand neu vom Server.
  Future<void> reload() => _load();

  /// Schlägt ein Date vor.
  Future<void> propose({
    required SyncDateIdee idee,
    required DateTime startAt,
  }) async {
    final updated = await _service.propose(
      _matchId,
      idee: idee,
      startAt: startAt,
    );
    if (updated != null && mounted) state = updated;
  }

  /// Nimmt das Date an.
  Future<void> accept() async {
    final updated = await _service.accept(_matchId);
    if (updated != null && mounted) state = updated;
  }

  /// Sagt das Date ab.
  Future<void> decline() async {
    await _service.decline(_matchId);
    if (mounted) state = null;
  }
}

/// Der Chat, der gerade gesperrt ist (während eines laufenden Dates).
///
/// DER WEG (Betreiber, 27.11.2026): "Es darf nur dieser Chat während des
/// Dates in der App genutzt werden (also alle anderen Chats und Modi
/// sind nicht verfügbar, bis das Date zu Ende ist - sowas wie
/// Einstellungen soll aber gehen)."
///
/// Der Wert ist die Match-ID des laufenden Dates. `null` heißt: es
/// läuft kein Date, die App ist frei. Der Router schaut hier hinein
/// und leitet jeden anderen Weg um (siehe `umleitung` in app_router.dart).
final syncDateSperreProvider = StateProvider<String?>((ref) => null);

/// Provider (Family) für das Sync-Date eines Matches.
final syncDateProvider =
    StateNotifierProvider.family<SyncDateNotifier, SyncDate?, String>((
      ref,
      matchId,
    ) {
      return SyncDateNotifier(ref.watch(syncDateServiceProvider), matchId);
    });
