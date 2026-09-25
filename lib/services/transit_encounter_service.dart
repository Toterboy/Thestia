import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:thestia/models/transit_models.dart';
import 'package:thestia/services/local_storage.dart';

/// Lokaler Encounter-Cache für Transit Spark (Phase 1).
///
/// Speichert EPHEMERE Tokens anderer Geräte, die per BLE-Advertising in
/// der Nähe (3-10 m) gesichtet wurden. Vorhaltezeit 45 Minuten (die
/// Person darf auch später noch "Blicke getauscht" senden); ältere
/// Einträge werden beim Laden/Zugriff verworfen. Bewusst KLEIN und
/// datensparsam: Nur Token + Zeitstempel, keine Positionsdaten.
class TransitEncounterService {
  TransitEncounterService(this._storage);

  final LocalStorage _storage;
  static const String _key = 'transit_encounters';

  final Map<String, TransitEncounter> _cache = {};

  /// Kryptografisch zufälliges, ephemeres Token (hex, 20 Zeichen = 10 Byte).
  ///
  /// ABSICHTLICH kurz: Das Token geht als BLE-Manufacturer-Payload
  /// ("WST1" + Token) aufs Air - ein Legacy-Advertisement fasst max.
  /// 31 Byte (Flags + Header + Company-ID + Payload = 7 Byte Overhead,
  /// Rest 24). Mit 32-Zeichen-Tokens (früher) scheiterte JEDES Advertising
  /// still mit ADVERTISE_FAILED_DATA_TOO_LARGE ("0 in Reichweite").
  /// 80 Bit Entropie reichen für 45-Minuten-Ephemeren dicke.
  /// Server-Regex ([0-9a-fA-F-]{8,64}) und Cache akzeptieren die Länge.
  static String generateToken() {
    final rnd = Random.secure();
    return List.generate(
      10,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Max. nutzbare BLE-Manufacturer-Payload (31 B Paket - 3 B Flags -
  /// 2 B AD-Header - 2 B Company-ID).
  static const int maxBlePayloadBytes = 24;

  /// Marker im Manufacturer-Feld (muss zum nativen Advertiser und zum
  /// Scanner passen).
  static const String bleMarker = 'WST1';

  /// True, wenn Marker + [token] garantiert in EIN Legacy-Advertisement
  /// passt (sonst DATA_TOO_LARGE und stille Funkstille).
  static bool blePayloadFits(String token) =>
      bleMarker.length + token.length <= maxBlePayloadBytes;

  /// Trägt eine Sichtung ein (dedupe per Token, frischeste Zeit gewinnt).
  void recordEncounter(String token) {
    if (token.length < 8) return;
    _purgeExpired();
    _cache[token] = TransitEncounter(
      token: token,
      seenAt: DateTime.now(),
    );
  }

  /// Frische Encounters sortiert (neueste zuerst) - fuer die
  /// Gruessen-Sektion im Radar (Soft-Ping, v0.9.1).
  List<TransitEncounter> freshList() {
    _purgeExpired();
    final list = _cache.values.where((e) => e.isFresh).toList()
      ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
    return list;
  }

  /// Alle NOCH SICHTBAREN Encounters (2-Stunden-Fenster, v0.9.0):
  /// nach dem Radar-Ende bleibt die Liste zum Nachschauen bestehen;
  /// funkenfähig sind nur die frischen ([freshTokens]).
  List<TransitEncounter> softList() {
    _purgeExpired();
    final list = _cache.values.where((e) => e.isSoftFresh).toList()
      ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
    return list;
  }

  /// Alle frischen Tokens (für den Signal-Versand, max. 100).
  List<String> freshTokens() {
    _purgeExpired();
    return _cache.values.map((e) => e.token).take(100).toList();
  }

  int get count => _cache.length;

  /// Persistenz: kleines JSON (best-effort; Verlust ist unkritisch).
  Future<void> persist() async {
    try {
      final list = _cache.values
          .map((e) => {'t': e.token, 'at': e.seenAt.toIso8601String()})
          .toList();
      await _storage.saveString(_key, jsonEncode(list));
    } catch (e) {
      debugPrint('[TransitEncounter] Persist fehlgeschlagen: $e');
    }
  }

  Future<void> load() async {
    try {
      final raw = await _storage.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final token = map['t'] as String?;
        final at = DateTime.tryParse(map['at'] as String? ?? '');
        if (token == null || at == null) continue;
        _cache[token] = TransitEncounter(token: token, seenAt: at);
      }
      _purgeExpired();
    } catch (e) {
      debugPrint('[TransitEncounter] Laden fehlgeschlagen: $e');
    }
  }

  /// Alles verwerfen (Deaktivierung / Privacy).
  Future<void> clear() async {
    _cache.clear();
    try {
      await _storage.remove(_key);
    } catch (_) {}
  }

  void _purgeExpired() {
    // v0.9.0: 2-Stunden-Sichtbarkeit - erst nach softRetention verwerfen.
    _cache.removeWhere((_, e) => !e.isSoftFresh);
  }
}
