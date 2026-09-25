import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Chat-Hintergründe (v0.9.1): vorgefertigte Muster oder eigenes Bild.
///
/// IDs: 'none', 'dots', 'lines', 'hearts', 'stars', 'waves', 'custom'.
/// Die Auswahl (`chatBackground`) wird serverseitig in `ui_prefs`
/// gespiegelt; der lokale Pfad eines eigenen Bildes (`chatBackgroundPath`)
/// bleibt bewusst NUR auf dem Gerät.
class ChatBackgrounds {
  ChatBackgrounds._();

  static const String none = 'none';
  static const String dots = 'dots';
  static const String lines = 'lines';
  static const String hearts = 'hearts';
  static const String stars = 'stars';
  static const String waves = 'waves';
  static const String custom = 'custom';

  /// Vorgefertigte Muster in Anzeigereihenfolge (ohne 'none'/'custom').
  static const List<String> presets = [dots, lines, hearts, stars, waves];

  /// Gültige IDs (wird beim Laden validiert).
  static bool isValid(String id) =>
      id == none || id == custom || presets.contains(id);

  /// L10n-Schlüssel für die Anzeige-Namen.
  static String labelKey(String id) => 'chatbg.$id';

  /// Wird beim App-Start einmalig gesetzt (sync, kein Future).
  static String? _appDocsDir;

  /// Bindet das App-Dokumentenverzeichnis für die Pfadprüfung des
  /// eigenen Hintergrundbildes.
  static void bindAppDocsDir(String dir) => _appDocsDir = dir;

  /// Liegt [file] im App-Dokumentenverzeichnis und ist es der
  /// Hintergrund-Dateiname? Schützt davor, dass ein manipulierter
  /// Einstellungs-Import einen beliebigen Dateipfad als Hintergrund
  /// einschleust.
  static bool isOwnBackgroundFile(File file) {
    final docs = _appDocsDir;
    if (docs == null) return false;
    return file.path.startsWith(docs) &&
        file.path.endsWith('chat_bg_custom.jpg');
  }
}

/// Zeigt den gewählten Chat-Hintergrund als füllendes Widget.
///
/// - 'none': transparent (Standard-Theme-Hintergrund).
/// - Presets: dezente Muster in der Primärfarbe (funktioniert in
///   Hell- und Dunkelmodus).
/// - 'custom': eigenes Bild (Dateipfad) mit abdunkelndem Overlay für
///   Lesbarkeit; fehlt die Datei, Fallback auf transparent.
class ChatBackgroundView extends StatelessWidget {
  const ChatBackgroundView({
    super.key,
    required this.backgroundId,
    this.customPath,
  });

  final String backgroundId;
  final String? customPath;

  @override
  Widget build(BuildContext context) {
    if (backgroundId == ChatBackgrounds.custom && customPath != null) {
      final file = File(customPath!);
      // Nur Bilder aus dem App-eigenen Verzeichnis rendern: Der Pfad
      // stamm aus lokalen Einstellungen. Würde dort ein beliebiger Pfad
      // (z. B. über einen manipulierten Datenimport) landen, sollen keine
      // fremden Dateien als Hintergrund erscheinen.
      if (!_isOwnAppFile(file)) return const SizedBox.shrink();
      // cacheWidth begrenzt den dekodierten Bitmap-Speicher auf die
      // tatsächlich benötigte Auflösung (statt voller Bildgröße).
      final logicalWidth = MediaQuery.sizeOf(context).width;
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            file,
            fit: BoxFit.cover,
            cacheWidth: (logicalWidth * 2).round().clamp(320, 2400),
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          // Overlay für Lesbarkeit in beiden Modi.
          Container(
            color: Theme.of(context)
                .scaffoldBackgroundColor
                .withValues(alpha: 0.55),
          ),
        ],
      );
    }
    if (backgroundId == ChatBackgrounds.none ||
        !ChatBackgrounds.presets.contains(backgroundId)) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _PatternPainter(
        id: backgroundId,
        color: Theme.of(context).colorScheme.primary,
      ),
      child: const SizedBox.expand(),
    );
  }

  /// Liegt [file] im App-Dokumentenverzeichnis? Siehe
  /// [ChatBackgrounds.isOwnBackgroundFile].
  static bool _isOwnAppFile(File file) =>
      ChatBackgrounds.isOwnBackgroundFile(file);
}

/// Zeichnet die Muster dezent (Alpha ~0.10), Kachelgröße 56 px.
class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.id, required this.color});

  final String id;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const tile = 56.0;
    switch (id) {
      case ChatBackgrounds.dots:
        for (var y = tile / 2; y < size.height + tile; y += tile) {
          for (var x = tile / 2; x < size.width + tile; x += tile) {
            canvas.drawCircle(Offset(x, y), 3, paint);
          }
        }
      case ChatBackgrounds.lines:
        for (var d = -size.height; d < size.width + size.height; d += 18) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height),
              stroke);
        }
      case ChatBackgrounds.hearts:
        var row = 0;
        for (var y = tile / 2; y < size.height + tile; y += tile) {
          final off = (row.isEven ? 0.0 : tile / 2);
          for (var x = tile / 2 + off; x < size.width + tile; x += tile) {
            _heart(canvas, Offset(x, y), 9, paint);
          }
          row++;
        }
      case ChatBackgrounds.stars:
        var row = 0;
        for (var y = tile / 2; y < size.height + tile; y += tile) {
          final off = (row.isEven ? 0.0 : tile / 2);
          for (var x = tile / 2 + off; x < size.width + tile; x += tile) {
            _sparkle(canvas, Offset(x, y), 11, paint);
          }
          row++;
        }
      case ChatBackgrounds.waves:
        for (var y = 0.0; y < size.height + tile; y += 28) {
          final path = Path();
          for (var x = -20.0; x <= size.width + 20; x += 8) {
            final yy = y + 8 * math.sin((x / size.width) * 2 * math.pi);
            if (x <= -20) {
              path.moveTo(x, yy);
            } else {
              path.lineTo(x, yy);
            }
          }
          canvas.drawPath(
              path,
              Paint()
                ..color = color.withValues(alpha: 0.10)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
    }
  }

  /// Kleines Herz aus zwei Kreisen + Dreieck.
  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    canvas.drawCircle(Offset(c.dx - s * 0.35, c.dy - s * 0.2), s * 0.42, paint);
    canvas.drawCircle(Offset(c.dx + s * 0.35, c.dy - s * 0.2), s * 0.42, paint);
    final path = Path()
      ..moveTo(c.dx - s * 0.72, c.dy)
      ..lineTo(c.dx + s * 0.72, c.dy)
      ..lineTo(c.dx, c.dy + s * 0.9)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Vierstrahl-Sparkle (Rhombus).
  void _sparkle(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - s)
      ..lineTo(c.dx + s * 0.28, c.dy - s * 0.28)
      ..lineTo(c.dx + s, c.dy)
      ..lineTo(c.dx + s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx, c.dy + s)
      ..lineTo(c.dx - s * 0.28, c.dy + s * 0.28)
      ..lineTo(c.dx - s, c.dy)
      ..lineTo(c.dx - s * 0.28, c.dy - s * 0.28)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.id != id || old.color != color;
}
