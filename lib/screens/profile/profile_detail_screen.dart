import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/models/gender.dart';
import 'package:thestia/models/user_mood.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/widgets/birthday_style.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/widgets/intro_audio_player.dart';
import 'package:thestia/widgets/profile_widgets.dart';
import 'package:thestia/widgets/music_taste_widgets.dart';

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
  double? _distanceKm;
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
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final row = await db.fetchPublicProfile(userId);
      if (row != null) {
        profile = UserProfile.fromPublicView(
          Map<String, dynamic>.from(row as Map),
        );
      }
    } catch (_) {
      // Kein Supabase verfügbar oder User nicht gefunden.
    }

    // Distanz in km (5-km-Schritte, serverseitig berechnet) - optional.
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final distance = await db.fetchDistanceKm(userId);
      if (mounted) setState(() => _distanceKm = distance);
    } catch (_) {}

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
      body: SingleChildScrollView(
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${profile.name}${profile.age != null && profile.age! > 0 ? ', ${profile.age}' : ''}'
                      '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                      '${(profile.state ?? '').isNotEmpty ? ' · ${profile.state}' : ''}'
                      '${profile.city.isNotEmpty && (profile.state ?? '').isEmpty ? ' · ${profile.city}' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Verifiziert-Badge direkt neben dem Namen
                  // (Nutzerwunsch; serverseitig durch Admin-Freigabe).
                  if (profile.isVerified) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: L10n.t(context, 'verify.badge'),
                      child: Icon(
                        Icons.verified,
                        size: 20,
                        color: Colors.lightBlue.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_distanceKm != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  // Nur die gerundete Entfernung - nie der exakte Standort.
                  _distanceKm!.round() == 0
                      ? 'unter 5 km entfernt'
                      : 'ca. ${_distanceKm!.round()} km entfernt',
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
            if (isPhotosVisible)
              Container(
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Colors.deepPurple, Colors.blue],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.person, color: Colors.white, size: 48),
                ),
              ),
            const SizedBox(height: 16),
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
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  L10n.t(
                                    context,
                                    'profile.detail.commonWithYou',
                                  ),
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            InterestChips(interests: common, highlighted: true),
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
            if (profile.musicLiked.isNotEmpty ||
                profile.musicDisliked.isNotEmpty ||
                (profile.favoriteSong?.isNotEmpty == true)) ...[
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
                                style: Theme.of(context).textTheme.titleMedium,
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
                                  color: Theme.of(context).colorScheme.primary,
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
                                  color: Theme.of(context).colorScheme.primary,
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
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  L10n.t(context, 'profile.detail.sameTaste'),
                                  style: Theme.of(context).textTheme.labelLarge
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
          ],
        ),
      ),
    );
  }
}

/// Profilbild des FREMDEN Nutzers (v0.8.1-Fix + 107-Härtung): Schlüssel
/// kommen aus match-media (nur für Berechtigte), nie mehr aus der
/// Public-View. Respektiert Blind Mode / Foto-Freischaltung
/// (isPhotosVisible).
class _PublicProfileAvatar extends ConsumerStatefulWidget {
  const _PublicProfileAvatar({
    required this.profile,
    required this.isPhotosVisible,
  });

  final UserProfile profile;
  final bool isPhotosVisible;

  @override
  ConsumerState<_PublicProfileAvatar> createState() =>
      _PublicProfileAvatarState();
}

class _PublicProfileAvatarState extends ConsumerState<_PublicProfileAvatar> {
  Future<Uint8List?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _PublicProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Neues Bild (neue Referenz) -> neu laden.
    final oldRef = oldWidget.profile.photos.isNotEmpty
        ? oldWidget.profile.photos.first
        : null;
    final newRef = widget.profile.photos.isNotEmpty
        ? widget.profile.photos.first
        : null;
    if (oldRef != newRef) _loadAvatar();
  }

  void _loadAvatar() {
    // 107: Pfade aus der View enthalten keine Schlüssel mehr - Fremd-
    // Bilder laufen über match-media (URL + Schlüssel, serverseitig
    // berechtigungsgeprüft). VOR dem Laden den Memory-Cache-Eintrag
    // verwerfen (NUTZERWUNSCH "Bild einfach nicht sichtbar"): Ein alter
    // Schlüssel-Cache könnte sonst permanent ein nicht entschlüsselbares
    // Bild liefern.
    final path = widget.profile.photos.isNotEmpty
        ? widget.profile.photos.first
        : null;
    if (path == null) {
      _avatarFuture = null;
      return;
    }
    final service = ref.read(supabaseStorageServiceProvider);
    service.invalidatePartnerAvatar(
      targetUserId: widget.profile.id,
      path: path,
    );
    _avatarFuture = service.loadPartnerAvatarBytes(
      targetUserId: widget.profile.id,
      path: path,
    );
  }

  @override
  Widget build(BuildContext context) {
    // v0.9.0: abgerundet-RECHTECKIG statt komplett rund + Thumbnails der
    // weiteren Bilder (max. 3, gleiche Verschlüsselung wie Avatare).
    final scheme = Theme.of(context).colorScheme;
    final others = widget.profile.photos
        .skip(1)
        .take(SupabaseStorageService.maxPhotos - 1)
        .toList();

    Widget mainImage;
    if (!widget.isPhotosVisible) {
      mainImage = const Center(child: Icon(Icons.visibility_off, size: 48));
    } else if (_avatarFuture == null) {
      mainImage = Icon(Icons.person, size: 56, color: scheme.onSurfaceVariant);
    } else {
      mainImage = FutureBuilder<Uint8List?>(
        future: _avatarFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              // LOAD-FIX: In Displaygröße dekodieren statt das
              // Multi-MB-Original (schnellere Anzeige, weniger RAM).
              cacheWidth: 148 * 3,
              width: double.infinity,
              height: double.infinity,
            );
          }
          // NUTZERWUNSCH "Bild einfach nicht sichtbar": Am Ende des
          // Futures NICHT still stehen bleiben - ein Retry nach kurzer
          // Wartezeit holt ggf. einen frischen match-media-Schlüssel
          // (Cache-bereinigt), ohne Endlos-Spinner.
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Icon(
                Icons.person,
                size: 56,
                color: scheme.onSurfaceVariant,
              ),
            );
          }
          return _AvatarRetryLoader(
            onRetry: () => setState(() => _loadAvatar()),
          );
        },
      );
    }

    return Column(
      children: [
        // Geburtstag des Gegenübers: Stil-Rahmen + Chip (Nutzerwunsch,
        // dezent; birthdayToday kommt serverseitig ohne Geburtsdatum).
        BirthdayStyleFrame(
          style: widget.profile.birthdayStyle,
          active: widget.profile.birthdayToday,
          borderRadius: 20,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 148,
              height: 188,
              color: scheme.primaryContainer,
              child: mainImage,
            ),
          ),
        ),
        if (widget.profile.birthdayToday) ...[
          const SizedBox(height: 8),
          const Center(child: BirthdayChip()),
        ],
        // NUTZERWUNSCH "Profilbild nicht sichtbar": Bei gesperrten Fotos
        // (Quiz noch nicht bestanden / kein Foto hochgeladen) steht hier
        // jetzt DER GRUND statt eines stummen Platzhalters.
        if (!widget.isPhotosVisible) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              L10n.t(context, 'profile.detail.photosLockedHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (widget.isPhotosVisible && others.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ref1 in others)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 72,
                      height: 92,
                      color: scheme.surfaceContainerHighest,
                      // FIX "Profilbilder von anderen nicht sichtbar":
                      // Fremd-Thumbnails laufen wie das Hauptbild über
                      // match-media (Schlüssel/IV kommen serverseitig).
                      // loadAvatarBytes wäre der EIGENE Pfad -> 403 ->
                      // nur Spinner, nie ein Bild.
                      child: FutureBuilder<Uint8List?>(
                        future: ref
                            .read(supabaseStorageServiceProvider)
                            .loadPartnerAvatarBytes(
                              targetUserId: widget.profile.id,
                              path: ref1,
                            ),
                        builder: (context, snap) {
                          final b = snap.data;
                          if (b == null) {
                            return const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          return Image.memory(
                            b,
                            fit: BoxFit.cover,
                            cacheWidth: 72 * 3,
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// AppBar-Aktion "Profil lokal speichern" (v0.9.1): Erzeugt einen
/// PERSISTENTEN QR-Kontakt aus dem geladenen Profil (funktioniert auch
/// ohne Internet, da die Profil-Daten lokal übernommen werden). Max. 5;
/// bereits gespeicherte Profile lassen sich hier wieder entfernen.
class _SavedProfileAction extends ConsumerWidget {
  const _SavedProfileAction({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(chatProvider);
    final existing = contacts
        .where((m) => m.isQrContact && m.partner.id == profile.id)
        .firstOrNull;

    if (existing != null) {
      return IconButton(
        // NUTZERWUNSCH: Aktiv-Status farblich (gefülltes Icon in
        // Primärfarbe statt grauem Outline-Icon).
        icon: Icon(
          Icons.bookmark,
          color: Theme.of(context).colorScheme.primary,
        ),
        tooltip: L10n.t(context, 'profile.detail.savedRemove'),
        onPressed: () {
          ref.read(chatProvider.notifier).deleteQrContact(existing.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                L10n.tf(context, 'profile.detail.savedRemoved', {
                  'name': profile.name,
                }),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    return IconButton(
      icon: const Icon(Icons.bookmark_border),
      tooltip: L10n.t(context, 'profile.detail.savedSave'),
      onPressed: () async {
        final match = ref
            .read(chatProvider.notifier)
            .findOrCreateMatch(profile.id);
        if (match == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'qr.limitBody')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
        ref.read(chatProvider.notifier).updatePartner(match.id, profile);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'profile.detail.savedDone', {
                'name': profile.name,
              }),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
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

/// Platzhalter mit Retry-Tap für Partner-Avatare (NUTZERWUNSCH: "Bild
/// einfach nicht sichtbar" -> der Nutzer kann EINMAL selbst nachladen,
/// statt still nichts zu sehen; löscht auch den Memory-Cache-Eintrag).
class _AvatarRetryLoader extends StatelessWidget {
  const _AvatarRetryLoader({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onRetry,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.refresh,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
