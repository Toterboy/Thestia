// Der Teil '_OwnIntroAudioPlayer'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

/// Spielt die EIGENE Audio-Vorstellung ab (signierte URL des eigenen
/// Storage-Pfads - keine match-media-Berechtigung nötig).
class _OwnIntroAudioPlayer extends ConsumerStatefulWidget {
  const _OwnIntroAudioPlayer({required this.userId, required this.hasAudio});

  final String userId;
  final bool hasAudio;

  @override
  ConsumerState<_OwnIntroAudioPlayer> createState() =>
      _OwnIntroAudioPlayerState();
}
