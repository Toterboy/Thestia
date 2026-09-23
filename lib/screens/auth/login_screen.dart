import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wisp/models/gender.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/utils/validators.dart';
import 'package:wisp/widgets/language_switch.dart';
import 'package:wisp/widgets/app_version_footer.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/captcha_challenge.dart';

/// Login & Registrierung (Mock).
///
/// Registrierung erfasst Name, Geburtsdatum (statt Alter), E-Mail,
/// Passwort und Geschlecht - alle Pflichtfelder werden validiert
/// (inkl. 16+-Prüfung basierend auf dem Geburtsdatum).
///
/// Verbesserungen:
/// - Fehler werden erst NACH einer Eingabe oder einem Absende-Versuch gezeigt.
/// - Eindeutige Fehlermeldungen bei falschen Zugangsdaten bzw. technischen
///   Fehlern.
/// - Ladeanzeige (Spinner) im Button während der Netzwerk-Aktion.
/// - "Passwort anzeigen"-Icon sowie "Passwort vergessen?"-Link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  Gender _gender = Gender.diverse;
  DateTime? _birthDate;
  // Login-Modus als Default: Beim Erststart führt der Router zuerst über die
  // Willkommensscreens; der "Konto erstellen"-Modus soll nicht vorab als
  // erstes sichtbar sein (und auch bei transientem Rendern nicht aufblitzen).
  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _submitAttempted = false;
  bool _passkeyLoading = false;
  bool _submitting = false;

  /// Alters-Wahrheits-Bestätigung (v0.9.1, Pflicht bei Registrierung):
  /// Falsche Altersangaben gefährden insbesondere junge Nutzer und führen
  /// zum Ausschluss.
  bool _ageConfirmed = false;

  /// „Angemeldet bleiben" (Default: AN). Wird beim Start gelesen und beim
  /// Umschalten sofort persistiert; der Restore im AuthNotifier respektiert
  /// den Wert (false = Session beim Start verwerfen).
  bool _keepLoggedIn = true;

  @override
  void initState() {
    super.initState();
    _loadKeepLoggedIn();
  }

  Future<void> _loadKeepLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _keepLoggedIn = prefs.getBool('keep_logged_in') ?? true);
    }
  }

  Future<void> _persistKeepLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_logged_in', value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ??
          DateTime(DateTime.now().year - 18, DateTime.now().month,
              DateTime.now().day),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Wähle dein Geburtsdatum',
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      // NICHT _formKey.currentState?.validate() aufrufen!
      // Validierung erfolgt erst nach Klick auf "Registrieren"/"Anmelden"
      // über _submitAttempted-State und autovalidateMode.
    }
  }

  Future<void> _submit() async {
    debugPrint('[LoginScreen] _submit aufgerufen (isRegister=$_isRegister)');
    // Markiere, dass ein Absende-Versuch stattfand - erst jetzt dürfen
    // die Pflichtfeld-Fehler angezeigt werden.
    setState(() => _submitAttempted = true);
    if (!_formKey.currentState!.validate()) {
      debugPrint('[LoginScreen] Validierung fehlgeschlagen - Abbruch.');
      return;
    }

    // Eigener Ladezustand für den Absende-Button. Bewusst NICHT an
    // `authProvider.isLoading` gekoppelt: Sonst wären auch der
    // "Passwort vergessen?"-Button und der Modus-Wechsel während eines
    // (langsamen) Logins deaktiviert bzw. der ganze Screen wirkte "laggy".
    setState(() => _submitting = true);
    // Großer, nicht-abwischbarer Ladekreis: Direkt nach dem Klick klar
    // sichtbar (der kleine Button-Spinner allein wurde als
    // "passiert nichts" empfunden).
    unawaited(_showBlockingLoader());
    try {
      final auth = ref.read(authProvider.notifier);
      if (_isRegister) {
        // Geburtsdatum ist im Registrierungs-Modus Pflicht; bei Login
        // (kein Feld) bewusst null lassen.
        final age = Validators.ageFromBirthDate(_birthDate);
        if (age == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.t(context, 'auth.birthDateMissing')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        // Alters-Wahrheit muss explizit bestätigt sein (v0.9.1).
        if (!_ageConfirmed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(L10n.t(context, 'auth.ageConfirmRequired')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        debugPrint('[LoginScreen] Registriere Nutzer...');

        // CAPTCHA (Bot-Schutz): Zeigt die Challenge VOR der Registrierung,
        // wenn im Build konfiguriert (AppConstants.captchaEnabled) – Details
        // siehe widgets/captcha_challenge.dart. Der Nutzer muss die Aufgabe
        // lösen (Token) oder bricht ab.
        String? captchaToken;
        if (AppConstants.captchaEnabled) {
          captchaToken = await showCaptchaChallenge(context);
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
        }

        await auth.register(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          gender: _gender.value,
          birthDate: _birthDate!,
          captchaToken: captchaToken,
        );
        // Profil wurde bereits in AuthNotifier.register() via setProfile()
        // gesetzt – kein redundantes update() nötig.
      } else {
        // CAPTCHA (Bot-Schutz) auch beim Login: gleicher Ablauf wie bei der
        // Registrierung – Challenge lösen oder abbrechen.
        String? captchaToken;
        if (AppConstants.captchaEnabled) {
          captchaToken = await showCaptchaChallenge(context);
          if (captchaToken == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.t(context, 'auth.captchaLogin')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
        }
        await auth.login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          captchaToken: captchaToken,
        );
      }

      final result = ref.read(authProvider);
      if (result.hasError) {
        if (kDebugMode) {
          debugPrint('[LoginScreen] Auth-Provider hat Fehler: ${result.error}');
        }
        if (mounted) {
          final message = result.error is AppException
              ? (result.error as AppException).message
              : L10n.t(context, 'error.generic');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      // Explizite Navigation nach erfolgreichem Login/Registrierung.
      // Der Router-Redirect ist ein Fallback, aber explizites Navigieren ist
      // zuverlässiger (vermeidet Timing-Probleme bei Provider-Initialisierung).
      // Nach Registrierung: zuerst E-Mail-Verifizierung, dann Einstellungen & Privatsphäre.
      // Nach Login: Home - Redirect-Logik leitet basierend auf Setup-Fortschritt weiter.
      debugPrint('[LoginScreen] Auth erfolgreich, navigiere zu: '
          '${_isRegister ? AppRoutes.emailVerification : AppRoutes.home}');
      if (mounted) {
        context.go(
          _isRegister ? AppRoutes.emailVerification : AppRoutes.home,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoginScreen] FEHLER bei ${_isRegister ? "Registrierung" : "Login"}: $e');
        debugPrint('[LoginScreen] Exception-Typ: ${e.runtimeType}');
      }
      if (mounted) {
        String message;
        if (e is EmailBannedException) {
          // Plattform-Sperre (Migration 045): Weiterleitung zum
          // Entsperrungs-Flow statt generischer Fehlermeldung.
          context.go(AppRoutes.unbanRequest, extra: e.email);
          return;
        } else if (e is AppException) {
          // Duplikat-Marker aus SupabaseAuthService.register übersetzen
          // (Supabase selbst meldet bei existierender E-Mail keinen
          // Fehler, siehe dort).
          message = e.message == 'EMAIL_ALREADY_REGISTERED'
              ? L10n.t(context, 'error.alreadyRegistered')
              : e.message;
        } else if (e is AuthException) {
          // Supabase-Fehlertexte nicht direkt anzeigen, sondern übersetzen.
          final lower = e.message.toLowerCase();
          if (lower.contains('invalid login credentials')) {
            message = L10n.t(context, 'error.invalidCredentials');
          } else if (lower.contains('not confirmed')) {
            message = L10n.t(context, 'error.notConfirmed');
          } else if (lower.contains('user already registered') ||
              lower.contains('already_exists') ||
              lower.contains('may have been registered')) {
            message = L10n.t(context, 'error.alreadyRegistered');
          } else if (lower.contains('too many') || lower.contains('rate')) {
            message = L10n.t(context, 'error.rateLimited');
          } else if (lower.contains('weak password')) {
            // zxcvbn-Komplexitäts-Prüfung (Password Strength Policy im
            // Dashboard): Länge allein reicht nicht.
            message = L10n.t(context, 'error.weakPassword');
          } else if (lower.contains('password should')) {
            // Server-Meldung durchreichen (z. B. "Password should be at
            // least 12 characters") – die Mindestlänge steht im Dashboard.
            message = e.message;
          } else if (lower.contains('captcha')) {
            message = L10n.t(context, 'error.captchaRejected');
          } else if (lower.contains('database error') ||
              lower.contains('saving new user')) {
            message = L10n.t(context, 'error.signupFailed');
          } else {
            // Generischer Fallback. Im Debug-Modus wird die Original-
            // Server-Meldung direkt mit angezeigt, damit die Ursache
            // ohne Konsole sichtbar wird (Produktiv-Builds bleiben
            // generisch).
            message = kDebugMode
                ? '${L10n.t(context, 'error.loginFailed')} (Server: ${e.message})'
                : L10n.t(context, 'error.loginFailed');
          }
        } else {
          message = kDebugMode
              ? '${L10n.t(context, 'error.generic')} (${e.runtimeType}: $e)'
              : L10n.t(context, 'error.generic');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    } finally {
      _dismissBlockingLoader();
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Großer, nicht-abwischbarer Ladekreis während der Auth-Anfrage.
  /// Optik (Fix "hochkant rechteckig"): kompakte, abgerundet-viereckige
  /// Karte mit zentriertem Spinner. Der Column aus Spinner + Text ergab
  /// vorher einen unpassenden Hochformat-Kasten.
  Future<void> _showBlockingLoader() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _dismissBlockingLoader() {
    if (mounted &&
        Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Meldet den Nutzer per Passkey (WebAuthn) an, ohne E-Mail/Passwort.
  ///
  /// Läuft NUR im Supabase-Modus und über denselben Pfad wie die
  /// Passwort-Anmeldung ([AuthNotifier.loginWithPasskey]): Ladezustand
  /// (Ladekreis), Aufräumen und Server-Sync. Nach erfolgreicher Zeremonie
  /// wird explizit zu Home navigiert - der Router-Redirect leitet je nach
  /// Setup-Fortschritt weiter.
  Future<void> _signInWithPasskey() async {
    setState(() => _passkeyLoading = true);
    // Großer, nicht-abwischbarer Ladekreis - wie bei der Passwort-
    // Anmeldung (Nutzerwunsch: klar sichtbares Feedback direkt nach dem
    // Tap, der kleine Button-Spinner allein reichte nicht).
    unawaited(_showBlockingLoader());
    try {
      // Bei aktivierter Dashboard-CAPTCHA verlangt der Server auch für
      // den Passkey-Login ein Token (wie beim normalen Login), sonst
      // lehnt er die Anfrage direkt ab, bevor der native Dialog
      // erscheint. Der Passkey-Button zeigt solange den Ladekreis.
      String? captchaToken;
      if (AppConstants.captchaEnabled) {
        captchaToken = await showCaptchaChallenge(context);
        if (captchaToken == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.t(context, 'auth.captchaLogin')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }
      await ref.read(authProvider.notifier).loginWithPasskey(
            captchaToken: captchaToken,
          );
      // Explizite Navigation nach erfolgreichem Login - wie im
      // Passwort-Pfad (zuverlässiger als der Router-Redirect allein).
      debugPrint('[LoginScreen] Passkey-Login erfolgreich, navigiere zu Home');
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        final message = e is AppException
            ? L10n.exc(context, e)
            : (e.toString().toLowerCase().contains('cancel')
                ? L10n.t(context, 'auth.passkeyCancelled')
                : L10n.t(context, 'auth.passkeyFailed'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      _dismissBlockingLoader();
      if (mounted) setState(() => _passkeyLoading = false);
    }
  }

  /// Formularfeld mit fest reserviertem Platz für die Fehlermeldung,
  /// damit sich die anderen Felder bei Validierungsfehlern nicht verschieben.
  ///
  /// [showError] steuert, ob die Fehlermeldung überhaupt angezeigt wird - erst
  /// nach einer Eingabe oder nach einem Absende-Versuch.
  Widget _field({
    required Widget child,
    String? Function()? validate,
    bool showError = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        // Fester, reservierter Bereich für die Fehlermeldung (2 Zeilen).
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: FormField<String>(
            validator: (_) => showError ? validate?.call() : null,
            builder: (field) => field.errorText == null
                ? const SizedBox.shrink()
                : Text(
                    field.errorText!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bewusst KEINE AppBar (Rückmeldung UX): Die "Einloggen"-Überschrift
    // war redundant zur "Willkommen zurück"-Headline und hat den Inhalt
    // unnötig nach unten gedrückt. Herz, Headline und Sprach-Button
    // rücken dadurch höher.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              autovalidateMode: _submitAttempted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.favorite, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  // Überschrift mit Sprach-Button auf derselben Höhe
                  // (rechtsbündig). Der Stack hält die Überschrift exakt
                  // zentriert; Clip.none erlaubt dem 48-px-Buttons, die
                  // schmalere Zeilenhöhe der Überschrift zu überragen.
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Text(
                        _isRegister
                            ? L10n.t(context, 'auth.registerTitle')
                            : L10n.t(context, 'auth.welcomeBack'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: LanguageSwitch(compact: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isRegister) ...[
                     _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _nameCtrl,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                              labelText: L10n.t(context, 'auth.name')),
                          validator: (v) => Validators.name(context, v),
                        ),
                      ),
                      _field(
                        showError: _submitAttempted,
                        validate: () => Validators.birthDate(context, _birthDate),
                        child: InkWell(
                          onTap: _pickBirthDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'auth.birthDate'),
                              hintText: L10n.t(context, 'auth.birthDateHint'),
                              errorText: _submitAttempted
                                  ? Validators.birthDate(context, _birthDate)
                                  : null,
                            ),
                            child: Text(
                              _birthDate == null
                                  ? L10n.t(context, 'auth.birthDatePick')
                                  : '${_birthDate!.day}.${_birthDate!.month}.'
                                      '${_birthDate!.year}',
                            ),
                          ),
                        ),
                      ),
                      _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                              labelText: L10n.t(context, 'auth.email')),
                          validator: (v) => Validators.email(context, v),
                        ),
                      ),
                       _field(
                         showError: _submitAttempted,
                         child: TextFormField(
                           controller: _passwordCtrl,
                           keyboardType: TextInputType.text,
                           obscureText: _obscurePassword,
                           textInputAction: TextInputAction.done,
                           onFieldSubmitted: (_) => _submit(),
                           decoration: InputDecoration(
                            labelText: L10n.t(context, 'auth.password'),
                            helperText: L10n.t(
                                context, 'auth.passwordHintStrong'),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              tooltip: _obscurePassword
                                  ? L10n.t(context, 'auth.showPassword')
                                  : L10n.t(context, 'auth.hidePassword'),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                           validator: (v) =>
                               Validators.registrationPassword(context, v),
                         ),
                       ),
                        _field(
                          child: DropdownButtonFormField<Gender>(
                           initialValue: _gender,
                           // Abgerundetes Auswahlmenü (konsistent mit
                           // popupMenuTheme/Cards, 16 px).
                           borderRadius: BorderRadius.circular(16),
                           decoration: InputDecoration(
                              labelText: L10n.t(context, 'auth.gender')),
                           items: [
                             DropdownMenuItem(
                                 value: Gender.male,
                                 child: Text(L10n.t(context, 'gender.male'))),
                             DropdownMenuItem(
                                 value: Gender.maleTrans,
                                 child: Text(L10n.t(context, 'gender.maleTrans'))),
                             DropdownMenuItem(
                                 value: Gender.female,
                                 child: Text(L10n.t(context, 'gender.female'))),
                             DropdownMenuItem(
                                 value: Gender.femaleTrans,
                                 child: Text(L10n.t(context, 'gender.femaleTrans'))),
                             DropdownMenuItem(
                                 value: Gender.diverse,
                                 child: Text(L10n.t(context, 'gender.diverse'))),
                             DropdownMenuItem(
                                 value: Gender.other,
                                 child: Text(L10n.t(context, 'gender.other'))),
                           ],
                            onChanged: (v) {
                              if (v != null) setState(() => _gender = v);
                            },
                          ),
                        ),
                        _field(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(L10n.t(context,
                                    'auth.ageConfirmTitle')),
                                subtitle: Text(L10n.t(context,
                                    'auth.ageConfirmSub')),
                                value: _ageConfirmed,
                                onChanged: (v) => setState(
                                    () => _ageConfirmed = v ?? false),
                              ),
                              if (_submitAttempted && !_ageConfirmed)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 16, top: 4),
                                  child: Text(
                                    L10n.t(context,
                                        'auth.ageConfirmRequired'),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                L10n.t(
                                    context, 'auth.liabilityNote'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                     ] else ...[
                     _field(
                       showError: _submitAttempted,
                       child: TextFormField(
                         controller: _emailCtrl,
                         keyboardType: TextInputType.text,
                         decoration: InputDecoration(
                             labelText: L10n.t(context, 'auth.email')),
                          validator: (v) => Validators.email(context, v),
                       ),
                     ),
                      _field(
                        showError: _submitAttempted,
                        child: TextFormField(
                          controller: _passwordCtrl,
                          keyboardType: TextInputType.text,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                           decoration: InputDecoration(
                             labelText: L10n.t(context, 'auth.password'),
                             helperText:
                                 L10n.t(context, 'auth.passwordHint'),
                             suffixIcon: IconButton(
                               icon: Icon(_obscurePassword
                                   ? Icons.visibility_off
                                   : Icons.visibility),
                               tooltip: _obscurePassword
                                   ? L10n.t(context, 'auth.showPassword')
                                   : L10n.t(context, 'auth.hidePassword'),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) => Validators.password(context, v),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_submitting || _passkeyLoading)
                              ? null
                              : () => context.go(AppRoutes.forgotPassword),
                          child: Text(L10n.t(context, 'auth.forgot')),
                        ),
                      ),
                      CheckboxListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(L10n.t(context, 'auth.keepLoggedIn')),
                        subtitle: Text(
                          L10n.t(context, 'auth.keepLoggedInSub'),
                        ),
                        value: _keepLoggedIn,
                        onChanged: (v) {
                          setState(() => _keepLoggedIn = v ?? true);
                          _persistKeepLoggedIn(_keepLoggedIn);
                        },
                      ),
                   ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _submitting
                        ? L10n.t(context, 'common.loading')
                        : L10n.t(
                            context,
                            _isRegister
                                ? 'auth.register'
                                : 'auth.login',
                          ),
                    onPressed: _submitting ? null : _submit,
                    loading: _submitting,
                  ),
                  if (!_isRegister && SupabaseService.isInitialized) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          (_submitting || _passkeyLoading) ? null : _signInWithPasskey,
                      icon: _passkeyLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.fingerprint),
                      label: Text(L10n.t(context, 'auth.passkey')),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_submitting || _passkeyLoading)
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                              _submitAttempted = false;
                            }),
                    child: Text(
                      _isRegister
                          ? L10n.t(context, 'auth.toLogin')
                          : L10n.t(context, 'auth.toRegister'),
                    ),
                  ),
                   const SizedBox(height: 8),
                   const AppVersionFooter(),
                   const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

