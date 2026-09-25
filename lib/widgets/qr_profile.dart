import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Zeigt den QR-Code eines Nutzerprofils an.
///
/// Inhalt des QR-Codes (Deep Link): `thestia://user/<userId>`
///
/// Fallback (fuer Nutzer ohne App): `https://thestia.de/invite/<userId>`
///
/// Beim Scannen:
/// - App installiert → App oeffnet, Profil wird geladen, Chat startbar
/// - App nicht installiert → Fallback-Link oeffnet Browser
class QrProfileWidget extends StatelessWidget {
  const QrProfileWidget({
    super.key,
    required this.userId,
    this.size = 220,
    this.showLabel = true,
  });

  final String userId;
  final double size;
  final bool showLabel;

  String get _deepLink => 'thestia://user/$userId';
  // Fallback für Nutzer ohne App:
  // String get _fallbackUrl => 'https://thestia.de/invite/$userId';

  /// QR enthaelt NUR den Deep-Link.
  String get _qrContent => _deepLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: _qrContent,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF1A1A2E),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 16),
          Text(
            'Scanne diesen Code, um mich\nzu finden und anzuschreiben.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Generiert einen kurzen, teilbaren Nutzer-Code (Threema-Style).
///
/// Basiert auf den ersten 8 Zeichen der User-ID.
/// Kann manuell eingegeben werden, um einen Nutzer zu finden.
String generateUserCode(String userId) {
  final normalized = userId.replaceAll('-', '').toUpperCase();
  return normalized.length >= 8
      ? normalized.substring(0, 8)
      : normalized.padRight(8, '0');
}

