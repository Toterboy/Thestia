// Der Teil '_AsyncList'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.loading,
    required this.error,
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyText,
    required this.itemBuilder,
    required this.onRetry,
    this.header,
  });

  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> items;

  /// Symbol des Leerzustands. Bewusst Teil des Gerästs: die drei Tabs, die
  /// sich vorher je ein eigenes `Center(child: Text(...))` gebaut hatten,
  /// zeigten dasselbe Nichts ohne Hinweis, was dort normalerweise steht.
  final IconData emptyIcon;

  final String emptyTitle;
  final String emptyText;

  /// Optionale Leiste über der Liste (z. B. das Suchfeld im Sperren-Tab).
  /// Gehört in den Scroll-Bereich, damit Pull-to-refresh sie mitzieht.
  final Widget? header;

  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return ErrorState(
        message: L10n.tf(context, 'admin.error', {'error': '$error'}),
        onRetry: () => onRetry(),
      );
    }
    if (items.isEmpty) {
      return EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyText);
    }
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length + (header == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        // Card-Look konsistent zur restlichen Nutzeroberfläche. Radius 12
        // ist hier Absicht und nicht der 24er der Kacheln: eine Liste von
        // dicht gestapelten Eintrügen braucht eine engere Rundung, sonst
        // wirken die Zeilen wie Kacheln.
        itemBuilder: (context, i) {
          if (header != null && i == 0) return header!;
          final index = i - (header == null ? 0 : 1);
          return Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: itemBuilder(context, items[index]),
            ),
          );
        },
      ),
    );
  }
}
