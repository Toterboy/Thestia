import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:thestia/utils/avatar_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// v0.9.3: geocoding und geolocator sind hier nicht mehr noetig.
// Der Standort kommt aus locationVerificationService (Position) und
// describeStateFor (Bundesland) - beide ohne eigene Geokodierung im
// Screen. Vorher stand hier locationFromAddress() fuer die
// Ortseingabe per Freitext.
import 'package:go_router/go_router.dart';

import 'package:thestia/models/gender.dart';
import 'package:thestia/models/habitude_level.dart';
import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/location_check_service.dart';
import 'package:thestia/services/location_verification_service.dart';
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/passkey_auth.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/utils/geo_names.dart';
import 'package:thestia/utils/location_privacy.dart';
import 'package:thestia/widgets/age_range_sliders.dart';
import 'package:thestia/widgets/appearance_selector.dart';
import 'package:thestia/widgets/birthday_style.dart';
import 'package:thestia/widgets/buttons.dart';
import 'package:thestia/widgets/gender_preference_selector.dart';
import 'package:thestia/widgets/habitude_selector.dart';
import 'package:thestia/widgets/intro_editor.dart';
import 'package:thestia/widgets/interview_bubble.dart';
import 'package:thestia/widgets/music_taste_widgets.dart';
import 'package:thestia/widgets/selectable_tile.dart';
import 'package:thestia/widgets/theme_picker.dart';

/// Einmaliger Einstellungen- & Privatsphäre-Screen direkt nach der Anmeldung.
/// Danach sind diese Einstellungen jederzeit in den normalen Einstellungen änderbar.
class SettingsPrivacyOnceScreen extends ConsumerStatefulWidget {
  const SettingsPrivacyOnceScreen({super.key});

  @override
  ConsumerState<SettingsPrivacyOnceScreen> createState() =>
      _SettingsPrivacyOnceScreenState();
}

class _SettingsPrivacyOnceScreenState
    extends ConsumerState<SettingsPrivacyOnceScreen> {
  final _pageController = PageController();

  int _currentPage = 0;
  bool _isDetectingLocation = false;
  String? _locationError;

  // v0.9.3: Entfernt wurden der Orts-Textfeld-Controller (_locationCtrl),
  // der Bundesland-Freitext-Controller (_stateCtrl) und der ganze
  // Debounce-Pfad (_locationDebounce, _locationSeq, _locateTypedPlace,
  // _locationValidationError).
  //
  // Der Debounce existierte nur, weil der Nutzer einen Ort FREI tippen
  // konnte und der Plattform-Geocoder bei jedem Tastenanschlag lief.
  // Ohne Eingabefeld gibt es nichts zu entprellen: die Standortangabe
  // kommt jetzt aus der GPS-Position und liefert nur das Bundesland.
  //
  // Der Freitext fuer den Bundesland-Filter ist einem Dropdown gewichen
  // - damit kann kein Tippfehler mehr die Filterung stillschweigend
  // aufheben ("bayrn" traf nie auf "Bayern").

  // v0.9.3: 10 Seiten statt 8. Neu sind der Geburtstags-Stil (mit
  // GROSSER Vorschau) und der Musik-Geschmack - beide wurden bei einer
  // Registrierung nie abgefragt. Dazu kommen die drei Fortschrittsschritte
  // von unten.
  static const int _pageCount = 10;
  static const int _profilePage = 1;
  static const int _introPage = 2;
  static const int _birthdayPage = 3;
  static const int _musicPage = 4;
  static const int _habitudesPage = 5;

  /// Geburtstags-Stil (v0.9.3, eigene Seite in der Einrichtung).
  ///
  /// Frueher nur beim App-Update nachfragbar (whats_new_screen.dart) und
  /// im Profil-Edit. In der Einrichtung stand er nie - wer sich frisch
  /// registriert hat, hatte den Default, ohne es gewaehlt zu haben.
  String _birthdayStyle = BirthdayStyle.values.first;

  /// Musik-Geschmack (v0.9.3).
  ///
  /// [musicLiked]/[musicDisliked] enthalten SLUGS (z. B. `hip_hop`), nicht
  /// die deutschen Labels. Der alte Onboarding-Screen schrieb hier
  /// Labels in `profiles.music_liked`, die das Matching nicht erkannte -
  /// siehe [kMusicGenres].
  Set<String> _musicLiked = {};
  Set<String> _musicDisliked = {};
  final _songCtrl = TextEditingController();
  final _bandCtrl = TextEditingController();

  // Schritt "Deine Vorstellung" (überspringbar): Werte des IntroEditor.
  String _introText = '';
  String? _introAudioPath;

  // Schritt "Profil & Interessen": Bio, Bundesland, Interessen, Avatar.
  final _bioCtrl = TextEditingController();
  String? _selectedState;
  Set<String> _selectedInterests = {};
  bool _uploadingAvatar = false;
  Uint8List? _avatarBytes;

  // Schritt "Passkey" (überspringbar).
  bool _passkeyBusy = false;
  bool _passkeyCreated = false;

  // Schritt "Gewohnheiten" (Rauchen, Alkohol, Drogen).
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;
  bool _habitsDealbreaker = false;

  @override
  void initState() {
    super.initState();
    // v0.9.3: Kein Vorbelegen von Textfeldern mehr - die beiden
    // Controller (_locationCtrl, _stateCtrl) sind mit dem Orts-Feld
    // entfallen. Der Bundesland-Filter liest jetzt direkt aus
    // userPreferences.preferredState (siehe das Dropdown auf Seite 1).
    // Vorhandene Konsum-Präferenzen vorbelegen, falls bereits gesetzt.
    final profile = ref.read(profileProvider);
    _smoking = profile.smoking;
    _alcohol = profile.alcohol;
    _drugs = profile.drugs;
    _habitsDealbreaker = ref.read(settingsProvider).habitsDealbreaker;
    // Profil-Seite vorbelegen (falls bereits Daten vorhanden sind).
    _bioCtrl.text = profile.bio;
    _selectedState = profile.state;
    _selectedInterests = {...profile.interests};
    // Vorbelegen: sonst zeigt die Stilauswahl immer classic, auch wenn
    // jemand bereits einen anderen gesetzt hat (z. B. beim Update).
    _birthdayStyle = BirthdayStyle.orDefault(profile.birthdayStyle);
    // Musik ebenfalls vorbelegen (Slug-Form, siehe _musicLiked).
    _musicLiked = {...profile.musicLiked};
    _musicDisliked = {...profile.musicDisliked};
    _songCtrl.text = profile.favoriteSong ?? '';
    _bandCtrl.text = profile.favoriteBand ?? '';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bioCtrl.dispose();
    _songCtrl.dispose();
    _bandCtrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final leave =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t(ctx, 'setup.abortTitle')),
            content: Text(L10n.t(ctx, 'setup.abortBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'setup.abortContinue')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
            ],
          ),
        ) ??
        false;
    return leave;
  }

  void _prevPage() {
    if (_currentPage == _musicPage) {
      unawaited(_saveMusicTaste());
    }
    if (_currentPage == _birthdayPage) {
      unawaited(_saveBirthdayStyle());
    }
    if (_currentPage == _habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    // Pflicht-Schritte (3 Profil, 4 Vorstellung): Grundangaben muessen
    // erledigt sein, bevor weitergeblaettert werden kann. Schritt 2
    // (Filter) hat sinnvolle Defaults und ist damit immer gueltig.
    if (_currentPage == _profilePage) {
      if (_bioCtrl.text.trim().isEmpty) {
        _showStepHint(L10n.t(context, 'setup.hintBio'));
        return;
      }
      if (_selectedInterests.isEmpty) {
        _showStepHint(L10n.t(context, 'setup.hintInterests'));
        return;
      }
      unawaited(_saveProfileExtras());
    }
    if (_currentPage == _introPage) {
      if (!IntroEditor.isValid(text: _introText, audioPath: _introAudioPath)) {
        _showStepHint(L10n.t(context, 'setup.hintIntro'));
        return;
      }
      _saveIntro();
    }
    if (_currentPage == _birthdayPage) {
      unawaited(_saveBirthdayStyle());
    }
    if (_currentPage == _musicPage) {
      unawaited(_saveMusicTaste());
    }
    if (_currentPage == _habitudesPage) {
      unawaited(_saveHabitudes());
    }
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showStepHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Speichert Text + Audio der Vorstellung (best effort, optionaler
  /// Schritt). Identische Mechanik wie im Find-your Match-Screen.
  Future<void> _saveIntro() async {
    final text = _introText.trim();
    if (text.isEmpty && _introAudioPath == null) return;
    try {
      await ref
          .read(profileProvider.notifier)
          .update(
            introText: text,
            introAudioPath: _introAudioPath,
            clearIntroAudio: _introAudioPath == null,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'intro_text': text,
          'intro_audio_path': _introAudioPath,
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Intro-Speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert die Konsum-Präferenzen (Rauchen, Alkohol, Drogen) lokal
  /// und best-effort serverseitig. Beeinflusst den Find-your-Match-Filter.
  Future<void> _saveHabitudes() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(smoking: _smoking, alcohol: _alcohol, drugs: _drugs);
      await ref
          .read(settingsProvider.notifier)
          .setHabitsDealbreaker(_habitsDealbreaker);
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'smoking': _smoking?.toServer(),
          'alcohol': _alcohol?.toServer(),
          'drugs': _drugs?.toServer(),
          'habits_dealbreaker': _habitsDealbreaker,
        });
      }
    } catch (e) {
      debugPrint(
        '[SettingsPrivacyOnce] Habituden-Speichern fehlgeschlagen: $e',
      );
    }
  }

  /// Speichert den Geburtstags-Stil (v0.9.3). Eigene Seite, deshalb
  /// eigener Save - sonst muesste die Style-Seite in [_saveProfileExtras]
  /// aufgewaecht werden, obwohl sie an einem anderen Ort steht.
  Future<void> _saveBirthdayStyle() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(birthdayStyle: _birthdayStyle);
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(
          SupabaseService.client,
        ).updateOwnProfile({'birthday_style': _birthdayStyle});
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Geburtstags-Stil speichern '
          'fehlgeschlagen: $e');
    }
  }

  /// Speichert den Musik-Geschmack (v0.9.3).
  ///
  /// Gespeichert werden SLUGS. Der alte Onboarding-Screen hat hier
  /// deutsche Labels ("Hip-Hop") geschrieben; das Matching vergleicht
  /// aber Slugs (`hip_hop`) - die Angabe war damit wirkungslos.
  ///
  /// Leeres Lieblingssong/-band wird als leerer String gespeichert, weil
  /// die Spalten `NOT NULL DEFAULT ''` sind (Migration 092/119).
  Future<void> _saveMusicTaste() async {
    try {
      final song = _songCtrl.text.trim();
      final band = _bandCtrl.text.trim();
      await ref
          .read(profileProvider.notifier)
          .update(
            musicLiked: _musicLiked.toList(),
            musicDisliked: _musicDisliked.toList(),
            favoriteSong: song,
            favoriteBand: band,
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(
          SupabaseService.client,
        ).updateOwnProfile({
          'music_liked': _musicLiked.toList(),
          'music_disliked': _musicDisliked.toList(),
          'favorite_song': song,
          'favorite_band': band,
        });
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Musik speichern fehlgeschlagen: $e');
    }
  }

  /// Speichert Bio, Bundesland und Interessen der Profil-Seite lokal UND
  /// serverseitig (gleiche Felder wie "Profil bearbeiten").
  Future<void> _saveProfileExtras() async {
    try {
      await ref
          .read(profileProvider.notifier)
          .update(
            bio: _bioCtrl.text.trim(),
            stateStr: _selectedState,
            interests: _selectedInterests.toList(),
          );
      if (SupabaseService.isInitialized) {
        await SupabaseDatabaseService(SupabaseService.client).updateOwnProfile({
          'bio': _bioCtrl.text.trim(),
          'state': _selectedState,
          'interests': _selectedInterests.toList(),
        });
      }
    } catch (e) {
      debugPrint(
        '[SettingsPrivacyOnce] Profil-Extras speichern '
        'fehlgeschlagen: $e',
      );
    }
  }

  /// Profilbild auswaehlen, quadratisch zuschneiden und in den privaten
  /// avatars-Bucket laden (identisch zu "Profil bearbeiten").
  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await pickAndCropAvatar(context);
      if (bytes == null) return;

      // Lokale Vorschau sofort zeigen.
      if (mounted) setState(() => _avatarBytes = bytes);
      final storage = ref.read(supabaseStorageServiceProvider);
      final path = await storage.uploadAvatar(bytes);
      await ref.read(profileProvider.notifier).update(photos: [path]);

      // v0.9.3: Serverseitiger Write fehlte hier vollstaendig. Das Bild
      // lag in Storage und lokal - aber `profiles.photos` wurde nie
      // gesetzt. Beim naechsten fetchOwnProfile stand dort wieder der
      // alte Stand, das Bild verschwand. Von aussen sah es damit aus,
      // als frage die Einrichtung gar kein Profilbild ab.
      if (SupabaseService.isInitialized) {
        await ref
            .read(supabaseDatabaseServiceProvider)
            .updateOwnProfile({'photos': [path]});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'setupp.photoDone'))),
        );
      }
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Avatar-Upload fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'setupp.photoFail'))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// Richtet einen Passkey ein (überspringbarer Schritt). Fehler werden
  /// angezeigt, blockieren aber nicht – "Weiter" geht immer.
  Future<void> _setupPasskey() async {
    if (_passkeyBusy || _passkeyCreated) return;
    setState(() => _passkeyBusy = true);
    try {
      await PasskeyAuth.register();
      if (!mounted) return;
      setState(() => _passkeyCreated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'setup.passkeyDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Passkey-Setup fehlgeschlagen: $e');
      // Nur die bereinigte Meldung zeigen - keine Plugin-/WebAuthn-Interna.
      final msg = e is AppException
          ? L10n.exc(context, e)
          : L10n.t(context, 'setup.passkeySetupFailed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _passkeyBusy = false);
    }
  }

  void _acceptAndFinish() async {
    // Zuerst Community-Richtlinien akzeptieren, dann Setup abschließen –
    // mit dringender Sicherheitsempfehlung (Passkey/2FA), falls fehlend.
    await ref.read(settingsProvider.notifier).acceptCommunityGuidelines();
    await _finishWithSecurityNudge();
  }

  Future<void> _finish() async {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final accepted = ref.read(settingsProvider).communityGuidelinesAccepted;
    if (!accepted) {
      await settingsNotifier.acceptCommunityGuidelines();
    }
    final prefsNotifier = ref.read(userPreferencesProvider.notifier);
    // v0.9.3: Der Stadt-Sync ist entfallen. Der Ortsname war das
    // eigentlich sensible Datum - oeffentlich lesbar fuer jeden
    // angemeldeten Nutzer (Migration 135). Das Bundesland wird ueber
    // _saveProfileExtras geschrieben, die Koordinaten ueber
    // _detectLocation.
    await _saveHabitudes();
    await _saveBirthdayStyle();
    await _saveMusicTaste();
    await settingsNotifier.completeOneTimeSettings();
    // UI-Einstellungen (Blind Mode, Sichtbarkeit, Dark Mode, ...) einmalig
    // serverseitig spiegeln (v0.8.0, ui_prefs) - best effort.
    scheduleUiPrefsServerSync(ref.read(settingsProvider));
    // Setup-Stand serverseitig sichern, damit die Einrichtung nach
    // Neuinstallation/neuem Login nicht erneut erscheint. Fehlschlag wird
    // ANGEZEIGT (bisher: stiller debugPrint, weshalb die Einrichtung
    // bei der nächsten Anmeldung wieder kam, obwohl sie "fertig" war).
    final flagsSaved = await _persistSetupFlagsToServer();
    // Präferenzen (Entfernung, "Ich suche", Bundesland, Altersspanne)
    // zusätzlich serverseitig sichern ("Nichts geht verloren"-Garantie,
    // Migration 066). Kein city mehr - die Spalte wird in Migration 136
    // entfernt.
    if (SupabaseService.isInitialized) {
      try {
        final s = ref.read(settingsProvider);
        final profileState = ref.read(profileProvider).state;
        await prefsNotifier.savePreferencesToServer(
          ageRangeMin: s.ageRangeMin,
          ageRangeMax: s.ageRangeMax,
          stateStr: profileState,
        );
      } catch (_) {
        // Best-Effort: Blockiert den Abschluss nicht.
      }
    }
    if (mounted && !flagsSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'setup.flagsWarn')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (mounted) context.go(AppRoutes.home);
  }

  /// Dringende Empfehlung: Wenn weder Passkey noch 2FA eingerichtet sind,
  /// vor dem Abschluss ein deutlicher Hinweis mit Direkt-Sprüngen.
  Future<void> _finishWithSecurityNudge() async {
    final mfaActive =
        ref.read(mfaStatusProvider).hasVerifiedFactors ||
        ref.read(mfaStatusProvider).hasAnyFactor;
    if (_passkeyCreated || mfaActive) {
      await _finish();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.shield_outlined,
          color: Theme.of(ctx).colorScheme.primary,
          size: 40,
        ),
        title: Text(L10n.t(ctx, 'setup.nudgeTitle')),
        content: Text(L10n.t(ctx, 'setup.nudgeBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(L10n.t(ctx, 'setup.nudgeSkip')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('mfa'),
            child: Text(L10n.t(ctx, 'setup.nudgeMfa')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('passkey'),
            child: Text(L10n.t(ctx, 'setup.nudgePasskey')),
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (choice) {
      case 'passkey':
        // v0.9.3: Zwei neue Seiten (Geburtstag, Musik) sitzen vor
        // Passkey/MFA, deshalb sind die Zielseiten um zwei gewandert.
        _pageController.jumpToPage(7); // Passkey-Seite
      case 'mfa':
        _pageController.jumpToPage(8); // 2FA-Seite
      default:
        await _finish();
    }
  }

  /// Schreibt die Setup-Flags in die profiles-Tabelle und verifiziert das
  /// Ergebnis per Zurücklesen (stille 0-Zeilen-Updates und transiente
  /// Netzfehler werden dadurch erkennbar und retries).
  /// Rückgabe: true bei Erfolg (false = fehlgeschlagen, Aufrufer zeigt
  /// einen Hinweis).
  Future<bool> _persistSetupFlagsToServer() async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final settings = ref.read(settingsProvider);
      // WICHTIG: onboarding_done wird hier bewusst NICHT mitgeschickt -
      // es ist in diesem Moment noch false (der Persönlichkeitstest als
      // letzter Schritt setzt es) und würde sonst einen etwaigen
      // serverseitigen true-Stand (Backfill, Migration 065) überschreiben.
      return await SupabaseDatabaseService(
        SupabaseService.client,
      ).updateSetupFlagsAndVerify({
        'one_time_settings_completed': settings.oneTimeSettingsCompleted,
        'community_guidelines_accepted': settings.communityGuidelinesAccepted,
      });
    } catch (e) {
      debugPrint('[SettingsPrivacyOnce] Server-Flags fehlgeschlagen: $e');
      return false;
    }
  }

  Future<void> _detectLocation() async {
    // Doppelaufruf verhindern: setState wirkt erst naechsten Frame,
    // daher ist _isDetectingLocation hier noch false.
    if (_isDetectingLocation) return;
    setState(() {
      _isDetectingLocation = true;
      _locationError = null;
    });

    try {
      final locationService = ref.read(locationVerificationServiceProvider);
      final position = await locationService.getCurrentLocation();
      if (!mounted) return;

      if (position == null) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'setup.locationDetectFail');
        });
        return;
      }

      // Plausibilitaets-Check gegen die BISHERIGEN Standorte dieses
      // Geraets (lokal). Ein serverseitiger Abgleich mit fremden Accounts
      // existiert bewusst nicht - der Server prueft separat eigene
      // Positions-Spruenge (>15 km / >300 km/h) via process-location-check.
      // isLocationSuspicious liest den Secure Storage (async) - in dieser
      // Zeit kann der Screen verlassen worden sein.
      final suspicious = await locationService.isLocationSuspicious(position);
      if (!mounted) return;
      if (suspicious) {
        setState(() {
          _isDetectingLocation = false;
          _locationError = L10n.t(context, 'setup.locationSuspicious');
        });
        return;
      }

      // v0.9.3: Nur noch das Bundesland als Anzeige. Frueher stand hier
      // der ORTSNAME (via der Geocoder-Hilfe in geo_names.dart) und wurde
      // nach profiles.city geschrieben - damit war der Aufenthaltsort
      // bis auf ~11 km genau oeffentlich, auch direkt per PostgREST
      // (Migration 135).
      //
      // Die Koordinaten werden auf 5-km-Raster gerundet, BEVOR sie
      // gespeichert werden. Der Server rundet ebenfalls; identisch zu
      // sein ist wichtig, sonst springt die Entfernungsanzeige.
      final snapped = LocationPrivacy.snapToGrid(
        position.latitude,
        position.longitude,
      );
      // Bundesland fuer die Anzeige. Ohne Treffer wird NICHT geraten -
      // der Nutzer waehlt es dann von Hand aus der Liste.
      final detectedState = await describeStateFor(snapped.lat, snapped.lng);
      if (!mounted) return;

      // Koordinaten lokal UND serverseitig persistieren - sonst koennen
      // Entfernungen zu anderen Nutzern nicht berechnet werden.
      await ref
          .read(profileProvider.notifier)
          .update(
            stateStr: detectedState,
            locationLat: snapped.lat,
            locationLng: snapped.lng,
          );
      if (SupabaseService.isInitialized) {
        try {
          final userId = SupabaseService.client.auth.currentUser?.id;
          if (userId != null) {
            unawaited(
              ref
                  .read(locationCheckServiceProvider)
                  .processLocationCheck(
                    userId: userId,
                    newLatitude: snapped.lat,
                    newLongitude: snapped.lng,
                  ),
            );
            // Bundesland serverseitig sichern, damit ein späterer
            // Profil-Sync (fetchOwnProfile) den Wert nicht mit leer
            // überschreibt. Kein city: den gibt es nicht mehr.
            unawaited(
              ref.read(supabaseDatabaseServiceProvider).updateOwnProfile({
                'state': detectedState,
              }),
            );
          }
        } catch (_) {
          // Best-Effort: Standort-Sync darf den Flow nicht blockieren.
        }
      }

setState(() {
        _isDetectingLocation = false;
        _locationError = null;
        // Das erkannte Bundesland in die Auswahl uebernehmen, damit der
        // Nutzer es bestaetigen oder korrigieren kann. Ohne Treffer
        // bleibt die bisherige Wahl stehen.
        if (detectedState != null) _selectedState = detectedState;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detectedState == null
                  ? L10n.t(context, 'setup.locationStateUnknown')
                  : L10n.t(context, 'setup.locationDone'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDetectingLocation = false;
        _locationError = L10n.tf(context, 'setup.locationError', {
          'error': e.toString(),
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final userPrefs = ref.watch(userPreferencesProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final userPrefsNotifier = ref.read(userPreferencesProvider.notifier);
    final profile = ref.watch(profileProvider);

    // Altersbasierte Sicherheits-Regeln.
    // WICHTIG: Solange das Profil (Geburtsdatum) noch nicht geladen ist,
    // wird NICHT als Minderjähriger geklemmt (Fallback 18 = Erwachsen).
    // Vorher führte der Fallback 16 dazu, dass die Altersspanne dauerhaft
    // auf 16-19 gespeichert wurde ("Alter falsch gemerkt").
    final userAge = profile.age;
    final effectiveAge = userAge ?? 18;
    final allowedAgeMin = AgeSafetyRules.minFilterAge(effectiveAge);
    final allowedAgeMax = AgeSafetyRules.maxFilterAge(effectiveAge);
    final clampedAgeMin = settings.ageRangeMin.clamp(
      allowedAgeMin,
      allowedAgeMax,
    );
    final clampedAgeMax = settings.ageRangeMax.clamp(
      clampedAgeMin,
      allowedAgeMax,
    );

    // Falls Werte außerhalb erlaubtem Bereich: asynchron korrigieren –
    // aber NUR, wenn das Alter tatsächlich bekannt ist.
    if (userAge != null &&
        (settings.ageRangeMin != clampedAgeMin ||
            settings.ageRangeMax != clampedAgeMax)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setAgeRange(clampedAgeMin, clampedAgeMax);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final leave = await _onWillPop();
        if (leave && mounted) router.go(AppRoutes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(L10n.t(context, 'setup.appbarTitle')),
          leading: _currentPage > 0
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: L10n.t(context, 'common.back'),
                  onPressed: _prevPage,
                )
              : null,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fortschrittsanzeige (Schritt X von Y).
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          L10n.tf(context, 'setup.stepOf', {
                            'n': '${_currentPage + 1}',
                            'of': '$_pageCount',
                          }),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const Spacer(),
                        Text(
                          '${(_pageCount == 0 ? 0 : ((_currentPage + 1) / _pageCount * 100).round())}%',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_currentPage + 1) / _pageCount,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  // Nutzerwunsch: Swipen DEAKTIVIERT. Die Buttons führen die
                  // pro Schritt erforderlichen Aktionen (Validierung, Speichern)
                  // aus - Wer swipe-te, übersprang sie, wodurch Angaben nicht ins
                  // Profil übernommen wurden.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    // Page 1: Filter & Präferenzen
                    _Page(
                      questionKey: 'setupq.filter',
                      subtitle: L10n.t(context, 'setup.filterSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t(context, 'setupp.lookingFor'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          // Mehrfachauswahl per Chips (inkl. "Alle"-Kurzform).
                          // Ein einzelnes Geschlecht kann nicht abgewählt
                          // werden, solange es das letzte aktive ist.
                           const GenderPreferenceSelector(),
                           const SizedBox(height: 20),
                           // Kein Doppel-Titel: Die Frage steht bereits in
                           // der Bubble oben (setupq.filter).
                           DropdownButtonFormField<RelationshipType>(
                            initialValue: userPrefs.relationshipType,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.relType'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: RelationshipType.casual,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.casual'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.dating,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.dating'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.relationship,
                                child: Text(
                                  L10n.t(
                                    context,
                                    'profile.edit.rel.relationship',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.friends,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.friends'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: RelationshipType.open,
                                child: Text(
                                  L10n.t(context, 'profile.edit.rel.open'),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                userPrefsNotifier.setRelationshipType(v);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Text(
                            L10n.t(context, 'setupp.distance'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<DistanceFilterMode>(
                            initialValue: userPrefs.distanceFilterMode,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.filterLabel'),
                            ),
                            items: DistanceFilterMode.values.map((mode) {
                              return DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                userPrefsNotifier.setDistanceFilterMode(v);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.distanceKm) ...[
                            Text(
                              // Gleiche Quelle wie "Profil bearbeiten"
                              // (userPreferences), damit beide Screens
                              // immer denselben Wert zeigen.
                              L10n.tf(context, 'setupp.maxDistance', {
                                'km': '${userPrefs.maxDistanceKm}',
                              }),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Slider(
                              value: userPrefs.maxDistanceKm.toDouble(),
                              min: 1,
                              max: AppConstants.maxDistanceKm.toDouble(),
                              divisions: AppConstants.maxDistanceKm - 1,
                              label: '${userPrefs.maxDistanceKm} km',
                              onChanged: (v) =>
                                  userPrefsNotifier.setMaxDistanceKm(v.round()),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.state) ...[
                            const SizedBox(height: 20),
                            // v0.9.3: Auswahl statt Freitext.
                            //
                            // Vorher stand hier ein Textfeld. Damit konnte
                            // jeder beliebige String gespeichert werden -
                            // "Bayern", "bayrn", "Bayern " oder "Irgendwas".
                            // Der Filter vergleicht danach exakt, also
                            // funktionierte die Entfernungsfilterung dann
                            // einfach nicht, ohne dass man es merkte.
                            //
                            // Eine Liste aus kGermanStates kann keinen
                            // Tippfehler produzieren. Und sie ist neben der
                            // Dropdown-Auswahl auf der Profilseite derselbe
                            // Katalog - vorher standen hier Vollnamen
                            // ("Bayern") und im Profil-Edit Kuerzel ("BY"),
                            // was die Filterung ebenfalls aushebte.
                            DropdownButtonFormField<String>(
                              initialValue:
                                  userPrefs.preferredState?.trim().isEmpty ??
                                      true
                                  ? null
                                  : userPrefs.preferredState!.trim(),
                              borderRadius: BorderRadius.circular(16),
                              decoration: InputDecoration(
                                labelText: L10n.t(
                                  context,
                                  'setupp.stateLabel',
                                ),
                              ),
                              hint: Text(L10n.t(context, 'setup.pleasePick')),
                              items: kGermanStates
                                  .map(
                                    (st) => DropdownMenuItem(
                                      value: st,
                                      child: Text(st),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) async {
                                // Kein Fehlerhinweis mehr noetig: eine
                                // Liste kann nicht falsch getippt werden.
                                await userPrefsNotifier
                                    .setPreferredState(v);
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (userPrefs.distanceFilterMode ==
                              DistanceFilterMode.germany) ...[
                            const SizedBox(height: 20),
                            Text(
                              L10n.t(context, 'setupp.germanyNote'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                          ],
                          // v0.9.3: Standort. Kein Ort-Textfeld mehr.
                          //
                          // Vorher stand hier ein Freitextfeld fuer die
                          // Stadt, mit 600-ms-Debounce, Geokodierung und
                          // 15-km-Abgleich zur GPS-Position. Das ergab einen
                          // Ort mit ~11 km Genauigkeit - oeffentlich, weil
                          // profiles.city fuer jeden angemeldeten Nutzer
                          // lesbar war (Migration 135).
                          //
                          // Jetzt gibt es nur noch die GPS-Erkennung, und
                          // die liefert ausschliesslich das Bundesland. Das
                          // Bundesland steht bereits auf der naechsten Seite
                          // (Profil) zur Auswahl - doppelt fragen waere
                          // nur eine weitere Pflichtangabe.
                          OutlinedButton.icon(
                            onPressed: _isDetectingLocation
                                ? null
                                : _detectLocation,
                            icon: _isDetectingLocation
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                            label: Text(
                              L10n.t(context, 'setupp.detectState'),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                          if (_locationError != null) ...[
                            const SizedBox(height: 8),
                            _LocationNotice(text: _locationError!),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Bevorzugte Altersspanne: '
                            '$clampedAgeMin bis $clampedAgeMax Jahre',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          // Zwei gekoppelte Slider statt RangeSlider:
                          // Bei identischen Werten (z. B. 18-18) friert
                          // ein RangeSlider ein (End-Regler nicht greif-
                          // bar). Die Grenzen sind die STATISCHEN
                          // Sicherheitsgrenzen - nicht die Auswahl selbst.
                          AgeRangeSliders(
                            minValue: clampedAgeMin,
                            maxValue: clampedAgeMax,
                            boundsMin: allowedAgeMin,
                            boundsMax: allowedAgeMax,
                            minLabelPrefix: L10n.t(
                              context,
                              'profile.edit.minAgeLabel',
                            ),
                            maxLabelPrefix: L10n.t(
                              context,
                              'profile.edit.maxAgeLabel',
                            ),
                            labelSuffix: L10n.t(context, 'common.years'),
                            onChanged: (min, max) {
                              notifier.setAgeRange(min, max);
                              // Entprellter Server-Sync (Regler feuern
                              // kontinuierlich) - siehe Profile-Editor.
                              ref
                                  .read(userPreferencesProvider.notifier)
                                  .queueServerSync(
                                    ageRangeMin: min,
                                    ageRangeMax: max,
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                    // Page 2: Profil & Interessen (Bio, Bundesland, Bild)
                    _Page(
                      questionKey: 'setupq.profile',
                      subtitle: L10n.t(context, 'setupp.profileSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---- Profilbild ----
                          Center(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 44,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      backgroundImage: _avatarBytes != null
                                          ? MemoryImage(_avatarBytes!)
                                          : null,
                                      child: _avatarBytes == null
                                          ? const Icon(Icons.person, size: 44)
                                          : null,
                                    ),
                                    SizedBox(
                                      height: 32,
                                      width: 32,
                                      child: IconButton.filledTonal(
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        onPressed: _uploadingAvatar
                                            ? null
                                            : _pickAvatar,
                                        icon: _uploadingAvatar
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.add_a_photo),
                                        tooltip: L10n.t(
                                          context,
                                          'setup.photoTooltip',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ---- Bio ----
                          TextFormField(
                            controller: _bioCtrl,
                            maxLines: 3,
                            maxLength: 300,
                            decoration: InputDecoration(
                              labelText: L10n.t(context, 'setupp.bioLabel'),
                              hintText: L10n.t(context, 'setupp.bioHint'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // ---- Bundesland ----
                          DropdownButtonFormField<String>(
                            initialValue:
                                (_selectedState == null ||
                                    _selectedState!.isEmpty)
                                ? null
                                : _selectedState,
                            borderRadius: BorderRadius.circular(16),
                            decoration: InputDecoration(
                              labelText: L10n.t(
                                context,
                                'setupp.stateOptional',
                              ),
                            ),
                            hint: Text(L10n.t(context, 'setup.pleasePick')),
                            items: kGermanStates
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedState = v),
                          ),
                          const SizedBox(height: 20),
                          // ---- Interessen (ohne Doppel-Titel: Frage steht
                          // in der Bubble oben) ----
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppConstants.presetInterests.map((i) {
                              final selected = _selectedInterests.contains(i);
                              return FilterChip(
                                label: Text(i),
                                selected: selected,
                                onSelected: (on) => setState(() {
                                  on
                                      ? _selectedInterests.add(i)
                                      : _selectedInterests.remove(i);
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    // Page 3: Deine Vorstellung (Text + Audio, überspringbar)
                    _Page(
                      questionKey: 'setupq.intro',
                      subtitle: L10n.t(context, 'setupp.introSub'),
                      child: IntroEditor(
                        initialText: _introText,
                        initialAudioPath: _introAudioPath,
                        required: true,
                        onChanged: (text, audioPath) {
                          setState(() {
                            _introText = text;
                            _introAudioPath = audioPath;
                          });
                        },
                      ),
                    ),
                    // Page 4 (v0.9.3): Geburtstags-Stil mit GROSSER Vorschau.
                    // Eigene Seite, weil die 128-px-Kacheln aus dem
                    // Wrap als "nur ein kleines Bild" gemeldet wurden -
                    // und der Stil eine Entscheidung ist, keine
                    // Nebenheit.
                    _Page(
                      questionKey: 'setupq.birthday',
                      subtitle: L10n.t(context, 'setup.birthdaySub'),
                      child: SingleChildScrollView(
                        child: BirthdayStylePicker(
                          selected: _birthdayStyle,
                          large: true,
                          // Kein echtes Profilbild in der Vorschau:
                          // das Bild liegt verschluesselt als
                          // "pfad|key|iv" im Storage und laesst sich ohne
                          // Signier-URL hier nicht laden. Die Vorschau
                          // zeigt deshalb das Person-Symbol. Die Ausgabe
                          // "nur ein kleines Bild" bezog sich auf die
                          // Groesse der Kachel, nicht aufs Motiv.
                          avatarPath: null,
                          onSelected: (v) => setState(() {
                            _birthdayStyle = v;
                          }),
                        ),
                      ),
                    ),
                    // Page 5 (v0.9.3): Musik-Geschmack. War im toten
                    // onboarding_screen und wurde dort mit deutschen
                    // Labels statt Slugs gespeichert, sodass das
                    // Matching nichts dazu fand.
                    _Page(
                      questionKey: 'setupq.music',
                      subtitle: L10n.t(context, 'setup.musicSub'),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MusicTasteEditor(
                              liked: _musicLiked.toList(),
                              disliked: _musicDisliked.toList(),
                              onChanged: (liked, disliked) {
                                setState(() {
                                  _musicLiked = liked.toSet();
                                  _musicDisliked = disliked.toSet();
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _songCtrl,
                              maxLength: 120,
                              scrollPadding:
                                  const EdgeInsets.only(bottom: 180),
                              decoration: InputDecoration(
                                labelText: L10n.t(
                                  context,
                                  'profile.edit.favoriteSong',
                                ),
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bandCtrl,
                              maxLength: 120,
                              scrollPadding:
                                  const EdgeInsets.only(bottom: 180),
                              decoration: InputDecoration(
                                labelText: L10n.t(
                                  context,
                                  'profile.edit.favoriteBand',
                                ),
                                counterText: '',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Page 6: Gewohnheiten (Rauchen, Alkohol, Drogen)
                    _Page(
                      questionKey: 'setupq.habits',
                      subtitle: L10n.t(context, 'setupp.habitsSub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            L10n.t(context, 'setupp.habitsHint'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Dealbreaker (wie in "Profil bearbeiten"): harter
                          // Filter - Kandidaten mit höherem Konsum werden
                          // serverseitig ausgeschlossen.
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(L10n.t(context,
                                'profile.edit.habitsDealbreaker')),
                            subtitle: Text(L10n.t(context,
                                'profile.edit.habitsDealbreakerSub')),
                            value: _habitsDealbreaker,
                            onChanged: (v) =>
                                setState(() => _habitsDealbreaker = v),
                          ),
                          const SizedBox(height: 8),
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
                        ],
                      ),
                    ),
                    // Page 5: Privatsphäre & Theme
                    _Page(
                      questionKey: 'setupq.visibility',
                      subtitle: L10n.t(context, 'setupp.visibilitySub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Kein Doppel-Titel: Die Frage steht bereits in
                          // der Bubble oben (setupq.visibility).
                          for (final v in ProfileVisibility.values)
                            SelectableTile<ProfileVisibility>(
                              value: v,
                              groupValue: settings.profileVisibility,
                              title: L10n.t(context, v.labelKey),
                              onChanged: (val) {
                                if (val != null) {
                                  notifier.setProfileVisibility(val);
                                }
                              },
                            ),
                          const Divider(),
                          Text(
                            L10n.t(context, 'setupp.appearance'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          // v0.9.2: dieselbe Auswahl wie in den
                          // Einstellungen, damit beide Stellen nicht
                          // unterschiedlich aussehen. String-Keys statt
                          // bool? bleibt: Radio mit null-Value
                          // verschluckt Taps. Mapping: 'system' -> null,
                          // 'light' -> false, 'dark' -> true.
                          AppearanceSelector(
                            value: settings.useDarkMode == null
                                ? 'system'
                                : (settings.useDarkMode! ? 'dark' : 'light'),
                            onChanged: (mode) {
                              switch (mode) {
                                case 'light':
                                  notifier.setDarkMode(false);
                                case 'dark':
                                  notifier.setDarkMode(true);
                                default:
                                  notifier.setDarkMode(null);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            L10n.t(context, 'setupp.colorWorld'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ThemePicker(
                            selectedName: settings.themeName,
                            onChanged: (t) => notifier.setThemeName(t.name),
                          ),
                        ],
                      ),
                    ),
                    // Page 6: Passkey (überspringbar)
                    _Page(
                      questionKey: 'setupq.passkey',
                      subtitle: L10n.t(context, 'setupp.passkeySub'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.key, size: 48),
                          const SizedBox(height: 16),
                          Text(L10n.t(context, 'setupp.passkeyBody')),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _passkeyBusy || _passkeyCreated
                                ? null
                                : _setupPasskey,
                            icon: _passkeyBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _passkeyCreated
                                        ? Icons.check_circle
                                        : Icons.fingerprint,
                                  ),
                            label: Text(
                              _passkeyCreated
                                  ? L10n.t(context, 'setupp.passkeyDone')
                                  : L10n.t(context, 'setupp.passkeyStart'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            L10n.t(context, 'setupp.laterHint'),
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // Page 7: Zwei-Faktor-Schutz (überspringbar)
                    _Page(
                      questionKey: 'setupq.mfa',
                      subtitle:
                          'Melde dich künftig zusätzlich mit einem Code aus '
                          'einer Authenticator-App an. Optional, du kannst '
                          'diesen Schritt überspringen.',
                      child: Builder(
                        builder: (context) {
                          final mfaActive = ref
                              .watch(mfaStatusProvider)
                              .hasVerifiedFactors;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                mfaActive
                                    ? Icons.verified_user
                                    : Icons.shield_outlined,
                                size: 48,
                                color: mfaActive
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                mfaActive
                                    ? L10n.t(context, 'setupp.mfaActive')
                                    : L10n.t(context, 'setupp.mfaBody'),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: mfaActive
                                    ? null
                                    : () => context.push(AppRoutes.mfaSetup),
                                icon: Icon(
                                  mfaActive
                                      ? Icons.check_circle
                                      : Icons.qr_code,
                                ),
                                label: Text(
                                  mfaActive
                                      ? L10n.t(context, 'setupp.mfaDone')
                                      : L10n.t(context, 'setupp.mfaStart'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                L10n.t(context, 'setupp.laterHint'),
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Page 8: Community Richtlinien
                    _Page(
                      questionKey: 'setupq.guidelines',
                      subtitle: L10n.t(context, 'setupp.guidelinesSub'),
                      child: _buildCommunityGuidelines(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_currentPage < _pageCount - 1)
                      PrimaryButton(
                        label: L10n.t(context, 'onb.next'),
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _nextPage,
                      )
                    else
                      PrimaryButton(
                        label: L10n.t(context, 'setupp.finish'),
                        icon: const Icon(Icons.check),
                        onPressed: _acceptAndFinish,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.t(context, 'setupp.changeLater'),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommunityGuidelines(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'setupp.guidelinesIntroTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(L10n.t(context, 'setupp.guidelinesIntroBody')),
        const SizedBox(height: 16),
        _RuleItem('1', L10n.t(context, 'cg.1.titleShort')),
        _RuleItem('2', L10n.t(context, 'cg.2.titleShort')),
        _RuleItem('3', L10n.t(context, 'cg.3.titleShort')),
        _RuleItem('4', L10n.t(context, 'cg.4.titleShort')),
        _RuleItem('5', L10n.t(context, 'cg.5.titleShort')),
        _RuleItem('6', L10n.t(context, 'setupp.guidelinesBan')),
        const SizedBox(height: 12),
        Text(
          L10n.t(context, 'setupp.guidelinesWarn'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.number, this.text);

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.questionKey,
    required this.subtitle,
    required this.child,
  });

  /// Interview-Frage als L10n-Key (Thestia-Bubble statt Formular-Überschrift).
  final String questionKey;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Interview-Stil: Thestia stellt die Frage (Chat-Optik).
            InterviewBubble(text: L10n.t(context, questionKey)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  // Platz für die Tastatur: Der Inhalt bleibt so über dem
                  // Keyboard scrollbar, statt dahinter zu verschwinden.
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dezent gestylter Hinweis-/Fehlerkasten fuer Standort-Meldungen
/// (statt roher roter Einzeilen-Texte).
class _LocationNotice extends StatelessWidget {
  const _LocationNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
