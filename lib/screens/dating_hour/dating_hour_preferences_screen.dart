import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wisp/models/dating_hour_models.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/models/habitude_level.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/providers/user_preferences_provider.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/services/dating_hour_service.dart';
import 'package:wisp/widgets/age_range_sliders.dart';
import 'package:wisp/widgets/habitude_selector.dart';

/// Screen für Dating-Hour-Präferenzen (vor dem Event-Beitritt).
class DatingHourPreferencesScreen extends ConsumerStatefulWidget {
  const DatingHourPreferencesScreen({super.key});

  @override
  ConsumerState<DatingHourPreferencesScreen> createState() => _DatingHourPreferencesScreenState();
}

class _DatingHourPreferencesScreenState extends ConsumerState<DatingHourPreferencesScreen> {
  final _traitController = TextEditingController();

  // Altersbereich (Dating Hour ist 18+): Zwei gekoppelte Werte statt
  // RangeValues - der frühere RangeSlider "frohr" bei identischen Werten
  // (z. B. 18-18) ein, weil sich der End-Regler nicht mehr greifen ließ.
  int _ageMin = 18;
  int _ageMax = 99;
  late String _genderPreference;
  String _selectedTrait = 'Humor';
  int _maxDistanceKm = 50;
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

  static const List<String> _suggestedTraits = [
    'Humor', 'Ehrlichkeit', 'Abenteuerlust', 'Intelligenz',
    'Empathie', 'Spontanität', 'Zuverlässigkeit', 'Leidenschaft',
    'Offenheit', 'Bodenständigkeit',
  ];

  /// Angezeigter Name für gespeicherte (deutsche) Trait-Werte.
  static String _traitLabel(BuildContext context, String trait) {
    const keys = {
      'Humor': 'dh.prefs.trait.humor',
      'Ehrlichkeit': 'dh.prefs.trait.honesty',
      'Abenteuerlust': 'dh.prefs.trait.adventure',
      'Intelligenz': 'dh.prefs.trait.intelligence',
      'Empathie': 'dh.prefs.trait.empathy',
      'Spontanität': 'dh.prefs.trait.spontaneity',
      'Zuverlässigkeit': 'dh.prefs.trait.reliability',
      'Leidenschaft': 'dh.prefs.trait.passion',
      'Offenheit': 'dh.prefs.trait.openness',
      'Bodenständigkeit': 'dh.prefs.trait.downToEarth',
    };
    final key = keys[trait];
    return key == null ? trait : L10n.t(context, key);
  }

  @override
  void initState() {
    super.initState();
    // Defaults aus der Einrichtung übernehmen (Altersspanne, Geschlechts-
    // Präferenz, maximale Distanz) – ohne Anpassung sind die Dating-Hour-
    // Präferenzen identisch zu den regulären Filter-Einstellungen.
    final settings = ref.read(settingsProvider);
    final userPrefs = ref.read(userPreferencesProvider);
    // Eingangswerte in den Dating-Hour-Rahmen (18-99) einrasten; min/max
    // dabei gekoppelt halten (max >= min).
    _ageMin = settings.ageRangeMin.clamp(18, 99);
    _ageMax = settings.ageRangeMax.clamp(_ageMin, 99);
    _genderPreference = genderPrefFromList(userPrefs.genderPreferences);
    _maxDistanceKm = settings.maxDistanceKm;
    // ZULETZT GENUTZTE Dating-Hour-Präferenzen vom Server laden (Migration
    // 067) und die Defaults überschreiben - sie bleiben so über Events und
    // Neuinstallationen hinweg erhalten.
    _loadLastPreferences();
  }

  Future<void> _loadLastPreferences() async {
    try {
      final saved = await ref.read(datingHourServiceProvider).getMyLastPreferences();
      if (saved == null || !mounted) return;
      final last = DatingHourPreferences.fromJson(saved);
      setState(() {
        if (last.ageMin >= 18) {
          _ageMin = last.ageMin.clamp(18, 99);
          _ageMax = last.ageMax.clamp(_ageMin, 99);
        }
        _genderPreference = genderPrefFromList([last.genderPreference]);
        if (last.preferredTrait.isNotEmpty) _selectedTrait = last.preferredTrait;
        if (last.maxDistanceKm > 0) _maxDistanceKm = last.maxDistanceKm.round();
        _smoking = HabitudeLevel.fromServer(last.smoking);
        _alcohol = HabitudeLevel.fromServer(last.alcohol);
        _drugs = HabitudeLevel.fromServer(last.drugs);
      });
    } catch (_) {
      // Best-Effort: Ohne Server-Antwort gelten die Einrichtungs-Defaults.
    }
  }

  @override
  void dispose() {
    _traitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'dh.prefs.title')),
        leading: BackButton(
          onPressed: () {
            // Robuster Zurück-Weg: Der Screen kann auch ohne
            // Navigator-Stack geöffnet worden sein (context.go) – dann
            // führt pop() ins Leere (der alte X-Button "funktionierte
            // nicht"). In dem Fall direkt zum Event-Screen.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.datingHourEvent);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L10n.t(context, 'dh.prefs.header'),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'dh.prefs.intro'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Altersbereich
            _SectionTitle(L10n.t(context, 'dh.prefs.ageSection')),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Text(
              L10n.tf(context, 'dh.prefs.ageRange',
                      {'min': '$_ageMin', 'max': '$_ageMax'}),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Zwei gekoppelte Slider: Bei identischen Werten blieb der
            // RangeSlider "eingefroren" (Regler ausgegraut, keine Bewegung).
            AgeRangeSliders(
              minValue: _ageMin,
              maxValue: _ageMax,
              boundsMin: 18,
              boundsMax: 99,
              minLabelPrefix: L10n.t(context, 'profile.edit.minAgeLabel'),
              maxLabelPrefix: L10n.t(context, 'profile.edit.maxAgeLabel'),
              labelSuffix: L10n.t(context, 'common.years'),
              onChanged: (min, max) {
                setState(() {
                  _ageMin = min;
                  _ageMax = max;
                });
              },
            ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Gesuchte Geschlechter
            _SectionTitle(L10n.t(context, 'dh.prefs.genderSection')),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RadioGroup<String>(
                  groupValue: _genderPreference,
                  onChanged: (v) {
                    if (v != null) setState(() => _genderPreference = v);
                  },
                  child: Column(
                    // N: crossAxisAlignment stretch verhindert Overflow durch
                    // RadioListTiles auf schmalen Bildschirmen.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _GenderPreference.values.map((pref) {
                      return RadioListTile<String>(
                        title: Text(L10n.t(context, pref.labelKey)),
                        value: pref.value,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Automatische Teilnahme (Abfrage nach Ende eines Events)
            _SectionTitle(L10n.t(context, 'dh.prefs.joinSection')),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: Text(L10n.t(context, 'dh.prefs.autoJoin')),
                subtitle: Text(
                  L10n.t(context, 'dh.prefs.autoJoinHint'),
                ),
                value: ref.watch(settingsProvider).datingHourAutoJoin,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setDatingHourAutoJoin(v),
              ),
            ),

            const SizedBox(height: 24),

            // Bevorzugte Eigenschaft (Freitext + Vorschläge)
            _SectionTitle(L10n.t(context, 'dh.prefs.traitSection')),
            const SizedBox(height: 8),
            Text(
              L10n.t(context, 'dh.prefs.traitHint2'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestedTraits.map((trait) {
                final isSelected = _selectedTrait == trait;
                return FilterChip(
                  label: Text(_traitLabel(context, trait)),
                  selected: isSelected,
                  onSelected: (v) => setState(() => _selectedTrait = trait),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _traitController,
              decoration: InputDecoration(
                labelText: L10n.t(context, 'dh.prefs.traitOwn'),
                hintText: L10n.t(context, 'dh.prefs.traitHintField'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                prefixIcon: const Icon(Icons.edit),
              ),
              onChanged: (v) => setState(() => _selectedTrait = v.trim()),
              onSubmitted: (_) => _savePreferences(),
            ),

            const SizedBox(height: 32),

            // Gewohnheiten als weiche Matching-Präferenz
            Text(L10n.t(context, 'dh.prefs.habits'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, 'dh.prefs.habitsHint2'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.smoking,
              value: _smoking,
              onChanged: (v) => setState(() => _smoking = v),
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.alcohol,
              value: _alcohol,
              onChanged: (v) => setState(() => _alcohol = v),
            ),
            const SizedBox(height: 16),
            HabitudeSelector(
              topic: HabitudeTopic.drugs,
              value: _drugs,
              onChanged: (v) => setState(() => _drugs = v),
            ),

            const SizedBox(height: 32),

            // Speichern (ohne Beitritt)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(L10n.t(context, 'dh.prefs.save')),
                onPressed: _savePreferences,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Hinweis
            Text(
              L10n.t(context, 'dh.prefs.saveHint2'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePreferences() async {
    final service = ref.read(datingHourServiceProvider);
    final prefs = DatingHourPreferences(
      ageMin: _ageMin,
      ageMax: _ageMax,
      genderPreference: _genderPreference,
      preferredTrait: _selectedTrait.isNotEmpty ? _selectedTrait : _suggestedTraits.first,
      maxDistanceKm: _maxDistanceKm.toDouble(), // aus den Einrichtungs-Einstellungen
      smoking: _smoking?.toServer(),
      alcohol: _alcohol?.toServer(),
      drugs: _drugs?.toServer(),
    );

    // NUR Präferenzen speichern - KEIN automatischer Beitritt mehr.
    // Die Teilnahme erfolgt ausschließlich über den Button "Ich bin dabei"
    // auf dem Event-Screen.
    try {
      final event = await service.getCurrentOrNextEvent();
      if (event == null) {
        throw DatingHourException('Kein Event verfügbar');
      }
      await service.savePreferences(event.id, prefs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.prefs.savedHint')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.datingHourEvent);
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.tf(context, 'common.errorWith',
                  {'error': e.message}))),
        );
      }
    }
  }
}

/// Mappt die Geschlechts-Präferenz-Liste aus der Einrichtung auf die
/// Dating-Hour-Kategorien. Leer/alles = "all".
String genderPrefFromList(List<String> genderPreferences) {
  final values = genderPreferences.toSet();
  final all = kAllGenderValues.toSet();
  if (values.isEmpty || values.length >= all.length) return 'all';
  final maleish = {'male', 'male_trans'};
  final femaleish = {'female', 'female_trans'};
  final hasMale = values.intersection(maleish).isNotEmpty;
  final hasFemale = values.intersection(femaleish).isNotEmpty;
  if (hasMale && !hasFemale) return 'men';
  if (hasFemale && !hasMale) return 'women';
  return 'all';
}

/// Geschlechts-Präferenz für Dating Hour (Anzeige immer über labelKey).
enum _GenderPreference {
  all('all', 'dh.gender.all'),
  women('women', 'dh.gender.women'),
  men('men', 'dh.gender.men'),
  nonBinary('non_binary', 'dh.gender.nonBinary');

  const _GenderPreference(this.value, this.labelKey);
  final String value;
  final String labelKey;
}

/// Section-Title Widget.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
