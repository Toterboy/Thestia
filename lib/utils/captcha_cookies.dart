/// Drittanbieter-Cookies fuer die CAPTCHA-WebView (Android).
///
/// WARUM ES DAS GIBT (24.10.2026):
///
/// Der Android-WebView hat Drittanbieter-Cookies **per Voreinstellung
/// aus** (so seit Android 5 / Lollipop, fuer Apps mit targetSdk 21+).
/// Turnstile legt seine Challenge-Session in genau diesen Cookies ab.
/// Ohne sie kommt die Challenge nicht durch, der Widget meldet einen
/// Fehler, und die Registrierung bleibt haengen - mitten in der
/// WebView, ohne erkennbare Ursache.
///
/// Die Seite selbst liegt auf `auth.thestia.de`, die Challenge auf
/// `challenges.cloudflare.com`. Fuer den Browser ist die Challenge
/// damit ein Drittanbieter - und genau dafuer braucht es die Erlaubnis.
///
/// DIESER DATEI GEHOERT ZUR APP, NICHT IN DEN STORE: Es geht um die
/// Technik des WebView, nicht um Daten. Es werden keine Inhalte
/// gespeichert, die nicht schon in der WebView selbst stehen.
///
/// Die Aufrufe sind auf Android beschraenkt: `setAcceptThirdPartyCookies`
/// gibt es nur in der Android-Implementierung. Auf anderen Plattformen
/// ist diese Datei ein leerer Stub (captcha_cookies_stub.dart).
library;

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Aktiviert Cookies fuer die CAPTCHA-WebView.
///
/// [controller] ist der WebView-Controller der Challenge. Der Aufruf
/// ist ein Fehler-Fang: Wenn die Android-Implementierung nicht
/// verfuegbar ist (aelteres WebView, Nicht-Android), laeuft die
/// Challenge ohne die Erweiterung weiter - dann gilt der alte Zustand,
/// aber es gibt keinen Absturz.
Future<void> enableCaptchaCookies(WebViewController controller) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (WebViewPlatform.instance is! AndroidWebViewPlatform) return;
    final android = controller.platform as AndroidWebViewController;
    // Drittanbieter-Cookies: die Challenge von challenges.cloudflare.com
    // ist fuer die Seite auth.thestia.de ein Drittanbieter. Erstanbieter-
    // Cookies sind im WebView per Voreinstellung erlaubt.
    //
    // Der Manager wird ueber die plattformuebergreifende
    // WebViewCookieManager geholt - auf Android ist das ein
    // AndroidWebViewCookieManager, der die Android-Methode anbietet.
    final manager = WebViewCookieManager();
    if (manager.platform is AndroidWebViewCookieManager) {
      await (manager.platform as AndroidWebViewCookieManager)
          .setAcceptThirdPartyCookies(android, true);
    }
  } catch (e) {
    // Kein Grund fuer einen Absturz - die Challenge laeuft ohne diese
    // Erweiterung notfalls mit einem Fehler, den der Nutzer sieht.
    debugPrint('[CAPTCHA] Cookies konnten nicht aktiviert werden: $e');
  }
}
