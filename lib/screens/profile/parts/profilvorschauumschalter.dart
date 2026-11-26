// Der Teil 'ProfilVorschauUmschalter'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

/// Umschalter in der Profil-Vorschau: normal oder Geburtstag.
///
/// NUTZERWUNSCH (28.10.2026): "Unter Profil Vorschau soll man
/// zwischen der normalen Profil Vorschau und der Profil Vorschau für
/// den Geburtstag wechseln können."
///
/// Zwei Pillen statt eines Schalters: der Geburtstags-Zustand ist ein
/// ZWEITER Zustand, kein An-Aus - man will sehen, wie das Profil in
/// beiden Varianten aussieht.
class ProfilVorschauUmschalter extends StatelessWidget {
  const ProfilVorschauUmschalter({
    required this.geburtstag,
    required this.onChanged,
    super.key,
  });

  /// Zustand: true = Geburtstags-Vorschau.
  final ValueListenable<bool> geburtstag;

  /// Wird bei jedem Wechsel aufgerufen.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: geburtstag,
      builder: (context, istGeburtstag, _) {
        return Row(
          children: [
            _Pill(
              label: L10n.t(context, 'profile.preview.modeNormal'),
              icon: Icons.person_outline,
              selected: !istGeburtstag,
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 8),
            _Pill(
              label: L10n.t(context, 'profile.preview.modeBirthday'),
              icon: Icons.auto_awesome,
              selected: istGeburtstag,
              onTap: () => onChanged(true),
            ),
          ],
        );
      },
    );
  }
}
