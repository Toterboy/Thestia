import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Spenden-Button.
///
/// Der Button existierte bis v0.4.0 und wurde beim UI-Umbau zusammen mit
/// den Spender-Badges entfernt - zu Recht, weil die Zahlung damals eine
/// Attrappe war. Jetzt ist er wieder da, aber ohne Attrappe: es gibt
/// keine erfundene Buchung, keine "Danke"-Bestaetigung ohne Zahlung und
/// kein Spender-Badge. Der Button oeffnet genau einen Link.
///
/// ZIEL EINSTELLEN
///
/// Die Adresse kommt aus dem Build, nicht aus dem Quelltext:
///
///     .env:  LIBERAPAY_URL=https://liberapay.com/<dein-name>/
///     bauen: powershell -File tool\build_release.ps1 ...
///
/// Warum als Build-Wert und nicht als Konstante hier: die Kuerzel des
/// Zahlungsanbieters sind oeffentlich, aber sie aendern sich je Konto.
/// Wer sie fest in den Quelltext schreibt, muss fuer jeden Wechsel eine
/// Aenderung einchecken und danach den Build erneut verteilen - das ist
/// genau der Fehler, den [kDonateUrl] als Leerstring ueber Jahre
/// konserviert hat: niemand wusste mehr, dass hier etwas einzutragen war.
///
/// Bleibt der Wert leer, passiert beim Antippen nichts weiter als ein
/// Hinweis. Es wird KEIN Platzhalter aufgerufen und nichts angezeigt,
/// was so aussieht, als haette gespendet.
const String kDonateUrl = String.fromEnvironment('LIBERAPAY_URL');

/// Ist ein Zahlungsziel hinterlegt?
bool get donateConfigured => kDonateUrl.trim().isNotEmpty;

class DonateButton extends StatelessWidget {
  const DonateButton({super.key, this.icon});

  /// Optionales Icon. Ohne Icon wird eine eigene Spenden-Glyphe
  /// gezeichnet, damit die Schenkform nicht mit einem Standard-Icon
  /// (z. B. `Icons.favorite`) verwechselt wird - das steht in der App
  /// bereits fuer "Gefällt mir".
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Icon(icon, size: 20, color: scheme.primary)
              else
                const _GiftGlyph(),
              const SizedBox(width: 10),
              Text(
                L10n.t(context, 'profile.donateBtn'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    // Texte und Messenger VOR dem ersten await holen. Nach einem await
    // ist der Context moeglicherweise weg (Route gepoppt) - und der
    // Analyzer moniert zu Recht, ihn dann noch zu benutzen.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failedText = L10n.t(context, 'profile.donateOpenFailed');

    if (!donateConfigured) {
      await _explainMissingLink(context);
      return;
    }

    final uri = Uri.tryParse(kDonateUrl);
    if (uri == null) {
      _toast(messenger, failedText);
      return;
    }
    // Kein canLaunchUrl() davor. Die Abfrage gilt seit Android 11 als
    // unzuverlaessig: ohne <queries> im Manifest liefert sie `false`,
    // obwohl ein Browser installiert ist und der Aufruf funktionieren
    // wuerde. Sie als Tor zu benutzen hiess hier, jede Web-Seite als
    // "kann nicht geoeffnet werden" zu melden. Der Aufruf selbst
    // entscheidet, nicht die Vorabfrage.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _toast(messenger, failedText);
    }
  }

  /// Erklaert offen, dass keine Zieladresse hinterlegt ist.
  ///
  /// Bewusst als Dialog mit nur einem Knopf: der Nutzer soll hier keine
  /// Moeglichkeit bekommen, etwas zu bestaetigen, das nicht passiert.
  Future<void> _explainMissingLink(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(L10n.t(context, 'profile.donateTitle')),
        content: Text(L10n.t(context, 'profile.donateNotConfigured')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.t(context, 'common.close')),
          ),
        ],
      ),
    );
  }

  void _toast(ScaffoldMessengerState? messenger, String text) {
    messenger?.showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Kleine Schenk-Glyphe.
///
/// Bewusst gezeichnet statt `Icons.card_giftcard`: die Material-Glyphe
/// zeigt ein Geschenk mit Schleife und wirkt in der App wie ein
/// weiteres Standard-Icon. Hier ist es eine einfache Schenkbox mit
/// Deckel und Band, gezeichnet in derselben Strichstaerke wie die
/// anderen eigengen Glyphen der App.
class _GiftGlyph extends StatelessWidget {
  const _GiftGlyph();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GiftPainter(c)),
    );
  }
}

class _GiftPainter extends CustomPainter {
  _GiftPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.11;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Box
    final boxTop = h * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.10, boxTop, w * 0.80, h * 0.48),
        Radius.circular(w * 0.10),
      ),
      paint,
    );
    // Deckel
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, h * 0.24, w * 0.92, h * 0.20),
        Radius.circular(w * 0.08),
      ),
      paint,
    );
    // Band
    canvas.drawLine(
      Offset(w * 0.50, h * 0.24),
      Offset(w * 0.50, h * 0.90),
      paint,
    );
    // Schleife links und rechts
    canvas.drawCircle(Offset(w * 0.36, h * 0.17), w * 0.10, paint);
    canvas.drawCircle(Offset(w * 0.64, h * 0.17), w * 0.10, paint);
  }

  @override
  bool shouldRepaint(_GiftPainter old) => old.color != color;
}

/// Kleiner Helfer fuer Screens, die den Button nur als Textzeile
/// einbauen wollen.
Future<void> openDonateLink(BuildContext context) async {
  if (!donateConfigured) {
    await HapticFeedback.selectionClick();
    return;
  }
  await launchUrl(Uri.parse(kDonateUrl),
      mode: LaunchMode.externalApplication);
}
