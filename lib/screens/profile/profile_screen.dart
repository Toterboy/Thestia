import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/mood_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/admin/admin_screen.dart';
import 'package:thestia/services/verification/verification_service.dart'
    show verificationSubmittedKey, verificationServiceProvider;
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/common/birthday_style.dart';
import 'package:thestia/widgets/profile/profile_avatar_box.dart';
import 'package:thestia/widgets/chat/centered_name_with_badges.dart';
import 'package:thestia/widgets/common/donate_button.dart';
import 'package:thestia/widgets/profile/new_account_badge.dart';
import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/widgets/profile/profile_widgets.dart';
import 'package:thestia/widgets/common/scroll_more_hint.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/profilvorschauumschalter.dart';
part 'parts/pill.dart';
part 'parts/verificationstatuscard.dart';
part 'parts/moodcard.dart';
part 'parts/ownintroaudioplayer.dart';
part 'parts/ownintroaudioplayerstate.dart';
part 'parts/ownavatar.dart';

/// Form der Profil-Dialoge (Profil-Menü, Profil-Vorschau, Vorstellung).
///
/// NUTZERWUNSCH (28.10.2026): "Beim Reiter Profil, soll wenn man auf
/// den Profil Button drückt, das Popup mit Profil bearbeiten, Profil
/// vorschau und Vorstellung vorschau auch unten abgerundet sein".
///
/// Standardmässig ist ein Bottom-Sheet nur OBEN abgerundet - unten
/// stossen die Ecken an den Bildschirmrand. Mit einem Radius an allen
/// vier Ecken schließt das Blatt sichtbar ab.
ShapeBorder profilDialogForm() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));

/// Der kleine Streifen oben in den Profil-Dialogen.
///
/// NUTZERWUNSCH (28.10.2026): "und oben diesen kleinen streifen haben,
/// der zeigt, dass man das Pop up wie gerade auch schon, nach unten weg
/// schieben kann".
///
/// Ein dünner Balken in der Mitte - die übliche Sprache für
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

/// Profil-Anzeige des eigenen Nutzers mit Schnellzugriff auf Bearbeiten
/// und Einstellungen.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Das Bundesland für die Kopfzeile, oder null wenn keines gesetzt ist.
  ///
  /// v0.10.0: Ersetzt den Ort in derselben Zeile. Bewusst eine kleine
  /// Funktion statt zweier Inline-Ausdrücke: die Zeile stand zweimal im
  /// File, und bei zwei Kopien zeigt eine gern das Bundesland und die
  /// andere keines.
  static String? _stateLabel(UserProfile profile) {
    final st = profile.state?.trim();
    if (st == null || st.isEmpty) return null;
    return st;
  }

  /// Hält den Bundesland-Teil der Kopfzeile zusammen - inklusive
  /// führendem Trennzeichen, damit die Zeile nicht mit einem "·" endet,
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

    // NUTZERWUNSCH (30.10.2026): derselbe flächige Geburtstags-Hintergrund
    // wie in der Vorschau - nicht nur der Rahmen ums Bild.
    final isBirthday = UserProfile.isBirthdayToday(profile.birthDate);

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
      body: BirthdayStyleSurface(
        style: profile.birthdayStyle,
        active: isBirthday,
        child: ScrollMoreHint(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: _OwnAvatar()),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    // Versteckter Admin-Zugang: Long-Press auf den Namen
                    // öffnet nur für die konfigurierte Admin-ID den
                    // Admin-Bereich. Normale Nutzer erreichen ihn nicht.
                    onLongPress: isCurrentUserAdmin()
                        ? () => context.go(AppRoutes.admin)
                        : null,
                    child: CenteredNameWithBadges(
                      name: profile.name.isEmpty
                          ? L10n.t(context, 'profile.unknown')
                          : profile.name,
                      style: Theme.of(context).textTheme.headlineSmall,
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
                        // Konto jünger als 7 Tage. Auf dem eigenen Profil
                        // sichtbar, damit man sieht, wie man bei anderen
                        // wirkt - die eigentliche Wirkung ist die Anzeige
                        // auf fremden Profilen.
                        if (profile.isRecentlyCreated)
                          NewAccountBadge(profile: profile),
                      ],
                    ),
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
                        '${L10n.t(context, 'profile.typePrefix')} ${profile.personalityType}',
                      ),
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
                        Text(
                          L10n.t(context, 'profile.aboutMe'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                          Text(
                            L10n.t(context, 'profile.interests'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
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
                // Der Schalter "Persönlichkeit vor Aussehen" ist
                // entfernt (NUTZERWUNSCH 01.11.2026: "soll nicht mehr
                // deaktivierbar sein, da meine App genau das ja
                // ausmacht. Also einfach entfernen.").
                //
                // Das Verhalten ist trotzdem unverändert: der Blind
                // Mode ist jetzt fest AN (app_settings.dart erzwingt
                // das), die Fotos bleiben also bis zum ersten Funke
                // verborgen. Der Unterschied ist nur, dass es keine
                // Schaltfläche mehr gibt, mit der man es abschalten
                // kännte.
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      _showProfileMenu(context, ref, profile, settings),
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
                // der Button das auch - es tut so, als wäre gespendet
                // worden, wäre schlimmer als gar nichts.
                const Center(child: DonateButton()),
                const SizedBox(height: 12),
              ],
            ),
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
        child: Padding(
          // NUTZERWUNSCH (31.10.2026): "Der Strich im Profil und dann
          // ... soll nicht ganz oben sein, sondern noch ein bisschen
          // Platz/Rand nach oben haben." Der Griff klebt nicht mehr an
          // der Oberkante des Blattes.
          padding: const EdgeInsets.only(top: 12),
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
                subtitle: Text(L10n.t(context, 'profile.menu.introPreviewSub')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showIntroPreview(context, ref, profile);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Vorschau der eigenen Vorstellung (Text + Audio) für "Find your Match".
  void _showIntroPreview(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
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
      debugPrint(
        '[PROFILE_SCREEN] profile.age=${profile.age}, birthDate=${profile.birthDate}, myAge=$myAge',
      );
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
    final Future<Uint8List?> avatarFuture =
        (isPhotosVisible && photoRef != null)
        ? ref.read(supabaseStorageServiceProvider).loadAvatarBytes(photoRef)
        : Future<Uint8List?>.value(null);

    // Zustand des Umschalters: normale Vorschau oder Geburtstags-Vorschau.
    //
    // NUTZERWUNSCH (28.10.2026): "Unter Profil Vorschau soll man
    // zwischen der normalen Profil Vorschau und der Profil Vorschau
    // für den Geburtstag wechseln können."
    //
    // Ein ValueNotifier statt eines StatefulBuilder: der Dialog wird bei
    // jeder Änderung neu gebaut, ein StatefulBuilder würde den
    // ganzen Blatt-Baum neu aufbauen - der Notifier hört nur auf die
    // Teile, die sich ändern.
    final geburtstag = ValueNotifier<bool>(false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // NUTZERWUNSCH (22.11.2026): "Die Geburtstagsvorschau ist noch
      // immer komplett falsch, da der Hintergrund nicht der des
      // Geburtstagsthemes ist." Das Blatt bekommt deshalb KEINEN eigenen
      // Hintergrund - der Geburtstagsstil (BirthdayStyleSurface) malt
      // den Theme-Hintergrund in das ganze Blatt hinein.
      backgroundColor: Colors.transparent,
      shape: profilDialogForm(),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => ValueListenableBuilder<bool>(
          valueListenable: geburtstag,
          builder: (context, istGeburtstag, _) => BirthdayStyleSurface(
            style: profile.birthdayStyle,
            active: istGeburtstag,
            // Alle vier Ecken (wie das Blatt) - sonst schauen die
            // unteren Ecken des Theme-Hintergrunds heraus.
            borderRadius: BorderRadius.circular(28),
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  profilGriffleiste(context),
                  // NUTZERWUNSCH (30.10.2026): Die Vorschau ist
                  // zentriert - Bild UND alle Angaben. Der Titel
                  // steht mittig, das Schließen-Icon bleibt oben
                  // rechts (Stack statt Row).
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          L10n.t(context, 'profile.preview.title'),
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'profile.preview.hint'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      // Im Geburtstags-Modus liegt der Text auf dem
                      // Theme-Hintergrund - bei midnight und mono ist
                      // der dunkel, also muss der Text hell sein.
                      color: istGeburtstag
                          ? BirthdayStyle.foregroundFor(
                              profile.birthdayStyle,
                              context,
                            ).withValues(alpha: 0.85)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
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
                  // Die ganze Fläche darüber tönt [BirthdayStyleSurface].
                  //
                  // BEFUND (07.11.2026, Betreiber): "Die Profilvorschau soll
                  // dem entsprechen, was auch andere wirklich sehen
                  // können." Hier stand ein KREIS (112 px) - das echte
                  // Profil zeigt ein abgerundetes Rechteck. Beide benutzen
                  // jetzt denselben Baustein (ProfileAvatarBox), damit die
                  // Vorschau gar nicht abweichen kann.
                  Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: geburtstag,
                      builder: (context, istGeburtstag, _) {
                        return FutureBuilder<Uint8List?>(
                          future: avatarFuture,
                          builder: (context, snap) {
                            final bytes = snap.data;
                            if (!isPhotosVisible) {
                              return Container(
                                width: 118,
                                height: 152,
                                color: Colors.grey.shade300,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.visibility_off,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              );
                            }
                            return ProfileAvatarBox(
                              bytes: bytes,
                              birthdayStyle: profile.birthdayStyle,
                              isBirthday: istGeburtstag,
                              placeholderIcon: Icons.person,
                            );
                          },
                        );
                      },
                    ),
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
                    child: Builder(
                      builder: (context) {
                        final genderName =
                            profile.gender != null && profile.gender!.isNotEmpty
                            ? (Gender.fromValue(profile.gender) != null
                                  ? L10n.t(
                                      context,
                                      Gender.fromValue(
                                        profile.gender,
                                      )!.labelKey,
                                    )
                                  : profile.gender!)
                            : '';
                        return Text(
                          '${profile.name}${profile.age != null ? ', ${profile.age}' : ''}'
                          '${genderName.isNotEmpty ? ' · $genderName' : ''}'
                          '${stateSuffix(profile)}',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                  if (profile.personalityType != null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Chip(
                        label: Text(
                          '${L10n.t(context, 'profile.preview.type')} ${profile.personalityType}',
                        ),
                      ),
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
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              L10n.t(context, 'profile.preview.photoHidden'),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
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
                          Text(
                            L10n.t(context, 'profile.preview.aboutMe'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
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
                            Text(
                              L10n.t(context, 'profile.preview.interests'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
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
        ),
      ),
    );
  }
}

/// Entschlüsselte Bild-Bytes für das EIGENE Profilbild (v0.8.1: Avatare
/// sind AES-256-GCM-verschlüsselt - Download + lokale Entschlüsselung).
final _ownAvatarBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, ref1) async {
      try {
        return await ref
            .read(supabaseStorageServiceProvider)
            .loadAvatarBytes(ref1);
      } catch (_) {
        return null;
      }
    });
