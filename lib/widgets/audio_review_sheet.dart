import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'package:wisp/l10n/app_strings.dart';

/// Zeigt eine aufgezeichnete Audio-Datei zum ANHÖREN an, bevor sie
/// gesendet/verwendet wird ("Anhören" vor "Senden").
///
/// Liefert `true`, wenn der Nutzer "Senden"/"Verwenden" bestätigt hat,
/// `false`/`null` bei "Verwerfen" oder Abbruch. Die Datei selbst wird
/// hier NICHT gelöscht – der Aufrufer entscheidet über das Schicksal
/// der Datei.
Future<bool?> showAudioReviewSheet({
  required BuildContext context,
  required String path,
  required int durationSeconds,
  int minimumSeconds = 1,
  String? confirmLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AudioReviewSheet(
      path: path,
      durationSeconds: durationSeconds,
      minimumSeconds: minimumSeconds,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AudioReviewSheet extends StatefulWidget {
  const _AudioReviewSheet({
    required this.path,
    required this.durationSeconds,
    required this.minimumSeconds,
    required this.confirmLabel,
  });

  final String path;
  final int durationSeconds;
  final int minimumSeconds;
  final String? confirmLabel;

  @override
  State<_AudioReviewSheet> createState() => _AudioReviewSheetState();
}

class _AudioReviewSheetState extends State<_AudioReviewSheet> {
  AudioPlayer? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _audioLength = Duration.zero;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setFilePath(widget.path);
      player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _audioLength = d);
      });
      player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      player.playerStateStream.listen((s) {
        if (!mounted) return;
        if (s.playing != _playing) setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      debugPrint('[AudioReviewSheet] Vorschau nicht abspielbar: $e');
      if (mounted) {
        setState(() => _loadError = L10n.t(context, 'intro.review.loadError'));
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tooShort = widget.durationSeconds < widget.minimumSeconds;
    final total =
        _audioLength > Duration.zero ? _audioLength : const Duration();
    final progress = total.inMilliseconds > 0
        ? _position.inMilliseconds / total.inMilliseconds
        : 0.0;
    final scheme = Theme.of(context).colorScheme;

    final lengthText = tooShort
        ? L10n.tf(context, 'intro.review.lengthMin', {
            'length': _fmt(Duration(seconds: widget.durationSeconds)),
            'min': '${widget.minimumSeconds}',
          })
        : L10n.tf(context, 'intro.review.length', {
            'length': _fmt(Duration(seconds: widget.durationSeconds)),
          });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L10n.t(context, 'intro.review.title'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              lengthText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tooShort ? scheme.error : scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              Text(
                _loadError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            // Play-Button optisch auf Höhe des Fortschrittbalkens: Die
            // Zeile startet oben bündig, die Fortschrittspalte bekommt
            // oben (Buttonhöhe 40 - Balkenhöhe 4) / 2 Platz, damit beide
            // Mitten übereinanderliegen (statt Button mittig zur
            // Gesamtspalte aus Balken + Zeitlabels).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filled(
                  onPressed: _loadError != null
                      ? null
                      : () {
                          if (_playing) {
                            _player?.pause();
                          } else {
                            _player?.play();
                          }
                        },
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  tooltip: _playing
                      ? L10n.t(context, 'intro.review.pause')
                      : L10n.t(context, 'intro.review.listen'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_position)),
                            Text(_fmt(total)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (tooShort) ...[
              Text(
                L10n.tf(context, 'intro.review.tooShort',
                    {'min': '${widget.minimumSeconds}'}),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.refresh),
                label: Text(L10n.t(context, 'intro.review.rerecord')),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check),
                label: Text(widget.confirmLabel ??
                    L10n.t(context, 'intro.review.send')),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.delete_outline),
                label: Text(L10n.t(context, 'intro.review.discard')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
