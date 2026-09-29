import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
    // RepaintBoundary: das Muster ist eine grossflaechige, teure
    // CustomPaint-Zeichnung. Ohne eigene Ebene wird sie bei jedem Repaint des
    // Chat-Screens (Scrollen, neue Nachricht, Animationen) neu gerastert -
    // das kostet spuerbar Strom. Die Ebene merkt sich das fertige Muster und
    // zeichnet es nur neu, wenn sich Farbe/ID aendern.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PatternPainter(
          id: backgroundId,
          color: Theme.of(context).colorScheme.primary,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Liegt [file] im App-Dokumentenverzeichnis? Siehe
  /// [ChatBackgrounds.isOwnBackgroundFile].
  static bool _isOwnAppFile(File file) =>
      ChatBackgrounds.isOwnBackgroundFile(file);
}

/// Zeichnet die Muster dezent (Alpha ~0.10), Kachelgröße 56 px.
///
/// PERFORMANCE – der Grund fuer die Umstellung
/// ------------------------------------------
/// Beim Wechsel hell <-> dunkel aendert sich `colorScheme.primary`, also
/// greift [shouldRepaint] und die bildschirmfuellende Flaeche wird neu
/// gerastert. Das ist der einzige Grund, warum der Chat-Hintergrund
/// sichtbar hinterherläuft, während der Rest der Oberflaeche (nur
/// Farbwerte neu zugewiesen) sofort steht.
///
/// Die alte Fassung baute pro Kachel ein eigenes [Path] und rasterte es
/// sofort. Bei "hearts" auf einem 1080x2400-Geraet sind das rund 817
/// Kacheln x 64 Segmente = ~52.000 Pfad-Segmente, JEDES mit
/// Sinus-/Kosinus-Berechnung, plus 817 Allokationen - pro Repaint.
///
/// Jetzt:
///  - Die Kurvenform wird EINMAL als normalisiertes [Path] gebaut
///    (statisch, app-weit) und pro Kachel nur noch mit [Path.addPath]
///    verschoben. Keine Trigonometrie mehr pro Kachel.
///  - Die Schrittzahl der Herz-Kurve ist von 64 auf 16 gesenkt. Bei
///    11 px Kachelradius ist der Unterschied zwischen einer 16- und
///    64-Ecken-Kurve nicht sichtbar, die Kosten sind aber 4x.
///  - Alle Kacheln eines Musters landen in EINEM [Path] und werden mit
///    einem einzigen [Canvas.drawPath] gezeichnet - 817 Draw-Calls werden 1.
///  - "dots" nutzt [Canvas.drawPoints] (ein Call statt 817).
///  - "waves" zeichnet alle Zeilen in ein Pfad und Abtastung von 8 auf
///    14 px vergrößert; bei 60 px Wellenlänge ist das optisch gleich.
///
/// Zusammen sinkt die Zeichenlast beim Theme-Wechsel um etwa eine
/// Größenordnung, ohne dass sich das Muster sichtbar ändert.
class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.id, required this.color});

  final String id;
  final Color color;

  /// Kachelgröße (unverändert zur vorherigen Fassung).
  static const double _tile = 56.0;

  // ---- Normalisierte Formen: einmal gebaut, app-weit wiederverwendet ----

  /// Kachelradius, den die Musterformen bereits eingebacken bekommen.
  static const double _shapeRadius = 11.0;

  /// Herz, fertig skaliert und vertikal gespiegelt, Ursprung = Kachelmitte.
  /// 16 Stützstellen statt 64: bei 11 px Kachelradius ist die
  /// 16-Ecken-Näherung visuell identisch.
  ///
  /// Skalierung und Spiegelung sind bewusst EINMAL hier eingerechnet,
  /// damit pro Kachel nur noch [Path.addPath] mit einer Verschiebung
  /// nötig ist - keine Matrix und keine Trigonometrie im Repaint.
  static final Path _heartShape = _buildHeartShape();

  /// Vierstrahl-Sparkle, fertig skaliert, Ursprung = Kachelmitte.
  static final Path _starShape = _buildStarShape();

  static Path _buildHeartShape() {
    const steps = 16;
    final k = _shapeRadius / 16.0;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final x = 16 * math.pow(math.sin(t), 3);
      final y = 13 * math.cos(t) -
          5 * math.cos(2 * t) -
          2 * math.cos(3 * t) -
          math.cos(4 * t);
      if (i == 0) {
        path.moveTo(x * k, -y * k + _shapeRadius * 0.55);
      } else {
        path.lineTo(x * k, -y * k + _shapeRadius * 0.55);
      }
    }
    path.close();
    return path;
  }

  static Path _buildStarShape() {
    final s = _shapeRadius;
    return Path()
      ..moveTo(0, -s)
      ..lineTo(s * 0.28, -s * 0.28)
      ..lineTo(s, 0)
      ..lineTo(s * 0.28, s * 0.28)
      ..lineTo(0, s)
      ..lineTo(-s * 0.28, s * 0.28)
      ..lineTo(-s, 0)
      ..lineTo(-s * 0.28, -s * 0.28)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    switch (id) {
      case ChatBackgrounds.dots:
        // EIN Aufruf statt ~817: alle Punkte in einer Liste sammeln und
        // mit PointMode.points zeichnen.
        final pts = <Offset>[];
        for (var y = _tile / 2; y < size.height + _tile; y += _tile) {
          for (var x = _tile / 2; x < size.width + _tile; x += _tile) {
            pts.add(Offset(x, y));
          }
        }
        canvas.drawPoints(
            ui.PointMode.points, pts, fill..strokeWidth = 6);

      case ChatBackgrounds.lines:
        // Alle Diagonalen in EIN Pfad: 1 drawPath statt ~270 drawLine.
        final path = Path();
        for (var d = -size.height; d < size.width + size.height; d += 18) {
          path
            ..moveTo(d, 0)
            ..lineTo(d + size.height, size.height);
        }
        canvas.drawPath(path, stroke);

      case ChatBackgrounds.hearts:
      case ChatBackgrounds.stars:
        // Ein Pfad, der alle Kacheln enthaelt. [addPath] verschiebt die
        // bereits fertige, massgestabte Form - ohne die Kurve neu zu
        // berechnen. Abschluss: EIN drawPath fuer das ganze Muster.
        final shape =
            id == ChatBackgrounds.hearts ? _heartShape : _starShape;
        final path = Path();
        var row = 0;
        for (var y = _tile / 2; y < size.height + _tile; y += _tile) {
          final off = (row.isEven ? 0.0 : _tile / 2);
          for (var x = _tile / 2 + off; x < size.width + _tile; x += _tile) {
            path.addPath(shape, Offset(x, y));
          }
          row++;
        }
        canvas.drawPath(path, fill);

      case ChatBackgrounds.waves:
        // Alle Zeilen in EIN Pfad. Abtastung 8 -> 14 px: bei einer
        // Wellenlänge von ~60 px ist der Unterschied nicht sichtbar,
        // die Punktzahl sinkt um 43 %.
        final path = Path();
        for (var y = 0.0; y < size.height + _tile; y += 28) {
          var first = true;
          for (var x = -20.0; x <= size.width + 20; x += 14) {
            final yy = y + 8 * math.sin((x / size.width) * 2 * math.pi);
            if (first) {
              path.moveTo(x, yy);
              first = false;
            } else {
              path.lineTo(x, yy);
            }
          }
        }
        canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.id != id || old.color != color;
}
