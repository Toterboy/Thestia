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
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
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
    return FilledButton.tonalIcon(
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
    );
  }
}
