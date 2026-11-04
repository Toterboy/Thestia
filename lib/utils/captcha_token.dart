/// Formatprüfung für das Turnstile-Token.
///
/// WARUM EINE EIGENE DATEI (04.11.2026): Die Prüfung stand als private
/// Methode im Widget und war damit nicht testbar - und genau dort ist
/// der Fehler passiert, den sie verhindern sollte.
///
/// DER FEHLER: Die Prüfung verlangte ein Token mit dem Präfix `0.`.
/// Cloudflare liefert aber inzwischen `1.` - live gemessen am
/// 04.11.2026 gegen https://auth.thestia.de/:
///
///     Länge 837, Präfix "1.lAbV5RcI1e…", Zeichenmenge
///     - . 0-9 A-Z _ a-z
///
/// Ergebnis in der App: jedes gültige Token wurde als
/// `CAPTCHA_ERROR:invalid-token` verworfen, die Registrierung war für
/// alle nicht mehr möglich. Der Fehler sah aus wie ein Angriff auf den
/// Sicherheitscheck - tatsächlich war es die Prüfung selbst, die zu
/// streng war.
///
/// DIE REGEL: Das Präfix ist die FORMATVERSION, keine feste
/// Zeichenfolge. Deshalb wird eine Ziffer als Version zugelassen
/// (`0.`, `1.`, und was morgen kommt), nicht nur `0.`.
library;

/// Ist [text] ein plausibles Turnstile-Token?
///
/// Zugelassen sind:
///   * eine Ziffer als Formatversion, danach ein Punkt
///     (`0.` war der Stand bis 2026, `1.` seit November 2026),
///   * danach eine Zeichenkette aus Buchstaben, Ziffern, `_`, `-` und
///     `.` - das ist das base64url-Alphabet, in dem Cloudflare den
///     Payload liefert (der Payload selbst enthält Punkte).
///
/// Abgelehnt wird alles andere: beliebige Zeichenketten aus einer
/// manipulierten Seite oder einem Iframe. Diese Prüfung ist die
/// Gegenmaßnahme gegen genau das - sie darf nicht strenger sein als
/// das echte Format, sonst sperrt sie die App aus.
bool isTurnstileToken(String text) {
  if (text.length < 8 || text.length > 4096) return false;
  return RegExp(r'^\d\.[A-Za-z0-9_.-]+$').hasMatch(text);
}
