import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:thestia/models/transit_models.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/utils/best_effort.dart';

/// Lokaler Encounter-Cache für Transit Spark (Phase 1).
///
/// Speichert EPHEMERE Tokens anderer Geräte, die per BLE-Advertising in
/// der Nähe (3-10 m) gesichtet wurden. Vorhaltezeit 45 Minuten (die
/// Person darf auch später noch "Blicke getauscht" senden); ältere
/// Einträge werden beim Laden/Zugriff verworfen. Bewusst KLEIN und
/// datensparsam: Nur Token + Zeitstempel, keine Positionsdaten.
class TransitEncounterService {
  TransitEncounterService([LocalStorage? storage])
    // SECURITY (Audit 2026-09-26): Default ist jetzt der Keystore.
    //
    // Vorher bekam der Service `localStorageProvider`, im Betrieb also
    // SharedPreferences = Klartext. Der Cache enthaelt BEGEHNACHWEISE
    // (welche Geraete waren per BLE in Funkreichweite, wann) - das ist
    // ein Ortungsdatum (DSGVO Art. 9), kein "nur ein Token". Die
    // restlichen Art.-9-Preferenzen liegen bereits im Keystore
    // (user_preferences_provider.dart:374), dieser Store war die
    // Ausnahme.
    : _storage = storage ?? SecurePreferencesStorage();

  final LocalStorage _storage;
  static const String _key = 'transit_encounters';

  final Map<String, TransitEncounter> _cache = {};

  /// Kryptografisch zufälliges, ephemeres Token (hex, 20 Zeichen = 10 Byte).
  ///
  /// ACHTUNG: Die Laenge ist Teil des Protokolls. Der Scanner erkennt
  /// ein Token nur, wenn es exakt [tokenLaenge] Hexzeichen hat - und
  /// sonst nichts. Das ist Absicht (BEFUND 06.11.2026): die alte
  /// Pruefung ("irgendetwas nach dem Marker") hat auf Android 16 jedes
  /// fremde Bluetooth-Geraet als Thestia-Geraet gezaehlt - die Anzeige
  /// "X Thestia-Geräte in Reichweite" zeigte ueber 100 Geraete, obwohl
  /// hoechstens eines in der Naehe war.
  ///
  /// Das Token geht als BLE-Manufacturer-Payload ("WST1" + Token) aufs
  /// Air - ein Legacy-Advertisement fasst max. 31 Byte (Flags + Header +
  /// Company-ID + Payload = 7 Byte Overhead, Rest 24). Mit 32-Zeichen-
  /// Tokens (frueher) scheiterte JEDES Advertising still mit
  /// ADVERTISE_FAILED_DATA_TOO_LARGE ("0 in Reichweite"). 80 Bit
  /// Entropie reichen fuer 45-Minuten-Ephemeren dicke.
  /// Server-Regex ([0-9a-fA-F-]{8,64}) und Cache akzeptieren die Laenge.
  static String generateToken() {
    final rnd = Random.secure();
    return List.generate(
      10,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Laenge des Tokens in Zeichen (10 Byte = 20 Hexzeichen).
  static const int tokenLaenge = 20;

  /// Ist [token] ein wohlgeformtes Thestia-Token?
  ///
  /// Genau [tokenLaenge] Hexzeichen, sonst nichts. Ein echtes Token
  /// kann nicht von einem fremden Bluetooth-Geraet erzeugt werden -
  /// der Zufallsanteil macht eine Verwechslung praktisch unmoeglich.
  static bool isValidToken(String token) {
    if (token.length != tokenLaenge) return false;
    for (var i = 0; i < token.length; i++) {
      final c = token.codeUnitAt(i);
      final istHex =
          (c >= 0x30 && c <= 0x39) || // 0-9
          (c >= 0x41 && c <= 0x46) || // A-F
          (c >= 0x61 && c <= 0x66); // a-f
      if (!istHex) return false;
    }
    return true;
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
    // Nur echte Tokens zaehlen (BEFUND 06.11.2026): der Cache landet
    // in der Anzeige "X Thestia-Geräte in Reichweite" UND wird beim
    // Senden als Token-Liste an den Server geschickt. Unbekannte Werte
    // haben dort keine Entsprechung.
    if (!isValidToken(token)) return;
    _purgeExpired();
    _cache[token] = TransitEncounter(token: token, seenAt: DateTime.now());
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

  /// Alle bekannten Begegnungen (inklusive der abgelaufenen - die
  /// werden beim Zugriff aussortiert).
  int get count => _cache.length;

  /// Die Begegnungen, die noch zaehlen - also die FRISCHEN (45
  /// Minuten). Das ist genau das Fenster, in dem der Server sie noch
  /// zuordnen kann.
  ///
  /// BEFUND (06.11.2026, Betreiber): "Es werden immer mehr (aktuell
  /// ueber 100 gefunden)." Der Zaehler nahm alle Eintraege (zwei
  /// Stunden) und nannte sie "Geraete" - dabei liefert ein einziges
  /// Geraet mehrere Signale, weil sein Token alle 6-14 Minuten
  /// wechselt.
  int get freshCount {
    _purgeExpired();
    return _cache.values.where((e) => e.isFresh).length;
  }

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
    await bestEffort('remove', () async {
      await _storage.remove(_key);
    });
  }

  void _purgeExpired() {
    // v0.9.0: 2-Stunden-Sichtbarkeit - erst nach softRetention verwerfen.
    _cache.removeWhere((_, e) => !e.isSoftFresh);
  }
}
