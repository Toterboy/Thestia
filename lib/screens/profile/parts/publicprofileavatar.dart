// Der Teil '_PublicProfileAvatar'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_detail_screen.dart';

/// Profilbild des FREMDEN Nutzers (v0.8.1-Fix + 107-Härtung): Schlüssel
/// kommen aus match-media (nur für Berechtigte), nie mehr aus der
/// Public-View. Respektiert Blind Mode / Foto-Freischaltung
/// (isPhotosVisible).
class _PublicProfileAvatar extends ConsumerStatefulWidget {
  const _PublicProfileAvatar({
    required this.profile,
    required this.isPhotosVisible,
  });

  final UserProfile profile;
  final bool isPhotosVisible;

  @override
  ConsumerState<_PublicProfileAvatar> createState() =>
      _PublicProfileAvatarState();
}
