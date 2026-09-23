import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wisp/services/auth_exception.dart';

/// App-Sprache (Deutsch/Englisch). Default: Deutsch. Der Startwert wird
/// in main() aus SharedPreferences als Override gesetzt; [saveLocale]
/// aktualisiert State + Persistenz.
final localeProvider = StateProvider<Locale>((ref) {
  return const Locale('de');
});

Future<void> saveLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_locale', locale.languageCode);
}

/// Zentrale Übersetzungen für die aktuell vollständig zweisprachig
/// ausgelieferten Oberflächen (Login/Registrieren, Einstellungen,
/// Navigation, Home, zentrale Dialoge). Nicht abgedeckte Keys fallen
/// auf Deutsch zurück.
class L10n {
  L10n._();

  static Locale localeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_L10nScope>()?.locale ??
      const Locale('de');

  static String t(BuildContext context, String key) {
    final locale = localeOf(context).languageCode;
    return _strings[locale]?[key] ?? _strings['de']![key] ?? key;
  }

  /// Wie [t], ersetzt aber {platzhalter} im Text, z. B.
  /// tf(context, 'profile.edit.maxDistance', {'km': '42'}).
  static String tf(
    BuildContext context,
    String key,
    Map<String, String> params,
  ) {
    var s = t(context, key);
    params.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    return s;
  }

  /// Zeigt eine Service-Exception zweisprachig an: Services haben keinen
  /// BuildContext, liefern aber optional einen L10n-Key
  /// ([AppException.messageKey]) mit {platzhalter}-Params mit.
  /// Fallback: die deutsche Klartext-Message.
  static String exc(BuildContext context, Object e) {
    if (e is AppException) {
      final key = e.messageKey;
      if (key != null && key.isNotEmpty) {
        var s = t(context, key);
        if (s != key) {
          e.params.forEach((k, v) {
            s = s.replaceAll('{$k}', v);
          });
          return s;
        }
      }
      return e.message;
    }
    return e.toString();
  }
}

/// InheritedWidget, das die aktive Locale an [L10n.t] verteilt.
class _L10nScope extends InheritedWidget {
  const _L10nScope({required this.locale, required super.child});

  final Locale locale;

  @override
  bool updateShouldNotify(_L10nScope oldWidget) => oldWidget.locale != locale;
}

/// Wrappt [child] und stellt die aktive Locale für [L10n.t] bereit.
class L10nScope extends ConsumerWidget {
  const L10nScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return _L10nScope(locale: locale, child: child);
  }
}

const Map<String, Map<String, String>> _strings = {
  'de': {
    // Auth
    'auth.login': 'Einloggen',
    'auth.lockedOut':
        'Zu viele fehlgeschlagene Anmeldeversuche. Bitte warte {minutes} '
        'Minute(n) und versuche es dann erneut.',
    'auth.lockedOut10':
        'Zu viele fehlgeschlagene Anmeldeversuche. Die Anmeldung ist für '
        '{minutes} Minuten gesperrt.',
    'auth.register': 'Registrieren',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Passwort',
    'auth.passwordHint': 'Mindestens 8 Zeichen',
    'auth.forgot': 'Passwort vergessen?',
    'auth.keepLoggedIn': 'Angemeldet bleiben',
    'auth.keepLoggedInSub':
        'Automatisch eingeloggt bleiben, wenn du die App schließt (empfohlen).',
    'mfa.title': 'Sicherheitscode',
    'mfa.body': 'Gib den Code aus deiner Authenticator-App ein',
    'mfa.paste': 'Einfügen',
    'mfa.setupTitle': 'Konto absichern',
    'mfa.activeTitle': '2FA ist aktiviert',
    'mfa.activeBody':
        'Dein Konto ist mit einer Authenticator-App geschützt. Bei der '
        'Anmeldung wird zusätzlich zum Passwort der aktuelle Code abgefragt.',
    'mfa.introTitle': 'Schütze dein Konto mit einem zweiten Faktor',
    'mfa.introBody':
        'Mit einer Authenticator-App (z. B. Google Authenticator, Aegis '
        'oder 2FAS) erstellst du bei jedem Login einen einmaligen Code. '
        'Nur mit diesem Code kann sich jemand in dein Konto einloggen, '
        'auch wenn dein Passwort gestohlen wurde.',
    'mfa.introSkip':
        'Du kannst diesen Schritt überspringen und die Einrichtung '
        'jederzeit nachholen.',
    'mfa.setupScan': 'Mit Authenticator-App einrichten',
    'mfa.setupLater': 'Später erinnern',
    'mfa.scanStep': '1. QR-Code scannen',
    'mfa.scanBody':
        'Öffne deine Authenticator-App (z. B. Google Authenticator, '
        'Aegis oder 2FAS) und füge den Eintrag per QR-Scan hinzu.',
    'mfa.manualKey':
        'Kein Scan möglich? Trage diesen Schlüssel manuell ein '
        '(antippen zum Kopieren):',
    'mfa.copied': 'Schlüssel kopiert. Wird in 30 s automatisch gelöscht.',
    'mfa.setupNext': 'Weiter: Code eingeben',
    'mfa.setupNextHint':
        'Danach gibst du den 6-stelligen Code aus deiner '
        'Authenticator-App einmal ein, um die Einrichtung zu bestätigen.',
    'mfa.confirmStep': '2. Code eingeben',
    'mfa.confirmBody':
        'Gib den aktuellen 6-stelligen Code aus deiner '
        'Authenticator-App ein, um die Einrichtung zu bestätigen:',
    'mfa.setupBackQr': 'Zurück zum QR-Code',
    'mfa.doneTitle': 'Zwei-Faktor-Schutz aktiv!',
    'mfa.doneBody':
        'Ab jetzt wirst du bei jedem Login nach dem Code aus deiner '
        'Authenticator-App gefragt.',
    'auth.toRegister': 'Noch kein Konto? Registrieren',
    'auth.toLogin': 'Schon ein Konto? Einloggen',
    'auth.passkey': 'Mit Passkey anmelden',
    'auth.passkeyCreate': 'Passkey erstellen',
    'auth.captcha': 'Sicherheitscheck',
    'auth.registerTitle': 'Konto erstellen',
    'auth.welcomeBack': 'Willkommen zurück',
    'auth.birthDate': 'Geburtsdatum',
    'auth.birthDateHint': 'TT. MM. JJJJ',
    'auth.birthDatePick': 'Bitte auswählen',
    'auth.birthDateMissing': 'Bitte wähle dein Geburtsdatum.',
    'auth.ageConfirmTitle': 'Mein Geburtsdatum ist korrekt',
    'auth.ageConfirmSub':
        'Falsche Altersangaben gefährden andere, besonders junge Nutzer, '
        'und führen zum dauerhaften Ausschluss.',
    'auth.ageConfirmRequired':
        'Bitte bestätige die Richtigkeit deines Geburtsdatums.',
    'auth.liabilityNote':
        'Hinweis: Wisp prüft Angaben nicht lückenlos. Verlass dich nie '
        'allein auf Profilangaben, triff dich nur an öffentlichen Orten '
        'und melde Verdacht auf falsches Alter sofort.',
    'email.resent':
        'Bestätigungsemail wurde erneut gesendet. Bitte prüfe auch '
        'deinen Spamordner.',
    'email.rateLimited': 'Zu viele Anfragen. Bitte warte einen Moment.',
    'email.confirmed': 'Email bestätigt!',
    'email.waiting': 'Wir warten auf die Bestätigung...',
    'email.demoContinue': 'In der Demo kannst du direkt fortfahren.',
    'email.title': 'Email bestätigen',
    'email.heading': 'Bestätige deine Emailadresse',
    'email.body':
        'Wir haben dir eine Bestätigungsemail gesendet. Bitte klicke auf '
        'den Link in der Email, um deinen Account zu aktivieren. Danach '
        'geht es automatisch weiter.',
    'email.sending': 'Wird gesendet...',
    'email.sent': 'Email gesendet',
    'email.cooldown': 'Erneut senden in {s}s',
    'email.resend': 'Bestätigungsmail erneut senden',
    'email.continueBtn': 'Ich habe die Mail bestätigt: Weiter',
    'email.dnsHint':
        'Kommt der Link in der Email nicht durch? Das kann an aktiven DNS '
        'Filtern oder VPNs (z. B. DNS Forge) liegen, die Tracking Links '
        'blockieren. Deaktiviere den Filter vorübergehend und klicke den '
        'Link erneut. Nach der Bestätigung kannst du ihn wieder aktivieren.',
    'email.reportIssue': 'Problem melden',
    'email.logout': 'Abmelden',
    'email.cancel': 'Registrierung abbrechen',
    'email.cancelTitle': 'Registrierung abbrechen?',
    'email.cancelBody':
        'Dein noch unbestätigter Account wird dabei in Supabase '
        'gelöscht. Bereits gemachte Angaben gehen verloren.',
    'email.cancelConfirm': 'Ja, Konto löschen',
    'email.cancelKeep': 'Doch fortfahren',
    'email.deleted': 'Registrierung abgebrochen, Konto gelöscht.',
    'email.cancelExpired':
        'Anmeldedaten abgelaufen - melde dich einfach erneut an, die '
        'Bestätigung wird dann erneut gesendet.',
    'email.deleteFailed': 'Löschen fehlgeschlagen: {error}',
    'forgot.title': 'Passwort vergessen',
    'forgot.heading': 'Passwort zurücksetzen',
    'forgot.body':
        'Gib deine Emailadresse ein. Wir senden dir einen Link, um dein '
        'Passwort zurückzusetzen.',
    'forgot.sentBody':
        'Wenn ein Konto mit dieser Email existiert, haben wir einen Link '
        'zum Zurücksetzen gesendet.',
    'forgot.sentBox':
        'Falls ein Konto mit dieser Email existiert, wurde ein Link '
        'gesendet.',
    'forgot.email': 'Email',
    'forgot.sending': 'Sende …',
    'forgot.toLogin': 'Zurück zum Login',
    'forgot.sendLink': 'Link senden',
    'reset.title': 'Neues Passwort',
    'reset.doneTitle': 'Passwort geändert',
    'reset.doneBody':
        'Dein neues Passwort wurde gespeichert. Aus Sicherheitsgründen '
        'wurdest du auf allen Geräten abgemeldet. Bitte melde dich neu an.',
    'reset.toLogin': 'Zum Login',
    'reset.heading': 'Neues Passwort festlegen',
    'reset.body':
        'Wähle ein neues Passwort für dein Konto. Es muss mindestens 8 '
        'Zeichen lang sein und Buchstaben und Zahlen enthalten.',
    'reset.newPassword': 'Neues Passwort',
    'reset.repeat': 'Passwort wiederholen',
    'reset.repeatMissing': 'Bitte wiederhole das Passwort',
    'reset.mismatch': 'Die Passwörter stimmen nicht überein.',
    'reset.save': 'Passwort speichern',
    'unban.title': 'Entsperrungsantrag',
    'unban.doneTitle': 'Antrag gesendet',
    'unban.doneBody':
        'Dein Entsperrungsantrag wurde an den Support übermittelt. Wir '
        'prüfen den Fall und melden uns per E-Mail.',
    'unban.heading': 'Konto gesperrt?',
    'unban.body':
        'Diese E-Mail-Adresse ist auf der Plattform gesperrt. Wenn du '
        'glaubst, dass ein Fehler vorliegt, sende einen '
        'Entsperrungsantrag. Wir prüfen den Fall.',
    'unban.email': 'E-Mail-Adresse',
    'unban.emailMissing': 'Bitte gib deine E-Mail-Adresse ein.',
    'unban.emailInvalid': 'Bitte gib eine gültige E-Mail-Adresse ein.',
    'unban.reason': 'Begründung',
    'unban.reasonHint':
        'Erkläre kurz, warum dein Konto entsperrt werden sollte '
        '(mindestens 20 Zeichen).',
    'unban.reasonShort':
        'Bitte gib eine Begründung mit mindestens 20 Zeichen an.',
    'unban.send': 'Antrag senden',
    'unban.backToLogin': 'Zurück zur Anmeldung',
    'auth.gender': 'Geschlecht',
    'gender.male': 'Männlich',
    'gender.maleTrans': 'Männlich (F to M)',
    'gender.female': 'Weiblich',
    'gender.femaleTrans': 'Weiblich (M to F)',
    'gender.diverse': 'Divers',
    'gender.other': 'Eigenes / Anderes',
    'auth.passwordHintStrong':
        'Mindestens 8 Zeichen, mit Groß- und '
        'Kleinbuchstaben, einer Zahl und einem Sonderzeichen',
    'auth.showPassword': 'Passwort anzeigen',
    'auth.hidePassword': 'Passwort verbergen',
    'auth.captchaRegister':
        'Bitte schließe den Sicherheitscheck ab, um '
        'dich zu registrieren.',
    'auth.captchaLogin':
        'Bitte schließe den Sicherheitscheck ab, um dich '
        'anzumelden.',
    'captcha.retry': 'Erneut versuchen',
    'language.german': 'Deutsch',
    'language.english': 'Englisch',
    // Navigation
    'nav.home': 'Aktuelles',
    'nav.discover': 'Entdecken',
    'nav.interests': 'Interessen',
    'nav.profile': 'Profil',
    // Settings (Kern)
    'settings.title': 'Einstellungen',
    'settings.appearance': 'Darstellung',
    'settings.system': 'System',
    'settings.light': 'Hell',
    'settings.dark': 'Dunkel',
    'settings.colors': 'Farbwelt',
    'settings.language': 'Sprache',
    'settings.notifications': 'Benachrichtigungen',
    'settings.push': 'Push Benachrichtigungen',
    'settings.pushEnable': 'Benachrichtigungen aktivieren',
    'settings.pushEnableSub':
        'Nachrichten, Likes, Funken und Event Erinnerungen',
    'settings.notifyMessages': 'Chat Nachrichten',
    'settings.notifyLikes': 'Neue Likes',
    'settings.notifyFunken': 'Neue Funken',
    'settings.notifyFunkenSub': 'Wenn ein Funke entsteht',
    'settings.notifyDatingHour': 'Dating Hour Erinnerung',
    'settings.notifyDatingHourSub': '10 Minuten vor Beginn, wenn du dabei bist',
    'settings.chatSafety': 'Sicherheit im Chat',
    'settings.blur': 'Bilder verpixelt anzeigen',
    'settings.e2e': 'E2E-Identität',
    'settings.backupCreate': 'Backup erstellen',
    'settings.backupRestore': 'Backup wiederherstellen',
    'settings.passkeyDiagnose': 'Passkey-Diagnose',
    'settings.privacyAccount': 'Datenschutz & Account',
    'settings.privacyAccountSub':
        'Gespeicherte Daten, Einwilligungen, Account löschen',
    'settings.pause': 'Profil pausieren',
    'settings.pauseSub':
        'Unsichtbar in Entdecken und Find your Match. Funken und Chats '
        'bleiben bestehen.',
    'settings.pauseActive':
        'Profil ist pausiert und für neue Personen unsichtbar.',
    'settings.pauseConfirmTitle': 'Profil pausieren?',
    'settings.pauseConfirmBody':
        'Dein Profil wird in Entdecken und Find your Match nicht mehr '
        'angezeigt. Bestehende Funken und Chats bleiben bestehen. Du kannst '
        'die Pause jederzeit beenden.',
    'settings.pauseConfirmBtn': 'Pausieren',
    'settings.pauseOn':
        'Profil pausiert. Du bist unsichtbar, bis du die Pause beendest.',
    'settings.pauseOff': 'Pause beendet. Dein Profil ist wieder sichtbar.',
    'settings.visEveryoneSub':
        'Dein Profil erscheint in Entdecken und Find your Match.',
    'settings.visMatchesSub':
        'Nur Personen, mit denen du einen Funken hast, sehen dein Profil.',
    'settings.visHiddenSub':
        'Pausenmodus: unsichtbar für alle neuen Personen. Funken und Chats '
        'bleiben bestehen.',
    'settings.visEveryone': 'Jeder',
    'settings.visMatchesOnly': 'Nur Funken',
    'settings.visHidden': 'Unsichtbar (Pausiert)',
    'mood.happy': 'Glücklich',
    'mood.relaxed': 'Entspannt',
    'mood.adventurous': 'Abenteuerlustig',
    'mood.flirty': 'Flirty',
    'mood.thoughtful': 'Nachdenklich',
    'mood.tired': 'Müde',
    'theme.classic': 'Classic WispDating',
    'theme.ocean': 'Ozean',
    'theme.forest': 'Wald',
    'theme.sunset': 'Sonnenuntergang',
    'theme.lavender': 'Lavendel',
    'theme.slate': 'Schiefer',
    'theme.colorScheme': 'Farbschema',
    'dm.discovery': 'Entdecken',
    'dm.discoveryDesc': 'Profile entdecken, Funken versenden, chatten',
    'dm.findMatch': 'Find your Match',
    'dm.findMatchDesc': 'Vorstellung anhören oder lesen, dann entscheiden',
    'dm.randomChat': 'Zufallschat',
    'dm.randomChatDesc': 'Direkter Text-Chat mit zufällig passender Person',
    'dm.qrScan': 'QR-Code scannen',
    'dm.qrScanDesc': 'Code einer Person scannen und direkt verbinden',
    'dm.datingHour': 'Dating Hour (Event)',
    'dm.datingHourDesc':
        'Samstags 20 bis 21 Uhr: 5-Minuten-Chats mit Entscheidungsphase',
    'dm.transitSpark': 'Transit Spark',
    'dm.transitSparkDesc':
        'Blicke getauscht, sich nicht getraut? Später funken - auch wenn '
        'ihr längst weitergefahren seid.',
    'dm.groupMeet': 'Menschen kennenlernen',
    'dm.groupDirect': 'Direkt verbinden',
    'dm.groupOnTheGo': 'Unterwegs',
    'dm.pickHint': 'Wähle einen Modus, um neue Leute zu entdecken:',
    'common.new': 'NEU',
    'transit.title': 'Transit Spark',
    'transit.start': 'Radar aktivieren',
    'transit.stop': 'Radar stoppen',
    'transit.active':
        'Radar aktiv - du bist sichtbar für Wisp-Geräte in der Nähe.',
    'transit.inactive': 'Radar aus. Aktiviere es, wenn du unterwegs bist.',
    'transit.remaining': 'Noch {time} aktiv',
    'transit.seenCount': '{count} Wisp-Geräte in Reichweite gesehen.',
    'transit.exchanged': 'Blicke getauscht',
    'transit.modeLabel': 'Wie weit soll die Erkennung reichen?',
    'transit.mode.transit': 'Normal',
    'transit.mode.convention': 'Nur direkt daneben',
    'transit.modeHint':
        'Messe-Modus: nur starke Signale zählen (echter Sichtkontakt in '
        'dichten Umgebungen).',
    'transit.sheetTitle': 'Wer war das?',
    'transit.sheetHint':
        'Wähle 2-5 Merkmale, die dir an der Person aufgefallen sind - '
        'die Auswahl schärft das Matching.',
    'transit.sheetSend': 'Funken',
    'transit.tag.black_hoodie': 'Hoodie (schwarz)',
    'transit.tag.tshirt': 'T-Shirt',
    'transit.tag.sweater': 'Pullover',
    'transit.tag.shorts': 'Kurze Hose',
    'transit.tag.pants': 'Lange Hose',
    'transit.tag.sporty': 'Sportliche Kleidung',
    'dm.appbarTitle': 'Entdeckungsmodus wählen',
    'fym.introSaved': 'Vorstellung gespeichert. Viel Spaß beim Kennenlernen!',
    'setup.appbarTitle': 'Einstellungen & Privatsphäre',
    'setup.filterTitle': 'Filter & Präferenzen',
    'setup.filterSub': 'Wen möchtest du kennenlernen?',
    'setup.openAll': 'Offen für alles',
    'setup.photoTooltip': 'Profilbild wählen',
    'setup.pleasePick': 'Bitte wählen',
    'setup.locationDone': 'Standort erkannt und übernommen (GPS-Koordinaten).',
    'setup.passkeyDone':
        'Passkey eingerichtet. Du kannst dich künftig damit anmelden.',
    // Erst-Einrichtung als Interview (Wisp-Fragen-Bubbles)
    'setupq.visibility':
        'Wie privat magst du bleiben, und wie soll die App aussehen?',
    // Setup: Dialoge, Validierung, Status
    'setup.abortTitle': 'Einrichtung abbrechen?',
    'setup.abortBody':
        'Möchtest du die Einrichtung wirklich abbrechen? Deine bisherigen '
        'Angaben werden gespeichert.',
    'setup.abortContinue': 'Weiter machen',
    'setup.hintBio': 'Bitte schreibe eine kurze Bio (Über mich).',
    'setup.hintInterests': 'Bitte wähle mindestens ein Interesse.',
    'setup.hintIntro':
        'Deine Vorstellung braucht Text UND Audio. Andere sollen dich '
        'kennenlernen, bevor sie dein Foto sehen.',
    'setup.stepOf': 'Schritt {n} von {of}',
    'setup.flagsWarn':
        'Hinweis: Der Einrichtungs-Stand konnte nicht auf dem Server '
        'gesichert werden. Die Einrichtung erscheint beim nächsten Login '
        'möglicherweise erneut.',
    'setup.locationDetectFail':
        'Standort konnte nicht ermittelt werden. Bitte gib ihn manuell ein '
        'oder erlaube den Zugriff.',
    'setup.locationSuspicious':
        'Hinweis: Dieser Standort weicht deutlich von deinen bisherigen '
        'Standorten auf diesem Gerät ab. Falls das stimmt, wähle ihn '
        'trotzdem - andernfalls gib deinen Ort bitte manuell ein.',
    'setup.locationError': 'Fehler bei der Standortermittlung: {error}',
    'setup.locationTooFar':
        'Der Ort liegt mehr als 15 km von deinem aktuellen Standort entfernt.',
    // Setup: Seiten-Inhalte
    'setupp.visibilitySub':
        'Wer darf dein Profil sehen? Wie soll die App aussehen?',
    'setupp.appearance': 'Darstellung',
    'setupp.systemTheme': 'System',
    'setupp.lightTheme': 'Hell',
    'setupp.darkTheme': 'Dunkel',
    'setupp.colorWorld': 'Farbwelt',
    'setupp.lookingFor': 'Ich suche',
    'setupp.relType': 'Beziehungsart',
    'setupp.distance': 'Entfernung',
    'setupp.filterLabel': 'Filter',
    'setupp.maxDistance': 'Maximale Entfernung: {km} km',
    'setupp.stateLabel': 'Bundesland',
    'setupp.stateHint': 'z. B. Bayern',
    'setupp.germanyNote': 'Es werden Profile aus ganz Deutschland angezeigt.',
    'setupp.location': 'Standort',
    'setupp.locationLabel': 'Dein Standort / Stadt',
    'setupp.locationHint': 'z. B. Berlin',
    'setupp.locationGps': 'Standort erkennen (GPS)',
    'setupp.bioLabel': 'Über mich (Bio)',
    'setupp.bioHint': 'z. B. Hobbys, was dir wichtig ist',
    'setupp.stateOptional': 'Bundesland (optional)',
    'setupp.profileSub':
        'Ein Bild, ein paar Worte über dich und deine Interessen helfen '
        'anderen, dich kennenzulernen. Alles optional und später änderbar.',
    'setupp.photoDone': 'Profilbild hochgeladen.',
    'setupp.photoFail':
        'Upload fehlgeschlagen. Du kannst das Bild jederzeit später im '
        'Profil festlegen.',
    'setupp.introSub':
        'Erzähl von dir, als Text und gesprochen. Beides wird anderen '
        'gezeigt, bevor sie dein Foto sehen. Du kannst diesen Schritt auch '
        'überspringen.',
    'setupp.habitsSub':
        'Wie stehst du zu Rauchen, Alkohol und Drogen? Diese Angaben '
        'beeinflussen, wen du bei "Find your Match" siehst.',
    'setupp.habitsHint':
        'Es werden nur Personen gezeigt, die maximal so viel konsumieren '
        'wie du. Du kannst das später in den Einstellungen oder im Profil '
        'ändern.',
    'setupp.passkeySub':
        'Melde dich künftig ohne Passwort an, per Fingerabdruck oder '
        'Gesicht. Optional, du kannst diesen Schritt überspringen.',
    'setupp.passkeyBody':
        'Ein Passkey ist die sicherste und bequemste Anmeldeart: Kein '
        'Passwort, das du merken oder vergessen kannst, und schwerer zu '
        'stehlen als ein Passwort.',
    'setupp.passkeyDone': 'Passkey eingerichtet',
    'setupp.passkeyStart': 'Passkey jetzt einrichten',
    'setupp.mfaActive':
        'Zwei-Faktor-Schutz ist aktiv. Bei jedem Login wirst du nach dem '
        'Code aus deiner Authenticator-App gefragt.',
    'setupp.mfaBody':
        'Ein zweiter Faktor schützt dein Konto, selbst wenn dein Passwort '
        'gestohlen wird. Du brauchst eine Authenticator-App (z. B. Google '
        'Authenticator, Aegis oder 2FAS).',
    'setupp.mfaDone': '2FA eingerichtet',
    'setupp.mfaStart': 'Jetzt einrichten',
    'setupp.laterHint':
        'Du kannst die Einrichtung jederzeit später in den Einstellungen '
        'nachholen.',
    'setupp.guidelinesSub':
        'Bitte akzeptiere die Regeln der App, um fortzufahren.',
    'setupp.guidelinesIntroTitle': 'Wertegemeinschaft',
    'setupp.guidelinesIntroBody':
        'Diese App lebt von einem respektvollen, wertschätzenden Umgang '
        'miteinander, unabhängig von Herkunft, Geschlecht, Religion oder '
        'Lebensentwurf.',
    'setupp.guidelinesBan':
        'Verstöße führen zu Verwarnung bis zur dauerhaften Sperrung.',
    'setupp.guidelinesWarn':
        'Bei Verstoß kann der Zugang dauerhaft gesperrt werden.',
    'setupp.finish': "Akzeptieren & los geht's",
    'setupp.changeLater':
        'Diese Einstellungen kannst du später jederzeit in den '
        'Einstellungen ändern.',
    // Interessen-Tab
    'interests.title': 'Interessen',
    'interests.tabSent': 'Gesendet',
    'interests.tabReceived': 'Erhalten',
    'interests.tabSparks': 'Funken',
    'interests.emptySentTitle': 'Du hast noch niemanden geliked',
    'interests.emptySentBody':
        'Lerne Leute über ihre Vorstellung kennen ("Find your Match") oder '
        'swipe blind durch Profile.',
    'interests.emptyReceivedTitle': 'Noch keine erhaltenen Likes',
    'interests.emptyReceivedBody':
        'Sobald dich jemand über seine Vorstellung mag, erscheint er hier '
        'und du entscheidest über Funke oder Ablehnung.',
    'interests.emptySparksTitle': 'Noch keine Funken',
    'interests.emptySparksBody':
        'Bestätige erhaltene Likes, um Funken zu bekommen. Danach kannst du '
        'direkt chatten und optional das Kennenlern-Quiz für das Foto '
        'spielen.',
    'interests.likedYou': 'Hat dich geliked',
    'interests.decline': 'Ablehnen',
    'interests.sparkAccepted':
        'Ein Funke mit {name} ist entstanden! Ihr könnt direkt chatten.',
    'interests.likeDeclined': 'Like von {name} abgelehnt.',
    'interests.photoUnlocked': 'Foto freigeschaltet',
    'interests.quizPending': 'Foto-Freischaltung: Kennenlern-Quiz',
    'interests.noBio': 'Keine Bio',
    'interests.manage': 'Verwalten',
    'interests.hideSelected': 'Ausblenden ({n})',
    'interests.hiddenCount': '{n} Chat(s) aus der Liste entfernt.',
    'interests.hideFailed':
        '{failed} von {total} konnten nicht entfernt werden. Bitte erneut '
        'versuchen.',
    'interests.resparkBtn': 'Re-Funke',
    'interests.resparkFailed':
        'Re-Funke fehlgeschlagen. Bitte erneut versuchen.',
    'interests.cooledTitle': 'Erschlossene Funken',
    'interests.cooledSub':
        'Ruhig beendet - auch automatisch nach 3 Tagen ohne Nachricht. '
        'Der Chat bleibt erhalten, jederzeit wieder entzündbar',
    'interests.savedTitle': 'Gespeicherte Profile',
    'interests.savedSub':
        'Lokal gespeichert (max. 5) - zum Nachschreiben, wenn du unterwegs '
        'kein Internet hattest',
    'interests.savedTileSub': 'Gespeichert - später anschreiben',
    'interests.deleteSavedTitle': 'Gespeichertes Profil entfernen?',
    'interests.deleteSavedBody':
        '{name} wird lokal gelöscht. Der zugehörige Chat-Verlauf geht damit '
        'verloren.',
    // QR-Flow
    'qr.menuTitle': 'QR Code',
    'qr.choiceTitle': 'Was möchtest du tun?',
    'qr.showMine': 'Meinen QR Code zeigen',
    'qr.showMineBtn': 'Meinen eigenen Code anzeigen',
    'qr.scanTitle': 'QR Code scannen',
    'qr.enterCode': 'Code eingeben',
    'qr.enterCodeSub': 'Den 8 stelligen Code manuell eintippen',
    'qr.enterCodeHint':
        'Gib den 8 stelligen Code der Person ein,\ndie du finden möchtest.',
    'qr.codeHint': 'z. B. A1B2C3D4',
    'qr.searchUser': 'Nutzer suchen',
    'qr.ownCode': 'Das ist dein eigener Code!',
    'qr.noUserFound': 'Kein Nutzer mit diesem Code gefunden.',
    // QR-Scan = erstmal Like (nicht direkt ein Chat)
    'qr.likeSent':
        'Like gesendet! Sobald die Person annimmt, entsteht euer Funke '
        'und damit der Chat.',
    'qr.likeFailed': 'Like konnte nicht gesendet werden: {error}',
    'qr.invalidCode':
        'Dieser QR-Code ist kein Wisp-Profilcode. Bitte scanne den '
        'persönlichen QR-Code aus der App.',
    'qr.savedOffline':
        'Kein Internet - Profil lokal gespeichert. Du kannst die Person '
        'später anschreiben ("Gespeicherte Profile").',
    'setupq.filter': 'Wonach soll Wisp jemanden für dich suchen?',
    'setupq.profile':
        'Was macht dich aus? Ein Bild, ein paar Worte, deine Interessen.',
    'setupq.intro': 'Wie klingst du? Erzähl von dir, als Text und gesprochen.',
    'setupq.habits': 'Wie stehst du zu Rauchen, Alkohol und Drogen?',
    'setupq.passkey':
        'Magst du dein Konto mit einem Passkey absichern? Geht schnell.',
    'setupq.mfa': 'Magst du zusätzlich einen zweiten Faktor einrichten?',
    'setupq.guidelines':
        'Magst du unsere Wertegemeinschaft und ihre Regeln akzeptieren?',
    // Passkey-Einrichtung in der Erst-Einrichtung
    'setup.passkeySetupFailed':
        'Passkey-Setup fehlgeschlagen oder abgebrochen. Du kannst es '
        'später jederzeit in den Einstellungen nachholen.',
    // Sicherheitshinweis vor dem Abschluss
    'setup.nudgeTitle': 'Dringend empfohlen',
    'setup.nudgeBody':
        'Sichere dein Konto jetzt mit einem Passkey oder der '
        'Zwei-Faktor-Authentisierung. Ohne zweiten Faktor kann jeder '
        'mit deinem Passwort dein Konto übernehmen. Bei einer '
        'Dating-App besonders heikel.',
    'setup.nudgeSkip': 'Trotzdem fortfahren',
    'setup.nudgeMfa': '2FA einrichten',
    'setup.nudgePasskey': 'Passkey einrichten',
    'transit.tag.hoodie': 'Hoodie',
    'transit.tag.top': 'Oberteil',
    'transit.colorOptional': 'Farbe (optional)',
    'transit.color.black': 'Schwarz',
    'transit.color.white': 'Weiß',
    'transit.color.grey': 'Grau',
    'transit.color.blue': 'Blau',
    'transit.color.green': 'Grün',
    'transit.color.red': 'Rot',
    'transit.color.yellow': 'Gelb',
    'transit.color.orange': 'Orange',
    'transit.color.pink': 'Pink',
    'transit.color.brown': 'Braun',
    'transit.color.purple': 'Lila',
    'transit.color.teal': 'Türkis',
    'transit.self.title': 'Wie siehst du gerade aus?',
    'transit.self.hint':
        'Wähle 2-5 Merkmale zu dir selbst - nur so können dich andere '
        'über Transit Spark finden. Jeden Tag neu angeben.',
    'transit.modeDesc.transit':
        'Übliche Reichweite: Begegnungen im Vorbeigehen, z. B. auf der '
        'Straße als Fußgänger, im Zug oder im Café.',
    'transit.modeDesc.convention':
        'Eng begrenzt: nur Personen unmittelbar neben dir zählen. Ideal '
        'für volle Messen, Konzerte und Events.',
    'transit.tag.jacket': 'Jacke',
    'transit.tag.cap': 'Cap',
    'transit.tag.glasses': 'Brille',
    'transit.tag.headphones': 'Kopfhörer',
    'transit.tag.backpack': 'Rucksack',
    'transit.tag.tote_bag': 'Tote Bag',
    'transit.tag.lanyard': 'Lanyard / Badge',
    'transit.tag.scarf': 'Schal',
    'transit.tag.colorful_top': 'Auffälliges Oberteil',
    'transit.greetSection': 'Gesehene Geräte in dieser Session',
    'transit.greet': 'Grüßen',
    'transit.justNow': 'gerade eben',
    'transit.minutesAgo': 'vor {count} Min.',
    'transit.hoursAgo': 'vor {count} Std.',
    'transit.noEncounters': 'Noch keine Geräte in Reichweite gewesen.',
    'transit.pingSheetTitle': 'Einen Gruß senden',
    'transit.pingSheetHint':
        'Einmal pro Begegnung möglich. Die Person entscheidet still, '
        'ob sie antwortet - du erfährst nur von einem Ja.',
    'transit.pingSend': 'Gruß senden',
    'transit.pingSent':
        'Gruß gesendet. 48 Stunden Zeitfenster - mehr '
        'nicht.',
    'transit.pingCustomHint': 'Optional: eine kurze eigene Zeile …',
    'transit.preset.wave': 'Hallo! Ich war gerade eben in deiner Nähe.',
    'transit.preset.again': 'Vielleicht kreuzen sich unsere Wege ja nochmal?',
    'transit.preset.coffee': 'Falls du magst: ein Kaffee in der Nähe?',
    'transit.inboxTitle': 'Grüße für dich',
    'transit.ignore': 'Ausblenden',
    'transit.accept': 'Funke annehmen',
    'transit.locationActiveTitle': 'Standort aktiviert',
    'transit.locationActiveBody':
        'Dein Standort ist jetzt eingeschaltet. Tippe auf "Radar starten", '
        'um direkt mit deinen bereits gewählten Merkmalen zu beginnen - '
        'du musst nichts neu eingeben.',
    'transit.locationActiveBtn': 'Radar starten',
    'transit.matchTitle': 'Funke übergesprungen!',
    'transit.matchBody':
        'Die Person hat denselben Moment gespürt. Schaut in eure Funken - '
        'ihr könnt jetzt chatten.',
    'transit.later': 'Später',
    'transit.openSparks': 'Zu den Funken',
    'transit.startFailed':
        'Radar konnte nicht gestartet werden. Bluetooth an und Berechtigung '
        'erteilen.',
    // Radar-Verlassen (Radar läuft): Stoppen? + Merk-Checkbox
    'transit.exitTitle': 'Radar laufen lassen?',
    'transit.exitBody':
        'Das Radar läuft noch. Du kannst es beim Verlassen der Seite '
        'stoppen oder im Hintergrund weiterlaufen lassen (Fenster läuft '
        'weiter, Funke auch Stunden später möglich).',
    'transit.exitKeep': 'Weiterlaufen lassen',
    'transit.exitStop': 'Radar stoppen',
    'transit.exitRemember': 'Zukünftig automatisch so beibehalten',
    // 2-Stunden-Ruhezeit gesehener Personen (088-Runde)
    'transit.retainedBtn': 'Gesehene Geräte ansehen (2 Stunden)',
    'transit.retainedTitle': 'Gesehene Geräte',
    'transit.retainedHint': 'Die Liste bleibt noch 2 Stunden erhalten.',
    'transit.retainedUntil': 'Die Liste bleibt bis {time} Uhr erhalten.',
    'transit.howTitle': 'Wie funktioniert das?',
    'transit.howBody':
        'Aktiviere das Radar, wenn du unterwegs bist (Zug, Café, Messe). '
        'Dein Gerät tauscht mit anderen Wisp-Geräten in nächster Nähe '
        'anonyme, zufällige Token aus - ohne Namen, ohne Standort, ohne '
        'Fotos. Tippe später auf "Blicke getauscht": Spürt die andere '
        'Person denselben Moment und funkt ebenfalls, entsteht ein Funke.',
    'transit.privacyNote':
        'Tokens sind zufällig, rotieren regelmäßig und verfallen nach '
        '45 Minuten. Gespeichert wird nur, was du aktiv sendest - nichts '
        'verlässt dein Gerät, solange du nicht selbst funkt. Ein Gruß an eine Person braucht deren aktuelles Token - dafür wird bei aktivem Radar dein zufälliges Token (nur dieses) 45 Minuten serverseitig hinterlegt.',
    'transit.teenNote':
        'Unter 18? Du siehst ausschließlich altersseitig kompatible '
        'Nutzer - serverseitig erzwungen.',
    'onboarding.appbarTitle': 'Kurz kennengelernt',
    'onboarding.skipAll': 'Überspringen',
    'onboarding.fillLater': 'Später ausfüllen',
    'onboarding.next': 'Weiter',
    'onboarding.hello.title': 'Hi, ich bin Wisp!',
    'onboarding.hello.body':
        'In den nächsten Minuten richten wir dein Profil zusammen - '
        'als kurzes Gespräch statt Formular. Alles ist überspringbar, '
        'nichts ist falsch.',
    'onboarding.blind.title': 'Persönlichkeit vor Aussehen',
    'onboarding.blind.body':
        'Standardmäßig siehst du zuerst nur Name, Alter, Bio und '
        'Interessen - keine Fotos. So entscheidest du mit dem Kopf, '
        'nicht nur mit den Augen. Jederzeit abschaltbar.',
    'onboarding.connections.title': 'Echte Verbindungen',
    'onboarding.connections.body':
        'Ein Funke entsteht nur, wenn ihr euch beide wählt. Erst dann '
        'werden Fotos freigeschaltet und ihr könnt loschatten - fair '
        'statt oberflächlich.',
    'onboarding.q.photo':
        'Magst du ein Profilbild von dir zeigen? Kein Stress - Fotos '
        'sind bei uns ohnehin erst nach einem Funke sichtbar.',
    'onboarding.photoLater': 'Du kannst später ein Profilbild hochladen.',
    'onboarding.q.music': 'Gibt es einen Song, der dich gerade begleitet?',
    'onboarding.q.musicGenres': 'Welche Musik-Genres magst du?',
    'onboarding.q.musicHint': 'z. B. Lieblingssong …',
    'onboarding.q.bandHint': 'z. B. Lieblingsband oder Künstler …',
    'onboarding.q.birthday':
        'Welcher Stil soll dein Profil an deinem Geburtstag haben?',
    'onboarding.done.title': 'Geschafft - schön, dass du da bist!',
    'onboarding.done.body':
        'Dein Profil steht. Alles kannst du später jederzeit in den '
        'Einstellungen ändern. Viel Spaß beim Entdecken!',
    'welcome.t1': 'Willkommen bei Blind Date',
    'welcome.b1':
        'Hier lernst du Menschen wirklich kennen, bevor du ihr Foto '
        'siehst. Denn am Anfang zählt die Persönlichkeit, nicht das '
        'Aussehen.',
    'welcome.t2': 'Blind Chat und Match',
    'welcome.b2':
        'Chatte zuerst blind und lerne die Person hinter dem Profil '
        'kennen. Erst wenn ihr euch beide gemocht habt, werden die Fotos '
        'freigeschaltet.',
    'welcome.t3': 'Deine Privatsphäre',
    'welcome.b3':
        'Alle Nachrichten und Anrufe sind Ende zu Ende verschlüsselt '
        '(E2E). Niemand außer dir und deinem Gegenüber kann mitlesen, '
        'auch wir nicht. Deine Daten gehören dir.\n\nHochgeladene Fotos '
        'werden automatisch auf unangemessene Inhalte geprüft. Diese '
        'Prüfung erfolgt DSGVO konform und ohne dauerhafte Speicherung '
        'deiner Bilder bei Drittanbietern.',
    'welcome.start': 'Los geht es',
    'pt.title': 'Persönlichkeitstest',
    'pt.doneTitle': 'Test abgeschlossen!',
    'pt.youAre': 'Du bist ein {t}!',
    'pt.heading': 'Lerne deine Persönlichkeit kennen',
    'pt.sub':
        'Beantworte ein paar Fragen, ganz ohne falsch oder richtig. Das '
        'hilft, dir passende Menschen zu zeigen.',
    'pt.finish': 'Test abschließen',
    'pt.saveFailed':
        'Hinweis: Der Einrichtungs-Stand konnte nicht auf dem Server '
        'gesichert werden. Die Einrichtung erscheint beim nächsten Login '
        'möglicherweise erneut.',
    'pt.profileLine': 'Persönlichkeitstest: {label}',
    'pt.q1': 'Wie lädst du neue Energie auf?',
    'pt.q1a': 'Bei Menschen und Aktivität',
    'pt.q1b': 'Bei Ruhe und Zeit für mich',
    'pt.q2': 'Was beschreibt dich besser?',
    'pt.q2a': 'Spontan und flexibel',
    'pt.q2b': 'Geplant und organisiert',
    'pt.q3': 'Bei Entscheidungen vertraust du eher …',
    'pt.q3a': 'dem Bauchgefühl',
    'pt.q3b': 'den Fakten',
    'pt.q4': 'Wie gehst du auf neue Leute zu?',
    'pt.q4a': 'Offen und aktiv',
    'pt.q4b': 'Eher zurückhaltend',
    'pt.q5': 'Du magst es, Dinge …',
    'pt.q5a': 'praktisch und konkret anzugehen',
    'pt.q5b': 'im großen Zusammenhang zu sehen',
    'pt.q6': 'In der Freizeit bevorzugst du …',
    'pt.q6a': 'Abwechslung und Überraschungen',
    'pt.q6b': 'Routine und Vertrautes',
    'pt.q7': 'Konflikte gehst du am liebsten an …',
    'pt.q7a': 'direkt und sachlich',
    'pt.q7b': 'behutsam und harmonisch',
    'pt.q8': 'Du arbeitest gern …',
    'pt.q8a': 'im Team mit anderen',
    'pt.q8b': 'selbstständig allein',
    'pt.q9': 'Beim Kennenlernen zählt für dich zuerst …',
    'pt.q9a': 'was wir gemeinsam erleben',
    'pt.q9b': 'worüber wir reden',
    'pt.q10': 'Pläne für das Wochenende …',
    'pt.q10a': 'stehen meist schon fest',
    'pt.q10b': 'entstehen oft spontan',
    'pt.label.ENFJ': 'Der Mentor',
    'pt.label.ENFP': 'Der Begeisterer',
    'pt.label.ENTJ': 'Der Anführer',
    'pt.label.ENTP': 'Der Erfinder',
    'pt.label.ESFJ': 'Der Versorger',
    'pt.label.ESFP': 'Der Entertainer',
    'pt.label.ESTJ': 'Der Organisator',
    'pt.label.ESTP': 'Der Macher',
    'pt.label.INFJ': 'Der Träumer',
    'pt.label.INFP': 'Der Idealist',
    'pt.label.INTJ': 'Der Stratege',
    'pt.label.INTP': 'Der Denker',
    'pt.label.ISFJ': 'Der Beschützer',
    'pt.label.ISFP': 'Der Künstler',
    'pt.label.ISTJ': 'Der Logiker',
    'pt.label.ISTP': 'Der Handwerker',
    'pt.label.fallback': 'Der Entdecker',
    'pt.desc.ENFJ':
        'Du bist ein natürlicher Mentor, empathisch, organisiert und '
        'inspirierend. Du bringst Menschen zusammen und hilfst ihnen, ihr '
        'Potenzial zu entfalten.',
    'pt.desc.ENFP':
        'Du sprudelst vor Begeisterung und Ideen. Deine Neugier und '
        'Offenheit machen dich zu einem magnetischen Menschen, der andere '
        'mitreißt.',
    'pt.desc.ENTJ':
        'Du führst mit Vision und Entschlossenheit. Strategisches Denken '
        'und natürliche Autorität machen dich zu einem geborenen Anführer.',
    'pt.desc.ENTP':
        'Du liebst intellektuelle Herausforderungen und neue Perspektiven. '
        'Dein Erfindergeist und deine Schlagfertigkeit machen Gespräche '
        'mit dir spannend.',
    'pt.desc.ESFJ':
        'Du sorgst dich aufrichtig um andere und schaffst harmonische '
        'Umgebungen. Deine Zuverlässigkeit und dein Organisationstalent '
        'werden geschätzt.',
    'pt.desc.ESFP':
        'Du lebst im Moment und genießt das Leben in vollen Zügen. Deine '
        'Spontanität und Wärme machen dich zum Mittelpunkt jeder Runde.',
    'pt.desc.ESTJ':
        'Du bringst Struktur in Chaos. Mit klarem Verstand und praktischem '
        'Sinn organisierst du effizient und verlässlich.',
    'pt.desc.ESTP':
        'Du handelst schnell und entschlossen. Herausforderungen nimmst du '
        'direkt an, pragmatisch, energetisch und lösungsorientiert.',
    'pt.desc.INFJ':
        'Du besitzt eine seltene Tiefe und Intuition. Dein Idealismus und '
        'dein Einfühlungsvermögen machen dich zu einem vertrauensvollen '
        'Berater.',
    'pt.desc.INFP':
        'Du folgst deinen Werten mit stiller Entschlossenheit. Deine '
        'Kreativität und Authentizität inspirieren andere, echt zu sein.',
    'pt.desc.INTJ':
        'Du denkst strategisch und langfristig. Deine analytische Schärfe '
        'und dein Wille zur Verbesserung machen dich zu einem visionären '
        'Planer.',
    'pt.desc.INTP':
        'Du durchdringst komplexe Systeme mit neugierigem Verstand. Deine '
        'logische Tiefe und Unabhängigkeit führen zu originellen Lösungen.',
    'pt.desc.ISFJ':
        'Du bist der stille Fels in der Brandung. Fürsorglich, '
        'detailverliebt und loyal, auf dich kann man sich immer verlassen.',
    'pt.desc.ISFP':
        'Du drückst dich durch Taten und Ästhetik aus. Deine Sensibilität '
        'für Schönheit und deine Authentizität machen dich einzigartig.',
    'pt.desc.ISTJ':
        'Du bist das Fundament, auf dem andere bauen. Gewissenhaft, '
        'logisch und beständig, du hältst, was du versprichst.',
    'pt.desc.ISTP':
        'Du meisterst praktische Probleme mit Ruhe und Geschick. Deine '
        'analytische Beobachtung und handwerkliches Talent überzeugen.',
    'pt.desc.fallback':
        'Du entdeckst die Welt mit offener Neugier und findest deinen '
        'eigenen Weg, ganz egal, welcher Typ du bist.',
    'chathist.tileTitle': 'Chat-Verlauf lokal speichern',
    'chathist.mode.off': 'Aus',
    'chathist.mode.cap200': 'An (200 Nachrichten)',
    'chathist.mode.all': 'An (kompletter Verlauf)',
    'chathist.tileSubPrefix': 'Verschlüsselt (AES-256) auf diesem Gerät.',
    'chathist.deleteHint': 'Deaktivieren löscht die Historie.',
    'chathist.dialogTitle': 'Chat-Verlauf speichern',
    'chathist.modeWord': 'Modus:',
    'chat.safetyNumber': 'Sicherheitsnummer',
    'chat.safetyNumberTooltip': 'Sicherheitsnummer (E2E-Verifikation)',
    'chat.safetyChangedTitle': 'Sicherheitsnummer hat sich geändert',
    'chat.safetyChangedBody':
        'Der Verschlüsselungsschlüssel deines Kontakts hat sich geändert. '
        'Das kann nach einer Neuinstallation passieren - oder darauf '
        'hindeuten, dass sich jemand in die Verbindung einschleichen '
        'will.\n\nVergleiche die Sicherheitsnummer über einen zweiten '
        'Kanal (z. B. Anruf oder persönlich), bevor du fortfährst.',
    'transit.btTitle': 'Bluetooth aktivieren',
    'transit.btBody':
        'Für Transit Spark muss Bluetooth eingeschaltet sein. Soll es jetzt aktiviert werden?',
    'transit.btEnable': 'Jetzt aktivieren',
    'transit.locationTitle': 'Standort einschalten',
    'transit.locationBody':
        'Für das Radar muss der Standort-DIENST (GPS) eingeschaltet sein '
        '(Android braucht das für BLE-Scans, besonders Android 11). Die App '
        'kann ihn nicht selbst einschalten - bitte aktiviere ihn in den '
        'Systemeinstellungen und starte das Radar danach erneut.',
    'transit.locationOpen': 'Einstellungen öffnen',
    'transit.permissionTitle': 'Berechtigung nötig',
    'transit.permissionBody':
        'Ohne diese Berechtigung kann das Radar nicht starten. Bitte erteile '
        'sie in den App-Einstellungen und versuche es erneut.',
    'transit.permissionOpen': 'App-Einstellungen öffnen',
    'transit.advertiseBody':
        'Zum Senden deiner Anwesenheit braucht die App die '
        'Bluetooth-Werbungs-Berechtigung (Android 12+). Bitte erteile sie '
        'und starte das Radar erneut.',
    'transit.cleanupTitle': 'Nach Radar ausschalten?',
    'transit.cleanupBody':
        'Radar ist aus. Bluetooth und Standort bleiben an - schalte sie '
        'selbst in den Einstellungen aus, die App darf das nicht.',
    'transit.cleanupToggle': 'Nach Radar erinnern',
    'transit.cleanupToggleSub':
        'Aus. Fragt nach Radar-Ende, ob du Bluetooth/Standort '
        'ausschalten willst.',
    'transit.cleanupOpenLocation': 'Standort',
    'transit.cleanupOpenBluetooth': 'Bluetooth',
    'transit.cleanupLater': 'Später',
    'transit.batteryHint':
        'Aktives Radar braucht Bluetooth und scannt dauerhaft. Das '
        'verbraucht merklich mehr Akku. Stoppe das Radar, wenn du es '
        'nicht mehr brauchst.',
    'transit.self.noteHint':
        'Eigene Ergänzung (optional, z. B. "Rote Mütze, grüner Rucksack") …',
    'transit.sendFailed':
        'Das Signal konnte gerade nicht gesendet werden. Prüfe deine Verbindung und versuche es gleich noch einmal.',
    'transit.stored':
        'Dein Signal ist gespeichert. Spürt die andere Person denselben Moment und funkt ebenfalls, entsteht euer Funke.',
    'chat.safetyChangedCancel': 'Abbrechen',
    'chat.safetyChangedAccept': 'Nummer geprüft: akzeptieren',
    'chat.reconnectStillFailing': 'Verbindung weiterhin fehlgeschlagen.',
    'chat.imageSourcePrompt': 'Wähle eine Quelle für das zu sendende Bild.',
    'chat.identityVerifiedTitle': 'Identität bestätigt',
    'chat.close': 'Schließen',
    'chat.coolSpark': 'Funke kühlen',
    'chat.coolSparkError': 'Funke konnte nicht gekühlt werden: {error}',
    'chat.coolSparkDone':
        'Funke gekühlt. Ihr findet euch unter „Erschlossene Funken" wieder.',
    'chat.backToSparks': 'Zurück zu den Funken',
    'chat.closeImageHint':
        'Schließen (Bild kann danach nicht mehr angesehen werden)',
    'settings.backupChoosePw': 'Backup-Passwort wählen',
    'settings.restoreConfirmTitle': 'Identität wiederherstellen?',
    'settings.backupPasteCode': 'Backup-Code einfügen',
    'settings.restored': 'E2E-Identität wiederhergestellt.',
    'settings.codeInvalid': 'Ungültiger oder abgelaufener Code.',
    'settings.passkeyDeleteTitle': 'Passkey löschen?',
    'settings.delete': 'Löschen',
    'settings.passkeyDeleted': 'Passkey gelöscht.',
    'settings.deleteFailed': 'Löschen fehlgeschlagen.',
    'dh.prefs.setBtn': 'Präferenzen festlegen',
    'dh.nextEventIn': 'Nächstes Event in',
    'dh.searching': 'Suche läuft...',
    'dh.feature.noPhotos':
        'Keine Fotos, keine Bios, nur 5 Minuten echtes Gespräch.',
    'dh.feature.e2eTitle': 'Ende zu Ende verschlüsselt',
    'dh.feature.e2eSub':
        'Niemand außer euch beiden kann eure Nachrichten lesen (Signal-Protokoll).',
    'dh.prefs.savedHint':
        'Präferenzen gespeichert. Deine Teilnahme meldest du über "Ich bin dabei" am Event-Tag an.',
    'report.detailsOptional': 'Zusätzliche Details (optional)',
    'report.checkingTitle': 'Bild wird geprüft…',
    'report.checkingSub': 'Die KI prüft das gemeldete Bild.',
    'report.retryLater': 'Bitte später erneut versuchen.',
    'report.type.harassment': 'Belästigung / Beleidigungen',
    'report.type.default': 'Meldung',
    'report.type.inappropriateContent':
        'Unangemessene Inhalte (Bilder/Nachrichten)',
    'report.type.spam': 'Spam / Werbung',
    'report.type.fakeProfile': 'Fake Profil / Identitätsmissbrauch',
    'report.type.other': 'Sonstiges',
    'report.type.wrongAge': 'Falsches Alter / Alter stimmt nicht',
    'verify.submitFailed':
        'Einreichen fehlgeschlagen. Bitte prüfe deine Internetverbindung '
        'und versuche es erneut.',
    'verify.doneTitle': 'Verifizierung',
    'verify.autoTitle': 'Verifiziert!',
    'verify.autoBody':
        'Die Altersprüfung war unauffällig. Du erhältst sofort das '
        'Verifiziert-Zeichen. Dein Video bleibt für Stichproben erhalten.',
    'verify.pendingTitle': 'Video eingereicht!',
    'verify.pendingBody':
        'Dein Video wurde sicher übermittelt. Der Support prüft es '
        'persönlich, auch dein angegebenes Alter. Sobald es freigegeben '
        'ist, erscheint das Verifiziert-Zeichen in deinem Profil. Dein '
        'Konto bleibt bis dahin voll nutzbar.',
    'verify.toApp': 'Zur App',
    'verify.badge': 'Verifiziert',
    'verify.pendingChip': 'Prüfung läuft',
    'verify.pendingReason.deviation':
        'Warum manuell? Die KI-Schätzung weicht {years} Jahre von deinem '
        'angegebenen Alter ab - der Support gleicht das mit deinem Video ab.',
    'verify.pendingReason.faces':
        'Warum manuell? Es wurde nicht genau ein Gesicht erkannt - '
        'der Support prüft dein Video persönlich.',
    'verify.pendingReason.noAi':
        'Warum manuell? Die Alters-KI konnte auf diesem Gerät nicht '
        'laufen - der Support prüft dein Video persönlich.',
    'verify.pendingReason.noStated':
        'Warum manuell? Dein angegebenes Alter konnte nicht verifiziert '
        'werden - der Support prüft dein Video persönlich.',
    'verify.cleanupTitle': 'Berechtigungen wieder deaktivieren?',
    'verify.cleanupBody':
        'Die Verifizierung ist fertig. Standort, Kamera und Mikrofon '
        'brauchst du dafür nicht mehr - möchtest du sie wieder '
        'deaktivieren?',
    'verify.cleanupLater': 'Später',
    'verify.cleanupLocation': 'Standort',
    'verify.cleanupOpen': 'Kamera & Mikrofon',
    'verify.pendingHint':
        'Dein Video wird vom Support geprüft. Das dauert meist nur '
        'wenige Stunden.',
    'verify.cta': 'Jetzt verifizieren',
    'verify.ctaSub':
        'Kurzes Selbstvideo. Eine lokale KI prüft dein Alter auf dem '
        'Gerät, auffällige Fälle sieht der Support persönlich.',
    'report.confirmed': 'Meldung bestätigt',
    'report.forwardBtn': 'Zur manuellen Prüfung',
    'report.forwardFailed':
        'Weiterleitung fehlgeschlagen. Bitte später erneut versuchen.',
    'interests.likeWithdrawn': 'Like zurückgezogen.',
    'interests.likeWithdrawTooltip': 'Like zurückziehen',
    'interests.sparkConfirmBtn': 'Funke bestätigen',
    'interests.resparkDone': 'Funke mit {name} glüht wieder ✨',
    'interests.matchesSub': 'Bestätigte gegenseitige Likes',
    'qr.openingChat': 'Chat mit {name} wird geöffnet...',
    // Gespeicherte Profile (lokal, max. 5, zum Nachschreiben)
    'qr.limitTitle': 'Maximum erreicht',
    'qr.limitBody':
        'Es sind bereits 5 Profile lokal gespeichert. Entferne in der Liste '
        'zuerst eines, dann scanne erneut.',
    'qr.limitEmpty':
        'Keine gespeicherten Profile mehr vorhanden - '
        'jetzt erneut scannen.',
    'qr.savedDeleteTooltip': 'Gespeichertes Profil entfernen',
    'qr.enterFullCode': 'Bitte gib den vollständigen 8 stelligen Code ein.',
    'qr.resolveFailed': 'Code konnte nicht aufgelöst werden.',
    'qr.shareSub': 'Damit andere dich finden können',
    'qr.scanSub': 'Kamera öffnen und Code einscannen',
    'qr.myCode': 'Mein QR Code',
    'qr.yourCode': 'Dein Code',
    'qr.copyTooltip': 'Code kopieren',
    'qr.copied': 'Code in die Zwischenablage kopiert',
    'qr.shareHint':
        'Teile diesen Code oder den QR Code mit anderen. Sie können dich damit in der App finden und direkt anschreiben.',
    'meet.metTitle': 'Schön, dass ihr euch getroffen habt! 🎉',
    'meet.youWant': 'Du möchtest dich treffen',
    'meet.theyWant': '{name} würde sich gerne mit dir treffen',
    'meet.later': 'Vielleicht später',
    'meet.ideas': 'Ideen für ein erstes Treffen:',
    'home.settingsTooltip': 'Einstellungen & Privatsphäre',
    'home.discoverSub': 'Lerne Leute über ihre Vorstellung kennen.',
    'home.likesSub': 'Likes führen zu Funken, wenn beide sich mögen.',
    'random.partnerLeft':
        'Dein Gesprächspartner hat den Zufallschat verlassen.',
    'random.backToDiscover': 'Zurück zu Entdecken',
    'random.connecting': 'Partner gefunden! Verbinde verschlüsselt…',
    'profile.detail.unavailable': 'Dieses Profil ist derzeit nicht verfügbar.',
    'safety.linkFailed': 'Konnte Link nicht öffnen.',
    'safety.protectOwnImages': 'Eigene Bilder schützen',
    'safety.protectOwnImagesBody':
        'Bilder eingehender Nachrichten sind standardmäßig verpixelt '
        '(Einstellungen - Sicherheit im Chat). Eigene Fotos bleiben bis '
        'zum gegenseitigen Quiz-Erfolg grundsätzlich verborgen.',
    'safety.ageTitle': 'Alter und Täuschung',
    'safety.ageBody':
        'Manche geben ein falsches Alter an. Das gefährdet besonders junge '
        'Nutzer und führt bei Nachweis zum dauerhaften Ausschluss. Schütze '
        'dich: Glaube keiner Altersangabe blind. Bei großer Altersdifferenz '
        'warnt dich der Chat. Triff dich nur an öffentlichen Orten, nimm '
        'beim ersten Treffen dein Handy mit und sag einer Vertrauensperson '
        'Bescheid. Melde Verdacht auf falsches Alter sofort über den '
        'Meldegrund "Falsches Alter". Wisp kann Angaben nicht lückenlos '
        'prüfen und übernimmt keine Gewähr für deren Richtigkeit.',
    'home.noMessages': 'Keine neuen Nachrichten',
    'home.noMessagesSub':
        'Wenn du Funken hast, erscheinen hier neue Nachrichten.',
    'safety.sectionHelp': 'Sofort Hilfe',
    'safety.hotline1': 'Hilfetelefon "Gewalt gegen Frauen"',
    'safety.hotline1Sub': '116 016 - kostenlos, 24/7, anonym',
    'safety.hotline2': 'TelefonSeelsorge',
    'safety.hotline2Sub': '0800 111 0 111 - kostenlos, 24/7',
    'safety.hotline3': 'klicksafe (Cybermobbing & Beratung)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Hilfetelefon Stalking (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.sectionProtect': 'Schutz in WispDating',
    'safety.reportSomeone': 'Jemanden melden',
    'safety.reportSomeoneBody':
        'Im Chat über das Flag-Symbol oben rechts oder per langem Drücken '
        'auf ein Bild. Deine letzten Nachrichten werden transparent als '
        'Kontext übermittelt und vom Support persönlich geprüft.',
    'safety.blockSomeone': 'Jemanden blockieren',
    'safety.blockSomeoneBody':
        'Chat-Menü (drei Punkte) - Blockieren. Likes und Funken werden '
        'entfernt; künftige Interaktionen werden serverseitig verhindert. '
        'Die Person erfährt nicht davon.',
    'safety.stalkingGuide': 'Stalking-Leitfaden',
    'safety.stalkingBody':
        'Wenn dir jemand online (oder offline) nachstellt: 1. Nicht '
        'antworten, Kontakt bewusst abbrechen. 2. Alles dokumentieren: '
        'Screenshots mit Datum, Chatverlauf, Profilnamen. 3. In-App '
        'blockieren und uns über die Melde-Funktion informieren. Wir '
        'können Accounts dauerhaft sperren. 4. Passwörter ändern und 2FA '
        'aktivieren (Einstellungen). 5. Bei Bedrohung oder Angst: Polizei '
        '(110) bzw. 116 006 kontaktieren.',
    'safety.exportData': 'Meine Daten exportieren',
    'safety.exportDataSub': 'JSON-Export aller gespeicherten Daten',
    'spice.answerSent': 'Antwort gesendet. Dein Gegenüber antwortet bald.',
    'spice.answerEdit': 'Antwort ändern',
    'spice.answer': 'Antworten',
    'spice.title': 'Eisbrecher-Fragen',
    'spice.searchHint': 'In Kategorien suchen …',
    'spice.copied': 'Kopiert - füge die Frage im Chat ein.',
    'spice.copyTooltip': 'Frage kopieren',
    'spice.countHint':
        '{n} Fragen in 10 Kategorien - antippen zum Senden, Icon zum Kopieren.',
    'spice.perCategory': '{n} Fragen',
    'spice.emptySearch': 'Nichts gefunden. Versuche ein anderes Wort.',
    'spice.sendTitle': 'Frage in den Chat senden?',
    'spice.sendBtn': 'In Chat senden',
    'interests.cooledDone': 'Funke mit {name} gekühlt.',
    'interests.hiddenOne': '{name} aus der Liste entfernt.',
    'interests.coolBtn': 'Funke kühlen',
    'interests.hideOneBtn': 'Aus Liste entfernen',
    'bugreport.sendFailed':
        'Übermittlung fehlgeschlagen. Bitte versuche es später erneut.',
    'bugreport.maxImages': 'Maximal {n} Bilder erlaubt.',
    'bugreport.badFormat':
        'Bitte wähle eine Bilddatei im Format jpg, jpeg oder png.',
    'bugreport.prepareFailed':
        'Screenshot konnte nicht aufbereitet werden '
        '(Metadaten-Entfernung fehlgeschlagen) und wurde nicht angehängt.',
    'bugreport.sent': 'Danke, dein Bug Report wurde übermittelt',
    'bugreport.notSent':
        'Übermittlung konnte nicht abgeschlossen werden. '
        'Bitte versuche es später erneut.',
    'bugreport.defaultSummary': 'Bug Report',
    'bug.title': 'Bug melden',
    'bug.github': 'Bug auf GitHub melden',
    'bug.githubBody':
        'Diese Meldung ist öffentlich auf GitHub sichtbar. Trage dein '
        'Problem dort als Issue ein.',
    'bug.privateBody':
        'Alternativ kannst du den Bug auch direkt und privat per Email '
        'melden. Die Meldung wird über Brevo an eine Proton Mail Adresse '
        'gesendet. Sie ist nicht öffentlich einsehbar.',
    'bug.descLabel': 'Beschreibung *',
    'bug.descMissing': 'Bitte gib eine kurze Beschreibung ein.',
    'bug.descShort': 'Beschreibung zu kurz.',
    'bug.descLong': 'Maximal {n} Zeichen erlaubt.',
    'bug.preview': 'Vorschau',
    'bug.gallery': 'Galerie',
    'bug.camera': 'Kamera',
    'bug.send': 'Absenden',
    'bug.limits':
        'Erlaubt sind maximal {images} Bilder im Format jpg, jpeg oder '
        'png und {text} Zeichen Text. Es werden keine weiteren '
        'persönlichen Daten versendet.',
    'random.sendFailed': 'Nachricht konnte nicht gesendet werden.',
    'random.leaveTitle': 'Zufallschat beenden?',
    'random.leaveBody':
        'Der Chat wird beendet und die Verbindung getrennt. Du kannst '
        'jederzeit einen neuen Zufallschat starten.',
    'random.leaveConfirm': 'Beenden',
    'random.endedTitle': 'Chat beendet',
    'random.likeTooltip': 'Liken',
    'random.likeSentWaiting':
        'Gefällt-Markierung gesendet! Der Funke entsteht, sobald ihr '
        'gegenseitig geliked habt.',
    'random.endTooltip': 'Chat beenden',
    'random.hint': 'Nachricht …',
    'random.searching': 'Suche nach einer Person…',
    'random.searchingSub':
        'Sobald jemand anderes den Zufallschat startet, werdet ihr '
        'verbunden.',
    'random.hello': 'Sag {name} hallo! 🙂',
    'random.helloDefault': 'deinem Partner',
    'random.errorNoPartner':
        'Zufallschat konnte nicht gestartet werden. Möglicherweise sind '
        'gerade keine anderen Nutzer online. Bitte versuche es später '
        'erneut.',
    'random.errorUnavailable': 'Zufallschat nicht verfügbar.',
    'random.errorEnded': 'Der Zufallschat wurde beendet.',
    'random.errorOffline':
        'Der Zufallschat ist ohne Verbindung nicht verfügbar.',
    'random.errorConnectTimeout':
        'Die direkte Verbindung zum Partner konnte nicht aufgebaut '
        'werden. Hinweis: In Mobilfunknetzen wird der Zufallschat '
        'derzeit nicht unterstützt, weil es keinen Relay-Server (TURN) '
        'gibt. Bitte nutze stattdessen WLAN.',
    'random.relayStatus':
        'E2E über Server (verschlüsselt, kein direkter Kanal)',
    'random.waitingForPartner':
        'Warte auf das Partner-Gerät (Schlüssel werden dort vorbereitet). '
        'Die Verbindung stellt sich automatisch her - schreib ruhig schon '
        'mal etwas.',
    'random.relayNoDirect':
        'Direktverbindung vom Netzwerk blockiert (typisch: AP-Isolation im '
        'Router oder Mobilfunk). Nachrichten kommen sicher über den '
        'Server (E2E-verschlüsselt) an.',
    'random.infoBlind':
        'Zufallschat: Du bist blind mit einer zufälligen Person verbunden.',
    'random.infoE2e':
        'Gespräche sind Ende zu Ende verschlüsselt und laufen Peer zu Peer.',
    'meet.metBody':
        'Wir hoffen, ihr hattet eine schöne Zeit. Echte Verbindungen '
        'statt nur Online-Reden.',
    'meet.waitBody':
        'Wir haben {name} deinen Wunsch weitergegeben. Sobald {name} '
        'zustimmt, könnt ihr planen.',
    'meet.tryBody': 'Was hältst du davon, es mal wirklich zu versuchen?',
    'meet.yesGlad': 'Ja, gerne',
    'meet.noThanks': 'Doch lieber nicht',
    'meet.suggestTitle': 'Lust auf ein echtes Treffen?',
    'meet.suggestBody':
        'Ihr schreibt euch schon eine Weile. Wie wäre es mit einem '
        'Kaffee oder einem Spaziergang? Trefft euch an einem öffentlichen '
        'Ort.',
    'meet.yesWant': 'Ja, ich will',
    'meet.planningTitle': 'Ihr wollt euch treffen! 🎉',
    'meet.idea.1': 'Kaffee trinken',
    'meet.idea.2': 'Spazieren gehen',
    'meet.idea.3': 'Ins Kino',
    'meet.idea.4': 'Museum besuchen',
    'meet.idea.5': 'Etwas essen gehen',
    'meet.noteHint': 'Notiz (z. B. "Samstag, 15 Uhr, Café X")',
    'meet.metBtn': 'Wir haben uns getroffen',
    'meet.safetyTip':
        'Tipp: Trifft euch immer an einem öffentlichen Ort und sag einer '
        'Vertrauensperson Bescheid.',
    'music.likedTitle': 'Diese Genres mag ich',
    'music.dislikedTitle': 'Diese Genres mag ich nicht (freiwillig)',
    'music.exclude': 'Genre ausschließen…',
    'music.genre.klassik': 'Klassik',
    'home.noLikes': 'Keine neuen Likes',
    'home.noSparks': 'Keine neuen Funken',
    'home.viewCount': '{count} ansehen',
    'home.viewAll': 'Alle ansehen',
    'common.hint': 'Hinweis',
    'interests.sparksTitle': 'Funken',
    'dh.feature.realChat': 'Echter Chat statt Profil Check',
    'dh.info.title': 'Wie funktioniert Dating Hour?',
    'dh.info.timeTitle': '5 Minuten Zeit',
    'dh.info.timeSub': 'Danach entscheiden beide: "Annehmen" oder "Ablehnen".',
    'dh.info.liveTitle': 'Live mit echten Personen',
    'dh.info.liveSub':
        'Du wirst live mit einer anderen Person verbunden, die genau jetzt ebenfalls aktiv einen Dating Hour Partner sucht.',
    'dh.info.retryTitle': 'Kein Funke? Neue Chance!',
    'dh.info.retrySub':
        'Bei "Ablehnen" sucht der Algorithmus sofort jemand Neues.',
    'chathist.off.title': 'Gar nichts (nur Arbeitsspeicher)',
    'chathist.cap200.title': '200 Nachrichten pro Chat',
    'chathist.all.title': 'Kompletter Verlauf',
    'chathist.off.sub': 'Chats sind nach dem Neustart weg.',
    'chathist.cap200.sub': 'Verschlüsselt, max. 200 pro Chat.',
    'chathist.all.sub': 'Verschlüsselt, ohne Limit.',
    'profile.menu.edit': 'Profil bearbeiten',
    'profile.menu.editSub': 'Daten, Interessen und Vorstellung ändern',
    'profile.menu.preview': 'Profil Vorschau',
    'profile.menu.previewSub': 'So sehen dich andere',
    'profile.menu.introPreview': 'Vorstellung Vorschau',
    'profile.menu.introPreviewSub': 'Deine Text- und Audio-Vorstellung ansehen',
    'profile.preview.title': 'Profil Vorschau',
    'profile.preview.hint':
        'So sehen dich andere Nutzer (inkl. Altersschutz & Blind Mode):',
    'profile.preview.photoHidden':
        'Deine Fotos sind aufgrund deiner Einstellungen (Persönlichkeit vor Aussehen / Altersschutz) für andere nicht sichtbar.',
    'profile.preview.aboutMe': 'Über mich',
    'profile.preview.noBio': 'Noch keine Bio.',
    'profile.preview.interests': 'Interessen',
    'profile.preview.note':
        'Hinweis: Die tatsächliche Sichtbarkeit hängt vom Alter und den Einstellungen der jeweiligen Betrachter ab.',
    'profile.preview.type': 'Typ',
    'profile.intro.title': 'Meine Vorstellung',
    'profile.intro.empty': 'Du hast noch keine Text-Vorstellung hinterlegt.',
    'profile.intro.hint':
        'Andere lernen dich über diese Vorstellung kennen, bevor sie ein Foto sehen. Bearbeiten kannst du sie unter Profil bearbeiten.',
    'profile.intro.audioEmpty': 'Noch keine Audio-Vorstellung hinterlegt.',
    'profile.intro.audioMissing': 'Audio-Vorstellung nicht gefunden.',
    'profile.intro.audioLoadError':
        'Audio-Vorstellung konnte nicht geladen werden.',
    'profile.intro.stop': 'Stopp',
    'profile.intro.listen': 'Audio-Vorstellung anhören',
    // Intro-Editor (Audio-Recorder-UX)
    'intro.title': 'Meine Vorstellung',
    'intro.hintRequired':
        'So lernst du andere kennen, bevor ein Foto zu sehen ist. '
        'Text UND Audio sind Pflicht.',
    'intro.hintOptional':
        'So lernst du andere kennen, bevor ein Foto zu sehen ist. Du '
        'kannst diesen Schritt auch überspringen und alles später '
        'ergänzen.',
    'intro.textRequired': 'Vorstellung (Text) *',
    'intro.text': 'Vorstellung (Text)',
    'intro.textHint': 'z. B. wer du bist und wonach du suchst',
    'intro.promptTitle': 'Brauchst du Ideen? Tippe eine Frage an:',
    'intro.prompt.weekend': 'Was machst du am liebsten am Wochenende?',
    'intro.prompt.friends': 'Was schätzen deine Freunde an dir?',
    'intro.prompt.laugh': 'Worüber kannst du richtig lachen?',
    'intro.prompt.dream': 'Wovon träumst du gerade?',
    'intro.audioTitleRequired': 'Audio-Vorstellung *',
    'intro.audioTitle': 'Audio-Vorstellung',
    'intro.savedState':
        'Aufgenommen. Du kannst sie neu aufnehmen oder entfernen.',
    'intro.rangeHint':
        '{min} bis {max} Sekunden. Du kannst jede Aufnahme vor dem '
        'Speichern anhören.',
    'intro.record': 'Aufnehmen',
    'intro.rerecord': 'Neu aufnehmen',
    'intro.recordingState': 'Aufnahme läuft …',
    'intro.pausedState': 'Pausiert',
    'intro.pause': 'Pause',
    'intro.resume': 'Weiter',
    'intro.stopListen': 'Fertig',
    'intro.discard': 'Verwerfen',
    'intro.discardTitle': 'Aufnahme verwerfen?',
    'intro.discardBody': 'Die laufende Aufnahme wird gelöscht.',
    'intro.discardKeep': 'Behalten',
    'intro.delete': 'Entfernen',
    'intro.deleteTitle': 'Audio-Vorstellung entfernen?',
    'intro.deleteBody': 'Die gespeicherte Aufnahme wird endgültig gelöscht.',
    'intro.deleteTooltip': 'Audio-Vorstellung entfernen',
    'intro.micDenied': 'Mikrofon-Zugriff verweigert.',
    'intro.saved': 'Audio-Vorstellung hochgeladen.',
    'intro.removed': 'Audio-Vorstellung entfernt.',
    'intro.recordFailed': 'Aufnahme fehlgeschlagen: {error}',
    'intro.unavailable': 'Vorstellung nicht abrufbar',
    'intro.unplayable': 'Vorstellung nicht abspielbar',
    'intro.stop': 'Stopp',
    'intro.listen': 'Vorstellung anhören',
    // Audio-Review-Sheet (Anhören vor dem Senden)
    'intro.review.title': 'Aufnahme prüfen',
    'intro.review.length': 'Länge: {length}',
    'intro.review.lengthMin': 'Länge: {length} (mindestens {min} s)',
    'intro.review.listen': 'Anhören',
    'intro.review.pause': 'Pause',
    'intro.review.send': 'Senden',
    'intro.review.confirm': 'Verwenden & hochladen',
    'intro.review.discard': 'Verwerfen',
    'intro.review.rerecord': 'Neu aufnehmen',
    'intro.review.loadError':
        'Vorschau nicht abspielbar. Du kannst die Aufnahme trotzdem '
        'verwenden oder verwerfen.',
    'intro.review.tooShort':
        'Die Aufnahme ist zu kurz (mindestens {min} Sekunden). '
        'Bitte nimm sie neu auf.',
    'mood.noneSelected': 'Kein Mood ausgewählt',
    'mood.today': 'Heute',
    'mood.changeHint': 'Tippe, um deine Stimmung zu ändern.',
    'mood.selectHint': 'Tippe, um deine Stimmung des Tages zu wählen.',
    'mood.change': 'Ändern',
    'mood.select': 'Wählen',
    'settings.logout': 'Abmelden',
    'settings.deleteAccount': 'Konto löschen',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privatsphäre',
    'settings.whoCanSee': 'Wer kann mein Profil sehen?',
    'settings.localDataNote':
        'Deine Daten werden nur lokal auf diesem Gerät gespeichert. Es '
        'werden keine unnötigen Berechtigungen angefordert.',
    'settings.communitySafety': 'Community & Sicherheit',
    'settings.communityRules': 'Community Regeln',
    'settings.communityRulesSub': 'Respektvoller Umgang & Verhaltensregeln',
    'settings.passkeyCreate': 'Passkey erstellen',
    'settings.passkeyCreateSub':
        'Biometrischer Login (FaceID/TouchID) ohne Passwort',
    'settings.passkeyCreated': 'Passkey wurde erstellt.',
    'settings.passkeyFailed': 'Passkey-Erstellung fehlgeschlagen.',
    // Passkey-Bestaetigungs-/Fehlertexte (Services ohne BuildContext)
    'passkey.err.cancelledRegister': 'Passkey-Einrichtung abgebrochen.',
    'passkey.err.cancelledLogin': 'Passkey-Anmeldung abgebrochen.',
    'passkey.err.notAllowedRegister':
        'Passkey-Einrichtung wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
    'passkey.err.notAllowedLogin':
        'Passkey-Anmeldung wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
    'passkey.err.invalidState':
        'Auf diesem Gerät existiert bereits ein Passkey für dieses Konto.',
    'passkey.err.securityError':
        'Die App konnte ihre Domain-Zugehörigkeit nicht nachweisen '
        '(Passkey-Domain-Verknüpfung). Prüfe, ob die neueste App-Version '
        'installiert ist, und melde es dem Support, falls es bleibt.',
    'passkey.err.syncAccount':
        'Der Passkey konnte nicht verschlüsselt gespeichert werden. '
        'Stelle sicher, dass du auf dem Gerät mit einem Google-Konto '
        'angemeldet bist und die Google Play Services aktuell sind.',
    'passkey.err.timeoutRegister':
        'Zeitüberschreitung bei der Passkey-Einrichtung. Bitte versuche '
        'es gleichzeitig am Bildschirm erneut.',
    'passkey.err.timeoutLogin':
        'Zeitüberschreitung bei der Passkey-Anmeldung. Bitte versuche es '
        'gleichzeitig am Bildschirm erneut.',
    'passkey.err.noCredentialLogin':
        'Kein Passkey für dieses Konto gefunden. Richte zuerst einen '
        'unter Einstellungen ein.',
    'passkey.err.noCredentialRegister':
        'Kein Passkey-Speicher verfügbar. Prüfe Sperrbildschirm und '
        'Google Play Services.',
    'passkey.err.captcha':
        'Der Sicherheitscheck fehlte oder ist abgelaufen. '
        'Bitte versuche es erneut.',
    'passkey.err.verificationFailed':
        'Der Server konnte den Passkey nicht bestätigen. Wahrscheinlich '
        'fehlt der Ursprung (apk-key-hash) der installierten App in der '
        'Passkey-Konfiguration des Servers - siehe '
        'docs/PASSKEYS_SERVER_SETUP.md. Alternativ: alten Passkey unter '
        '"Passkeys verwalten" löschen und erneut anlegen.',
    'passkey.err.serverRejected':
        'Der Server hat die Passkey-Anfrage abgelehnt. Bitte prüfe in '
        'den Supabase-Einstellungen, ob "Passkeys" aktiviert ist und die '
        'RP-ID auf auth.wispdating.de gesetzt ist.{reason}',
    'passkey.err.unknownRegister':
        'Passkey-Einrichtung fehlgeschlagen. Bitte versuche es später '
        'erneut.',
    'passkey.err.unknownLogin':
        'Passkey-Anmeldung fehlgeschlagen. Bitte versuche es später '
        'erneut.',
    // Passkey-Dialog in den Einstellungen (Server-Bestätigung)
    'settings.passkeyExistsTitle': 'Passkey existiert bereits',
    'settings.passkeyExistsBody':
        'Auf deinem Konto sind bereits {count} Passkey(s) registriert. '
        'Wenn das Anlegen wieder an der Server-Bestätigung scheitert, '
        'lösche die alten Einträge unter "Passkeys verwalten" und '
        'versuche es erneut.\n\nTrotzdem einen weiteren Passkey '
        'erstellen?',
    'settings.passkeyExistsAbort': 'Abbrechen',
    'settings.passkeyExistsContinue': 'Weiter erstellen',
    'settings.passkeyWaitConfirm': 'Warte auf Bestätigung …',
    // "Passkeys verwalten"-Karte
    'passkey.name': 'Passkey',
    'passkey.stepUpHint':
        'Zum Anzeigen der Passkeys ist eine 2FA-Bestätigung nötig.',
    'passkey.loadError':
        'Passkeys konnten nicht geladen werden. Bitte später erneut versuchen.',
    'passkey.renameTitle': 'Passkey umbenennen',
    'passkey.renameLabel': 'Anzeigename',
    'passkey.renameHint': 'z. B. Pixel 8',
    'passkey.renameFailed': 'Umbenennen fehlgeschlagen.',
    'passkey.deleteBody':
        '"{name}" wird von deinem Konto entfernt. Die Anmeldung damit '
        'ist danach nicht mehr möglich. Der Passkey bleibt ggf. auf dem '
        'Gerät gespeichert.',
    'passkey.managerSub': 'Registrierte Passkeys auf deinem Konto',
    'passkey.managerHint':
        '{count} registriert - tippe zum Umbenennen, Papierkorb zum '
        'Entfernen',
    // Passkey-Fallbacks im Login (keine AppException)
    'auth.passkeyCancelled': 'Passkey-Anmeldung abgebrochen.',
    'auth.passkeyFailed':
        'Passkey-Anmeldung fehlgeschlagen. Bitte versuche es mit '
        'E-Mail und Passwort.',
    'settings.devices': 'Angemeldete Geräte',
    'settings.devicesSub': 'Wo bin ich eingeloggt? Überall abmelden',
    'devices.title': 'Angemeldete Geräte',
    'devices.logoutTitle': 'Überall abmelden?',
    'devices.logoutBody':
        'Du wirst auf allen anderen Geräten abgemeldet. Die Sitzung auf '
        'diesem Gerät bleibt bestehen. Die anderen Geräte müssen sich '
        'danach neu anmelden.',
    'devices.logoutBtn': 'Überall abmelden',
    'devices.logoutDone': 'Alle anderen Geräte wurden abgemeldet.',
    'devices.logoutFailed':
        'Abmelden ist fehlgeschlagen. Bitte prüfe deine Verbindung und '
        'versuche es erneut.',
    'devices.retry': 'Erneut versuchen',
    'devices.hint':
        'Hier siehst du, auf welchen Geräten du aktuell angemeldet bist. '
        'Über "Überall abmelden" beendest du alle anderen Sitzungen. '
        'Dieses Gerät bleibt angemeldet.',
    'devices.current': 'Dieses Gerät',
    'devices.activeNow': 'gerade aktiv',
    'devices.activeMinutesA': 'aktiv vor',
    'devices.activeMinutesB': 'Min.',
    'devices.activeHoursA': 'aktiv vor',
    'devices.activeHoursB': 'Std.',
    'devices.activeLastSeen': 'zuletzt aktiv am',
    'devices.empty':
        'Keine weiteren Geräte registriert. Öffne Wisp auf einem anderen '
        'Gerät (mindestens diese Version), damit es sich in der Liste zeigt.',
    'devices.signingOut': 'Melde ab …',
    'devices.logoutBtnLong': 'Überall abmelden (außer diesem Gerät)',
    'devices.logoutNote':
        'Die anderen Geräte werden sofort abgemeldet und müssen sich beim '
        'nächsten Öffnen neu einloggen.',
    'profile.title': 'Mein Profil',
    'profile.qrTooltip': 'Mein QR Code',
    'profile.unknown': 'Unbekannt',
    'profile.years': 'Jahre',
    'profile.ageUnknown': 'Alter unbekannt',
    'profile.typePrefix': 'Typ',
    'profile.aboutMe': 'Über mich',
    'profile.noBio': 'Noch keine Bio.',
    'profile.interests': 'Interessen',
    'profile.blindModeTitle': 'Persönlichkeit vor Aussehen',
    'profile.blindModeSub': 'Fotos erst nach Funke anzeigen',
    'profile.profileBtn': 'Profil',
    'profile.bugReportBtn': 'Bug melden',
    'profile.edit.title': 'Profil bearbeiten',
    'profile.edit.name': 'Name',
    'profile.edit.birthDate': 'Geburtsdatum',
    'profile.edit.birthDateHint': 'TT. MM. JJJJ',
    'profile.edit.birthDatePick': 'Bitte auswählen',
    'profile.edit.birthDateHelp': 'Wähle dein Geburtsdatum',
    'profile.edit.gender': 'Geschlecht',
    'profile.edit.lookingFor': 'Ich suche',
    'profile.edit.relationship': 'Was suchst du?',
    'profile.edit.location': 'Standort',
    'profile.edit.city': 'Ort / Stadt',
    'profile.edit.cityHint': 'z. B. Berlin',
    'profile.edit.gpsTooltip': 'Standort erkennen (GPS)',
    'profile.edit.country': 'Land',
    'profile.edit.state': 'Bundesland',
    'profile.edit.stateHint': 'Bitte wählen',
    'profile.edit.stateNotApplicable':
        'Bundesland entfällt außerhalb Deutschlands.',
    'profile.edit.noGeoLimit':
        'Keine geografische Einschränkung, Suche in ganz Deutschland.',
    'country.deutschland': 'Deutschland',
    'country.oesterreich': 'Österreich',
    'country.schweiz': 'Schweiz',
    'country.luxemburg': 'Luxemburg',
    'country.belgien': 'Belgien',
    'country.niederlande': 'Niederlande',
    'country.frankreich': 'Frankreich',
    'country.italien': 'Italien',
    'country.spanien': 'Spanien',
    'country.portugal': 'Portugal',
    'country.polen': 'Polen',
    'country.tschechien': 'Tschechien',
    'country.daenemark': 'Dänemark',
    'country.schweden': 'Schweden',
    'country.norwegen': 'Norwegen',
    'country.finnland': 'Finnland',
    'country.uk': 'Vereinigtes Königreich',
    'country.irland': 'Irland',
    'country.usa': 'USA',
    'country.kanada': 'Kanada',
    'country.australien': 'Australien',
    'country.other': 'Anderes Land',
    'state.badenWuerttemberg': 'Baden-Württemberg',
    'state.bayern': 'Bayern',
    'state.berlin': 'Berlin',
    'state.brandenburg': 'Brandenburg',
    'state.bremen': 'Bremen',
    'state.hamburg': 'Hamburg',
    'state.hessen': 'Hessen',
    'state.mecklenburgVorpommern': 'Mecklenburg-Vorpommern',
    'state.niedersachsen': 'Niedersachsen',
    'state.nrw': 'Nordrhein-Westfalen',
    'state.rheinlandPfalz': 'Rheinland-Pfalz',
    'state.saarland': 'Saarland',
    'state.sachsen': 'Sachsen',
    'state.sachsenAnhalt': 'Sachsen-Anhalt',
    'state.schleswigHolstein': 'Schleswig-Holstein',
    'state.thueringen': 'Thüringen',
    'profile.edit.rel.casual': 'Lockere Bekanntschaft',
    'profile.edit.rel.dating': 'Ernsthaftes Dating',
    'profile.edit.rel.relationship': 'Feste Beziehung',
    'profile.edit.rel.friends': 'Freundschaft',
    'profile.edit.rel.open': 'Offen für alles',
    'profile.edit.minAgeLabel': 'Mindestalter',
    'profile.edit.maxAgeLabel': 'Höchstalter',
    'common.years': 'Jahre',
    'common.unknownError': 'Unbekannter Fehler',
    'common.errorWith': 'Fehler: {error}',
    'common.copy': 'Kopieren',
    // Einstellungen: Backup + Passkeys
    'settings.backupPw': 'Passwort (min. 8 Zeichen)',
    'settings.backupPwShort': 'Zu kurz (min. 8)',
    'settings.backupPwRepeat': 'Passwort wiederholen',
    'settings.backupPwMismatch': 'Passwörter stimmen nicht überein',
    'settings.backupCreateBtn': 'Backup erstellen',
    'settings.backupCreateFailed': 'Backup konnte nicht erstellt werden.',
    'settings.backupCodeTitle': 'Dein Backup-Code',
    'settings.backupKeepSafe':
        'Bewahre Code UND Passwort sicher auf (z. B. Passwort-Manager). '
        'Ohne beides ist eine Wiederherstellung unmöglich.',
    'settings.backupCopied': 'Backup-Code kopiert.',
    'settings.restoreOverwrite':
        'Die aktuelle E2E-Identität auf diesem Gerät wird ÜBERSCHRIEBEN '
        '(bestehende verschlüsselte Sitzungen gehen verloren). Verwende nur '
        'ein Backup deines eigenen Kontos.',
    'settings.restoreEnterTitle': 'Backup eingeben',
    'settings.restorePw': 'Backup-Passwort',
    'settings.restoreBtn': 'Wiederherstellen',
    'settings.restoreFailed':
        'Wiederherstellung fehlgeschlagen. Prüfe Code und Passwort.',
    'settings.passkeysManage': 'Passkeys verwalten',
    'settings.passkeyCreatedAt': 'Erstellt {date}',
    'settings.passkeyLastUsed': 'Zuletzt genutzt {date}',
    'settings.passkeyRename': 'Umbenennen',
    'common.close': 'Schließen',
    // Quiz "Wie gut kenn ich mein Match"
    'quiz.title': 'Kennenlern-Quiz',
    'quiz.loadError': 'Quiz-Zustand konnte nicht geladen werden.',
    'quiz.photoHidden': 'Foto noch verborgen',
    'quiz.startTitle': 'Wie gut kennst du dein Gegenüber?',
    'quiz.startBody':
        'Ihr bekommt dieselbe Frage. Antwortet ihr beide richtig, ist das '
        'Foto dauerhaft freigeschaltet.',
    'quiz.startPersonalHint':
        'Fragen richten sich nach dem Profil deines Gegenübers.',
    'quiz.startAttempt': 'Versuch starten',
    'quiz.submit': 'Antwort abgeben',
    'quiz.passedTitle':
        'Bestanden! Das Foto ist jetzt dauerhaft freigeschaltet.',
    'quiz.toChat': 'Zum Chat',
    'quiz.partnerIntroTitle': 'Vorstellung deines Matches',
    'quiz.correctTitle':
        'Richtig! Jetzt wartest du auf die Antwort deines Matches.',
    'quiz.correctBody':
        'Antwortet dein Gegenüber auch richtig, ist das Quiz bestanden.',
    'quiz.roundClosed':
        'Die Runde ist vorbei. Dein Gegenüber hat sie nicht bestanden, also '
        'startet ihr nach der Pause gemeinsam neu.',
    'quiz.wrongTitle': 'Leider falsch.',
    'quiz.wrongBody':
        'Fehlversuch {failed}: Foto-Stufe {level}. Neuer Versuch nach der '
        '5-Minuten-Pause.',
    'quiz.cooldownIn': 'Nächster Versuch in {time}',
    'quiz.cooldownBody':
        'Nach jedem Fehlversuch gilt eine Pause von 5 Minuten. Danach könnt '
        'ihr es erneut versuchen.',
    'quiz.cooldownReady': 'Bereit - neuen Versuch starten',
    'quiz.passedBadge': 'Quiz bestanden!',
    'quiz.passedBody':
        'Das Foto bleibt dauerhaft scharf und farbig. Das komplette Profil '
        'deines Matches ist jetzt freigeschaltet.',
    // Community-Regeln (Rechts-Screen + Erst-Einrichtung)
    'cg.0.title': '§0 Respektvoller Umgang',
    'cg.0.body':
        'Wir erwarten von allen Nutzern einen freundlichen, respektvollen '
        'und wertschätzenden Umgang miteinander, unabhängig von Herkunft, '
        'Geschlecht, sexueller Orientierung, Religion oder Aussehen. Kritik '
        'und Ablehnung sollen stets sachlich und ohne Herabwürdigung '
        'erfolgen.',
    'cg.1.title': '§1 Keine Belästigung',
    'cg.1.titleShort': 'Behandle andere mit Respekt und Freundlichkeit.',
    'cg.1.body':
        'Beleidigungen, Diskriminierung, Drohungen oder unerwünschte '
        'sexuelle Ansprachen sind nicht gestattet und führen zum sofortigen '
        'Ausschluss.',
    'cg.2.title': '§2 Echte Profile',
    'cg.2.titleShort': 'Keine Fake Profile, keine Werbung und kein Missbrauch.',
    'cg.2.body':
        'Nutze nur echte Angaben und Bilder von dir selbst. Fake Profile '
        'oder das Vorgeben einer falschen Identität sind untersagt. Das '
        'gilt besonders für dein Alter und dein Geburtsdatum: Wer sich '
        'jünger ausgibt als er ist, gefährdet andere, besonders junge '
        'Nutzer, und wird bei Nachweis dauerhaft ausgeschlossen. Wisp kann '
        'Angaben nicht lückenlos prüfen und übernimmt keine Gewähr für '
        'deren Richtigkeit.',
    'cg.3.title': '§3 Kein Spam',
    'cg.3.titleShort':
        'Persönlichkeit vor Aussehen: Fotos werden erst nach einem Funke '
        'gezeigt.',
    'cg.3.body':
        'Werbung, Kettenbriefe oder das gezielte Weiterleiten von Links zu '
        'externen Angeboten sind nicht erlaubt.',
    'cg.4.title': '§4 Datenschutz',
    'cg.4.titleShort':
        'Respektiere Grenzen: Keine unerwünschten Bilder oder Nachrichten.',
    'cg.4.body':
        'Teile keine fremden privaten Daten (Adressen, Telefonnummern, '
        'Dokumente) ohne Zustimmung. Der Schutz Minderjähriger hat oberste '
        'Priorität.',
    'cg.5.title': '§5 Melden & Konsequenzen',
    'cg.5.titleShort':
        'Ehrlichkeit zahlt sich aus: Sei authentisch in deinem Profil.',
    'cg.5.body':
        'Verstöße können über den Melde-Button in Profil und Chat gemeldet '
        'werden. Wiederholter oder schwerer Verstoß führt zur Sperrung des '
        'Accounts.',
    'onb.page1.title': 'Privatsphäre & Darstellung',
    'onb.page2.title': 'Dein Profil',
    'onb.page3.title': 'Fertig',
    'onb.next': 'Weiter',
    'onb.back': 'Zurück',
    'onb.finish': 'Fertig werden',
    'chat.hint': 'Nachricht...',
    'chat.send': 'Senden',
    'chat.empty': 'Schreib die erste Nachricht! 😊',

    'chat.report': 'Bild melden',
    'chat.block': 'Nutzer blockieren',
    'chat.blockSub':
        'Keine Nachrichten, Likes oder Funken mehr von dieser Person.',
    'chat.end': 'Funke beenden',
    'chat.call': 'Audio Anruf',
    // Vorstellung im Chat + Kennenlern-Quiz-Banner (Chat zuerst)
    'chat.introTitle': 'Vorstellung',
    'chat.quizBanner':
        'Das Kennenlern-Quiz schaltet das Profilfoto frei. Chatten ist '
        'unabhängig möglich.',
    'chat.quizOpen': 'Zum Quiz',
    // Herzensstärken (v0.9.2): Erinnerung, Freundschaft, Erinnerungsliste
    'milestone.sparkDay': 'Euer erster Tag',
    'milestone.sparkDayBody':
        'Am {date} habt ihr euch gefunden. Manchmal hilft ein Blick '
        'darauf, warum ihr geschrieben habt.',
    'milestone.quizPassed': 'Quiz bestanden',
    'milestone.quizPassedBody':
        'Ihr habt euch am {date} im Quiz gekannt - das Foto ist seitdem '
        'frei.',
    'milestone.month1': 'Ein Monat',
    'milestone.month1Body':
        'Ein Monat Funkentanz: {date} bis heute. Was war euer bestes '
        'Gespräch?',
    'milestone.month3': 'Drei Monate',
    'milestone.month3Body':
        'Drei Monate seit {date}. Manche Verbindungen brauchen Zeit - '
        'ihr habt sie ihr gegeben.',
    'milestone.year1': 'Ein Jahr',
    'milestone.year1Body':
        'Ein Jahr! Vom ersten Funken am {date} bis hierher - das '
        ' verdient einen ehrlichen Respekt.',
    'milestone.title': 'Erinnere dich daran',
    'milestone.dismiss': 'Schließen',
    'friends.toggleTitle': 'Freundschaft',
    'friends.toggleHint':
        'Diese Verbindung ist eine Freundschaft - kein romantischer '
        'Funke. Ihr könnt es jederzeit umschalten.',
    'friends.badge': 'Freundschaft',
    'bucket.title': 'Erinnerungsliste',
    'bucket.hint':
        'Das wollt ihr gemeinsam erleben. Beide können Einträge '
        'hinzufügen und abhaken.',
    'bucket.add': 'Hinzufügen',
    'bucket.addHint': 'Was wollt ihr zusammen unternehmen?',
    'bucket.empty':
        'Noch leer. Schreibt eure ersten Ideen auf - große und kleine.',
    'bucket.staleNote':
        'Eure Erinnerungsliste wartet seit {days} Tagen - Lust, etwas '
        'davon anzupacken?',
    'bucket.mine': 'von dir',
    'bucket.theirs': 'von {name}',
    'whatsnew.v090.sparkMoments':
        'Erinnerungs-Momente im Chat: erster Tag, Quiz-Bestehen und '
        'Jubiläen werden ehrlich gewürdigt.',
    'whatsnew.v090.friendship':
        'Freundschafts-Modus: Verbindungen sind jetzt ausdrücklich als '
        'Freundschaft kennzeichnbar.',
    'whatsnew.v090.bucketList':
        'Gemeinsame Erinnerungsliste im Chat: Das wollt ihr zusammen '
        'erleben - ankreuzbar, ohne Druck.',
    'whatsnew.v090.birthdayStyles':
        '5 schicke Geburtstags-Stile für dein Profil (unten auswählen '
        'oder später im Profil-Bearbeiten).',
    // Sprachnachrichten im Chat (Einmal-Anhören, M-17)
    'chat.voiceOnce':
        'Diese Sprachnachricht wurde bereits angehört und entfernt '
        '(Datenschutz: entschlüsselte Audio-Reste werden gelöscht).',
    'chat.voiceOnlyOnce':
        'Wiedergabe nicht möglich - die Nachricht wurde '
        'bereits angehört.',
    'chat.voiceListened': 'angehört',
    // Chat-Dialoge & Steuerung (zweisprachig)
    'chat.you': 'Du',
    'chat.callBatteryHint':
        'Anrufe brauchen dauerhaft Mikrofon und Funk und verbrauchen '
        'merklich mehr Akku.',
    'chat.ageGapHint':
        'Hinweis: Ihr seid {my} und {other} Jahre alt. Profile können '
        'falsche Angaben enthalten. Bleib vorsichtig, triff dich nur '
        'öffentlich und melde Verdacht auf falsches Alter.',
    'chat.relayBannerShort': 'Keine direkte Verbindung',
    'chat.relayBanner':
        'Keine direkte Verbindung. Nachrichten sind Ende-zu-Ende '
        'verschlüsselt und kommen an, sobald der Chat geöffnet wird.',
    'chat.relayStored':
        'Verschlüsselt zwischengespeichert. Wird zugestellt, sobald der '
        'Chat geöffnet wird.',
    'chat.sendFailed': 'Nachricht konnte nicht gesendet werden: {error}',
    'chat.queuedHint':
        'Offline - Nachricht wartet in der Warteschlange und wird bei der '
        'nächsten direkten Verbindung zugestellt.',
    'chat.spiceUnavailable':
        'Eisbrecher-Fragen gibt es nur für Funken-Chats (nicht für '
        'gespeicherte Kontakte).',
    'chat.quizUnavailable': 'Das Kennenlern-Quiz gibt es nur für Funken-Chats.',
    'chat.imageSend': 'Bild senden',
    'chat.idea.coffeeCake': 'Kaffee & Kuchen',
    'chat.idea.walk': 'Gemeinsam spazieren gehen',
    'chat.idea.iceCream': 'Eis essen',
    'chat.idea.museum': 'Museum oder Ausstellung',
    'chat.idea.minigolf': 'Minigolf',
    'chat.idea.movieNight': 'Kinoabend',
    'chat.idea.market': 'Markt bummeln',
    'chat.idea.bowling': 'Bowling oder Billard',
    'chat.idea.liveMusic': 'Live-Musik',
    'chat.idea.stargazing': 'Sterne beobachten',
    'chat.imageBlurredHint':
        'Verpixelte Bildnachricht. Doppeltippen zum Anzeigen nach '
        'Warnung, lang drücken zum Melden.',
    'chat.imageHint':
        'Bildnachricht. Doppeltippen für Vollbild, lang drücken zum '
        'Melden.',
    'chat.camera': 'Kamera',
    'chat.gallery': 'Galerie',
    'chat.imageSendFailed': 'Senden fehlgeschlagen',
    'chat.imageSendFailedBody':
        'Das Bild konnte nicht gesendet werden.\n\n{error}',
    'chat.retry': 'Wiederholen',
    'chat.voiceTooShort': 'Aufnahme zu kurz (< 1 s), verworfen.',
    'chat.voiceRecordFailed': 'Aufnahme fehlgeschlagen: {error}',
    'chat.voiceStartFailed': 'Aufnahme konnte nicht gestartet werden: {error}',
    'chat.voiceCancelled': 'Aufnahme abgebrochen',
    'chat.voiceStopSend': 'Aufnahme beenden & senden',
    'chat.voiceTooltip': 'Sprachnachricht',
    'chat.voiceCancel': 'Aufnahme abbrechen',
    'chat.recordingHint': 'Aufnahme: {s} s',
    'chat.blockTitle': 'Nutzer blockieren?',
    'chat.blockBody':
        '{name} wird dauerhaft blockiert: Der Funke wird beendet und diese '
        'Person kann dich nicht mehr liken, einen Funke setzen oder dir '
        'Nachrichten senden. Die Blockierung kann später über den '
        'Support-Dialog nicht aufgehoben werden. Nur du selbst kannst sie '
        'in den Einstellungen entfernen.',
    'chat.blockAction': 'Blockieren',
    'chat.blockedDone': '{name} wurde blockiert.',
    'chat.blockFailed': 'Blockieren fehlgeschlagen. Bitte versuche es erneut.',
    'chat.spiceTooltip': 'Eisbrecher-Fragen (Spice Questions)',
    'chat.reportTooltip': 'Nutzer melden',
    'chat.reportImageSub': 'Wird mit Kontext an den Support übermittelt.',
    'chat.ideaWheelBtn': 'Dreh das Rad, Date-Idee finden',
    'chat.ideaHide': 'Date-Rad für diesen Chat ausblenden',
    'chat.icebreakerOn': 'Interessen-Vorschläge anzeigen',
    'chat.icebreakerOff': 'Interessen-Vorschläge ausblenden',
    'chat.icebreakerText':
        'Wir teilen das Interesse "{interest}". Erzähl mir davon: was war '
        'dein Highlight dazu? 😊',
    'chat.dateIdea': 'Idee für ein Date: {idea} ✨ Was meinst du?',
    'chat.ideaSendFailed': 'Vorschlag konnte nicht gesendet werden.',
    'chat.endSparkTitle': 'Funke beenden: ehrlich und freundlich',
    'chat.endSparkBody':
        'Der Funke wandert bei euch beiden in "Erschlossene Funken", ganz '
        'ohne Countdown und ohne Benachrichtigung. Ein Re-Funke ist '
        'jederzeit mit einem Tap möglich.',
    'chat.endSilent': 'Ruhig enden lassen',
    'chat.endSilentSub': 'Ohne Nachricht',
    'chat.goodbye.1':
        'Hey, ich hatte wirklich schöne Gespräche mit dir, spüre aber '
        'selbst, dass es nicht das wird, was wir beide verdienen. Ich '
        'lasse den Funken jetzt ruhen. Danke dir und alles Gute! 🌿',
    'chat.goodbye.2':
        'Ich mag dich, aber ich merke, dass ich gerade nicht dasselbe '
        'investieren kann wie du. Ehrlicher finde ich, das klar zu sagen, '
        'statt mich zu verziehen. Mach\'s gut! 🙏',
    'chat.goodbye.3':
        'Wir passen für mich gerade nicht zusammen. Das sagt nichts über '
        'dich aus. Ich wünsche dir von Herzen alles Gute! ✨',
    'chat.goodbye.4':
        'Meine Gefühle haben sich verändert. Statt dich im Ungewissen zu '
        'lassen, lasse ich den Funken jetzt sanft ruhen. Danke für die '
        'schönen Momente! 🕊️',
    'chat.wheelTitle': 'Dreh das Rad',
    'chat.wheelSpin': 'Drehen',
    'chat.wheelAgain': 'Nochmal drehen',
    'chat.wheelHint':
        'Passt das? Schick den Vorschlag, deine Gegenstelle kann einfach '
        'antworten.',
    'chat.wheelSend': 'Vorschlag senden',
    'chat.revealTitle': 'Bild anzeigen?',
    'chat.revealBody':
        'Dieses Bild ist verpixelt, um dich vor unangemessenen Inhalten zu '
        'schützen. Es kann Inhalte enthalten, die du als störend '
        'empfindest.\n\nDu kannst es danach direkt melden.',
    'chat.revealAction': 'Anzeigen',
    'chat.reportImage': 'Bild melden',
    'chat.blurred': 'Verpixelt',
    'chat.viewOnce': 'Einmalig',
    'chat.viewedOnce': 'Bereits angesehen',
    'chat.photosAfterSpark': 'Fotos nach Funke sichtbar',
    'chat.safetyNotConnected':
        'Noch keine verschlüsselte Verbindung zu {name} aufgebaut. Die '
        'Nummer erscheint nach der ersten Nachricht.',
    'chat.safetyCompare':
        'Vergleiche diese Nummer mit {name}, am besten persönlich oder '
        'telefonisch:',
    'chat.identityVerifiedHint':
        'Nur aktivieren, wenn die Nummern übereinstimmen.',
    'chat.more': 'Weitere Optionen',
    'dh.event.startingSoon': 'Dating Hour startet gleich',
    'dh.event.cancelledToday':
        'Heute fällt die Dating Hour aus: Es haben sich nicht genug '
        'Personen angemeldet.',
    'dh.event.serverTimeWarn':
        'Die Server-Zeit konnte nicht verifiziert werden.',
    'dh.event.loadErrorFull': 'Fehler beim Laden: {error}',
    'dh.event.autoJoinFailed': 'Auto-Beitritt fehlgeschlagen: {error}',
    'dh.event.autoJoinAsk':
        'Das Event ist für heute vorbei. Möchtest du beim nächsten '
        'Mal automatisch dabei sein?',
    'dh.event.welcomeBack':
        'Willkommen zurück! Du bist automatisch wieder dabei.',
    'dh.event.autoJoinOn':
        'Du bist beim nächsten Dating Hour automatisch dabei.',
    'dh.event.autoJoinOff': 'Alles klar, du wirst beim nächsten Mal gefragt.',
    'dh.event.prefsNote': '(änderbar in den Präferenzen).',
    'dh.event.localTimeWarn':
        'Countdown und Status basieren auf der lokalen Gerätezeit. '
        'Die Server-Zeit konnte nicht verifiziert werden.',
    'dh.event.liveNow': 'LIVE: Dating Hour läuft!',
    'dh.event.nextAt': 'Nächste Dating Hour am {date}',
    'dh.event.chipParticipating': 'Du nimmst teil',
    'dh.event.chipNotParticipating': 'Nicht angemeldet',
    'dh.event.participatingLive': 'Du nimmst teil! Chats laufen.',
    'dh.event.participatingWaiting': 'Du nimmst teil! Warte auf den Start.',

    'dh.rules.title': 'Dating Hour Regeln',
    'dh.rules.intro':
        'Bitte lies diese Regeln aufmerksam durch, bevor du teilnimmst.',
    'dh.rules.acceptedTitle': 'Regeln akzeptiert',
    'dh.rules.next': 'Weiter',
    'dh.how.title': 'Wie funktioniert Dating Hour?',
    'dh.how.intro':
        'Die Dating Hour läuft jeden Samstag von 20:00 bis 21:00 Uhr. '
        'Hier ist der Ablauf im Überblick:',
    'dh.how.next': 'Zur Dating Hour',
    'dh.rules.introLong':
        'Bitte lies diese Regeln aufmerksam durch, bevor du an der Dating '
        'Hour teilnimmst.',
    'dh.rules.bodyFun': 'Viel Spaß bei der Dating Hour!',
    'dh.rules.1.title': 'Respektvoll bleiben',
    'dh.rules.1.body':
        'Behandele deinen Gegenüber mit Respekt. Keine Beleidigungen, '
        'Diskriminierung oder unerwünschte Nachrichten.',
    'dh.rules.2.title': 'Keine persönlichen Daten teilen',
    'dh.rules.2.body':
        'Gib keine Adressen, Telefonnummern oder Kontodetails preis. '
        'Bleibt zunächst in der App.',
    'dh.rules.3.title': 'Ehrliches Profil',
    'dh.rules.3.body':
        'Nutze nur echte Angaben und aktuelle Bilder. Fake Profile oder '
        'Identitätsdiebstahl werden gemeldet.',
    'dh.rules.4.title': '5 Minuten Regel',
    'dh.rules.4.body':
        'Jeder Chat dauert maximal 5 Minuten. Danach entscheidest du, ob '
        'du den Funken verlängern möchtest.',
    'dh.rules.5.title': 'Keine unerwünschten Bilder',
    'dh.rules.5.body':
        'Sende keine intimen Bilder oder unerwünschten Content. Verstöße '
        'führen zur sofortigen Sperrung.',
    'dh.rules.6.title': 'Minderjährigenschutz',
    'dh.rules.6.body':
        'Die Dating Hour ist erst ab 16 Jahren freigegeben. Jüngere '
        'Nutzer werden automatisch ausgeschlossen.',
    'dh.how.step1.title': 'Beitreten',
    'dh.how.step1.body':
        'Wähle deine Präferenzen und trete dem samstäglichen Event '
        'bei. Du kannst jederzeit wieder austreten.',
    'dh.how.step2.title': 'Warten auf eine Zuordnung',
    'dh.how.step2.body':
        'Die App verbindet dich mit einer passenden Person. Sobald beide '
        'bereit sind, startet der 5 Minuten Chat.',
    'dh.how.step3.title': '5 Minuten chatten',
    'dh.how.step3.body':
        'Lerne die Person in einem kurzen, zeitlich begrenzten Gespräch '
        'kennen. Fotos werden je nach Einstellung angezeigt.',
    'dh.how.step4.title': 'Entscheidung',
    'dh.how.step4.body':
        'Nach dem Gespräch entscheidest du, ob du den Kontakt verlängern '
        'möchtest.',
    'dh.how.step5.title': 'Funken',
    'dh.how.step5.body':
        'Wenn beide sich für eine Verlängerung entscheiden, entsteht ein '
        'Funke und ihr könnt weiter chatten.',
    'dh.chat.sparkJumped': 'Ein Funke ist übersprungen! Chat wird geöffnet...',
    'dh.chat.noSpark': 'Kein Funke',
    'dh.chat.keepSearching': 'Weiter suchen',
    'dh.chat.e2e': 'Ende zu Ende verschlüsselt',
    'dh.chat.leaveTitle': 'Chat verlassen?',
    'dh.chat.leaveBody':
        'Wenn du den Chat verlässt, gilt das als "Ablehnen". Möchtest du '
        'wirklich gehen?',
    'dh.chat.stay': 'Bleiben',
    'dh.chat.leaveDecline': 'Verlassen & Ablehnen',
    'dh.chat.sayHello': 'Sag hallo zu {name}!',
    'dh.chat.fiveMinutes':
        'Ihr habt 5 Minuten Zeit, euch kennenzulernen. Danach entscheidet '
        'ihr beide: Funke oder weitersuchen?',
    'dh.chat.icebreakerBtn': 'Gesprächsstarter senden',
    'dh.chat.hint': 'Nachricht...',
    'dh.chat.timeUp': 'Die 5 Minuten sind um!\nMöchtest du euch wiedersehen?',
    'dh.chat.decline': 'Ablehnen',
    'dh.chat.accept': 'Annehmen',
    'dh.chat.bothMustAccept':
        'Beide müssen "Annehmen" drücken für einen Funken.',
    'dh.chat.voted': 'Du hast abgestimmt. Warte auf deine Gegenseite...',
    'dh.chat.resultPending':
        'Sobald beide entschieden haben, erfährst du das Ergebnis.',
    'dh.chat.backToOverview': 'Zurück zur Übersicht',
    'dh.chat.sendFailed': 'Nachricht konnte nicht gesendet werden.',
    'dh.gender.all': 'Alle Geschlechter',
    'dh.gender.women': 'Frauen',
    'dh.gender.men': 'Männer',
    'dh.gender.nonBinary': 'Nichtbinäre Personen',
    'dh.prefs.title': 'Dating Hour: Präferenzen',
    'dh.prefs.header': 'Deine Dating Hour Präferenzen',
    'dh.prefs.headerSub':
        'Diese Einstellungen helfen uns, dich mit passenden Personen zu '
        'verbinden. Du kannst sie vor jedem Event anpassen.',
    'dh.prefs.ageRange': '{min} bis {max} Jahre',
    'dh.prefs.sectionJoin': 'Teilnahme',
    'dh.prefs.autoJoin': 'Automatisch wieder dabei sein',
    'dh.prefs.autoJoinSub':
        'Wenn aktiviert, nimmst du am nächsten Dating Hour Event '
        'automatisch teil.',
    'dh.prefs.traitHint':
        'Wähle eine Eigenschaft oder gib deine eigene ein. Dies fließt '
        'als weicher Faktor bei den Funken-Vorschlägen ein.',
    'dh.prefs.traitOwn': 'Eigene Eigenschaft eingeben',
    'dh.prefs.traitHintField':
        'z. B. "Gute Laune", "Tiefgründige Gespräche"...',
    'dh.prefs.habits': 'Gewohnheiten (optional)',
    'dh.prefs.intro':
        'Diese Einstellungen helfen uns, dich mit passenden Personen zu '
        'verbinden. Du kannst sie vor jedem Event anpassen.',
    'dh.prefs.ageSection': 'Altersbereich',
    'dh.prefs.genderSection': 'Ich suche...',
    'dh.prefs.joinSection': 'Teilnahme',
    'dh.prefs.autoJoinHint':
        'Wenn aktiviert, nimmst du am nächsten Dating Hour '
        'automatisch teil, sobald es läuft.',
    'dh.prefs.traitSection': 'Was du an anderen besonders magst',
    'dh.prefs.traitHint2':
        'Wähle eine Eigenschaft oder gib deine eigene ein. '
        'Dies fließt als weicher Faktor bei den Funken-Vorschlägen ein.',
    'dh.prefs.habitsHint2':
        'Personen mit passenden Gewohnheiten werden dir bei den '
        'Funken-Vorschlägen zuerst vorgeschlagen, ausgeschlossen wird niemand.',
    'dh.prefs.saveHint2':
        'Speichern meldet dich NICHT an. Deine Teilnahme bestätigst '
        'du separat mit "Ich bin dabei" auf dem Event-Screen.',
    'dh.prefs.trait.humor': 'Humor',
    'dh.prefs.trait.honesty': 'Ehrlichkeit',
    'dh.prefs.trait.adventure': 'Abenteuerlust',
    'dh.prefs.trait.intelligence': 'Intelligenz',
    'dh.prefs.trait.empathy': 'Empathie',
    'dh.prefs.trait.spontaneity': 'Spontanität',
    'dh.prefs.trait.reliability': 'Zuverlässigkeit',
    'dh.prefs.trait.passion': 'Leidenschaft',
    'dh.prefs.trait.openness': 'Offenheit',
    'dh.prefs.trait.downToEarth': 'Bodenständigkeit',
    'dh.prefs.habitsSub':
        'Personen mit passenden Gewohnheiten werden dir bei den '
        'Funken-Vorschlägen zuerst vorgeschlagen, ausgeschlossen wird niemand.',
    'dh.prefs.save': 'Präferenzen speichern',
    'dh.prefs.saveNote':
        'Speichern meldet dich NICHT an. Deine Teilnahme bestätigst du '
        'separat mit "Ich bin dabei" auf dem Event-Screen.',
    'dh.prefs.saved':
        'Präferenzen gespeichert. Deine Teilnahme meldest du über "Ich '
        'bin dabei" am Event-Tag an.',
    'dh.event.joinConfirmTitle': 'Am Event teilnehmen?',
    'dh.event.join': 'Ich bin dabei',
    'dh.event.joined': 'Du nimmst am Dating Hour Event teil!',
    'dh.event.left': 'Du hast das Event verlassen.',
    'dh.event.bye': 'Bis zum nächsten Mal!',
    'dh.event.noThanks': 'Nein, danke',
    'dh.event.yesPlease': 'Ja, gerne',
    'dh.event.title': 'Dating Hour',
    'dh.event.ended': 'Dating Hour beendet',
    'dh.event.joinNow': 'Jetzt beitreten & chatten',
    'dh.event.leave': 'Raus',
    'dh.event.setPrefs': 'Präferenzen festlegen',
    'dh.event.nextIn': 'Nächstes Event in {d}',
    'dh.event.searching': 'Suche läuft...',
    'dh.event.loadError': 'Fehler beim Laden',
    'dh.event.searchingPartner': 'Wir suchen gerade einen Partner...',
    'dh.event.toChat': 'Zum Chat',
    'dh.event.nonePlanned': 'Aktuell ist kein Dating Hour Event geplant.',
    'dh.event.remaining': 'Noch {d}',
    'dh.event.startIn': 'Start in {d}',
    'dh.event.chatsRunning': 'Chats laufen.',
    'dh.event.waitStart': 'Warte auf den Start.',
    'dh.event.participating': 'Du nimmst teil!',
    // Dating-Hour-Regeln-Detailzeilen (Event-Screen, Regeln-Karte)
    'dh.event.rulesTitle': 'Wichtige Regeln',
    'dh.event.rule.1':
        'Samstags 20:00 bis 21:00 Uhr (Beitritt bereits vorher möglich).',
    'dh.event.rule.2':
        'Direkt in 1:1 Chat verbunden, ohne vorherige Profilansicht.',
    'dh.event.rule.3':
        '5 Minuten Chat, dann Entscheidung: "Annehmen" oder "Ablehnen".',
    'dh.event.rule.4': 'Nur bei BEIDSEITIGEM "Annehmen" entsteht ein Funke.',
    'dh.event.rule.5':
        'Bei "Ablehnen" (oder Timeout): Automatische neue Zuordnung.',
    'dh.event.rule.6': 'Während eines Chats: NUR dieser Chat erlaubt.',
    'dh.event.rule.7':
        'Um 21:00 Uhr Ende, laufende Chats werden zu Ende geführt.',
    'dh.event.participants': '{n} Teilnehmer dabei',
    'dh.event.participantsSub':
        'Die Dating Hour findet immer statt, egal wie viele mitmachen. '
        'Reicht es nicht für ein Paar, bekommst du diesmal kein Gespräch.',
    'dh.event.rule.8':
        'Die Dating Hour findet immer statt, egal wie viele mitmachen. '
        'Es gibt keine Mindestanzahl mehr.',
    'dh.event.rule.9':
        'Die Erstellung von Fake Accounts ist strengstens untersagt.',

    'profile.edit.filters': 'Filter & Präferenzen',
    'profile.edit.radiusMode': 'Suchradius definieren über',
    'profile.edit.maxDistance': 'Maximale Entfernung: {km} km',
    'profile.edit.minAge': 'Mindestalter: {age} Jahre',
    'profile.edit.maxAge': 'Höchstalter: {age} Jahre',
    'profile.edit.bio': 'Bio',
    'profile.edit.music': 'Musik',
    'profile.edit.musicSub':
        'Welche Musik beschreibt dich? Dein Geschmack fließt in den '
        'Verbindungs-Score ein.',
    'profile.edit.habits': 'Gewohnheiten',
    'profile.edit.habitsSub':
        'Wie stehst du dazu? Diese Angaben beeinflussen, wen du bei '
        '"Find your Match" siehst. Es werden nur Personen gezeigt, die '
        'maximal so viel konsumieren wie du.',
    'profile.edit.interests': 'Interessen',
    'profile.edit.personality': 'Persönlichkeitstest',
    'profile.edit.personalityDone':
        'Du hast den Test abgeschlossen. Du kannst ihn jederzeit '
        'wiederholen.',
    'profile.edit.personalityOpen': 'Zeig anderen, wer du wirklich bist.',
    'profile.edit.personalityRetake': 'Test wiederholen',
    'profile.edit.personalityStart': 'Persönlichkeitstest starten',
    'profile.edit.saved': 'Profil gespeichert',
    'profile.edit.savedNoSync':
        'Lokal gespeichert. Server-Sync fehlgeschlagen, bitte später '
        'erneut speichern.',
    'profile.edit.missingFields':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert).',
    'profile.edit.missingFieldsHint':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert). Bitte prüfe das Formular.',
    'profile.edit.birthDateMissing': 'Bitte wähle dein Geburtsdatum',
    'profile.edit.photoUpdated': 'Profilbild aktualisiert.',
    'profile.edit.photoUploadError': 'Fehler beim Hochladen: {error}',
    'profile.edit.photoPolicyBlocked':
        'Dieses Bild entspricht nicht unseren Richtlinien und wurde nicht '
        'hochgeladen.',
    'profile.edit.photoNsfwTitle': 'Bild nicht freigegeben',
    'profile.edit.photoNsfwBody':
        'Dieses Bild wurde lokal auf deinem Gerät als potenziell '
        'anstößig eingestuft und wird nicht hochgeladen.',
    'profile.edit.photoNsfwChoice': 'Was möchtest du tun?',
    'profile.edit.photoNsfwAppeal': 'Einspruch einlegen',
    'profile.edit.photoNsfwUnderstood': 'Verstanden',
    'profile.edit.photoNsfwVerdict': 'Lokaler Befund: {label} ({score} %).',
    'profile.edit.photoNsfwNotUploaded':
        'Das Bild wird nicht als Profilbild hochgeladen.',
    'profile.edit.photoOkTitle': 'Bild geprüft',
    'profile.edit.photoOkBody': 'Dein Bild ist okay und kann verwendet werden.',
    'profile.edit.photoOkBtn': 'Weiter',
    'profile.edit.appealSubmitted':
        'Einspruch eingereicht. Wir benachrichtigen dich über das Ergebnis.',
    'profile.edit.appealFailed':
        'Einspruch konnte nicht eingereicht werden. Bitte später erneut.',
    'profile.appeal.approvedTitle': 'Bild freigegeben',
    'profile.appeal.approvedBody':
        'Dein Einspruch wurde geprüft: Das Bild ist freigegeben. Möchtest '
        'du es jetzt als Profilbild verwenden?',
    'profile.appeal.useBtn': 'Jetzt verwenden',
    'profile.appeal.applied': 'Profilbild übernommen.',
    'profile.appeal.rejectedTitle': 'Bild abgelehnt',
    'profile.appeal.rejectedBody':
        'Dein Einspruch wurde geprüft: Das Bild wurde abgelehnt und kann '
        'nicht verwendet werden. Wähle bitte ein anderes Profilbild.',
    'profile.appeal.okBtn': 'Verstanden',
    'profile.edit.photoNsfwOther': 'Anderes Bild wählen',
    'profile.edit.birthDateLocked':
        'Aus Schutz vor Alters-Täuschung kann das Geburtsdatum nach der '
        'Registrierung nicht mehr geändert werden.',
    'profile.edit.favoriteSong': 'Lieblingssong',
    'profile.edit.favoriteSongHint': 'z. B. Songtitel …',
    'profile.edit.favoriteBand': 'Lieblingsband',
    'profile.edit.favoriteBandHint': 'z. B. Band oder Künstler …',
    'music.excludeTitle': 'Genre ausschließen',
    'music.excludeHint':
        'Dieses Genre beeinflusst dein Matching negativ - du siehst '
        'weniger Personen mit diesem Geschmack.',
    'music.excludeSearch': 'Genre suchen …',
    'music.excludeNoMatch': 'Kein Genre gefunden.',
    'profile.edit.locationDetected': 'Standort erkannt und übernommen.',
    'profile.edit.locationFailed':
        'Standort konnte nicht ermittelt werden. Bitte gib ihn manuell '
        'ein oder erlaube den Zugriff.',
    'profile.edit.locationSuspicious':
        'Hinweis: Dieser Standort weicht deutlich von deinen bisherigen '
        'Standorten auf diesem Gerät ab.',
    'profile.edit.locationError': 'Fehler bei der Standortermittlung: {error}',
    'profile.edit.unsavedTitle': 'Ungespeicherte Änderungen',
    'profile.edit.unsavedBody':
        'Deine Profiländerungen wurden noch nicht gespeichert. Was '
        'möchtest du tun?',
    'profile.edit.unsavedDiscard': 'Verwerfen',
    'profile.edit.farAway':
        'Der Ort liegt mehr als 15 km von deinem aktuellen Standort '
        'entfernt ({meters} m). Bitte gib einen nahegelegenen Ort ein.',
    'profile.edit.distanceKm': 'Entfernung in km',
    'profile.edit.modeGermany': 'Ganz Deutschland',
    'profile.edit.habitsDealbreaker': 'Dealbreaker: gleicher Konsum',
    'profile.edit.habitsDealbreakerSub':
        'Zeig mir nur Personen, die maximal so viel konsumieren wie ich.',
    'profile.detail.aboutMe': 'Über mich',
    // Gespeicherte Profile (lokal, max. 5)
    'profile.detail.savedSave': 'Profil lokal speichern (später anschreiben)',
    'profile.detail.savedRemove': 'Gespeichertes Profil entfernen',
    'profile.detail.savedDone':
        '{name} lokal gespeichert. Du kannst {name} später anschreiben.',
    'profile.detail.savedRemoved': '{name} wurde entfernt.',
    'profile.detail.noBio': 'Noch keine Bio.',
    'profile.detail.interests': 'Interessen',
    'profile.detail.commonWithYou': 'Gemeinsam mit dir',
    'profile.detail.more': 'Weitere',
    'profile.detail.title': 'Profil',
    'profile.detail.retry': 'Erneut versuchen',
    'profile.detail.photosLockedHint':
        'Fotos erscheinen hier, sobald das Kennenlern-Quiz bestanden ist '
        'und die Person ein Profilbild hochgeladen hat.',
    'profile.detail.type': 'Typ {t}',
    'profile.detail.reportUser': 'Nutzer melden',
    'profile.detail.blockUser': 'Blockieren',
    'profile.detail.music': 'Musik',
    'profile.detail.favoriteSong': 'Lieblingssong: {song}',
    'profile.detail.favoriteBand': 'Lieblingsband: {band}',
    'profile.detail.sameTaste': 'Gleicher Geschmack',
    'profile.detail.noMusic': 'Kein Musik-Geschmack angegeben.',
    'common.refresh': 'Aktualisieren',
    'settings.twoFactor': 'Zwei-Faktor-Schutz (2FA)',
    'settings.twoFactorActive': 'Aktiv: Login nur mit Authenticator-Code',
    'settings.twoFactorSetup': 'Login zusätzlich mit Authenticator-App sichern',
    'settings.notifyLikesSub': 'Wenn dich jemand liked',
    'settings.notifyMessagesSub': 'Wenn dir jemand schreibt',
    'settings.unifiedPush': 'Push ohne Google (UnifiedPush)',
    'settings.unifiedPushOn': 'Aktiv - Endpunkt ist hinterlegt.',
    'settings.unifiedPushOff':
        'Benötigt eine Distributor-App wie ntfy (F-Droid). FCM bleibt in '
        'der Play-Variante aktiv.',
    'settings.blurSub':
        'Schutz vor unangemessenen Inhalten: Bilder deiner Gegenstelle '
        'werden erst nach Bestätigung gezeigt (lang drücken zum Melden).',
    'settings.keyBackup': 'Verschlüsseltes Key-Backup',
    'settings.keyBackupSub':
        'Sichert die private Identität deiner Ende-zu-Ende-Verschlüsselung '
        '(passwortverschlüsselt, AES-256-GCM). Nur damit kannst du nach '
        'Gerätewechsel wieder verschlüsselt chatten. Verlust von Backup '
        'UND Passwort ist unwiederbringlich.',
    'settings.backupCreateSub': 'Erzeugt einen verschlüsselten Code',
    'settings.backupRestoreSub': 'Überschreibt die aktuelle E2E-Identität',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Hilfe bei Belästigung oder Stalking, Blockieren, Melden',
    // Datenschutz & Account
    'privacy.title': 'Datenschutz & Account',
    'privacy.validator.invalidEmail': 'Ungültig',
    'privacy.validator.tooShort': 'Zu kurz',
    'privacy.validator.mismatch': 'Nicht identisch',
    'privacy.yourData': 'Deine Daten',
    'privacy.dataInfo':
        'Wisp speichert Profilinformationen, Standortdaten (nur wenn du '
        'sie freigibst), Fotos, Chats, Likes und Funken. Alle Daten '
        'werden verschlüsselt übertragen und nur so lange gespeichert, '
        'wie dein Account aktiv ist.',
    'privacy.export': 'Meine Daten exportieren',
    'privacy.exportSub': 'JSON Download aller personenbezogenen Daten',
    'privacy.exportFailed': 'Export fehlgeschlagen',
    'privacy.import': 'Daten importieren',
    'privacy.importSub': 'JSON-Datenexport wiederherstellen',
    'privacy.importTitle': 'Daten importieren',
    'privacy.importBody':
        'Füge hier den Inhalt deiner Export-Datei (wisp_data_export.json) '
        'ein. Profil, Einstellungen und Präferenzen werden '
        'wiederhergestellt.',
    'privacy.importHint': '{ ... JSON hier einfügen ... }',
    'privacy.importApply': 'Importieren',
    'privacy.importInvalid':
        'Das eingefügte JSON konnte nicht gelesen '
        'werden. Bitte prüfe den Inhalt.',
    'privacy.importDone': 'Daten erfolgreich importiert.',
    'privacy.importFailed': 'Import fehlgeschlagen',
    'privacy.accountSection': 'Anmeldung',
    'privacy.accountInfo':
        'E-Mail- und Passwort-Änderungen erfordern dein aktuelles '
        'Passwort. Bei E-Mail-Wechsel bestätigst du die neue Adresse '
        'über einen Link in beiden Postfächern.',
    'privacy.changeEmail': 'E-Mail-Adresse ändern',
    'privacy.changeEmailInfo':
        'Du erhältst einen Bestätigungs-Link an deine alte UND neue '
        'Adresse. Die Änderung wird erst nach Bestätigung aktiv.',
    'privacy.changeEmailSent':
        'Bestätigungs-Link an beide E-Mail-Adressen gesendet.',
    'privacy.changePassword': 'Passwort ändern',
    'privacy.changePasswordDone': 'Passwort geändert.',
    'privacy.changeFailed': 'Änderung fehlgeschlagen',
    'auth.passwordCurrent': 'Aktuelles Passwort',
    'auth.passwordNew': 'Neues Passwort',
    'auth.passwordConfirm': 'Neues Passwort wiederholen',
    'privacy.processors': 'Auftragsverarbeiter',
    'privacy.processorsInfo':
        'Folgende Dienstleister (Art. 28 DSGVO) verarbeiten Daten im '
        'Auftrag. Chat-Inhalte sind Ende-zu-Ende-verschlüsselt und werden '
        'von keinem Dienstleister verarbeitet.',
    'privacy.processorSupabase': 'Hosting, Datenbank, Authentifizierung (EU)',
    'privacy.processorGoogle': 'Push-Benachrichtigungen',
    'privacy.processorBrevo': 'Transaktions-E-Mails (Bestätigung, Reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile) und TURN-Relay',
    'privacy.processorNetlify': 'Hosting der Anmelde-/CAPTCHA-Seite',
    'privacy.processorApple': 'App-Store-Verteilung',
    'privacy.consent': 'Einwilligungen',
    'privacy.location': 'Standortfreigabe',
    'privacy.locationSub':
        'Du kannst die Standortfreigabe in den Systemeinstellungen deines '
        'Geräts jederzeit widerrufen.',
    'privacy.openLocationSettings': 'Standort-Einstellungen öffnen',
    'privacy.push': 'Push Benachrichtigungen',
    'privacy.pushSub':
        'Öffnet die App-Einstellungen deines Geräts, dort kannst du die '
        'Benachrichtigungen steuern.',
    'privacy.openAppSettings': 'App-Einstellungen öffnen',
    'privacy.dangerZone': 'Gefahrenzone',
    'privacy.deleteAccount': 'Account dauerhaft löschen',
    'privacy.deleteAccountSub':
        'DSGVO Art. 17: Recht auf Löschung. Alle Daten werden entfernt.',
    'privacy.deleteTitle': 'Account löschen?',
    'privacy.deleteBody':
        'Dieser Schritt kann nicht rückgängig gemacht werden. Alle deine '
        'Daten (Profil, Fotos, Chats, Funken, Likes) werden dauerhaft '
        'gelöscht.',
    'privacy.deleteConfirm': 'Endgültig löschen',
    'privacy.deleteFailed': 'Account konnte nicht gelöscht werden',
    'common.save': 'Speichern',
    'common.cancel': 'Abbrechen',
    'common.ok': 'OK',
    'common.yes': 'Ja',
    'common.no': 'Nein',
    'common.continue': 'Weiter',
    'common.back': 'Zurück',
    'whatsnew.title': 'Neu in dieser Version',
    'whatsnew.inputsTitle': 'Neu zum Auswählen',
    'whatsnew.cta': 'Los geht\'s',
    'common.loading': 'Lädt…',
    'common.errorOccurred': 'Es ist ein Fehler aufgetreten:',
    'validation.field': 'Feld',
    'validation.required': '{field} darf nicht leer sein',
    'validation.nameEmpty': 'Bitte gib einen Namen ein',
    'validation.nameShort': 'Name ist zu kurz',
    'validation.ageEmpty': 'Bitte gib dein Alter ein',
    'validation.ageNumber': 'Bitte eine Zahl eingeben',
    'validation.ageMin':
        'Du musst mindestens {age} Jahre alt sein, um diese App zu nutzen',
    'validation.ageInvalid': 'Bitte gib ein gültiges Alter ein',
    'validation.emailEmpty': 'Bitte gib deine Email ein',
    'validation.emailInvalid': 'Bitte gib eine gültige Emailadresse ein',
    'validation.emailTld':
        'Bitte gib eine Email mit gültiger Domainendung ein '
        '(z. B. .de, .com, .net, .org)',
    'validation.passwordEmpty': 'Bitte gib ein Passwort ein',
    'validation.passwordLength': 'Das Passwort braucht mindestens 8 Zeichen',
    'validation.passwordLetter':
        'Das Passwort braucht mindestens einen Buchstaben',
    'validation.passwordDigit': 'Das Passwort braucht mindestens eine Zahl',
    'validation.passwordCommon':
        'Dieses Passwort ist zu häufig. Bitte wähle ein sichereres.',
    'validation.pwChars': '8 Zeichen',
    'validation.pwLower': 'einen Kleinbuchstaben',
    'validation.pwUpper': 'einen Großbuchstaben',
    'validation.pwDigit': 'eine Zahl',
    'validation.pwSpecial': 'ein Sonderzeichen',
    'validation.pwMissing': 'Das Passwort braucht: {list}',
    'validation.pwWeak': 'Schwach',
    'validation.pwMedium': 'Mittel',
    'validation.pwStrong': 'Stark',
    'validation.birthEmpty': 'Bitte wähle dein Geburtsdatum',
    'validation.birthFuture':
        'Das Geburtsdatum darf nicht in der Zukunft liegen',
    'validation.birthInvalid': 'Bitte gib ein gültiges Geburtsdatum ein',
    'validation.bioLong': 'Maximal 300 Zeichen',
    'common.skip': 'Überspringen',
    'common.confirm': 'Bestätigen',
    'common.check': 'Prüfen',
    'common.discard': 'Verwerfen',
    'common.done': 'Fertig',
    'common.whatHappened': 'Was ist passiert?',
    'nav.unsavedTitle': 'Ungespeicherte Änderungen',
    'nav.unsavedBody':
        'Deine Profil-Änderungen wurden noch nicht gespeichert. Was '
        'möchtest du tun?',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email oder Passwort ist falsch.',
    'error.notConfirmed': 'Bitte bestätige zuerst deine Emailadresse.',
    'error.alreadyRegistered':
        'Diese Emailadresse ist bereits registriert. Bitte melde dich '
        'direkt an oder setze dein Passwort zurück.',
    'error.rateLimited':
        'Zu viele Anfragen in kurzer Zeit. Bitte warte '
        'einen Moment und versuche es erneut.',
    'error.weakPassword':
        'Das Passwort ist zu schwach. Bitte wähle ein '
        'längeres Passwort mit Groß-/Kleinbuchstaben, Zahlen und '
        'Sonderzeichen.',
    'error.captchaRejected':
        'Der Sicherheitscheck wurde vom Server '
        'abgelehnt. Bitte versuche es erneut.',
    'error.signupFailed':
        'Registrierung auf dem Server fehlgeschlagen. '
        'Bitte versuche es später erneut.',
    'error.loginFailed':
        'Anmeldung fehlgeschlagen. Bitte versuche es '
        'erneut.',
    'error.generic': 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
    // Admin-Bereich (nur für Moderation sichtbar)
    'admin.deniedTitle': 'Zugriff verweigert',
    'admin.deniedBody': 'Du hast keine Berechtigung, diesen Bereich zu öffnen.',
    'admin.title': 'Admin-Bereich',
    'admin.tabReports': 'Meldungen',
    'admin.tabBugs': 'Bug-Reports',
    'admin.tabVerification': 'Verifizierung',
    'admin.tabModeration': 'Moderation',
    'admin.tabAppeals': 'Bild-Prüfung',
    'admin.tabBans': 'Sperren',
    'admin.close': 'Schließen',
    'admin.error': 'Fehler: {error}',
    'admin.retry': 'Erneut versuchen',
    'admin.unknown': 'unbekannt',
    'admin.reportResolveFailed': 'Konnte Meldung nicht abschließen: {error}',
    'admin.noReports': 'Keine Meldungen vorhanden.',
    'admin.noBugs': 'Keine Bug-Reports vorhanden.',
    'dh.event.joinConfirmBody':
        'Du wirst nur dann mit jemandem verbunden, wenn du jetzt '
        'bestätigst. Du kannst jederzeit aussteigen.',
    'dh.duration.minute': '{m} Minute',
    'dh.duration.minutes': '{m} Minuten',
    'dh.duration.hour': '{h} Stunde',
    'dh.duration.hours': '{h} Stunden',
    // Safety Center
    'safety.centerTitle': 'Safety Center',
    'safety.myReports': 'Meine Meldungen',
    'safety.noReports': 'Du hast bisher keine Meldungen geschrieben.',
    'safety.unblockFailed':
        'Entblocken fehlgeschlagen. Bitte erneut versuchen.',
    'safety.blockedUsers': 'Blockierte Nutzer',
    'safety.noBlocked': 'Du hast niemanden blockiert.',
    'safety.unblock': 'Entblocken',
    // Stimmung
    'mood.title': 'Stimmung des Tages',
    'mood.saved': 'Mood gespeichert',
    'mood.question': 'Wie fühlst du dich heute?',
    'mood.explainer':
        'Dein Mood hilft uns, dir passendere Vorschläge zu machen.',
    'mood.saving': 'Speichern...',
    'mood.save': 'Speichern',
    'mood.current': 'Aktuelle Stimmung',
    // Aktuelles (Home)
    'home.title': 'Aktuelles',
    'home.fallbackName': 'du',
    'home.discover': 'Leute entdecken',
    'home.randomChat': 'Zufallschat starten',
    // Find your Match
    'match.required': 'Text UND Audio sind Pflicht.',
    'match.title': 'Find your Match',
    'match.editIntro': 'Meine Vorstellung bearbeiten',
    'match.createFirst': 'Erstelle zuerst deine eigene Vorstellung',
    'match.createSub':
        'Andere lernen dich über deine Vorstellung kennen, bevor sie '
        'ein Foto sehen.',
    'match.saveContinue': 'Speichern & weiter',
    'match.empty': 'Aktuell gibt es keine neuen Vorstellungen.',
    'match.introTitle': 'Vorstellung',
    'match.noIntro': 'Diese Person hat noch keine Vorstellung hinterlegt.',
    'match.interestsTitle': 'Interessen',
    'match.emptyTip':
        'Tipp: Hinterlege selbst eine Vorstellung in deinem Profil, '
        'dann wirst du hier anderen angezeigt.',
    'match.reload': 'Neu laden',
    // Start / Update
    'startup.failedTitle': 'Die App konnte nicht gestartet werden.',
    'startup.failedBody':
        'Bitte schließe die App komplett und versuche es erneut.',
    'update.required': 'Update erforderlich',
    'update.body':
        'Deine Version von Wisp unterstützt nicht mehr alle '
        'Server-Funktionen. Bitte aktualisiere die App, um '
        'weiterzumachen.',
    'update.now': 'Jetzt aktualisieren',
    'update.later': 'Trotzdem fortfahren',
    // Video-Verifizierung
    'verify.title': 'Video-Verifizierung',
    'verify.start': 'Video-Verifizierung starten',
    'verify.errorTitle': 'Fehler',
    'verify.infoBody':
        'Um sicherzugehen, dass echte Menschen die App nutzen, machst du '
        'ein kurzes Selbstvideo (5 bis 15 Sekunden).',
    'verify.infoCardTitle': 'Was passiert mit deinem Video?',
    'verify.info.1': 'Das Video wird **lokal verschlüsselt** gespeichert.',
    'verify.info.2':
        'Nach dem Einreichen liegt es in einem **privaten Speicher**. Nur '
        'der Support kann es zur Prüfung ansehen.',
    'verify.info.3':
        'Es dient der **persönlichen Prüfung durch den Support** '
        '(Mensch-Verifizierung).',
    'verify.info.4':
        'Es wird **niemals** öffentlich angezeigt oder an Dritte '
        'weitergegeben.',
    'verify.info.5':
        'Du kannst es jederzeit löschen; bei Ablehnung wird es automatisch '
        'entfernt.',
    'verify.info.6':
        'Nimm **Kopfbedeckung, Kopfhörer, Sonnenbrille und Maske ab**: '
        'Das Gesicht muss frei erkennbar sein, sonst prüft der Support '
        'manuell nach.',
    'verify.locationTitle': 'Einmalige Standortabfrage',
    'verify.locationBody':
        'Zusätzlich fragen wir **einmalig** deinen GPS-Standort ab. Dies '
        'hilft uns, massenhaft Fake-Accounts vom selben Ort oder Gerät zu '
        'erkennen. Der Standort wird **nur** für diese Sicherheitsprüfung '
        'gespeichert und nicht für Matching genutzt.',
    'verify.taskTitle': 'Deine Aufgabe:',
    'verify.recording': 'Aufnahme: {s} s',
    'verify.recordHint':
        'Mindestens 5 Sekunden, maximal 15 Sekunden aufnehmen.',
    'verify.recordFaceHint':
        'Gesicht frei zeigen: keine Kopfbedeckung, Kopfhörer oder '
        'Sonnenbrille.',
    'verify.stopHint': 'Tippe erneut zum Stoppen (Auto-Stopp bei 15 s)',
    'verify.processing':
        'Video wird ausgewertet. Bitte kurz warten, das kann bis zu '
        'einer halben Minute dauern.',
    'verify.cameraError': 'Kamera konnte nicht initialisiert werden: {error}',
    'verify.challenge.base.speakNumber': 'Sage die angezeigte Zahl laut vor.',
    'verify.challenge.base.makeGesture': 'Mache die angezeigte Geste.',
    'verify.challenge.base.turnHead': 'Drehe den Kopf langsam.',
    'verify.challenge.base.smile': 'Lächle kurz in die Kamera.',
    'verify.challenge.task': 'Deine Aufgabe:',
    'verify.challenge.gesture.tongue': 'Zunge rausstrecken',
    'verify.challenge.gesture.blink': 'Einmal blinzeln',
    'verify.challenge.gesture.brows': 'Augenbrauen hochziehen',
    'verify.challenge.direction.left_right': 'links und rechts',
    'verify.challenge.direction.right_left': 'rechts und links',
    'verify.challenge.action.smile': 'lächeln',
    // Chat-Details + Anruf
    'chat.title': 'Chat',
    'chat.gone': 'Dieser Chat existiert nicht mehr.',
    'chat.imagePrepareFailed':
        'Bild konnte nicht sicher aufbereitet werden und wurde nicht '
        'gesendet.',
    'chat.callMicDenied': 'Mikrofon-Zugriff verweigert.',
    'chat.callVoiceFailed': 'Sprachpaket konnte nicht gesendet werden.',
    'chat.callStatusConnecting': 'Verbinde…',
    'chat.callStatusRingingOut': 'Es klingelt…',
    'chat.callStatusRingingIn': 'Eingehender Anruf…',
    'chat.callStatusConnected': 'Verbunden',
    'chat.callStatusRecording': 'Aufnahme… {s} s',
    'chat.callStatusDeclined': 'Anruf abgelehnt',
    'chat.callStatusEnded': 'Anruf beendet',
    'chat.callStatusUnreachable': 'Keine direkte Verbindung möglich',
    'chat.callPttHold': 'Gedrückt halten zum Sprechen',
    'chat.callMuted': 'Stumm',
    'chat.callUnmuted': 'Mikrofon',
    'chat.callE2eInfo':
        'Sprache ist Ende-zu-Ende verschlüsselt und läuft direkt '
        'Peer zu Peer (Push to Talk).',
    'chat.callNetHint':
        'Hinweis: Sprachanrufe laufen direkt zwischen den Geräten und '
        'funktionieren nur im WLAN zuverlässig. Im Mobilfunknetz sollten '
        'Anrufe nicht gestartet werden.',
    'chat.e2eReady': 'Ende-zu-Ende verschlüsselt (Signal-Protokoll via P2P)',
    'chat.e2eWaiting': 'E2E-Verbindung wird aufgebaut.',
    'chat.connDiag': 'Technik: ICE {ice} - automatischer Neuversuch läuft.',
    'chat.connError': 'Letzter Fehler: {error}',
    // Datenschutz: TOTP-Bestätigung
    'privacy.totpTitle': 'Konto bestätigen',
    'privacy.totpLabel': 'TOTP-Code (Authenticator-App)',
    'privacy.totpConfirm': 'Bestätigen',
    // Melden (Nutzer + Bilder)
    'report.userTitle': 'Nutzer melden: {name}',
    'report.userTooltip': 'Nutzer melden',
    'report.sendDone': 'Meldung gesendet. Danke für deine Hilfe!',
    'report.imageTitle': 'Bild melden: {name}',
    'report.imageUnavailable': 'Dieses Bild kann leider nicht gemeldet werden.',
    'report.sendReport': 'Meldung absenden',
    'report.analyzing': 'Bild wird lokal analysiert…',
    'report.noLocalModel':
        'Lokale Prüfung nicht verfügbar (Modell fehlt). Die Meldung '
        'läuft über den serverseitigen Fallback.',
    'report.failedTitle': 'Meldung fehlgeschlagen',
    'report.aiResult': 'KI-Ergebnis',
    'report.forwardedTitle': 'Weitergeleitet',
    'report.forwardedBody':
        'Deine Meldung wurde zur manuellen Prüfung an unser Team '
        'weitergeleitet - inklusive Bild, deinem Report und dem '
        'KI-Ergebnis. Danke für deine Hilfe!',
    'common.retry': 'Erneut versuchen',
    // 404-Fehlerseite
    'error.notFoundTitle': 'Seite nicht gefunden',
    'error.notFoundBody':
        'Diese Seite existiert nicht (mehr). Kein Problem, du kommst '
        'gleich weiter.',
    'error.goHome': 'Zur Startseite',
    // Melden: KI-Bestätigung
    'report.aiConfirm':
        'Danke! Die KI stuft das Bild ebenfalls als unangemessen ein '
        '(Score {score}%).',
    'report.aiEscalated':
        'Bild, dein Report und das KI-Ergebnis wurden automatisch an '
        'unser Team gesendet.',
    'report.aiNotNotified':
        'Hinweis: Das Team konnte nicht per E-Mail benachrichtigt werden '
        '- deine Meldung ist trotzdem gespeichert.',
    'genderpref.all': 'Alle',
    'random.connectFailed': 'Verbindung zum Partner fehlgeschlagen: {error}',
    'random.notLoggedIn': 'Nicht eingeloggt - Zufallschat nicht verfügbar.',
    'random.fallbackPartnerName': 'Zufallspartner',
    'random.fallbackTitle': 'Zufallschat',
    'dm.photosNote':
        'Fotos siehst du erst, wenn du das Kennenlern-Quiz nach '
        'einem Funke bestehst. Bis dahin zählt, was jemand über '
        'sich erzählt.',
    'admin.reportedUser': 'Gemeldeter Nutzer: {id}',
    'admin.reporter': 'Reporter: {id} (gehasht)',
    'admin.messagesAttached': '{count} Nachricht(en) beigelegt',
    'admin.resolved': 'Bearbeitet',
    'admin.statusPending': 'ausstehend',
    'admin.noDescription': '(ohne Beschreibung)',
    'admin.attachments': 'Anhänge: {count} · {time}',
    'admin.user': 'Nutzer: {id}',
    'admin.reviewFailed': 'Review fehlgeschlagen: {error}',
    'admin.noVideoUrl': 'keine Video-URL erhalten',
    'admin.browserOpenFailed': 'Browser konnte URL nicht öffnen',
    'admin.videoFailed': 'Video konnte nicht geladen werden: {error}',
    'admin.watchVideo': 'Video ansehen',
    'admin.approve': 'Freigeben',
    'admin.rejectWithVideo': 'Ablehnen (Video wird gelöscht)',
    'admin.noVerifications': 'Keine offenen Verifizierungen.',
    'admin.auditTitle': 'Stichproben: Auto-Freigaben',
    'admin.auditEmpty': 'Keine Auto-Freigaben zur Stichprobe.',
    'admin.ageNoAi': 'Alter: Angabe {stated} (keine KI-Schätzung)',
    'admin.ageAi': 'Alter: Angabe {stated}, KI {est} (Abweichung {dev})',
    'admin.noModeration': 'Keine ausstehenden Moderationen.',
    'admin.approveTooltip': 'Genehmigen',
    'admin.rejectTooltip': 'Ablehnen',
    'admin.banUser': 'Nutzer sperren',
    'admin.banTarget': 'E-Mail oder User-ID',
    'admin.banTargetHint': 'z. B. aus der Meldungs-Mail kopiert',
    'admin.banReason': 'Begründung (Pflicht)',
    'admin.banReasonHint': 'Warum wird der Nutzer gesperrt?',
    'admin.required': 'Pflichtfeld',
    'admin.minChars': 'Mindestens 3 Zeichen',
    'admin.notifyUser': 'Nutzer per E-Mail informieren',
    'admin.notifySub':
        'Enthält die Begründung und den Weg zum Entsperrungsantrag',
    'admin.banHint':
        'Hinweis: Mit User-ID wird zusätzlich der bestehende Account '
        'sofort gesperrt (Sessions ungültig). Mit nur E-Mail ist die '
        'Neu-Registrierung blockiert.',
    'admin.cancel': 'Abbrechen',
    'admin.banned': 'Nutzer gesperrt.',
    'admin.ban': 'Sperren',
    'admin.banFailed': 'Sperren fehlgeschlagen.',
    'admin.actionFailed': 'Aktion fehlgeschlagen (Status {status}).',
    'admin.unbanTitle': 'Entsperren?',
    'admin.unbanBody':
        '{email} kann sich wieder registrieren und anmelden. Der '
        'Entsperrungsantrag sollte vorher geprüft worden sein.',
    'admin.unban': 'Entsperren',
    'admin.unbanned': '{email} wurde entsperrt.',
    'admin.unbanFailed': 'Entsperren fehlgeschlagen.',
    'admin.noBans': 'Keine Sperren vorhanden.',
    'admin.bannedBy': '{time} · von {by}',
    'admin.decideFailed': 'Entscheidung fehlgeschlagen: {error}',
    'admin.noAppeals': 'Keine offenen Bild-Einsprüche.',
    'admin.appealSubmitted': 'Eingereicht: {time}',
    'admin.appealFinding': 'Lokaler Befund: {label} ({score} %)',
    'ai.localBadge': 'On-Device-KI',
    'ai.cloudBadge': 'Cloud-KI',
    'call.icebreakerTitle': 'Eisbrecher-Fragen',
    'call.icebreakerHint':
        'Stöbere in der Sammlung und stelle die Frage laut - '
        'zum Weiterreden, wenn es still wird.',
    'birthday.styleTitle': 'Geburtstags-Stil',
    'birthday.pickHint':
        'Wähle, wie dein Profil an deinem Geburtstag aussieht.',
    'birthday.style.classic': 'Klassisch',
    'birthday.style.midnight': 'Mitternacht',
    'birthday.style.sage': 'Salbei',
    'birthday.style.rose': 'Rosé',
    'birthday.style.mono': 'Mono',
    'birthday.todayTitle': 'Alles Gute zum Geburtstag!',
    'chat.icebreakerSuggestTitle': 'Gesprächseinstieg gefällig?',
    'chat.icebreakerSuggestBody':
        'Ihr habt euch noch nichts geschrieben. Wie wäre es mit '
        'einer Eisbrecher-Frage an dein Gegenüber?',
    'chat.icebreakerSuggestSend': 'Frage senden',
    'chat.icebreakerSuggestLater': 'Später',
    'admin.statusOpen': 'Offen',
    'admin.statusApproved': 'Freigegeben',
    'admin.statusRejected': 'Abgelehnt',
    'admin.statusNotified': 'Quittiert',
  },
  'en': {
    'auth.login': 'Log in',
    'auth.lockedOut':
        'Too many failed sign-in attempts. Please wait {minutes} minute(s) '
        'and try again.',
    'auth.lockedOut10':
        'Too many failed sign-in attempts. Sign-in is locked for {minutes} '
        'minutes.',
    'auth.register': 'Sign up',
    'auth.name': 'Name',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.passwordHint': 'At least 8 characters',
    'auth.forgot': 'Forgot password?',
    'auth.keepLoggedIn': 'Stay logged in',
    'auth.keepLoggedInSub':
        'Stay automatically logged in when you close the app (recommended).',
    'mfa.title': 'Security code',
    'mfa.body': 'Enter the code from your authenticator app',
    'mfa.paste': 'Paste',
    'mfa.setupTitle': 'Secure account',
    'mfa.activeTitle': '2FA is enabled',
    'mfa.activeBody':
        'Your account is protected with an authenticator app. When '
        'logging in, the current code is requested in addition to your '
        'password.',
    'mfa.introTitle': 'Protect your account with a second factor',
    'mfa.introBody':
        'With an authenticator app (e.g. Google Authenticator, Aegis or '
        '2FAS) you create a one-time code at every login. Only with this '
        'code can someone log into your account, even if your password '
        'was stolen.',
    'mfa.introSkip': 'You can skip this step and complete setup anytime later.',
    'mfa.setupScan': 'Set up with authenticator app',
    'mfa.setupLater': 'Remind later',
    'mfa.scanStep': '1. Scan QR code',
    'mfa.scanBody':
        'Open your authenticator app (e.g. Google Authenticator, Aegis '
        'or 2FAS) and add the entry via QR scan.',
    'mfa.manualKey': 'No scan possible? Enter this key manually (tap to copy):',
    'mfa.copied': 'Key copied. Will be deleted automatically in 30 s.',
    'mfa.setupNext': 'Next: enter code',
    'mfa.setupNextHint':
        'Afterwards, enter the 6-digit code from your authenticator '
        'app once to confirm setup.',
    'mfa.confirmStep': '2. Enter code',
    'mfa.confirmBody':
        'Enter the current 6-digit code from your authenticator app to '
        'confirm setup:',
    'mfa.setupBackQr': 'Back to QR code',
    'mfa.doneTitle': 'Two-factor protection active!',
    'mfa.doneBody':
        'From now on you will be asked for the code from your '
        'authenticator app at every login.',
    'auth.toRegister': 'No account yet? Sign up',
    'auth.toLogin': 'Already have an account? Log in',
    'auth.passkey': 'Sign in with Passkey',
    'auth.passkeyCreate': 'Create Passkey',
    'auth.captcha': 'Security check',
    'auth.registerTitle': 'Create account',
    'auth.welcomeBack': 'Welcome back',
    'auth.birthDate': 'Date of birth',
    'auth.birthDateHint': 'DD MM YYYY',
    'auth.birthDatePick': 'Please select',
    'auth.birthDateMissing': 'Please choose your date of birth.',
    'auth.ageConfirmTitle': 'My date of birth is correct',
    'auth.ageConfirmSub':
        'False age information endangers others, especially young users, '
        'and leads to a permanent ban.',
    'auth.ageConfirmRequired':
        'Please confirm that your date of birth is correct.',
    'auth.liabilityNote':
        'Note: Wisp cannot verify every detail. Never rely on profile '
        'information alone, only meet in public places and report '
        'suspected false age immediately.',
    'email.resent':
        'Confirmation email has been resent. Please also check your '
        'spam folder.',
    'email.rateLimited': 'Too many requests. Please wait a moment.',
    'email.confirmed': 'Email confirmed!',
    'email.waiting': 'Waiting for confirmation...',
    'email.demoContinue': 'In the demo you can continue directly.',
    'email.title': 'Confirm email',
    'email.heading': 'Confirm your email address',
    'email.body':
        'We sent you a confirmation email. Please click the link in the '
        'email to activate your account. Afterwards it continues '
        'automatically.',
    'email.sending': 'Sending...',
    'email.sent': 'Email sent',
    'email.cooldown': 'Resend in {s}s',
    'email.resend': 'Resend confirmation email',
    'email.continueBtn': 'I confirmed the email: Continue',
    'email.dnsHint':
        'Email link not coming through? This can be caused by active DNS '
        'filters or VPNs (e.g. DNS Forge) blocking tracking links. '
        'Temporarily disable the filter and click the link again. You can '
        're-enable it after confirmation.',
    'email.reportIssue': 'Report issue',
    'email.logout': 'Log out',
    'email.cancel': 'Cancel registration',
    'email.cancelTitle': 'Cancel registration?',
    'email.cancelBody':
        'Your not yet confirmed account will be deleted in Supabase. '
        'Any details already entered will be lost.',
    'email.cancelConfirm': 'Yes, delete account',
    'email.cancelKeep': 'Keep going',
    'email.deleted': 'Registration cancelled, account deleted.',
    'email.cancelExpired':
        'Credentials expired - just sign up again, the confirmation '
        'will be re-sent.',
    'email.deleteFailed': 'Delete failed: {error}',
    'forgot.title': 'Forgot password',
    'forgot.heading': 'Reset password',
    'forgot.body':
        'Enter your email address. We will send you a link to reset your '
        'password.',
    'forgot.sentBody':
        'If an account with this email exists, we sent a reset link.',
    'forgot.sentBox': 'If an account with this email exists, a link was sent.',
    'forgot.email': 'Email',
    'forgot.sending': 'Sending…',
    'forgot.toLogin': 'Back to login',
    'forgot.sendLink': 'Send link',
    'reset.title': 'New password',
    'reset.doneTitle': 'Password changed',
    'reset.doneBody':
        'Your new password has been saved. For security reasons you were '
        'logged out on all devices. Please log in again.',
    'reset.toLogin': 'To login',
    'reset.heading': 'Set new password',
    'reset.body':
        'Choose a new password for your account. It must be at least 8 '
        'characters long and contain letters and numbers.',
    'reset.newPassword': 'New password',
    'reset.repeat': 'Repeat password',
    'reset.repeatMissing': 'Please repeat the password',
    'reset.mismatch': 'Passwords do not match.',
    'reset.save': 'Save password',
    'unban.title': 'Unban request',
    'unban.doneTitle': 'Request sent',
    'unban.doneBody':
        'Your unban request was submitted to support. We will review the '
        'case and contact you by email.',
    'unban.heading': 'Account banned?',
    'unban.body':
        'This email address is banned on the platform. If you believe '
        'this is a mistake, send an unban request. We will review the '
        'case.',
    'unban.email': 'Email address',
    'unban.emailMissing': 'Please enter your email address.',
    'unban.emailInvalid': 'Please enter a valid email address.',
    'unban.reason': 'Reason',
    'unban.reasonHint':
        'Briefly explain why your account should be unbanned '
        '(at least 20 characters).',
    'unban.reasonShort': 'Please provide a reason with at least 20 characters.',
    'unban.send': 'Send request',
    'unban.backToLogin': 'Back to login',
    'auth.gender': 'Gender',
    'gender.male': 'Male',
    'gender.maleTrans': 'Male (F to M)',
    'gender.female': 'Female',
    'gender.femaleTrans': 'Female (M to F)',
    'gender.diverse': 'Diverse',
    'gender.other': 'Own / Other',
    'auth.passwordHintStrong':
        'At least 8 characters, with upper and lower '
        'case letters, a number and a special character',
    'auth.showPassword': 'Show password',
    'auth.hidePassword': 'Hide password',
    'auth.captchaRegister': 'Please complete the security check to sign up.',
    'auth.captchaLogin': 'Please complete the security check to log in.',
    'captcha.retry': 'Try again',
    'language.german': 'German',
    'language.english': 'English',
    'nav.home': 'Home',
    'nav.discover': 'Discover',
    'nav.interests': 'Interests',
    'nav.profile': 'Profile',
    'settings.title': 'Settings',
    'settings.appearance': 'Appearance',
    'settings.system': 'System',
    'settings.light': 'Light',
    'settings.dark': 'Dark',
    'settings.colors': 'Color scheme',
    'settings.language': 'Language',
    'settings.notifications': 'Notifications',
    'settings.push': 'Push notifications',
    'settings.pushEnable': 'Enable notifications',
    'settings.pushEnableSub': 'Messages, likes, sparks and event reminders',
    'settings.notifyMessages': 'Chat messages',
    'settings.notifyLikes': 'New likes',
    'settings.notifyFunken': 'New sparks',
    'settings.notifyFunkenSub': 'When a spark is created',
    'settings.notifyDatingHour': 'Dating Hour reminder',
    'settings.notifyDatingHourSub': '10 minutes before start, if joined',
    'settings.chatSafety': 'Chat safety',
    'settings.blur': 'Show pictures pixelated',
    'settings.e2e': 'E2E identity',
    'settings.backupCreate': 'Create backup',
    'settings.backupRestore': 'Restore backup',
    'settings.passkeyDiagnose': 'Passkey diagnostics',
    'settings.privacyAccount': 'Privacy & account',
    'settings.privacyAccountSub': 'Stored data, consents, delete account',
    'settings.pause': 'Pause profile',
    'settings.pauseSub':
        'Invisible in Discovery and Find your Match. Sparks and chats '
        'remain.',
    'settings.pauseActive': 'Profile is paused and invisible to new people.',
    'settings.pauseConfirmTitle': 'Pause profile?',
    'settings.pauseConfirmBody':
        'Your profile will no longer appear in Discovery and Find your '
        'Match. Existing sparks and chats remain. You can end the pause '
        'at any time.',
    'settings.pauseConfirmBtn': 'Pause',
    'settings.pauseOn':
        'Profile paused. You are invisible until you end the pause.',
    'settings.pauseOff': 'Pause ended. Your profile is visible again.',
    'settings.visEveryoneSub':
        'Your profile appears in Discovery and Find your Match.',
    'settings.visMatchesSub':
        'Only people you have a spark with can see your profile.',
    'settings.visHiddenSub':
        'Pause mode: invisible to all new people. Sparks and chats remain.',
    'settings.visEveryone': 'Everyone',
    'settings.visMatchesOnly': 'Sparks only',
    'settings.visHidden': 'Invisible (paused)',
    'mood.happy': 'Happy',
    'mood.relaxed': 'Relaxed',
    'mood.adventurous': 'Adventurous',
    'mood.flirty': 'Flirty',
    'mood.thoughtful': 'Thoughtful',
    'mood.tired': 'Tired',
    'theme.classic': 'Classic WispDating',
    'theme.ocean': 'Ocean',
    'theme.forest': 'Forest',
    'theme.sunset': 'Sunset',
    'theme.lavender': 'Lavender',
    'theme.slate': 'Slate',
    'theme.colorScheme': 'Color scheme',
    'dm.discovery': 'Discover',
    'dm.discoveryDesc': 'Browse profiles, send sparks, chat',
    'dm.findMatch': 'Find your Match',
    'dm.findMatchDesc': 'Listen to or read the intro, then decide',
    'dm.randomChat': 'Random chat',
    'dm.randomChatDesc': 'Direct text chat with a randomly matched person',
    'dm.qrScan': 'Scan QR code',
    'dm.qrScanDesc': "Scan someone's code and connect instantly",
    'dm.datingHour': 'Dating Hour (event)',
    'dm.datingHourDesc':
        'Saturdays 8 to 9 pm: 5-minute chats with a decision phase',
    'dm.transitSpark': 'Transit Spark',
    'dm.transitSparkDesc':
        'Exchanged glances but too shy? Spark later - even after you have '
        'both moved on.',
    'dm.groupMeet': 'Meet people',
    'dm.groupDirect': 'Connect directly',
    'dm.groupOnTheGo': 'On the go',
    'dm.pickHint': 'Choose a mode to discover new people:',
    'common.new': 'NEW',
    'transit.title': 'Transit Spark',
    'transit.start': 'Activate radar',
    'transit.stop': 'Stop radar',
    'transit.active': 'Radar active - visible to nearby Wisp devices.',
    'transit.inactive': 'Radar off. Activate it when you are on the go.',
    'transit.remaining': 'Active for another {time}',
    'transit.seenCount': 'Seen {count} Wisp devices in range.',
    'transit.exchanged': 'Exchanged glances',
    'transit.modeLabel': 'How far should detection reach?',
    'transit.mode.transit': 'Normal',
    'transit.mode.convention': 'Only right next to me',
    'transit.modeHint':
        'Convention mode: only strong signals count (real sight contact '
        'in dense environments).',
    'transit.sheetTitle': 'Who was it?',
    'transit.sheetHint':
        'Pick 2-5 traits you noticed about the person - your selection '
        'sharpens the matching.',
    'transit.sheetSend': 'Spark',
    'transit.tag.black_hoodie': 'Hoodie (black)',
    'transit.tag.tshirt': 'T-shirt',
    'transit.tag.sweater': 'Sweater',
    'transit.tag.shorts': 'Shorts',
    'transit.tag.pants': 'Long pants',
    'transit.tag.sporty': 'Sporty clothes',
    'dm.appbarTitle': 'Choose discovery mode',
    'fym.introSaved': 'Intro saved. Enjoy getting to know each other!',
    'setup.appbarTitle': 'Settings & privacy',
    'setup.filterTitle': 'Filters & preferences',
    'setup.filterSub': 'Who would you like to meet?',
    'setup.openAll': 'Open to everything',
    'setup.photoTooltip': 'Choose profile picture',
    'setup.pleasePick': 'Please choose',
    'setup.locationDone': 'Location detected and applied (GPS coordinates).',
    'setup.passkeyDone': 'Passkey set up. You can now sign in with it.',
    // One-time setup as interview (Wisp question bubbles)
    'setupq.visibility':
        'How private would you like to stay - and how should the app look?',
    'setupq.filter': 'What should Wisp search for on your behalf?',
    'setupq.profile':
        'What makes you you? A photo, a few words, your interests.',
    'setupq.intro':
        'How do you sound? Tell about yourself - in text and voice.',
    'setupq.habits': 'How do you feel about smoking, alcohol and drugs?',
    'setupq.passkey':
        'Would you like to secure your account with a passkey? It is quick.',
    'setupq.mfa': 'Would you like to add a second factor on top?',
    'setupq.guidelines':
        'Would you like to accept our community of values and its rules?',
    // Passkey setup during one-time setup
    'setup.passkeySetupFailed':
        'Passkey setup failed or was cancelled. You can do it later any '
        'time in the settings.',
    // Security nudge before finishing
    'setup.nudgeTitle': 'Strongly recommended',
    'setup.nudgeBody':
        'Secure your account now with a passkey or two-factor '
        'authentication. Without a second factor anyone with your '
        'password can take over your account - especially risky for a '
        'dating app.',
    'setup.nudgeSkip': 'Continue anyway',
    'setup.nudgeMfa': 'Set up 2FA',
    'setup.nudgePasskey': 'Set up passkey',
    'transit.tag.hoodie': 'Hoodie',
    'transit.tag.top': 'Top',
    'transit.colorOptional': 'Color (optional)',
    'transit.color.black': 'Black',
    'transit.color.white': 'White',
    'transit.color.grey': 'Grey',
    'transit.color.blue': 'Blue',
    'transit.color.green': 'Green',
    'transit.color.red': 'Red',
    'transit.color.yellow': 'Yellow',
    'transit.color.orange': 'Orange',
    'transit.color.pink': 'Pink',
    'transit.color.brown': 'Brown',
    'transit.color.purple': 'Purple',
    'transit.color.teal': 'Teal',
    'transit.self.title': 'How do you look right now?',
    'transit.self.hint':
        'Pick 2-5 traits describing yourself - only this way others '
        'can find you via Transit Spark. Re-enter daily.',
    'transit.modeDesc.transit':
        'Typical range: passing encounters, e. g. on the street as a '
        'pedestrian, on the train or in a café.',
    'transit.modeDesc.convention':
        'Tightly limited: only people right next to you count. Ideal '
        'for packed conventions, concerts and events.',
    'transit.tag.jacket': 'Jacket',
    'transit.tag.cap': 'Cap',
    'transit.tag.glasses': 'Glasses',
    'transit.tag.headphones': 'Headphones',
    'transit.tag.backpack': 'Backpack',
    'transit.tag.tote_bag': 'Tote bag',
    'transit.tag.lanyard': 'Lanyard / badge',
    'transit.tag.scarf': 'Scarf',
    'transit.tag.colorful_top': 'Colorful top',
    'transit.greetSection': 'Devices seen in this session',
    'transit.greet': 'Greet',
    'transit.justNow': 'just now',
    'transit.minutesAgo': '{count} min ago',
    'transit.hoursAgo': '{count} h ago',
    'transit.noEncounters': 'No devices in range yet.',
    'transit.pingSheetTitle': 'Send a greeting',
    'transit.pingSheetHint':
        'Possible once per encounter. The person decides quietly '
        'whether to respond - you will only hear about a yes.',
    'transit.pingSend': 'Send greeting',
    'transit.pingSent': 'Greeting sent. 48-hour window - that is all.',
    'transit.pingCustomHint': 'Optional: one short line of your own …',
    'transit.preset.wave': 'Hi! I was just near you.',
    'transit.preset.again': 'Maybe our paths will cross again?',
    'transit.preset.coffee': 'If you like: a coffee nearby?',
    'transit.inboxTitle': 'Greetings for you',
    'transit.ignore': 'Hide',
    'transit.accept': 'Accept spark',
    'transit.locationActiveTitle': 'Location enabled',
    'transit.locationActiveBody':
        'Your location is now turned on. Tap "Start radar" to begin '
        'directly with your previously selected traits - no need to '
        're-enter anything.',
    'transit.locationActiveBtn': 'Start radar',
    'transit.matchTitle': 'Spark jumped over!',
    'transit.matchBody':
        'The other person felt the same moment. Check your sparks - you '
        'can chat now.',
    'transit.later': 'Later',
    'transit.openSparks': 'To the sparks',
    'transit.startFailed':
        'Radar could not start. Turn on Bluetooth and grant permission.',
    'transit.btTitle': 'Turn on Bluetooth',
    'transit.btBody':
        'Transit Spark needs Bluetooth turned on. Turn it on now?',
    'transit.btEnable': 'Turn on now',
    'transit.locationTitle': 'Turn on location',
    'transit.locationBody':
        'The radar needs the location SERVICE (GPS) turned on (Android '
        'requires this for BLE scans, especially Android 11). The app '
        'cannot turn it on itself - please enable it in system settings '
        'and restart the radar afterwards.',
    'transit.locationOpen': 'Open settings',
    'transit.permissionTitle': 'Permission required',
    'transit.permissionBody':
        'The radar cannot start without this permission. Please grant it '
        'in app settings and try again.',
    'transit.permissionOpen': 'Open app settings',
    'transit.advertiseBody':
        'To broadcast your presence, the app needs the Bluetooth '
        'advertising permission (Android 12+). Please grant it and '
        'restart the radar.',
    'transit.cleanupTitle': 'Turn off after radar?',
    'transit.cleanupBody':
        'Radar is off. Bluetooth and location stay on - turn them off '
        'yourself in settings, the app is not allowed to.',
    'transit.cleanupToggle': 'Remind after radar',
    'transit.cleanupToggleSub':
        'Off. Asks after radar sessions whether to turn off '
        'Bluetooth/location.',
    'transit.cleanupOpenLocation': 'Location',
    'transit.cleanupOpenBluetooth': 'Bluetooth',
    'transit.cleanupLater': 'Later',
    'transit.batteryHint':
        'Active radar uses Bluetooth and scans continuously. This uses '
        'noticeably more battery. Stop the radar when you no longer need it.',
    'transit.self.noteHint':
        'Your own note (optional, e.g. "Red cap, green backpack") …',
    'transit.sendFailed':
        'The signal could not be sent right now. Check your connection and try again in a moment.',
    'transit.stored':
        'Your signal is saved. If the other person feels the same moment and signals too, your spark is created.',
    // Leaving the radar screen (radar active): stop? + remember checkbox
    'transit.exitTitle': 'Keep the radar running?',
    'transit.exitBody':
        'The radar is still active. You can stop it when leaving this page '
        'or let it keep running in the background (the window keeps '
        'running, a spark is possible hours later).',
    'transit.exitKeep': 'Keep running',
    'transit.exitStop': 'Stop radar',
    'transit.exitRemember': 'Apply automatically in the future',
    // 2-hour retention of seen people
    'transit.retainedBtn': 'View seen devices (2 hours)',
    'transit.retainedTitle': 'Seen devices',
    'transit.retainedHint': 'The list stays for 2 more hours.',
    'transit.retainedUntil': 'The list stays until {time}.',
    'transit.howTitle': 'How does it work?',
    'transit.howBody':
        'Activate the radar while you are on the go (train, café, '
        'convention). Your device exchanges anonymous, random tokens with '
        'other Wisp devices nearby - no names, no location, no photos. '
        'Later, tap "Exchanged glances": if the other person feels the '
        'same moment and signals too, a spark is created.',
    'transit.privacyNote':
        'Tokens are random, rotate regularly and expire after 45 minutes. '
        'Only what you actively send is stored - nothing leaves your '
        'device unless you choose to signal. A greeting to a person '
        'needs their current token - therefore while the radar is '
        'active your random token (only this one) is stored server-'
        'side for 45 minutes.',
    'transit.teenNote':
        'Under 18? You only see age-compatible users - enforced '
        'server-side.',
    'onboarding.appbarTitle': 'Nice to meet you',
    'onboarding.skipAll': 'Skip',
    'onboarding.fillLater': 'Fill in later',
    'onboarding.next': 'Continue',
    'onboarding.hello.title': 'Hi, I am Wisp!',
    'onboarding.hello.body':
        'Over the next few minutes we will set up your profile - as a '
        'short conversation instead of a form. Everything is skippable, '
        'nothing is wrong.',
    'onboarding.blind.title': 'Personality before looks',
    'onboarding.blind.body':
        'By default you will see only name, age, bio and interests '
        'first - no photos. Decide with your head, not just your eyes. '
        'Switchable at any time.',
    'onboarding.connections.title': 'Real connections',
    'onboarding.connections.body':
        'A spark is created only if you both choose each other. Photos '
        'unlock then and you can start chatting - fair instead of '
        'superficial.',
    'onboarding.q.photo':
        'Would you like to show a profile picture? No pressure - '
        'photos are only visible after a spark anyway.',
    'onboarding.photoLater': 'You can upload a profile picture later.',
    'onboarding.q.music': 'Is there a song accompanying you right now?',
    'onboarding.q.musicGenres': 'Which music genres do you like?',
    'onboarding.q.musicHint': 'e.g. favorite song …',
    'onboarding.q.bandHint': 'e.g. favorite band or artist …',
    'onboarding.q.birthday':
        'Which style should your profile have on your birthday?',
    'onboarding.done.title': 'Done - glad you are here!',
    'onboarding.done.body':
        'Your profile is set up. You can change everything later in '
        'the settings. Enjoy discovering!',
    'welcome.t1': 'Welcome to Blind Date',
    'welcome.b1':
        'Here you really get to know people before you see their photo. '
        'Because at first, personality counts, not looks.',
    'welcome.t2': 'Blind Chat and Match',
    'welcome.b2':
        'First chat blind and get to know the person behind the profile. '
        'Photos are only unlocked once you both liked each other.',
    'welcome.t3': 'Your privacy',
    'welcome.b3':
        'All messages and calls are end-to-end encrypted (E2E). Nobody '
        'except you and your counterpart can read along, not even us. '
        'Your data belongs to you.\n\nUploaded photos are automatically '
        'checked for inappropriate content. This check is GDPR compliant '
        'and does not permanently store your images with third parties.',
    'welcome.start': 'Let us go',
    'pt.title': 'Personality test',
    'pt.doneTitle': 'Test completed!',
    'pt.youAre': 'You are a {t}!',
    'pt.heading': 'Get to know your personality',
    'pt.sub':
        'Answer a few questions, there is no wrong or right. This helps '
        'show you matching people.',
    'pt.finish': 'Complete test',
    'pt.saveFailed':
        'Note: The setup state could not be saved on the server. Setup '
        'may appear again at next login.',
    'pt.profileLine': 'Personality test: {label}',
    'pt.q1': 'How do you recharge?',
    'pt.q1a': 'Around people and activities',
    'pt.q1b': 'With quiet time for myself',
    'pt.q2': 'What describes you better?',
    'pt.q2a': 'Spontaneous and flexible',
    'pt.q2b': 'Planned and organized',
    'pt.q3': 'When deciding, you rather trust …',
    'pt.q3a': 'gut feeling',
    'pt.q3b': 'facts',
    'pt.q4': 'How do you approach new people?',
    'pt.q4a': 'Open and active',
    'pt.q4b': 'Rather reserved',
    'pt.q5': 'You like to approach things …',
    'pt.q5a': 'practically and concretely',
    'pt.q5b': 'seeing the big picture',
    'pt.q6': 'In your free time you prefer …',
    'pt.q6a': 'Variety and surprises',
    'pt.q6b': 'Routine and familiarity',
    'pt.q7': 'You prefer to handle conflict …',
    'pt.q7a': 'directly and factually',
    'pt.q7b': 'gently and harmoniously',
    'pt.q8': 'You like to work …',
    'pt.q8a': 'in a team with others',
    'pt.q8b': 'independently alone',
    'pt.q9': 'When getting to know someone, what counts first …',
    'pt.q9a': 'what we experience together',
    'pt.q9b': 'what we talk about',
    'pt.q10': 'Weekend plans …',
    'pt.q10a': 'are usually already set',
    'pt.q10b': 'often emerge spontaneously',
    'pt.label.ENFJ': 'The Mentor',
    'pt.label.ENFP': 'The Enthusiast',
    'pt.label.ENTJ': 'The Leader',
    'pt.label.ENTP': 'The Inventor',
    'pt.label.ESFJ': 'The Provider',
    'pt.label.ESFP': 'The Entertainer',
    'pt.label.ESTJ': 'The Organizer',
    'pt.label.ESTP': 'The Doer',
    'pt.label.INFJ': 'The Dreamer',
    'pt.label.INFP': 'The Idealist',
    'pt.label.INTJ': 'The Strategist',
    'pt.label.INTP': 'The Thinker',
    'pt.label.ISFJ': 'The Protector',
    'pt.label.ISFP': 'The Artist',
    'pt.label.ISTJ': 'The Logician',
    'pt.label.ISTP': 'The Maker',
    'pt.label.fallback': 'The Explorer',
    'pt.desc.ENFJ':
        'You are a natural mentor, empathic, organized and inspiring. '
        'You bring people together and help them unfold their potential.',
    'pt.desc.ENFP':
        'You bubble over with enthusiasm and ideas. Your curiosity and '
        'openness make you a magnetic person who sweeps others along.',
    'pt.desc.ENTJ':
        'You lead with vision and determination. Strategic thinking and '
        'natural authority make you a born leader.',
    'pt.desc.ENTP':
        'You love intellectual challenges and new perspectives. Your '
        'inventive spirit and quick wit make conversations with you '
        'exciting.',
    'pt.desc.ESFJ':
        'You genuinely care about others and create harmonious '
        'environments. Your reliability and organizational talent are '
        'appreciated.',
    'pt.desc.ESFP':
        'You live in the moment and enjoy life to the fullest. Your '
        'spontaneity and warmth make you the center of every gathering.',
    'pt.desc.ESTJ':
        'You bring structure into chaos. With a clear mind and practical '
        'sense you organize efficiently and reliably.',
    'pt.desc.ESTP':
        'You act fast and decisively. You take on challenges directly, '
        'pragmatic, energetic and solution-oriented.',
    'pt.desc.INFJ':
        'You possess a rare depth and intuition. Your idealism and '
        'empathy make you a trusted advisor.',
    'pt.desc.INFP':
        'You follow your values with quiet determination. Your '
        'creativity and authenticity inspire others to be real.',
    'pt.desc.INTJ':
        'You think strategically and long-term. Your analytical edge and '
        'drive for improvement make you a visionary planner.',
    'pt.desc.INTP':
        'You penetrate complex systems with a curious mind. Your logical '
        'depth and independence lead to original solutions.',
    'pt.desc.ISFJ':
        'You are the quiet rock in the surf. Caring, detail-loving and '
        'loyal, you can always be relied upon.',
    'pt.desc.ISFP':
        'You express yourself through actions and aesthetics. Your '
        'sensitivity for beauty and your authenticity make you unique.',
    'pt.desc.ISTJ':
        'You are the foundation others build upon. Conscientious, '
        'logical and steady, you keep what you promise.',
    'pt.desc.ISTP':
        'You master practical problems with calm and skill. Your '
        'analytical observation and craftsmanship convince.',
    'pt.desc.fallback':
        'You discover the world with open curiosity and find your own '
        'way, no matter your type.',
    'chathist.tileTitle': 'Save chat history locally',
    'chathist.mode.off': 'Off',
    'chathist.mode.cap200': 'On (200 messages)',
    'chathist.mode.all': 'On (full history)',
    'chathist.tileSubPrefix': 'Encrypted (AES-256) on this device.',
    'chathist.deleteHint': 'Disabling deletes the history.',
    'chathist.dialogTitle': 'Save chat history',
    'chathist.modeWord': 'Mode:',
    'chat.safetyNumber': 'Safety number',
    'chat.safetyNumberTooltip': 'Safety number (E2E verification)',
    'chat.safetyChangedTitle': 'Safety number has changed',
    'chat.safetyChangedBody':
        'The encryption key of your contact has changed. This can happen '
        'after a reinstall - or it may indicate that someone is trying to '
        'intercept the conversation.\n\nVerify the safety number through '
        'a second channel (e.g. a call or in person) before continuing.',
    'chat.safetyChangedCancel': 'Cancel',
    'chat.safetyChangedAccept': 'Verified: accept',
    'chat.reconnectStillFailing': 'Connection still failing.',
    'chat.imageSourcePrompt': 'Choose a source for the image to send.',
    'chat.identityVerifiedTitle': 'Identity verified',
    'chat.close': 'Close',
    'chat.coolSpark': 'Cool spark',
    'chat.coolSparkError': 'Could not cool the spark: {error}',
    'chat.coolSparkDone':
        'Spark cooled - you will find it under "Settled sparks" again.',
    'chat.backToSparks': 'Back to sparks',
    'chat.closeImageHint':
        'Close (the image can no longer be viewed afterwards)',
    'settings.backupChoosePw': 'Choose backup password',
    'settings.restoreConfirmTitle': 'Restore identity?',
    'settings.backupPasteCode': 'Paste backup code',
    'settings.restored': 'E2E identity restored.',
    'settings.codeInvalid': 'Invalid or expired code.',
    'settings.passkeyDeleteTitle': 'Delete passkey?',
    'settings.delete': 'Delete',
    'settings.passkeyDeleted': 'Passkey deleted.',
    'settings.deleteFailed': 'Deletion failed.',
    'dh.prefs.setBtn': 'Set preferences',
    'dh.nextEventIn': 'Next event in',
    'dh.searching': 'Searching...',
    'dh.feature.noPhotos':
        'No photos, no bios, just 5 minutes of real conversation.',
    'dh.feature.e2eTitle': 'End-to-end encrypted',
    'dh.feature.e2eSub':
        'Nobody but the two of you can read your messages (Signal protocol).',
    'dh.prefs.savedHint':
        'Preferences saved. You join via "I am in" on the event day.',
    'report.detailsOptional': 'Additional details (optional)',
    'report.checkingTitle': 'Checking image…',
    'report.checkingSub': 'The AI is checking the reported image.',
    'report.retryLater': 'Please try again later.',
    'report.type.harassment': 'Harassment / insults',
    'report.type.default': 'Report',
    'report.type.inappropriateContent':
        'Inappropriate content (images/messages)',
    'report.type.spam': 'Spam / advertising',
    'report.type.fakeProfile': 'Fake profile / identity abuse',
    'report.type.other': 'Other',
    'report.type.wrongAge': 'Wrong age / age does not match',
    'verify.submitFailed':
        'Submission failed. Please check your internet connection and '
        'try again.',
    'verify.doneTitle': 'Verification',
    'verify.autoTitle': 'Verified!',
    'verify.autoBody':
        'The age check was inconspicuous. You immediately receive the '
        'verified badge. Your video is kept for spot checks.',
    'verify.pendingTitle': 'Video submitted!',
    'verify.pendingBody':
        'Your video was transmitted securely. Support reviews it '
        'personally, including your stated age. Once approved, the '
        'verified badge appears in your profile. Your account remains '
        'fully usable until then.',
    'verify.toApp': 'To the app',
    'verify.badge': 'Verified',
    'verify.pendingChip': 'Review in progress',
    'verify.pendingReason.deviation':
        'Why manual? The AI estimate deviates {years} years from your '
        'stated age - support will reconcile this with your video.',
    'verify.pendingReason.faces':
        'Why manual? Exactly one face could not be detected - '
        'support will review your video personally.',
    'verify.pendingReason.noAi':
        'Why manual? The age AI could not run on this device - '
        'support will review your video personally.',
    'verify.pendingReason.noStated':
        'Why manual? Your stated age could not be verified - '
        'support will review your video personally.',
    'verify.cleanupTitle': 'Revoke permissions again?',
    'verify.cleanupBody':
        'Verification is complete. You no longer need location, camera '
        'and microphone for it - would you like to turn them off again?',
    'verify.cleanupLater': 'Later',
    'verify.cleanupLocation': 'Location',
    'verify.cleanupOpen': 'Camera & microphone',
    'verify.pendingHint':
        'Your video is being reviewed by support. This usually takes '
        'only a few hours.',
    'verify.cta': 'Verify now',
    'verify.ctaSub':
        'Short selfie video. A local AI checks your age on-device, '
        'conspicuous cases are seen personally by support.',
    'report.confirmed': 'Report confirmed',
    'report.forwardBtn': 'Forward for manual review',
    'report.forwardFailed': 'Forwarding failed. Please try again later.',
    'interests.likeWithdrawn': 'Like withdrawn.',
    'interests.likeWithdrawTooltip': 'Withdraw like',
    'interests.sparkConfirmBtn': 'Confirm spark',
    'interests.resparkDone': 'Spark with {name} is glowing again ✨',
    'interests.matchesSub': 'Confirmed mutual likes',
    'qr.openingChat': 'Opening chat with {name}...',
    // Saved profiles (local, max. 5, for writing later)
    'qr.limitTitle': 'Maximum reached',
    'qr.limitBody':
        '5 profiles are already saved locally. Remove one from the list '
        'first, then scan again.',
    'qr.limitEmpty': 'No saved profiles left - scan again now.',
    'qr.savedDeleteTooltip': 'Remove saved profile',
    'qr.enterFullCode': 'Please enter the full 8-digit code.',
    'qr.resolveFailed': 'Could not resolve the code.',
    'qr.shareSub': 'So others can find you',
    'qr.scanSub': 'Open the camera and scan a code',
    'qr.myCode': 'My QR code',
    'qr.yourCode': 'Your code',
    'qr.copyTooltip': 'Copy code',
    'qr.copied': 'Code copied to clipboard',
    'qr.shareHint':
        'Share this code or the QR code with others. They can find you in the app and message you directly.',
    'meet.metTitle': 'Great that you met! 🎉',
    'meet.youWant': 'You want to meet',
    'meet.theyWant': '{name} would like to meet you',
    'meet.later': 'Maybe later',
    'meet.ideas': 'Ideas for a first meeting:',
    'home.settingsTooltip': 'Settings & privacy',
    'home.discoverSub': 'Get to know people through their intro.',
    'home.likesSub': 'Likes become sparks when you both like each other.',
    'random.partnerLeft': 'Your random chat partner has left.',
    'random.backToDiscover': 'Back to Discover',
    'random.connecting': 'Partner found! Connecting encrypted…',
    'profile.detail.unavailable': 'This profile is currently unavailable.',
    'safety.linkFailed': 'Could not open link.',
    'safety.protectOwnImages': 'Protect your own images',
    'safety.protectOwnImagesBody':
        'Images in incoming messages are blurred by default (settings - '
        'chat safety). Your own photos remain hidden until mutual quiz '
        'success.',
    'safety.ageTitle': 'Age and deception',
    'safety.ageBody':
        'Some people state a false age. This particularly endangers young '
        'users and leads to a permanent ban when proven. Protect yourself: '
        'never blindly trust an age claim. The chat warns you about large '
        'age differences. Only meet in public places, bring your phone to '
        'a first meeting and tell a trusted person. Report suspected false '
        'age immediately via the "Wrong age" report reason. Wisp cannot '
        'verify every detail and gives no guarantee for their accuracy.',
    'home.noMessages': 'No new messages',
    'home.noMessagesSub': 'New messages appear here once you have sparks.',
    'safety.sectionHelp': 'Immediate help',
    'safety.hotline1': 'Help hotline "Violence against women"',
    'safety.hotline1Sub': '116 016 - free, 24/7, anonymous',
    'safety.hotline2': 'Telephone counselling',
    'safety.hotline2Sub': '0800 111 0 111 - free, 24/7',
    'safety.hotline3': 'klicksafe (cyberbullying & counselling)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Stalking helpline (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.sectionProtect': 'Protection in WispDating',
    'safety.reportSomeone': 'Report someone',
    'safety.reportSomeoneBody':
        'In the chat via the flag icon at the top right, or by long-pressing '
        'an image. Your last messages are transparently submitted as context '
        'and personally reviewed by support.',
    'safety.blockSomeone': 'Block someone',
    'safety.blockSomeoneBody':
        'Chat menu (three dots) - Block. Likes and sparks are removed; '
        'future interactions are prevented server-side. The person is not '
        'notified.',
    'safety.stalkingGuide': 'Stalking guide',
    'safety.stalkingBody':
        'If someone is stalking you online (or offline): 1. Do not reply, '
        'deliberately end contact. 2. Document everything: screenshots with '
        'dates, chat history, profile names. 3. Block in the app and inform '
        'us via the report function. We can permanently suspend accounts. '
        '4. Change passwords and enable 2FA (settings). 5. If threatened or '
        'afraid: contact the police (110) or 116 006.',
    'safety.exportData': 'Export my data',
    'safety.exportDataSub': 'JSON export of all stored data',
    'spice.answerSent': 'Answer sent. Your partner will answer soon.',
    'spice.answerEdit': 'Edit answer',
    'spice.answer': 'Answer',
    'spice.title': 'Icebreaker questions',
    'spice.searchHint': 'Search categories …',
    'spice.copied': 'Copied - paste the question into the chat.',
    'spice.copyTooltip': 'Copy question',
    'spice.countHint':
        '{n} questions in 10 categories - tap to send, icon to copy.',
    'spice.perCategory': '{n} questions',
    'spice.emptySearch': 'Nothing found. Try a different word.',
    'spice.sendTitle': 'Send question to the chat?',
    'spice.sendBtn': 'Send to chat',
    'interests.cooledDone': 'Spark with {name} cooled down.',
    'interests.hiddenOne': '{name} removed from the list.',
    'interests.coolBtn': 'Cool down spark',
    'interests.hideOneBtn': 'Remove from list',
    'bugreport.sendFailed': 'Submission failed. Please try again later.',
    'bugreport.maxImages': 'Maximum {n} images allowed.',
    'bugreport.badFormat':
        'Please choose an image file in jpg, jpeg or png format.',
    'bugreport.prepareFailed':
        'Screenshot could not be prepared '
        '(metadata removal failed) and was not attached.',
    'bugreport.sent': 'Thanks, your bug report has been submitted',
    'bugreport.notSent':
        'Submission could not be completed. '
        'Please try again later.',
    'bugreport.defaultSummary': 'Bug Report',
    'bug.title': 'Report bug',
    'bug.github': 'Report bug on GitHub',
    'bug.githubBody':
        'This report is publicly visible on GitHub. Please file your '
        'issue there.',
    'bug.privateBody':
        'Alternatively you can report the bug directly and privately by '
        'email. The report is sent via Brevo to a Proton Mail address. '
        'It is not publicly visible.',
    'bug.descLabel': 'Description *',
    'bug.descMissing': 'Please enter a short description.',
    'bug.descShort': 'Description too short.',
    'bug.descLong': 'At most {n} characters allowed.',
    'bug.preview': 'Preview',
    'bug.gallery': 'Gallery',
    'bug.camera': 'Camera',
    'bug.send': 'Send',
    'bug.limits':
        'At most {images} images in jpg, jpeg or png format and {text} '
        'characters of text are allowed. No further personal data is sent.',
    'random.sendFailed': 'Message could not be sent.',
    'random.leaveTitle': 'End random chat?',
    'random.leaveBody':
        'The chat will be ended and the connection closed. You can start '
        'a new random chat anytime.',
    'random.leaveConfirm': 'End',
    'random.endedTitle': 'Chat ended',
    'random.likeTooltip': 'Like',
    'random.likeSentWaiting':
        'Like sent! The spark appears as soon as you both like each '
        'other.',
    'random.endTooltip': 'End chat',
    'random.hint': 'Message …',
    'random.searching': 'Searching for a person…',
    'random.searchingSub':
        'Once someone else starts random chat, you will be connected.',
    'random.hello': 'Say hello to {name}! 🙂',
    'random.helloDefault': 'your partner',
    'random.errorNoPartner':
        'Random chat could not be started. Possibly no other users are '
        'online right now. Please try again later.',
    'random.errorUnavailable': 'Random chat not available.',
    'random.errorEnded': 'The random chat has ended.',
    'random.errorOffline': 'Random chat is not available without connection.',
    'random.errorConnectTimeout':
        'The direct connection to your partner could not be established. '
        'Note: Random chat is currently not supported on mobile data '
        'because there is no relay server (TURN). Please use WiFi '
        'instead.',
    'random.relayStatus': 'E2E via server (encrypted, no direct channel)',
    'random.waitingForPartner':
        'Waiting for the partner device (keys are being prepared there). '
        'The connection establishes automatically - feel free to write '
        'already.',
    'random.relayNoDirect':
        'Direct connection blocked by the network (typically AP isolation '
        'on the router or mobile data). Messages arrive securely via the '
        'server (E2E encrypted).',
    'random.infoBlind':
        'Random chat: you are blindly connected with a random person.',
    'random.infoE2e':
        'Conversations are end-to-end encrypted and run peer to peer.',
    'meet.metBody':
        'We hope you had a great time. Real connections instead of just '
        'chatting online.',
    'meet.waitBody':
        'We passed your wish on to {name}. Once {name} agrees, you can '
        'plan.',
    'meet.tryBody': 'How about really giving it a try?',
    'meet.yesGlad': 'Yes, gladly',
    'meet.noThanks': 'Rather not',
    'meet.suggestTitle': 'Up for a real meeting?',
    'meet.suggestBody':
        'You have been writing for a while. How about a coffee or a '
        'walk? Meet in a public place.',
    'meet.yesWant': 'Yes, I want to',
    'meet.planningTitle': 'You want to meet! 🎉',
    'meet.idea.1': 'Have coffee',
    'meet.idea.2': 'Go for a walk',
    'meet.idea.3': 'Go to the cinema',
    'meet.idea.4': 'Visit a museum',
    'meet.idea.5': 'Go out for dinner',
    'meet.noteHint': 'Note (e.g. "Saturday, 3pm, café X")',
    'meet.metBtn': 'We have met',
    'meet.safetyTip':
        'Tip: Always meet in a public place and tell a trusted person.',
    'music.likedTitle': 'Genres I like',
    'music.dislikedTitle': 'Genres I dislike (optional)',
    'music.exclude': 'Exclude genre…',
    'music.genre.klassik': 'Classical',
    'home.noLikes': 'No new likes',
    'home.noSparks': 'No new sparks',
    'home.viewCount': 'View {count}',
    'home.viewAll': 'View all',
    'common.hint': 'Note',
    'interests.sparksTitle': 'Sparks',
    'dh.feature.realChat': 'Real chat instead of profile check',
    'dh.info.title': 'How does Dating Hour work?',
    'dh.info.timeTitle': '5 minutes',
    'dh.info.timeSub': 'Then both decide: "Accept" or "Decline".',
    'dh.info.liveTitle': 'Live with real people',
    'dh.info.liveSub':
        'You are connected live with another person who is also actively looking for a Dating Hour partner right now.',
    'dh.info.retryTitle': 'No spark? New chance!',
    'dh.info.retrySub':
        'On "Decline" the algorithm immediately looks for someone new.',
    'chathist.off.title': 'Nothing (RAM only)',
    'chathist.cap200.title': '200 messages per chat',
    'chathist.all.title': 'Full history',
    'chathist.off.sub': 'Chats are gone after restart.',
    'chathist.cap200.sub': 'Encrypted, max. 200 per chat.',
    'chathist.all.sub': 'Encrypted, no limit.',
    'profile.menu.edit': 'Edit profile',
    'profile.menu.editSub': 'Change details, interests and intro',
    'profile.menu.preview': 'Profile preview',
    'profile.menu.previewSub': 'How others see you',
    'profile.menu.introPreview': 'Intro preview',
    'profile.menu.introPreviewSub': 'View your text and audio intro',
    'profile.preview.title': 'Profile preview',
    'profile.preview.hint':
        'This is how other users see you (incl. age protection & blind mode):',
    'profile.preview.photoHidden':
        'Your photos are not visible to others due to your settings (personality first / age protection).',
    'profile.preview.aboutMe': 'About me',
    'profile.preview.noBio': 'No bio yet.',
    'profile.preview.interests': 'Interests',
    'profile.preview.note':
        'Note: Actual visibility depends on the age and settings of each viewer.',
    'profile.preview.type': 'Type',
    'profile.intro.title': 'My intro',
    'profile.intro.empty': 'You have not added a text intro yet.',
    'profile.intro.hint':
        'Others get to know you through this intro before they see a photo. You can edit it under Edit profile.',
    'profile.intro.audioEmpty': 'No audio intro recorded yet.',
    'profile.intro.audioMissing': 'Audio intro not found.',
    'profile.intro.audioLoadError': 'Audio intro could not be loaded.',
    'profile.intro.stop': 'Stop',
    'profile.intro.listen': 'Listen to audio intro',
    // Intro editor (audio recorder UX)
    'intro.title': 'My intro',
    'intro.hintRequired':
        'This is how you get to know others before a photo is shown. '
        'Text AND audio are required.',
    'intro.hintOptional':
        'This is how you get to know others before a photo is shown. '
        'You can skip this step and add everything later.',
    'intro.textRequired': 'Intro (text) *',
    'intro.text': 'Intro (text)',
    'intro.textHint': 'e.g. who you are and what you are looking for',
    'intro.promptTitle': 'Need ideas? Tap a question:',
    'intro.prompt.weekend': 'What do you enjoy most on weekends?',
    'intro.prompt.friends': 'What do your friends appreciate about you?',
    'intro.prompt.laugh': 'What makes you really laugh?',
    'intro.prompt.dream': 'What are you dreaming of right now?',
    'intro.audioTitleRequired': 'Audio intro *',
    'intro.audioTitle': 'Audio intro',
    'intro.savedState': 'Recorded. You can re-record or remove it.',
    'intro.rangeHint':
        '{min} to {max} seconds. You can listen to every recording '
        'before saving.',
    'intro.record': 'Record',
    'intro.rerecord': 'Re-record',
    'intro.recordingState': 'Recording …',
    'intro.pausedState': 'Paused',
    'intro.pause': 'Pause',
    'intro.resume': 'Resume',
    'intro.stopListen': 'Done',
    'intro.discard': 'Discard',
    'intro.discardTitle': 'Discard recording?',
    'intro.discardBody': 'The current recording will be deleted.',
    'intro.discardKeep': 'Keep it',
    'intro.delete': 'Remove',
    'intro.deleteTitle': 'Remove audio intro?',
    'intro.deleteBody': 'The saved recording will be permanently deleted.',
    'intro.deleteTooltip': 'Remove audio intro',
    'intro.micDenied': 'Microphone access denied.',
    'intro.saved': 'Audio intro uploaded.',
    'intro.removed': 'Audio intro removed.',
    'intro.recordFailed': 'Recording failed: {error}',
    'intro.unavailable': 'Introduction unavailable',
    'intro.unplayable': 'Introduction cannot be played',
    'intro.stop': 'Stop',
    'intro.listen': 'Listen to introduction',
    // Audio review sheet (listen before sending)
    'intro.review.title': 'Check your recording',
    'intro.review.length': 'Length: {length}',
    'intro.review.lengthMin': 'Length: {length} (minimum {min} s)',
    'intro.review.listen': 'Listen',
    'intro.review.pause': 'Pause',
    'intro.review.send': 'Send',
    'intro.review.confirm': 'Use & upload',
    'intro.review.discard': 'Discard',
    'intro.review.rerecord': 'Re-record',
    'intro.review.loadError':
        'Preview not playable. You can still use or discard the '
        'recording.',
    'intro.review.tooShort':
        'The recording is too short (minimum {min} seconds). '
        'Please record it again.',
    'mood.noneSelected': 'No mood selected',
    'mood.today': 'Today',
    'mood.changeHint': 'Tap to change your mood.',
    'mood.selectHint': 'Tap to choose your mood of the day.',
    'mood.change': 'Change',
    'mood.select': 'Choose',
    'settings.logout': 'Log out',
    'settings.deleteAccount': 'Delete account',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privacy',
    'settings.whoCanSee': 'Who can see my profile?',
    'settings.localDataNote':
        'Your data is stored only locally on this device. No unnecessary '
        'permissions are requested.',
    'settings.communitySafety': 'Community & safety',
    'settings.communityRules': 'Community rules',
    'settings.communityRulesSub': 'Respectful conduct & rules of behavior',
    'settings.passkeyCreate': 'Create passkey',
    'settings.passkeyCreateSub':
        'Biometric login (FaceID/TouchID) without a password',
    'settings.passkeyCreated': 'Passkey created.',
    'settings.passkeyFailed': 'Passkey creation failed.',
    // Passkey confirmation / error texts (services without BuildContext)
    'passkey.err.cancelledRegister': 'Passkey setup cancelled.',
    'passkey.err.cancelledLogin': 'Passkey sign-in cancelled.',
    'passkey.err.notAllowedRegister':
        'The passkey setup was cancelled or expired. Make sure your '
        'device has a screen lock (PIN, pattern or biometrics) and try '
        'again.',
    'passkey.err.notAllowedLogin':
        'The passkey sign-in was cancelled or expired. Make sure your '
        'device has a screen lock (PIN, pattern or biometrics) and try '
        'again.',
    'passkey.err.invalidState':
        'A passkey for this account already exists on this device.',
    'passkey.err.securityError':
        'The app could not prove its domain association '
        '(passkey domain link). Check whether the latest app version is '
        'installed, and report it to support if it persists.',
    'passkey.err.syncAccount':
        'The passkey could not be stored encrypted. Make sure you are '
        'signed in with a Google account on the device and that Google '
        'Play Services are up to date.',
    'passkey.err.timeoutRegister':
        'Passkey setup timed out. Please try again while the dialog is '
        'visible on screen.',
    'passkey.err.timeoutLogin':
        'Passkey sign-in timed out. Please try again while the dialog is '
        'visible on screen.',
    'passkey.err.noCredentialLogin':
        'No passkey found for this account. Set one up under Settings '
        'first.',
    'passkey.err.noCredentialRegister':
        'No passkey storage available. Check screen lock and Google Play '
        'Services.',
    'passkey.err.captcha':
        'The security check was missing or expired. Please try again.',
    'passkey.err.verificationFailed':
        'The server could not confirm the passkey. Most likely the '
        'origin (apk-key-hash) of the installed app is missing in the '
        'server passkey configuration - see '
        'docs/PASSKEYS_SERVER_SETUP.md. Alternatively delete the old '
        'passkey under "Manage passkeys" and create it again.',
    'passkey.err.serverRejected':
        'The server rejected the passkey request. Please check in the '
        'Supabase settings whether "Passkeys" is enabled and the RP ID '
        'is set to auth.wispdating.de.{reason}',
    'passkey.err.unknownRegister':
        'Passkey setup failed. Please try again later.',
    'passkey.err.unknownLogin':
        'Passkey sign-in failed. Please try again later.',
    // Passkey dialog in settings (server confirmation)
    'settings.passkeyExistsTitle': 'Passkey already exists',
    'settings.passkeyExistsBody':
        'Your account already has {count} passkey(s) registered. If '
        'creating another one keeps failing at server confirmation, '
        'delete the old entries under "Manage passkeys" and try '
        'again.\n\nCreate another passkey anyway?',
    'settings.passkeyExistsAbort': 'Cancel',
    'settings.passkeyExistsContinue': 'Create anyway',
    'settings.passkeyWaitConfirm': 'Waiting for confirmation …',
    // "Manage passkeys" card
    'passkey.name': 'Passkey',
    'passkey.stepUpHint': 'Showing your passkeys requires a 2FA confirmation.',
    'passkey.loadError':
        'Passkeys could not be loaded. Please try again later.',
    'passkey.renameTitle': 'Rename passkey',
    'passkey.renameLabel': 'Display name',
    'passkey.renameHint': 'e.g. Pixel 8',
    'passkey.renameFailed': 'Renaming failed.',
    'passkey.deleteBody':
        '"{name}" will be removed from your account. You will no longer '
        'be able to sign in with it. The passkey may remain stored on '
        'the device.',
    'passkey.managerSub': 'Passkeys registered on your account',
    'passkey.managerHint':
        '{count} registered - tap to rename, trash icon to remove',
    // Passkey fallbacks on the login screen (not an AppException)
    'auth.passkeyCancelled': 'Passkey sign-in cancelled.',
    'auth.passkeyFailed':
        'Passkey sign-in failed. Please try with email and password.',
    'settings.devices': 'Signed-in devices',
    'settings.devicesSub': 'Where am I logged in? Sign out everywhere',
    'devices.title': 'Signed-in devices',
    'devices.logoutTitle': 'Sign out everywhere?',
    'devices.logoutBody':
        'You will be signed out on all other devices. The session on this '
        'device stays active. The other devices will need to sign in '
        'again afterwards.',
    'devices.logoutBtn': 'Sign out everywhere',
    'devices.logoutDone': 'All other devices have been signed out.',
    'devices.logoutFailed':
        'Signing out failed. Please check your connection and try again.',
    'devices.retry': 'Try again',
    'devices.hint':
        'Here you can see which devices are currently signed in. Use '
        '"Sign out everywhere" to end all other sessions. This device '
        'stays signed in.',
    'devices.current': 'This device',
    'devices.activeNow': 'active right now',
    'devices.activeMinutesA': 'active',
    'devices.activeMinutesB': 'min ago',
    'devices.activeHoursA': 'active',
    'devices.activeHoursB': 'h ago',
    'devices.activeLastSeen': 'last active on',
    'devices.empty':
        'No other devices registered. Open Wisp on another device (at '
        'least this version) so it shows up in the list.',
    'devices.signingOut': 'Signing out…',
    'devices.logoutBtnLong': 'Sign out everywhere (except this device)',
    'devices.logoutNote':
        'The other devices will be signed out immediately and must log in '
        'again the next time they open the app.',
    'profile.title': 'My profile',
    'profile.qrTooltip': 'My QR code',
    'profile.unknown': 'Unknown',
    'profile.years': 'years',
    'profile.ageUnknown': 'Age unknown',
    'profile.typePrefix': 'Type',
    'profile.aboutMe': 'About me',
    'profile.noBio': 'No bio yet.',
    'profile.interests': 'Interests',
    'profile.blindModeTitle': 'Personality over looks',
    'profile.blindModeSub': 'Show photos only after a spark',
    'profile.profileBtn': 'Profile',
    'profile.bugReportBtn': 'Report a bug',
    'profile.edit.title': 'Edit profile',
    'profile.edit.name': 'Name',
    'profile.edit.birthDate': 'Date of birth',
    'profile.edit.birthDateHint': 'DD. MM. YYYY',
    'profile.edit.birthDatePick': 'Please select',
    'profile.edit.birthDateHelp': 'Choose your date of birth',
    'profile.edit.gender': 'Gender',
    'profile.edit.lookingFor': 'I am looking for',
    'profile.edit.relationship': 'What are you looking for?',
    'profile.edit.location': 'Location',
    'profile.edit.city': 'City',
    'profile.edit.cityHint': 'e.g. Berlin',
    'profile.edit.gpsTooltip': 'Detect location (GPS)',
    'profile.edit.country': 'Country',
    'profile.edit.state': 'Federal state',
    'profile.edit.stateHint': 'Please select',
    'profile.edit.stateNotApplicable':
        'Federal state only applies within Germany.',
    'profile.edit.noGeoLimit':
        'No geographic restriction, searching all of Germany.',
    'country.deutschland': 'Germany',
    'country.oesterreich': 'Austria',
    'country.schweiz': 'Switzerland',
    'country.luxemburg': 'Luxembourg',
    'country.belgien': 'Belgium',
    'country.niederlande': 'Netherlands',
    'country.frankreich': 'France',
    'country.italien': 'Italy',
    'country.spanien': 'Spain',
    'country.portugal': 'Portugal',
    'country.polen': 'Poland',
    'country.tschechien': 'Czechia',
    'country.daenemark': 'Denmark',
    'country.schweden': 'Sweden',
    'country.norwegen': 'Norway',
    'country.finnland': 'Finland',
    'country.uk': 'United Kingdom',
    'country.irland': 'Ireland',
    'country.usa': 'USA',
    'country.kanada': 'Canada',
    'country.australien': 'Australia',
    'country.other': 'Other country',
    'state.badenWuerttemberg': 'Baden-Württemberg',
    'state.bayern': 'Bavaria',
    'state.berlin': 'Berlin',
    'state.brandenburg': 'Brandenburg',
    'state.bremen': 'Bremen',
    'state.hamburg': 'Hamburg',
    'state.hessen': 'Hesse',
    'state.mecklenburgVorpommern': 'Mecklenburg-Vorpommern',
    'state.niedersachsen': 'Lower Saxony',
    'state.nrw': 'North Rhine-Westphalia',
    'state.rheinlandPfalz': 'Rhineland-Palatinate',
    'state.saarland': 'Saarland',
    'state.sachsen': 'Saxony',
    'state.sachsenAnhalt': 'Saxony-Anhalt',
    'state.schleswigHolstein': 'Schleswig-Holstein',
    'state.thueringen': 'Thuringia',
    'profile.edit.rel.casual': 'Casual acquaintance',
    'profile.edit.rel.dating': 'Serious dating',
    'profile.edit.rel.relationship': 'Committed relationship',
    'profile.edit.rel.friends': 'Friendship',
    'profile.edit.rel.open': 'Open to anything',
    'profile.edit.minAgeLabel': 'Minimum age',
    'profile.edit.maxAgeLabel': 'Maximum age',
    'common.years': 'years',
    'common.unknownError': 'Unknown error',
    'common.errorWith': 'Error: {error}',
    'common.copy': 'Copy',
    // Settings: backup + passkeys
    'settings.backupPw': 'Password (min. 8 characters)',
    'settings.backupPwShort': 'Too short (min. 8)',
    'settings.backupPwRepeat': 'Repeat password',
    'settings.backupPwMismatch': 'Passwords do not match',
    'settings.backupCreateBtn': 'Create backup',
    'settings.backupCreateFailed': 'Backup could not be created.',
    'settings.backupCodeTitle': 'Your backup code',
    'settings.backupKeepSafe':
        'Keep the code AND password safe (e.g. password manager). '
        'Without both, restore is impossible.',
    'settings.backupCopied': 'Backup code copied.',
    'settings.restoreOverwrite':
        'The current E2E identity on this device will be OVERWRITTEN '
        '(existing encrypted sessions are lost). Only use a backup of '
        'your own account.',
    'settings.restoreEnterTitle': 'Enter backup',
    'settings.restorePw': 'Backup password',
    'settings.restoreBtn': 'Restore',
    'settings.restoreFailed': 'Restore failed. Check code and password.',
    'settings.passkeysManage': 'Manage passkeys',
    'settings.passkeyCreatedAt': 'Created {date}',
    'settings.passkeyLastUsed': 'Last used {date}',
    'settings.passkeyRename': 'Rename',
    'common.close': 'Close',
    // Quiz "How well do I know my match"
    'quiz.title': 'Getting-to-know quiz',
    'quiz.loadError': 'Could not load the quiz state.',
    'quiz.photoHidden': 'Photo still hidden',
    'quiz.startTitle': 'How well do you know your counterpart?',
    'quiz.startBody':
        'You both get the same question. If you both answer correctly, the '
        'photo is unlocked permanently.',
    'quiz.startPersonalHint':
        'Questions are based on your counterpart\'s profile.',
    'quiz.startAttempt': 'Start attempt',
    'quiz.submit': 'Submit answer',
    'quiz.passedTitle': 'Passed! The photo is now unlocked permanently.',
    'quiz.toChat': 'To the chat',
    'quiz.partnerIntroTitle': "Your match's introduction",
    'quiz.correctTitle': 'Correct! Now you wait for your match\'s answer.',
    'quiz.correctBody':
        'If your counterpart also answers correctly, the quiz is passed.',
    'quiz.roundClosed':
        'The round is over. Your counterpart did not pass it, so you both '
        'start again after the break.',
    'quiz.wrongTitle': 'Unfortunately wrong.',
    'quiz.wrongBody':
        'Failed attempt {failed}: photo level {level}. New attempt after '
        'the 5-minute break.',
    'quiz.cooldownIn': 'Next attempt in {time}',
    'quiz.cooldownBody':
        'Each failed attempt starts a 5-minute break. Afterwards you can '
        'try again.',
    'quiz.cooldownReady': 'Ready - start a new attempt',
    'quiz.passedBadge': 'Quiz passed!',
    'quiz.passedBody':
        'The photo stays sharp and colored permanently. Your match\'s '
        'complete profile is now unlocked.',
    // Community guidelines (legal screen + one-time setup)
    'cg.0.title': '§0 Respectful interaction',
    'cg.0.body':
        'We expect all users to interact in a friendly, respectful and '
        'appreciative way, regardless of origin, gender, sexual '
        'orientation, religion or appearance. Criticism and rejection '
        'should always remain factual and non-degrading.',
    'cg.1.title': '§1 No harassment',
    'cg.1.titleShort': 'Treat others with respect and kindness.',
    'cg.1.body':
        'Insults, discrimination, threats or unwanted sexual advances are '
        'not permitted and lead to immediate exclusion.',
    'cg.2.title': '§2 Real profiles',
    'cg.2.titleShort': 'No fake profiles, no advertising, no abuse.',
    'cg.2.body':
        'Only use real information and pictures of yourself. Fake profiles '
        'or pretending to be someone else are prohibited. This applies in '
        'particular to your age and date of birth: pretending to be younger '
        'than you are endangers others, especially young users, and leads '
        'to a permanent ban when proven. Wisp cannot verify every detail '
        'and gives no guarantee for their accuracy.',
    'cg.3.title': '§3 No spam',
    'cg.3.titleShort':
        'Personality before looks: Photos are shown only after a spark.',
    'cg.3.body':
        'Advertising, chain letters or deliberately forwarding links to '
        'external offers are not allowed.',
    'cg.4.title': '§4 Privacy',
    'cg.4.titleShort': 'Respect boundaries: no unwanted pictures or messages.',
    'cg.4.body':
        'Do not share other people\'s private data (addresses, phone '
        'numbers, documents) without consent. Protecting minors has '
        'top priority.',
    'cg.5.title': '§5 Reporting & consequences',
    'cg.5.titleShort': 'Honesty pays off: Be authentic in your profile.',
    'cg.5.body':
        'Violations can be reported via the report button in profile and '
        'chat. Repeated or serious violations lead to account suspension.',
    // Setup: dialogs, validation, status
    'setup.abortTitle': 'Cancel setup?',
    'setup.abortBody':
        'Do you really want to cancel the setup? Your entries so far are '
        'saved.',
    'setup.abortContinue': 'Keep going',
    'setup.hintBio': 'Please write a short bio (about me).',
    'setup.hintInterests': 'Please pick at least one interest.',
    'setup.hintIntro':
        'Your intro needs text AND audio. Others should get to know you '
        'before they see your photo.',
    'setup.stepOf': 'Step {n} of {of}',
    'setup.flagsWarn':
        'Note: The setup state could not be saved to the server. The setup '
        'may appear again on your next login.',
    'setup.locationDetectFail':
        'Location could not be detected. Please enter it manually or grant '
        'access.',
    'setup.locationSuspicious':
        'Note: This location differs clearly from your previous locations '
        'on this device. If that is correct, choose it anyway - otherwise '
        'please enter your place manually.',
    'setup.locationError': 'Location detection failed: {error}',
    'setup.locationTooFar':
        'The place is more than 15 km away from your current location.',
    // Setup: page content
    'setupp.visibilitySub':
        'Who may see your profile? How should the app look?',
    'setupp.appearance': 'Appearance',
    'setupp.systemTheme': 'System',
    'setupp.lightTheme': 'Light',
    'setupp.darkTheme': 'Dark',
    'setupp.colorWorld': 'Color scheme',
    'setupp.lookingFor': 'I am looking for',
    'setupp.relType': 'Relationship type',
    'setupp.distance': 'Distance',
    'setupp.filterLabel': 'Filter',
    'setupp.maxDistance': 'Maximum distance: {km} km',
    'setupp.stateLabel': 'Federal state',
    'setupp.stateHint': 'e.g. Bavaria',
    'setupp.germanyNote': 'Profiles from all over Germany are shown.',
    'setupp.location': 'Location',
    'setupp.locationLabel': 'Your location / city',
    'setupp.locationHint': 'e.g. Berlin',
    'setupp.locationGps': 'Detect location (GPS)',
    'setupp.bioLabel': 'About me (bio)',
    'setupp.bioHint': 'e.g. hobbies, what matters to you',
    'setupp.stateOptional': 'Federal state (optional)',
    'setupp.profileSub':
        'A photo, a few words about you and your interests help others get '
        'to know you. All optional and changeable later.',
    'setupp.photoDone': 'Profile photo uploaded.',
    'setupp.photoFail':
        'Upload failed. You can set the photo later in your profile.',
    'setupp.introSub':
        'Tell about yourself, as text and voice. Both are shown to others '
        'before they see your photo. You can skip this step.',
    'setupp.habitsSub':
        'How do you feel about smoking, alcohol and drugs? These answers '
        'influence who you see in "Find your Match".',
    'setupp.habitsHint':
        'Only people who consume at most as much as you are shown. You can '
        'change this later in settings or in your profile.',
    'setupp.passkeySub':
        'Sign in without a password in the future, via fingerprint or face. '
        'Optional, you can skip this step.',
    'setupp.passkeyBody':
        'A passkey is the most secure and convenient sign-in method: no '
        'password to remember or forget, and harder to steal than a '
        'password.',
    'setupp.passkeyDone': 'Passkey set up',
    'setupp.passkeyStart': 'Set up passkey now',
    'setupp.mfaActive':
        'Two-factor protection is active. Every sign-in will ask for the '
        'code from your authenticator app.',
    'setupp.mfaBody':
        'A second factor protects your account even if your password is '
        'stolen. You need an authenticator app (e.g. Google Authenticator, '
        'Aegis or 2FAS).',
    'setupp.mfaDone': '2FA set up',
    'setupp.mfaStart': 'Set up now',
    'setupp.laterHint':
        'You can complete the setup any time later in the settings.',
    'setupp.guidelinesSub': 'Please accept the app\'s rules to continue.',
    'setupp.guidelinesIntroTitle': 'Community of values',
    'setupp.guidelinesIntroBody':
        'This app thrives on respectful, appreciative interaction, '
        'regardless of origin, gender, religion or way of life.',
    'setupp.guidelinesBan':
        'Violations lead to warnings up to a permanent ban.',
    'setupp.guidelinesWarn':
        'In case of violations access can be blocked permanently.',
    'setupp.finish': 'Accept & let\'s go',
    'setupp.changeLater':
        'You can change these settings any time later in the settings.',
    // Interests tab
    'interests.title': 'Interests',
    'interests.tabSent': 'Sent',
    'interests.tabReceived': 'Received',
    'interests.tabSparks': 'Sparks',
    'interests.emptySentTitle': 'You have not liked anyone yet',
    'interests.emptySentBody':
        'Meet people through their intro ("Find your Match") or swipe '
        'profiles blindly.',
    'interests.emptyReceivedTitle': 'No received likes yet',
    'interests.emptyReceivedBody':
        'As soon as someone likes your intro, they appear here and you '
        'decide on spark or decline.',
    'interests.emptySparksTitle': 'No sparks yet',
    'interests.emptySparksBody':
        'Confirm received likes to get sparks. Afterwards you can chat '
        'right away and optionally play the quiz for the photo.',
    'interests.likedYou': 'Liked you',
    'interests.decline': 'Decline',
    'interests.sparkAccepted':
        'A spark with {name} was created! You can chat right away.',
    'interests.likeDeclined': 'Like from {name} declined.',
    'interests.photoUnlocked': 'Photo unlocked',
    'interests.quizPending': 'Photo unlock: getting-to-know quiz',
    'interests.noBio': 'No bio',
    'interests.manage': 'Manage',
    'interests.hideSelected': 'Hide ({n})',
    'interests.hiddenCount': '{n} chat(s) removed from the list.',
    'interests.hideFailed':
        '{failed} of {total} could not be removed. Please try again.',
    'interests.resparkBtn': 'Re-spark',
    'interests.resparkFailed': 'Re-spark failed. Please try again.',
    'interests.cooledTitle': 'Cooled sparks',
    'interests.cooledSub':
        'Quietly ended - also automatically after 3 days without a '
        'message. The chat is kept, can be re-sparked any time',
    'interests.savedTitle': 'Saved profiles',
    'interests.savedSub':
        'Stored locally (max. 5) - to write to them later when you had no '
        'internet on the go',
    'interests.savedTileSub': 'Saved - write later',
    'interests.deleteSavedTitle': 'Remove saved profile?',
    'interests.deleteSavedBody':
        '{name} will be deleted locally. The related chat history is lost '
        'with it.',
    // QR flow
    'qr.menuTitle': 'QR code',
    'qr.choiceTitle': 'What would you like to do?',
    'qr.showMine': 'Show my QR code',
    'qr.showMineBtn': 'Show my own code',
    'qr.scanTitle': 'Scan QR code',
    'qr.enterCode': 'Enter code',
    'qr.enterCodeSub': 'Type the 8-digit code manually',
    'qr.enterCodeHint':
        'Enter the 8-digit code of the person\nyou want to find.',
    'qr.codeHint': 'e.g. A1B2C3D4',
    'qr.searchUser': 'Search user',
    'qr.ownCode': 'That is your own code!',
    'qr.noUserFound': 'No user found with this code.',
    // QR scan = like first (no instant chat)
    'qr.likeSent':
        'Like sent! As soon as the person accepts it, your chat opens up.',
    'qr.likeFailed': 'Like could not be sent: {error}',
    'qr.invalidCode':
        'This QR code is not a Wisp profile code. Please scan the personal '
        'QR code from the app.',
    'qr.savedOffline':
        'No internet - profile saved locally. You can write to the person '
        'later ("Saved profiles").',
    'onb.page1.title': 'Privacy & appearance',
    'onb.page2.title': 'Your profile',
    'onb.page3.title': 'Done',
    'onb.next': 'Next',
    'onb.back': 'Back',
    'onb.finish': 'Finish',
    'chat.hint': 'Message...',
    'chat.send': 'Send',
    'chat.empty': 'Write the first message! 😊',

    'chat.report': 'Report image',
    'chat.block': 'Block user',
    'chat.blockSub': 'No messages, likes or sparks from this person anymore.',
    'chat.end': 'End spark',
    'chat.call': 'Audio call',
    // Intro in chat + getting-to-know-you quiz banner (chat first)
    'chat.introTitle': 'Intro',
    'chat.quizBanner':
        'The getting-to-know-you quiz unlocks the profile photo. Chatting '
        'works independently.',
    'chat.quizOpen': 'Take quiz',
    // Herzensstärken (v0.9.2): Erinnerung, Freundschaft, Erinnerungsliste
    'milestone.sparkDay': 'Your first day',
    'milestone.sparkDayBody':
        'You found each other on {date}. Sometimes it helps to look '
        'back at why you started writing.',
    'milestone.quizPassed': 'Quiz passed',
    'milestone.quizPassedBody':
        'You knew each other in the quiz on {date} - the photo has been '
        'unlocked since then.',
    'milestone.month1': 'One month',
    'milestone.month1Body':
        'One month of sparks: {date} until today. What was your best '
        'conversation?',
    'milestone.month3': 'Three months',
    'milestone.month3Body':
        'Three months since {date}. Some connections need time - you '
        'gave it to them.',
    'milestone.year1': 'One year',
    'milestone.year1Body':
        'One year! From the first spark on {date} to here - that '
        'deserves honest respect.',
    'milestone.title': 'Remember this',
    'milestone.dismiss': 'Close',
    'friends.toggleTitle': 'Friendship',
    'friends.toggleHint':
        'This connection is a friendship - not a romantic spark. You '
        'can switch it back at any time.',
    'friends.badge': 'Friendship',
    'bucket.title': 'Memory list',
    'bucket.hint':
        'Things you want to experience together. Both of you can add '
        'and check off entries.',
    'bucket.add': 'Add',
    'bucket.addHint': 'What do you want to do together?',
    'bucket.empty':
        'Empty so far. Write down your first ideas - big and small.',
    'bucket.staleNote':
        'Your memory list has been waiting for {days} days - feel like '
        'picking something from it?',
    'bucket.mine': 'by you',
    'bucket.theirs': 'by {name}',
    'whatsnew.v090.sparkMoments':
        'Milestones in the chat: first day, quiz passed and '
        'anniversaries are acknowledged honestly.',
    'whatsnew.v090.friendship':
        'Friendship mode: connections can now be explicitly marked as '
        'friendship.',
    'whatsnew.v090.bucketList':
        'Shared memory list in the chat: things you want to experience '
        'together - checkable, no pressure.',
    'whatsnew.v090.birthdayStyles':
        '5 tasteful birthday styles for your profile (choose below or '
        'later in profile editing).',
    // Voice messages (listen once, M-17)
    'chat.voiceOnce':
        'This voice message was already listened to and removed (privacy: '
        'decrypted audio remains are deleted).',
    'chat.voiceOnlyOnce':
        'Playback not possible - the message was already '
        'listened to.',
    'chat.voiceListened': 'listened',
    // Chat dialogs & controls
    'chat.you': 'You',
    'chat.callBatteryHint':
        'Calls continuously use microphone and radio and noticeably '
        'drain the battery.',
    'chat.ageGapHint':
        'Note: you are {my} and {other} years old. Profiles may contain '
        'false information. Stay cautious, only meet in public and report '
        'suspected false age.',
    'chat.relayBannerShort': 'No direct connection',
    'chat.relayBanner':
        'No direct connection. Messages stay end-to-end encrypted and '
        'arrive once the chat is opened.',
    'chat.relayStored':
        'Stored encrypted. Will be delivered once the chat is opened.',
    'chat.sendFailed': 'Message could not be sent: {error}',
    'chat.queuedHint':
        'Offline - message is queued and will be delivered on the next '
        'direct connection.',
    'chat.spiceUnavailable':
        'Icebreaker questions are only available for spark chats (not for '
        'saved contacts).',
    'chat.quizUnavailable':
        'The getting-to-know-you quiz is only available for spark chats.',
    'chat.imageSend': 'Send image',
    'chat.idea.coffeeCake': 'Coffee & cake',
    'chat.idea.walk': 'Going for a walk together',
    'chat.idea.iceCream': 'Getting ice cream',
    'chat.idea.museum': 'Museum or exhibition',
    'chat.idea.minigolf': 'Mini golf',
    'chat.idea.movieNight': 'Movie night',
    'chat.idea.market': 'Strolling through a market',
    'chat.idea.bowling': 'Bowling or billiards',
    'chat.idea.liveMusic': 'Live music',
    'chat.idea.stargazing': 'Stargazing',
    'chat.imageBlurredHint':
        'Pixelated image message. Double-tap to show after the '
        'warning, long-press to report.',
    'chat.imageHint':
        'Image message. Double-tap for fullscreen, long-press to '
        'report.',
    'chat.camera': 'Camera',
    'chat.gallery': 'Gallery',
    'chat.imageSendFailed': 'Sending failed',
    'chat.imageSendFailedBody': 'The image could not be sent.\n\n{error}',
    'chat.retry': 'Retry',
    'chat.voiceTooShort': 'Recording too short (< 1 s), discarded.',
    'chat.voiceRecordFailed': 'Recording failed: {error}',
    'chat.voiceStartFailed': 'Recording could not be started: {error}',
    'chat.voiceCancelled': 'Recording cancelled',
    'chat.voiceStopSend': 'Stop recording & send',
    'chat.voiceTooltip': 'Voice message',
    'chat.voiceCancel': 'Cancel recording',
    'chat.recordingHint': 'Recording: {s} s',
    'chat.blockTitle': 'Block user?',
    'chat.blockBody':
        '{name} will be blocked permanently: the spark is ended and this '
        'person can no longer like you, spark you or send you messages. '
        'Blocking cannot be undone via the support dialog later. Only you '
        'can remove it in the settings.',
    'chat.blockAction': 'Block',
    'chat.blockedDone': '{name} was blocked.',
    'chat.blockFailed': 'Blocking failed. Please try again.',
    'chat.spiceTooltip': 'Icebreaker questions (Spice Questions)',
    'chat.reportTooltip': 'Report user',
    'chat.reportImageSub': 'Sent with context to the support team.',
    'chat.ideaWheelBtn': 'Spin the wheel, find a date idea',
    'chat.ideaHide': 'Hide date wheel for this chat',
    'chat.icebreakerOn': 'Show interest suggestions',
    'chat.icebreakerOff': 'Hide interest suggestions',
    'chat.icebreakerText':
        'We share the interest "{interest}". Tell me about it: what was '
        'your highlight there? 😊',
    'chat.dateIdea': 'Date idea: {idea} ✨ What do you think?',
    'chat.ideaSendFailed': 'Suggestion could not be sent.',
    'chat.endSparkTitle': 'End spark - honestly & kindly',
    'chat.endSparkBody':
        'The spark moves to "Cooled sparks" for both of you - without '
        'countdown, without notification. Re-sparking is one tap away at '
        'any time.',
    'chat.endSilent': 'Let it end quietly',
    'chat.endSilentSub': 'Without a message',
    'chat.goodbye.1':
        'Hey, I really had lovely conversations with you, but I feel '
        'myself that it is not going to become what we both deserve. I am '
        'letting the spark rest now - thank you and all the best! 🌿',
    'chat.goodbye.2':
        'I like you, but I notice that I currently cannot invest as much '
        'as you. I find it more honest to say that clearly instead of '
        'vanishing. Take care! 🙏',
    'chat.goodbye.3':
        'We do not fit together for me right now - that says nothing about '
        'you. I wish you all the best from my heart! ✨',
    'chat.goodbye.4':
        'My feelings have changed. Instead of leaving you in uncertainty, '
        'I let the spark rest gently now. Thanks for the beautiful '
        'moments! 🕊️',
    'chat.wheelTitle': 'Spin the wheel',
    'chat.wheelSpin': 'Spin',
    'chat.wheelAgain': 'Spin again',
    'chat.wheelHint':
        'Like it? Send the suggestion - your counterpart can simply reply.',
    'chat.wheelSend': 'Send suggestion',
    'chat.revealTitle': 'Show image?',
    'chat.revealBody':
        'This image is blurred to protect you from inappropriate content. '
        'It may contain content you find disturbing.\n\nYou can report it '
        'directly afterwards.',
    'chat.revealAction': 'Show',
    'chat.reportImage': 'Report image',
    'chat.blurred': 'Blurred',
    'chat.viewOnce': 'Once',
    'chat.viewedOnce': 'Already viewed',
    'chat.photosAfterSpark': 'Photos visible after spark',
    'chat.safetyNotConnected':
        'No encrypted connection to {name} established yet. The number '
        'appears after the first message.',
    'chat.safetyCompare':
        'Compare this number with {name}, ideally in person or by phone:',
    'chat.identityVerifiedHint': 'Only enable if the numbers match.',
    'chat.more': 'More options',
    'dh.event.startingSoon': 'Dating Hour starts soon',
    'dh.event.cancelledToday':
        "Today's Dating Hour is cancelled: not enough people signed up.",
    'dh.event.serverTimeWarn': 'The server time could not be verified.',
    'dh.event.loadErrorFull': 'Loading failed: {error}',
    'dh.event.autoJoinFailed': 'Auto-join failed: {error}',
    'dh.event.autoJoinAsk':
        "Today's event is over. Would you like to automatically join "
        'the next one?',
    'dh.event.welcomeBack': 'Welcome back! You are automatically in.',
    'dh.event.autoJoinOn': 'You will automatically join the next Dating Hour.',
    'dh.event.autoJoinOff': 'Alright, you will be asked next time.',
    'dh.event.prefsNote': '(changeable in the preferences).',
    'dh.event.localTimeWarn':
        'Countdown and status are based on the local device time. '
        'The server time could not be verified.',
    'dh.event.liveNow': 'LIVE: Dating Hour is running!',
    'dh.event.nextAt': 'Next Dating Hour on {date}',
    'dh.event.chipParticipating': "You're participating",
    'dh.event.chipNotParticipating': 'Not registered',
    'dh.event.participatingLive': "You're in! Chats are running.",
    'dh.event.participatingWaiting': "You're in! Waiting for the start.",

    'dh.rules.title': 'Dating Hour rules',
    'dh.rules.intro': 'Please read these rules carefully before joining.',
    'dh.rules.acceptedTitle': 'Rules accepted',
    'dh.rules.next': 'Next',
    'dh.how.title': 'How does Dating Hour work?',
    'dh.how.intro':
        'The Dating Hour takes place every Saturday from 20:00 to 21:00. '
        'Here is the flow at a glance:',
    'dh.how.next': 'Go to Dating Hour',
    'dh.rules.introLong':
        'Please read these rules carefully before taking part in the '
        'Dating Hour.',
    'dh.rules.bodyFun': 'Have fun at the Dating Hour!',
    'dh.rules.1.title': 'Stay respectful',
    'dh.rules.1.body':
        'Treat your counterpart with respect. No insults, discrimination '
        'or unwanted messages.',
    'dh.rules.2.title': 'No sharing of personal data',
    'dh.rules.2.body':
        'Do not share addresses, phone numbers or account details. Stay '
        'in the app for now.',
    'dh.rules.3.title': 'Honest profile',
    'dh.rules.3.body':
        'Use only real information and current pictures. Fake profiles '
        'or identity theft will be reported.',
    'dh.rules.4.title': '5 minute rule',
    'dh.rules.4.body':
        'Each chat lasts a maximum of 5 minutes. Afterwards you decide '
        'whether you want to extend the match.',
    'dh.rules.5.title': 'No unwanted pictures',
    'dh.rules.5.body':
        'Do not send intimate pictures or unwanted content. Violations '
        'lead to an immediate ban.',
    'dh.rules.6.title': 'Minor protection',
    'dh.rules.6.body':
        'The Dating Hour is only available from age 16. Younger users '
        'are automatically excluded.',
    'dh.how.step1.title': 'Join',
    'dh.how.step1.body':
        'Choose your preferences and join the Saturday event. You can '
        'leave at any time.',
    'dh.how.step2.title': 'Waiting for a match',
    'dh.how.step2.body':
        'The app connects you with a matching person. As soon as both '
        'are ready, the 5 minute chat starts.',
    'dh.how.step3.title': 'Chat for 5 minutes',
    'dh.how.step3.body':
        'Get to know the person in a short, time-limited conversation. '
        'Photos are shown depending on your settings.',
    'dh.how.step4.title': 'Decision',
    'dh.how.step4.body':
        'After the chat you decide whether you want to extend the '
        'contact.',
    'dh.how.step5.title': 'Sparks',
    'dh.how.step5.body':
        'If both decide to extend, a spark is created and you can keep '
        'chatting.',
    'dh.chat.sparkJumped': 'A spark jumped! Opening the chat...',
    'dh.chat.noSpark': 'No spark',
    'dh.chat.keepSearching': 'Keep searching',
    'dh.chat.e2e': 'End-to-end encrypted',
    'dh.chat.leaveTitle': 'Leave chat?',
    'dh.chat.leaveBody':
        'Leaving the chat counts as "declining". Do you really want to '
        'go?',
    'dh.chat.stay': 'Stay',
    'dh.chat.leaveDecline': 'Leave & decline',
    'dh.chat.sayHello': 'Say hi to {name}!',
    'dh.chat.fiveMinutes':
        'You have 5 minutes to get to know each other. Afterwards you '
        'both decide: match or keep searching?',
    'dh.chat.icebreakerBtn': 'Send conversation starter',
    'dh.chat.hint': 'Message...',
    'dh.chat.timeUp':
        'The 5 minutes are up!\nWould you like to see each other again?',
    'dh.chat.decline': 'Decline', 'dh.chat.accept': 'Accept',
    'dh.chat.bothMustAccept': 'Both must press "Accept" for a spark.',
    'dh.chat.voted': 'You have voted. Waiting for the other side...',
    'dh.chat.resultPending':
        'As soon as both have decided, you will see the result.',
    'dh.chat.backToOverview': 'Back to overview',
    'dh.chat.sendFailed': 'Message could not be sent.',
    'dh.gender.all': 'All genders',
    'dh.gender.women': 'Women',
    'dh.gender.men': 'Men',
    'dh.gender.nonBinary': 'Non-binary people',
    'dh.prefs.title': 'Dating Hour: preferences',
    'dh.prefs.header': 'Your Dating Hour preferences',
    'dh.prefs.headerSub':
        'These settings help us connect you with matching people. You can '
        'adjust them before every event.',
    'dh.prefs.ageRange': '{min} to {max} years',
    'dh.prefs.sectionJoin': 'Participation',
    'dh.prefs.autoJoin': 'Automatically join again',
    'dh.prefs.autoJoinSub':
        'If enabled, you will automatically take part in the next Dating '
        'Hour event.',
    'dh.prefs.traitHint':
        'Pick a trait or type your own. It flows into matching as a soft '
        'factor.',
    'dh.prefs.traitOwn': 'Enter custom trait',
    'dh.prefs.traitHintField': 'e.g. "Good vibes", "Deep conversations"...',
    'dh.prefs.habits': 'Habits (optional)',
    'dh.prefs.intro':
        'These settings help us connect you with matching people. '
        'You can adjust them before every event.',
    'dh.prefs.ageSection': 'Age range',
    'dh.prefs.genderSection': 'I am looking for...',
    'dh.prefs.joinSection': 'Participation',
    'dh.prefs.autoJoinHint':
        'If enabled, you will automatically take part in the next '
        'Dating Hour once it starts.',
    'dh.prefs.traitSection': 'What you especially like in others',
    'dh.prefs.traitHint2':
        'Choose a trait or enter your own. '
        'This counts as a soft factor in match suggestions.',
    'dh.prefs.habitsHint2':
        'People with matching habits will be suggested to you first '
        'in match suggestions, nobody is excluded.',
    'dh.prefs.saveHint2':
        'Saving does NOT sign you up. You confirm your participation '
        'separately with "I am in" on the event screen.',
    'dh.prefs.trait.humor': 'Humor',
    'dh.prefs.trait.honesty': 'Honesty',
    'dh.prefs.trait.adventure': 'Love of adventure',
    'dh.prefs.trait.intelligence': 'Intelligence',
    'dh.prefs.trait.empathy': 'Empathy',
    'dh.prefs.trait.spontaneity': 'Spontaneity',
    'dh.prefs.trait.reliability': 'Reliability',
    'dh.prefs.trait.passion': 'Passion',
    'dh.prefs.trait.openness': 'Openness',
    'dh.prefs.trait.downToEarth': 'Down-to-earth attitude',
    'dh.prefs.habitsSub':
        'People with matching habits are suggested to you first during '
        'matching, nobody is excluded.',
    'dh.prefs.save': 'Save preferences',
    'dh.prefs.saveNote':
        'Saving does NOT sign you up. You confirm your participation '
        'separately with "I am in" on the event screen.',
    'dh.prefs.saved':
        'Preferences saved. You confirm your participation with "I am '
        'in" on the event day.',
    'dh.event.joinConfirmTitle': 'Join the event?',
    'dh.event.join': 'I am in',
    'dh.event.joined': "You're in for the Dating Hour event!",
    'dh.event.left': 'You left the event.',
    'dh.event.bye': 'See you next time!',
    'dh.event.noThanks': 'No, thanks',
    'dh.event.yesPlease': 'Yes, please',
    'dh.event.title': 'Dating Hour',
    'dh.event.ended': 'Dating hour ended',
    'dh.event.joinNow': 'Join now & chat',
    'dh.event.leave': 'Leave',
    'dh.event.setPrefs': 'Set preferences',
    'dh.event.nextIn': 'Next event in {d}',
    'dh.event.searching': 'Searching...',
    'dh.event.loadError': 'Loading error',
    'dh.event.searchingPartner': 'Looking for a partner for you...',
    'dh.event.toChat': 'To chat',
    'dh.event.nonePlanned': 'Currently no Dating Hour event is planned.',
    'dh.event.remaining': '{d} left',
    'dh.event.startIn': 'Starts in {d}',
    'dh.event.chatsRunning': 'Chats are running.',
    'dh.event.waitStart': 'Waiting for the start.',
    'dh.event.participating': 'You are in!',
    // Dating Hour rules detail lines (event screen, rules card)
    'dh.event.rulesTitle': 'Important rules',
    'dh.event.rule.1':
        'Saturdays 20:00 to 21:00 (you can already join beforehand).',
    'dh.event.rule.2':
        'Connected directly in a 1:1 chat, without viewing profiles first.',
    'dh.event.rule.3': '5 minutes of chat, then decide: "Accept" or "Decline".',
    'dh.event.rule.4': 'A spark only forms if BOTH sides "Accept".',
    'dh.event.rule.5': 'On "Decline" (or timeout): automatic new matching.',
    'dh.event.rule.6': 'During a chat: ONLY this chat is allowed.',
    'dh.event.rule.7': 'End at 21:00; ongoing chats are finished.',
    'dh.event.participants': '{n} participants joined',
    'dh.event.participantsSub':
        'The Dating Hour always takes place, no matter how many join. If '
        'there is nobody to pair you with, you get no conversation this time.',
    'dh.event.rule.8':
        'The Dating Hour always takes place, no matter how many join. '
        'There is no minimum number anymore.',
    'dh.event.rule.9': 'Creating fake accounts is strictly prohibited.',

    'profile.edit.filters': 'Filters & preferences',
    'profile.edit.radiusMode': 'Define search radius by',
    'profile.edit.maxDistance': 'Maximum distance: {km} km',
    'profile.edit.minAge': 'Minimum age: {age} years',
    'profile.edit.maxAge': 'Maximum age: {age} years',
    'profile.edit.bio': 'Bio',
    'profile.edit.music': 'Music',
    'profile.edit.musicSub':
        'Which music describes you? Your taste flows into the connection '
        'score.',
    'profile.edit.habits': 'Habits',
    'profile.edit.habitsSub':
        'How do you feel about these? Your answers influence who you see '
        'in "Find your Match". Only people who consume at most as much '
        'as you do are shown.',
    'profile.edit.interests': 'Interests',
    'profile.edit.personality': 'Personality test',
    'profile.edit.personalityDone':
        'You have completed the test. You can retake it at any time.',
    'profile.edit.personalityOpen': 'Show others who you really are.',
    'profile.edit.personalityRetake': 'Retake test',
    'profile.edit.personalityStart': 'Start personality test',
    'profile.edit.saved': 'Profile saved',
    'profile.edit.savedNoSync':
        'Saved locally. Server sync failed, please save again later.',
    'profile.edit.missingFields':
        'Some information is missing or some fields are invalid (marked '
        'in red).',
    'profile.edit.missingFieldsHint':
        'Some information is missing or some fields are invalid (marked '
        'in red). Please check the form.',
    'profile.edit.birthDateMissing': 'Please choose your date of birth',
    'profile.edit.photoUpdated': 'Profile picture updated.',
    'profile.edit.photoUploadError': 'Upload failed: {error}',
    'profile.edit.photoPolicyBlocked':
        'This image does not meet our guidelines and was not uploaded.',
    'profile.edit.photoNsfwTitle': 'Image not approved',
    'profile.edit.photoNsfwBody':
        'This image was classified on your device as potentially '
        'inappropriate and will not be uploaded.',
    'profile.edit.photoNsfwChoice': 'What would you like to do?',
    'profile.edit.photoNsfwAppeal': 'Appeal',
    'profile.edit.photoNsfwUnderstood': 'Understood',
    'profile.edit.photoNsfwVerdict': 'Local verdict: {label} ({score} %).',
    'profile.edit.photoNsfwNotUploaded':
        'This image will not be uploaded as your profile picture.',
    'profile.edit.photoOkTitle': 'Image checked',
    'profile.edit.photoOkBody': 'Your image is fine and can be used.',
    'profile.edit.photoOkBtn': 'Continue',
    'profile.edit.appealSubmitted':
        'Appeal submitted. We will notify you about the decision.',
    'profile.edit.appealFailed':
        'Appeal could not be submitted. Please try again later.',
    'profile.appeal.approvedTitle': 'Image approved',
    'profile.appeal.approvedBody':
        'Your appeal has been reviewed: the image is approved. Would you '
        'like to use it as your profile picture now?',
    'profile.appeal.useBtn': 'Use now',
    'profile.appeal.applied': 'Profile picture updated.',
    'profile.appeal.rejectedTitle': 'Image rejected',
    'profile.appeal.rejectedBody':
        'Your appeal has been reviewed: the image was rejected and cannot '
        'be used. Please choose a different profile picture.',
    'profile.appeal.okBtn': 'Understood',
    'profile.edit.photoNsfwOther': 'Choose another image',
    'profile.edit.birthDateLocked':
        'To protect against age deception, the birth date cannot be '
        'changed after registration.',
    'profile.edit.favoriteSong': 'Favorite song',
    'profile.edit.favoriteSongHint': 'e.g. song title …',
    'profile.edit.favoriteBand': 'Favorite band',
    'profile.edit.favoriteBandHint': 'e.g. band or artist …',
    'music.excludeTitle': 'Exclude genre',
    'music.excludeHint':
        'This genre negatively influences your matching - you will see '
        'fewer people with this taste.',
    'music.excludeSearch': 'Search genre …',
    'music.excludeNoMatch': 'No genre found.',
    'profile.edit.locationDetected': 'Location detected and applied.',
    'profile.edit.locationFailed':
        'Location could not be determined. Please enter it manually or '
        'grant permission.',
    'profile.edit.locationSuspicious':
        'Note: This location differs greatly from your previous locations '
        'on this device.',
    'profile.edit.locationError': 'Location detection failed: {error}',
    'profile.edit.unsavedTitle': 'Unsaved changes',
    'profile.edit.unsavedBody':
        'Your profile changes have not been saved yet. What would you '
        'like to do?',
    'profile.edit.unsavedDiscard': 'Discard',
    'profile.edit.farAway':
        'The place is more than 15 km away from your current location '
        '({meters} m). Please enter a nearby place.',
    'profile.edit.distanceKm': 'Distance in km',
    'profile.edit.modeGermany': 'All of Germany',
    'profile.edit.habitsDealbreaker': 'Dealbreaker: same consumption',
    'profile.edit.habitsDealbreakerSub':
        'Only show me people who consume at most as much as I do.',
    'profile.detail.aboutMe': 'About me',
    // Saved profiles (local, max. 5)
    'profile.detail.savedSave': 'Save profile locally (write later)',
    'profile.detail.savedRemove': 'Remove saved profile',
    'profile.detail.savedDone':
        '{name} saved locally. You can write to {name} later.',
    'profile.detail.savedRemoved': '{name} was removed.',
    'profile.detail.noBio': 'No bio yet.',
    'profile.detail.interests': 'Interests',
    'profile.detail.commonWithYou': 'Shared with you',
    'profile.detail.more': 'More',
    'profile.detail.title': 'Profile',
    'profile.detail.retry': 'Try again',
    'profile.detail.photosLockedHint':
        'Photos appear here once the getting-to-know quiz is passed '
        'and the person has uploaded a profile picture.',
    'profile.detail.type': 'Type {t}',
    'profile.detail.reportUser': 'Report user',
    'profile.detail.blockUser': 'Block',
    'profile.detail.music': 'Music',
    'profile.detail.favoriteSong': 'Favorite song: {song}',
    'profile.detail.favoriteBand': 'Favorite band: {band}',
    'profile.detail.sameTaste': 'Same taste',
    'profile.detail.noMusic': 'No music taste given.',
    'common.refresh': 'Refresh',
    'settings.twoFactor': 'Two-factor protection (2FA)',
    'settings.twoFactorActive': 'Active: login only with authenticator code',
    'settings.twoFactorSetup': 'Secure your login with an authenticator app',
    'settings.notifyLikesSub': 'When someone likes you',
    'settings.notifyMessagesSub': 'When someone writes to you',
    'settings.unifiedPush': 'Push without Google (UnifiedPush)',
    'settings.unifiedPushOn': 'Active - endpoint registered.',
    'settings.unifiedPushOff':
        'Requires a distributor app like ntfy (F-Droid). FCM stays active '
        'in the Play variant.',
    'settings.blurSub':
        'Protection from inappropriate content: images from your match are '
        'only shown after confirmation (long press to report).',
    'settings.keyBackup': 'Encrypted key backup',
    'settings.keyBackupSub':
        'Backs up the private identity of your end-to-end encryption '
        '(password-encrypted, AES-256-GCM). Only with it can you chat '
        'encrypted again after switching devices. Losing both backup AND '
        'password is irreversible.',
    'settings.backupCreateSub': 'Generates an encrypted code',
    'settings.backupRestoreSub': 'Overwrites the current E2E identity',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Help with harassment or stalking, blocking, reporting',
    // Privacy & account
    'privacy.title': 'Privacy & account',
    'privacy.validator.invalidEmail': 'Invalid',
    'privacy.validator.tooShort': 'Too short',
    'privacy.validator.mismatch': 'Does not match',
    'privacy.yourData': 'Your data',
    'privacy.dataInfo':
        'Wisp stores profile information, location data (only if you '
        'share it), photos, chats, likes and matches. All data is '
        'transferred encrypted and stored only as long as your account is '
        'active.',
    'privacy.export': 'Export my data',
    'privacy.exportSub': 'JSON download of all personal data',
    'privacy.exportFailed': 'Export failed',
    'privacy.import': 'Import my data',
    'privacy.importSub': 'Restore your JSON data export',
    'privacy.importTitle': 'Import data',
    'privacy.importBody':
        'Paste the contents of your export file '
        '(wisp_data_export.json) here. Profile, settings and '
        'preferences will be restored.',
    'privacy.importHint': '{ ... paste JSON here ... }',
    'privacy.importApply': 'Import',
    'privacy.importInvalid':
        'The pasted JSON could not be read. Please check the content.',
    'privacy.importDone': 'Data imported successfully.',
    'privacy.importFailed': 'Import failed',
    'privacy.accountSection': 'Sign-in',
    'privacy.accountInfo':
        'Email and password changes require your current password. For '
        'email changes you confirm the new address via a link sent to '
        'both inboxes.',
    'privacy.changeEmail': 'Change email address',
    'privacy.changeEmailInfo':
        'You will receive a confirmation link at your old AND new '
        'address. The change only becomes active after confirmation.',
    'privacy.changeEmailSent':
        'Confirmation link sent to both email addresses.',
    'privacy.changePassword': 'Change password',
    'privacy.changePasswordDone': 'Password changed.',
    'privacy.changeFailed': 'Change failed',
    'auth.passwordCurrent': 'Current password',
    'auth.passwordNew': 'New password',
    'auth.passwordConfirm': 'Repeat new password',
    'privacy.processors': 'Processors',
    'privacy.processorsInfo':
        'The following service providers (Art. 28 GDPR) process data on '
        'our behalf. Chat content is end-to-end encrypted and is not '
        'processed by any provider.',
    'privacy.processorSupabase': 'Hosting, database, authentication (EU)',
    'privacy.processorGoogle': 'Push notifications',
    'privacy.processorBrevo': 'Transactional emails (confirmation, reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile) and TURN relay',
    'privacy.processorNetlify': 'Hosting of the auth/CAPTCHA page',
    'privacy.processorApple': 'App Store distribution',
    'privacy.consent': 'Consents',
    'privacy.location': 'Location sharing',
    'privacy.locationSub':
        'You can revoke location sharing at any time in your device\'s '
        'system settings.',
    'privacy.openLocationSettings': 'Open location settings',
    'privacy.push': 'Push notifications',
    'privacy.pushSub':
        'Opens your device\'s app settings, where you can control '
        'notifications.',
    'privacy.openAppSettings': 'Open app settings',
    'privacy.dangerZone': 'Danger zone',
    'privacy.deleteAccount': 'Delete account permanently',
    'privacy.deleteAccountSub':
        'GDPR Art. 17: Right to erasure. All data will be removed.',
    'privacy.deleteTitle': 'Delete account?',
    'privacy.deleteBody':
        'This step cannot be undone. All your data (profile, photos, '
        'chats, matches, likes) will be permanently deleted.',
    'privacy.deleteConfirm': 'Delete permanently',
    'privacy.deleteFailed': 'Account could not be deleted',
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'common.yes': 'Yes',
    'common.no': 'No',
    'common.continue': 'Continue',
    'common.back': 'Back',
    'whatsnew.title': 'New in this version',
    'whatsnew.inputsTitle': 'New choices',
    'whatsnew.cta': "Let's go",
    'common.loading': 'Loading…',
    'common.errorOccurred': 'An error occurred:',
    'validation.field': 'Field',
    'validation.required': '{field} must not be empty',
    'validation.nameEmpty': 'Please enter a name',
    'validation.nameShort': 'Name is too short',
    'validation.ageEmpty': 'Please enter your age',
    'validation.ageNumber': 'Please enter a number',
    'validation.ageMin': 'You must be at least {age} years old to use this app',
    'validation.ageInvalid': 'Please enter a valid age',
    'validation.emailEmpty': 'Please enter your email',
    'validation.emailInvalid': 'Please enter a valid email address',
    'validation.emailTld':
        'Please enter an email with a valid domain ending '
        '(e.g. .de, .com, .net, .org)',
    'validation.passwordEmpty': 'Please enter a password',
    'validation.passwordLength': 'The password needs at least 8 characters',
    'validation.passwordLetter': 'The password needs at least one letter',
    'validation.passwordDigit': 'The password needs at least one digit',
    'validation.passwordCommon':
        'This password is too common. Please choose a safer one.',
    'validation.pwChars': '8 characters',
    'validation.pwLower': 'a lowercase letter',
    'validation.pwUpper': 'an uppercase letter',
    'validation.pwDigit': 'a digit',
    'validation.pwSpecial': 'a special character',
    'validation.pwMissing': 'The password needs: {list}',
    'validation.pwWeak': 'Weak',
    'validation.pwMedium': 'Medium',
    'validation.pwStrong': 'Strong',
    'validation.birthEmpty': 'Please pick your birth date',
    'validation.birthFuture': 'The birth date must not be in the future',
    'validation.birthInvalid': 'Please enter a valid birth date',
    'validation.bioLong': 'Maximum 300 characters',
    'common.skip': 'Skip',
    'common.confirm': 'Confirm',
    'common.check': 'Check',
    'common.discard': 'Discard',
    'common.done': 'Done',
    'common.whatHappened': 'What happened?',
    'nav.unsavedTitle': 'Unsaved changes',
    'nav.unsavedBody':
        'Your profile changes have not been saved yet. What would you '
        'like to do?',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email or password is wrong.',
    'error.notConfirmed': 'Please confirm your email address first.',
    'error.alreadyRegistered':
        'This email address is already registered. Please log in directly '
        'or reset your password.',
    'error.rateLimited':
        'Too many requests in a short time. Please wait a '
        'moment and try again.',
    'error.weakPassword':
        'The password is too weak. Please choose a longer '
        'one with upper/lower case letters, numbers and special characters.',
    'error.captchaRejected':
        'The security check was rejected by the server. '
        'Please try again.',
    'error.signupFailed':
        'Sign-up failed on the server. Please try again '
        'later.',
    'error.loginFailed': 'Log-in failed. Please try again.',
    'error.generic': 'Something went wrong. Please try again.',
    // Admin area (visible for moderation only)
    'admin.deniedTitle': 'Access denied',
    'admin.deniedBody': 'You do not have permission to open this area.',
    'admin.title': 'Admin area',
    'admin.tabReports': 'Reports',
    'admin.tabBugs': 'Bug reports',
    'admin.tabVerification': 'Verification',
    'admin.tabModeration': 'Moderation',
    'admin.tabAppeals': 'Image review',
    'admin.tabBans': 'Bans',
    'admin.close': 'Close',
    'admin.error': 'Error: {error}',
    'admin.retry': 'Try again',
    'admin.unknown': 'unknown',
    'admin.reportResolveFailed': 'Could not resolve report: {error}',
    'admin.noReports': 'No reports.',
    'admin.noBugs': 'No bug reports.',
    'dh.event.joinConfirmBody':
        'You will only be matched with someone if you confirm now. '
        'You can drop out any time.',
    'dh.duration.minute': '{m} minute',
    'dh.duration.minutes': '{m} minutes',
    'dh.duration.hour': '{h} hour',
    'dh.duration.hours': '{h} hours',
    // Safety center
    'safety.centerTitle': 'Safety center',
    'safety.myReports': 'My reports',
    'safety.noReports': 'You have not written any reports yet.',
    'safety.unblockFailed': 'Unblock failed. Please try again.',
    'safety.blockedUsers': 'Blocked users',
    'safety.noBlocked': 'You have not blocked anyone.',
    'safety.unblock': 'Unblock',
    // Mood
    'mood.title': 'Mood of the day',
    'mood.saved': 'Mood saved',
    'mood.question': 'How are you feeling today?',
    'mood.explainer': 'Your mood helps us suggest better matches for you.',
    'mood.saving': 'Saving...',
    'mood.save': 'Save',
    'mood.current': 'Current mood',
    // Home (latest)
    'home.title': 'Latest',
    'home.fallbackName': 'you',
    'home.discover': 'Discover people',
    'home.randomChat': 'Start random chat',
    // Find your Match
    'match.required': 'Text AND audio are required.',
    'match.title': 'Find your Match',
    'match.editIntro': 'Edit my intro',
    'match.createFirst': 'First create your own intro',
    'match.createSub':
        'Others get to know you through your intro before seeing '
        'a photo.',
    'match.saveContinue': 'Save & continue',
    'match.empty': 'There are no new intros right now.',
    'match.introTitle': 'Introduction',
    'match.noIntro': 'This person has not added an introduction yet.',
    'match.interestsTitle': 'Interests',
    'match.emptyTip':
        'Tip: Add an intro to your profile and you will be shown '
        'to others here.',
    'match.reload': 'Reload',
    // Startup / update
    'startup.failedTitle': 'The app could not be started.',
    'startup.failedBody': 'Please close the app completely and try again.',
    'update.required': 'Update required',
    'update.body':
        'Your version of Wisp no longer supports all server features. '
        'Please update the app to continue.',
    'update.now': 'Update now',
    'update.later': 'Continue anyway',
    // Video verification
    'verify.title': 'Video verification',
    'verify.start': 'Start video verification',
    'verify.errorTitle': 'Error',
    'verify.infoBody':
        'To make sure real people use the app, you record a short selfie '
        'video (5 to 15 seconds).',
    'verify.infoCardTitle': 'What happens to your video?',
    'verify.info.1': 'The video is stored **encrypted locally**.',
    'verify.info.2':
        'After submission it sits in **private storage**. Only support '
        'can view it for review.',
    'verify.info.3':
        'It serves **personal review by support** (human verification).',
    'verify.info.4':
        'It is **never** shown publicly or shared with third parties.',
    'verify.info.5':
        'You can delete it any time; if rejected it is removed '
        'automatically.',
    'verify.info.6':
        'Take off **headwear, headphones, sunglasses and masks**: '
        'Your face must be fully visible, otherwise support reviews '
        'manually.',
    'verify.locationTitle': 'One-time location check',
    'verify.locationBody':
        'We additionally ask for your GPS location **once**. This helps '
        'us detect masses of fake accounts from the same place or device. '
        'The location is stored **only** for this security check and not '
        'used for matching.',
    'verify.taskTitle': 'Your task:',
    'verify.recording': 'Recording: {s} s',
    'verify.recordHint': 'Record at least 5 seconds, at most 15 seconds.',
    'verify.recordFaceHint':
        'Keep your face visible: no headwear, headphones or sunglasses.',
    'verify.stopHint': 'Tap again to stop (auto-stop at 15 s)',
    'verify.processing':
        'Processing your video. Please wait, this can take up to half '
        'a minute.',
    'verify.cameraError': 'Camera could not be initialized: {error}',
    'verify.challenge.base.speakNumber': 'Say the displayed number out loud.',
    'verify.challenge.base.makeGesture': 'Do the displayed gesture.',
    'verify.challenge.base.turnHead': 'Slowly turn your head.',
    'verify.challenge.base.smile': 'Smile briefly into the camera.',
    'verify.challenge.task': 'Your task:',
    'verify.challenge.gesture.tongue': 'Stick out your tongue',
    'verify.challenge.gesture.blink': 'Blink once',
    'verify.challenge.gesture.brows': 'Raise your eyebrows',
    'verify.challenge.direction.left_right': 'left and right',
    'verify.challenge.direction.right_left': 'right and left',
    'verify.challenge.action.smile': 'smile',
    // Chat details + call
    'chat.title': 'Chat',
    'chat.gone': 'This chat no longer exists.',
    'chat.imagePrepareFailed':
        'Image could not be prepared securely and was not sent.',
    'chat.callMicDenied': 'Microphone access denied.',
    'chat.callVoiceFailed': 'Voice packet could not be sent.',
    'chat.callStatusConnecting': 'Connecting…',
    'chat.callStatusRingingOut': 'Ringing…',
    'chat.callStatusRingingIn': 'Incoming call…',
    'chat.callStatusConnected': 'Connected',
    'chat.callStatusRecording': 'Recording… {s} s',
    'chat.callStatusDeclined': 'Call declined',
    'chat.callStatusEnded': 'Call ended',
    'chat.callStatusUnreachable': 'No direct connection possible',
    'chat.callPttHold': 'Press and hold to talk',
    'chat.callMuted': 'Muted',
    'chat.callUnmuted': 'Microphone',
    'chat.callE2eInfo':
        'Voice is end-to-end encrypted and runs directly peer to peer '
        '(push to talk).',
    'chat.callNetHint':
        'Note: Voice calls run directly between devices and are only '
        'reliable on WiFi. Calls should not be started on mobile '
        'networks.',
    'chat.e2eReady': 'End-to-end encrypted (Signal protocol via P2P)',
    'chat.e2eWaiting': 'E2E connection is being established.',
    'chat.connDiag': 'Tech: ICE {ice} - automatic retry in progress.',
    'chat.connError': 'Last error: {error}',
    // Privacy: TOTP confirmation
    'privacy.totpTitle': 'Confirm account',
    'privacy.totpLabel': 'TOTP code (authenticator app)',
    'privacy.totpConfirm': 'Confirm',
    // Reporting (users + images)
    'report.userTitle': 'Report user: {name}',
    'report.userTooltip': 'Report user',
    'report.sendDone': 'Report sent. Thank you for your help!',
    'report.imageTitle': 'Report image: {name}',
    'report.imageUnavailable': 'This image cannot be reported, unfortunately.',
    'report.sendReport': 'Send report',
    'report.analyzing': 'Analyzing image locally…',
    'report.noLocalModel':
        'Local check unavailable (model missing). The report uses the '
        'server-side fallback.',
    'report.failedTitle': 'Report failed',
    'report.aiResult': 'AI result',
    'report.forwardedTitle': 'Forwarded',
    'report.forwardedBody':
        'Your report was forwarded to our team for manual review - '
        'including image, your report and the AI result. Thank you for '
        'your help!',
    'common.retry': 'Try again',
    // 404 error page
    'error.notFoundTitle': 'Page not found',
    'error.notFoundBody':
        'This page does not (or no longer) exist. No problem, you will '
        'be on your way shortly.',
    'error.goHome': 'To home page',
    // Reporting: AI confirmation
    'report.aiConfirm':
        'Thanks! The AI also flags the image as inappropriate '
        '(score {score}%).',
    'report.aiEscalated':
        'Image, your report and the AI result were automatically sent '
        'to our team.',
    'report.aiNotNotified':
        'Note: The team could not be notified by email - your report '
        'is saved anyway.',
    'genderpref.all': 'All',
    'random.connectFailed': 'Connection to partner failed: {error}',
    'random.notLoggedIn': 'Not logged in - random chat unavailable.',
    'random.fallbackPartnerName': 'Random partner',
    'random.fallbackTitle': 'Random chat',
    'dm.photosNote':
        'You only see photos after passing the getting-to-know quiz '
        'following a spark. Until then, what someone says about '
        'themselves counts.',
    'admin.reportedUser': 'Reported user: {id}',
    'admin.reporter': 'Reporter: {id} (hashed)',
    'admin.messagesAttached': '{count} message(s) attached',
    'admin.resolved': 'Resolved',
    'admin.statusPending': 'pending',
    'admin.noDescription': '(no description)',
    'admin.attachments': 'Attachments: {count} · {time}',
    'admin.user': 'User: {id}',
    'admin.reviewFailed': 'Review failed: {error}',
    'admin.noVideoUrl': 'no video URL received',
    'admin.browserOpenFailed': 'Browser could not open URL',
    'admin.videoFailed': 'Video could not be loaded: {error}',
    'admin.watchVideo': 'Watch video',
    'admin.approve': 'Approve',
    'admin.rejectWithVideo': 'Reject (video will be deleted)',
    'admin.noVerifications': 'No pending verifications.',
    'admin.auditTitle': 'Spot checks: auto approvals',
    'admin.auditEmpty': 'No auto approvals to spot-check.',
    'admin.ageNoAi': 'Age: stated {stated} (no AI estimate)',
    'admin.ageAi': 'Age: stated {stated}, AI {est} (deviation {dev})',
    'admin.noModeration': 'No pending moderation.',
    'admin.approveTooltip': 'Approve',
    'admin.rejectTooltip': 'Reject',
    'admin.banUser': 'Ban user',
    'admin.banTarget': 'Email or user ID',
    'admin.banTargetHint': 'e.g. copied from the report email',
    'admin.banReason': 'Reason (required)',
    'admin.banReasonHint': 'Why is the user being banned?',
    'admin.required': 'Required',
    'admin.minChars': 'At least 3 characters',
    'admin.notifyUser': 'Notify user by email',
    'admin.notifySub': 'Contains the reason and how to request unban',
    'admin.banHint':
        'Note: With a user ID, the existing account is additionally '
        'banned immediately (sessions invalid). With only an email, '
        're-registration is blocked.',
    'admin.cancel': 'Cancel',
    'admin.banned': 'User banned.',
    'admin.ban': 'Ban',
    'admin.banFailed': 'Ban failed.',
    'admin.actionFailed': 'Action failed (status {status}).',
    'admin.unbanTitle': 'Unban?',
    'admin.unbanBody':
        '{email} can register and sign in again. The unban request '
        'should have been reviewed first.',
    'admin.unban': 'Unban',
    'admin.unbanned': '{email} was unbanned.',
    'admin.unbanFailed': 'Unban failed.',
    'admin.noBans': 'No bans.',
    'admin.bannedBy': '{time} · by {by}',
    'admin.decideFailed': 'Decision failed: {error}',
    'admin.noAppeals': 'No pending image appeals.',
    'admin.appealSubmitted': 'Submitted: {time}',
    'admin.appealFinding': 'Local finding: {label} ({score} %)',
    'ai.localBadge': 'On-device AI',
    'ai.cloudBadge': 'Cloud AI',
    'call.icebreakerTitle': 'Icebreaker questions',
    'call.icebreakerHint':
        'Browse the collection and ask the question out loud - '
        'to keep talking when it goes quiet.',
    'birthday.styleTitle': 'Birthday style',
    'birthday.pickHint': 'Choose how your profile looks on your birthday.',
    'birthday.style.classic': 'Classic',
    'birthday.style.midnight': 'Midnight',
    'birthday.style.sage': 'Sage',
    'birthday.style.rose': 'Rosé',
    'birthday.style.mono': 'Mono',
    'birthday.todayTitle': 'Happy birthday!',
    'chat.icebreakerSuggestTitle': 'Need a conversation starter?',
    'chat.icebreakerSuggestBody':
        'You have not exchanged messages yet. How about an '
        'icebreaker question for your counterpart?',
    'chat.icebreakerSuggestSend': 'Send question',
    'chat.icebreakerSuggestLater': 'Later',
    'admin.statusOpen': 'Open',
    'admin.statusApproved': 'Approved',
    'admin.statusRejected': 'Rejected',
    'admin.statusNotified': 'Acknowledged',
  },
};
