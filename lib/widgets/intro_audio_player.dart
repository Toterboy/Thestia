import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/utils/best_effort.dart';

/// Wiedergabe der Audio-Vorstellung eines Nutzers.
///
/// Holt eine signierte URL über die match-media-Edge-Function (serverseitige
/// Berechtigungsprüfung) und spielt sie mit just_audio ab.
class IntroAudioPlayer extends ConsumerStatefulWidget {
  const IntroAudioPlayer({required this.targetUserId, super.key});

  final String targetUserId;

  @override
  ConsumerState<IntroAudioPlayer> createState() => _IntroAudioPlayerState();
}

class _IntroAudioPlayerState extends ConsumerState<IntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  String? _errorKey;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  /// Die Position in der Aufnahme (der Balken).
  Duration _position = Duration.zero;

  /// Die Gesamtdauer der Aufnahme.
  Duration? _duration;

  /// Wie breit der Balken wird (px).
  static const double _balkenBreite = 116;

  /// Die Zeit als m:ss (die Vorstellungen sind kurz, aber eine
  /// Vorstellung darf auch eine Minute dauern).
  static String _zeit(Duration d) {
    final s = d.inSeconds.clamp(0, 3599);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Wie lange darf das Laden der Vorstellung dauern?
  ///
  /// BEFUND (07.11.2026, Betreiber): "Vorstellung von anderen nicht
  /// abhoerbar. Sie laedt nicht oder braucht seeeeeeehr lange."
  ///
  /// DER GRUND (zwei Fehler in diesem Widget):
  ///
  ///  1) `await _player.play()` wartet, BIS DIE AUFNAHME ZUENDE IST.
  ///     just_audio liefert das Future von `play()` erst fertig, wenn
  ///     die Wiedergabe durchgelaufen ist. Die ganze Abspielzeit blieb
  ///     der Lade-Spinner stehen - die App sah aus, als laede sie noch.
  ///
  ///  2) Es gab keinen Zeitlimit. Haengt das Netz (oder die
  ///     Edge-Function), blieb der Spinner fuer immer stehen - ohne
  ///     jede Meldung.
  ///
  /// Beides ist behoben: `play()` wird nicht mehr abgewartet, und das
  /// Laden hat ein Zeitlimit mit einer verstaendlichen Meldung.
  static const Duration _ladeTimeout = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    // Der Zustands-Listener wird VOR dem Abspielen gesetzt, damit das
    // Ende der Aufnahme zuverlaessig zurueckgemeldet wird.
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });

    // BEFUND (09.11.2026, Betreiber): "Bei Vorstellung anhoeren im Chat
    // soll eine Zeitanzeige mit Balken sein, falls noch nicht vorhanden."
    // Der Knopf allein sagt nichts: man hoert nicht, wie lang die
    // Aufnahme noch ist und wie weit man gekommen ist.
    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _durationSub = _player.durationStream.listen((dauer) {
      if (!mounted) return;
      setState(() => _duration = dauer);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await bestEffort('stop', () async {
        await _player.stop();
      });
      if (mounted) setState(() => _playing = false);
      return;
    }

    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final service = ref.read(findYourMatchServiceProvider);
      // Das Laden hat ein Zeitlimit - sonst bleibt der Spinner bei
      // einem Netzproblem fuer immer stehen.
      final url = await service
          .getIntroAudioUrl(widget.targetUserId)
          .timeout(_ladeTimeout);
      if (!mounted) return;
      if (url == null) {
        setState(() {
          _loading = false;
          _errorKey = 'intro.unavailable';
        });
        return;
      }
      await _player.setUrl(url).timeout(_ladeTimeout);
      if (!mounted) return;
      // Der Balken beginnt bei null - die neue Aufnahme ist eine andere.
      if (mounted) {
        setState(() {
          _position = Duration.zero;
          _duration = null;
        });
      }

      // WICHTIG: `play()` NICHT abwarten. Das Future endet erst, wenn
      // die Aufnahme zu Ende ist - das war der Grund fuer den
      // endlosen Lade-Spinner.
      unawaited(_player.play());
      if (mounted) {
        setState(() {
          _playing = true;
          _loading = false;
        });
      }
    } on TimeoutException {
      debugPrint('[IntroAudioPlayer] Zeitueberschreitung beim Laden.');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'intro.unplayable';
        });
      }
    } catch (e) {
      debugPrint('[IntroAudioPlayer] Fehler: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'intro.unplayable';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dauer = _duration;
    final anteil = (dauer == null || dauer.inMilliseconds <= 0)
        ? 0.0
        : (_position.inMilliseconds / dauer.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonalIcon(
          onPressed: _toggle,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_playing ? Icons.stop : Icons.play_arrow),
          label: Text(
            _playing
                ? L10n.t(context, 'intro.stop')
                : _errorKey != null
                ? L10n.t(context, _errorKey!)
                : L10n.t(context, 'intro.listen'),
          ),
        ),
        const SizedBox(width: 10),
        // Der Balken: er ist erst sichtbar, wenn die Dauer bekannt ist
        // (vorher waere er sinnlos - jede Aufnahme ist anders lang).
        SizedBox(
          width: _balkenBreite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: dauer == null ? null : anteil,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dauer == null
                    ? '--:--'
                    : '${_zeit(_position)} / ${_zeit(dauer)}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
