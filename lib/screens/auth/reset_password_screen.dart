import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/validators.dart';
import 'package:thestia/widgets/buttons.dart';

/// Screen zum Setzen eines neuen Passworts nach der Passwort-Reset-Mail.
///
/// Erreichbar ausschließlich über den Recovery-Deep-Link
/// (`thestia://reset-password`), den der eingebaute Deep-Link-Observer
/// (app_links + detectSessionInUriPredicate in main.dart) verarbeitet und
/// als `passwordRecovery`-Event anmeldet ([passwordRecoveryPendingProvider]).
/// Das neue Passwort wird serverseitig per `updateUser` gesetzt – der
/// Client besitzt nie einen Admin-Schlüssel.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _done = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_done || _saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text),
      );
      // Audit M-13: Nach einem Passwortwechsel werden ALLE Sessions
      // (auch die dieses Geräts) global invalidiert - ein gestohlener
      // Refresh-Token überlebt den Passwortwechsel damit nicht. Der
      // Nutzer meldet sich einfach mit dem neuen Passwort neu an.
      try {
        await SupabaseService.client.auth
            .signOut(scope: SignOutScope.global)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // Fail-open beim lokalen SignOut: Das Passwort ist trotzdem
        // geändert; beim nächsten App-Start greift die Session-Validierung.
      }
      // Reset abgeschlossen: Recovery-Flag löschen, damit der Router wieder
      // die normale Flusslogik übernimmt (Login mit dem neuen Passwort).
      ref.read(passwordRecoveryPendingProvider.notifier).state = false;
      if (!mounted) return;
      setState(() => _done = true);
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
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Bricht den Reset ab (z. B. Link versehentlich geöffnet): Recovery-Flag
  /// löschen und abmelden, damit keine halbe Reset-Session hängen bleibt.
  Future<void> _cancel() async {
    ref.read(passwordRecoveryPendingProvider.notifier).state = false;
    await ref.read(authProvider.notifier).logout();
    if (mounted && context.mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    // Ohne ausstehenden Reset (z. B. direkter URL-Aufruf) nichts anzeigen;
    // der Router leitet ohnehin um. Fail-safe: einfach den Login zeigen.
    final pending = ref.watch(passwordRecoveryPendingProvider);
    if (!pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) context.go(AppRoutes.login);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'reset.title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      L10n.t(context, 'reset.doneTitle'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.t(context, 'reset.doneBody'),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: L10n.t(context, 'reset.toLogin'),
                      onPressed: () => context.go(AppRoutes.login),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_reset, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        L10n.t(context, 'reset.heading'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        L10n.t(context, 'reset.body'),
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'reset.newPassword'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => Validators.password(context, v),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: L10n.t(context, 'reset.repeat'),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return L10n.t(context, 'reset.repeatMissing');
                          }
                          if (v != _passwordCtrl.text) {
                            return L10n.t(context, 'reset.mismatch');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: L10n.t(context, 'reset.save'),
                        onPressed: _saving ? null : _submit,
                        loading: _saving,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : _cancel,
                        child: Text(L10n.t(context, 'common.cancel')),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}