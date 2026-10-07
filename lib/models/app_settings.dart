import 'package:thestia/models/profile_visibility.dart';
import 'package:thestia/utils/constants.dart';

/// App-Einstellungen inkl. Blind-Mode und Privatsphäre-Optionen.
///
/// Diese Klasse ist die "Single Source of Truth" für Nutzerpräferenzen und
/// wird sicher lokal (shared_preferences) gespeichert.
class AppSettings {
  /// Blind Mode: Fotos werden erst nach einem Match angezeigt.
  final bool blindModeEnabled;

  /// Eigene Fotos erst nach Match freigeben.
  final bool revealPhotosAfterMatch;

  /// Wer darf das eigene Profil sehen?
  final ProfileVisibility profileVisibility;

  /// Dark Mode erzwungen? (true = dunkel, false = hell, null = System)
  final bool? useDarkMode;

  /// Onboarding bereits gesehen?
  final bool onboardingCompleted;

  /// Maximale Distanz (km) für den Entfernungsfilter.
  final int maxDistanceKm;

  /// Untere Grenze der bevorzugten Alterspanne (Jahre).
  final int ageRangeMin;

  /// Obere Grenze der bevorzugten Alterspanne (Jahre).
  final int ageRangeMax;

  /// Persönlichkeitstest abgeschlossen?
  final bool personalityTestCompleted;

  /// Einmalige Settings/Privacy nach Registrierung abgeschlossen?
  final bool oneTimeSettingsCompleted;

  /// Community Richtlinien akzeptiert?
  final bool communityGuidelinesAccepted;

  /// Einrichtungskette mindestens EINMAL abgeschlossen (serverseitig
  /// gespiegelt als profiles.onboarding_done, Migration 065)?
  ///
  /// "Niemals-Einrichtung"-Garantie: Sobald true, erzwingt der Router die
  /// Einrichtung / den Persönlichkeitstest nie wieder - auch nicht kurz,
  /// auch wenn Einzelpunkte übersprungen oder Einzelflag-Stände unvoll-
  /// ständig sind. Nur-Upgrade: Wird von false auf true gesetzt, nie zurück.
  final bool onboardingDone;

  /// Einführung (Willkommens-Screen) bereits gesehen?
  /// Wenn true, wird der Willkommens-Screen nicht erneut gezeigt.
  final bool introSeen;

  /// Benachrichtigungen aktiv?
  final bool notificationsEnabled;

  /// Einzel-Schalter: Benachrichtigung bei neuem Match.
  final bool notifyMatches;

  /// Einzel-Schalter: Benachrichtigung bei erhaltenem Like.
  final bool notifyLikes;

  /// Einzel-Schalter: Benachrichtigung bei neuer Chat-Nachricht.
  final bool notifyMessages;

  /// Einzel-Schalter: Erinnerung, wenn die Dating Hour gleich beginnt.
  final bool notifyDatingHour;

  /// Dating Hour Intro (Regeln + Erklärung) bereits gesehen?
  final bool datingHourIntroSeen;

  /// Dating Hour: Beim nächsten Event automatisch wieder dabei sein?
  /// Wird nach Ende eines Events abgefragt (Dialog im Dating-Hour-Chat).
  final bool datingHourAutoJoin;

  /// MFA-Einrichtungshinweis dauerhaft ausgeblendet?
  /// (Nutzer hat „Später“ auf dem 2FA-Setup-Screen gewählt.)
  final bool mfaSetupDismissed;

  /// Bilder im Chat standardmäßig verpixelt anzeigen (Schutz vor
  /// unangemessenen Inhalten; Antippen zeigt nach Warnung das Bild).
  final bool blurChatImages;

  /// Hat der Nutzer die prominente Mikrofon-Offenlegung bestaetigt?
  ///
  /// Google Play verlangt fuer RECORD_AUDIO eine in der App sichtbare
  /// Begruendung, BEVOR die Berechtigung angefragt wird. Damit die
  /// Offenlegung nicht bei jeder Sprachnachricht erneut erscheint, wird
  /// die Bestaetigung hier gespeichert - es ist eine Einstellung und
  /// gehoert neben die anderen datenschutzrelevanten Schalter.
  ///
  /// `false` ist der sichere Standard: wer die App frisch installiert,
  /// sieht die Erklaerung beim ersten Versuch eine Sprachnachricht zu
  /// schreiben.
  final bool micDisclosureAccepted;

  /// Hat der Nutzer die prominente Kamera-Offenlegung bestaetigt?
  ///
  /// Wie [micDisclosureAccepted], aber fuer CAMERA. Die Kamera wird in
  /// der Alters-/Identitaetsverifikation direkt beim Oeffnen benutzt -
  /// ohne Offenlegung waere das ein Antrag im Hintergrund, den der
  /// Nutzer nicht erwartet. Google Play verlangt fuer beides eine
  /// sichtbare Begruendung VOR der Anfrage.
  final bool cameraDisclosureAccepted;

  /// Gewähltes Farbschema (Name aus ThestiaTheme, Default 'classic').
  final String themeName;

  /// Pausenmodus (v0.8.0): Profil in Discovery/FYM unsichtbar, Funken
  /// und Chats bleiben bestehen. Serverseitig gespiegelt (profiles.paused).
  final bool paused;

  /// Habit-Dealbreaker (v0.8.0): nur Kandidaten mit <= eigenem Konsum.
  final bool habitsDealbreaker;

  /// Kontext-Icebreaker-Chip im Chat (v0.8.0): Vorschläge aus gemeinsamen
  /// Interessen; vom Nutzer deaktivierbar.
  final bool contextIcebreakerEnabled;

  /// Chat-Hintergrund (v0.9.1): none, Muster oder custom (eigenes Bild).
  /// Serverseitig in ui_prefs gespiegelt.
  final String chatBackground;

  /// Lokaler Dateipfad des eigenen Chat-Hintergrundbildes (nur custom).
  /// Bleibt bewusst NUR auf dem Geraet (kein Server-Sync).
  final String? chatBackgroundPath;

  /// Kurzer Willkommensscreen nach der Registrierung (v0.9.1) gesehen?
  /// Einmalig nach E-Mail-Bestaetigung, danach direkt Einrichtung.
  final bool signupWelcomeSeen;

  /// Chat-Hintergrund-Auswahl beim ersten Chat gezeigt (v0.10.0)?
  ///
  /// Bewusst KEIN Teil der Einrichtung: der Hintergrund ist eine
  /// Geschmacksfrage, und die Einrichtung war mit zehn Seiten lang
  /// genug. Die Abfrage kommt stattdessen beim ersten geoeffneten Chat
  /// (Dialog) - dort sieht der Nutzer auch, worum es geht.
  ///
  /// Einmalig: nach dem Schliessen bleibt es in den Einstellungen
  /// erreichbar und wird nicht erneut angeboten.
  final bool chatBackgroundSeen;

  /// Veroeffentlichen, dass andere meine (grobe) Entfernung sehen
  /// duerfen (v0.10.0)?
  ///
  /// Standard `false`: es wird nichts veroeffentlicht, solange der
  /// Nutzer das nicht ausdruecklich erlaubt hat. Wer es einschaltet,
  /// sieht danach eine Entfernung in 10-km-Stufen ("unter 10 km",
  /// "10 bis 20 km") - nie den genauen Standort.
  ///
  /// Serverseitig gespiegelt, weil die Anzeegeraete fremd entscheiden.
  final bool showDistance;

  const AppSettings({
    this.blindModeEnabled = true,
    this.revealPhotosAfterMatch = true,
    this.profileVisibility = ProfileVisibility.everyone,
    this.useDarkMode,
    this.onboardingCompleted = true,
    this.maxDistanceKm = AppConstants.defaultDistanceKm,
    this.ageRangeMin = 16,
    this.ageRangeMax = 99,
    this.personalityTestCompleted = false,
    this.oneTimeSettingsCompleted = false,
    this.communityGuidelinesAccepted = false,
    this.onboardingDone = false,
    this.introSeen = false,
    this.notificationsEnabled = true,
    this.notifyMatches = true,
    this.notifyLikes = true,
    this.notifyMessages = true,
    this.notifyDatingHour = true,
    this.datingHourIntroSeen = false,
    this.datingHourAutoJoin = false,
    this.mfaSetupDismissed = false,
    this.blurChatImages = true,
    this.micDisclosureAccepted = false,
    this.cameraDisclosureAccepted = false,
    this.themeName = 'classic',
    this.paused = false,
    this.habitsDealbreaker = false,
    this.contextIcebreakerEnabled = true,
    this.chatBackground = 'none',
    this.chatBackgroundPath,
    this.signupWelcomeSeen = false,
    this.chatBackgroundSeen = false,
    // v0.10.0: Datenschutz-Vorgabe. Nichts veroeffentlichen, was der
    // Nutzer nicht ausdruecklich erlaubt hat.
    this.showDistance = false,
  });

  /// Standard-Einstellungen für einen neuen Nutzer.
  factory AppSettings.defaults() => const AppSettings();

  /// Erzeugt Einstellungen aus einem JSON-Map.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      blindModeEnabled: json['blindModeEnabled'] as bool? ?? true,
      revealPhotosAfterMatch: json['revealPhotosAfterMatch'] as bool? ?? true,
      profileVisibility: ProfileVisibility.fromValue(
        json['profileVisibility'] as String?,
      ),
      useDarkMode: json['useDarkMode'] as bool?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? true,
      maxDistanceKm:
          json['maxDistanceKm'] as int? ?? AppConstants.defaultDistanceKm,
      ageRangeMin: json['ageRangeMin'] as int? ?? 16,
      ageRangeMax: json['ageRangeMax'] as int? ?? 99,
      personalityTestCompleted:
          json['personalityTestCompleted'] as bool? ?? false,
      oneTimeSettingsCompleted:
          json['oneTimeSettingsCompleted'] as bool? ?? false,
      communityGuidelinesAccepted:
          json['communityGuidelinesAccepted'] as bool? ?? false,
      onboardingDone: json['onboardingDone'] as bool? ?? false,
      introSeen: json['introSeen'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      notifyMatches: json['notifyMatches'] as bool? ?? true,
      notifyLikes: json['notifyLikes'] as bool? ?? true,
      notifyMessages: json['notifyMessages'] as bool? ?? true,
      notifyDatingHour: json['notifyDatingHour'] as bool? ?? true,
      datingHourIntroSeen: json['datingHourIntroSeen'] as bool? ?? false,
      datingHourAutoJoin: json['datingHourAutoJoin'] as bool? ?? false,
      mfaSetupDismissed: json['mfaSetupDismissed'] as bool? ?? false,
      blurChatImages: json['blurChatImages'] as bool? ?? true,
    micDisclosureAccepted:
        json['micDisclosureAccepted'] as bool? ?? false,
    cameraDisclosureAccepted:
        json['cameraDisclosureAccepted'] as bool? ?? false,
      themeName: json['themeName'] as String? ?? 'classic',
      paused: json['paused'] as bool? ?? false,
      habitsDealbreaker: json['habitsDealbreaker'] as bool? ?? false,
      contextIcebreakerEnabled:
          json['contextIcebreakerEnabled'] as bool? ?? true,
      chatBackground: json['chatBackground'] as String? ?? 'none',
      chatBackgroundPath: json['chatBackgroundPath'] as String?,
      signupWelcomeSeen: json['signupWelcomeSeen'] as bool? ?? false,
      chatBackgroundSeen: json['chatBackgroundSeen'] as bool? ?? false,
      // Fehlende Schluessel (alte Installation) gelten als "aus" -
      // das ist die datenschutzfreundliche Richtung.
      showDistance: json['showDistance'] as bool? ?? false,
    );
  }

  /// Wandelt die Einstellungen in ein JSON-Map um.
  Map<String, dynamic> toJson() => {
    'blindModeEnabled': blindModeEnabled,
    'revealPhotosAfterMatch': revealPhotosAfterMatch,
    'profileVisibility': profileVisibility.value,
    'useDarkMode': useDarkMode,
    'onboardingCompleted': onboardingCompleted,
    'maxDistanceKm': maxDistanceKm,
    'ageRangeMin': ageRangeMin,
    'ageRangeMax': ageRangeMax,
    'personalityTestCompleted': personalityTestCompleted,
    'oneTimeSettingsCompleted': oneTimeSettingsCompleted,
    'communityGuidelinesAccepted': communityGuidelinesAccepted,
    'onboardingDone': onboardingDone,
    'introSeen': introSeen,
    'notificationsEnabled': notificationsEnabled,
    'notifyMatches': notifyMatches,
    'notifyLikes': notifyLikes,
    'notifyMessages': notifyMessages,
    'notifyDatingHour': notifyDatingHour,
    'datingHourIntroSeen': datingHourIntroSeen,
    'datingHourAutoJoin': datingHourAutoJoin,
    'mfaSetupDismissed': mfaSetupDismissed,
    'blurChatImages': blurChatImages,
    'micDisclosureAccepted': micDisclosureAccepted,
    'cameraDisclosureAccepted': cameraDisclosureAccepted,
    'themeName': themeName,
    'paused': paused,
    'habitsDealbreaker': habitsDealbreaker,
    'contextIcebreakerEnabled': contextIcebreakerEnabled,
    'chatBackground': chatBackground,
    'chatBackgroundPath': chatBackgroundPath,
    'signupWelcomeSeen': signupWelcomeSeen,
    'chatBackgroundSeen': chatBackgroundSeen,
    'showDistance': showDistance,
  };

  /// Immutabele Kopie mit veränderten Werten.
  ///
  /// Sentinel für [useDarkMode]: Das Feld ist nullable (null = System),
  /// daher kann ein plain `??` ein explizites null nicht von "nicht
  /// gesetzt" unterscheiden – `copyWith(useDarkMode: null)` würde sonst
  /// still den alten Wert behalten (Bug: "System" war nach Hell/Dunkel
  /// nicht mehr wählbar). Alle anderen Felder sind non-nullable und
  /// brauchen keinen Sentinel.
  static const _useDarkModeUnset = Object();

  /// Sentinel für [chatBackgroundPath]: null bedeutet "Pfad löschen",
  /// daher braucht es die Unterscheidung wie bei [useDarkMode].
  static const _chatBackgroundPathUnset = Object();

  AppSettings copyWith({
    bool? blindModeEnabled,
    bool? revealPhotosAfterMatch,
    ProfileVisibility? profileVisibility,
    Object? useDarkMode = _useDarkModeUnset,
    bool? onboardingCompleted,
    int? maxDistanceKm,
    int? ageRangeMin,
    int? ageRangeMax,
    bool? personalityTestCompleted,
    bool? oneTimeSettingsCompleted,
    bool? communityGuidelinesAccepted,
    bool? onboardingDone,
    bool? introSeen,
    bool? notificationsEnabled,
    bool? notifyMatches,
    bool? notifyLikes,
    bool? notifyMessages,
    bool? notifyDatingHour,
    bool? datingHourIntroSeen,
    bool? datingHourAutoJoin,
    bool? mfaSetupDismissed,
    bool? blurChatImages,
    bool? micDisclosureAccepted,
    bool? cameraDisclosureAccepted,
    String? themeName,
    bool? paused,
    bool? habitsDealbreaker,
    bool? contextIcebreakerEnabled,
    String? chatBackground,
    Object? chatBackgroundPath = _chatBackgroundPathUnset,
    bool? signupWelcomeSeen,
    bool? chatBackgroundSeen,
    bool? showDistance,
  }) {
    return AppSettings(
      blindModeEnabled: blindModeEnabled ?? this.blindModeEnabled,
      revealPhotosAfterMatch:
          revealPhotosAfterMatch ?? this.revealPhotosAfterMatch,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      useDarkMode: identical(useDarkMode, _useDarkModeUnset)
          ? this.useDarkMode
          : useDarkMode as bool?,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      ageRangeMin: ageRangeMin ?? this.ageRangeMin,
      ageRangeMax: ageRangeMax ?? this.ageRangeMax,
      personalityTestCompleted:
          personalityTestCompleted ?? this.personalityTestCompleted,
      oneTimeSettingsCompleted:
          oneTimeSettingsCompleted ?? this.oneTimeSettingsCompleted,
      communityGuidelinesAccepted:
          communityGuidelinesAccepted ?? this.communityGuidelinesAccepted,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      introSeen: introSeen ?? this.introSeen,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyMatches: notifyMatches ?? this.notifyMatches,
      notifyLikes: notifyLikes ?? this.notifyLikes,
      notifyMessages: notifyMessages ?? this.notifyMessages,
      notifyDatingHour: notifyDatingHour ?? this.notifyDatingHour,
      datingHourIntroSeen: datingHourIntroSeen ?? this.datingHourIntroSeen,
      datingHourAutoJoin: datingHourAutoJoin ?? this.datingHourAutoJoin,
      mfaSetupDismissed: mfaSetupDismissed ?? this.mfaSetupDismissed,
      blurChatImages: blurChatImages ?? this.blurChatImages,
    micDisclosureAccepted: micDisclosureAccepted ?? this.micDisclosureAccepted,
    cameraDisclosureAccepted:
        cameraDisclosureAccepted ?? this.cameraDisclosureAccepted,
      themeName: themeName ?? this.themeName,
      paused: paused ?? this.paused,
      habitsDealbreaker: habitsDealbreaker ?? this.habitsDealbreaker,
      contextIcebreakerEnabled:
          contextIcebreakerEnabled ?? this.contextIcebreakerEnabled,
      chatBackground: chatBackground ?? this.chatBackground,
      chatBackgroundPath:
          identical(chatBackgroundPath, _chatBackgroundPathUnset)
              ? this.chatBackgroundPath
              : chatBackgroundPath as String?,
      signupWelcomeSeen: signupWelcomeSeen ?? this.signupWelcomeSeen,
      chatBackgroundSeen: chatBackgroundSeen ?? this.chatBackgroundSeen,
      showDistance: showDistance ?? this.showDistance,
    );
  }
}
