import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/services/secure_hive.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/supabase_storage_service.dart';

/// Merker "Verifizierung eingereicht" für die Pending-Anzeige im Profil.
///
/// Konto-gebunden: Muss bei Logout/Account-Wechsel gelöscht werden,
/// sonst sieht ein neu registrierter Account auf demselben Gerät
/// "Prüfung läuft", ohne je etwas eingereicht zu haben (siehe
/// [AuthNotifier.logout]).
const String verificationSubmittedKey = 'verification_submitted';

/// Model für das Verifizierungs-Video.
class VerificationVideo {
  const VerificationVideo({
    required this.filePath,
    required this.recordedAt,
    required this.durationSeconds,
    this.challengeText,
    this.challengeGesture,
    this.location,
    this.isVerified = false,
    this.faceEmbedding, // Für späteren Gesichtserkennungs-Abgleich
  });

  /// Lokaler Dateipfad des Videos.
  final String filePath;

  /// Aufnahmezeitpunkt.
  final DateTime recordedAt;

  /// Dauer in Sekunden.
  final int durationSeconds;

  /// Zufälliger Text, den der Nutzer sprechen musste (Liveness).
  final String? challengeText;

  /// Zufällige Geste, die der Nutzer machen musste (z. B. "Zunge raus", "Blinzeln").
  final String? challengeGesture;

  /// GPS-Position bei Aufnahme (für Massen-Fake-Erkennung).
  final Position? location;

  /// Ob das Video manuell/automatisch verifiziert wurde.
  final bool isVerified;

  /// Gesichtseinbettung (Embedding) für späteren Abgleich mit Profilbildern.
  /// In Produktion: Vektor aus FaceNet/ML-Kit. Für Prototyp: null.
  final List<double>? faceEmbedding;

  VerificationVideo copyWith({
    String? filePath,
    DateTime? recordedAt,
    int? durationSeconds,
    String? challengeText,
    String? challengeGesture,
    Position? location,
    bool? isVerified,
    List<double>? faceEmbedding,
  }) {
    return VerificationVideo(
      filePath: filePath ?? this.filePath,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      challengeText: challengeText ?? this.challengeText,
      challengeGesture: challengeGesture ?? this.challengeGesture,
      location: location ?? this.location,
      isVerified: isVerified ?? this.isVerified,
      faceEmbedding: faceEmbedding ?? this.faceEmbedding,
    );
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'recordedAt': recordedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'challengeText': challengeText,
        'challengeGesture': challengeGesture,
        'location': location != null
            ? {'lat': location!.latitude, 'lng': location!.longitude}
            : null,
        'isVerified': isVerified,
        'faceEmbedding': faceEmbedding,
      };

  factory VerificationVideo.fromJson(Map<String, dynamic> json) {
    return VerificationVideo(
      filePath: json['filePath'] as String,
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      durationSeconds: json['durationSeconds'] as int,
      challengeText: json['challengeText'] as String?,
      challengeGesture: json['challengeGesture'] as String?,
      location: json['location'] == null
          ? null
          : Position(
              latitude: (json['location']['lat'] as num).toDouble(),
              longitude: (json['location']['lng'] as num).toDouble(),
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              headingAccuracy: 0,
              altitudeAccuracy: 0,
            ),
      isVerified: json['isVerified'] as bool? ?? false,
      faceEmbedding: (json['faceEmbedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
    );
  }
}

/// Challenge-Typen für Liveness-Check.
enum VerificationChallengeType {
  /// Zufällige Zahl/Ziffernfolge vorlesen.
  speakNumber,
  /// Bestimmte Geste machen (z. B. blinzeln, Zunge raus).
  makeGesture,
  /// Kopf drehen (links/rechts).
  turnHead,
  /// Lächeln.
  smile,
}

/// Service für Video-Verifizierung.
class VerificationService {
  static const String _boxName = 'verification_videos';
  static const int _minDurationSeconds = 5;
  static const int _maxDurationSeconds = 15;

  /// Minimale zulässige Aufnahmedauer in Sekunden.
  static int get minDurationSeconds => _minDurationSeconds;

  /// Maximale zulässige Aufnahmedauer in Sekunden.
  static int get maxDurationSeconds => _maxDurationSeconds;

  // =========================================================================
  // Speicher: JSON-STRING-Box statt typed Hive-Objekt.
  //
  // ROOT-CAUSE-FIX ("Einreichen schlägt fehl"): VerificationVideo hatte
  // KEINEN Hive-TypeAdapter - box.put() warf "HiveError: unknown type" und
  // die Einreichung brach VOR dem Upload ab (Server-Logs: nie ein
  // verification-videos-POST). Strings brauchen keinen Adapter; die
  // Metadaten laufen via toJson/fromJson.
  // =========================================================================
  late Box<String> _box;
  bool _initialized = false;

  /// Letzter EINREICHUNGS-Fehler (NUTZERWUNSCH Diagnose): Der Screen
  /// zeigt diese Meldung statt des Generik-Texts, wenn submit/auto
  /// mit false zurückkehrt (kein SnackBar-Textverlust mehr).
  String? _lastSubmitError;
  String? get lastSubmitError => _lastSubmitError;

  /// Verfügbare Challenges für Liveness-Check.
  static const List<VerificationChallengeType> _challengeTypes = [
    VerificationChallengeType.speakNumber,
    VerificationChallengeType.makeGesture,
    VerificationChallengeType.turnHead,
    VerificationChallengeType.smile,
  ];

  /// Initialisiert den Service.
  Future<void> initialize() async {
    if (_initialized) return;
    // AES-verschlüsselt (GPS-Metadaten + Verifizierungsstatus, s. SecureHive).
    _box = await SecureHive.instance.openBox<String>(_boxName);
    _initialized = true;
    // Cleanup-Policy (Audit N2): Abgelaufene Videos/Dateien entfernen –
    // passiert im Hintergrund, blockiert die Initialisierung nicht.
    unawaited(_purgeExpired());
  }

  /// Aufbewahrungsdauer für Verifizierungs-Videos und ihre Metadaten.
  /// Nach Ablauf werden Datei und Hive-Eintrag gelöscht (DSGVO-
  /// Datenminimierung; ein Video wird i. d. R. innerhalb weniger Stunden
  /// geprüft).
  static const Duration _retention = Duration(days: 7);

  /// Entfernt abgelaufene Verifizierungs-Videos:
  /// 1. Hive-Einträge, deren recordedAt älter als [_retention] ist,
  /// 2. Dateien `verification_*` im Temp-Verzeichnis (auch verwaiste, deren
  ///    Box-Eintrag bereits fehlt).
  Future<void> _purgeExpired() async {
    try {
      final cutoff = DateTime.now().subtract(_retention);

      // 1) Box-Einträge + zugehörige Dateien.
      final expired = <String>[];
      for (final key in _box.keys) {
        final video = _videoFromBox(key);
        if (video == null) continue;
        if (video.recordedAt.isBefore(cutoff)) {
          expired.add(key as String);
          final file = File(video.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      if (expired.isNotEmpty) {
        await _box.deleteAll(expired);
      }

      // 2) Verwaiste Dateien in App-Support (M-17) und Legacy-Temp.
      for (final dirPath in [
        (await getApplicationSupportDirectory()).path,
        (await getTemporaryDirectory()).path, // Legacy-Ablage
      ]) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (!name.startsWith('verification_') || !name.endsWith('.mp4')) {
            continue;
          }
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Cleanup ist Best-Effort – darf Initialisierung/Nutzung nie brechen.
      if (kDebugMode) {
        debugPrint('[Verification] Cleanup fehlgeschlagen: $e');
      }
    }
  }

  /// Generiert eine zufällige Challenge für den Nutzer.
  ///
  /// Verwendet Random.secure() (Audit M8): Die frühere Uhrzeit-Modulo-
  /// Variante war vorhersagbar und hätte vorab vorbereitet werden können.
  ///
  /// Die Daten sind SPRACHNEUTRALE Codes (Zahl bzw. Schlüssel wie
  /// 'tongue'), KEINE deutschen Sätze - angezeigt wird lokalisiert via
  /// [challengeDataLabel]. Challenge-Texte erreichen den Server ohnehin
  /// nie (nur lokale Hive-Ablage + Anzeige).
  (VerificationChallengeType, String) generateChallenge() {
    final type =
        _challengeTypes[_secureRandom.nextInt(_challengeTypes.length)];
    String challengeData;

    switch (type) {
      case VerificationChallengeType.speakNumber:
        final number =
            (1000 + _secureRandom.nextInt(9000)).toString();
        challengeData = number;
        break;
      case VerificationChallengeType.makeGesture:
        const gestures = ['tongue', 'blink', 'brows'];
        challengeData = gestures[_secureRandom.nextInt(gestures.length)];
        break;
      case VerificationChallengeType.turnHead:
        challengeData =
            _secureRandom.nextBool() ? 'left_right' : 'right_left';
        break;
      case VerificationChallengeType.smile:
        challengeData = 'smile';
        break;
    }

    return (type, challengeData);
  }

  static final Random _secureRandom = Random.secure();

  /// Lokalisiertes Label für Challenge-Daten-Codes (Zahlen kommen durch).
  static String challengeDataLabel(
      BuildContext context, VerificationChallengeType type, String data) {
    switch (type) {
      case VerificationChallengeType.speakNumber:
        return data;
      case VerificationChallengeType.makeGesture:
        return L10n.t(context, 'verify.challenge.gesture.$data');
      case VerificationChallengeType.turnHead:
        return L10n.t(context, 'verify.challenge.direction.$data');
      case VerificationChallengeType.smile:
        return L10n.t(context, 'verify.challenge.action.smile');
    }
  }

  /// Holt die lokalisierten Anzeigetexte für eine Challenge.
  String challengeDescription(BuildContext context,
      VerificationChallengeType type, String challengeData) {
    final base = L10n.t(context, 'verify.challenge.base.${type.name}');
    final label = challengeDataLabel(context, type, challengeData);
    return '$base\n\n${L10n.t(context, 'verify.challenge.task')} "$label"';
  }

  /// Startet die Video-Aufnahme mit der Frontkamera.
  ///
  /// Gibt den Pfad zur aufgenommenen Datei zurück.
  ///
  /// Audit M-17: Die Datei liegt im app-privaten Anwendungs-Support-
  /// Verzeichnis statt im System-Temp-Ordner (der von Backup-/Cleaner-Tools
  /// und Forensik leichter lesbar ist). Das Video zeigt Gesicht + Stimme
  /// und ist damit biometrie-nahe PII.
  Future<String?> recordVerificationVideo({
    required CameraController cameraController,
    required VerificationChallengeType challengeType,
    required String challengeData,
    int maxDurationSeconds = _maxDurationSeconds,
  }) async {
    if (!cameraController.value.isInitialized) {
      throw StateError('Kamera nicht initialisiert');
    }

    final dir = await getApplicationSupportDirectory();
    final filePath =
        '${dir.path}/verification_${DateTime.now().millisecondsSinceEpoch}.mp4';

    try {
      await cameraController.startVideoRecording();
      await Future.delayed(Duration(seconds: maxDurationSeconds));
      final file = await cameraController.stopVideoRecording();

      // Datei an endgültigen Ort verschieben
      await file.saveTo(filePath);
      return filePath;
    } catch (e) {
      debugPrint('[Verification] Aufnahmefehler: $e');
      return null;
    }
  }

  /// Speichert das fertige Verifizierungs-Video mit Metadaten.
  ///
  /// KRITISCHER FIX ("Kein Video im lokalen Speicher gefunden"): Der
  /// Screen liefert den Pfad von stopVideoRecording() - eine CACHE-Datei
  /// des Kamera-Plugins (z. B. .../cache/video1234.mp4). Die enthielt
  /// (a) NICHT `verification_` im Namen und wurde von
  /// [getVerificationVideo] deshalb gefiltert (-> submit sah kein Video)
  /// und (b) könnte der System-Cache-Manager jederzeit räumen. Der
  /// alte Rename/Copy-Schritt aus recordVerificationVideo ging beim
  /// Flow-Umbau verloren. Jetzt: Die Datei wird in den App-Support-
  /// Ordner unter `verification_<Zeitstempel>.mp4` kopiert (Name-Muster
  /// + Retention-Sweep + DeleteAllLocalData passen dazu), das Kamera-
  /// Cache-Original entfernt und der FINALE Pfad gespeichert.
  ///
  /// Datenschutz/Ordnung: Alle ÄLTEREN Aufnahmen werden mit ihrer
  /// Datei gelöscht - nur die aktuelle Aufnahme bleibt als
  /// Einreichungsquelle erhalten.
  Future<VerificationVideo> saveVerificationVideo({
    required String filePath,
    required VerificationChallengeType challengeType,
    required String challengeData,
    Position? location,
  }) async {
    // Alte Aufnahmen entfernen (Box-Eintrag + Datei).
    final stale = <String>[];
    for (final key in _box.keys.toList()) {
      final old = _videoFromBox(key);
      if (old == null) continue;
      if (old.filePath == filePath) continue;
      stale.add(key as String);
      final f = File(old.filePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    if (stale.isNotEmpty) {
      await _box.deleteAll(stale);
    }

    // Umbenennen/Kopieren in den dauerhaften App-Support-Ordner.
    final dir = await getApplicationSupportDirectory();
    final finalPath =
        '${dir.path}/verification_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final source = File(filePath);
    if (!await source.exists()) {
      throw StateError(
          'Aufnahme-Datei fehlt nach dem Stoppen ($filePath) - bitte '
          'erneut aufnehmen.');
    }
    try {
      await source.copy(finalPath);
    } catch (e) {
      throw StateError(
          'Aufnahme konnte nicht gesichert werden: $e');
    }
    // Cache-Original entfernen (best effort - gehört dem Kamera-Plugin).
    try {
      await source.delete();
    } catch (_) {}

    final video = VerificationVideo(
      filePath: finalPath,
      recordedAt: DateTime.now(),
      durationSeconds: _maxDurationSeconds,
      challengeText: challengeType == VerificationChallengeType.speakNumber ? challengeData : null,
      challengeGesture: challengeType != VerificationChallengeType.speakNumber ? challengeData : null,
      location: location,
    );

    // JSON-String statt typed Objekt (kein Adapter nötig, s. oben).
    await _box.put(finalPath, jsonEncode(video.toJson()));
    return video;
  }

  /// Dekodiert einen Box-Eintrag (JSON-String) in [VerificationVideo].
  /// Liefert null bei ungültigen/beschädigten Einträgen (werden beim
  /// nächsten Aufruf als stale behandelt).
  VerificationVideo? _videoFromBox(dynamic key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return VerificationVideo.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Holt das Verifizierungs-Video des aktuellen Nutzers.
  ///
  /// FIX (mehrere Aufnahmen): Bei erneuter Aufnahme legt saveVerification-
  /// Video einen NEUEN Eintrag an - vorher kam hier der ÄLTESTEN zurück,
  /// d. h. die Wiedereinreichung lud das ALTE Video hoch und ließ das
  /// frische liegen ("Verifizierung funktioniert immer noch nicht").
  /// Jetzt: der Eintrag mit dem NEUESTEN recordedAt.
  VerificationVideo? getVerificationVideo() {
    if (_box.isEmpty) return null;
    VerificationVideo? latest;
    for (final key in _box.keys) {
      final v = _videoFromBox(key);
      if (v == null) continue;
      if (!v.filePath.contains('verification_')) continue;
      if (latest == null || v.recordedAt.isAfter(latest.recordedAt)) {
        latest = v;
      }
    }
    return latest;
  }

  /// Markiert das Video als verifiziert (nach manueller/automatischer Prüfung).
  Future<void> markAsVerified(String filePath) async {
    if (!_box.containsKey(filePath)) return;
    final video = _videoFromBox(filePath);
    if (video == null) return;
    await _box.put(filePath, jsonEncode(video.copyWith(isVerified: true).toJson()));
  }

  /// Löscht das Video (z. B. bei erneuter Verifizierung).
  Future<void> deleteVideo(String filePath) async {
    await _box.delete(filePath);
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Prüft, ob der Nutzer bereits verifiziert ist.
  ///
  /// HINWEIS (Audit M3): Rein lokaler UX-Zustand – manipulierbar und ohne
  /// serverseitige Bedeutung. Authoritative Quelle ist
  /// `profiles.is_verified` (nur durch Admins/Edge Functions setzbar,
  /// Migration 040/verify-account).
  bool get isVerified {
    final video = getVerificationVideo();
    return video?.isVerified == true;
  }

  /// Audit M-17 / H-8: Entfernt ALLE lokalen Verifikations-Reste
  /// (Box-Einträge + Videodateien in App-Support- UND Legacy-Temp-Ordner).
  /// Wird bei Logout-Aufräumen und Account-Löschung aufgerufen.
  Future<void> deleteAllLocalData() async {
    try {
      for (final key in _box.keys.toList()) {
        final video = _videoFromBox(key);
        if (video != null) {
          final file = File(video.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      await _box.clear();

      // Datei-Sweep in beiden Verzeichnissen (inkl. verwaister Dateien).
      final dirs = <Directory>[
        Directory((await getApplicationSupportDirectory()).path),
        Directory((await getTemporaryDirectory()).path), // Legacy-Reste
      ];
      for (final dir in dirs) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('verification_') && name.endsWith('.mp4')) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VerificationService] deleteAllLocalData fehlgeschlagen: $e');
    }
  }

  /// Reicht das aufgezeichnete Verifizierungs-Video ein.
  ///
  /// Ablauf:
  ///   1. Lokal speichern (immer, auch offline).
  ///   2. Server-Upload (privater Bucket) + verify-account Edge Function.
  ///   3. Fällt der SERVER-Teil aus (Netzwerk/Storage/Edge), gilt die
  ///      Einreichung trotzdem als lokal abgeschlossen (Status pending) -
  ///      der Nutzer hat seine Aufgabe erfüllt; der Upload wird beim
  ///      nächsten App-Start über [retryPendingUpload] nachgeholt.
  Future<bool> submitVerification({
    double? estimatedAge,
    int? faceCount,
  }) async {
    // Video muss lokal existieren.
    final video = getVerificationVideo();
    if (video == null) {
      _lastSubmitError = 'Kein Video im lokalen Speicher gefunden';
      return false;
    }

    if (!SupabaseService.isInitialized) {
      // Offline: lokal als pending vermerken (Upload später).
      return true;
    }

    try {
      // 1) Privater Upload (mit Timeout: Bei langsamem Netz darf die
      //    Auswertung nicht endlos hängen - bei Timeout greift unten der
      //    Fail-open-Pfad (lokal pending, Upload wird nachgeholt).
      final file = File(video.filePath);
      if (!await file.exists()) {
        _lastSubmitError =
            'Video-Datei fehlt auf dem Gerät (${video.filePath})';
        return false;
      }
      final bytes = await file.readAsBytes();

      final storage = SupabaseStorageService(SupabaseService.client);
      await storage
          .uploadVerificationVideo(bytes)
          .timeout(const Duration(seconds: 60));

      // 2) Serverseitige Einreichung vermerken (KI-Schätzung optional).
      final submitBody = <String, dynamic>{'action': 'submit'};
      final est = estimatedAge;
      if (est != null && est.isFinite) submitBody['estimatedAge'] = est;
      final fc = faceCount;
      if (fc != null) submitBody['faceCount'] = fc;
      final response = await SupabaseService.client.functions
          .invoke(
            'verify-account',
            body: submitBody,
          )
          .timeout(const Duration(seconds: 45));

      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        final accepted = data['status'] == 'pending';
        if (accepted) {
          await deleteVideo(video.filePath);
        } else {
          _lastSubmitError =
              'Server lehnte die Einreichung ab: '
              '${data['error'] ?? data['status'] ?? data.keys.toList()}';
        }
        return accepted;
      }
      _lastSubmitError =
          'Unerwartete Server-Antwort (${response.data.runtimeType})';
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VerificationService] Server-Submit fehlgeschlagen '
            '(lokal pending): $e');
      }
      // Server nicht erreichbar: Video ist LOKAL gespeichert, die
      // Aufgabe ist erfüllt -> als pending akzeptieren (Fix "Einreichen
      // schlägt immer fehl trotz korrekter Ausführung"). Der Upload
      // wird über retryPendingUpload beim nächsten Start nachgeholt.
      _lastSubmitError = null;
      return true;
    }
  }

  /// KI-Triage unauffällig (v0.9.1, Migration 095 + Edge Action "auto").
  ///
  /// Nur aufrufen, wenn lokal gilt: genau 1 Gesicht, Liveness-Challenge
  /// absolviert, Abweichung <= 2 Jahre. Der Server prüft die Regel erneut
  /// (Video-Existenz, Status, Grenzen) und setzt givenenfalls Badge +
  /// Status 'auto'. Das Video bleibt für Stichproben erhalten.
  /// Rückgabe: true bei sofortiger Freigabe.
  ///
  /// KRITISCHER FIX ("Überprüfung schlägt fehl"): Das Video wurde erst im
  /// SUBMIT-Pfad hochgeladen - der Auto-Call kam davor an, der Server
  /// fand kein Video im Bucket (400) und die KI-Triage scheiterte STANDS-
  /// MÄSSIG (immer manuelle Prüfung). Jetzt: Upload VOR dem Auto-Call.
  Future<bool> autoVerification({
    required double estimatedAge,
    required int faceCount,
    required double deviation,
    // Play-Integrity-Attestierung (v0.9.0, nur Play-Builds): Wird der
    // Server-Prüfung übergeben; fehlt sie, gilt der bisherige Pfad
    // (F-Droid, iOS, alte Builds). Niemals clientseitig entscheiden.
    String? integrityToken,
    String? integrityNonce,
  }) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      // 1) Privater Upload (Server-Regel verlangt das Video im Bucket).
      //    Timeout wie im Submit-Pfad: kein endloses Hängen.
      final video = getVerificationVideo();
      if (video == null) return false;
      final file = File(video.filePath);
      if (!await file.exists()) return false;
      final storage = SupabaseStorageService(SupabaseService.client);
      await storage
          .uploadVerificationVideo(await file.readAsBytes())
          .timeout(const Duration(seconds: 60));

      // 2) Serverseitige Prüfung (Regel "auto").
      final response = await SupabaseService.client.functions
          .invoke(
            'verify-account',
            body: {
              'action': 'auto',
              'estimatedAge': estimatedAge,
              'faceCount': faceCount,
              'deviation': deviation,
              'liveness': true,
              if (integrityToken != null && integrityNonce != null) ...{
                'integrityToken': integrityToken,
                'integrityNonce': integrityNonce,
              },
            },
          )
          .timeout(const Duration(seconds: 45));
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data['status'] == 'auto') {
          // Lokale Kopie entfernen (liegt serverseitig für Stichproben).
          await deleteVideo(video.filePath);
          return true;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VerificationService] Auto-Freigabe fehlgeschlagen: $e');
      }
      return false;
    }
  }

  void dispose() {
    _box.close();
  }
}

/// Provider für den VerificationService.
final verificationServiceProvider = Provider<VerificationService>((ref) {
  final service = VerificationService();
  Future.microtask(() => service.initialize());
  ref.onDispose(service.dispose);
  return service;
});