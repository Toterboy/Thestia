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
/// [kDonateUrl] ist bewusst leer. Solange sie leer ist, passiert beim
/// Antippen nichts weiter als ein Hinweis - es wird KEIN Platzhalter
/// aufgerufen und nichts angezeigt, was so aussieht, als haette
/// gespendet. Erst eine echte Zieladresse (z. B. bei einem
/// Zahlungsanbieter oder auf einem eigenen Unterstuetzungs-Bereich)
/// macht den Button vollstaendig.
const String kDonateUrl = '';

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

    if (kDonateUrl.isEmpty) {
      await _explainMissingLink(context);
      return;
    }

    final uri = Uri.tryParse(kDonateUrl);
    if (uri == null) {
      _toast(messenger, failedText);
      return;
    }
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      _toast(messenger, failedText);
      return;
    }
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
  if (kDonateUrl.isEmpty) {
    await HapticFeedback.selectionClick();
    return;
  }
  await launchUrl(Uri.parse(kDonateUrl),
      mode: LaunchMode.externalApplication);
}
