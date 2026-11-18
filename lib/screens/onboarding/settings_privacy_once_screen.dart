import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:thestia/utils/avatar_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// v0.10.0: geocoding und geolocator sind hier nicht mehr noetig.
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
import 'package:thestia/widgets/captcha_challenge.dart';
import 'package:thestia/widgets/gender_preference_selector.dart';
import 'package:thestia/widgets/habitude_selector.dart';
import 'package:thestia/widgets/intro_editor.dart';
import 'package:thestia/widgets/interview_bubble.dart';
import 'package:thestia/widgets/location_disclosure.dart';
import 'package:thestia/widgets/music_taste_widgets.dart';
import 'package:thestia/widgets/selectable_tile.dart';
import 'package:thestia/widgets/theme_picker.dart';
import 'package:thestia/utils/best_effort.dart';

part 'parts/einrichtungabschluss.dart';

part 'parts/einrichtungspeichern.dart';

part 'parts/einrichtungnavigation.dart';

part 'parts/ruleitem.dart';
part 'parts/page.dart';
part 'parts/locationnotice.dart';
part 'parts/einrichtungsaufbau.dart';

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

  // v0.10.0: Entfernt wurden der Orts-Textfeld-Controller (_locationCtrl),
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

  // v0.10.0: 10 Seiten statt 8. Neu sind der Geburtstags-Stil (mit
  // GROSSER Vorschau) und der Musik-Geschmack - beide wurden bei einer
  // Registrierung nie abgefragt. Dazu kommen die drei Fortschrittsschritte
  // von unten.
  static const int _pageCount = 10;
  static const int _profilePage = 1;
  static const int _introPage = 2;
  static const int _birthdayPage = 3;
  static const int _musicPage = 4;
  static const int _habitudesPage = 5;

  /// Geburtstags-Stil (v0.10.0, eigene Seite in der Einrichtung).
  ///
  /// Frueher nur beim App-Update nachfragbar (whats_new_screen.dart) und
  /// im Profil-Edit. In der Einrichtung stand er nie - wer sich frisch
  /// registriert hat, hatte den Default, ohne es gewaehlt zu haben.
  String _birthdayStyle = BirthdayStyle.values.first;

  /// Musik-Geschmack (v0.10.0).
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

  // Schritt "Profil & Interessen": Bio, Land, Bundesland, Interessen,
  // Avatar.
  final _bioCtrl = TextEditingController();
  String? _selectedState;
  String? _selectedCountry;
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
    // v0.10.0: Kein Vorbelegen von Textfeldern mehr - die beiden
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

  @override
  Widget build(BuildContext context) => _baueEinrichtung(context);

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehoert zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}
