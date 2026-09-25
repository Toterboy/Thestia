import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/notification_service.dart';

/// Screen mit den wichtigsten Regeln für die Dating Hour.
///
/// Wird beim ersten Betreten der Dating Hour angezeigt, damit Nutzer
/// die Erwartungen und Verbotsregeln direkt sehen.
class DatingHourRulesScreen extends ConsumerWidget {
  const DatingHourRulesScreen({super.key});

  /// Die 6 Kernregeln (v0.8.0 zweisprachig über L10n-Keys).
  List<_RuleItem> _rules(BuildContext context) => [
        _RuleItem(
          L10n.t(context, 'dh.rules.1.title'),
          L10n.t(context, 'dh.rules.1.body'),
        ),
        _RuleItem(
          L10n.t(context, 'dh.rules.2.title'),
          L10n.t(context, 'dh.rules.2.body'),
        ),
        _RuleItem(
          L10n.t(context, 'dh.rules.3.title'),
          L10n.t(context, 'dh.rules.3.body'),
        ),
        _RuleItem(
          L10n.t(context, 'dh.rules.4.title'),
          L10n.t(context, 'dh.rules.4.body'),
        ),
        _RuleItem(
          L10n.t(context, 'dh.rules.5.title'),
          L10n.t(context, 'dh.rules.5.body'),
        ),
        _RuleItem(
          L10n.t(context, 'dh.rules.6.title'),
          L10n.t(context, 'dh.rules.6.body'),
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = _rules(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'dh.rules.title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.rules.introLong'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ...rules.map(
              (rule) => _RuleExpansion(rule: rule),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                NotificationService.instance.show(
                  id: 999,
                  title: L10n.t(context, 'dh.rules.acceptedTitle'),
                  body: L10n.t(context, 'dh.rules.bodyFun'),
                  ref: ref,
                  type: NotificationType.datingHour,
                );
                context.go(AppRoutes.datingHourHowItWorks);
              },
              child: Text(L10n.t(context, 'dh.rules.next')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleExpansion extends StatelessWidget {
  const _RuleExpansion({required this.rule});

  final _RuleItem rule;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        // Keine Trennlinien ober-/unterhalb der Bubble (Default-Zeichnung
        // des ExpansionTile zieht im aufgeklappten Zustand Divider-Linien).
        shape: const Border(),
        title: Text(
          rule.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(rule.body),
          ),
        ],
      ),
    );
  }
}

class _RuleItem {
  const _RuleItem(this.title, this.body);

  final String title;
  final String body;
}
