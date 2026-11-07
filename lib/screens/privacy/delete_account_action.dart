import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Der Konto-Lösch-Ablauf - von zwei Stellen aus erreichbar.
///
/// WARUM (06.11.2026, Betreiber): "Konto löschen" und "Daten löschen"
/// sollen die untersten Punkte sein - in den Einstellungen UND im
/// Datenschutz-Bereich. Der Ablauf stand vorher nur im Datenschutz-
/// Screen; als eigene Funktion ist er jetzt von beiden Stellen nutzbar,
/// ohne den Code zu verdoppeln.
///
/// Der Ablauf ist unveraendert:
///  1) MFA-Step-up (ASVS 7.5.3): bei aktivem 2FA wird vor der Loeschung
///     eine zusaetzliche TOTP-Verifikation verlangt.
///  2) Bestaetigungsdialog
///  3) Loeschung ueber den Auth-Provider, danach zur Startseite.
Future<void> deleteAccountWithConfirmation(
  BuildContext context,
  WidgetRef ref,
) async {
  // Step-up (ASVS 7.5.3): Bei aktivem MFA ist vor der Konto-Loeschung
  // eine zusaetzliche TOTP-Verifikation noetig - eine reine Passwort-
  // Session (AAL1) reicht nicht (die Edge Function erzwingt AAL2
  // serverseitig; der Pre-Check hier liefert die verstaendliche
  // Fehlermeldung statt eines kryptischen Server-Fehlers).
  final mfa = ref.read(mfaStatusProvider);
  if (mfa.hasVerifiedFactors && mfa.currentAal != 'aal2') {
    final code = await promptTotpCode(context);
    if (code == null || !context.mounted) return; // abgebrochen
    try {
      await MfaService(SupabaseService.client).verifyChallenge(code: code);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ungültiger oder abgelaufener Code. '
              'Die Löschung wurde abgebrochen.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(context, 'privacy.deleteTitle')),
      content: Text(L10n.t(context, 'privacy.deleteBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(context, 'common.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(L10n.t(context, 'privacy.deleteConfirm')),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(authProvider.notifier).deleteAccount();
    if (context.mounted) {
      context.go(AppRoutes.welcome);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.t(context, 'privacy.deleteFailed')}: $e'),
        ),
      );
    }
  }
}

/// Fragt den 6-stelligen TOTP-Code für das Step-up vor einer sensiblen
/// Aktion (Konto-Löschung, Passkey-Erstellung) ab.
/// Liefert `null`, wenn der Nutzer abgebrochen hat.
Future<String?> promptTotpCode(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(ctx, 'privacy.totpTitle')),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(
          labelText: L10n.t(ctx, 'privacy.totpLabel'),
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(L10n.t(ctx, 'privacy.totpConfirm')),
        ),
      ],
    ),
  );
}
