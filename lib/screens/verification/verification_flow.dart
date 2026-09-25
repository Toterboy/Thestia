import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thumb;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/age_estimation_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/play_integrity_service.dart';
import 'package:thestia/services/verification_service.dart';
import 'package:thestia/services/location_verification_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/ai_badge.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ergebnis der Verifizierung für den Abschluss-Screen (v0.9.1):
/// 'auto' = KI-Triage unauffällig, Badge sofort; 'pending' = manuelle
/// Prüfung durch den Support, Badge erst danach.
final verificationResultProvider = StateProvider<String?>((ref) => null);

/// Warum die KI-Triage die Verifizierung in die manuelle Queue gelegt hat
/// (L10n-Key, Diagnose für den Nutzer auf dem Abschluss-Screen).
final verificationPendingReasonProvider = StateProvider<String?>((ref) => null);

/// KI-Schätzabweichung in Jahren (für die Diagnose-Anzeige).
final verificationDeviationProvider = StateProvider<double?>((ref) => null);

/// Info-Screen VOR der Video Verifizierung.
class VerificationInfoScreen extends ConsumerWidget {
  const VerificationInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = GoRouterState.of(context).uri.queryParameters['code'] ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'verify.title'))),
      // Scrollbar statt starrer Column + Spacer: Auf kleinen Geräten war
      // der untere Teil (Button) unerreichbar.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.videocam,
                  size: 50,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                L10n.t(context, 'verify.title'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'verify.infoBody'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              L10n.t(context, 'verify.infoCardTitle'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InfoBullet(L10n.t(context, 'verify.info.1')),
                      _InfoBullet(L10n.t(context, 'verify.info.2')),
                      _InfoBullet(L10n.t(context, 'verify.info.3')),
                      _InfoBullet(L10n.t(context, 'verify.info.4')),
                      _InfoBullet(L10n.t(context, 'verify.info.5')),
                      _InfoBullet(L10n.t(context, 'verify.info.6')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              L10n.t(context, 'verify.locationTitle'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          children: _boldSpans(
                            L10n.t(context, 'verify.locationBody'),
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(L10n.t(context, 'verify.start')),
                onPressed: () =>
                    context.go('${AppRoutes.verificationVideo}?code=$code'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baut TextSpans aus **fett**-Markern. Ohne das stünden die Sterne
/// sichtbar im Text ("Wörter haben **xy**"-Bug).
List<InlineSpan> _boldSpans(String text, TextStyle? base) {
  final spans = <InlineSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    spans.add(
      TextSpan(
        text: parts[i],
        style: i.isOdd
            ? (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold)
            : base,
      ),
    );
  }
  return spans;
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✅ ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: _boldSpans(
                  text,
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen für Video Verifizierung (Aufnahme).
class VerificationVideoScreen extends ConsumerStatefulWidget {
  const VerificationVideoScreen({super.key});

  @override
  ConsumerState<VerificationVideoScreen> createState() =>
      _VerificationVideoScreenState();
}

class _VerificationVideoScreenState
    extends ConsumerState<VerificationVideoScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _processing = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  VerificationChallengeType _challengeType =
      VerificationChallengeType.speakNumber;
  String _challengeData = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _generateChallenge();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      final frontCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = L10n.tf(context, 'verify.cameraError', {'error': '$e'}),
        );
      }
    }
  }

  void _generateChallenge() {
    final (type, data) = ref
        .read(verificationServiceProvider)
        .generateChallenge();
    setState(() {
      _challengeType = type;
      _challengeData = data;
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    // Während der Auswertung keine zweite Aufnahme starten (Fix "nach
    // dem Stoppen passiert nichts": Ein Fehler im Stop-Pfad ließ den
    // Screen ohne Feedback hängen).
    if (_processing) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (_isRecording) {
      _recordTimer?.cancel();
      _recordTimer = null;
      // Sofort in den Processing-Zustand (Spinner sichtbar, Re-Entry
      // blockiert), DANN auswerten.
      setState(() {
        _isRecording = false;
        _processing = true;
      });
      try {
        final file = await controller.stopVideoRecording();
        await _saveVideo(file.path);
        // Erfolg: _saveVideo navigiert weg (Complete-Screen).
      } catch (e) {
        debugPrint('[Verification] Auswertung fehlgeschlagen: $e');
        if (mounted) {
          // Diagnose sichtbar statt generischem Text (der nächste
          // Tester sieht, WELCHER Schritt bricht).
          final short = e
              .toString()
              .replaceFirst('Exception: ', '')
              .replaceFirst('StateError: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                short.length > 200 ? '${short.substring(0, 200)}…' : short,
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _processing = false);
      }
      return;
    }

    if (!controller.value.isRecordingVideo) {
      try {
        await controller.startVideoRecording();
      } catch (e) {
        debugPrint('[Verification] Aufnahme-Start fehlgeschlagen: $e');
        if (mounted) {
          setState(
            () => _error = L10n.tf(context, 'verify.cameraError', {
              'error': '$e',
            }),
          );
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
    }
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordSeconds++);
      if (_recordSeconds >= 15) _toggleRecording(); // Auto-stop nach 15s
    });
  }

  Future<void> _saveVideo(String path) async {
    final service = ref.read(verificationServiceProvider);
    final locationService = ref.read(locationVerificationServiceProvider);

    // Standort abfragen (optional - Permission kann verweigert sein).
    Position? location;
    if (await locationService.hasLocationPermission()) {
      location = await locationService.getCurrentLocation();
      // getCurrentLocation kann trotz Permission null liefern (Timeout).
      if (location != null) {
        await locationService.saveVerificationLocation(location);
      }
    }

    // Mehrframe-Median (v0.9.0): Frames VOR dem Sichern aus der frischen
    // Aufnahme entnehmen (saveVerificationVideo löscht das Original).
    // Über den Clip verteilte Zeitstempel -> Pose/Mimik/Licht variieren,
    // Einzelbild-Ausreißer gehen im Median unter. Best-Effort: Was
    // schiefgeht, fehlt einfach als Sample.
    Future<List<Uint8List>> extractFrames(String videoPath) async {
      final frames = <Uint8List>[];
      for (final ms in AgeEstimationService.verificationFrameTimeMs) {
        try {
          final Uint8List? bytes = await thumb.VideoThumbnail.thumbnailData(
            video: videoPath,
            imageFormat: thumb.ImageFormat.JPEG,
            maxWidth: 480,
            quality: 80,
            timeMs: ms,
          ).timeout(const Duration(seconds: 10), onTimeout: () => null);
          if (bytes != null && bytes.isNotEmpty) frames.add(bytes);
        } catch (e) {
          debugPrint('[Verification] Frame @$ms ms übersprungen: $e');
        }
      }
      return frames;
    }

    final frames = await extractFrames(path);

    // Video speichern
    await service.saveVerificationVideo(
      filePath: path,
      challengeType: _challengeType,
      challengeData: _challengeData,
      location: location,
    );

    // Lokale Alters-KI (v0.9.0, Mehrframe-Median): Alle Samples (Video-
    // Frames + 1 Selfie) mit DEMSELBEN Modell schätzen, Median nehmen.
    // Best-Effort mit Timeout - bei Fehlschlag geht es in die manuelle
    // Prüfung (nichts wird blockiert). Kein Zweitmodell: Der Support
    // ist der Fallback.
    //
    // ROBUSTHEIT (Fix "Verifizierung klappt nicht"): Manche Geräte
    // hängen nach stopVideoRecording in einem ungültigen Kamera-Zustand
    // (takePicture wirft) - dann Kamera neu initialisieren und EINMAL
    // erneut versuchen, statt standesmäßig ohne KI einzureichen.
    final estimations = <AgeEstimation>[];
    Future<void> estimateSamples(List<Uint8List> samples) async {
      final svc = ref.read(ageEstimationServiceProvider);
      try {
        if (!await svc.ensureLoaded()) return;
        for (final bytes in samples) {
          try {
            final est = await svc
                .estimateAge(bytes)
                .timeout(const Duration(seconds: 10), onTimeout: () => null);
            if (est != null) estimations.add(est);
          } catch (e) {
            debugPrint('[Verification] Frame-Schätzung fehl: $e');
          }
          if (estimations.length >= 6) break;
        }
      } finally {
        // Modell-Speicher sofort wieder freigeben (ca. 82 MB, Akku/RAM).
        svc.release();
      }
    }

    Future<Uint8List?> captureSelfie() async {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return null;
      }
      try {
        final photo = await _cameraController!.takePicture();
        final bytes = await File(photo.path).readAsBytes();
        try {
          await File(photo.path).delete();
        } catch (_) {}
        return bytes;
      } catch (e) {
        debugPrint('[Verification] Selfie-Aufnahme 1. Versuch fehl: $e');
      }
      // Neuaufbau der Kamera + zweiter Versuch. Ein Fehlschlag der
      // Neuinitialisierung setzt _error (Fehler-Screen) - bei Erfolg
      // wird er unten wieder gelöscht, damit die Einreichung läuft.
      try {
        await _cameraController!.dispose();
      } catch (_) {}
      _cameraController = null;
      await _initializeCamera();
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return null;
      }
      try {
        final photo = await _cameraController!.takePicture();
        final bytes = await File(photo.path).readAsBytes();
        try {
          await File(photo.path).delete();
        } catch (_) {}
        // Re-Init hatte ggf. _error gesetzt (Fehler-Screen): Erfolg
        // heißt, die Kamera läuft - Flag zurücksetzen.
        if (mounted) setState(() => _error = null);
        return bytes;
      } catch (e) {
        debugPrint('[Verification] Selfie-Aufnahme 2. Versuch fehl: $e');
        return null;
      }
    }

    try {
      final selfie = await captureSelfie();
      final samples = <Uint8List>[...frames];
      if (selfie != null) samples.add(selfie);
      if (samples.isNotEmpty) {
        await estimateSamples(samples);
      }
    } catch (e) {
      debugPrint('[Verification] Altersschätzung übersprungen: $e');
    }

    final summary = AgeEstimationService.summarizeFrames(estimations);
    final median = summary?.medianAge;

    final statedAgeLocal = ref.read(profileProvider).age;
    // NUTZERWUNSCH "Verifizierung klappt nicht": Ist das Profil-Alter
    // (noch) nicht im State, holen wir es als Fallback vom Server
    // (get_public_profile liefert das Alter aus birth_date). Ohne
    // statedAge fiel die Auto-Triage STANDSMESSIG in die manuelle
    // Prüfung, auch wenn die KI-Abweichung längst ok war.
    var statedAge = statedAgeLocal;
    if (statedAge == null && SupabaseService.isInitialized) {
      try {
        final myId = SupabaseService.currentUser?.id;
        if (myId != null) {
          final row = await SupabaseService.client.rpc(
            'get_public_profile',
            params: {'p_user_id': myId},
          );
          if (row != null) {
            statedAge = ((row as Map)['age'] as num?)?.toInt();
          }
        }
      } catch (_) {}
    }
    final stated = statedAge;
    final autoOk =
        summary != null &&
        median != null &&
        stated != null &&
        summary.allSingleFace &&
        !AgeEstimationService.needsManualReview(
          estimatedAge: median,
          statedAge: stated,
          faceCount: 1,
        );

    bool done = false;
    String result = 'pending';
    if (autoOk) {
      // Play-Integrity-Attestierung (v0.9.0, nur Play-Builds):
      // best-effort, null auf F-Droid/iOS/Fehlern. Das Verdict prüft
      // der Server; hier wird nichts entschieden.
      final integrity = await PlayIntegrityService.requestToken();
      // KI-Triage unauffällig: sofortige Freigabe (Server prüft nach).
      done = await service.autoVerification(
        estimatedAge: median,
        faceCount: 1,
        deviation: (median - stated).abs(),
        integrityToken: integrity?.token,
        integrityNonce: integrity?.nonce,
      );
      if (done) result = 'auto';
    }
    if (!done) {
      // Manuelle Prüfung (Median-Abweichung > 2 Jahre, nicht in jedem
      // Frame genau ein Gesicht, zu wenige Frames, keine KI oder Auto
      // abgelehnt): Median als Orientierung mitsenden.
      done = await service.submitVerification(
        estimatedAge: median,
        faceCount: summary == null ? null : (summary.allSingleFace ? 1 : 0),
      );
      result = 'pending';
      // Diagnose für den Nutzer (Transparenz, warum manuell): Grund
      // cachen und auf dem Abschluss-Screen anzeigen.
      String? reasonKey;
      if (summary == null) {
        reasonKey = 'verify.pendingReason.noAi';
      } else if (!summary.allSingleFace) {
        reasonKey = 'verify.pendingReason.faces';
      } else if (stated == null) {
        reasonKey = 'verify.pendingReason.noStated';
      } else {
        reasonKey = 'verify.pendingReason.deviation';
      }
      ref.read(verificationPendingReasonProvider.notifier).state = reasonKey;
      ref.read(verificationDeviationProvider.notifier).state =
          (median != null && stated != null) ? (median - stated).abs() : null;
    }

    if (!mounted) return;
    if (done) {
      ref.read(verificationResultProvider.notifier).state = result;
      try {
        await ref
            .read(localStorageProvider)
            .saveBool(verificationSubmittedKey, true);
      } catch (_) {}
      if (!mounted) return;
      context.go(AppRoutes.verificationComplete);
    } else {
      // NUTZERWUNSCH "nur 'Einreichen fehlgeschlagen, bitte Internet...'":
      // Der ECHTE Grund der letzten Stufe wird angezeigt (kein Verlust
      // der Diagnose mehr).
      final detail = service.lastSubmitError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail == null || detail.isEmpty
                ? L10n.t(context, 'verify.submitFailed')
                : '${L10n.t(context, 'verify.submitFailed')}\n$detail',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 10),
        ),
      );
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'verify.title'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  L10n.t(context, 'verify.errorTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _initializeCamera,
                  child: Text(L10n.t(context, 'admin.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'verify.title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final challengeText = ref
        .read(verificationServiceProvider)
        .challengeDescription(context, _challengeType, _challengeData);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'verify.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _processing
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Challenge-Anzeige: Karte mit abgerundeten Ecken (Nutzerwunsch)
            // statt randloser Vollbreite-Block.
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.assignment,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        L10n.t(context, 'verify.taskTitle'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    challengeText,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Kamera-Vorschau: FittedBox(cover) füllt die Fläche OHNE
            // Verzerrung (leichtes Cropping an den Rändern statt Stauchung).
            // Das ist der Standard-Ansatz der camera-Package-Doku.
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width:
                            _cameraController!.value.previewSize?.height ?? 360,
                        height:
                            _cameraController!.value.previewSize?.width ?? 640,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                    // Aufnahme-Indikator: dezenter Pill/Chip oben mittig
                    if (_isRecording)
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _BlinkingDot(),
                                const SizedBox(width: 8),
                                Text(
                                  L10n.tf(context, 'verify.recording', {
                                    's': '$_recordSeconds',
                                  }),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Auswertung läuft: Spinner-Overlay
                    if (_processing)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    Text(L10n.t(context, 'verify.processing')),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Aufnahme-Button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (!_isRecording && _recordSeconds == 0)
                      Column(
                        children: [
                          Text(
                            L10n.t(context, 'verify.recordHint'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            L10n.t(context, 'verify.recordFaceHint'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          // KI-Transparenz (Nutzerwunsch): Die Altersprüfung
                          // läuft als On-Device-KI - kein Bild für die
                          // Schätzung verlässt das Gerät.
                          const SizedBox(height: 8),
                          const AiBadge.localCompact(),
                        ],
                      ),
                    const SizedBox(height: 16),
                    IgnorePointer(
                      ignoring: _processing,
                      child: Opacity(
                        opacity: _processing ? 0.4 : 1,
                        child: GestureDetector(
                          onTap: _toggleRecording,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_isRecording
                                              ? Colors.red
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary)
                                          .withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.videocam,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isRecording)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          L10n.t(context, 'verify.stopHint'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blinkender Aufnahme-Punkt (rec-Chip).
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
    );
  }
}

/// Erfolgs-Screen nach Verifizierung (v0.9.1: zwei Varianten).
class VerificationSuccessScreen extends ConsumerStatefulWidget {
  const VerificationSuccessScreen({super.key});

  @override
  ConsumerState<VerificationSuccessScreen> createState() =>
      _VerificationSuccessScreenState();
}

class _VerificationSuccessScreenState
    extends ConsumerState<VerificationSuccessScreen> {
  /// NUTZERWUNSCH: Nach der Video-Verifizierung daran erinnern, dass
  /// Standort, Kamera und Mikrofon wieder deaktiviert werden können -
  /// die Verifizierung ist fertig, die Zugriffe nicht mehr nötig.
  void _maybeOfferPrivacyCleanup() {
    Future<void>.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final open = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined, size: 40),
          title: Text(L10n.t(ctx, 'verify.cleanupTitle')),
          content: Text(L10n.t(ctx, 'verify.cleanupBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('later'),
              child: Text(L10n.t(ctx, 'verify.cleanupLater')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('location'),
              child: Text(L10n.t(ctx, 'verify.cleanupLocation')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('app'),
              child: Text(L10n.t(ctx, 'verify.cleanupOpen')),
            ),
          ],
        ),
      );
      if (!mounted || open == 'later') return;
      if (open == 'location') {
        try {
          await Geolocator.openLocationSettings();
        } catch (_) {}
      } else if (open == 'app' && mounted) {
        // Kamera + Mikrofon: App-Berechtigungsseite (beide abdrehbar).
        try {
          await openAppSettings();
        } catch (_) {}
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeOfferPrivacyCleanup();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 'auto' = KI-Triage unauffällig (Badge sofort), sonst manuelle
    // Prüfung durch den Support (Badge erst danach).
    final auto = ref.watch(verificationResultProvider) == 'auto';
    final reasonKey = ref.watch(verificationPendingReasonProvider);
    final deviation = ref.watch(verificationDeviationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'verify.doneTitle'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  auto ? Icons.verified : Icons.check_circle,
                  size: 64,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                auto
                    ? L10n.t(context, 'verify.autoTitle')
                    : L10n.t(context, 'verify.pendingTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                auto
                    ? L10n.t(context, 'verify.autoBody')
                    : L10n.t(context, 'verify.pendingBody'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              // Diagnose (NUTZERWUNSCH "Verifizierung klappt nicht"):
              // transparent, warum die KI-Triage in die manuelle Queue
              // gelegt hat - Abweichung / Gesichter / keine KI.
              if (!auto && reasonKey != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    deviation != null
                        ? L10n.tf(context, reasonKey, {
                            'years': deviation.round().toString(),
                          })
                        : L10n.t(context, reasonKey),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(L10n.t(context, 'verify.toApp')),
                onPressed: () => context.go(AppRoutes.home),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
