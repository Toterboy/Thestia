import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/widgets/buttons.dart';

/// Persönlichkeitstest als Teil des Registrierungs-Flows (MBTI-Stil).
///
/// Optional und überspringbar. Das Ergebnis (Typ + Bezeichnung) wird im
/// Profil gespeichert und fließt in den Matching-Algorithmus ein.
class PersonalityTestScreen extends ConsumerStatefulWidget {
  const PersonalityTestScreen({super.key});

  @override
  ConsumerState<PersonalityTestScreen> createState() =>
      _PersonalityTestScreenState();
}

class _PersonalityTestScreenState
    extends ConsumerState<PersonalityTestScreen> {
  /// Fragen mit je zwei gegensätzlichen Polen (A/B). Die Auswahl steuert
  /// die Dimensionen E/I, S/N, T/F, J/P. Lokalisiert (pt.q1..q10).
  List<(String, String, String)> _questions(BuildContext context) => [
        for (var i = 1; i <= 10; i++)
          (
            L10n.t(context, 'pt.q$i'),
            L10n.t(context, 'pt.q${i}a'),
            L10n.t(context, 'pt.q${i}b'),
          ),
      ];

  /// Anzahl der Fragen (s. [_questions]).
  static const int questionCount = 10;

  /// 0 = erstes Item (A), 1 = zweites Item (B).
  final List<int?> _answers = List.filled(questionCount, null);

  bool get _allAnswered => _answers.every((a) => a != null);

  /// Ermittelt den MBTI-Typ aus den Antworten (A-Pole = erste Dimension,
  /// B-Pole = zweite Dimension).
  String _type() {
    final ei = _answers[0] == 0 || _answers[3] == 0 || _answers[7] == 0 ? 'E' : 'I';
    final sn = _answers[2] == 1 || _answers[4] == 0 ? 'S' : 'N';
    final tf = _answers[2] == 0 || _answers[6] == 0 ? 'T' : 'F';
    final jp = _answers[1] == 1 || _answers[5] == 1 || _answers[9] == 1 ? 'J' : 'P';
    return ei + sn + tf + jp;
  }

  /// Anzeigelabel zum Typ (pt.label.*, Fallback bei unbekanntem Typ).
  /// Wird auch gespeichert (Profil) und dort angezeigt.
  String _resultLabel(BuildContext context, String type) {
    final label = L10n.t(context, 'pt.label.$type');
    if (label == 'pt.label.$type') {
      return L10n.t(context, 'pt.label.fallback');
    }
    return label;
  }

  Future<void> _finish() async {
    final type = _type();
    final result = _resultLabel(context, type);
    await ref.read(profileProvider.notifier).update(
          personalityType: type,
          personalityResult: result,
        );
    await ref.read(settingsProvider.notifier).completePersonalityTest();
    // Setup-Stand zusätzlich serverseitig sichern (Einrichtung erscheint
    // nach Neuinstallation/neuem Login nicht erneut). onboarding_done ist
    // das "Niemals-Einrichtung"-Flag (Migration 065) - ab jetzt erzwingt
    // der Router die Einrichtung/Test nie wieder. AWARTEN statt
    // fire-and-forget: Schlägt das still fehl, erscheint der Test nach der
    // nächsten Neuinstallation erneut - deshalb bei Misserfolg derselbe
    // sichtbare Hinweis wie im Einstellungs-Screen.
    final flagsSaved = await _persistSetupFlagsToServer();
    if (mounted && !flagsSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'pt.saveFailed')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (mounted) {
      // Ergebnis anzeigen
      await showDialog<void>(        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(context, 'pt.doneTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.tf(context, 'pt.youAre', {'t': type}),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                result,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _typeDescription(context, type),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                context.go(AppRoutes.home);
              },
              child: Text(L10n.t(context, 'common.continue')),
            ),
          ],
        ),
      );
    }
  }

  /// Schreibt den Test-Flag verifiziert in die profiles-Tabelle
  /// (siehe [SupabaseDatabaseService.updateSetupFlagsAndVerify]).
  Future<bool> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return true;
    try {
      return await SupabaseDatabaseService(SupabaseService.client)
          .updateSetupFlagsAndVerify({
        'personality_test_completed': true,
        'onboarding_done': true,
      });
    } catch (e) {
      debugPrint('[PersonalityTest] Server-Flag fehlgeschlagen: $e');
      return false;
    }
  }

  /// Beschreibung zum Typ (pt.desc.*, Fallback bei unbekanntem Typ).
  String _typeDescription(BuildContext context, String type) {
    final desc = L10n.t(context, 'pt.desc.$type');
    if (desc == 'pt.desc.$type') {
      return L10n.t(context, 'pt.desc.fallback');
    }
    return desc;
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'pt.title')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'pt.heading'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.t(context, 'pt.sub'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _allAnswered
                        ? 1
                        : _answers.whereType<int>().length /
                            questions.length,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: questions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 20),
                  itemBuilder: (context, i) {
                    final q = questions[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${q.$1}',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        RadioGroup<int>(
                          groupValue: _answers[i],
                          onChanged: (v) {
                            if (v != null) setState(() => _answers[i] = v);
                          },
                          child: Column(
                            children: [0, 1].map((j) {
                              final text = j == 0 ? q.$2 : q.$3;
                              return RadioListTile<int>(
                                title: Text(text),
                                value: j,
                                activeColor: Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  PrimaryButton(
                    label: L10n.t(context, 'pt.finish'),
                    onPressed: _allAnswered ? _finish : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      await ref
                          .read(settingsProvider.notifier)
                          .completePersonalityTest();
                      if (mounted) router.go(AppRoutes.home);
                    },
                    child: Text(L10n.t(context, 'common.skip')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

