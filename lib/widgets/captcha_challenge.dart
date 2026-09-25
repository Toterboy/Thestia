import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/utils/constants.dart';

/// CAPTCHA-Challenge für Registrierung & Login (Bot-Schutz).
///
/// Lädt die statische Turnstile-Seite `index.html` (gehostet auf
/// `https://auth.thestia.de/`, Ordner `passkey-assets/`) in einem WebView
/// und liefert das Token an die aufrufende Stelle. Das Token wird an
/// `supabase.auth.signUp(...)` bzw. `signInWithPassword(...)` als
/// `captchaToken` übergeben; Supabase validiert es serverseitig gegen das
/// im Dashboard konfigurierte Secret.
///
/// Konfiguration (Operator):
///   1. `passkey-assets/index.html` deployen; dort den Platzhalter
///      `<TURNSTILE_SITE_KEY>` durch den öffentlichen Sitekey ersetzen.
///   2. Cloudflare-Dashboard: Widget-Hostname `auth.thestia.de`
///      registrieren – die Seite wird exakt unter
///      `https://auth.thestia.de/` ausgeliefert (Netlify liefert
///      `index.html` automatisch als Startseite aus).
///   3. Supabase Dashboard → Authentication → CAPTCHA: Turnstile aktivieren
///      + Secret eintragen (Secret liegt NUR dort, nie im Client).
///   4. Beim App-Build:
///      --dart-define=CAPTCHA_PROVIDER=turnstile
///      --dart-define=CAPTCHA_SITEKEY=<öffentlicher Sitekey>
///
/// Ohne beide dart-defines ist das CAPTCHA im Client deaktiviert
/// (AppConstants.captchaEnabled = false) und die Flows laufen wie bisher
/// ohne Token (der Server akzeptiert das nur, solange die Dashboard-Option
/// ebenfalls aus ist).
///
/// Hinweis Web: WebView-basiertes CAPTCHA ist nur für Mobile geeignet;
/// für eine Web-Version müsste später eine HtmlElementView-Anbindung
/// ergänzt werden.
Future<String?> showCaptchaChallenge(BuildContext context) async {
  if (!AppConstants.captchaEnabled) return null;

  if (kIsWeb) {
    if (kDebugMode) {
      debugPrint('[CAPTCHA] Web-Build: WebView-CAPTCHA nicht unterstützt, '
          'Flows laufen ohne Token. Für Web später HtmlElementView nutzen.');
    }
    return null;
  }

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _CaptchaChallengeDialog(),
  );
}

class _CaptchaChallengeDialog extends StatefulWidget {
  const _CaptchaChallengeDialog();

  @override
  State<_CaptchaChallengeDialog> createState() =>
      _CaptchaChallengeDialogState();
}

class _CaptchaChallengeDialogState extends State<_CaptchaChallengeDialog> {
  late final WebViewController _controller;

  /// Lädt die statische Turnstile-Seite von der RP-Domain.
  ///
  /// Wichtig: Turnstile validiert den Hostnamen der aufrufenden Seite gegen
  /// die Widget-Konfiguration. `loadHtmlString` hätte die Origin
  /// `about:blank` und würde abgelehnt – deshalb wird die Seite exakt unter
  /// `https://auth.thestia.de/` ausgeliefert (Netlify, Ordner
  /// `passkey-assets/`, `index.html` als Startseite). Im Cloudflare-
  /// Dashboard muss der Hostname `auth.thestia.de` registriert sein.
  static const String _captchaPageUrl = 'https://auth.thestia.de/';

  /// Fehlertext, falls Turnstile einen Fehler meldet (z. B. abgelaufen).
  String? _error;

  void _handleMessage(String message) {
    if (!mounted) return;
    final text = message.trim();
    if (text.isEmpty) return;
    if (text.startsWith('ERROR:')) {
      // Fehler von onError/onExpired/fehlendem Script: Dialog offen lassen,
      // Nutzer kann erneut versuchen oder abbrechen.
      setState(() => _error = text.substring('ERROR:'.length));
      return;
    }
    // Turnstile-Token (beginnt mit "0.") – Challenge erfolgreich.
    Navigator.of(context).pop(text);
  }

  void _retry() {
    setState(() => _error = null);
    _controller.reload();
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Captcha',
        onMessageReceived: (message) => _handleMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Nur CAPTCHA-/Anbieter-bezogene Navigation erlauben
            // (Startseite, Turnstile-Assets). Host-exakter Vergleich statt
            // startsWith - sonst matchen auch Suffix-Domains wie
            // auth.thestia.de.evil.com.
            final host = Uri.tryParse(request.url)?.host.toLowerCase();
            if (host == 'auth.thestia.de' ||
                host == 'challenges.cloudflare.com' ||
                (host?.endsWith('.challenges.cloudflare.com') ?? false)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(_captchaPageUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(L10n.t(context, 'auth.captcha')),
        content: SizedBox(
          // Cloudflare-Turnstile (managed) ist ~300x65; die interaktive
          // Challenge braucht etwas mehr Platz. Kompakt starten, WebView
          // skaliert den Inhalt auf die Breite.
          width: 300,
          height: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.t(context, 'captcha.retry')),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: WebViewWidget(controller: _controller),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
        ],
      ),
    );
  }
}
