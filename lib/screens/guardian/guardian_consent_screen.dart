import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/guardian_provider.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/buttons.dart';

/// Screen fuer die Elternfreigabe (16 und 17 Jahre).
///
/// Er wird direkt nach dem Willkommens-Screen gezeigt. Die Freigabe ist
/// FREIWILLIG: wer sie nicht will, kann sie ueberspringen - nach § 3a JUG
/// kann eine Person ab dem vollendeten 16. Lebensjahr selbst einwilligen.
///
/// Die eigentliche Entscheidung faellt der Elternteil: er bekommt eine
/// E-Mail mit einem Link und bestaetigt dort. Diese Seite verschickt
/// nur die Anfrage.
class GuardianConsentScreen extends ConsumerStatefulWidget {
  const GuardianConsentScreen({super.key});

  @override
  ConsumerState<GuardianConsentScreen> createState() =>
      _GuardianConsentScreenState();
}

class _GuardianConsentScreenState extends ConsumerState<GuardianConsentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim().toLowerCase();

    // Die eigene Kontoadresse kann nicht Elternteil sein. Der Server
    // prueft das ebenfalls - hier nur die freundliche Meldung.
    final eigene = SupabaseService.currentUser?.email?.toLowerCase();
    if (eigene != null && eigene.isNotEmpty && eigene == email) {
      _fehler(L10n.t(context, 'guardian.errorSameEmail'));
      return;
    }

    setState(() => _sending = true);
    final result = await ref
        .read(guardianProvider.notifier)
        .requestConsent(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (result.isOk) {
      setState(() => _sent = true);
    } else {
      _fehler(_text(result.code));
    }
  }

  void _fehler(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _text(String? code) {
    switch (code) {
      case 'same_email':
        return L10n.t(context, 'guardian.errorSameEmail');
      case 'not_eligible':
        return L10n.t(context, 'guardian.errorNotEligible');
      case 'invalid_email':
        return L10n.t(context, 'guardian.errorInvalidEmail');
      case 'rate_limited':
        return L10n.t(context, 'guardian.errorRateLimited');
      default:
        return L10n.t(context, 'guardian.errorGeneric');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _emailCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'guardian.requestScreenTitle')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: _sent
            ? _Fertig(email: email, onDone: () => context.go('/'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        L10n.t(context, 'guardian.requestIntro'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        enableIMEPersonalizedLearning: false,
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'guardian.emailLabel'),
                          hintText: L10n.t(context, 'guardian.emailHint'),
                        ),
                        validator: (v) {
                          final wert = (v ?? '').trim();
                          if (wert.isEmpty) return null;
                          if (!RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(wert)) {
                            return L10n.t(
                              context,
                              'guardian.errorInvalidEmail',
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: L10n.t(context, 'guardian.sendBtn'),
                        loading: _sending,
                        onPressed: _sending ? null : _send,
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(
                        label: L10n.t(context, 'guardian.skipBtn'),
                        onPressed: _sending ? null : () => context.go('/'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Der Zustand nach dem Absenden: "Bitte warte auf die Bestaetigung".
class _Fertig extends StatelessWidget {
  const _Fertig({required this.email, required this.onDone});

  final String email;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.mark_email_read_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            L10n.t(context, 'guardian.sentTitle'),
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            L10n.tf(context, 'guardian.sentText', {'email': email}),
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          PrimaryButton(label: L10n.t(context, 'common.ok'), onPressed: onDone),
        ],
      ),
    );
  }
}
