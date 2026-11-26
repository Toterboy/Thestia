// Der Teil '_VerificationVideoScreenState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../verification_flow.dart';

class _VerificationVideoScreenState
    extends ConsumerState<VerificationVideoScreen>
    with WidgetsBindingObserver {
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
    // NUTZERWUNSCH (01.11.2026): "Die App laggt extrem, wenn ich die
    // Videörifizierung mache" und "soll die Kamera weg, um Ressourcen
    // zu sparen".
    //
    // Ohne Lifecycle-Behandlung bleibt die Kamera offen, wenn der
    // Nutzer die App während der Aufnahme in den Hintergrund
    // schaltet: der Preview-Texture lebt weiter, der Sensor bleibt
    // belegt. Die camera-Doku verlangt dispose() bei inactive und
    // einen Neuaufbau bei resumed.
    WidgetsBinding.instance.addObserver(this);
    _generateChallenge();
    // Kamera erst NACH der Offenlegung öffnen - siehe _initializeCamera.
    //
    // Das Holen des ersten Frames ist zugleich der Grund, warum das
    // überhaupt nötig war: in initState hat der Context noch keinen
    // Frame, ein Dialog kann dort nicht zuverlässig stehen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureCameraDisclosureThenOpen());
    });
  }

  /// Zeigt die prominente Kamera-Offenlegung und öffnet danach die
  /// Kamera.
  ///
  /// Google Play verlangt für CAMERA dieselbe vorangezeigte
  /// Begründung wie für das Mikrofon: die App muss erklären, warum
  /// sie aufnimmt bzw. filmt, BEVOR der Systemdialog erscheint.
  /// Gerade dieser Schritt öffnete die Kamera bislang sofort beim
  /// Betreten - der Nutzer sah den Kamera-Dialog, ohne vorher zu
  /// erfahren, worum es ging.
  ///
  /// Ohne Kamera ist die Verifikation nicht möglich, deshalb endet der
  /// Dialog mit einer Ablehnung in einem erklärenden Zustand statt in
  /// einem Absturz: der bestehende Fehlerpfad zeigt den Grund an.
  Future<void> _ensureCameraDisclosureThenOpen() async {
    final settings = ref.read(settingsProvider);
    if (!settings.cameraDisclosureAccepted) {
      final accepted = await _askCameraDisclosure();
      if (accepted != true || !mounted) {
        if (mounted) {
          setState(() => _error = L10n.t(context, 'verify.cameraDeclined'));
        }
        return;
      }
      // Beide Flaggen setzen, nicht nur die Kamera: der Dialog hat oben
      // ausdrücklich für Kamera UND Mikrofon gewarnt, weil die
      // Aufnahme mit enableAudio läuft. Wer hier bestätigt, weiß
      // also beides und soll im Chat nicht denselben Hinweis nochmal
      // bekommen. Das Mikrofon-Flag bleibt ansonsten unberührt - wer
      // nur verifiziert und nie chattet, sieht den Hinweis später
      // genau dann, wenn er ihn braucht.
      await ref
          .read(settingsProvider.notifier)
          .setCameraDisclosureAccepted(true);
      await ref.read(settingsProvider.notifier).setMicDisclosureAccepted(true);
    }
    await _initializeCamera();
  }

  Future<bool?> _askCameraDisclosure() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(L10n.t(context, 'verify.cameraDisclosureTitle')),
      content: Text(L10n.t(context, 'verify.cameraDisclosureBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(L10n.t(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(L10n.t(context, 'verify.cameraDisclosureAccept')),
        ),
      ],
    ),
  );

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
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    final controller = _cameraController;
    _cameraController = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Die Kamera bei inactive/paused freigeben und bei resumed neu
    // aufbauen. Das camera-Plugin verlangt das ausdrücklich: ein
    // weiterlaufender Preview-Texture im Hintergrund kostet Akku und
    // hält den Sensor belegt.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_isRecording) {
        unawaited(_kameraFreigeben());
      }
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _cameraController == null &&
        !_processing &&
        _error == null) {
      unawaited(_initializeCamera());
    }
  }

  /// Gibt die Kamera frei: Preview-Texture, Sensor und Akku.
  ///
  /// NUTZERWUNSCH (01.11.2026): "Wenn es verifiziert wird, nach der
  /// Aufnahme, soll die Kamera weg, um Ressourcen zu sparen."
  ///
  /// Vorher lief die Kamera während der kompletten Nachbearbeitung
  /// weiter - Frames entnehmen, KI-Schätzung, Upload. Das sind
  /// mehrere Sekunden, in denen die Kamera ohne Zweck offen war.
  Future<void> _kameraFreigeben() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) return;
    // Beim Freigeben darf nichts werfen - der Aufrufer ist im
    // catch-Block einer Fehlerbehandlung.
    await bestEffort('dispose', () async {
      await controller.dispose();
    });
    if (mounted) setState(() {});
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
      // PARALLEL (NUTZERWUNSCH 01.11.2026): "Die App laggt extrem,
      // wenn ich die Videörifizierung mache."
      //
      // Vorher wurden die fünf Thumbnails NACHEINANDER entnommen. Das
      // Plugin dekodiert auf Android ein voll aufgelöstes Frame und
      // komprimiert es neu - pro Frame einige hundert Millisekunden.
      // Fünf mal hintereinander war einer der längsten Einzelposten
      // der gesamten Verifizierung.
      //
      // Das Plugin arbeitet mit einem Thread-Pool
      // (Executors.newCachedThreadPool) - parallele Aufrufe sind also
      // sicher. Die Reihenfolge der Ergebnisse bleibt erhalten
      // (Future.wait liefert sie in der Reihenfolge der Futures), der
      // Median rechnet also mit denselben Werten wie vorher.
      final zeitpunkte = AgeEstimationService.verificationFrameTimeMs;
      final ergebnisse = await Future.wait(
        zeitpunkte.map((ms) async {
          try {
            final Uint8List? bytes = await thumb.VideoThumbnail.thumbnailData(
              video: videoPath,
              imageFormat: thumb.ImageFormat.JPEG,
              maxWidth: 480,
              quality: 80,
              timeMs: ms,
            ).timeout(const Duration(seconds: 10), onTimeout: () => null);
            return bytes;
          } catch (e) {
            debugPrint('[Verification] Frame @$ms ms übersprungen: $e');
            return null;
          }
        }),
      );
      return ergebnisse
          .whereType<Uint8List>()
          .where((bytes) => bytes.isNotEmpty)
          .toList();
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
        await bestEffort('File.delete', () async {
          await File(photo.path).delete();
        });
        return bytes;
      } catch (e) {
        debugPrint('[Verification] Selfie-Aufnahme 1. Versuch fehl: $e');
      }
      // Neuaufbau der Kamera + zweiter Versuch. Ein Fehlschlag der
      // Neuinitialisierung setzt _error (Fehler-Screen) - bei Erfolg
      // wird er unten wieder gelöscht, damit die Einreichung läuft.
      await bestEffort('dispose', () async {
        await _cameraController!.dispose();
      });
      _cameraController = null;
      await _initializeCamera();
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return null;
      }
      try {
        final photo = await _cameraController!.takePicture();
        final bytes = await File(photo.path).readAsBytes();
        await bestEffort('File.delete', () async {
          await File(photo.path).delete();
        });
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

      // Die Kamera wird ab hier nicht mehr gebraucht: die Aufnahme ist
      // zu Ende und das Selfie ist geholt. Sie hier freizugeben spart
      // Akku, schont die Sensoren und beendet den Preview-Texture -
      // vorher lief die Kamera während der kompletten Auswertung
      // (Frames, KI-Schätzung, Upload) weiter.
      await _kameraFreigeben();

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
      await bestEffort('toInt', () async {
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
      });
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
      await bestEffort('localStorageProvider.saveBool', () async {
        await ref
            .read(localStorageProvider)
            .saveBool(verificationSubmittedKey, true);
      });
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
                    // Nach der Aufnahme wird die Kamera freigegeben -
                    // dann gibt es keinen Preview mehr. Der schwarze
                    // Hintergrund ist der Hintergrund des
                    // Verarbeitungs-Hinweises darüber.
                    if (_cameraController != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width:
                              _cameraController!.value.previewSize?.height ??
                              360,
                          height:
                              _cameraController!.value.previewSize?.width ??
                              640,
                          child: CameraPreview(_cameraController!),
                        ),
                      )
                    else
                      const ColoredBox(color: Colors.black),
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
