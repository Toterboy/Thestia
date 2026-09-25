import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/data/icebreaker_catalog.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';

/// "Spice Questions": Eisbrecher-Fragen als reine Auswahl (v0.9.1).
///
/// Kein Beantworten, kein Server: 10 Kategorien mit je 6 Fragen
/// (DE + EN), durchsuchbar. Ein Tap kopiert die Frage in die
/// Zwischenablage, damit sie im Chat eingefügt werden kann.
class SpiceQuestionsScreen extends ConsumerStatefulWidget {
  const SpiceQuestionsScreen({required this.matchId, super.key});

  final int matchId;

  @override
  ConsumerState<SpiceQuestionsScreen> createState() =>
      _SpiceQuestionsScreenState();
}

class _SpiceQuestionsScreenState extends ConsumerState<SpiceQuestionsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      // Ohne Back-Stack (per go() geöffnet): zurück in den Chat.
      context.go(AppRoutes.chatDetailPath(widget.matchId.toString()));
    }
  }

  Future<void> _copyQuestion(IcebreakerQuestion question) async {
    final lang = L10n.localeOf(context).languageCode;
    final text = question.textFor(lang);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'spice.copied')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Tap auf eine Frage: als GEMEINSAME Bubble in den Chat senden (beide
  /// Seiten sehen sie mittig) oder nur kopieren.
  Future<void> _onQuestionTap(IcebreakerQuestion question) async {
    final lang = L10n.localeOf(context).languageCode;
    final text = question.textFor(lang);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'spice.sendTitle')),
        content: Text(
          text,
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(ctx).pop('copy'),
            icon: const Icon(Icons.copy_outlined),
            label: Text(L10n.t(ctx, 'spice.copyTooltip')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop('send'),
            icon: const Icon(Icons.send_outlined),
            label: Text(L10n.t(ctx, 'spice.sendBtn')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'copy') {
      await _copyQuestion(question);
    } else if (choice == 'send') {
      // Zurück in den Chat MIT der Frage als Pop-Resultat (v0.9.1): Der
      // Chat sendet sie direkt als gemeinsame Bubble an beide Seiten.
      // Ohne Stack (Deep-Link) notfalls per go() in den Chat.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(text);
      } else if (mounted) {
        context.go(AppRoutes.chatDetailPath(widget.matchId.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = L10n.localeOf(context).languageCode;
    final q = _query.trim().toLowerCase();

    final visible = q.isEmpty
        ? icebreakerCatalog
        : icebreakerCatalog
            .map((cat) {
              final matches = cat.questions
                  .where((item) =>
                      item.de.toLowerCase().contains(q) ||
                      item.en.toLowerCase().contains(q))
                  .toList();
              if (matches.isEmpty) return null;
              return (cat: cat, questions: matches);
            })
            .whereType<({IcebreakerCategory cat, List<IcebreakerQuestion> questions})>()
            .toList();

    final total = icebreakerCatalog.fold<int>(
      0,
      (sum, cat) => sum + cat.questions.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'spice.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: L10n.t(context, 'common.back'),
          onPressed: _goBack,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: L10n.t(context, 'spice.searchHint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                L10n.tf(context, 'spice.countHint', {'n': '$total'}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          Expanded(
            child: q.isNotEmpty && visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        L10n.t(context, 'spice.emptySearch'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: q.isEmpty
                        ? icebreakerCatalog.length
                        : visible.length,
                    itemBuilder: (context, index) {
                      if (q.isEmpty) {
                        final cat = icebreakerCatalog[index];
                        return _CategoryCard(
                          title: cat.titleFor(lang),
                          icon: cat.icon,
                          questions: cat.questions,
                          lang: lang,
                          onCopy: _copyQuestion,
                          onTap: _onQuestionTap,
                        );
                      }
                      final entry = visible[index]
                          as ({IcebreakerCategory cat, List<IcebreakerQuestion> questions});
                      return _CategoryCard(
                        title: entry.cat.titleFor(lang),
                        icon: entry.cat.icon,
                        questions: entry.questions,
                        lang: lang,
                        onCopy: _copyQuestion,
                        onTap: _onQuestionTap,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.icon,
    required this.questions,
    required this.lang,
    required this.onCopy,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final List<IcebreakerQuestion> questions;
  final String lang;
  final Future<void> Function(IcebreakerQuestion) onCopy;
  final Future<void> Function(IcebreakerQuestion) onTap;

  @override
  Widget build(BuildContext context) {
    // shape/collapsedShape ohne BorderSide (v0.9.1): sonst zeichnet das
    // Material-3-ExpansionTile einen Strich über/unter der geöffneten
    // Kategorie.
    final tileShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: tileShape,
      child: ExpansionTile(
        shape: tileShape,
        collapsedShape: tileShape,
        leading: Icon(icon,
            color: Theme.of(context).colorScheme.primary),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          L10n.tf(context, 'spice.perCategory',
              {'n': '${questions.length}'}),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          for (final question in questions)
            ListTile(
              title: Text(question.textFor(lang)),
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: L10n.t(context, 'spice.copyTooltip'),
                onPressed: () => onCopy(question),
              ),
              onTap: () => onTap(question),
            ),
        ],
      ),
    );
  }
}
