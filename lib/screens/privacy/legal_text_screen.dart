import 'package:flutter/material.dart';

import 'package:thestia/generated/privacy_policy_blocks.dart';

/// Zeigt einen Rechtstext in der App an: die Datenschutzerklärung oder
/// die Nutzungsbedingungen.
///
/// WARUM ES DIESEN BILDSCHIRM GIBT (14.11.2026, Betreiber): "Die
/// Nutzungsbedingungen funktionieren in der App nicht." Vorher verlinkte
/// die App auf die Webseite - das setzt einen installierten Browser und
/// eine erreichbare Seite voraus, und in der App selbst stand nichts.
/// Die Datenschutzerklärung macht es seit dem 03.11.2026 besser: ihr
/// Volltext steht als Datei im Binary und wird hier angezeigt. Eine URL
/// kann falsch, verschoben oder nicht erreichbar sein; der Text nicht.
///
/// Beide Texte benutzen denselben Bildschirm - sie unterscheiden sich
/// nur in den Blöcken und in der Überschrift.
class LegalTextScreen extends StatefulWidget {
  const LegalTextScreen({
    required this.blocks,
    required this.title,
    this.footer,
    super.key,
  });

  /// Die Abschnitte des Textes.
  final List<PrivacyBlock> blocks;

  /// Die Überschrift der Seite (steht auch im App-Balken).
  final String title;

  /// Optionaler Bereich unter dem Text (z. B. der Link auf die
  /// Webfassung).
  final Widget? footer;

  @override
  State<LegalTextScreen> createState() => _LegalTextScreenState();
}

class _LegalTextScreenState extends State<LegalTextScreen> {
  /// Spaltenüberschriften je Tabellenzeile.
  ///
  /// ListView.builder baut nur die sichtbaren Elemente, deshalb kann der
  /// Bildschirm die Überschrift beim Bauen der Zeile nicht einfach
  /// "merken". Die Zuordnung wird deshalb einmal vorab berechnet: Index
  /// der Zeile -> Kopfzeilen dieser Tabelle.
  ///
  /// Die Mappe wird zwischengespeichert: sie wird bei jedem Bau neu
  /// gebraucht, aber die Blöcke wechseln nicht ständig.
  Map<int, List<String>>? _headerCache;

  Map<int, List<String>> _headers() {
    return _headerCache ??= _computeHeaders(widget.blocks);
  }

  static Map<int, List<String>> _computeHeaders(List<PrivacyBlock> blocks) {
    final map = <int, List<String>>{};
    List<String>? current;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.kind == 'table_head') {
        current = block.cells;
      } else if (block.kind == 'table') {
        map[i] = current ?? block.cells ?? const <String>[];
      } else {
        current = null;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloecke = widget.blocks;
    final headers = _headers();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      // SelectionArea: einzelne Absätze kopierbar, etwa für den
      // Bug-Report. Ohne Auswahl gibt es auf Android nichts zu markieren.
      body: SelectionArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: bloecke.length,
                itemBuilder: (context, index) => _block(
                  context,
                  bloecke[index],
                  // Map-Zugriff gibt zurück, ob der Schlüssel existiert.
                  // Bei einer Tabelle ohne Kopfzeile ist die Liste leer,
                  // nicht null - deshalb das explizite Ersetzen.
                  headers[index] ?? const <String>[],
                  theme,
                ),
              ),
            ),
            if (widget.footer != null) widget.footer!,
          ],
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context,
    PrivacyBlock block,
    List<String> headers,
    ThemeData theme,
  ) {
    switch (block.kind) {
      case 'h1':
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            _plain(block.text),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 8),
          child: Text(
            _plain(block.text),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        );

      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(
            _plain(block.text),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case 'li':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: theme.textTheme.bodyMedium),
              Expanded(child: _rich(context, block.text, theme)),
            ],
          ),
        );

      case 'table_head':
        // Wird nicht gerendert: die Spaltennamen stehen in den
        // Datenzeilen darunter. Eine eigene Kopfzeile wäre auf dem
        // Telefon nur ein zweiter, unnötiger Block.
        return const SizedBox.shrink();

      case 'table':
        return _dataRow(
          context,
          block.cells ?? const <String>[],
          headers,
          theme,
        );

      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _rich(context, block.text, theme),
        );
    }
  }

  /// Eine Tabellenzeile als Karte: die erste Spalte ist der Titel, die
  /// übrigen werden mit ihrer echten Überschrift beschriftet.
  ///
  /// Ein echtes Grid ist hier falsch: die Tabelle in Abschnitt 2 hat
  /// vier Spalten mit langen Texten. Auf einem Telefon wären die Spalten
  /// unlesbar schmal; als Karte bleibt alles lesbar und es geht keine
  /// Information verloren.
  Widget _dataRow(
    BuildContext context,
    List<String> cells,
    List<String> headers,
    ThemeData theme,
  ) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final scheme = theme.colorScheme;

    final labelled = <(String, String)>[];
    for (var i = 1; i < cells.length; i++) {
      final label = (i < headers.length && headers[i].isNotEmpty)
          ? headers[i]
          : null;
      labelled.add((label ?? '', cells[i]));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _plain(cells.first),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in labelled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _rich(
                context,
                entry.$1.isEmpty ? entry.$2 : '**${entry.$1}:** ${entry.$2}',
                theme,
              ),
            ),
        ],
      ),
    );
  }

  /// Setzt **fett** um, ohne eine Markdown-Bibliothek einzuführen.
  Widget _rich(BuildContext context, String raw, ThemeData theme) {
    final base = theme.textTheme.bodyMedium;
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var rest = raw;

    while (true) {
      final match = pattern.firstMatch(rest);
      if (match == null) {
        if (rest.isNotEmpty) spans.add(TextSpan(text: rest));
        break;
      }
      if (match.start > 0) {
        spans.add(TextSpan(text: rest.substring(0, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      rest = rest.substring(match.end);
    }

    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Überschriften enthalten im Markdown keine Auszeichnung.
  String _plain(String raw) => raw.replaceAll('**', '').trim();
}
