import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thestia/utils/location/avatar_image.dart';

import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/models/profile/habitude_level.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/services/profile/location_check_service.dart';
import 'package:thestia/services/profile/location_verification_service.dart';
import 'package:thestia/services/profile/image_safety_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/utils/location/geo_names.dart';
import 'package:thestia/utils/location/location_privacy.dart';
import 'package:thestia/utils/security/validators.dart';
import 'package:thestia/widgets/profile/ai_badge.dart';
import 'package:thestia/widgets/common/birthday_style.dart';
import 'package:thestia/widgets/common/buttons.dart';
import 'package:thestia/widgets/settings/age_range_sliders.dart';
import 'package:thestia/widgets/settings/gender_preference_selector.dart';
import 'package:thestia/widgets/settings/location_disclosure.dart';
import 'package:thestia/widgets/profile/music_taste_widgets.dart';
import 'package:thestia/widgets/settings/habitude_selector.dart';
import 'package:thestia/widgets/profile/intro_editor.dart';
import 'package:thestia/widgets/common/stable_chip.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/profileditspeichern.dart';

part 'parts/profileditbilder.dart';

part 'parts/profileditladen.dart';

part 'parts/locationnotice.dart';
part 'parts/photoslotsrow.dart';
part 'parts/profileditaufbau.dart';

/// Unterstützte Wohnsitzländer (Auswahl für die Profilangabe).

// kGermanStates ist zentral in lib/utils/common/constants.dart definiert.

/// Angezeigter Name für gespeicherte (deutsche) Länder-/Bundesland-Werte.
/// Unbekannte Werte fallen auf den Rohwert zurück (niemals leer).
String _countryLabel(BuildContext context, String value) {
  const keys = {
    'Deutschland': 'country.deutschland',
    'Österreich': 'country.oesterreich',
    'Schweiz': 'country.schweiz',
    'Luxemburg': 'country.luxemburg',
    'Belgien': 'country.belgien',
    'Niederlande': 'country.niederlande',
    'Frankreich': 'country.frankreich',
    'Italien': 'country.italien',
    'Spanien': 'country.spanien',
    'Portugal': 'country.portugal',
    'Polen': 'country.polen',
    'Tschechien': 'country.tschechien',
    'Dänemark': 'country.daenemark',
    'Schweden': 'country.schweden',
    'Norwegen': 'country.norwegen',
    'Finnland': 'country.finnland',
    'Vereinigtes Königreich': 'country.uk',
    'Irland': 'country.irland',
    'USA': 'country.usa',
    'Kanada': 'country.kanada',
    'Australien': 'country.australien',
    'Anderes Land': 'country.other',
  };
  final key = keys[value];
  return key == null ? value : L10n.t(context, key);
}

String _stateLabel(BuildContext context, String value) {
  const keys = {
    'Baden-Württemberg': 'state.badenWuerttemberg',
    'Bayern': 'state.bayern',
    'Berlin': 'state.berlin',
    'Brandenburg': 'state.brandenburg',
    'Bremen': 'state.bremen',
    'Hamburg': 'state.hamburg',
    'Hessen': 'state.hessen',
    'Mecklenburg-Vorpommern': 'state.mecklenburgVorpommern',
    'Niedersachsen': 'state.niedersachsen',
    'Nordrhein-Westfalen': 'state.nrw',
    'Rheinland-Pfalz': 'state.rheinlandPfalz',
    'Saarland': 'state.saarland',
    'Sachsen': 'state.sachsen',
    'Sachsen-Anhalt': 'state.sachsenAnhalt',
    'Schleswig-Holstein': 'state.schleswigHolstein',
    'Thüringen': 'state.thueringen',
  };
  final key = keys[value];
  return key == null ? value : L10n.t(context, key);
}

/// Profil bearbeiten: Name, Geburtsdatum, Geschlecht, Präferenzen, Bio,
/// Beziehungsart, Standort, Entfernungsfilter, Interessen und die
/// True, solange "Profil bearbeiten" ungespeicherte Änderungen enthält.
/// Die Bottom-Navigation prüft das vor einem Tab-Wechsel und fragt nach
/// Speichern/Verwerfen (Feedback: Änderungen sollten nicht still verloren
/// gehen).
final profileEditDirtyProvider = StateProvider<bool>((ref) => false);

/// Ziel-Route, zu der nach einem erfolgreichen Speichern navigiert werden
/// soll (von der Navigation gesetzt, vom Edit-Screen verarbeitet).
final profileEditNavigateAfterSaveProvider = StateProvider<String?>(
  (ref) => null,
);

/// Vorstellung für "Find your Match" (Text + Audio).
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _songCtrl = TextEditingController();
  final _bandCtrl = TextEditingController();

  /// true, waehrend _save() laeuft (Spinner im Speichern-Button).
  bool _saving = false;

  /// true, nachdem ein Speichern-Versuch an Validierung gescheitert ist
  /// (stellt den Hinweis am Speichern-Button dar).
  bool _showValidationError = false;

  /// Kurzbeschreibung des letzten Server-Sync-Fehlers (v0.8.1-Diagnose):
  /// erscheint im SnackBar, damit fehlende Migrationen nicht still
  /// bleiben ("Suchradius kommt nicht in Supabase an").
  String? _lastSyncError;

  late Gender _gender;
  late RelationshipType _relationshipType;
  DateTime? _birthDate;
  String _countryValue = 'Deutschland';
  bool _isDetectingLocation = false;
  String? _locationError;
  Future<Uint8List?>? _avatarBytesFuture;
  ProviderSubscription<UserProfile>? _profileSub;

  /// Neu gewähltes Profilbild (noch nicht hochgeladen): Wird erst beim
  /// Speichern hochgeladen (v0.8.1-Fix) - vorher wurde das Bild sofort
  /// übernommen, ohne Speichern-Aufforderung wie bei den anderen Angaben.
  /// Der NSFW-Check läuft bereits bei der Auswahl (das Bild verlässt das
  /// Gerät bei Nichtbestehen nicht).
  Uint8List? _pendingAvatarBytes;

  /// Mehrere Profilbilder (v0.9.0-Nutzerwunsch, max. 3): Zustand der
  /// Slots 1 und 2 (das PRIMÄRE Bild ist Slot 0 über
  /// [_pendingAvatarBytes]). Key = Slot-Index, Value = neue Bytes.
  final Map<int, Uint8List> _pendingExtraBytes = {};

  /// Slots (0..2), die zum Entfernen markiert sind (nachträglich löschbar
  /// bis zum Speichern; vorhandene Refs wandern dann aus profiles.photos).
  final Set<int> _removedPhotoSlots = {};

  /// Ladefutures für BESTEHENDE Extra-Bilder (Slot 1/2).
  final Map<int, Future<Uint8List?>?> _extraBytesFutures = {};

  /// Verzoegerter NSFW-Modell-Warm-up (abbrechbar, siehe initState).
  Timer? _nsfwWarmupTimer;

  // Vorstellung (Find your Match): Zustand wird vom IntroEditor gemeldet.
  String _introTextValue = '';
  String? _introAudioPath;

  /// Intro-Snapshot beim Öffnen (siehe initState-Kommentar): Nur bei
  /// Abweichung davon werden die Intro-Felder serverseitig geschrieben.
  String _initialIntroText = '';
  String? _initialIntroAudioPath;

  // Konsum-Präferenzen (Rauchen, Alkohol, Drogen) – beeinflussen den
  // Find-your-Match-Filter.
  HabitudeLevel? _smoking;
  HabitudeLevel? _alcohol;
  HabitudeLevel? _drugs;

  // Musik-Geschmack (v0.8.0): gemagte + ausgeschlossene Genres.
  List<String> _musicLiked = const [];
  List<String> _musicDisliked = const [];

  // Geburtstags-Stil (v0.9.1): 5 wählbare schicke Styles.
  String _birthdayStyle = 'classic';
  bool _habitsDealbreaker = false;

  // ---- Dirty-Snapshot (Stand beim Öffnen des Screens) --------------------
  // Alle Werte, die dieser Screen ändern kann, werden gegen diesen
  // Snapshot verglichen. Nur so bemerkt der "Speichern?"-Dialog ALLE
  // Änderungen - auch Regler/Dropdowns, die sofort in die Provider
  // schreiben (Bug: Änderungen an Geburtsdatum, Altersspanne, Entfernung
  // und Suchradius-Modus lösten die Nachfrage nie aus).
  late DateTime? _initialBirthDate;
  late int _initialAgeMin;
  late int _initialAgeMax;
  late int _initialMaxDistanceKm;
  late DistanceFilterMode _initialDistanceMode;
  late String? _initialPreferredState;

  /// Referenz auf den Dirty-State-Controller: Im initState gelesen, damit
  /// der dispose-Callback (wo `ref` nicht mehr nutzbar ist) den Flag
  /// zurücksetzen kann (siehe dispose-Kommentar).
  StateController<bool>? _dirtyController;

  @override
  void initState() {
    super.initState();
    _dirtyController = ref.read(profileEditDirtyProvider.notifier);
    final p = ref.read(profileProvider);
    final prefs = ref.read(userPreferencesProvider);
    final settings = ref.read(settingsProvider);
    _nameCtrl.text = p.name;
    _bioCtrl.text = p.bio;
    _stateCtrl.text = p.state ?? '';
    _songCtrl.text = p.favoriteSong ?? '';
    _bandCtrl.text = p.favoriteBand ?? '';
    _introTextValue = p.introText;
    _introAudioPath = p.introAudioPath;
    // Intro-Snapshot (v0.9.0-Fix): Die Intro-Felder werden beim
    // Server-Sync NUR mitgeschickt, wenn sie hier geändert wurden.
    // Sonst würde ein veralteter Screen-Stand (z. B. vor dem Intro-
    // Record geöffnet) die serverseitige Vorstellung mit Leerwerten
    // überschreiben ("Vorstellung verschwindet bei Aktualisierung").
    _initialIntroText = p.introText;
    _initialIntroAudioPath = p.introAudioPath;
    _smoking = p.smoking;
    _alcohol = p.alcohol;
    _drugs = p.drugs;
    _musicLiked = List.of(p.musicLiked);
    _musicDisliked = List.of(p.musicDisliked);
    _birthdayStyle = p.birthdayStyle;
    _habitsDealbreaker = ref.read(settingsProvider).habitsDealbreaker;
    _countryValue = p.country.isEmpty ? 'Deutschland' : p.country;
    _gender = Gender.fromValue(p.gender) ?? Gender.diverse;
    _relationshipType = prefs.relationshipType ?? RelationshipType.open;
    _birthDate = p.birthDate;

    // Dirty-Snapshot einfrieren (siehe Feld-Kommentar).
    _initialBirthDate = p.birthDate;
    _initialAgeMin = settings.ageRangeMin;
    _initialAgeMax = settings.ageRangeMax;
    _initialMaxDistanceKm = prefs.maxDistanceKm;
    _initialDistanceMode = prefs.distanceFilterMode;
    _initialPreferredState = prefs.preferredState;

    // Tab-Wechsel-Bug-Fix: Reine Textfeld-Änderungen triggern KEINEN
    // Rebuild - der Dirty-Flag blieb dadurch false und die Bottom-Navigation
    // fragte beim Verlassen nicht nach. Diese Listener halten den Flag
    // bei jedem Tastenanschlag synchron.
    for (final controller in [
      _nameCtrl,
      _bioCtrl,
      _stateCtrl,
      _songCtrl,
      _bandCtrl,
    ]) {
      controller.addListener(() {
        if (!mounted) return;
        ref.read(profileEditDirtyProvider.notifier).state = _isDirty();
      });
    }

    // NSFW-Modell VORAB laden (v0.8.1) - aber NACH dem ersten Frame und
    // mit kleinem, ABBRECHBAREM Delay: OrtSession.fromBuffer parst 12 MB
    // synchron im UI-Thread und wuerde sonst direkt beim Screen-Oeffnen
    // janken. Cancel im dispose (sonst haengender Timer in Tests/ANR).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nsfwWarmupTimer = Timer(const Duration(milliseconds: 600), () {
        ImageSafetyService.instance.ensureSession();
      });
    });

    // Einspruchs-Entscheidung abholen (v0.8.1): approved -> Bild aus dem
    // Pruefungsort uebernehmen (clientseitig verschluesselt hochladen);
    // rejected -> Aufräumen + Meldung. Danach als 'notified' quittiert.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePendingAppeal();
    });

    // Initial signed URL für aktuelles Profilbild laden.
    if (p.photos.isNotEmpty) {
      _avatarBytesFuture = ref
          .read(supabaseStorageServiceProvider)
          .loadAvatarBytes(p.photos.first);
    }
    // v0.9.0: bestehende ZUSATZ-Bilder (Slots 1/2) ebenfalls laden.
    _loadExtraFutures(p.photos);

    // Falls das Profil später nachgeladen wird, die Felder nachziehen.
    _profileSub = ref.listenManual<UserProfile>(profileProvider, (prev, next) {
      if (!mounted) return;
      if (_nameCtrl.text != next.name) {
        _nameCtrl.text = next.name;
      }
      if (_bioCtrl.text != next.bio) {
        _bioCtrl.text = next.bio;
      }
      if (next.state != null && _stateCtrl.text != next.state) {
        _stateCtrl.text = next.state!;
      }
      if (next.birthDate != null && _birthDate != next.birthDate) {
        setState(() => _birthDate = next.birthDate);
      }
      if (_introTextValue != next.introText) {
        _introTextValue = next.introText;
      }
      if (_introAudioPath != next.introAudioPath) {
        _introAudioPath = next.introAudioPath;
      }
      if (prev?.photos != next.photos) {
        setState(() {
          if (next.photos.isNotEmpty) {
            _avatarBytesFuture = ref
                .read(supabaseStorageServiceProvider)
                .loadAvatarBytes(next.photos.first);
          } else {
            _avatarBytesFuture = null;
          }
          _loadExtraFutures(next.photos, skipPending: true);
        });
      }
    });
  }

  @override
  void dispose() {
    // Invariante für die Tab-Navigation: Der Dirty-Flag ist GENAU DANN
    // true, wenn dieser Screen offen ist und ungespeicherte Änderungen
    // hat. Beim Verlassen (dispose) deshalb immer zurücksetzen.
    //
    // WICHTIG: Nicht SYNCHRON im dispose schreiben - während des Unmounts
    // sind die Riverpod-Subscriptions dieses Elements noch aktiv und ein
    // Write würde ein markNeedsBuild auf ein bereits defunct Element
    // auslösen. Der Microtask läuft erst NACH abgeschlossenem Unmount.
    _nsfwWarmupTimer?.cancel();
    _nsfwWarmupTimer = null;
    final dirtyController = _dirtyController;
    _dirtyController = null;
    if (dirtyController != null) {
      scheduleMicrotask(() {
        // Container bereits weg (App-Ende) - nichts zu tun.
        bestEffortSync(' dirtyController.state = false;', () {
          dirtyController.state = false;
        });
      });
    }
    _profileSub?.close();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _stateCtrl.dispose();
    _songCtrl.dispose();
    _bandCtrl.dispose();
    super.dispose();
  }

  /// Reihenfolge-unabhängiger Listenvergleich (Dirty-Erkennung).
  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < a.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => _baueProfil(context);

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehoert zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}
