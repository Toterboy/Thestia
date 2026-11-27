import 'package:thestia/models/profile/profile_visibility.dart';
import 'package:thestia/models/settings/nachricht_ueberdenken.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/utils/common/json_leser.dart';

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

  /// Hat der Nutzer die prominente Mikrofon-Offenlegung bestätigt?
  ///
  /// Google Play verlangt für RECORD_AUDIO eine in der App sichtbare
  /// Begründung, BEVOR die Berechtigung angefragt wird. Damit die
  /// Offenlegung nicht bei jeder Sprachnachricht erneut erscheint, wird
  /// die Bestätigen hier gespeichert - es ist eine Einstellung und
  /// gehört neben die anderen datenschutzrelevanten Schalter.
  ///
  /// `false` ist der sichere Standard: wer die App frisch installiert,
  /// sieht die Erklären beim ersten Versuch eine Sprachnachricht zu
  /// schreiben.
  final bool micDisclosureAccepted;

  /// Hat der Nutzer die prominente Kamera-Offenlegung bestätigt?
  ///
  /// Wie [micDisclosureAccepted], aber für CAMERA. Die Kamera wird in
  /// der Alters-/Identitätsverifikation direkt beim Öffnen benutzt -
  /// ohne Offenlegung wäre das ein Antrag im Hintergrund, den der
  /// Nutzer nicht erwartet. Google Play verlangt für beides eine
  /// sichtbare Begründung VOR der Anfrage.
  final bool cameraDisclosureAccepted;

  /// Hat der Nutzer die prominente Standort-Offenlegung bestätigt?
  ///
  /// Wie [cameraDisclosureAccepted], aber für den Standort. Google Play
  /// verlangt für empfindliche Berechtigungen (Kamera, Mikrofon,
  /// Standort) eine sichtbare Begründung VOR der Anfrage - die App hat
  /// das für Kamera und Mikrofon, für den Standort fehlte es (BEFUND
  /// 06.11.2026).
  final bool locationDisclosureAccepted;

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
  /// Bleibt bewusst NUR auf dem Gerät (kein Server-Sync).
  final String? chatBackgroundPath;

  /// Kurzer Willkommensscreen nach der Registrierung (v0.9.1) gesehen?
  /// Einmalig nach E-Mail-Bestätigen, danach direkt Einrichtung.
  final bool signupWelcomeSeen;

  /// Sicherheits-Aufklärung vor der Einrichtung abgeschlossen?
  ///
  /// NUTZERWUNSCH (30.10.2026): Nach der E-Mail-Bestätigung und VOR dem
  /// Setup wird gefragt, ob die Person schon Dating-Apps benutzt hat und
  /// ob ihr die Gefahren bewusst sind. Wer beides verneint (oder noch
  /// keine App benutzt hat), bekommt die Aufklärungsseiten. Der Flag
  /// gehört zum Setup: einmal abgeschlossen, nie wieder erzwungen.
  final bool datingSafetyEducationCompleted;

  /// Chat-Hintergrund-Auswahl beim ersten Chat gezeigt (v0.10.0)?
  ///
  /// Bewusst KEIN Teil der Einrichtung: der Hintergrund ist eine
  /// Geschmacksfrage, und die Einrichtung war mit zehn Seiten lang
  /// genug. Die Abfrage kommt stattdessen beim ersten geöffneten Chat
  /// (Dialog) - dort sieht der Nutzer auch, worum es geht.
  ///
  /// Einmalig: nach dem Schließen bleibt es in den Einstellungen
  /// erreichbar und wird nicht erneut angeboten.
  final bool chatBackgroundSeen;

  /// Bis wann die App schweigt (der Ruhemodus nach einem Treffen).
  ///
  /// DER WEG (Plan 0.11.0, "Begegnung statt Bildschirm"): "Nach einem
  /// Treffen, das BEIDE Personen bestätigt haben, erscheint der sanfte
  /// Vorschlag 'Genießt die Zeit - Thestia schweigt bis morgen':
  /// Benachrichtigungen stumm für den Abend, ruhiger Bildschirm. Die App
  /// feiert Abwesenheit statt Bindung zu erzeugen."
  ///
  /// Solange dieser Zeitpunkt in der Zukunft liegt, kommen keine
  /// Benachrichtigungen mehr. Die Anrufe kommen trotzdem an - ein
  /// Anruf ist eine Einladung, keine Forderung.
  ///
  /// LOKAL: Der Ruhemodus steht nur auf diesem Gerät. Er wird nicht
  /// gespiegelt - das ist eine Sache zwischen dem Nutzer und seinem
  /// Telefon.
  final DateTime? ruhemodusBis;

  /// Veröffentlichen, dass andere meine (grobe) Entfernung sehen
  /// dürfen (v0.10.0)?
  ///
  /// Standard `false`: es wird nichts veröffentlicht, solange der
  /// Nutzer das nicht ausdrücklich erlaubt hat. Wer es einschaltet,
  /// sieht danach eine Entfernung in 10-km-Stufen ("unter 10 km",
  /// "10 bis 20 km") - nie den genauen Standort.
  ///
  /// Serverseitig gespiegelt, weil die Anzeegeräte fremd entscheiden.
  final bool showDistance;

  /// Zeigt meinen Namen, wenn jemand bei Transit Spark zuwinkt?
  ///
  /// BEFUND (Betreiber, 10.11.2026): "Ich finde aber, dass man bei Transit
  /// Spark einstellen können soll, ob der Name für andere sichtbar sein
  /// soll oder nicht."
  ///
  /// Der Server entscheidet: Er liefert den Namen nur, wenn dieser Schalter
  /// an ist (Migration 208). Ein Schalter, der nur im Gerät stünde, wäre
  /// wertlos - die andere Person sieht den Namen über den Server.
  ///
  /// Die Grenze (sie steht auch im Text der Einstellung): Der Schalter
  /// schützt davor, dass jemand deinen NAMEN sieht, der dir zugewinkt hat.
  /// Er schützt NICHT davor, dass dich jemand erkennt, der neben dir
  /// steht.
  final bool transitShowName;

  /// Stehen meine gemagten Musik-Genres im öffentlich Profil?
  ///
  /// NUTZERWUNSCH (22.11.2026): "Man soll diese Punkte und die
  /// Gewohnheiten einzeln fürs öffentliche Profil an und aus machen
  /// können."
  ///
  /// Der Server entscheidet (Migration 222): die Projektion liefert die
  /// Genres nur, wenn dieser Schalter an ist.
  final bool showMusicLiked;

  /// Stehen meine abgelehnten Musik-Genres im öffentlich Profil?
  final bool showMusicDisliked;

  /// Steht mein Lieblingssong im öffentlich Profil?
  final bool showFavoriteSong;

  /// Steht mein Lieblings-Künstler (Lieblingsband) im öffentlich Profil?
  final bool showFavoriteBand;

  /// Steht die Gewohnheit "Rauchen" im öffentlich Profil?
  final bool showHabitsSmoking;

  /// Steht die Gewohnheit "Alkohol" im öffentlich Profil?
  final bool showHabitsAlcohol;

  /// Steht die Gewohnheit "Drogen" im öffentlich Profil?
  final bool showHabitsDrugs;

  /// Wie die App vor dem Senden nachfragt ("Nachricht überdenken").
  ///
  /// NUTZERWUNSCH (26.11.2026): "In den Einstellungen im Chat bei den
  /// drei Punkten soll das sein - beim drücken auf den Senden-Button
  /// wird erst noch gefragt, wie du selbst die Nachricht verstehen
  /// würdest und ob sie wirklich so sein soll."
  ///
  /// Gespeichert wird der Text des Modus (siehe [NachrichtPruefModus]),
  /// damit man die Datei lesen kann. Standard ist "aus" - wer nichts
  /// eingestellt hat, wird nicht aufgehalten.
  final String nachrichtPruefModus;

  /// Ab wie vielen Zeichen geprüft wird (Modus "ab Zeichen").
  ///
  /// 250 Zeichen sind ungefähr vier Sätze. Der Wert ist frei stellbar -
  /// manche schreiben lieber kurz, andere brauchen mehr Ruhe.
  final int nachrichtPruefSchwelle;

  /// Die Ausnahmen je Kontakt (die Kontakt-ID auf den Modus als Text).
  ///
  /// DER WEG: So kann der Nutzer global "immer" sagen und für einen
  /// Kontakt "nein" - oder umgekehrt. Beides ist möglich, weil die
  /// Ausnahme des Kontakts den globalen Wert überstimmt.
  final Map<String, String> nachrichtPruefAusnahmen;

  /// Wie die eigene Tastatur belegt ist (0.11.0).
  ///
  /// DER WEG: Bisher folgte die Belegung der Sprache der App. Wer auf
  /// Deutsch schreibt, aber in einer englischen Umgebung arbeitet, will
  /// die App-Sprache ändern, ohne dass sich die Tasten verschieben -
  /// und umgekehrt. Deshalb ist es eine eigene Einstellung.
  ///
  /// Gespeichert als Text (siehe [TastaturBelegung]), gespiegelt nach
  /// `profiles.ui_prefs` (Überstehen einer Neuinstallation).
  final String tastaturBelegung;

  /// Wie die eigene Tastatur gefärbt ist (0.11.0).
  ///
  /// "wieApp" ist der heutige Stand (die Flächenfarben des Themas),
  /// "appFarbe" nimmt die Akzentfarbe der Farbwelt, "eigeneFarbe" den
  /// selbst gewählten Farbton aus [tastaturFarbe].
  final String tastaturStil;

  /// Der eigene Farbton der Tastatur (0.11.0) als ARGB-Zahl.
  ///
  /// Null, solange der Nutzer keine eigene Farbe gewählt hat. Wird
  /// nur benutzt, wenn [tastaturStil] auf "eigeneFarbe" steht.
  final int? tastaturFarbe;

  /// Die Einstellung "Nachricht überdenken" in der Form, in der die
  /// Oberfläche sie braucht.
  ///
  /// DER WEG: Gespeichert wird als Text (siehe [nachrichtPruefModus]),
  /// damit die Datei lesbar bleibt. Hier steht die fertige Einstellung
  /// bereit - inklusive der Ausnahmen je Kontakt.
  NachrichtPruefEinstellung get nachrichtPruef => NachrichtPruefEinstellung(
    modus: NachrichtPruefModusWert.ausWert(nachrichtPruefModus),
    schwelle: nachrichtPruefSchwelle,
    ausnahmen: nachrichtPruefAusnahmen.map(
      (k, v) => MapEntry(k, NachrichtPruefModusWert.ausWert(v)),
    ),
  );

  /// Hat der Nutzer bewusst entschieden, ob sein Name beim Transit-Zuwinken
  /// gezeigt wird?
  ///
  /// BEFUND (Betreiber, 10.11.2026): "Die Abfrage über die Entscheidung
  /// Name an oder aus soll beim ersten Öffnen des Transit Spark screens
  /// kommen und dann nachträglich noch änderbar sein. So ist die
  /// Entscheidung beim User und er kann bewusst entscheiden."
  ///
  /// Deshalb steht hier etwas anderes als der Wert selbst: der Wert
  /// ([transitShowName]) ist der aktuelle Stand, dieses Flag sagt, ob der
  /// Nutzer ihn selbst gewählt hat. Solange es false ist, fragt der
  /// Transit-Radar beim Öffnen nach.
  final bool transitShowNameSet;

  const AppSettings({
    this.blindModeEnabled = true,
    this.revealPhotosAfterMatch = true,
    this.profileVisibility = ProfileVisibility.everyone,
    this.useDarkMode,
    this.onboardingCompleted = true,
    this.maxDistanceKm = AppConstants.defaultDistanceKm,
    // v0.10.0: Die Spanne war 16-99 und damit praktisch "keine
    // Grenze" - ein 20-Jähriger bekam 99-Jährige vorgeschlagen.
    //
    // 18-65 ist die Spanne, die ein Vermittlungsdienst realistisch
    // bedienen kann: unter 18 ist Transit Spark ohnehin gesperrt, und
    // über 65 ist die Erfolgsquote erfahrungsgemäss sehr niedrig.
    // Beide Grenzen bleiben frei einstellbar.
    this.ageRangeMin = 18,
    this.ageRangeMax = 65,
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
    this.locationDisclosureAccepted = false,
    this.themeName = 'classic',
    this.paused = false,
    this.habitsDealbreaker = false,
    this.contextIcebreakerEnabled = true,
    this.chatBackground = 'none',
    this.chatBackgroundPath,
    this.signupWelcomeSeen = false,
    this.datingSafetyEducationCompleted = false,
    this.chatBackgroundSeen = false,
    // Der Ruhemodus nach einem Treffen (Plan 0.11.0) - standardmäßig
    // aus.
    this.ruhemodusBis,
    // v0.10.0: Datenschutz-Vorgabe. Nichts veröffentlichen, was der
    // Nutzer nicht ausdrücklich erlaubt hat.
    this.showDistance = false,
    this.transitShowName = true,
    this.transitShowNameSet = false,
    // NUTZERWUNSCH (22.11.2026): Die Musik und die Gewohnheiten
    // stehen standardmässig im öffentlich Profil - so war es
    // bisher. Wer sie nicht zeigen will, schaltet sie ab.
    this.showMusicLiked = true,
    this.showMusicDisliked = true,
    this.showFavoriteSong = true,
    this.showFavoriteBand = true,
    this.showHabitsSmoking = true,
    this.showHabitsAlcohol = true,
    this.showHabitsDrugs = true,
    this.nachrichtPruefModus = 'aus',
    this.nachrichtPruefSchwelle = 250,
    this.nachrichtPruefAusnahmen = const <String, String>{},
    this.tastaturBelegung = 'wieApp',
    this.tastaturStil = 'wieApp',
    this.tastaturFarbe,
  });

  /// Standard-Einstellungen für einen neuen Nutzer.
  factory AppSettings.defaults() => const AppSettings();

  /// Erzeugt Einstellungen aus einem JSON-Map.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      // Blind Mode ist fest AN (NUTZERWUNSCH 01.11.2026) - der
      // gespeicherte Wert wird bewusst ignoriert. Sonst könnte ein
      // alter Stand (Blind Mode aus) die App weiter ausblenden.
      blindModeEnabled: true,
      revealPhotosAfterMatch: json['revealPhotosAfterMatch'] as bool? ?? true,
      profileVisibility: ProfileVisibility.fromValue(
        json['profileVisibility'] as String?,
      ),
      useDarkMode: json['useDarkMode'] as bool?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? true,
      maxDistanceKm:
          json['maxDistanceKm'] as int? ?? AppConstants.defaultDistanceKm,
      // v0.10.0: 18-65 wie im Konstruktor. Vorher stand hier 16-99 -
      // der ausJson-Pfad hat damit die Server-Vorgabe wieder
      // überschrieben, sobald der lokale Stand fehlte.
      ageRangeMin: json['ageRangeMin'] as int? ?? 18,
      ageRangeMax: json['ageRangeMax'] as int? ?? 65,
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
      micDisclosureAccepted: json['micDisclosureAccepted'] as bool? ?? false,
      cameraDisclosureAccepted:
          json['cameraDisclosureAccepted'] as bool? ?? false,
      locationDisclosureAccepted:
          json['locationDisclosureAccepted'] as bool? ?? false,
      themeName: json['themeName'] as String? ?? 'classic',
      paused: json['paused'] as bool? ?? false,
      habitsDealbreaker: json['habitsDealbreaker'] as bool? ?? false,
      contextIcebreakerEnabled:
          json['contextIcebreakerEnabled'] as bool? ?? true,
      chatBackground: json['chatBackground'] as String? ?? 'none',
      chatBackgroundPath: json['chatBackgroundPath'] as String?,
      signupWelcomeSeen: json['signupWelcomeSeen'] as bool? ?? false,
      datingSafetyEducationCompleted:
          json['datingSafetyEducationCompleted'] as bool? ?? false,
      chatBackgroundSeen: json['chatBackgroundSeen'] as bool? ?? false,
      ruhemodusBis: dateOf(json, ['ruhemodusBis']),
      // Fehlende Schlüssel (alte Installation) gelten als "aus" -
      // das ist die datenschutzfreundliche Richtung.
      showDistance: json['showDistance'] as bool? ?? false,
      transitShowName: json['transitShowName'] as bool? ?? true,
      transitShowNameSet: json['transitShowNameSet'] as bool? ?? false,
      // NUTZERWUNSCH (22.11.2026): Fehlende Schlüssel (alte
      // Installation) gelten als "an" - das war das bisherige Verhalten.
      showMusicLiked: json['showMusicLiked'] as bool? ?? true,
      showMusicDisliked: json['showMusicDisliked'] as bool? ?? true,
      showFavoriteSong: json['showFavoriteSong'] as bool? ?? true,
      showFavoriteBand: json['showFavoriteBand'] as bool? ?? true,
      showHabitsSmoking: json['showHabitsSmoking'] as bool? ?? true,
      showHabitsAlcohol: json['showHabitsAlcohol'] as bool? ?? true,
      showHabitsDrugs: json['showHabitsDrugs'] as bool? ?? true,
      // "Nachricht überdenken" (26.11.2026): Fehlt der Schlüssel (alte
      // Installation), wird nicht nachgefragt.
      nachrichtPruefModus: json['nachrichtPruefModus'] as String? ?? 'aus',
      nachrichtPruefSchwelle:
          (json['nachrichtPruefSchwelle'] as num?)?.toInt() ?? 250,
      nachrichtPruefAusnahmen:
          (json['nachrichtPruefAusnahmen'] as Map?)?.map(
            (k, v) => MapEntry('$k', '$v'),
          ) ??
          const <String, String>{},
      // Die Tastatur (0.11.0): fehlende Schlüssel bedeuten "wie App".
      tastaturBelegung: json['tastaturBelegung'] as String? ?? 'wieApp',
      tastaturStil: json['tastaturStil'] as String? ?? 'wieApp',
      tastaturFarbe: (json['tastaturFarbe'] as num?)?.toInt(),
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
    'locationDisclosureAccepted': locationDisclosureAccepted,
    'themeName': themeName,
    'paused': paused,
    'habitsDealbreaker': habitsDealbreaker,
    'contextIcebreakerEnabled': contextIcebreakerEnabled,
    'chatBackground': chatBackground,
    'chatBackgroundPath': chatBackgroundPath,
    'signupWelcomeSeen': signupWelcomeSeen,
    'datingSafetyEducationCompleted': datingSafetyEducationCompleted,
    'chatBackgroundSeen': chatBackgroundSeen,
    'ruhemodusBis': ruhemodusBis?.toIso8601String(),
    'showDistance': showDistance,
    'transitShowName': transitShowName,
    'transitShowNameSet': transitShowNameSet,
    'showMusicLiked': showMusicLiked,
    'showMusicDisliked': showMusicDisliked,
    'showFavoriteSong': showFavoriteSong,
    'showFavoriteBand': showFavoriteBand,
    'showHabitsSmoking': showHabitsSmoking,
    'showHabitsAlcohol': showHabitsAlcohol,
    'showHabitsDrugs': showHabitsDrugs,
    'nachrichtPruefModus': nachrichtPruefModus,
    'nachrichtPruefSchwelle': nachrichtPruefSchwelle,
    'nachrichtPruefAusnahmen': nachrichtPruefAusnahmen,
    'tastaturBelegung': tastaturBelegung,
    'tastaturStil': tastaturStil,
    'tastaturFarbe': tastaturFarbe,
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

  /// Sentinel für [tastaturFarbe]: null bedeutet "Farbe löschen"
  /// (zurück auf keine eigene Farbe).
  static const _tastaturFarbeUnset = Object();

  /// Sentinel für [ruhemodusBis]: null bedeutet "der Ruhemodus ist
  /// vorbei" (der Nutzer hat ihn beendet).
  static const _ruhemodusBisUnset = Object();

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
    bool? locationDisclosureAccepted,
    String? themeName,
    bool? paused,
    bool? habitsDealbreaker,
    bool? contextIcebreakerEnabled,
    String? chatBackground,
    Object? chatBackgroundPath = _chatBackgroundPathUnset,
    bool? signupWelcomeSeen,
    bool? datingSafetyEducationCompleted,
    bool? chatBackgroundSeen,
    bool? showDistance,
    bool? transitShowName,
    bool? transitShowNameSet,
    bool? showMusicLiked,
    bool? showMusicDisliked,
    bool? showFavoriteSong,
    bool? showFavoriteBand,
    bool? showHabitsSmoking,
    bool? showHabitsAlcohol,
    bool? showHabitsDrugs,
    String? nachrichtPruefModus,
    int? nachrichtPruefSchwelle,
    Map<String, String>? nachrichtPruefAusnahmen,
    String? tastaturBelegung,
    String? tastaturStil,
    Object? tastaturFarbe = _tastaturFarbeUnset,
    Object? ruhemodusBis = _ruhemodusBisUnset,
  }) {
    return AppSettings(
      // Blind Mode ist fest AN - der übergebene Wert wird
      // bewusst ignoriert (NUTZERWUNSCH 01.11.2026).
      blindModeEnabled: true,
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
      micDisclosureAccepted:
          micDisclosureAccepted ?? this.micDisclosureAccepted,
      cameraDisclosureAccepted:
          cameraDisclosureAccepted ?? this.cameraDisclosureAccepted,
      locationDisclosureAccepted:
          locationDisclosureAccepted ?? this.locationDisclosureAccepted,
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
      datingSafetyEducationCompleted:
          datingSafetyEducationCompleted ?? this.datingSafetyEducationCompleted,
      chatBackgroundSeen: chatBackgroundSeen ?? this.chatBackgroundSeen,
      ruhemodusBis: identical(ruhemodusBis, _ruhemodusBisUnset)
          ? this.ruhemodusBis
          : ruhemodusBis as DateTime?,
      showDistance: showDistance ?? this.showDistance,
      transitShowName: transitShowName ?? this.transitShowName,
      transitShowNameSet: transitShowNameSet ?? this.transitShowNameSet,
      showMusicLiked: showMusicLiked ?? this.showMusicLiked,
      showMusicDisliked: showMusicDisliked ?? this.showMusicDisliked,
      showFavoriteSong: showFavoriteSong ?? this.showFavoriteSong,
      showFavoriteBand: showFavoriteBand ?? this.showFavoriteBand,
      showHabitsSmoking: showHabitsSmoking ?? this.showHabitsSmoking,
      showHabitsAlcohol: showHabitsAlcohol ?? this.showHabitsAlcohol,
      showHabitsDrugs: showHabitsDrugs ?? this.showHabitsDrugs,
      nachrichtPruefModus: nachrichtPruefModus ?? this.nachrichtPruefModus,
      nachrichtPruefSchwelle:
          nachrichtPruefSchwelle ?? this.nachrichtPruefSchwelle,
      nachrichtPruefAusnahmen:
          nachrichtPruefAusnahmen ?? this.nachrichtPruefAusnahmen,
      tastaturBelegung: tastaturBelegung ?? this.tastaturBelegung,
      tastaturStil: tastaturStil ?? this.tastaturStil,
      tastaturFarbe: identical(tastaturFarbe, _tastaturFarbeUnset)
          ? this.tastaturFarbe
          : tastaturFarbe as int?,
    );
  }
}
