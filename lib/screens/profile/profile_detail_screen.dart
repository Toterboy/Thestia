import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/models/profile/habitude_level.dart';
import 'package:thestia/models/profile/user_mood.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/utils/location/distance_bucket.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/widgets/common/birthday_style.dart';
import 'package:thestia/widgets/chat/centered_name_with_badges.dart';
import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:thestia/widgets/profile/intro_audio_player.dart';
import 'package:thestia/widgets/profile/new_account_badge.dart';
import 'package:thestia/widgets/profile/profile_widgets.dart';
import 'package:thestia/widgets/profile/music_taste_widgets.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/publicprofileavatar.dart';
part 'parts/publicprofileavatarstate.dart';
part 'parts/savedprofileaction.dart';
part 'parts/avatarretryloader.dart';

/// Versucht, ein Nutzerprofil anhand seiner ID aus den verfügbaren Quellen
/// aufzulösen (eigenes Profil, Matches). Liefert null, wenn kein Profil in
/// den synchronen Quellen gefunden wurde — der Aufrufer kann dann asynchron
/// die Supabase public_profiles-View abfragen.
UserProfile? resolveProfileById(WidgetRef ref, String userId) {
  if (userId.isEmpty) return null;

  // Eigenes Profil.
  final me = ref.read(profileProvider);
  if (me.id == userId) return me;

  // Partner aus bestehenden Matches.
  for (final match in ref.read(chatProvider)) {
    if (match.partner.id == userId) return match.partner;
  }

  return null;
}

/// Öffentliches Profil eines anderen Nutzers (aus Chat oder Matches).
///
/// Zeigt nur die Infos, die laut Alters-Sichtbarkeitsregeln erlaubt sind
/// (z. B. Fotos erst nach Match). Bietet keinen Bearbeiten-Button.
///
/// Lädt das fremde Profil aus mehreren Quellen: synchron aus Matches/
/// Vorschlägen, asynchron als Fallback aus der Supabase public_profiles-View.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<ProfileDetailScreen> createState() =>
      _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  UserProfile? _profile;

  /// Fertiger Anzeigetext fuer die Entfernung (v0.10.0).
  ///
  /// Gespeichert wird der TEXT, nicht die Kilometerzahl: die Umrechnung
  /// in eine 10-km-Stufe soll genau einmal passieren, direkt nach dem
  /// Server-Aufruf. Ein zweiter Aufbau-Punkt (andere Sprache, anderer
  /// Wert) kann sonst einen veralteten Text zeigen.
  String? _distanceLabel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.userId;
    if (mounted) setState(() => _loading = true);
    // Synchron aus bekannten Quellen (sofortige Anzeige).
    var profile = resolveProfileById(ref, userId);

    // Frische Serverdaten bevorzugen (v0.9.1-Fix: der lokale Chat-Partner
    // war oft veraltet - ohne Vorstellungstext/Audio-Pfad wirkte die
    // Vorstellung als "nicht sichtbar/hörbar"). Server-Fehler -> lokal.
    // Kein Supabase verfügbar oder User nicht gefunden.
    await bestEffort('from', () async {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final row = await db.fetchPublicProfile(userId);
      if (row != null) {
        profile = UserProfile.fromPublicView(
          Map<String, dynamic>.from(row as Map),
        );
      }
    });

    // Distanz serverseitig berechnet, Anzeige als 10-km-Stufe.
    //   Der Server liefert null, wenn die andere Person die Anzeige
    //   nicht freigegeben hat - dann steht hier nichts.
    await bestEffort('t', () async {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final distance = await db.fetchDistanceKm(userId);
      if (mounted) {
        setState(() {
          _distanceLabel = DistanceBucket.labelForKm(
            distance,
            (key) => L10n.t(context, key),
          );
        });
      }
    });

    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    if (_loading && profile == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          title: Text(L10n.t(context, 'profile.detail.title')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      // Profil konnte nicht aufgelöst werden (z. B. Demo-Mock ohne Daten).
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          title: Text(L10n.t(context, 'profile.detail.title')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.t(context, 'profile.detail.unavailable')),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _loadProfile,
                  icon: const Icon(Icons.refresh),
                  label: Text(L10n.t(context, 'profile.detail.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    final me = ref.watch(profileProvider);

    final genderLabel = profile.gender != null && profile.gender!.isNotEmpty
        ? (Gender.fromValue(profile.gender) != null
              ? L10n.t(context, Gender.fromValue(profile.gender)!.labelKey)
              : '')
        : '';

    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: profile.age ?? 16,
      viewerAge: me.age ?? 16,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: true, // Im Kontext von Chat/Matches ist ein Match gegeben.
    );
    // Audit M-18: Geburtsdaten (auch fremder Nutzer!) sind PII - nur im
    // Debug-Build loggen.
    if (kDebugMode) {
      debugPrint(
        '[PROFILE_DETAIL] targetAge=${profile.age}, viewerAge=${me.age}, '
        'targetBirthDate=${profile.birthDate}, viewerBirthDate=${me.birthDate}',
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Zurück zur vorherigen Seite (Chat/Matches), falls möglich.
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.interessen);
            }
          },
        ),
        title: Text(profile.name),
        actions: [
          // "Profil lokal speichern" (v0.9.1): Fremde Profile (z. B. per
          // QR gescannt, ohne Internet) lokal behalten, um sie später
          // anzuschreiben. Max. 5, einzeln löschbar. Für das eigene Profil
          // ausgeblendet.
          if (me.id != profile.id) _SavedProfileAction(profile: profile),
          // Melden + Blockieren (Fake-Schutz, Nutzerwunsch): Direkt am
          // fremden Profil - gegen falsche Alters-/Geschlechtsangaben und
          // Belästigung (gleiche Dialoge wie im Chat).
          if (me.id != profile.id)
            PopupMenuButton<String>(
              tooltip: L10n.t(context, 'profile.detail.reportUser'),
              onSelected: (value) {
                if (value == 'report') {
                  showReportUserDialog(
                    context: context,
                    ref: ref,
                    reportedUserId: profile.id,
                    reportedUserName: profile.name,
                  );
                } else if (value == 'block') {
                  _confirmBlock(context, ref, profile);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined),
                      const SizedBox(width: 8),
                      Text(L10n.t(ctx, 'profile.detail.reportUser')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      const Icon(Icons.block, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(L10n.t(ctx, 'profile.detail.blockUser')),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: BirthdayStyleSurface(
        style: profile.birthdayStyle,
        active: profile.birthdayToday,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: _PublicProfileAvatar(
                  profile: profile,
                  isPhotosVisible: isPhotosVisible,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: CenteredNameWithBadges(
                  name:
                      '${profile.name}${profile.age != null && profile.age! > 0 ? ', ${profile.age}' : ''}'
                      '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                      '${(profile.state ?? '').isNotEmpty ? ' · ${profile.state}' : ''}',
                  // v0.10.0: Der Ortsname ist entfallen. Vorher stand
                  // hier ein Fallback "Stadt, wenn kein Bundesland
                  // gesetzt war" - damit stand der genauere Ort genau
                  // dann im Profil, wenn die grobe Angabe fehlte. Das
                  // war die unguenstigste Reihenfolge.
                  style: Theme.of(context).textTheme.titleMedium,
                  badges: [
                    // Verifiziert-Badge direkt neben dem Namen
                    // (Nutzerwunsch; serverseitig durch Admin-Freigabe).
                    if (profile.isVerified)
                      Tooltip(
                        message: L10n.t(context, 'verify.badge'),
                        child: Icon(
                          Icons.verified,
                          size: 20,
                          color: Colors.lightBlue.shade400,
                        ),
                      ),
                    // Konto juenger als 7 Tage. Hier ist der Hinweis
                    // wertvoll: bei einem neuen Account ist eine
                    // ungefragte Nachricht mit hoher Wahrscheinlichkeit
                    // Missbrauch. Die RPC liefert created_at bereits mit.
                    // Verifikations-Hinweis bei ANDEREN Personen
                    // (v0.10.0). Nur wenn die Person NICHT verifiziert
                    // ist - ein "wird geprueft" ist eine Information, ein
                    // "verifiziert" hat bereits das Abzeichen.
                    //
                    // Drei Zustaende, bewusst getrennt: wer sich geprueft
                    // hat, aber die Freigabe noch nicht hat, ist nicht
                    // "nicht verifiziert", sondern "wird geprueft".
                    if (!profile.isVerified &&
                        profile.verificationState ==
                            VerificationState.underReview)
                      Tooltip(
                        message: L10n.t(context, 'verify.otherUnderReview'),
                        child: Icon(
                          Icons.hourglass_top,
                          size: 18,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    if (profile.isRecentlyCreated)
                      NewAccountBadge(profile: profile),
                  ],
                ),
              ),
              // v0.10.0: Nur anzeigen, wenn der Wert ueberhaupt eine
              // sichtbare Stufe ergibt. Unterhalb von 5 km liefert
              // labelForKm null - das ist Absicht: der Unterschied zwischen
              // 2 und 4 km verrate sonst den Nachbarn. Bei fehlendem
              // Label bleibt die Zeile weg, statt "0 km" zu zeigen.
              if (_distanceLabel != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _distanceLabel!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
              // Persönlichkeitstyp als Chip (Badge steht jetzt beim Namen).
              if (profile.personalityType != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                    label: Text(
                      L10n.tf(context, 'profile.detail.type', {
                        't': profile.personalityType ?? '',
                      }),
                    ),
                  ),
                ),
              ],
              if (profile.mood != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                    avatar: Icon(
                      Mood.fromValue(profile.mood)?.icon ?? Icons.mood,
                      size: 18,
                      color: Mood.fromValue(profile.mood)?.color,
                    ),
                    label: Text(
                      'Mood: ${Mood.fromValue(profile.mood) != null ? L10n.t(context, Mood.fromValue(profile.mood)!.labelKey) : (profile.mood ?? '')}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // BEFUND (07.11.2026, Betreiber): "doppeltes Profilbild".
              //
              // Hier stand ein Verlaufsblock mit Personen-Icon - direkt
              // unter dem echten Profilbild. Das las sich wie ein ZWEITES
              // Profilbild, das nicht geladen werden kann. Die Bilder
              // selbst zeigt _PublicProfileAvatar: das Hauptbild plus die
              // Thumbnails der weiteren Fotos (max. 3).
              //
              // Der Block ist deshalb weg. Bei gesperrten Fotos steht
              // stattdessen der Grund (photosLockedHint) - der wird
              // bereits im Avatar angezeigt.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.t(context, 'profile.detail.aboutMe'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.bio.isEmpty
                            ? L10n.t(context, 'profile.detail.noBio')
                            : profile.bio,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Vorstellung der anderen Person (Text + Audio, v0.9.1-Fix):
              // War bisher nur im Chat als 2-Zeilen-Vorschau sichtbar und im
              // Profil-Screen gar nicht - deshalb wirkte die Vorstellung als
              // "nicht aufrufbar". Jetzt eigene Karte mit vollem Text und
              // abspielbarer Audio-Vorstellung.
              if (profile.introText.isNotEmpty ||
                  profile.introAudioPath != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.record_voice_over_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              L10n.t(context, 'chat.introTitle'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        if (profile.introText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(profile.introText),
                        ],
                        if (profile.introAudioPath != null) ...[
                          const SizedBox(height: 12),
                          IntroAudioPlayer(targetUserId: profile.id),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (profile.interests.isNotEmpty) ...[
                Builder(
                  builder: (context) {
                    // Gemeinsame Interessen mit dem eigenen Profil hervorheben.
                    final me = ref.watch(profileProvider);
                    final common = profile.interests
                        .where(me.interests.contains)
                        .toList();
                    final others = profile.interests
                        .where((i) => !me.interests.contains(i))
                        .toList();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.t(context, 'profile.detail.interests'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (common.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    L10n.t(
                                      context,
                                      'profile.detail.commonWithYou',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              InterestChips(
                                interests: common,
                                highlighted: true,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (others.isNotEmpty) ...[
                              if (common.isNotEmpty)
                                Text(
                                  L10n.t(context, 'profile.detail.more'),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              const SizedBox(height: 8),
                              InterestChips(interests: others),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              // Musik-Geschmack (v0.8.0): gemeinsame Genres hervorgehoben.
              // Plus Lieblingssong/Band (v0.9.1, aus der Einrichtung).
              //
              // BEFUND (22.11.2026, Betreiber): "Musik Genres, die man
              // mag und Lieblings-Song und Künstler werden alle nicht im
              // Profil angezeigt (öffentlich)." Der Lieblings-Kuenstler
              // (Lieblingsband) fehlte in der Bedingung - stand nur der
              // Lieblings-Kuenstler im Profil, war die ganze Karte weg.
              if (profile.musicLiked.isNotEmpty ||
                  profile.musicDisliked.isNotEmpty ||
                  (profile.favoriteSong?.isNotEmpty == true) ||
                  (profile.favoriteBand?.isNotEmpty == true)) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final me = ref.watch(profileProvider);
                    final common = profile.musicLiked
                        .where(me.musicLiked.contains)
                        .toList();
                    final others = profile.musicLiked
                        .where((g) => !me.musicLiked.contains(g))
                        .toList();
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.music_note,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  L10n.t(context, 'profile.detail.music'),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (profile.favoriteSong?.isNotEmpty == true) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.star_outline,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      L10n.tf(
                                        context,
                                        'profile.detail.favoriteSong',
                                        {'song': profile.favoriteSong!},
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            // Lieblingsband (getrennt, Migration 119).
                            if (profile.favoriteBand?.isNotEmpty == true) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.music_note_outlined,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      L10n.tf(
                                        context,
                                        'profile.detail.favoriteBand',
                                        {'band': profile.favoriteBand!},
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (common.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    L10n.t(context, 'profile.detail.sameTaste'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              MusicTasteView(liked: common, commonWith: common),
                              const SizedBox(height: 12),
                            ],
                            if (others.isNotEmpty) ...[
                              if (common.isNotEmpty)
                                Text(
                                  L10n.t(context, 'profile.detail.more'),
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              const SizedBox(height: 8),
                              MusicTasteView(liked: others),
                            ],
                            if (profile.musicDisliked.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              MusicTasteView(
                                liked: const [],
                                disliked: profile.musicDisliked,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              // Die Gewohnheiten (Rauchen/Alkohol/Drogen).
              //
              // NUTZERWUNSCH (22.11.2026): "Man soll diese Punkte und die
              // Gewohnheiten einzeln fürs öffentliche Profil an und aus
              // machen können." Die Werte kommen vom Server - ist eine
              // Gewohnheit abgeschaltet, liefert der Server null und sie
              // steht hier nicht.
              if (profile.smoking != null ||
                  profile.alcohol != null ||
                  profile.drugs != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_cafe_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              L10n.t(context, 'profile.detail.habits'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final eintrag in <(String, HabitudeLevel?)>[
                          ('profile.detail.habitSmoking', profile.smoking),
                          ('profile.detail.habitAlcohol', profile.alcohol),
                          ('profile.detail.habitDrugs', profile.drugs),
                        ])
                          if (eintrag.$2 != null) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${L10n.t(context, eintrag.$1)}: '
                                    '${_habitudeLabel(context, eintrag.$2!)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Der Text einer Gewohnheit (NUTZERWUNSCH 22.11.2026: die Gewohnheiten
/// stehen im oeffentlichen Profil).
String _habitudeLabel(BuildContext context, HabitudeLevel stufe) {
  switch (stufe) {
    case HabitudeLevel.never:
      return L10n.t(context, 'profile.detail.habitNever');
    case HabitudeLevel.occasionally:
      return L10n.t(context, 'profile.detail.habitOccasionally');
    case HabitudeLevel.daily:
      return L10n.t(context, 'profile.detail.habitDaily');
  }
}

/// Blockieren-Bestätigung am fremden Profil (gleicher Dialog-Stil und
/// Ablauf wie im Chat: serverseitig blocken, danach zurück).
Future<void> _confirmBlock(
  BuildContext context,
  WidgetRef ref,
  UserProfile profile,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.block, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(L10n.t(ctx, 'chat.blockTitle'))),
        ],
      ),
      content: Text(L10n.tf(ctx, 'chat.blockBody', {'name': profile.name})),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(L10n.t(ctx, 'chat.blockAction')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await SupabaseDatabaseService(SupabaseService.client).blockUser(profile.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          L10n.tf(context, 'chat.blockedDone', {'name': profile.name}),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(AppRoutes.interessen);
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'chat.blockFailed')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
