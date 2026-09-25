import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// 2FA-Code-Abfrage beim Login (TOTP/Authenticator-App).
///
/// Wird vom Router angezeigt, wenn verifizierte Faktoren existieren, die
/// Session aber nur AAL1 (Passwort) ist. Erst nach erfolgreicher Verifikation
/// wird die App freigegeben.
class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!SupabaseService.isInitialized) return;
    final service = ref.read(mfaServiceProvider);

    final code = _codeCtrl.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Bitte gib den 6-stelligen Code ein.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.verifyChallenge(code: code);
      // Status aktualisieren (jetzt AAL2) – Router gibt die App frei.
      final status = await service.loadStatus();
      ref.read(mfaStatusProvider.notifier).state = status;
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (kDebugMode) debugPrint('[MfaChallenge] verify fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          _error = 'Code nicht korrekt. Bitte gib den aktuellen Code aus '
              'deiner Authenticator-App ein.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'mfa.title')),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.phonelink_lock_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'mfa.body'),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  // Einfuegen-Button (v0.9.0): Code aus der
                  // Authenticator-App kopiert? Ein Tap fuegt ihn ein -
                  // kein muhsames Ablesen/Eintippen noetig.
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: L10n.t(context, 'mfa.paste'),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData('text/plain');
                      final text =
                          (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
                      if (text.isNotEmpty) {
                        setState(() {
                          _codeCtrl.text = text.substring(
                              0, text.length > 6 ? 6 : text.length);
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _verify,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(L10n.t(context, 'common.check')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _logout,
                child: Text(L10n.t(context, 'email.logout')),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
