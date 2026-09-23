import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/avatar_crypto.dart';
import 'package:wisp/services/supabase_service.dart';

/// Service für private Avatar-Speicherung in Supabase Storage.
///
/// WICHTIG:
/// - Der Bucket `avatars` ist privat (public = false).
/// - Clientseitig wird NUR der Pfad `{userId}/avatar.jpg` verwendet.
/// - Der Upload nutzt die standard PostgREST-Insert-Route auf `storage.objects`.
/// - Anzeige erfolgt über signierte URLs ODER (v0.8.1) verschlüsselt:
///   Profilbilder werden clientseitig AES-256-GCM verschlüsselt, bevor
///   sie den Server erreichen. Der Schlüssel steckt im `photos`-Eintrag
///   der EIGENEN Profil-Zeile (`path|key|iv`); Fremd-Bilder laufen über
///   [loadPartnerAvatarBytes] mit Schlüssel aus match-media (107).
///   Download + lokale Entschlüsselung via [loadAvatarBytes].
class SupabaseStorageService {
  SupabaseStorageService(this._client);

  final SupabaseClient _client;

  User? get _currentUser => SupabaseService.currentUser;

  static const String _bucket = 'avatars';
  static const String _fileName = 'avatar.jpg';
  static const int _signedUrlExpirySeconds = 3600;

  /// Lädt eine Chat-Media-Datei (Bild, Sprache) in den Storage hoch.
  ///
  /// Speichert unter `{userId}/chat/{timestamp}.{ext}`.
  /// Gibt die signierte URL zurück, die direkt im Chat angezeigt werden kann.
  Future<String> uploadChatMedia(List<int> data, String fileExtension) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    // Pfad-Traversal/Injektion verhindern (Audit N1): Nur harmlose
    // Datei-Endungen erlauben, alles andere neutralisieren.
    final safeExtension =
        RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(fileExtension)
            ? fileExtension.toLowerCase()
            : 'bin';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$userId/chat/$timestamp.$safeExtension';
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload chat media: '
          'bucket=$_bucket size=${data.length}');
    }

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
        );

    final signedUrl = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlExpirySeconds);

    return signedUrl;
  }

  /// Pfad für den aktuellen Nutzer: `{userId}/avatar.jpg`.
  String _avatarPathForUser(String userId) => '$userId/$_fileName';

  /// Pfad für Einspruchs-Bilder: `{userId}/appeals/{timestamp}.jpg`.
  /// (v0.8.1: abgelehnte Bilder werden NIE als Avatar hochgeladen -
  /// sie landen ausschließlich im geschützten Prüfungsort, den nur der
  /// Eigentümer und Admins via Policy lesen können.)
  Future<String> uploadAppealImage(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }
    final path =
        '$userId/appeals/${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload appeal image: '
          'bucket=$_bucket size=${data.length}');
    }
    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  /// Signierte URL für ein Einspruchs-Bild (Admin-Anzeige im
  /// Moderations-Tab; Zugriff über die 079-Admin-Policy).
  Future<String?> getSignedUrlFor(String path) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(path, _signedUrlExpirySeconds);
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Signed-URL fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Lädt ein Einspruchs-Bild herunter (Klartext, Owner oder Admin).
  Future<Uint8List?> downloadAppealImage(String path) async {
    try {
      return await _client.storage.from(_bucket).download(path);
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Appeal-Download fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Löscht eine eigene Datei im avatars-Bucket (z. B. abgelehntes
  /// Einspruchs-Bild aufräumen). Owner-Policy erlaubt das.
  Future<void> deleteOwnObject(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Delete fehlgeschlagen: $e');
      }
    }
  }

  /// Lädt ein Avatar-Bild hoch (v0.8.1: AES-256-GCM-verschlüsselt).
  ///
  /// [data] sind die rohen Bild-Bytes. Sie werden VOR dem Upload
  /// verschlüsselt - der Server sieht nie das Klartext-Bild. Der Pfad
  /// bleibt `{userId}/avatar.jpg`; der Zufalls-Schlüssel wird im
  /// Rückgabewert (`path|key|iv`) mitgeführt und landet in
  /// `profiles.photos`. Alte (Klartext-)Avatare bleiben mit
  /// [loadAvatarBytes] lesbar (Fallback).
  Future<String> uploadAvatar(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final enc = AvatarCrypto.encrypt(Uint8List.fromList(data));
    final path = _avatarPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload avatar (verschlüsselt): '
          'bucket=$_bucket size=${enc.cipher.length}');
    }

    // upsert: Erneutes Hochladen (neues Bild) ueberschreibt das alte -
    // ohne upsert wuerde der zweite Upload mit 409 scheitern.
    await _client.storage.from(_bucket).uploadBinary(
          path,
          enc.cipher,
          fileOptions: const FileOptions(upsert: true),
        );

    return AvatarCrypto.encodeRef(path, enc.keyB64, enc.ivB64);
  }

  /// Lädt ein ZUSÄTZLICHES Profilbild hoch (v0.9.0, max. 3 - siehe
  /// [maxPhotos]).
  ///
  /// Gleiche Verschlüsselung wie [uploadAvatar], aber mit indiziertem
  /// Pfad `{userId}/photos/{index}.jpg`, damit bis zu drei Bilder
  /// parallel existieren. Der verschlüsselte Ref (`path|key|iv`) landet
  /// in `profiles.photos` (Liste).
  Future<String> uploadPhoto(List<int> data, {required int index}) async {
    assert(index >= 0 && index < maxPhotos, 'index 0..2 (max. 3 Bilder)');
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final enc = AvatarCrypto.encrypt(Uint8List.fromList(data));
    final path = '$userId/photos/${index + 1}.jpg';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          enc.cipher,
          fileOptions: const FileOptions(upsert: true),
        );

    return AvatarCrypto.encodeRef(path, enc.keyB64, enc.ivB64);
  }

  /// Maximale Anzahl an Profilbildern (v0.9.0-Nutzerwunsch).
  static const int maxPhotos = 3;

  /// Lädt ein Avatar herunter und entschlüsselt es lokal (v0.8.1).
  ///
  /// Akzeptiert sowohl verschlüsselte Einträge (`path|key|iv`) als auch
  /// Legacy-Klartext-Pfade. Liefert die BILD-BYTES (keine URL!) - der
  /// Aufrufer zeigt sie mit `Image.memory`/`MemoryImage` an.
  ///
  /// Performance (v0.8.1): Ergebnis wird pro Referenz IM SPEICHERER
  /// gecacht - Profil, Vorschau und QR-Screen laden ohne Wartezeit; der
  /// Cache-Key ist die komplette Referenz, ein neues Bild = neuer Key.
  static final Map<String, Uint8List> _avatarMemoryCache = {};

  Future<Uint8List?> loadAvatarBytes(String ref) async {
    final cached = _avatarMemoryCache[ref];
    if (cached != null) return cached;
    try {
      final parsed = AvatarCrypto.parseRef(ref);
      final path = parsed?.path ?? AvatarCrypto.pathOf(ref);
      final data =
          await _client.storage.from(_bucket).download(path);
      // FREEZE-FIX (v0.8.1): GCM-Entschlüsselung in pure Dart (1-2 MB)
      // dauert spürbar - Hintergrund-Isolate statt UI-Thread.
      final result = parsed == null
          ? data // Legacy: Klartext.
          : await compute(
              AvatarCrypto.decryptArgs,
              (data, parsed.key, parsed.iv),
            );
      _avatarMemoryCache[ref] = result;
      return result;
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Avatar-Download/Entschlüsselung '
            'fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Lädt das Avatar-Bild eines FREMDEN Nutzers (Match-Partner, Quiz etc.).
  ///
  /// Security-Fix (Migration 107): AES-Schlüssel/IV stehen NICHT mehr in
  /// der Public-View. Ablauf: match-media (kind=avatar, gleiche
  /// Match-/Quiz-Berechtigungsprüfung wie für die URL) liefert
  /// {url, keyB64, ivB64}; Download + lokale Entschlüsselung hier.
  /// Legacy-Klartextpfade (ohne Schlüssel) funktionieren weiter.
  /// Eigene Bilder NICHT hierüber laden (dafür [loadAvatarBytes] mit den
  /// vollen lokalen Refs) - match-media lehnt Selbstabfragen ab.
  static final Map<String, Uint8List> _partnerAvatarMemoryCache = {};

  Future<Uint8List?> loadPartnerAvatarBytes({
    required String targetUserId,
    String? path,
  }) async {
    final cacheKey = '$targetUserId|${path ?? 'avatar.jpg'}';
    final cached = _partnerAvatarMemoryCache[cacheKey];
    if (cached != null) return cached;
    try {
      final response = await _client.functions.invoke(
        'match-media',
        body: {
          'targetUserId': targetUserId,
          'kind': 'avatar',
          if (path != null && path.isNotEmpty) 'path': path,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url == null || url.isEmpty) return null;
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        if (kDebugMode) {
          log('[SupabaseStorageService] Partner-Avatar Download fehl: '
              'HTTP ${res.statusCode}');
        }
        return null;
      }
      final bytes = res.bodyBytes;
      final keyB64 = data?['keyB64'] as String?;
      final ivB64 = data?['ivB64'] as String?;
      if (keyB64 == null || ivB64 == null) {
        _partnerAvatarMemoryCache[cacheKey] = bytes; // Legacy-Klartext.
        return bytes;
      }
      final Uint8List result;
      try {
        result = await compute(
          AvatarCrypto.decryptArgs,
          (bytes, base64Decode(keyB64), base64Decode(ivB64)),
        );
      } catch (e) {
        // NUTZERWUNSCH "Bild einfach nicht sichtbar": Schlüssel passt
        // nicht zum Ciphertext (z. B. alter Refs-Cache) - NICHT cachen,
        // damit ein frischer match-media-Aufruf es erneut versucht.
        if (kDebugMode) {
          log('[SupabaseStorageService] Avatar-Entschlüsselung fehl: $e');
        }
        return null;
      }
      _partnerAvatarMemoryCache[cacheKey] = result;
      return result;
    } catch (e) {
      if (kDebugMode) {
        log('[SupabaseStorageService] Partner-Avatar fehlgeschlagen: $e');
      }
      return null;
    }
  }

  /// Entfernt einen Partner-Avatar aus dem Memory-Cache (NUTZERWUNSCH
  /// "Bild einfach nicht sichtbar": Bei Retry keinen veralteten
  /// Schlüssel-Cache behalten, damit match-media frisch antwortet).
  void invalidatePartnerAvatar({
    required String targetUserId,
    String? path,
  }) {
    _partnerAvatarMemoryCache
        .remove('$targetUserId|${path ?? 'avatar.jpg'}');
  }

  /// Erzeugt eine temporäre signierte URL für den angegebenen Storage-Pfad.
  ///
  /// Gültigkeit: 3600 Sekunden. Die URL ist nur mit aktiver Session gültig.
  /// (NUR noch für Intro-Audio u. ä. - Profilbilder laufen über
  /// [loadAvatarBytes], weil sie verschlüsselt sind.)
  Future<String?> getSignedAvatarUrl(String path) async {
    if (kDebugMode) {
      log('[SupabaseStorageService] Request signed URL: bucket=$_bucket');
    }

    final result = await _client.storage
        .from(_bucket)
        .createSignedUrl(path, _signedUrlExpirySeconds);

    return result;
  }

  /// Löscht den aktuellen Avatar.
  Future<void> deleteAvatar() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _avatarPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Delete avatar: bucket=$_bucket');
    }

    await _client.storage.from(_bucket).remove([path]);
  }

  /// Pfad der Intro-Audio-Datei: `{userId}/intro.m4a`.
  String _introPathForUser(String userId) => '$userId/intro.m4a';

  /// Lädt die Audio-Vorstellung hoch und gibt den Storage-Pfad zurück.
  Future<String> uploadIntroAudio(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _introPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload intro audio: bucket=$_bucket size=${data.length}');
    }

    await _client.storage.from(_bucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          // upsert: Erneutes Hochladen (z. B. zweite Aufnahme in der
          // Einrichtung) ueberschreibt das alte Audio - ohne upsert
          // scheitert es mit StorageException 409 "Duplicate".
          //
          // contentType (088): WICHTIG - ohne expliziten Typ landet
          // 'text/plain' in einem MIME-Whitelist-Bucket (Migration 003)
          // und der Upload wurde still verweigert ("Vorstellung mit
          // Audio verschwunden"). AAC/m4a = audio/mp4; der Bucket
          // erlaubt es seit Migration 088.
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'audio/mp4',
          ),
        );

    return path;
  }

  /// Entfernt die Audio-Vorstellung.
  Future<void> deleteIntroAudio() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }

    final path = _introPathForUser(userId);
    if (kDebugMode) {
      log('[SupabaseStorageService] Delete intro audio: bucket=$_bucket');
    }

    await _client.storage.from(_bucket).remove([path]);
  }

  // =========================================================================
  // Verifizierungs-Video (privater Bucket, nur eigener Ordner per RLS).
  // =========================================================================

  static const _verificationBucket = 'verification-videos';

  /// Lädt das Verifizierungs-Video in den PRIVATEN Bucket und gibt den
  /// Storage-Pfad zurück (`{userId}/video.mp4`). Lesen kann die Datei nur
  /// der Eigentümer; Admins erhalten kurzlebige signierte URLs über die
  /// Edge Function `verification-media`.
  Future<String> uploadVerificationVideo(List<int> data) async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }
    if (data.isEmpty) {
      throw AppException('Das Video ist leer.');
    }

    final path = '$userId/video.mp4';
    if (kDebugMode) {
      log('[SupabaseStorageService] Upload verification video: '
          'size=${data.length}');
    }

    // NUTZERWUNSCH-DIAGNOSE: uploadBinary wirft bei "Objekt existiert
    // bereits" (409) - der REUPLOAD (nach abgelehnter Einreichung)
    // scheiterte dadurch still. Upsert macht die Einreichung wiederholbar.
    await _client.storage.from(_verificationBucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          fileOptions: const FileOptions(
            contentType: 'video/mp4',
            upsert: true,
          ),
        );

    return path;
  }

  /// Entfernt das eigene Verifizierungs-Video (z. B. bei Abbruch).
  Future<void> deleteVerificationVideo() async {
    final userId = _currentUser?.id;
    if (userId == null) {
      throw AppException('Nicht eingeloggt.');
    }
    await _client.storage.from(_verificationBucket).remove([
      '$userId/video.mp4',
    ]);
  }
}

/// Provider für den [SupabaseStorageService].
final supabaseStorageServiceProvider = Provider<SupabaseStorageService>((ref) {
  return SupabaseStorageService(SupabaseService.client);
});
