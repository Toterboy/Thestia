// Der Teil '_OwnAvatar'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

class _OwnAvatar extends ConsumerWidget {
  const _OwnAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(profileProvider).photos;
    final photoRef = photos.isNotEmpty ? photos.first : null;
    final bytes = photoRef == null
        ? null
        : ref.watch(_ownAvatarBytesProvider(photoRef)).valueOrNull;

    // v0.9.0: abgerundet-RECHTECKIG statt komplett rund.    // Geburtstag: Stil-Rahmen am Ehrentag (Nutzerwunsch, dezent).
    //
    // BEFUND (07.11.2026, Betreiber): "Die Profilvorschau soll dem
    // entsprechen, was auch andere wirklich sehen können." Die
    // Vorschau zeichnete einen Kreis, das echte Profil ein Rechteck.
    // Beide benutzen jetzt DENSELBEN Baustein - sie können nicht mehr
    // auseinanderlaufen.
    final isBirthday = UserProfile.isBirthdayToday(
      ref.watch(profileProvider).birthDate,
    );
    final birthdayStyle = ref.watch(profileProvider).birthdayStyle;
    final avatarBox = ProfileAvatarBox(
      bytes: bytes,
      birthdayStyle: birthdayStyle,
      isBirthday: isBirthday,
      placeholderIcon: Icons.person,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatarBox,
        if (isBirthday) ...[const SizedBox(height: 8), const BirthdayChip()],
      ],
    );
  }
}
