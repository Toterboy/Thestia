// Der Teil '_MoodCard'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../profile_screen.dart';

class _MoodCard extends ConsumerWidget {
  const _MoodCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(moodProvider);
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
                mood?.color.withValues(alpha: 0.15) ??
                theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            mood?.icon ?? Icons.emoji_emotions_outlined,
            color: mood?.color ?? theme.colorScheme.primary,
          ),
        ),
        title: Text(
          mood != null
              ? '${L10n.t(context, 'mood.today')} ${L10n.t(context, mood.labelKey)}'
              : L10n.t(context, 'mood.noneSelected'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          mood != null
              ? L10n.t(context, 'mood.changeHint')
              : L10n.t(context, 'mood.selectHint'),
          style: theme.textTheme.bodySmall,
        ),
        trailing: TextButton(
          onPressed: () => context.push(AppRoutes.moodPicker),
          child: Text(
            mood != null
                ? L10n.t(context, 'mood.change')
                : L10n.t(context, 'mood.select'),
          ),
        ),
      ),
    );
  }
}
