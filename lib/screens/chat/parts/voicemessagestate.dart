// Der Teil '_VoiceMessageState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _VoiceMessageState extends State<_VoiceMessage> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _sourceLoaded = false;
  Duration _position = Duration.zero;

  /// Die Laenge der Aufnahme. Sie kommt aus den Metadaten der Nachricht
  /// - fehlen die, wird sie beim Laden aus der Datei gelesen (damit
  /// immer eine Dauer angezeigt wird).
  Duration _length = Duration.zero;
  bool _consumed = false; // Datei nach Wiedergabe gelöscht (M-17).
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  /// Deterministische Balken-Form aus der Message-ID: gleiche Nachricht
  /// sieht bei beiden Seiten identisch aus, keine zwei gleichen Wellen.
  List<double> get _bars {
    final seed = widget.msgId.hashCode;
    final rand = Random(seed);
    return List.generate(24, (_) => 0.25 + rand.nextDouble() * 0.75);
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_consumed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.voiceOnce')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final player = _player ??= AudioPlayer();
      if (_playing) {
        // Echte Pause (v0.9.1): Position bleibt, Fortsetzen per erneutem
        // Tap statt Neustart.
        await player.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (!_sourceLoaded) {
        await player.setFilePath(widget.path);
        _sourceLoaded = true;
        // Die Dauer aus der Datei, wenn die Nachricht keine mitbringt.
        //
        // BEFUND (07.11.2026, Betreiber): "Dauer der Sprachnachricht
        // anzeigen." Die Dauer kam nur aus den Metadaten der Nachricht.
        // Kamen die nicht an (aeltere Geraete, ein Weg ohne Metadaten),
        // stand da "0:00" - obwohl die Datei eine echte Laenge hat.
        // Der Player kennt sie: nach dem Laden auslesen.
        final laenge = player.duration;
        if (laenge != null && laenge > Duration.zero) {
          _length = laenge;
        }
        await _posSub?.cancel();
        _posSub = player.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        });
        await _stateSub?.cancel();
        _stateSub = player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed && mounted) {
            setState(() {
              _playing = false;
              _position = Duration.zero;
              _sourceLoaded = false;
              _consumed = true;
            });
            // Audit M-17: Nach der Wiedergabe wird die entschlüsselte Datei
            // sofort entfernt.
            unawaited(_deletePlayedFile());
          }
        });
      }
      // WICHTIG: `play()` NICHT abwarten. just_audio liefert das Future
      // erst fertig, wenn die Aufnahme ZU ENDE ist - waehrend der
      // ganzen Abspielzeit war der Zustand "nicht playing", der
      // Pause-Knopf kam nicht und die Oberflaeche tat, als sei nichts
      // passiert.
      unawaited(player.play());
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      debugPrint('[VoiceMessage] Wiedergabe fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.voiceOnlyOnce')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Audit M-17: Löscht die lokal entschlüsselte Voice-Datei nach der
  /// Wiedergabe.
  Future<void> _deletePlayedFile() async {
    // Best-effort: der globale Sweep (temp_cleanup) entfernt Reste.
    await bestEffort('delete', () async {
      final file = File(widget.path);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars;
    final totalSeconds = _length.inSeconds > 0
        ? _length.inSeconds
        : widget.durationSeconds;
    final progress = totalSeconds > 0
        ? _position.inMilliseconds / (totalSeconds * 1000)
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          visualDensity: VisualDensity.compact,
          tooltip: _playing
              ? L10n.t(context, 'intro.review.pause')
              : L10n.t(context, 'intro.review.listen'),
          onPressed: _toggle,
          // Weiß auf Primär-Button (v0.9.1-Fix: vorher Primär auf
          // Primär bei eigenen Nachrichten = unsichtbar).
          icon: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 132,
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < bars.length; i++)
                Container(
                  width: 3,
                  height: 6 + 22 * bars[i],
                  decoration: BoxDecoration(
                    color: _consumed
                        ? widget.textColor.withValues(alpha: 0.25)
                        : widget.textColor.withValues(
                            alpha: i / bars.length <= progress ? 1.0 : 0.4,
                          ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _consumed
              ? L10n.t(context, 'chat.voiceListened')
              : _fmt(totalSeconds),
          style: TextStyle(
            color: widget.textColor,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
