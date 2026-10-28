import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import 'package:thestia/models/app_settings.dart';
import 'package:thestia/models/gender.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/admin/admin_screen.dart';
import 'package:thestia/services/verification_service.dart'
    show verificationSubmittedKey, verificationServiceProvider;
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/birthday_style.dart';
import 'package:thestia/widgets/donate_button.dart';
import 'package:thestia/widgets/new_account_badge.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/widgets/profile_widgets.dart';
import 'package:thestia/widgets/scroll_more_hint.dart';

/// Form der Profil-Dialoge (Profil-Menü, Profil-Vorschau, Vorstellung).
///
/// NUTZERWUNSCH (28.10.2026): "Beim Reiter Profil, soll wenn man auf
/// den Profil Button drückt, das Popup mit Profil bearbeiten, Profil
/// vorschau und Vorstellung vorschau auch unten abgerundet sein".
///
/// Standardmaessig ist ein Bottom-Sheet nur OBEN abgerundet - unten
/// stossen die Ecken an den Bildschirmrand. Mit einem Radius an allen
/// vier Ecken schliesst das Blatt sichtbar ab.
ShapeBorder profilDialogForm() => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );

/// Der kleine Streifen oben in den Profil-Dialogen.
///
/// NUTZERWUNSCH (28.10.2026): "und oben diesen kleinen streifen haben,
/// der zeigt, dass man das Pop up wie gerade auch schon, nach unten weg
/// schieben kann".
///
/// Ein dünner Balken in der Mitte - die uebliche Sprache fuer
/// "wegschieben".
Widget profilGriffleiste(BuildContext context) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

/// Umschalter in der Profil-Vorschau: normal oder Geburtstag.
///
/// NUTZERWUNSCH (28.10.2026): "Unter Profil Vorschau soll man
/// zwischen der normalen Profil Vorschau und der Profil Vorschau fuer
/// den Geburtstag wechseln koennen."
///
/// Zwei Pillen statt eines Schalters: der Geburtstags-Zustand ist ein
/// ZWEITER Zustand, kein An-Aus - man will sehen, wie das Profil in
/// beiden Varianten aussieht.
class ProfilVorschauUmschalter extends StatelessWidget {
  const ProfilVorschauUmschalter({
    required this.geburtstag,
    required this.onChanged,
    super.key,
  });

  /// Zustand: true = Geburtstags-Vorschau.
  final ValueListenable<bool> geburtstag;

  /// Wird bei jedem Wechsel aufgerufen.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: geburtstag,
      builder: (context, istGeburtstag, _) {
        return Row(
          children: [
            _Pill(
              label: L10n.t(context, 'profile.preview.modeNormal'),
              icon: Icons.person_outline,
              selected: !istGeburtstag,
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 8),
            _Pill(
              label: L10n.t(context, 'profile.preview.modeBirthday'),
              icon: Icons.auto_awesome,
              selected: istGeburtstag,
              onTap: () => onChanged(true),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Pille des Umschalters.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profil-Anzeige des eigenen Nutzers mit Schnellzugriff auf Bearbeiten
/// und Einstellungen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Das Bundesland fuer die Kopfzeile, oder null wenn keines gesetzt ist.
  ///
  /// v0.10.0: Ersetzt den Ort in derselben Zeile. Bewusst eine kleine
  /// Funktion statt zweier Inline-Ausdruecke: die Zeile stand zweimal im
  /// File, und bei zwei Kopien zeigt eine gern das Bundesland und die
  /// andere keines.
  static String? _stateLabel(UserProfile profile) {
    final st = profile.state?.trim();
    if (st == null || st.isEmpty) return null;
    return st;
  }

  /// Haelt den Bundesland-Teil der Kopfzeile zusammen - inklusive
  /// fuehrendem Trennzeichen, damit die Zeile nicht mit einem "·" endet,
  /// wenn es kein Bundesland gibt.
  static String stateSuffix(UserProfile profile) {
    final st = _stateLabel(profile);
    return st == null ? '' : ' · $st';
  }

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
                    // Konto juenger als 7 Tage. Auf dem eigenen Profil
                    // sichtbar, damit man sieht, wie man bei anderen
                    // wirkt - die eigentliche Wirkung ist die Anzeige
                    // auf fremden Profilen.
                    if (profile.isRecentlyCreated) ...[
                      const SizedBox(width: 6),
                      NewAccountBadge(profile: profile),
                    ],
                  ],
                ),
              ),
              Center(
                child: Text(
                  '${profile.age != null ? '${profile.age} ${L10n.t(context, 'profile.years')}' : L10n.t(context, 'profile.ageUnknown')}'
                  '${genderLabel.isNotEmpty ? ' · $genderLabel' : ''}'
                  // v0.10.0: Bundesland statt Ort. Der Ort war
                  // der eigentlich sensible Teil und wird nicht
                  // mehr gespeichert (Migration 135/136).
                  '${stateSuffix(profile)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              // Persönlichkeitstyp als Chip (Badge steht jetzt beim Namen).
              if (profile.personalityType != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: Chip(
                    label: Text(
                        '${L10n.t(context, 'profile.typePrefix')} ${profile.personalityType}'),
                  ),
                ),
              ],
              // Verifizierungs-Status (v0.9.1): Prüfung läuft oder
              // Einstieg in den Video-Flow (Konto bleibt immer nutzbar).
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
              // Spenden-Button, wieder da (bis v0.4.0 entfernt, weil die
              // Zahlung eine Attrappe war). Ohne hinterlegte Adresse sagt
              // der Button das auch - es tut so, als waere gespendet
              // worden, waere schlimmer als gar nichts.
              const Center(child: DonateButton()),
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
      shape: profilDialogForm(),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Der kleine Streifen oben: er sagt "das kannst du nach
            // unten wegschieben" (NUTZERWUNSCH, 28.10.2026).
            profilGriffleiste(context),
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
      shape: profilDialogForm(),
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
              profilGriffleiste(context),
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

    // Zustand des Umschalters: normale Vorschau oder Geburtstags-Vorschau.
    //
    // NUTZERWUNSCH (28.10.2026): "Unter Profil Vorschau soll man
    // zwischen der normalen Profil Vorschau und der Profil Vorschau
    // fuer den Geburtstag wechseln koennen."
    //
    // Ein ValueNotifier statt eines StatefulBuilder: der Dialog wird bei
    // jeder Aenderung neu gebaut, ein StatefulBuilder wuerde den
    // ganzen Blatt-Baum neu aufbauen - der Notifier hoert nur auf die
    // Teile, die sich aendern.
    final geburtstag = ValueNotifier<bool>(false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: profilDialogForm(),
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
              profilGriffleiste(context),
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
          const SizedBox(height: 16),
          // Umschalter: normale Vorschau oder Geburtstag.
          ProfilVorschauUmschalter(
            geburtstag: geburtstag,
            onChanged: (v) => geburtstag.value = v,
          ),
          const SizedBox(height: 24),
          // Der Avatar reagiert auf den Umschalter: im Geburtstags-Modus
          // bekommt er den Stil-Rahmen (Verlauf) wie im echten Profil.
          ValueListenableBuilder<bool>(
            valueListenable: geburtstag,
            builder: (context, istGeburtstag, _) {
              final avatar = CircleAvatar(
                radius: 56,
                backgroundColor: isPhotosVisible
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey.shade300,
                child: !isPhotosVisible
                    ? const Icon(Icons.visibility_off,
                        size: 48, color: Colors.white)
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
              );
              if (!istGeburtstag) return avatar;
              return BirthdayStyleFrame(
                style: profile.birthdayStyle,
                active: true,
                borderRadius: 56,
                child: avatar,
              );
            },
          ),
          // Der Chip weist den aktiven Stil aus (wie im echten Profil).
          ValueListenableBuilder<bool>(
            valueListenable: geburtstag,
            builder: (context, istGeburtstag, _) => istGeburtstag
                ? const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Center(child: BirthdayChip()),
                  )
                : const SizedBox.shrink(),
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
                    '${stateSuffix(profile)}',
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

  /// Zustands-Listener. Ohne das Feld wurde bei JEDEM Klick auf Play ein
  /// weiterer Listener auf denselben Player gehaengt - nach 20 Klicks liefen
  /// 20 Closures, alle mit setState.
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void dispose() {
    _stateSub?.cancel();
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
      await _stateSub?.cancel();
      _stateSub = _player.playerStateStream.listen((state) {
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
