import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/gender.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Mehrfachauswahl der Geschlechts-Präferenz ("Ich suche").
///
/// Verhalten:
/// - Jedes Geschlecht ist ein eigener auswählbarer Chip (Mehrfachauswahl).
/// - Standard: NICHTS ausgewählt (leer = kein Geschlechter-Filter).
/// - "Alle" ist eine Kurzform: Ist sie aktiv (alle Chips ausgewählt),
///   deselektiert ein erneuter Tipp auf "Alle" die komplette Auswahl.
/// - Eine leere Auswahl ist erlaubt.
///
/// Die Auswahl wird lokal (UserPreferences) UND – sofern Supabase aktiv
/// ist – in der Datenbank (profiles.gender_preferences, TEXT[]) gespeichert.
class GenderPreferenceSelector extends ConsumerWidget {
  const GenderPreferenceSelector({super.key});

  /// Persistiert die Auswahl best-effort in Supabase (profiles).
  void _persistToDatabase(List<String> values) {
    if (!SupabaseService.isInitialized) return;
    unawaited(() async {
      try {
        await SupabaseDatabaseService(SupabaseService.client)
            .updateOwnProfile({'gender_preferences': values});
      } catch (e) {
        debugPrint('[GenderPreferenceSelector] DB-Persistenz fehlgeschlagen: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(userPreferencesProvider).genderPreferences;
    final notifier = ref.read(userPreferencesProvider.notifier);

    final allSelected =
        selected.length >= kAllGenderValues.length &&
        kAllGenderValues.every(selected.contains);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text(L10n.t(context, 'genderpref.all')),
          selected: allSelected,
          // "Alle" ist abwählbar: erneuter Tipp auf eine aktive
          // "Alle"-Auswahl hebt die komplette Auswahl auf.
          onSelected: (_) {
            if (allSelected) {
              notifier.clearGenders();
              _persistToDatabase(const []);
            } else {
              final all = List.of(kAllGenderValues);
              notifier.selectAllGenders();
              _persistToDatabase(all);
            }
          },
        ),
        for (final gender in Gender.values)
          FilterChip(
            label: Text(L10n.t(context, gender.labelKey)),
            selected: selected.contains(gender.value),
            onSelected: (_) {
              final current = List<String>.from(selected);
              if (current.contains(gender.value)) {
                current.remove(gender.value);
              } else {
                current.add(gender.value);
              }
              notifier.setGenderPreferences(current);
              _persistToDatabase(current);
            },
          ),
      ],
    );
  }
}
