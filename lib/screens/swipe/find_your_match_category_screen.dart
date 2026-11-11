import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/find_your_match_browse_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/widgets/age_range_sliders.dart';

/// "Find your Spark" - STOEBERN NACH INTERESSENS-KATEGORIE.
///
/// BEFUND (09.11.2026, Betreiber): "dann entweder Zufallsvorstellung
/// oder Vorstellungen anderer nach Kategorien ansehen. Also Kategorien
/// sind die Interessens-Kategorien. Auf diesen neuen Teil mit den
/// Kategorien soll ein Bereich mit 18+ sein, wo von 18 bis 99+ alle
/// gesehen werden (Aber man kann nach Alter filtern mit Regler) und ein
/// 16-17 Bereich ohne Vorstellung mit Alter darueber. Wichtig ist,
/// dass diese Grenze wirklich klappt, wie auch ueberall anders auch,
/// damit die Kinder/Jugend geschuetzt sind. Natuerlich da dann E2E
/// immer. Verschluesselt auf Server speichern."
///
/// WAS HIER SICHTBAR IST UND WAS NICHT:
/// * Der **Text** der Vorstellung (der liegt in `profiles.intro_text`).
/// * Die **Interessen** der Person.
/// * NICHT die Aufnahme: das Audio ist optional und wird - wie bisher -
///   erst beim Funke freigegeben (match-media, serverseitig geprueft).
///   E2E bleibt also: verschluesselt auf dem Server, entschluesselt
///   erst auf dem Geraet.
///
/// DIE ALTERSSGRENZE: Die Grenzen kommen aus `AgeSafetyRules` (16/17
/// fuer Minderjaehrige, 18-99 fuer Erwachsene) - und der SERVER
/// begrenzt sie zusaetzlich. Ein 16-Jaehriger kann also weder durch
/// den Regler noch durch einen manipulierten Client einen Erwachsenen
/// sehen: die Kandidaten kommen aus `public_profiles`, und die Sicht
/// filtert ueber `profile_discovery_visible_full`
/// (Migration 203/204).
class FindYourMatchCategoryScreen extends ConsumerStatefulWidget {
  const FindYourMatchCategoryScreen({super.key});

  @override
  ConsumerState<FindYourMatchCategoryScreen> createState() =>
      _FindYourMatchCategoryScreenState();
}

class _FindYourMatchCategoryScreenState
    extends ConsumerState<FindYourMatchCategoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(findYourMatchBrowseProvider.notifier).loadKategorien(),
    );
  }

  Future<void> _like(UserProfile profil) async {
    final ergebnis = await ref
        .read(findYourMatchBrowseProvider.notifier)
        .like(profil);
    if (!mounted) return;
    final text = !ergebnis.ok
        ? L10n.t(context, 'match.likeFailed')
        : ergebnis.isMatch
        ? L10n.tf(context, 'match.likeMutual', {'name': profil.name})
        : ergebnis.alreadyMatched
        ? L10n.tf(context, 'match.likeAlreadyMatched', {'name': profil.name})
        : L10n.tf(context, 'match.liked', {'name': profil.name});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(findYourMatchBrowseProvider);
    final notifier = ref.read(findYourMatchBrowseProvider.notifier);
    final blickAlter = ref.watch(profileProvider).age ?? 18;
    final grenzeMin = AgeSafetyRules.minFilterAge(blickAlter);
    final grenzeMax = AgeSafetyRules.maxFilterAge(blickAlter);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'fymb.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: L10n.t(context, 'fymb.reload'),
            onPressed: state.laedt ? null : notifier.neuLaden,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Die Altersspanne des Browsers -------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AgeRangeSliders(
                  minValue: state.alterMin.clamp(grenzeMin, grenzeMax),
                  maxValue: state.alterMax.clamp(grenzeMin, grenzeMax),
                  boundsMin: grenzeMin,
                  boundsMax: grenzeMax,
                  onChanged: (min, max) => notifier.setzeAltersspanne(min, max),
                  minLabelPrefix: L10n.t(context, 'profile.edit.minAgeLabel'),
                  maxLabelPrefix: L10n.t(context, 'profile.edit.maxAgeLabel'),
                  labelSuffix: L10n.t(context, 'common.years'),
                ),
              ),
            ),
          ),
          // --- Die Kategorien ---------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              L10n.t(context, 'fymb.categories'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(
            height: 52,
            child: state.kategorien.isEmpty
                ? Center(
                    child: Text(
                      L10n.t(context, 'fymb.noCategories'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final k in state.kategorien)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: state.kategorie == k.category,
                            label: Text('${k.category} (${k.count})'),
                            onSelected: state.laedt
                                ? null
                                : (_) => notifier.waehleKategorie(k.category),
                          ),
                        ),
                    ],
                  ),
          ),
          // --- Die Kandidaten ----------------------------------------
          Expanded(
            child: state.laedt
                ? const Center(child: CircularProgressIndicator())
                : state.kandidaten.isEmpty
                ? _EmptyHint(
                    kategorie: state.kategorie,
                    kategorien: state.kategorien,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: state.kandidaten.length,
                    itemBuilder: (context, i) {
                      final profil = state.kandidaten[i];
                      return _KandidatKarte(
                        profil: profil,
                        onLike: () => _like(profil),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Der Leerzustand der Kategorie-Sicht: KEINE Sackgasse.
///
/// BEFUND (11.11.2026): Bei einer leeren Kategorie stand nur ein nackter
/// Text - der Nutzer stand da. Die App kennt aber die Zahl je Kategorie
/// (`get_find_match_categories`). Also sagt sie, wo es Menschen gibt.
///
/// Ist ueberhaupt niemand da, wird das ehrlich gesagt - mit dem Hinweis,
/// spaeter wiederzukommen.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.kategorie, required this.kategorien});

  /// Die gewaehlte Kategorie (der Name im Text).
  final String? kategorie;

  /// Alle Kategorien mit ihren Zahlen.
  final List<CategoryCount> kategorien;

  @override
  Widget build(BuildContext context) {
    // Die Kategorien mit Menschen - die gewaehlte faellt weg.
    final mitMenschen =
        kategorien.where((k) => k.count > 0 && k.category != kategorie).toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    final gezeigt = mitMenschen.take(3).toList();

    if (gezeigt.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            L10n.t(context, 'fymb.emptyNoOne'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final liste = gezeigt.map((k) => '${k.category} (${k.count})').join(', ');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          L10n.tf(context, 'fymb.emptyOther', {
            'kategorie': kategorie ?? '',
            'liste': liste,
          }),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Eine Karte mit einem Kandidaten: Name, Alter, Vorstellungstext,
/// Interessen - und der Like-Knopf.
class _KandidatKarte extends StatelessWidget {
  const _KandidatKarte({required this.profil, required this.onLike});

  final UserProfile profil;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  child: const Icon(Icons.visibility_off, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${profil.name}'
                    '${profil.age != null ? ', ${profil.age}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onLike,
                  icon: const Icon(Icons.favorite, size: 18),
                  label: Text(L10n.t(context, 'fymb.like')),
                ),
              ],
            ),
            if (profil.introText.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                profil.introText.trim(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (profil.interests.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final interesse in profil.interests)
                    Chip(
                      label: Text(interesse),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
