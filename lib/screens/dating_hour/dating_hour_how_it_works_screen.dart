import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Screen, der erklärt, wie die Dating Hour funktioniert.
///
/// Wird direkt nach den Regeln angezeigt, bevor die eigentliche Event-Seite
/// geöffnet wird.
class DatingHourHowItWorksScreen extends ConsumerWidget {
  const DatingHourHowItWorksScreen({super.key});

  /// Die 5 Schritte (v0.8.0 zweisprachig über L10n-Keys).
  List<_HowItWorksItem> _steps(BuildContext context) => [
        _HowItWorksItem(
          L10n.t(context, 'dh.how.step1.title'),
          L10n.t(context, 'dh.how.step1.body'),
        ),
        _HowItWorksItem(
          L10n.t(context, 'dh.how.step2.title'),
          L10n.t(context, 'dh.how.step2.body'),
        ),
        _HowItWorksItem(
          L10n.t(context, 'dh.how.step3.title'),
          L10n.t(context, 'dh.how.step3.body'),
        ),
        _HowItWorksItem(
          L10n.t(context, 'dh.how.step4.title'),
          L10n.t(context, 'dh.how.step4.body'),
        ),
        _HowItWorksItem(
          L10n.t(context, 'dh.how.step5.title'),
          L10n.t(context, 'dh.how.step5.body'),
        ),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = _steps(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'dh.how.title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'dh.how.intro'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ...steps.map(
              (step) => _StepExpansion(step: step),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final settingsNotifier = ref.read(settingsProvider.notifier);
                await settingsNotifier.markDatingHourIntroSeen();
                // Intro-Stand serverseitig merken (Migration 071), damit
                // die Regeln/Erklärung pro Konto nur EINMAL erscheinen -
                // nicht bei jeder Neuinstallation erneut. Best effort.
                if (SupabaseService.isInitialized) {
                  unawaited(() async {
                    try {
                      await SupabaseDatabaseService(SupabaseService.client)
                          .updateOwnProfile({
                        'dating_hour_intro_seen': true,
                      });
                    } catch (e) {
                      debugPrint('[DatingHour] Intro-Flag-Sync fehlgeschlagen:'
                          ' $e');
                    }
                  }());
                }
                if (context.mounted) {
                  context.go(AppRoutes.datingHourEvent);
                }
              },
              child: Text(L10n.t(context, 'dh.how.next')),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepExpansion extends StatelessWidget {
  const _StepExpansion({required this.step});

  final _HowItWorksItem step;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        // Keine Trennlinien ober-/unterhalb der Bubble.
        shape: const Border(),
        title: Text(
          step.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(step.body),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksItem {
  const _HowItWorksItem(this.title, this.body);

  final String title;
  final String body;
}
