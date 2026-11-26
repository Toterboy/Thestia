// Der Teil '_PasskeyTileState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../settings_screen.dart';

class _PasskeyTileState extends ConsumerState<_PasskeyTile> {
  bool _busy = false;

  Future<void> _startRegistration() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _ensurePasskeyAal2(context, ref)) return;

      // Bestands-Check: Hängt auf dem Konto bereits ein (alter) Passkey,
      // kann dessen excludeCredentials-Eintrag die NEUE Registrierung
      // serverseitig scheitern lassen ("Der Server konnte den Passkey
      // nicht bestätigen"). Der Nutzer wird transparent darauf hingewiesen
      // und kann alt Einträge vorher unter "Passkeys verwalten" löschen.
      final existing = await PasskeyAuth.countRegistered();
      if (existing != null && existing > 0 && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.fingerprint,
              color: Theme.of(ctx).colorScheme.primary,
              size: 36,
            ),
            title: Text(L10n.t(ctx, 'settings.passkeyExistsTitle')),
            content: Text(
              L10n.tf(ctx, 'settings.passkeyExistsBody', {
                'count': '$existing',
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'settings.passkeyExistsAbort')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'settings.passkeyExistsContinue')),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }

      // ERST OHNE Captcha-Token versuchen (NUTZERWUNSCH 31.10.2026:
      // "hat jetzt aber eine extra Captcha Abfrage"). GoTrue verlangt das
      // Token nur, wenn der Bot-Schutz wirklich greift.
      //
      // Lehnt der Server ohne Token ab (die Challenge-Antwort kommt, BEVOR
      // der native Dialog erscheint), wird der Sicherheitscheck gezeigt
      // und der Versuch mit Token wiederholt. Ohne diesen Umweg schlug die
      // Einrichtung immer fehl, weil das Paket `registerPasskey()` gar
      // kein Token mitschicken kann.
      if (!mounted) return;
      try {
        await PasskeyAuth.register();
      } catch (e) {
        if (!PasskeyAuth.requiresCaptcha(e)) rethrow;
        if (!mounted) return;
        final captchaToken = await showCaptchaChallenge(context);
        if (captchaToken == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.t(context, 'auth.captchaRegister')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await PasskeyAuth.register(captchaToken: captchaToken);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'settings.passkeyCreated')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Konkrete Meldung statt der generischen - auch bei unerwarteten
        // Fehlern (NUTZERWUNSCH 31.10.2026).
        final msg = L10n.exc(
          context,
          PasskeyAuth.explainForUi(e, login: false),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.fingerprint),
      title: Text(L10n.t(context, 'settings.passkeyCreate')),
      subtitle: Text(
        _busy
            ? L10n.t(context, 'settings.passkeyWaitConfirm')
            : L10n.t(context, 'settings.passkeyCreateSub'),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      contentPadding: EdgeInsets.zero,
      onTap: _busy ? null : _startRegistration,
    );
  }
}
