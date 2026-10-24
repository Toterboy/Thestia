import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/habitude_level.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/notification_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';

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

    // Serververwaltete Felder nachziehen.
    //
    // BUG (Nutzerbefund): Nach der Admin-Freigabe blieb das eigene
    // Profil auf "nicht verifiziert". Ursache: Das Profil kommt
    // ausschliesslich aus dem LOKALEN Secure-Store. `is_verified` wird
    // aber serverseitig gesetzt (Admin-Freigabe), und nichts holte
    // diesen Wert nach. Die lokale Kopie blieb fuer immer auf false.
    //
    // Betroffen ist nicht nur das Badge: auch die Modus-Sperren und
    // die Anzeige "wird ueberprueft" lesen dieses Feld.
    unawaited(_refreshServerManagedFields());
  }

  /// Meldet die Freigabe der Verifizierung lokal.
  ///
  /// Bewusst als lokale Meldung und nicht als Push: die Freigabe
  /// entsteht, wenn der Admin sie im Backend setzt, und der Nutzer
  /// bekommt den Wechsel beim naechsten Abgleich mit. Eine
  /// Push-Benachrichtigung wuerde einen Server-Push-Kanal voraussetzen,
  /// den es hier nicht gibt.
  Future<void> _notifyVerified() async {
    try {
      await NotificationService.instance.showSystemNotice(
        // Feste ID: Es gibt nur eine Verifizierungs-Meldung, und eine
        // zweite wuerde die erste ersetzen statt daneben zu stehen.
        id: 90001,
        title: L10n.tWithoutContext('verify.autoTitle'),
        body: L10n.tWithoutContext('verify.autoBody'),
      );
    } catch (e) {
      debugPrint('[ProfileNotifier] Verifizierungs-Meldung fehlgeschlagen: '
          '$e');
    }
  }

  /// Holt die Felder, die der Server verwaltet, und schreibt sie in den
  /// lokalen Stand.
  ///
  /// Abgefragt werden `is_verified` und `verification_status`.
  ///
  /// BUG (Security-Audit 22.10.2026): es wurde nur `is_verified`
  /// gelesen. Der Dreifachzustand (unverified / under_review / verified)
  /// blieb dadurch lokal stehen - wer eine Einreichung gemacht hatte,
  /// sah weiterhin "nicht verifiziert" und die Modus-Sperren blieben
  /// ohne erkennbaren Grund bestehen.
  ///
  /// Der Rest des Profils ist nutzereigen und kommt aus dem Secure-Store;
  /// der Server ist fuer ihn nicht die Quelle.
  ///
  /// Fehler werden verschluckt: ohne Server bleibt der lokale Stand
  /// stehen, und die App ist offline benutzbar.
  Future<void> _refreshServerManagedFields() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final userId = SupabaseService.currentUser?.id;
      if (userId == null || userId.isEmpty) return;

      final res = await SupabaseService.client
          .from('profiles')
          .select('is_verified, verification_status')
          .eq('user_id', userId)
          .maybeSingle();
      if (res == null) return;

      final serverVerified = res['is_verified'] as bool? ?? false;
      final serverStatus = res['verification_status'] as String?;
      final serverState = VerificationState.fromServerStatus(
        serverStatus,
        isVerified: serverVerified,
      );
      if (serverVerified == state.isVerified &&
          serverState == state.verificationState) {
        return;
      }

      debugPrint('[ProfileNotifier] Verifikation vom Server: '
          'is_verified ${state.isVerified} -> $serverVerified, '
          'status ${state.verificationState.name} -> ${serverState.name}');
      final warVerifiziert = state.isVerified;
      state = state.copyWith(
        isVerified: serverVerified,
        verificationState: serverState,
      );
      await _persist();

      // Benachrichtigung ueber die Freigabe (v0.10.0).
      //
      // Die Freigabe passiert serverseitig durch einen Admin. Der
      // Nutzer sitzt derweil in der App und bekommt sonst nichts mit -
      // das Profil bleibt lokal auf "nicht verifiziert", bis die App
      // neu startet. Der Uebergang unveraendert -> verifiziert ist
      // deshalb das Signal fuer eine Meldung.
      if (!warVerifiziert && serverVerified) {
        unawaited(_notifyVerified());
      }
    } catch (e) {
      debugPrint('[ProfileNotifier] Serverstatus nicht abrufbar: $e');
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

