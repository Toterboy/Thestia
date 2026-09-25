import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/captcha_challenge.dart';

/// Screen zur Bestätigung der E-Mail-Adresse nach der Registrierung.
///
/// Pollt den Auth-Status alle 3 Sekunden via [emailConfirmedProvider].
/// Bietet einen "Erneut senden"-Button, falls die Mail nicht ankommt.
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen>
    with WidgetsBindingObserver {
  ProviderSubscription<bool?>? _emailConfirmedSub;
  bool _resending = false;
  bool _showSent = false;
  int _cooldownSeconds = 0;
  Timer? _sentTimer;
  Timer? _cooldownTimer;
  Timer? _autoLoginTimer;
  bool _autoLoginInProgress = false;
  int _autoLoginDelaySeconds = 5;
  String? _capturedEmail;

  /// Dauer der "E-Mail gesendet"-Bestätigung im Button.
  static const _sentAnimationDuration = Duration(seconds: 2);

  /// Cooldown bis zum nächsten erlaubten "Erneut senden".
  static const _resendCooldownDuration = Duration(seconds: 60);

  /// Start-Wartezeit bis zum ersten Auto-Login-Versuch (schont das
  /// Auth-Rate-Limit: Häufige stille Login-Versuche sorgten dafür, dass
  /// echte Registrierungs-/Login-Versuche mit "Zu viele Anfragen"
  /// abgelehnt wurden).
  static const _autoLoginInitialDelaySeconds = 10;

  /// Maximales Alter der im Speicher gehaltenen Registrierungs-Credentials
  /// (E-Mail + Passwort). Danach wird der stille Login eingestellt.
  static const _autoLoginCredentialsMaxAge = Duration(minutes: 15);

  /// Maximale Wartezeit zwischen zwei Auto-Login-Versuchen (Backoff).
  /// Längere Abstände (30 s) statt schnellem Polling, um das pro-Minute-
  /// Limit nicht zu erschöpfen. Nach dem Zurückkehren aus der
  /// Bestätigungs-Mail wird ohnehin sofort ein Versuch gestartet.
  static const _autoLoginMaxDelaySeconds = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // E-Mail aus der Registrierung (pendingVerificationEmailProvider) bzw.
    // dem Auth-State erfassen. Nach signUp mit aktivierter Bestätigung gibt
    // es KEINE Session (currentUser == null) – deshalb primär der Provider.
    _capturedEmail =
        ref.read(pendingVerificationEmailProvider) ??
        SupabaseService.client.auth.currentUser?.email;
    // Sobald die E-Mail bestätigt ist, automatisch zur Hauptapp weiterleiten.
    // v0.9.0-Fix: Nach FRISCHER Registrierung direkt die Einrichtung
    // erzwingen (Onboarding-Interview) - vorher kam sie erst beim 2.
    // Appstart, weil der Server-Flag-Sync ggf. einen veralteten Stand
    // lieferte.
    _emailConfirmedSub = ref.listenManual<bool?>(emailConfirmedProvider, (
      previous,
      next,
    ) {
      if (next == true && previous != true) {
        ref.read(settingsProvider.notifier).markOnboardingPending();
        if (mounted) context.go(AppRoutes.signupWelcome);
      }
    });
    // Stillen Auto-Login starten: Nach der Bestätigung meldet sich die App
    // automatisch an und geht weiter (Session existiert erst nach Login).
    _scheduleAutoLoginAttempt();
    // Ohne Supabase (Demo-Modus) gibt es nichts zu bestätigen: direkt zur
    // Hauptapp weiterleiten. Es gibt bewusst KEINEN "Weiter"-Button mehr,
    // die Bestätigung läuft vollautomatisch über den Poller.
    if (!SupabaseService.isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.home);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Die Bestätigung passiert meist im Browser: Beim Zurückkehren in die
    // App sofort prüfen. Im Hintergrund nicht pollen – schont das
    // Auth-Rate-Limit-Budget und den Akku.
    if (state == AppLifecycleState.resumed) {
      _autoLoginDelaySeconds = _autoLoginInitialDelaySeconds;
      // Der Nutzer kommt i. d. R. gerade aus der Bestätigungs-Mail zurück:
      // Genau jetzt EINE Captcha-Challenge anbieten (Server verlangt bei
      // aktivierter Dashboard-CAPTCHA auch für den stillen Login ein
      // Token) und dann mit Token anmelden. Vorher scheiterte der stille
      // Login still an captcha_failed -> "es geht nicht weiter".
      _attemptAutoLogin(withCaptcha: AppConstants.captchaEnabled);
    } else {
      _autoLoginTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sentTimer?.cancel();
    _cooldownTimer?.cancel();
    _autoLoginTimer?.cancel();
    _emailConfirmedSub?.close();
    super.dispose();
  }

  /// Versucht im Hintergrund einen Login mit den Registrierungsdaten
  /// (nur im Speicher). Vor der Bestätigung schlägt er fehl; sobald die
  /// E-Mail bestätigt ist, baut er die Session auf - der
  /// [emailConfirmedProvider] erkennt das und navigiert weiter.
  void _scheduleAutoLoginAttempt() {
    _autoLoginTimer?.cancel();
    _autoLoginTimer = Timer(
      Duration(seconds: _autoLoginDelaySeconds),
      _attemptAutoLogin,
    );
  }

  Future<void> _attemptAutoLogin({bool withCaptcha = false}) async {
    // Keine überlappenden Versuche (jeder Versuch kostet Rate-Limit-Budget).
    if (_autoLoginInProgress) return;
    if (!mounted || !SupabaseService.isInitialized) return;
    final creds = ref.read(pendingVerificationCredentialsProvider);
    if (creds == null) return;
    // Ablauf (Audit M1): Die Registrierungs-Credentials dürfen höchstens
    // 15 Minuten im Speicher weitergegeben werden. Danach wird der
    // Auto-Login eingestellt und der Nutzer muss sich regulär anmelden.
    if (DateTime.now().difference(creds.createdAt) >
        _autoLoginCredentialsMaxAge) {
      ref.read(pendingVerificationCredentialsProvider.notifier).state = null;
      return;
    }
    // Session schon vorhanden? Dann ist der normale Poller zuständig.
    if (SupabaseService.client.auth.currentSession != null) return;

    _autoLoginInProgress = true;
    try {
      // Bei aktivierter Dashboard-CAPTCHA verlangt der Server auch für
      // den stillen Login ein Token. Nur auf expliziten Wunsch (User ist
      // gerade aus der Mail zurückgekehrt) eine Challenge zeigen – die
      // stillen Timer-Versuche laufen ohne Token weiter und scheitern
      // leise, bis die Bestätigung + Challenge durch ist.
      String? captchaToken;
      if (withCaptcha && AppConstants.captchaEnabled && mounted) {
        captchaToken = await showCaptchaChallenge(context);
        if (captchaToken == null) {
          // Abgebrochen: normal weiter im Backoff, kein Endlos-Retry.
          return;
        }
      }
      // silentLogin statt login(): Der Status bleibt bei einem Fehler
      // unverändert, damit der Router den Nutzer nicht als "ausgeloggt"
      // behandelt und zum Login-Screen wirft.
      await ref
          .read(authProvider.notifier)
          .silentLogin(
            email: creds.email,
            password: creds.password,
            captchaToken: captchaToken,
          );
      // Erfolg: silentLogin hat die Credentials geleert und die Session
      // erzeugt. emailConfirmedProvider erkennt die Bestätigung und
      // navigiert weiter.
      return;
    } catch (_) {
      // Noch nicht bestätigt (oder temporärer Netzwerk-/Rate-Limit-Fehler):
      // mit Backoff erneut versuchen, solange der Screen offen ist.
      if (_autoLoginDelaySeconds < _autoLoginMaxDelaySeconds) {
        _autoLoginDelaySeconds *= 2;
        if (_autoLoginDelaySeconds > _autoLoginMaxDelaySeconds) {
          _autoLoginDelaySeconds = _autoLoginMaxDelaySeconds;
        }
      }
      _scheduleAutoLoginAttempt();
    } finally {
      _autoLoginInProgress = false;
    }
  }

  /// Manueller "Weiter"-Weg, nachdem der Nutzer die Mail bestätigt hat.
  ///
  /// Wichtig, weil der stille Auto-Login nur beim App-Wechsel (resumed)
  /// eine Captcha-Challenge zeigen kann: Bleibt die App während der
  /// Bestätigung offen (oder wurde die Mail auf einem anderen Gerät
  /// geöffnet), gäbe es sonst keinen Ausweg vom Screen. Sind die
  /// Registrierungs-Credentials (max. 15 Min) nicht mehr da, führt der
  /// reguläre Login zum Ziel – die Challenge gibt es dort ebenfalls.
  Future<void> _manualContinue() async {
    final creds = ref.read(pendingVerificationCredentialsProvider);
    if (creds == null ||
        DateTime.now().difference(creds.createdAt) >
            _autoLoginCredentialsMaxAge) {
      // Kein stiller Login mehr möglich: reguläre Anmeldung anbieten.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bitte melde dich jetzt mit E-Mail und Passwort an. '
              'Deine E-Mail-Adresse ist bereits bestätigt.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.login);
      }
      return;
    }
    await _attemptAutoLogin(withCaptcha: AppConstants.captchaEnabled);
  }

  /// Bricht die Registrierung ab und löscht den Account serverseitig.
  ///
  /// Nutzer-Regel: Auf dem Bestätigungs-Screen muss man abbrechen können,
  /// wobei der Supabase-Account gelöscht wird. Zwei Pfade:
  /// - Session vorhanden -> normale Löschung via deleteAccount().
  /// - Keine Session (Normalfall: unbestätigt) -> cancel-registration
  ///   mit E-Mail + Passwort aus dem Speicher-Nachweis.
  Future<void> _cancelRegistration() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t(ctx, 'email.cancelTitle')),
            content: Text(L10n.t(ctx, 'email.cancelBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'email.cancelKeep')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'email.cancelConfirm')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;

    try {
      final hasSession =
          SupabaseService.isInitialized &&
          SupabaseService.client.auth.currentUser != null;
      if (hasSession) {
        await ref.read(authProvider.notifier).deleteAccount();
      } else {
        final creds = ref.read(pendingVerificationCredentialsProvider);
        if (creds == null) {
          // Nachweis abgelaufen (> 15 Min): ausloggen, zum Login.
          // Eine Neuregistrierung sendet die Mail erneut.
          await ref.read(authProvider.notifier).logout();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'email.cancelExpired')),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.go(AppRoutes.login);
          return;
        }
        final response = await SupabaseService.client.functions
            .invoke(
              'cancel-registration',
              body: {'email': creds.email, 'password': creds.password},
            )
            .timeout(const Duration(seconds: 30));
        final ok = (response.data as Map?)?['deleted'] == true;
        if (!ok) {
          final err =
              (response.data as Map?)?['error']?.toString() ??
              'Unbekannter Fehler';
          throw StateError(err);
        }
        await ref.read(authProvider.notifier).logout();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'email.deleted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.login);
    } catch (e) {
      debugPrint('[EmailVerification] Abbrechen fehlgeschlagen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.tf(context, 'email.deleteFailed', {'error': '$e'}),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resend() async {
    if (_resending || _showSent || _cooldownSeconds > 0) return;
    setState(() => _resending = true);

    try {
      final email =
          _capturedEmail ?? SupabaseService.client.auth.currentUser?.email;
      if (email == null || email.isEmpty) {
        throw Exception(
          'Keine Emailadresse gefunden. Bitte registriere dich erneut.',
        );
      }
      // Bei aktivierter Dashboard-CAPTCHA verlangt auch der Resend-
      // Endpoint ein Token – vorher schlug "Erneut senden" mit
      // captcha_failed fehl.
      String? captchaToken;
      if (AppConstants.captchaEnabled) {
        captchaToken = await showCaptchaChallenge(context);
        if (captchaToken == null) {
          // Nutzer hat die Challenge abgebrochen – kein Versand.
          if (mounted) setState(() => _resending = false);
          return;
        }
      }
      await SupabaseService.client.auth.resend(
        type: OtpType.signup,
        email: email,
        captchaToken: captchaToken,
      );
      if (!mounted) return;

      // Kurze Erfolgs-Animation im Button ("E-Mail gesendet"), danach
      // sichtbarer Countdown bis zum nächsten erlaubten Versand.
      setState(() {
        _resending = false;
        _showSent = true;
      });
      _sentTimer = Timer(_sentAnimationDuration, () {
        if (!mounted) return;
        setState(() {
          _showSent = false;
          _cooldownSeconds = _resendCooldownDuration.inSeconds;
        });
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() => _cooldownSeconds--);
          if (_cooldownSeconds <= 0) t.cancel();
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'email.resent')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        // Bei Fehler Button sofort wieder freigeben (kein Cooldown).
        setState(() => _resending = false);
        final msg = e.toString();
        final display = msg.contains('rate_limit')
            ? L10n.t(context, 'email.rateLimited')
            : L10n.tf(context, 'common.errorWith', {'error': msg});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(display), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirmed = ref.watch(emailConfirmedProvider);
    final supabaseActive = SupabaseService.isInitialized;

    final statusText = switch (isConfirmed) {
      true => L10n.t(context, 'email.confirmed'),
      null =>
        supabaseActive
            ? L10n.t(context, 'email.waiting')
            : L10n.t(context, 'email.demoContinue'),
      false => L10n.t(context, 'email.waiting'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'email.title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.mark_email_read,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              L10n.t(context, 'email.heading'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              L10n.t(context, 'email.body'),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed:
                  (isConfirmed == true ||
                      isConfirmed == null && !supabaseActive ||
                      _resending ||
                      _showSent ||
                      _cooldownSeconds > 0)
                  ? null
                  : _resend,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: _resending
                    ? const SizedBox(
                        key: ValueKey('resending'),
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _showSent
                    ? const Icon(
                        Icons.check_circle,
                        key: ValueKey('sent'),
                        color: Colors.green,
                      )
                    : const Icon(Icons.refresh, key: ValueKey('idle')),
              ),
              label: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _resending
                      ? L10n.t(context, 'email.sending')
                      : _showSent
                      ? L10n.t(context, 'email.sent')
                      : _cooldownSeconds > 0
                      ? L10n.tf(context, 'email.cooldown', {
                          's': '$_cooldownSeconds',
                        })
                      : L10n.t(context, 'email.resend'),
                  key: ValueKey(
                    'label-${_resending
                        ? 'sending'
                        : _showSent
                        ? 'sent'
                        : _cooldownSeconds > 0
                        ? 'cooldown'
                        : 'idle'}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Manueller Weiter-Weg nach der Bestätigung: löst die
            // Capttha-Challenge + stillen Login aus (oder führt zum
            // Login-Screen, falls die Registrierungs-Daten abgelaufen
            // sind). Ohne diesen Button hing der Screen, wenn die App
            // während der Mail-Bestätigung offen blieb.
            FilledButton.icon(
              onPressed:
                  (isConfirmed == true || _autoLoginInProgress || _resending)
                  ? null
                  : _manualContinue,
              icon: const Icon(Icons.arrow_forward),
              label: Text(L10n.t(context, 'email.continueBtn')),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            // Hinweis: DNS-Filter/VPNs können den Bestätigungslink blockieren.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'email.dnsHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.bugReport),
              icon: const Icon(Icons.bug_report, size: 18),
              label: Text(L10n.t(context, 'email.reportIssue')),
            ),
            TextButton.icon(
              // Ausweg, falls die Session serverseitig nicht (mehr) existiert
              // und die Bestätigung daher nie gelingen kann: ausloggen und
              // neu registrieren/anmelden.
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (mounted && context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: Text(L10n.t(context, 'email.logout')),
            ),
            TextButton.icon(
              // Nutzer-Regel: Abbrechen löscht den noch unbestätigten
              // Account in Supabase (siehe _cancelRegistration).
              onPressed: _cancelRegistration,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              label: Text(
                L10n.t(context, 'email.cancel'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
