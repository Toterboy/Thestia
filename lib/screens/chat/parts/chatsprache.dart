// Die Methoden '_ChatSprache'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatSprache on _ChatDetailScreenState {
  /// Neues Aufnahme-Panel (v0.9.1): Karte mit Live-Dauer, Pegel-Balken,
  /// Pause/Fortsetzen, Verwerfen und Stoppen - analog zum IntroEditor,
  /// statt des alten Mic/X-Hint-Designs.
  Widget _buildVoiceRecordingPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liveColor = _paused ? scheme.onSurfaceVariant : scheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Card(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _paused ? Icons.pause_circle : Icons.radio_button_checked,
                    size: 18,
                    color: liveColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _paused
                        ? L10n.t(context, 'intro.pausedState')
                        : L10n.t(context, 'intro.recordingState'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: liveColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmtRecordSeconds(_recordSeconds),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (
                      var i = 0;
                      i < _ChatDetailScreenState._ampBarCount;
                      i++
                    )
                      Container(
                        width: 3.5,
                        height:
                            4.0 +
                            26.0 *
                                (_levels.length > i
                                    ? _levels[_levels.length - 1 - i]
                                    : 0.0),
                        decoration: BoxDecoration(
                          color:
                              (_levels.length > i
                                      ? _levels[_levels.length - 1 - i]
                                      : 0.0) <=
                                  0.01
                              ? liveColor.withValues(alpha: 0.25)
                              : liveColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _cancelRecording,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: L10n.t(context, 'chat.voiceCancel'),
                    color: scheme.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pauseResumeRecording,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                      label: Text(
                        _paused
                            ? L10n.t(context, 'intro.resume')
                            : L10n.t(context, 'intro.pause'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggleRecord,
                      icon: const Icon(Icons.stop),
                      label: Text(L10n.t(context, 'intro.stopListen')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// D: Bricht eine laufende Sprachaufnahme ab - es wird NICHTS gesendet
  /// und die temporäre Datei gelöscht.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    // Das cancel()-Future ist asynchron: ein Back-Navigieren im selben
    // Frame wuerde das folgende setState crashen.
    if (!mounted) return;
    _ampSub = null;
    final path = _recordingPath;
    _setzeState(() {
      _recording = false;
      _paused = false;
      _recordSeconds = 0;
      _recordingPath = null;
      _levels.clear();
    });
    await bestEffort('delete', () async {
      await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'chat.voiceCancelled'))),
      );
    }
  }

  /// Entfernt eine wiedergegebene Voice-Datei sofort (Audit M-17).
  Future<void> _deleteVoiceFile(String? path) async {
    if (path == null) return;
    // Best-effort: Der globale Sweep (temp_cleanup) entfernt Reste.
    await bestEffort('remove', () async {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      _voiceTempFiles.remove(path);
    });
  }

  String _fmtRecordSeconds(int s) {
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  /// Lautstärke für die Live-Visualisierung (neues Design, wie IntroEditor):
  /// dBFS (-60..0) auf 0..1 normieren.
  void _onChatAmplitude(Amplitude amp) {
    if (!mounted || !_recording || _paused) return;
    final db = amp.current.clamp(-60.0, 0.0);
    final level = ((db + 60) / 60).clamp(0.0, 1.0);
    _setzeState(() {
      _levels.add(level);
      while (_levels.length > _ChatDetailScreenState._ampBarCount) {
        _levels.removeAt(0);
      }
    });
  }

  /// Pause/Fortsetzen während der Sprachaufnahme (neues Design).
  Future<void> _pauseResumeRecording() async {
    if (!_recording) return;
    try {
      if (_paused) {
        await _audioRecorder.resume();
        if (mounted) _setzeState(() => _paused = false);
      } else {
        await _audioRecorder.pause();
        if (mounted) _setzeState(() => _paused = true);
      }
    } catch (e) {
      debugPrint('[ChatDetail] Pause/Resume fehlgeschlagen: $e');
    }
  }

  void _startChatTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      _setzeState(() => _recordSeconds++);
      if (_recordSeconds >= _ChatDetailScreenState._maxVoiceSeconds) {
        _toggleRecord();
      }
    });
  }

  /// D: Sprachaufnahme starten/beenden mit [AudioRecorder].
  ///
  /// Aufnahme als .m4a (AAC), dann Bytes E2E-verschlüsselt via
  /// `_p2p!.sendBinary()` senden. Löscht die temporäre Datei nach
  /// erfolgreichem Senden.
  ///
  /// Mindestlänge: 1 Sekunde (versehentliche Ultra-Kurz-Aufnahmen
  /// werden verworfen). Neues Design (v0.9.1): Live-Dauer +
  /// Lautstärke-Balken + Pause/Fortsetzen, wie im IntroEditor.
  Future<void> _toggleRecord() async {
    if (_recording) {
      _recordTimer?.cancel();
      await _ampSub?.cancel();
      // Siehe _cancelRecording: nach dem asynchronen cancel() kann der
      // Screen bereits disposed sein.
      if (!mounted) return;
      _ampSub = null;

      // WICHTIG: Sekunden VOR dem Reset sichern – vorher stand der Reset
      // vor der Prüfung, sodass jede Aufnahme als "unter 1 Sekunde"
      // verworfen wurde (Sprachnachrichten kamen nie durch).
      final seconds = _recordSeconds;

      // Aufnahme beenden.
      final path = _recordingPath;
      _setzeState(() {
        _recording = false;
        _paused = false;
        _recordSeconds = 0;
        _recordingPath = null;
        _levels.clear();
      });

      if (path == null) return;

      try {
        // Aufnahme stoppen (schreibt die Datei final) und Bytes lesen.
        final recordedPath = await _audioRecorder.stop();
        final effectivePath = recordedPath ?? path;
        final file = File(effectivePath);
        final exists = await file.exists();
        if (!exists) return;

        // Mindestlänge prüfen (mit der gesicherten, echten Dauer).
        if (seconds < 1) {
          await file.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(L10n.t(context, 'chat.voiceTooShort'))),
            );
          }
          return;
        }

        // Anhören vor dem Senden: Review-Sheet mit Player. Erst nach
        // Bestätigung wird die Nachricht (E2E-verschlüsselt) gesendet.
        if (!mounted) {
          await file.delete();
          return;
        }
        final send = await showAudioReviewSheet(
          context: context,
          path: effectivePath,
          durationSeconds: seconds,
          minimumSeconds: 1,
          confirmLabel: L10n.t(context, 'intro.review.send'),
        );
        if (send != true) {
          await file.delete();
          return;
        }

        final bytes = await file.readAsBytes();

        final match = _match;
        if (match == null) {
          await file.delete();
          return;
        }

        // E2E-verschlüsselt via P2P-DataChannel senden (inkl. Duration).
        await _p2p?.sendBinary(
          Uint8List.fromList(bytes),
          contentType: 'audio/m4a',
          metadata: {'durationSeconds': seconds},
        );

        // Lokale Vorschau anzeigen.
        final localMsg = Message(
          id: Message.newId('local_voice'),
          senderId: _myUserId ?? AppConstants.currentUserId,
          receiverId: match.partner.id,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: effectivePath,
          durationSeconds: seconds,
          type: MessageType.voice,
        );
        ref
            .read(chatProvider.notifier)
            .addMessage(match.id, localMsg, ref: ref);
        // BEFUND (16.11.2026, gefunden von einem Test): Hier stand kein
        // Neuaufbau - die aufgenommene Nachricht war erst zu sehen,
        // wenn der Bildschirm aus einem anderen Grund neu gebaut wurde
        // (Relay-Timer, Verbindungsstatus). Der Nutzer dachte, seine
        // Sprachnachricht sei nicht angekommen, und hat sie noch einmal
        // aufgenommen. Beim Text ist es seit dem 13.11.2026 genauso
        // (siehe _send) - jetzt auch hier.
        if (mounted) _setzeState(() {});
        if (mounted && !_p2pConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'chat.queuedHint')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Temporäre Datei NICHT löschen: die Nachricht referenziert den
        // Pfad, damit sie lokal angehört werden kann.
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'chat.voiceRecordFailed', {'error': '$e'}),
              ),
            ),
          );
        }
      }
    } else {
      // Aufnahme starten.
      try {
        // PROMINENTE OFFENLEGUNG (Google-Play-Richtlinie fuer Mikrofon):
        // Bevor ueberhaupt der Systemdialog erscheint, muss in der App
        // erklaert werden, WARUM aufgenommen wird. Vorher stand hier nur
        // eine hasPermission()-Pruefung; die Berechtigung fragte das
        // Plugin an, ohne dass die App vorher etwas sagte. Play verlangt
        // fuer RECORD_AUDIO eine sichtbare Begruendung UND die Anfrage
        // im Kontext der Funktion - ohne das gibt die Abnahme nicht.
        //
        // Die Offenlegung wird nur einmal gezeigt (der Nutzer kann sie
        // im Verlauf nicht wiederholen muessen); danach fragt der
        // Systemdialog. Bei Ablehnung wird nichts aufgenommen.
        if (!await _ensureMicDisclosure()) return;

        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(L10n.t(context, 'intro.micDenied'))),
            );
          }
          return;
        }

        final dir = Directory.systemTemp;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/thestia_voice_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 48000,
          ),
          path: path,
        );

        // Mikrofon-Permission + Start dauern real mehrere Hundert ms. Ein
        // Back-Navigieren in dieser Zeit wuerde das setState crashen.
        if (!mounted) {
          await _audioRecorder.stop();
          return;
        }

        _setzeState(() {
          _recording = true;
          _paused = false;
          _recordSeconds = 0;
          _recordingPath = path;
          _levels.clear();
        });
        _ampSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen(_onChatAmplitude);
        _startChatTimer();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'chat.voiceStartFailed', {'error': '$e'}),
              ),
            ),
          );
        }
      }
    }
  }

  /// Schreibt empfangene Voice-Bytes in eine temporäre Datei.
  ///
  /// Audit M-17: Der Pfad wird zusätzlich in [_voiceTempFiles] registriert;
  /// die Datei wird nach der Wiedergabe bzw. beim Verlassen des Chats
  /// gelöscht (entschlüsselte Sprache darf nicht akkumulierend im Temp-
  /// Verzeichnis liegen).
  Future<String?> _writeVoiceFile(String msgId, Uint8List data) async {
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/thestia_incoming_$msgId.m4a';
      await File(path).writeAsBytes(data);
      _voiceTempFiles.add(path);
      return path;
    } catch (e) {
      debugPrint(
        '[ChatDetail] Voice-Datei konnte nicht geschrieben werden: $e',
      );
      return null;
    }
  }
}
