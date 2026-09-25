import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/widgets/audio_review_sheet.dart';

/// Editor für die eigene Vorstellung ("Find your Match"): Text + Audio.
///
/// Selbstständig für Aufnahme/Upload/Entfernen der Audio-Datei zuständig.
/// Meldet jede Änderung über [onChanged] an den Parent, der die Werte
/// speichert.
///
/// Audio-Flow (Recorder-UX): Während der Aufnahme zeigt die Karte
/// Dauer + Lautstärke-Visualisierung (Amplituden-Balken) und erlaubt
/// Pause/Fortsetzen, Verwerfen und Stoppen. Nach dem Stoppen bleibt die
/// Aufnahme lokal erhalten und wird über ein Review-Sheet erst ANGEHÖRT
/// ([showAudioReviewSheet]) – erst nach Bestätigung erfolgt der Upload
/// ("Senden"). Mindestlänge 10 Sekunden ([minAudioSeconds]), Maximum
/// 5 Minuten / 300 Sekunden (Auto-Stopp).
///
/// Ist [required] false (z. B. in der Erst-Einrichtung), sind Text und
/// Audio freiwillige Angaben und der Pflicht-Hinweis entfällt.
class IntroEditor extends ConsumerStatefulWidget {
  const IntroEditor({
    required this.initialText,
    required this.initialAudioPath,
    required this.onChanged,
    super.key,
    this.required = true,
  });

  final String initialText;
  final String? initialAudioPath;
  final void Function(String text, String? audioPath) onChanged;
  final bool required;

  @override
  ConsumerState<IntroEditor> createState() => _IntroEditorState();

  /// True, wenn beide Pflichtangaben vorhanden sind.
  static bool isValid({required String text, String? audioPath}) =>
      text.trim().isNotEmpty && audioPath != null;

  /// Mindestlänge der Audio-Vorstellung in Sekunden.
  static const int minAudioSeconds = 10;

  /// Maximale Länge der Audio-Vorstellung in Sekunden (Auto-Stopp = 5 Min).
  static const int maxAudioSeconds = 300;

  /// Anzahl der Balken der Lautstärke-Visualisierung (Fenster ~3 s).
  static const int ampBarCount = 28;

  /// Abfrage-Intervall der Amplitude (ms).
  static const int ampIntervalMs = 100;
}

class _IntroEditorState extends ConsumerState<IntroEditor> {
  late final TextEditingController _textCtrl;
  final AudioRecorder _recorder = AudioRecorder();

  String? _audioPath;
  bool _recording = false;
  bool _paused = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _audioPath = widget.initialAudioPath;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _textCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Aufnahme-Steuerung (Start / Pause-Fortsetzen / Stop / Verwerfen)
  // ---------------------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'intro.micDenied')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final dir = Directory.systemTemp;
      final path =
          '${dir.path}/thestia_intro_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 48000,
        ),
        path: path,
      );
      setState(() {
        _recording = true;
        _paused = false;
        _recordSeconds = 0;
      });
      _startTimer();
    } catch (e) {
      debugPrint('[IntroEditor] Start fehlgeschlagen: $e');
    }
  }

  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_paused) return; // Pause zählt nicht zur Dauer.
      setState(() => _recordSeconds++);
      if (_recordSeconds >= IntroEditor.maxAudioSeconds) {
        _stopRecording();
      }
    });
  }

  Future<void> _pauseResume() async {
    if (!_recording) return;
    try {
      if (_paused) {
        await _recorder.resume();
        if (mounted) setState(() => _paused = false);
        _startTimer();
      } else {
        await _recorder.pause();
        _recordTimer?.cancel();
        if (mounted) setState(() => _paused = true);
      }
    } catch (e) {
      debugPrint('[IntroEditor] Pause/Resume fehlgeschlagen: $e');
    }
  }

  /// Stoppen -> Review-Sheet (Anhören) -> Senden (Upload).
  Future<void> _stopRecording() async {
    if (!_recording) return;
    // WICHTIG: Die Sekunden VOR dem Reset sichern – vorher stand der
    // Reset vor der Prüfung, sodass JEDE Aufnahme (auch 40 s) als
    // "unter 1 Sekunde" verworfen wurde.
    final seconds = _recordSeconds;
    _recordTimer?.cancel();
    setState(() {
      _recording = false;
      _paused = false;
      _recordSeconds = 0;
      _uploading = true;
    });
    try {
      final recordedPath = await _recorder.stop();
      if (recordedPath == null) {
        setState(() => _uploading = false);
        return;
      }
      final file = File(recordedPath);
      if (!mounted) {
        if (await file.exists()) await file.delete();
        return;
      }

      // Anhören vor dem Verwenden: Review-Sheet zeigt Player, Länge
      // und (bei Unterschreitung) die Mindestlänge. Nur bei expliziter
      // Bestätigung wird hochgeladen.
      final use = await showAudioReviewSheet(
        context: context,
        path: recordedPath,
        durationSeconds: seconds,
        minimumSeconds: IntroEditor.minAudioSeconds,
        confirmLabel: L10n.t(context, 'intro.review.confirm'),
      );
      if (use != true) {
        if (await file.exists()) await file.delete();
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final bytes = await file.readAsBytes();
      await file.delete();

      final storage = ref.read(supabaseStorageServiceProvider);
      final uploadedPath = await storage.uploadIntroAudio(bytes);
      if (!mounted) return;
      setState(() {
        _audioPath = uploadedPath;
        _uploading = false;
      });
      widget.onChanged(_textCtrl.text, _audioPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'intro.saved')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[IntroEditor] Aufnahme fehlgeschlagen: $e');
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(L10n.tf(context, 'intro.recordFailed', {'error': '$e'})),
          ),
        );
      }
    }
    return;
  }

  /// Laufende Aufnahme verwerfen (nach Rückfrage).
  Future<void> _discardRecording() async {
    final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t(ctx, 'intro.discardTitle')),
            content: Text(L10n.t(ctx, 'intro.discardBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'intro.discardKeep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'intro.discard')),
              ),
            ],
          ),
        ) ??
        false;
    if (!discard || !_recording) return;
    _recordTimer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[IntroEditor] Verwerfen fehlgeschlagen: $e');
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _paused = false;
        _recordSeconds = 0;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Gespeicherte Audio-Vorstellung
  // ---------------------------------------------------------------------

  Future<void> _deleteAudio() async {
    final delete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t(ctx, 'intro.deleteTitle')),
            content: Text(L10n.t(ctx, 'intro.deleteBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'intro.discardKeep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'intro.delete')),
              ),
            ],
          ),
        ) ??
        false;
    if (!delete) return;
    try {
      final storage = ref.read(supabaseStorageServiceProvider);
      await storage.deleteIntroAudio();
      if (!mounted) return;
      setState(() => _audioPath = null);
      widget.onChanged(_textCtrl.text, null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'intro.removed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[IntroEditor] Löschen fehlgeschlagen: $e');
    }
  }

  String _fmtSeconds(int s) {
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          L10n.t(context, 'intro.title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          widget.required
              ? L10n.t(context, 'intro.hintRequired')
              : L10n.t(context, 'intro.hintOptional'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _textCtrl,
          maxLines: 4,
          maxLength: 500,
          keyboardType: TextInputType.text,
          // Weit oben über der Tastatur halten, damit man beim Tippen
          // alle vier Zeilen lesen kann (Standard wäre nur 20 px).
          scrollPadding: const EdgeInsets.only(bottom: 180),
          decoration: InputDecoration(
            labelText: widget.required
                ? L10n.t(context, 'intro.textRequired')
                : L10n.t(context, 'intro.text'),
            hintText: L10n.t(context, 'intro.textHint'),
          ),
          onChanged: (_) => widget.onChanged(_textCtrl.text, _audioPath),
        ),
        // Fragenbasierte Einstiegshilfe (Nutzerwunsch "Einführungsscreen
        // fragenbasiert"): Leitfragen als Chips - Antippen hängt die
        // Frage als Starthilfe an den Text an.
        const SizedBox(height: 8),
        Text(
          L10n.t(context, 'intro.promptTitle'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in const [
              'intro.prompt.weekend',
              'intro.prompt.friends',
              'intro.prompt.laugh',
              'intro.prompt.dream',
            ])
              ActionChip(
                label: Text(L10n.t(context, key)),
                onPressed: () {
                  final q = L10n.t(context, key);
                  final cur = _textCtrl.text.trimRight();
                  final sep = cur.isEmpty ? '' : '\n';
                  _textCtrl.text = '$cur$sep$q ';
                  _textCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _textCtrl.text.length),
                  );
                  widget.onChanged(_textCtrl.text, _audioPath);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _recording ? _buildRecordingUI() : _buildIdleUI(),
          ),
        ),
      ],
    );
  }

  /// UI während der Aufnahme: Live-Dauer, Lautstärke-Balken, Pause/Stop.
  Widget _buildRecordingUI() {
    final scheme = Theme.of(context).colorScheme;
    final liveColor = _paused ? scheme.onSurfaceVariant : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(_paused ? Icons.pause_circle : Icons.radio_button_checked,
                size: 18, color: _paused ? scheme.onSurfaceVariant : scheme.error),
            const SizedBox(width: 8),
            Text(
              _paused
                  ? L10n.t(context, 'intro.pausedState')
                  : L10n.t(context, 'intro.recordingState'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _paused
                        ? scheme.onSurfaceVariant
                        : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Text(
              _fmtSeconds(_recordSeconds),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Lautstärke-Balken als EIGENES Widget: Die 10-Hz-Amplitude baut
        // sonst bei jedem Wert den kompletten Editor (Textfeld + Chips +
        // Karte) neu - auf schwachen Geräten sichtbares Ruckeln während
        // der Aufnahme. Jetzt rendert nur die Balken-Reihe neu.
        _AmplitudeBars(
          recorder: _recorder,
          active: _recording && !_paused,
          color: liveColor,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: _discardRecording,
              icon: const Icon(Icons.delete_outline),
              tooltip: L10n.t(context, 'intro.discard'),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pauseResume,
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused
                    ? L10n.t(context, 'intro.resume')
                    : L10n.t(context, 'intro.pause')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _stopRecording,
                icon: const Icon(Icons.stop),
                label: Text(L10n.t(context, 'intro.stopListen')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// UI im Ruhezustand: Aufnehmen / neu aufnehmen + Löschen.
  Widget _buildIdleUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.required
              ? L10n.t(context, 'intro.audioTitleRequired')
              : L10n.t(context, 'intro.audioTitle'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          _audioPath != null
              ? L10n.t(context, 'intro.savedState')
              : L10n.t(context, 'profile.intro.audioEmpty'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          L10n.tf(
            context,
            'intro.rangeHint',
            {
              'min': '${IntroEditor.minAudioSeconds}',
              'max': '${IntroEditor.maxAudioSeconds}',
            },
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _startRecording,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic),
                label: Text(
                  _audioPath != null
                      ? L10n.t(context, 'intro.rerecord')
                      : L10n.t(context, 'intro.record'),
                ),
              ),
            ),
            if (_audioPath != null) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: L10n.t(context, 'intro.deleteTooltip'),
                onPressed: _uploading ? null : _deleteAudio,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Lautstärke-Balken mit eigenem State: Abonniert die Recorder-Amplitude
/// (10 Hz) und baut NUR die Balken-Reihe neu - der Rest des Editors
/// (Textfeld mit Fokus!) bleibt unberührt.
class _AmplitudeBars extends StatefulWidget {
  const _AmplitudeBars({
    required this.recorder,
    required this.active,
    required this.color,
  });

  final AudioRecorder recorder;
  final bool active;
  final Color color;

  @override
  State<_AmplitudeBars> createState() => _AmplitudeBarsState();
}

class _AmplitudeBarsState extends State<_AmplitudeBars> {
  StreamSubscription<Amplitude>? _sub;

  /// Die letzten Amplituden-Level (0..1), spiegelbildlich dargestellt.
  final List<double> _levels = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _AmplitudeBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _subscribe();
      } else {
        _unsubscribe();
      }
    }
  }

  void _subscribe() {
    _unsubscribe();
    if (!widget.active) return;
    _sub = widget.recorder
        .onAmplitudeChanged(
            const Duration(milliseconds: IntroEditor.ampIntervalMs))
        .listen((amp) {
      if (!mounted) return;
      // dBFS (-60..0) auf 0..1 normieren.
      final db = amp.current.clamp(-60.0, 0.0);
      setState(() {
        _levels.add(((db + 60) / 60).clamp(0.0, 1.0));
        while (_levels.length > IntroEditor.ampBarCount) {
          _levels.removeAt(0);
        }
      });
    });
  }

  void _unsubscribe() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < IntroEditor.ampBarCount; i++)
            _AmpBar(
              level: _levels.length > i
                  ? _levels[_levels.length - 1 - i]
                  : 0.0,
              color: widget.color,
            ),
        ],
      ),
    );
  }
}

/// Ein Balken der Lautstärke-Visualisierung (0..1 -> 4..40 px Höhe).
class _AmpBar extends StatelessWidget {
  const _AmpBar({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final h = 4.0 + 36.0 * level.clamp(0.0, 1.0);
    return Container(
      width: 3.5,
      height: h,
      decoration: BoxDecoration(
        color: level <= 0.01
            ? color.withValues(alpha: 0.25)
            : color.withValues(alpha: 0.35 + 0.65 * level),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
