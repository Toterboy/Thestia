// Der Teil '_VerificationStatusCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

/// Verifizierungs-Status des eigenen Profils (v0.9.1).
///
/// Der Verifiziert-Badge steht oben in der Kopfzeile neben dem
/// Persönlichkeitstyp (Nutzerwunsch) - hier nur noch der Rest:
/// Eingereicht, aber noch kein Badge -> "Prüfung läuft" (Konto bleibt
/// voll nutzbar). Sonst Einstieg in den Video-Flow mit lokaler
/// KI-Triage (Modell auf dem Gerät, sonst manuelle Queue).
class _VerificationStatusCard extends ConsumerWidget {
  const _VerificationStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile.isVerified) {
      // Badge steht oben neben dem Persönlichkeitstyp - hier nichts.
      return const SizedBox.shrink();
    }
    return FutureBuilder<bool>(
      future: _submittedFlag(ref),
      builder: (context, snapshot) {
        final submitted = snapshot.data ?? false;
        if (submitted) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.hourglass_top_outlined),
              title: Text(L10n.t(context, 'verify.pendingChip')),
              subtitle: Text(L10n.t(context, 'verify.pendingHint')),
            ),
          );
        }
        if (!AppConstants.verificationEnabled) {
          return const SizedBox.shrink();
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(L10n.t(context, 'verify.cta')),
            subtitle: Text(L10n.t(context, 'verify.ctaSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.verificationInfo),
          ),
        );
      },
    );
  }

  Future<bool> _submittedFlag(WidgetRef ref) async {
    try {
      final storage = ref.read(localStorageProvider);
      // Badge da -> Merker aufräumen, Chip verschwindet von selbst.
      if (ref.read(profileProvider).isVerified) {
        await storage.remove(verificationSubmittedKey);
        return false;
      }
      final stored = await storage.getBool(verificationSubmittedKey) ?? false;
      if (!stored) return false;
      // Selbstheilung (Nutzer-Regel "läuft ohne Video"): Der Merker ohne
      // lokales Video (alte Installation, fremder Account-Rest) zeigt
      // fälschlich "Prüfung läuft" - aufräumen und CTA anzeigen. Ohne
      // Video gibt es serverseitig nichts zu prüfen.
      //
      // Robustheit: Service-Init abwarten (ungeöffnete Box würfe sonst
      // und der Chip bliebe fälschlich versteckt).
      final verificationService = ref.read(verificationServiceProvider);
      await bestEffort('verificationService.initialize', () async {
        await verificationService.initialize();
      });
      final video = verificationService.getVerificationVideo();
      if (video == null) {
        await storage.remove(verificationSubmittedKey);
        return false;
      }
      final dateiFehlt = await bestEffortOr(
        'File.exists',
        () async => !await File(video.filePath).exists(),
        false,
      );
      if (dateiFehlt) {
        await storage.remove(verificationSubmittedKey);
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
