import 'package:flutter/material.dart';

import 'package:wisp/l10n/app_strings.dart';

/// Musik-Genre-Katalog für "Geschmack & Matching" (v0.8.0, Migration 074).
///
/// Die Slugs sind die serverseitigen Werte (profiles.music_liked /
/// music_disliked, Migration 074) - NICHT umbenennen, sonst brechen
/// bestehende Profile. "instrumental" ist laut Roadmap Pflichtbestandteil.
class MusicGenre {
  const MusicGenre(this.slug, this.label);

  final String slug;
  final String label;
}

const kMusicGenres = <MusicGenre>[
  MusicGenre('pop', 'Pop'),
  MusicGenre('rock', 'Rock'),
  MusicGenre('indie', 'Indie'),
  MusicGenre('metal', 'Metal'),
  MusicGenre('punk', 'Punk'),
  MusicGenre('hip_hop', 'Hip-Hop'),
  MusicGenre('deutschrap', 'Deutschrap'),
  MusicGenre('rnb', 'R&B'),
  MusicGenre('soul', 'Soul'),
  MusicGenre('jazz', 'Jazz'),
  MusicGenre('blues', 'Blues'),
  MusicGenre('klassik', 'Klassik'),
  MusicGenre('instrumental', 'Instrumental'),
  MusicGenre('house', 'House'),
  MusicGenre('techno', 'Techno'),
  MusicGenre('rave_techno', 'Rave / Hard Techno'),
  MusicGenre('edm', 'EDM'),
  MusicGenre('reggae', 'Reggae'),
  MusicGenre('salsa_latin', 'Latin / Salsa'),
  MusicGenre('afrobeats', 'Afrobeats'),
  MusicGenre('k_pop', 'K-Pop'),
  MusicGenre('country', 'Country'),
  MusicGenre('folk', 'Folk'),
  MusicGenre('schlager', 'Schlager'),
  MusicGenre('volksmusik', 'Volksmusik'),
  MusicGenre('charts', 'Charts'),
];

String musicGenreLabel(String slug) {
  for (final g in kMusicGenres) {
    if (g.slug == slug) return g.label;
  }
  return slug;
}

/// Lokalisiertes Genre-Label (v0.9.1): Die meisten Genre-Namen sind
/// international identisch; nur abweichende stehen in L10n
/// (`music.genre.<slug>`), sonst gilt das deutsche Label.
String musicGenreLabelOf(BuildContext context, String slug) {
  for (final g in kMusicGenres) {
    if (g.slug == slug) {
      final key = 'music.genre.${g.slug}';
      final t = L10n.t(context, key);
      return t == key ? g.label : t;
    }
  }
  return slug;
}

/// Auswahl eines Musik-Geschmacks: Gemagte Genres (Mehrfachauswahl,
/// inkl. "Instrumental") + optional Genres, die man explizit nicht mag.
/// Ein Genre kann nicht gleichzeitig geliked UND disliked sein - ein
/// Klick auf das jeweils andere Feld zieht es dort zurück.
class MusicTasteEditor extends StatelessWidget {
  const MusicTasteEditor({
    required this.liked,
    required this.disliked,
    required this.onChanged,
    super.key,
  });

  final List<String> liked;
  final List<String> disliked;
  final void Function(List<String> liked, List<String> disliked) onChanged;

  void _toggle(String slug) {
    final nextLiked = [...liked];
    final nextDisliked = [...disliked];
    if (nextLiked.remove(slug)) {
      // war gemocht -> jetzt neutral
    } else if (nextDisliked.remove(slug)) {
      // war verneint -> jetzt neutral
    } else {
      nextLiked.add(slug);
    }
    onChanged(nextLiked, nextDisliked);
  }

  void _toggleDislike(String slug) {
    final nextLiked = [...liked];
    final nextDisliked = [...disliked];
    if (nextDisliked.remove(slug)) {
      // war verneint -> jetzt neutral
    } else if (nextLiked.remove(slug)) {
      // war gemocht -> jetzt verneint
      nextDisliked.add(slug);
    } else {
      nextDisliked.add(slug);
    }
    onChanged(nextLiked, nextDisliked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t(context, 'music.likedTitle'),
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in kMusicGenres)
              FilterChip(
                label: Text(musicGenreLabelOf(context, genre.slug)),
                selected: liked.contains(genre.slug),
                onSelected: (_) => _toggle(genre.slug),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(L10n.t(context, 'music.dislikedTitle'),
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in kMusicGenres)
              if (disliked.contains(genre.slug))
                FilterChip(
                  label: Text(musicGenreLabelOf(context, genre.slug)),
                  selected: true,
                  checkmarkColor: Theme.of(context).colorScheme.error,
                  selectedColor:
                      Theme.of(context).colorScheme.errorContainer,
                  onSelected: (_) => _toggleDislike(genre.slug),
                ),
            InputChip(
              avatar: const Icon(Icons.block, size: 16),
              label: Text(L10n.t(context, 'music.exclude')),
              onPressed: () => _pickDislike(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _pickDislike(BuildContext context) async {
    final remaining = kMusicGenres
        .where((g) => !liked.contains(g.slug) && !disliked.contains(g.slug))
        .toList();
    if (remaining.isEmpty) return null;
    // NUTZERWUNSCH "Umsetzung nicht gut": Das alte Sheet war eine nackte
    // ListView ohne Kontext. Jetzt: Titel + Erklärung, Suche (jedes
    // Genre auf einen Blick), Suchfeld mit Prompt und Loading-Klarschrift
    // - ein richtiges Auswahl-Sheet statt einer nackten Liste.
    final slug = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.65,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t(ctx, 'music.excludeTitle'),
                            style: Theme.of(ctx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            L10n.t(ctx, 'music.excludeHint'),
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.search, size: 20),
                          hintText: L10n.t(ctx, 'music.excludeSearch'),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (v) =>
                            setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final genre in remaining)
                            if (musicGenreLabelOf(ctx, genre.slug)
                                .toLowerCase()
                                .contains(query.toLowerCase()))
                              ListTile(
                                leading: const Icon(Icons.block_outlined,
                                    size: 18),
                                title: Text(
                                    musicGenreLabelOf(ctx, genre.slug)),
                                onTap: () =>
                                    Navigator.of(ctx).pop(genre.slug),
                              ),
                          if (remaining
                              .where((g) =>
                                  musicGenreLabelOf(ctx, g.slug)
                                      .toLowerCase()
                                      .contains(query.toLowerCase()))
                              .isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(L10n.t(
                                    ctx, 'music.excludeNoMatch')),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );
    if (slug != null && slug.isNotEmpty) _toggleDislike(slug);
    return slug;
  }
}

/// Zeigt den Musik-Geschmack eines (fremden) Profils an. Gemeinsame
/// gemagte Genres mit dem Betrachter werden hervorgehoben, wenn
/// [commonWith] gesetzt ist.
class MusicTasteView extends StatelessWidget {
  const MusicTasteView({
    required this.liked,
    this.disliked = const <String>[],
    this.commonWith = const <String>[],
    super.key,
  });

  final List<String> liked;
  final List<String> disliked;
  final List<String> commonWith;

  @override
  Widget build(BuildContext context) {
    if (liked.isEmpty && disliked.isEmpty) {
      return Text(
        L10n.t(context, 'profile.detail.noMusic'),
        style: const TextStyle(color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slug in liked)
          Chip(
            label: Text(musicGenreLabelOf(context, slug)),
            backgroundColor: commonWith.contains(slug)
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
        for (final slug in disliked)
          Chip(
            label: Text(
              '${musicGenreLabelOf(context, slug)} ✕',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
          ),
      ],
    );
  }
}
