import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import 'package:wisp/models/app_settings.dart';
import 'package:wisp/models/gender.dart';
import 'package:wisp/models/user_profile.dart';
import 'package:wisp/providers/mood_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/admin/admin_screen.dart';
import 'package:wisp/services/verification_service.dart'
    show verificationSubmittedKey, verificationServiceProvider;
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/supabase_storage_service.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/widgets/birthday_style.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/widgets/profile_widgets.dart';
import 'package:wisp/widgets/scroll_more_hint.dart';

/// Profil-Anzeige des eigenen Nutzers mit Schnellzugriff auf Bearbeiten
/// und Einstellungen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final settings = ref.watch(settingsProvider);

    final genderLabel = profile.gender != null && profile.gender!.isNotEmpty
        ? (Gender.fromValue(profile.gender) != null
            ? L10n.t(context, Gender.fromValue(profile.gender)!.labelKey)
            : '')
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'profile.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: L10n.t(context, 'profile.qrTooltip'),
            onPressed: () => context.push(AppRoutes.qrProfile),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: L10n.t(context, 'settings.title'),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: ScrollMoreHint(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: _OwnAvatar()),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Versteckter Admin-Zugang: Long-Press auf den Namen
                    // oeffnet nur fuer die konfigurierte Admin-ID den
                    // Admin-Bereich. Normale Nutzer erreichen ihn nicht.
                    GestureDetector(
                      onLongPress: isCurrentUserAdmin()
                          ? () => context.go(AppRoutes.admin)
                          : null,
                      child: Text(
                        profile.name.isEmpty
                            ? L10n.t(context, 'profile.unknown')
                            : profile.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: Text(
                  '${profile.age != null ? '${profile.age} ${L10n.t(context, 'profile.years')}' : L10n.t(context, 'profile.ageUnknown')}'
                  '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                  '${profile.city.isNotEmpty ? ' · ${profile.city}' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              // Verifiziert-Badge direkt neben dem Persönlichkeitstyp
              // (Nutzerwunsch; Layout wie im Profil-Detail-Screen).
              if (profile.isVerified || profile.personalityType != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (profile.isVerified)
                        Tooltip(
                          message: L10n.t(context, 'verify.badge'),
                          child: Icon(
                            Icons.verified,
                            size: 20,
                            color: Colors.lightBlue.shade400,
                          ),
                        ),
                      if (profile.isVerified && profile.personalityType != null)
                        const SizedBox(width: 6),
                      if (profile.personalityType != null)
                        Chip(
                          label: Text(
                              '${L10n.t(context, 'profile.typePrefix')} ${profile.personalityType}'),
                        ),
                    ],
                  ),
                ),
              ],
              // Verifizierungs-Status (v0.9.1): Prüfung läuft oder
              // Einstieg in den Video-Flow (Konto bleibt immer nutzbar).
              // Das Badge selbst steht oben neben dem Persönlichkeitstyp.
              if (!profile.isVerified) ...[
                const SizedBox(height: 8),
                const _VerificationStatusCard(),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L10n.t(context, 'profile.aboutMe'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        profile.bio.isEmpty
                            ? L10n.t(context, 'profile.noBio')
                            : profile.bio,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (profile.interests.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t(context, 'profile.interests'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        InterestChips(interests: profile.interests),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const _MoodCard(),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: Text(L10n.t(context, 'profile.blindModeTitle')),
                  subtitle: Text(L10n.t(context, 'profile.blindModeSub')),
                  value: settings.blindModeEnabled,
                  onChanged: (v) {
                    ref.read(settingsProvider.notifier).toggleBlindMode(v);
                    // Blind Mode gehört zu den gespiegelten UI-Einstellungen
                    // (v0.8.0) - entprellt serverseitig sichern.
                    scheduleUiPrefsServerSync(
                        ref.read(settingsProvider));
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showProfileMenu(context, ref, profile, settings),
                icon: const Icon(Icons.person),
                label: Text(L10n.t(context, 'profile.profileBtn')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.bugReport),
                icon: const Icon(Icons.bug_report),
                label: Text(L10n.t(context, 'profile.bugReportBtn')),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Profil-Menü: Profil bearbeiten, Profil Vorschau, Vorstellung Vorschau.
  void _showProfileMenu(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppSettings settings,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(L10n.t(context, 'profile.menu.edit')),
              subtitle: Text(L10n.t(context, 'profile.menu.editSub')),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push(AppRoutes.profileEdit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: Text(L10n.t(context, 'profile.menu.preview')),
              subtitle: Text(L10n.t(context, 'profile.menu.previewSub')),
              onTap: () {
                Navigator.of(ctx).pop();
                _showProfilePreview(context, ref, profile, settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: Text(L10n.t(context, 'profile.menu.introPreview')),
              subtitle:
                  Text(L10n.t(context, 'profile.menu.introPreviewSub')),
              onTap: () {
                Navigator.of(ctx).pop();
                _showIntroPreview(context, ref, profile);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Vorschau der eigenen Vorstellung (Text + Audio) für "Find your Match".
  void _showIntroPreview(BuildContext context, WidgetRef ref, UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                L10n.t(context, 'profile.intro.title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (profile.introText.isEmpty)
                Text(
                  L10n.t(context, 'profile.intro.empty'),
                  style: const TextStyle(color: Colors.grey),
                )
              else
                Text(
                  profile.introText,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              const SizedBox(height: 16),
              _OwnIntroAudioPlayer(
                userId: profile.id,
                hasAudio: profile.introAudioPath != null,
              ),
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'profile.intro.hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Zeigt eine Vorschau des eigenen Profils, wie es für andere sichtbar ist.
  void _showProfilePreview(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    AppSettings settings,
  ) {
    final myAge = profile.age ?? 16;
    // Audit M-18: Geburtsdatum ist PII - nur im Debug-Build loggen.
    if (kDebugMode) {
      debugPrint('[PROFILE_SCREEN] profile.age=${profile.age}, birthDate=${profile.birthDate}, myAge=$myAge');
    }
    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: myAge,
      viewerAge: myAge, // Selbst-Vorschau: gleiches Alter
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: true, // Bei Vorschau davon ausgehen, dass Match besteht
    );
    // Echtes (verschlüsseltes) Profilbild laden - v0.8.1-Fix: Die Vorschau
    // zeigte vorher NUR den Person-Platzhalter, egal welches Bild gesetzt
    // war. Einmalig vor dem Sheet erzeugt, damit der FutureBuilder nicht
    // bei jedem Rebuild neu lädt.
    final photoRef = profile.photos.isNotEmpty ? profile.photos.first : null;
    final Future<Uint8List?> avatarFuture = (isPhotosVisible && photoRef != null)
        ? ref.read(supabaseStorageServiceProvider).loadAvatarBytes(photoRef)
        : Future<Uint8List?>.value(null);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Text(
                L10n.t(context, 'profile.preview.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            L10n.t(context, 'profile.preview.hint'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 56,
              backgroundColor: isPhotosVisible
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.grey.shade300,
              child: !isPhotosVisible
                  ? const Icon(Icons.visibility_off, size: 48, color: Colors.white)
                  : FutureBuilder<Uint8List?>(
                      future: avatarFuture,
                      builder: (context, snap) {
                        final bytes = snap.data;
                        if (bytes != null) {
                          return ClipOval(
                            child: Image.memory(bytes,
                                width: 112, height: 112, fit: BoxFit.cover),
                          );
                        }
                        return const Icon(Icons.person,
                            size: 56, color: Colors.white);
                      },
                    ),
            ),
          ),
              const SizedBox(height: 16),
              Center(
                child: Builder(builder: (context) {
                  final genderName = profile.gender != null &&
                          profile.gender!.isNotEmpty
                      ? (Gender.fromValue(profile.gender) != null
                          ? L10n.t(
                              context, Gender.fromValue(profile.gender)!.labelKey)
                          : profile.gender!)
                      : '';
                  return Text(
                    '${profile.name}${profile.age != null ? ', ${profile.age}' : ''}'
                    '${genderName.isNotEmpty ? ' · $genderName' : ''}'
                    '${profile.city.isNotEmpty ? ' · ${profile.city}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  );
                }),
              ),
              if (profile.personalityType != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                      label: Text(
                          '${L10n.t(context, 'profile.preview.type')} ${profile.personalityType}')),
                ),
              ],
              if (!isPhotosVisible) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          L10n.t(context, 'profile.preview.photoHidden'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(L10n.t(context, 'profile.preview.aboutMe'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        profile.bio.isEmpty
                            ? L10n.t(context, 'profile.preview.noBio')
                            : profile.bio,
                      ),
                    ],
                  ),
                ),
              ),
              if (profile.interests.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.t(context, 'profile.preview.interests'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        InterestChips(interests: profile.interests),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                L10n.t(context, 'profile.preview.note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Verifizierungs-Status des eigenen Profils (v0.9.1).
///
/// Der Verifiziert-Badge steht oben in der Kopfzeile neben dem
/// Persönlichkeitstyp (Nutzerwunsch) - hier nur noch der Rest:
/// Eingereicht, aber noch kein Badge -> "Prüfung läuft" (Konto bleibt
/// voll nutzbar). Sonst Einstieg in den Video-Flow mit lokaler
/// KI-Triage (Modell auf dem Gerät, sonst manuelle Queue).
class _VerificationStatusCard extends ConsumerWidget {
  const _VerificationStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile.isVerified) {
      // Badge steht oben neben dem Persönlichkeitstyp - hier nichts.
      return const SizedBox.shrink();
    }
    return FutureBuilder<bool>(
      future: _submittedFlag(ref),
      builder: (context, snapshot) {
        final submitted = snapshot.data ?? false;
        if (submitted) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.hourglass_top_outlined),
              title: Text(L10n.t(context, 'verify.pendingChip')),
              subtitle: Text(L10n.t(context, 'verify.pendingHint')),
            ),
          );
        }
        if (!AppConstants.verificationEnabled) {
          return const SizedBox.shrink();
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(L10n.t(context, 'verify.cta')),
            subtitle: Text(L10n.t(context, 'verify.ctaSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.verificationInfo),
          ),
        );
      },
    );
  }

  Future<bool> _submittedFlag(WidgetRef ref) async {
    try {
      final storage = ref.read(localStorageProvider);
      // Badge da -> Merker aufräumen, Chip verschwindet von selbst.
      if (ref.read(profileProvider).isVerified) {
        await storage.remove(verificationSubmittedKey);
        return false;
      }
      final stored = await storage.getBool(verificationSubmittedKey) ?? false;
      if (!stored) return false;
      // Selbstheilung (Nutzer-Regel "läuft ohne Video"): Der Merker ohne
      // lokales Video (alte Installation, fremder Account-Rest) zeigt
      // fälschlich "Prüfung läuft" - aufräumen und CTA anzeigen. Ohne
      // Video gibt es serverseitig nichts zu prüfen.
      //
      // Robustheit: Service-Init abwarten (ungeöffnete Box würfe sonst
      // und der Chip bliebe fälschlich versteckt).
      final verificationService = ref.read(verificationServiceProvider);
      try {
        await verificationService.initialize();
      } catch (_) {}
      final video = verificationService.getVerificationVideo();
      if (video == null) {
        await storage.remove(verificationSubmittedKey);
        return false;
      }
      try {
        if (!await File(video.filePath).exists()) {
          await storage.remove(verificationSubmittedKey);
          return false;
        }
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }
}

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
            color: mood?.color.withValues(alpha: 0.15) ??
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
          child: Text(mood != null
              ? L10n.t(context, 'mood.change')
              : L10n.t(context, 'mood.select')),
        ),
      ),
    );
  }
}

/// Spielt die EIGENE Audio-Vorstellung ab (signierte URL des eigenen
/// Storage-Pfads - keine match-media-Berechtigung nötig).
class _OwnIntroAudioPlayer extends ConsumerStatefulWidget {
  const _OwnIntroAudioPlayer({required this.userId, required this.hasAudio});

  final String userId;
  final bool hasAudio;

  @override
  ConsumerState<_OwnIntroAudioPlayer> createState() =>
      _OwnIntroAudioPlayerState();
}

class _OwnIntroAudioPlayerState extends ConsumerState<_OwnIntroAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final storage = ref.read(supabaseStorageServiceProvider);
      final url =
          await storage.getSignedAvatarUrl('${widget.userId}/intro.m4a');
      if (url == null) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'profile.intro.audioMissing')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _player.setUrl(url);
      await _player.play();
      if (mounted) setState(() => _playing = true);
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      debugPrint('[OwnIntro] Fehler: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'profile.intro.audioLoadError')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasAudio) {
      return Text(
        L10n.t(context, 'profile.intro.audioEmpty'),
        style: const TextStyle(color: Colors.grey),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _toggle,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_playing ? Icons.stop : Icons.play_arrow),
      label: Text(_playing
          ? L10n.t(context, 'profile.intro.stop')
          : L10n.t(context, 'profile.intro.listen')),
    );
  }
}

/// Entschlüsselte Bild-Bytes für das EIGENE Profilbild (v0.8.1: Avatare
/// sind AES-256-GCM-verschlüsselt - Download + lokale Entschlüsselung).
final _ownAvatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, ref1) async {
  try {
    return await ref
        .read(supabaseStorageServiceProvider)
        .loadAvatarBytes(ref1);
  } catch (_) {
    return null;
  }
});

class _OwnAvatar extends ConsumerWidget {
  const _OwnAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(profileProvider).photos;
    final photoRef = photos.isNotEmpty ? photos.first : null;
    final bytes = photoRef == null
        ? null
        : ref.watch(_ownAvatarBytesProvider(photoRef)).valueOrNull;

    final placeholder = Icon(Icons.person,
        size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant);

    // v0.9.0: abgerundet-RECHTECKIG statt komplett rund.
    // Geburtstag: Stil-Rahmen am Ehrentag (Nutzerwunsch, dezent).
    final isBirthday =
        UserProfile.isBirthdayToday(ref.watch(profileProvider).birthDate);
    final birthdayStyle = ref.watch(profileProvider).birthdayStyle;
    final avatarBox = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 118,
        height: 152,
        color: Theme.of(context).colorScheme.primaryContainer,
        alignment: Alignment.center,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover,
                // LOAD-FIX: In Displaygröße dekodieren (2x DPR) statt das
                // Multi-MB-Original voll aufzulösen - deutlich schneller
                // sichtbar + weniger RAM.
                cacheWidth: 118 * 3,
                width: 118, height: 152)
            : placeholder,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BirthdayStyleFrame(
          style: birthdayStyle,
          active: isBirthday,
          borderRadius: 20,
          child: avatarBox,
        ),
        if (isBirthday) ...[
          const SizedBox(height: 8),
          const BirthdayChip(),
        ],
      ],
    );
  }
}
