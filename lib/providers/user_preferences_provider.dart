import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/models/gender.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Filter-Modus für die Entfernungs-Suche.
enum DistanceFilterMode {
  /// Entfernung in Kilometern (Slider).
  distanceKm,

  /// Bundesland (Dropdown).
  state,

  /// Ganz Deutschland (keine geografische Einschränkung).
  germany,
}

extension DistanceFilterModeLabel on DistanceFilterMode {
  String get label {
    switch (this) {
      case DistanceFilterMode.distanceKm:
        return 'Entfernung (km)';
      case DistanceFilterMode.state:
        return 'Bundesland';
      case DistanceFilterMode.germany:
        return 'Ganz Deutschland';
    }
  }
}

/// Nutzer-Präferenzen für Filter und Suche.
class UserPreferences {
  const UserPreferences({
    required this.genderPreferences,
    required this.distanceFilterMode,
    required this.maxDistanceKm,
    required this.preferredState,
    this.location,
    this.relationshipType,
  });

  /// Mehrfachauswahl der Geschlechts-Präferenz (Werte aus [Gender.value]).
  ///
  /// Alle sechs Geschlechter = funktional identisch mit der "Alle"-Option.
  /// Es ist immer mindestens ein Eintrag enthalten (UI verhindert Leermenge).
  final List<String> genderPreferences;
  final DistanceFilterMode distanceFilterMode;
  final int maxDistanceKm;
  final String? preferredState;
  final String? location;
  final RelationshipType? relationshipType;

  /// Erzeugt eine Kopie mit geänderten Feldern.
  UserPreferences copyWith({
    List<String>? genderPreferences,
    DistanceFilterMode? distanceFilterMode,
    int? maxDistanceKm,
    String? preferredState,
    String? location,
    RelationshipType? relationshipType,
    bool clearLocation = false,
  }) {
    return UserPreferences(
      genderPreferences: genderPreferences ?? this.genderPreferences,
      distanceFilterMode: distanceFilterMode ?? this.distanceFilterMode,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      preferredState: preferredState ?? this.preferredState,
      location: clearLocation ? null : (location ?? this.location),
      relationshipType: relationshipType ?? this.relationshipType,
    );
  }

  /// Serialisierung zu JSON.
  Map<String, dynamic> toJson() => {
        'genderPreferences': genderPreferences,
        'distanceFilterMode': distanceFilterMode.name,
        'maxDistanceKm': maxDistanceKm,
        'preferredState': preferredState,
        'location': location,
        'relationshipType': relationshipType?.value,
      };

  /// Deserialisierung aus JSON.
  ///
  /// Migriert das alte Format (einzelner String 'genderPreference')
  /// automatisch in die neue Liste: 'all'/leer -> alle Geschlechter,
  /// einzelner Wert -> Liste mit einem Eintrag.
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      genderPreferences: _parseGenderPreferences(json),
      distanceFilterMode: DistanceFilterMode.values.byName(
        json['distanceFilterMode'] as String? ?? 'distanceKm',
      ),
      maxDistanceKm: json['maxDistanceKm'] as int? ?? 100,
      preferredState: json['preferredState'] as String?,
      location: json['location'] as String?,
      relationshipType: RelationshipType.values.byName(
        json['relationshipType'] as String? ?? 'open',
      ),
    );
  }

  static List<String> _parseGenderPreferences(Map<String, dynamic> json) {
    final raw = json['genderPreferences'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    // Legacy-Format: einzelner String.
    final legacy = json['genderPreference'] as String?;
    if (legacy == null || legacy.isEmpty || legacy == 'all') {
      return List.of(kAllGenderValues);
    }
    return [legacy];
  }

  /// Standardwerte: KEINE Geschlechts-Präferenz ausgewählt
  /// (leer = kein Filter; "Alle" ist eine explizite, abwählbare Auswahl).
  factory UserPreferences.defaults() => const UserPreferences(
        genderPreferences: [],
        distanceFilterMode: DistanceFilterMode.distanceKm,
        maxDistanceKm: 100,
        preferredState: null,
        location: null,
        relationshipType: RelationshipType.open,
      );
}

/// StateNotifier für Nutzerpräferenzen.
///
/// Audit M-16: Die Präferenzen enthalten Art.-9-nahe Daten
/// (Gender-/Beziehungsvorlieben) und einen Standort-String - sie werden
/// deshalb im Keystore/Keychain ([SecurePreferencesStorage]) statt im
/// Klartext-[SharedPreferences] gespeichert. Bestehende Klartext-Einträge
/// werden beim Laden migriert und entfernt.
class UserPreferencesNotifier extends StateNotifier<UserPreferences> {
  UserPreferencesNotifier(this._storage, this._legacyRawPrefs)
      : super(UserPreferences.defaults()) {
    _load();
  }

  final LocalStorage _storage;

  /// Zugrundeliegende Klartext-Preferences (nur für die Einmal-Migration;
  /// darf NULL sein).
  final SharedPreferences? _legacyRawPrefs;

  static const _prefsKey = 'user_preferences';

  /// Debounce-Timer für den automatischen Präferenz-Sync: Regler feuern
  /// beim Ziehen kontinuierlich - erst wenn 1,5 s Ruhe ist, geht EIN
  /// Schreibvorgang an den Server ("Suchradius gespeichert wie der Name",
  /// auch ohne Speichern-Knopf).
  Timer? _serverSyncDebounce;

  /// Plant den serverseitigen Präferenz-Sync (entprellt). Optionale
  /// [ageRangeMin]/[ageRangeMax] werden mitgeschickt, wenn der Aufrufer
  /// (z. B. Altersspannen-Regler) gerade auch die Spanne geändert hat.
  void queueServerSync({int? ageRangeMin, int? ageRangeMax}) {
    _serverSyncDebounce?.cancel();
    _serverSyncDebounce = Timer(const Duration(milliseconds: 1500), () {
      unawaited(savePreferencesToServer(
        ageRangeMin: ageRangeMin,
        ageRangeMax: ageRangeMax,
      ));
    });
  }

  Future<void> _load() async {
    // Migration: alten Klartext-Eintrag in den sicheren Speicher übernehmen.
    final storage = _storage;
    final legacyPrefs = _legacyRawPrefs;
    if (storage is SecurePreferencesStorage && legacyPrefs != null) {
      try {
        await storage.migrateStringFrom(legacyPrefs, _prefsKey);
      } catch (_) {
        // Migration ist Best-Effort.
      }
    }
    final raw = await _storage.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = UserPreferences.fromJson(map);
      } catch (_) {
        // Bei korrupten Daten: Defaults beibehalten.
      }
      return;
    }
    // Fallback: alter Stand (falls die Migration noch nicht lief).
    final legacyRaw = _legacyRawPrefs?.getString(_prefsKey);
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        state =
            UserPreferences.fromJson(jsonDecode(legacyRaw) as Map<String, dynamic>);
        await _persist(); // Sofort im sicheren Speicher ablegen.
        await _legacyRawPrefs?.remove(_prefsKey);
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    await _storage.saveString(_prefsKey, jsonEncode(state.toJson()));
  }

  /// Setzt die komplette Präferenz-Liste (auch leer = kein Filter).
  Future<void> setGenderPreferences(List<String> values) async {
    state = state.copyWith(genderPreferences: values);
    await _persist();
    queueServerSync();
  }

  /// Schaltet ein einzelnes Geschlecht um.
  ///
  /// Eine LEERE Auswahl ist erlaubt (kein Filter); es gibt kein
  /// Mindest-Eins-Mehr.
  Future<void> toggleGenderPreference(String value) async {
    final current = List<String>.from(state.genderPreferences);
    if (current.contains(value)) {
      current.remove(value);
    } else {
      current.add(value);
    }
    state = state.copyWith(genderPreferences: current);
    await _persist();
  }

  /// "Alle"-Kurzform: alle Geschlechter aktivieren.
  Future<void> selectAllGenders() async {
    state = state.copyWith(genderPreferences: List.of(kAllGenderValues));
    await _persist();
  }

  /// Hebt die Auswahl komplett auf (nichts ausgewählt = kein Filter).
  Future<void> clearGenders() async {
    state = state.copyWith(genderPreferences: const []);
    await _persist();
  }

  /// Setzt alle Präferenzen auf die Standardwerte zurück
  /// (z. B. nach Account-Löschung).
  Future<void> resetToDefaults() async {
    state = UserPreferences.defaults();
    await _persist();
  }

  Future<void> setDistanceFilterMode(DistanceFilterMode mode) async {
    state = state.copyWith(distanceFilterMode: mode);
    await _persist();
    queueServerSync();
  }

  Future<void> setMaxDistanceKm(int km) async {
    state = state.copyWith(maxDistanceKm: km);
    await _persist();
    // Suchradius sofort (entprellt) serverseitig sichern - der Nutzer
    // erwartet, dass die Entfernung wie der Name dauerhaft gespeichert
    // wird.
    queueServerSync();
  }

  Future<void> setPreferredState(String? stateCode) async {
    state = state.copyWith(preferredState: stateCode);
    await _persist();
    queueServerSync();
  }

  Future<void> setLocation(String? location) async {
    state = state.copyWith(location: location);
    await _persist();
    queueServerSync();
  }

  Future<void> setRelationshipType(RelationshipType? type) async {
    state = state.copyWith(relationshipType: type);
    await _persist();
    queueServerSync();
  }

  /// Übernimmt Präferenzen aus dem Server-Profil (nach Login/Neuinstallation).
  ///
  /// "Nichts geht verloren"-Garantie: Entfernung, "Ich suche", Bundesland,
  /// Ort und Geschlechts-Filter stehen serverseitig in profiles (Migration
  /// 066) und werden hier in den lokalen Stand übernommen. Fehlende/null
  /// Werte lassen den bisherigen lokalen Stand unangetastet.
  Future<void> applyServerValues(Map<String, dynamic> p) async {
    RelationshipType? relationshipType = state.relationshipType;
    final rtRaw = p['relationship_type'] as String?;
    if (rtRaw != null && rtRaw.isNotEmpty) {
      for (final t in RelationshipType.values) {
        if (t.value == rtRaw) relationshipType = t;
      }
    }
    final city = (p['city'] as String? ?? '').trim();
    var filterMode = state.distanceFilterMode;
    final fmRaw = p['distance_filter_mode'] as String?;
    if (fmRaw != null && fmRaw.isNotEmpty) {
      for (final m in DistanceFilterMode.values) {
        if (m.name == fmRaw) filterMode = m;
      }
    }
    state = state.copyWith(
      distanceFilterMode: filterMode,
      maxDistanceKm:
          (p['max_distance_km'] as num?)?.toInt() ?? state.maxDistanceKm,
      preferredState: p['preferred_state'] as String? ?? state.preferredState,
      relationshipType: relationshipType,
      location: city.isNotEmpty ? city : state.location,
      genderPreferences:
          (p['gender_preferences'] as List?)?.whereType<String>().toList() ??
              state.genderPreferences,
    );
    await _persist();
  }

  /// Pusht die Präferenzen serverseitig in profiles (Migration 066) und
  /// verifiziert per Zurücklesen (gleiche Methode wie bei den Setup-Flags).
  ///
  /// [ageRangeMin]/[ageRangeMax] und [city]/[stateStr] können mitgegeben
  /// werden, wenn der Aufrufer sie gerade geändert hat (Einrichtung/
  /// Profil-Edit) - sie landen in denselben Server-Spalten.
  ///
  /// Rückgabe: true bei Erfolg (false = fehlgeschlagen, Aufrufer kann
  /// warnen; die lokalen Werte bleiben trotzdem gespeichert).
  Future<bool> savePreferencesToServer({
    int? ageRangeMin,
    int? ageRangeMax,
    String? city,
    String? stateStr,
  }) async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final body = <String, dynamic>{
        'max_distance_km': state.maxDistanceKm,
        // Modus mitsenden (Migration 085) - sonst springt er nach
        // Neuinstallation zurueck (der eigentliche Radius-weg-Bug).
        'distance_filter_mode': state.distanceFilterMode.name,
        'gender_preferences': state.genderPreferences,
        'relationship_type': state.relationshipType?.value,
        // Bewusst IMMER schreiben (auch null = Filter "Ganz Deutschland"),
        // sonst würde ein späterer Sync den alten Wert zurückholen.
        'preferred_state': state.preferredState,
      };
      if (ageRangeMin != null) body['age_range_min'] = ageRangeMin;
      if (ageRangeMax != null) body['age_range_max'] = ageRangeMax;
      if (city != null && city.trim().isNotEmpty) body['city'] = city.trim();
      if (stateStr != null && stateStr.trim().isNotEmpty) {
        body['state'] = stateStr.trim();
      }
      return await SupabaseDatabaseService(SupabaseService.client)
          .updateSetupFlagsAndVerify(body);
    } catch (e) {
      debugPrint('[UserPreferences] Server-Sync fehlgeschlagen: $e');
      return false;
    }
  }
}

/// Provider für die Nutzerpräferenzen (Audit M-16: sicher gespeichert).
final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesNotifier, UserPreferences>((ref) {
  final storage = ref.watch(securePrefsProvider);
  return UserPreferencesNotifier(storage, ref.watch(sharedPrefsProvider));
});

/// Audit M-16: Sichere Speicher-Instanz für sensible Präferenzen.
final securePrefsProvider = Provider<SecurePreferencesStorage>((ref) {
  return SecurePreferencesStorage();
});

/// Zugriff auf die rohen SharedPreferences (für Migrationen/Bestandssysteme).
final sharedPrefsProvider = Provider<SharedPreferences?>((ref) => null);
