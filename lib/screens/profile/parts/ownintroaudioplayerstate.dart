// Der Teil '_OwnIntroAudioPlayerState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

class _OwnIntroAudioPlayerState extends ConsumerState<_OwnIntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  /// Zustands-Listener. Ohne das Feld wurde bei JEDEM Klick auf Play ein
  /// weiterer Listener auf denselben Player gehängt - nach 20 Klicks liefen
  /// 20 Closures, alle mit setState.
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final storage = ref.read(supabaseStorageServiceProvider);
      final url = await storage.getSignedAvatarUrl(
        '${widget.userId}/intro.m4a',
      );
      if (url == null) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'profile.intro.audioMissing')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _player.setUrl(url);
      // Der Zustands-Listener kommt VOR dem Abspielen: sonst kann das
      // Ende der Aufstellung verpasst werden und der Button bleibt auf
      // "Stopp" stehen.
      await _stateSub?.cancel();
      _stateSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
      // WICHTIG: `play()` NICHT abwarten. just_audio liefert das
      // Future erst fertig, wenn die Aufnahme ZU ENDE ist - während
      // der ganzen Abspielzeit stand hier der Lade-Spinner. Genau das
      // war die Meldung "die Vorstellung lädt nicht oder braucht
      // seeeeeeehr lange".
      unawaited(_player.play());
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      debugPrint('[OwnIntro] Fehler: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'profile.intro.audioLoadError')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasAudio) {
      return Text(
        L10n.t(context, 'profile.intro.audioEmpty'),
        style: const TextStyle(color: Colors.grey),
      );
    }
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
            ? L10n.t(context, 'profile.intro.stop')
            : L10n.t(context, 'profile.intro.listen'),
      ),
    );
  }
}
