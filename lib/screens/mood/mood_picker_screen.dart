import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_mood.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/theme/app_theme.dart';
import 'package:thestia/widgets/buttons.dart';

/// Screen zur Auswahl des Mood of the Day.
///
/// Der Nutzer kann einmal pro Tag eine Stimmung wählen. Bereits
/// gespeicherte Moods werden vorausgewählt und können überschrieben
/// werden.
class MoodPickerScreen extends ConsumerStatefulWidget {
  const MoodPickerScreen({super.key});

  @override
  ConsumerState<MoodPickerScreen> createState() => _MoodPickerScreenState();
}

class _MoodPickerScreenState extends ConsumerState<MoodPickerScreen> {
  Mood? _selected;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(moodProvider);
  }

  Future<void> _save() async {
    final mood = _selected;
    if (mood == null) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(moodProvider.notifier).setMood(mood);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'mood.saved'))),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.tf(
                  context, 'common.errorWith', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMood = ref.watch(moodProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'mood.title')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L10n.t(context, 'mood.question'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                L10n.t(context, 'mood.explainer'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (currentMood != null) ...[
                _CurrentMoodCard(mood: currentMood),
                const SizedBox(height: 24),
              ],
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.1,
                  children: [
                    for (final mood in Mood.values)
                      _MoodChoiceTile(
                        mood: mood,
                        isSelected: _selected == mood,
                        onTap: () => setState(() => _selected = mood),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _isSaving
                    ? L10n.t(context, 'mood.saving')
                    : L10n.t(context, 'mood.save'),
                onPressed: _selected == null || _isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kachel zur Auswahl eines Moods.
class _MoodChoiceTile extends StatelessWidget {
  const _MoodChoiceTile({
    required this.mood,
    required this.isSelected,
    required this.onTap,
  });

  final Mood mood;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = mood.color;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : theme.colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mood.icon,
              size: 40,
              color: color,
            ),
            const SizedBox(height: 12),
            Text(
              L10n.t(context, mood.labelKey),
              style: theme.textTheme.titleMedium?.copyWith(
                color: isSelected ? color : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anzeige des aktuell gespeicherten Moods.
class _CurrentMoodCard extends StatelessWidget {
  const _CurrentMoodCard({required this.mood});

  final Mood mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: mood.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(mood.icon, color: mood.color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'mood.current'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    L10n.t(context, mood.labelKey),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: AppColors.like),
          ],
        ),
      ),
    );
  }
}
