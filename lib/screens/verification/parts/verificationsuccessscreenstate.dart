// Der Teil '_VerificationSuccessScreenState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../verification_flow.dart';

class _VerificationSuccessScreenState
    extends ConsumerState<VerificationSuccessScreen> {
  /// NUTZERWUNSCH: Nach der Video-Verifizierung daran erinnern, dass
  /// Standort, Kamera und Mikrofon wieder deaktiviert werden können -
  /// die Verifizierung ist fertig, die Zugriffe nicht mehr nötig.
  void _maybeOfferPrivacyCleanup() {
    Future<void>.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final open = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined, size: 40),
          title: Text(L10n.t(ctx, 'verify.cleanupTitle')),
          content: Text(L10n.t(ctx, 'verify.cleanupBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('later'),
              child: Text(L10n.t(ctx, 'verify.cleanupLater')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('location'),
              child: Text(L10n.t(ctx, 'verify.cleanupLocation')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('app'),
              child: Text(L10n.t(ctx, 'verify.cleanupOpen')),
            ),
          ],
        ),
      );
      if (!mounted || open == 'later') return;
      if (open == 'location') {
        await bestEffort('openLocationSettings', () async {
          await Geolocator.openLocationSettings();
        });
      } else if (open == 'app' && mounted) {
        // Kamera + Mikrofon: App-Berechtigungsseite (beide abdrehbar).
        await bestEffort('openAppSettings', () async {
          await openAppSettings();
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeOfferPrivacyCleanup();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 'auto' = KI-Triage unauffällig (Badge sofort), sonst manuelle
    // Prüfung durch den Support (Badge erst danach).
    final auto = ref.watch(verificationResultProvider) == 'auto';
    final reasonKey = ref.watch(verificationPendingReasonProvider);
    final deviation = ref.watch(verificationDeviationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'verify.doneTitle'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  auto ? Icons.verified : Icons.check_circle,
                  size: 64,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                auto
                    ? L10n.t(context, 'verify.autoTitle')
                    : L10n.t(context, 'verify.pendingTitle'),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                auto
                    ? L10n.t(context, 'verify.autoBody')
                    : L10n.t(context, 'verify.pendingBody'),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              // Diagnose (NUTZERWUNSCH "Verifizierung klappt nicht"):
              // transparent, warum die KI-Triage in die manuelle Queue
              // gelegt hat - Abweichung / Gesichter / keine KI.
              if (!auto && reasonKey != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    deviation != null
                        ? L10n.tf(context, reasonKey, {
                            'years': deviation.round().toString(),
                          })
                        : L10n.t(context, reasonKey),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(L10n.t(context, 'verify.toApp')),
                onPressed: () => context.go(AppRoutes.home),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
