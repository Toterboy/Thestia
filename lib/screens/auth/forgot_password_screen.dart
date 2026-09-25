import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/utils/validators.dart';
import 'package:thestia/widgets/buttons.dart';

/// Platzhalter-Screen für "Passwort vergessen?" (Prototyp).
///
/// Da die Authentifizierung nur ein lokaler Mock ist, wird hier keine echte
/// E-Mail versendet. Der Nutzer gibt seine E-Mail ein und erhält eine
/// Bestätigung, dass (im echten Betrieb) ein Link gesendet würde.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      if (SupabaseService.isInitialized) {
        await SupabaseService.client.auth.resetPasswordForEmail(
          _emailCtrl.text.trim(),
          redirectTo: 'thestia://reset-password',
        );
      }
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                L10n.tf(context, 'common.errorWith', {'error': '$e'})),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'forgot.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_reset, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    L10n.t(context, 'forgot.heading'),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sent
                        ? L10n.t(context, 'forgot.sentBody')
                        : L10n.t(context, 'forgot.body'),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (!_sent)
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                          labelText: L10n.t(context, 'forgot.email')),
                      validator: (v) => Validators.email(context, v),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  L10n.t(context, 'forgot.sentBox'),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                    ),
                  const SizedBox(height: 24),
                   PrimaryButton(
                    label: _sending
                        ? L10n.t(context, 'forgot.sending')
                        : (_sent
                            ? L10n.t(context, 'forgot.toLogin')
                            : L10n.t(context, 'forgot.sendLink')),
                    onPressed: _sending
                        ? null
                        : (_sent
                            ? () => context.go(AppRoutes.login)
                            : _submit),
                    loading: _sending,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

