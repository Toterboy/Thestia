// Der Teil '_CallScreenEisbrecher'.
//
// DER WEG: Der Anruf-Screen war zu lang (> 1000 Zeilen). Das
// Eisbrecher-Blatt (die Fragen, die man im Anruf stellen kann) kommt
// jetzt in diese Datei - der Aufrufer bleibt unverändert.
//
// Der Test `code_datei_groessen_test.dart` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../call_screen.dart';

extension _CallScreenEisbrecher on _CallScreenState {
  Future<void> _showIcebreakerSheet() async {
    final lang = Localizations.localeOf(context).languageCode;
    String? selectedCategory;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cats = icebreakerCatalog;
          final active = selectedCategory == null
              ? cats
              : cats.where((c) => c.id == selectedCategory).toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.t(ctx, 'call.icebreakerTitle'),
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.t(ctx, 'call.icebreakerHint'),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: Text(L10n.t(ctx, 'genderpref.all')),
                            selected: selectedCategory == null,
                            onSelected: (_) =>
                                setSheetState(() => selectedCategory = null),
                          ),
                          const SizedBox(width: 6),
                          for (final c in cats) ...[
                            ChoiceChip(
                              avatar: Icon(c.icon, size: 16),
                              label: Text(c.titleFor(lang)),
                              selected: selectedCategory == c.id,
                              onSelected: (_) =>
                                  setSheetState(() => selectedCategory = c.id),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final c in active) ...[
                            if (selectedCategory == null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 4,
                                ),
                                child: Text(
                                  c.titleFor(lang),
                                  style: Theme.of(ctx).textTheme.labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ),
                            for (final q in c.questions)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    q.textFor(lang),
                                    style: Theme.of(ctx).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
