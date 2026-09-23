import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/models/find_match_models.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/services/find_your_match_service.dart';
import 'package:wisp/widgets/heart_moments.dart';

/// Gemeinsame Erinnerungsliste (Idee 5, Migration 116): Einträge anlegen,
/// abhaken, eigene löschen. Stillstand-Hinweis ab 14 Tagen + Chat-Stille.
class BucketListSheet extends ConsumerStatefulWidget {
  const BucketListSheet({
    required this.matchId,
    required this.partnerName,
    required this.myId,
    super.key,
  });

  final int matchId;
  final String partnerName;
  final String myId;

  @override
  ConsumerState<BucketListSheet> createState() => _BucketListSheetState();
}

class _BucketListSheetState extends ConsumerState<BucketListSheet> {
  List<BucketItem>? _items;
  final _addCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ref
        .read(findYourMatchServiceProvider)
        .bucketItems(widget.matchId);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _add() async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty || _adding) return;
    setState(() => _adding = true);
    await ref
        .read(findYourMatchServiceProvider)
        .bucketAdd(widget.matchId, text);
    _addCtrl.clear();
    setState(() => _adding = false);
    await _load();
  }

  Future<void> _toggle(BucketItem item) async {
    await ref.read(findYourMatchServiceProvider).bucketToggle(item.id);
    await _load();
  }

  Future<void> _delete(BucketItem item) async {
    await ref.read(findYourMatchServiceProvider).bucketDelete(item.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    final stale = BucketReminder.shouldRemind(
      items: items ?? const [],
      messages:
          ref.read(chatProvider.notifier).messagesFor('${widget.matchId}'),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.t(context, 'bucket.title'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                L10n.t(context, 'bucket.hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Stillstand-Hinweis (Idee 5): sanft, nur wenn Liste alt UND
              // Chat ruhig.
              if (stale)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wb_twilight_outlined,
                          size: 18, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          L10n.tf(context, 'bucket.staleNote', {
                            'days':
                                '${BucketReminder.idleDays(items ?? const [])}',
                          }),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              // Hinzufügen-Zeile.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addCtrl,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: L10n.t(context, 'bucket.addHint'),
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _adding ? null : _add,
                    child: Text(L10n.t(context, 'bucket.add')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: items == null
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? Center(
                            child: Text(
                              L10n.t(context, 'bucket.empty'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView(
                            children: [
                              for (final item in items)
                                ListTile(
                                  leading: Checkbox(
                                    value: item.done,
                                    onChanged: (_) => _toggle(item),
                                  ),
                                  title: Text(
                                    item.text,
                                    style: TextStyle(
                                      decoration: item.done
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      color: item.done
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                          : null,
                                    ),
                                  ),
                                  subtitle: Text(item.createdBy ==
                                          widget.myId
                                      ? L10n.t(context, 'bucket.mine')
                                      : L10n.tf(context, 'bucket.theirs',
                                          {'name': widget.partnerName})),
                                  trailing: item.createdBy == widget.myId
                                      ? IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                          tooltip: L10n.t(
                                              context, 'common.discard'),
                                          onPressed: () => _delete(item),
                                        )
                                      : null,
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
