import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/providers/meet_intent_provider.dart';
import 'package:wisp/l10n/app_strings.dart';

/// Vorschlag-Karte für ein echtes Treffen im Chat.
///
/// Zustände:
/// - Match zu frisch (< 14 Tage): nichts.
/// - Beide wollen & nicht getroffen: Planungskarte.
/// - Ich will, Partner noch nicht: Warte-Hinweis.
/// - Partner will, ich noch nicht: Zustimmungs-Abfrage.
/// - Noch keiner: sanfter Vorschlag.
/// - Getroffen bestätigt: Erfolgsmeldung.
class MeetIntentCard extends ConsumerStatefulWidget {
  const MeetIntentCard({
    super.key,
    required this.matchId,
    required this.partnerName,
  });

  final String matchId;
  final String partnerName;

  @override
  ConsumerState<MeetIntentCard> createState() => _MeetIntentCardState();
}

class _MeetIntentCardState extends ConsumerState<MeetIntentCard> {
  // "Später" blendet die Karte nur für die aktuelle Sitzung aus.
  bool _dismissed = false;

  // Optionale Planungs-Notiz.
  final _noteCtrl = TextEditingController();

  /// Date-Ideen lokalisiert (meet.idea.1..5).
  List<String> _dateIdeas(BuildContext context) => [
        L10n.t(context, 'meet.idea.1'),
        L10n.t(context, 'meet.idea.2'),
        L10n.t(context, 'meet.idea.3'),
        L10n.t(context, 'meet.idea.4'),
        L10n.t(context, 'meet.idea.5'),
      ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lokale Kontakte (QR) haben keine DB-Match-ID -> keine Treffen-Logik.
    if (int.tryParse(widget.matchId) == null) {
      return const SizedBox.shrink();
    }

    final intent = ref.watch(meetIntentProvider(widget.matchId));
    if (intent == null) return const SizedBox.shrink();

    if (intent.metConfirmed) {
      return _card(
        icon: Icons.celebration,
        color: Colors.green,
        title: L10n.t(context, 'meet.metTitle'),
        body: L10n.t(context, 'meet.metBody'),
      );
    }

    if (!intent.eligible) return const SizedBox.shrink();
    if (_dismissed) return const SizedBox.shrink();

    final notifier = ref.read(meetIntentProvider(widget.matchId).notifier);

    if (intent.bothWant) {
      return _planningCard(notifier);
    }

    if (intent.myWants && !intent.partnerWants) {
      return _card(
        icon: Icons.schedule,
        color: Theme.of(context).colorScheme.primary,
        title: L10n.t(context, 'meet.youWant'),
        body: L10n.tf(context, 'meet.waitBody',
            {'name': widget.partnerName}),
      );
    }

    if (!intent.myWants && intent.partnerWants) {
      return _card(
        icon: Icons.favorite,
        color: Theme.of(context).colorScheme.primary,
        title: L10n.tf(context, 'meet.theyWant', {'name': widget.partnerName}),
        body: L10n.t(context, 'meet.tryBody'),
        actions: [
          FilledButton(
            onPressed: () => notifier.setWants(true),
            child: Text(L10n.t(context, 'meet.yesGlad')),
          ),
          TextButton(
            onPressed: () => notifier.setWants(false),
            child: Text(L10n.t(context, 'meet.noThanks')),
          ),
        ],
      );
    }

    // Noch keiner will.
    return _card(
      icon: Icons.coffee,
      color: Theme.of(context).colorScheme.primary,
      title: L10n.t(context, 'meet.suggestTitle'),
      body: L10n.t(context, 'meet.suggestBody'),
      actions: [
        FilledButton(
          onPressed: () => notifier.setWants(true),
          child: Text(L10n.t(context, 'meet.yesWant')),
        ),
        TextButton(
          onPressed: () => setState(() => _dismissed = true),
          child: Text(L10n.t(context, 'meet.later')),
        ),
      ],
    );
  }

  Widget _planningCard(MeetIntentNotifier notifier) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake),
                const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L10n.t(context, 'meet.planningTitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ],
            ),
            const SizedBox(height: 8),
            Text(L10n.t(context, 'meet.ideas')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dateIdeas(context)
                  .map((idea) => Chip(label: Text(idea)))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: L10n.t(context, 'meet.noteHint'),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(L10n.t(context, 'meet.metBtn')),
                    onPressed: () => notifier.confirmMet(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, 'meet.safetyTip'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    List<Widget> actions = const [],
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: actions
                    .map((a) => [a, const SizedBox(width: 8)])
                    .expand((e) => e)
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
