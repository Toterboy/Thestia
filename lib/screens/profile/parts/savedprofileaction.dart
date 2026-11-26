// Der Teil '_SavedProfileAction'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_detail_screen.dart';

/// AppBar-Aktion "Profil lokal speichern" (v0.9.1): Erzeugt einen
/// PERSISTENTEN QR-Kontakt aus dem geladenen Profil (funktioniert auch
/// ohne Internet, da die Profil-Daten lokal übernommen werden). Max. 5;
/// bereits gespeicherte Profile lassen sich hier wieder entfernen.
class _SavedProfileAction extends ConsumerWidget {
  const _SavedProfileAction({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(chatProvider);
    final existing = contacts
        .where((m) => m.isQrContact && m.partner.id == profile.id)
        .firstOrNull;

    if (existing != null) {
      return IconButton(
        // NUTZERWUNSCH: Aktiv-Status farblich (gefülltes Icon in
        // Primärfarbe statt graüm Outline-Icon).
        icon: Icon(
          Icons.bookmark,
          color: Theme.of(context).colorScheme.primary,
        ),
        tooltip: L10n.t(context, 'profile.detail.savedRemove'),
        onPressed: () {
          ref.read(chatProvider.notifier).deleteQrContact(existing.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'profile.detail.savedRemoved', {
                  'name': profile.name,
                }),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    return IconButton(
      icon: const Icon(Icons.bookmark_border),
      tooltip: L10n.t(context, 'profile.detail.savedSave'),
      onPressed: () async {
        final match = ref
            .read(chatProvider.notifier)
            .findOrCreateMatch(profile.id);
        if (match == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'qr.limitBody')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
        ref.read(chatProvider.notifier).updatePartner(match.id, profile);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'profile.detail.savedDone', {
                'name': profile.name,
              }),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}
