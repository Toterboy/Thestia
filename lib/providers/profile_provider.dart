import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/secure_storage.dart';
import 'package:wisp/utils/constants.dart';

/// Verwaltet das eigene Nutzerprofil und persistiert es lokal.
///
/// Sicherheit: Das Profil enthält PII (Geburtsdatum, GPS-Koordinaten,
/// Bio, Persönlichkeitsergebnis) und wird ausschließlich im
/// verschlüsselten Keystore/Keychain ([SecureProfileStore]) abgelegt.
/// Der frühere Klartext-Eintrag in SharedPreferences wird einmalig
/// migriert und gelöscht.
class ProfileNotifier extends StateNotifier<UserProfile> {
  ProfileNotifier(this._storage, this._secure)
      : super(
          UserProfile(
            id: AppConstants.currentUserId,
            name: '',
            birthDate: null,
            bio: '',
          ),
        ) {
    _load();
  }

  final LocalStorage _storage;
  final SecureProfileStore _secure;

  Future<void> _load() async {
    var raw = await _secure.read();

    // Migration: Alten Klartext-Eintrag aus SharedPreferences übernehmen
    // und entfernen (einmalig nach dem Update).
    if (raw == null) {
      final legacy = await _storage.getString(AppConstants.prefsProfileKey);
      if (legacy != null) {
        await _secure.write(legacy);
        await _storage.remove(AppConstants.prefsProfileKey);
        raw = legacy;
      }
    }

    if (raw != null) {
      try {
        final loaded = UserProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        // birthdayToday hängt vom Tagesdatum ab - gespeicherter Wert
        // (ggf. von gestern) wird beim Laden neu berechnet.
        state = loaded.copyWith(
          birthdayToday:
              UserProfile.isBirthdayToday(loaded.birthDate),
        );
      } catch (e) {
        debugPrint('[ProfileNotifier] Korrupte Profil-Daten erkannt: $e');
        // Korrupte Daten verwerfen – Nutzer muss Profil neu einrichten.
        await _secure.delete();
        await _storage.remove(AppConstants.prefsProfileKey);
        state = UserProfile(id: AppConstants.currentUserId, name: '', bio: '');
      }
    }
  }

  Future<void> _persist() async {
    await _secure.write(jsonEncode(state.toJson()));
  }

  /// überschreibt das Profil (z. B. nach Registrierung).
  Future<void> setProfile(UserProfile profile) async {
    state = profile;
    await _persist();
  }

  /// Aktualisiert einzelne Felder.
  Future<void> update({
    String? name,
    DateTime? birthDate,
    String? bio,
    List<String>? interests,
    List<String>? photos,
    String? city,
    String? stateStr,
    String? country,
    String? gender,
    String? personalityResult,
    String? personalityType,
    double? locationLat,
    double? locationLng,
    String? introText,
    String? introAudioPath,
    HabitudeLevel? smoking,
    HabitudeLevel? alcohol,
    HabitudeLevel? drugs,
    List<String>? musicLiked,
    List<String>? musicDisliked,
    String? favoriteSong,
    String? favoriteBand,
    String? birthdayStyle,
    bool clearIntroAudio = false,
  }) async {
    state = state.copyWith(
      name: name,
      birthDate: birthDate,
      bio: bio,
      interests: interests,
      photos: photos,
      city: city,
      state: stateStr,
      country: country,
      gender: gender,
      personalityResult: personalityResult,
      personalityType: personalityType,
      locationLat: locationLat,
      locationLng: locationLng,
      introText: introText,
      introAudioPath: introAudioPath,
      smoking: smoking,
      alcohol: alcohol,
      drugs: drugs,
      musicLiked: musicLiked,
      musicDisliked: musicDisliked,
      favoriteSong: favoriteSong,
      favoriteBand: favoriteBand,
      birthdayStyle: birthdayStyle,
      // birthdayToday für das eigene Profil immer lokal neu berechnen
      // (Stichtag hängt vom Tagesdatum ab, nicht vom State).
      birthdayToday: UserProfile.isBirthdayToday(
          birthDate ?? state.birthDate),
      clearIntroAudio: clearIntroAudio,
    );
    await _persist();
  }

  /// Fügt ein Interesse hinzu/entfernt es (Toggle).
  Future<void> toggleInterest(String interest) async {
    final set = {...state.interests};
    if (set.contains(interest)) {
      set.remove(interest);
    } else {
      set.add(interest);
    }
    state = state.copyWith(interests: set.toList());
    await _persist();
  }

  /// Fügt ein Foto (Pfad/URL) hinzu.
  Future<void> addPhoto(String path) async {
    state = state.copyWith(photos: [...state.photos, path]);
    await _persist();
  }

  /// Entfernt ein Foto an Index.
  Future<void> removePhotoAt(int index) async {
    final list = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: list);
    await _persist();
  }

  /// Setzt das Profil auf einen leeren Zustand zurück
  /// (z. B. nach Account-Löschung – keine Alt-Daten im neuen Account).
  Future<void> resetToDefaults() async {
    state = UserProfile(id: AppConstants.currentUserId, name: '', bio: '');
    await _secure.delete();
    // Legacy-Aufräumen (ältere App-Versionen).
    await _storage.remove(AppConstants.prefsProfileKey);
  }
}

/// Provider für das eigene Profil.
final profileProvider =
    StateNotifierProvider<ProfileNotifier, UserProfile>((ref) {
  final storage = ref.watch(localStorageProvider);
  final secure = ref.watch(secureProfileStoreProvider);
  return ProfileNotifier(storage, secure);
});

