import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/habitude_level.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/habitude_selector.dart';

/// Editierbare Karte für die Konsum-Präferenzen (Rauchen, Alkohol, Drogen).
///
/// Schreibt die Auswahl lokal in den [profileProvider] und spiegelt sie
/// best effort in die profiles-Tabelle, damit der Find-your-Match-Algorithmus
/// darüber filtern kann. Wird in den Einstellungen und im Profil genutzt.
class HabitudeEditCard extends ConsumerWidget {
  const HabitudeEditCard({super.key, this.onChanged});

  /// Optionaler Callback nach jeder Änderung (z. B. um UI neu zu laden).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    void persist() {
      if (!SupabaseService.isInitialized) return;
      final p = ref.read(profileProvider);
      unawaited(() async {
        try {
          await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
            'smoking': p.smoking?.toServer(),
            'alcohol': p.alcohol?.toServer(),
            'drugs': p.drugs?.toServer(),
          });
        } catch (e) {
          debugPrint('[HabitudeEditCard] Server-Sync fehlgeschlagen: $e');
        }
      }());
      onChanged?.call();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.t(context, 'profile.edit.habits'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, 'profile.edit.habitsSub'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.smoking,
              value: profile.smoking,
              onChanged: (v) {
                ref.read(profileProvider.notifier).update(smoking: v);
                persist();
              },
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.alcohol,
              value: profile.alcohol,
              onChanged: (v) {
                ref.read(profileProvider.notifier).update(alcohol: v);
                persist();
              },
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.drugs,
              value: profile.drugs,
              onChanged: (v) {
                ref.read(profileProvider.notifier).update(drugs: v);
                persist();
              },
            ),
          ],
        ),
      ),
    );
  }
}
