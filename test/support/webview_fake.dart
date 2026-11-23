// Der WebView als Ersatz (fuer den Sicherheitscheck der App).
//
// WARUM (23.11.2026): Das CAPTCHA laeuft in einem WebView - die
// Turnstile-Seite von https://auth.thestia.de/ wird in einem Fenster
// geladen und meldet das Token ueber einen JavaScript-Kanal. Im Test
// gibt es keinen WebView: ohne diesen Ersatz laesst sich der
// Sicherheitscheck gar nicht bauen - und damit auch kein Weg, der auf
// ein Token wartet.
//
// DER ERSATZ merkt sich alles, was die App der WebView ueberlaesst:
// die geladene Adresse, die JavaScript-Kanaele (der Test spielt so die
// Seite, die ein Token oder einen Fehler meldet) und die
// Navigations-Regel (der Test prueft, welche Adressen erlaubt sind).
import 'package:flutter/material.dart';
// Die WebView-Schnittstelle kommt als Transitivum ueber webview_flutter -
// der Ersatz braucht ihre Typen.
// ignore_for_file: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Der Ersatz fuer die WebView-Plattform.
///
/// DER AUFBAU: [WebViewPlatform] ist die Schnittstelle des Pakets
/// `webview_flutter`. Die App spricht nur mit [WebViewController] (dem
/// Paket `webview_flutter`), das wiederum die Plattform fragt. Dieser
/// Ersatz beantwortet die Aufrufe und merkt sich das Ergebnis.
class FakeWebViewPlattform extends WebViewPlatform {
  FakeWebViewPlattform() {
    WebViewPlatform.instance = this;
  }

  /// Die zuletzt geladene Adresse (null = noch nichts geladen).
  Uri? geladeneAdresse;

  /// Die JavaScript-Kanaele: Name -> Handler.
  final Map<String, void Function(JavaScriptMessage)> kanaele =
      <String, void Function(JavaScriptMessage)>{};

  /// Die Navigations-Regel der App (null = keine gesetzt).
  NavigationRequestCallback? navigationRequest;

  /// Die Navigations-Regel, die der Controller bekommen hat.
  PlatformNavigationDelegate? delegate;

  /// Wie oft wurde die Seite neu geladen?
  int neuGeladen = 0;

  /// Spielt eine Meldung der Seite aus (wie der JavaScript-Bridge).
  ///
  /// [text] ist der Inhalt, den die Seite meldet - ein Token oder ein
  /// Fehler wie "ERROR:CAPTCHA_ERROR:110200".
  void sendeAusDerSeite(String text, {String kanal = 'Captcha'}) {
    final handler = kanaele[kanal];
    if (handler == null) {
      throw StateError('Kein JavaScript-Kanal "$kanal" vorhanden');
    }
    handler(JavaScriptMessage(message: text));
  }

  /// Fragt die App, ob eine Adresse erlaubt ist.
  ///
  /// [url] ist die Adresse, die die WebView oeffnen will.
  Future<NavigationDecision> frageNavigation(String url) async {
    final regel = navigationRequest;
    if (regel == null) return NavigationDecision.navigate;
    return regel(NavigationRequest(url: url, isMainFrame: true));
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeWebViewController(this);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(this);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params.controller);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _FakeCookieManager();
}

/// Der Ersatz fuer den Controller der WebView.
class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(this.plattform)
    : super.implementation(const PlatformWebViewControllerCreationParams());

  final FakeWebViewPlattform plattform;

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    plattform.geladeneAdresse = params.uri;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    plattform.kanaele[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> reload() async {
    plattform.neuGeladen++;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    plattform.delegate = handler;
  }
}

/// Der Ersatz fuer die Navigations-Regel.
class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(this.plattform)
    : super.implementation(const PlatformNavigationDelegateCreationParams());

  final FakeWebViewPlattform plattform;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    plattform.navigationRequest = onNavigationRequest;
  }
}

/// Der Ersatz fuer die Anzeige der WebView (nur eine leere Flaeche).
class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(PlatformWebViewController controller)
    : super.implementation(
        PlatformWebViewWidgetCreationParams(controller: controller),
      );

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF202020));
}

/// Der Ersatz fuer die Cookies (die App benutzt sie nicht).
class _FakeCookieManager extends PlatformWebViewCookieManager {
  _FakeCookieManager()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());

  @override
  Future<bool> clearCookies() async => true;

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async =>
      const <WebViewCookie>[];

  @override
  Future<void> setCookie(WebViewCookie cookie) async {}
}
