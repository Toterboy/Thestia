import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// 2FA-Einrichtung (Authenticator-App / TOTP) – wird nach der
/// E-Mail-Bestätigung als optionaler Schritt angezeigt.
///
/// Ablauf:
///  1. QR-Code mit der otpauth://-URI anzeigen (Google Authenticator,
///     Aegis, 2FAS, Apple Passcodes & Passwörter …).
///  2. Nutzer trägt den ersten 6-stelligen Code ein.
///  3. Server verifiziert → Faktor ist aktiv, Session ist auf AAL2.
///
/// Bewusst NUR TOTP (keine SMS). „Später" blendet den Hinweis dauerhaft
/// aus (mfaSetupDismissed-Flag) – die Einrichtung ist optional, aber der
/// Login verlangt den Code, sobald ein Faktor existiert.
class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

enum _SetupPhase { intro, scan, confirm, done }

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  _SetupPhase _phase = _SetupPhase.intro;
  bool _loading = false;
  String? _error;

  String? _factorId;
  String? _qrUri;
  String? _secret;

  // Audit: TOTP-Secret nach 30 s automatisch aus der Zwischenablage
  // entfernen (falls es nicht durch etwas anderes ersetzt wurde).
  Timer? _clipboardClearTimer;

  final _codeCtrl = TextEditingController();

  /// True, wenn bereits ein verifizierter 2FA-Faktor existiert - dann zeigt
  /// der Screen die "aktiv"-Ansicht statt des Einrichtungs-Flows.
  bool _twoFaActive = false;

  /// Schützt das programmatische Verlassen („Später erinnern", fertig)
  /// vor dem blockierenden PopScope: Ohne dieses Flag poppte der Screen
  /// endlos gegen die eigene Sperre ("Seite öffnet sich immer neu").
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // 2FA-Stand FRISCH laden: Zeigt bereits aktivierte 2FA sofort als
    // "aktiv" an (vorher fehlte der Haken / die Einrichtung schlug fehl).
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final service = _tryGetService();
    if (service == null) return;
    try {
      final status = await service.loadStatus();
      if (!mounted) return;
      ref.read(mfaStatusProvider.notifier).state = status;
      setState(() => _twoFaActive = status.hasVerifiedFactors);
    } catch (_) {
      // Best effort: Intro bleibt sichtbar.
    }
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    // Unvollständige Einrichtung serverseitig verwerfen.
    final factorId = _factorId;
    if (factorId != null && _phase != _SetupPhase.done) {
      final service = _tryGetService();
      service?.cancelEnroll(factorId);
    }
    _codeCtrl.dispose();
    super.dispose();
  }

  MfaService? _tryGetService() {
    if (!SupabaseService.isInitialized) return null;
    try {
      return ref.read(mfaServiceProvider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startEnroll() async {
    final service = _tryGetService();
    if (service == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await service.startTotpEnroll();
      if (!mounted) return;
      setState(() {
        _factorId = result.factorId;
        _qrUri = result.qrUri;
        _secret = result.secret;
        _phase = _SetupPhase.scan;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[MfaSetup] enroll fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          // Kuratierte Server-Meldungen (z. B. "2FA ist bereits
          // aktiviert") IMMER zeigen; nur Unbekanntes bleibt generisch.
          _error = e is AuthException
              ? e.message
              : 'Einrichtung konnte nicht gestartet werden. '
                  'Bitte versuche es später erneut.';
          _loading = false;
        });
      }
    }
  }

  /// Nach dem Scannen/Eingeben des Schlüssels zum Bestätigungsschritt
  /// (TOTP-Code aus der Authenticator-App) wechseln.
  void _toConfirm() {
    if (_qrUri == null || _factorId == null) return;
    setState(() => _phase = _SetupPhase.confirm);
  }

  Future<void> _verifyCode() async {
    final service = _tryGetService();
    final factorId = _factorId;
    if (service == null || factorId == null) return;

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
      await service.verifyTotpEnroll(factorId: factorId, code: code);
      // Status aktualisieren: Router/andere Screens sehen jetzt AAL2.
      final status = await service.loadStatus();
      ref.read(mfaStatusProvider.notifier).state = status;
      if (mounted) {
        setState(() {
          _phase = _SetupPhase.done;
          _loading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MfaSetup] verify fehlgeschlagen: $e');
      if (mounted) {
        setState(() {
          _error = 'Code nicht akzeptiert. Prüfe, ob deine Authenticator-App '
              'den QR-Code erfasst hat und gib den AKTUELLEN Code ein.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _skip() async {
    // Fix: Ein Fehler beim Persistieren (z. B. Server-Sync) darf die
    // Navigation NICHT blockieren - sonst bleibt der Nutzer hier hängen
    // ("Später erinnern" ohne Wirkung).
    try {
      await ref.read(settingsProvider.notifier).setMfaSetupDismissed(true);
    } catch (_) {
      // Best-effort: Der Dismiss-Flag wird beim nächsten Erfolg nachgezogen.
    }
    if (mounted) _continueFlow();
  }

  /// Weiter: Wurde der Screen aufgestapelt geöffnet (Einrichtung,
  /// Einstellungen), zurück dorthin – sonst zur Startseite.
  void _continueFlow() {
    // PopScope-Sperre für das programmatische Verlassen aufheben - sonst
    // poppt der Screen endlos gegen die eigene Sperre ("öffnet sich
    // immer wieder neu").
    _leaving = true;
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wird der Screen aufgestapelt geöffnet (Einstellungen, Einrichtung),
    // einen Zurück-Pfeil zeigen; nur im alten Router-Flow (ohne Stack)
    // bleibt er ohne Leading.
    final canLeave = Navigator.of(context).canPop();
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaving) _continueFlow();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'mfa.setupTitle')),
        automaticallyImplyLeading: false,
        leading: canLeave
            ? BackButton(onPressed: () => context.pop())
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_phase) {
            _SetupPhase.intro => _buildIntro(),
            _SetupPhase.scan => _buildScan(),
            _SetupPhase.confirm => _buildConfirm(),
            _SetupPhase.done => _buildDone(),
          },
        ),
      ),
      ),
    );
  }

  Widget _buildIntro() {
    // 2FA bereits aktiv? Dann "aktiv"-Ansicht mit Haken statt des
    // Einrichtungs-Flows (User-Bericht: "steht nicht, dass ich es
    // eingerichtet habe" + "Einrichten geht nicht").
    if (_twoFaActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_user,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            L10n.t(context, 'mfa.activeTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            L10n.t(context, 'mfa.activeBody'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _continueFlow,
            icon: const Icon(Icons.check),
            label: Text(L10n.t(context, 'common.done')),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.shield_outlined, size: 64),
        const SizedBox(height: 16),
        Text(
          L10n.t(context, 'mfa.introTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'mfa.introBody'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'mfa.introSkip'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _loading ? null : _startEnroll,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.qr_code),
          label: Text(L10n.t(context, 'mfa.setupScan')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _skip,
          child: Text(L10n.t(context, 'mfa.setupLater')),
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
    );
  }

  Widget _buildScan() {
    // Responsiver QR: Auf schmalen Screens (oder großer Schrift) darf das
    // fixed 220px-Bild den Platz nicht wegdrücken.
    final qrSize = (MediaQuery.of(context).size.width - 120)
        .clamp(140.0, 220.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------- Abschnitt 1: QR-Code ----------
        Text(
          L10n.t(context, 'mfa.scanStep'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(L10n.t(context, 'mfa.scanBody')),
        const SizedBox(height: 24),
        if (_qrUri != null)
          Center(
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: _qrUri!,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
        if (_secret != null) ...[
          const SizedBox(height: 16),
          Text(
            L10n.t(context, 'mfa.manualKey'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _secret!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.t(context, 'mfa.copied')),
                ),
              );
              _clipboardClearTimer?.cancel();
              _clipboardClearTimer = Timer(const Duration(seconds: 30), () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text == _secret) {
                  await Clipboard.setData(const ClipboardData(text: ''));
                }
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _secret!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _toConfirm,
          icon: const Icon(Icons.arrow_forward),
          label: Text(L10n.t(context, 'mfa.setupNext')),
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'mfa.setupNextHint'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
    );
  }

  /// Bestätigungsschritt: Den aktuellen 6-stelligen Code aus der
  /// Authenticator-App einmal eingeben und damit die Einrichtung abschließen.
  Widget _buildConfirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          L10n.t(context, 'mfa.confirmStep'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(L10n.t(context, 'mfa.confirmBody')),
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            letterSpacing: 12,
            fontWeight: FontWeight.bold,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _loading ? null : _verifyCode,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(L10n.t(context, 'common.confirm')),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() => _phase = _SetupPhase.scan),
          child: Text(L10n.t(context, 'mfa.setupBackQr')),
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
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.verified_user,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          L10n.t(context, 'mfa.doneTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'mfa.doneBody'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _continueFlow,
          child: Text(L10n.t(context, 'common.continue')),
        ),
      ],
    );
  }
}
