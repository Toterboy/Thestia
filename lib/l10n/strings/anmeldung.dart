// Die Texte des Themas 'anmeldung' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsAnmeldung = {
  'de': {
    'auth.ageConfirmRequired':
        'Bitte bestätige die Richtigkeit deines Geburtsdatums.',
    'auth.ageConfirmSub':
        'Falsche Altersangaben gefährden andere, besonders junge Nutzer, '
        'und führen zum dauerhaften Ausschluss.',
    'auth.ageConfirmTitle': 'Mein Geburtsdatum ist korrekt',
    'auth.birthDate': 'Geburtsdatum',
    'auth.birthDateHint': 'TT. MM. JJJJ',
    'auth.birthDateMissing': 'Bitte wähle dein Geburtsdatum.',
    'auth.birthDatePick': 'Bitte auswählen',
    'auth.captcha': 'Sicherheitscheck',
    'auth.captchaLogin':
        'Bitte schließe den Sicherheitscheck ab, um dich '
        'anzumelden.',

    'captcha.err.domainNotAuthorized':
        'Diese Adresse ist für den Sicherheitscheck nicht freigegeben. '
        'Der Sicherheitscheck läuft unter auth.thestia.de.',
    'auth.captchaRegister':
        'Bitte schließe den Sicherheitscheck ab, um '
        'dich zu registrieren.',
    'auth.email': 'Email',
    'auth.forgot': 'Passwort vergessen?',
    'auth.gender': 'Geschlecht',
    'auth.hidePassword': 'Passwort verbergen',
    'auth.keepLoggedIn': 'Angemeldet bleiben',
    'auth.keepLoggedInSub':
        'Automatisch eingeloggt bleiben, wenn du die App schließt (empfohlen).',
    'auth.liabilityNote':
        'Hinweis: Thestia prüft Angaben nicht lückenlos. Verlass dich nie '
        'allein auf Profilangaben, triff dich nur an öffentlichen Orten '
        'und melde Verdacht auf falsches Alter sofort.',
    'auth.lockedOut':
        'Zu viele fehlgeschlagene Anmeldeversuche. Bitte warte {minutes} '
        'Minute(n) und versuche es dann erneut.',
    'auth.lockedOut10':
        'Zu viele fehlgeschlagene Anmeldeversuche. Die Anmeldung ist für '
        '{minutes} Minuten gesperrt.',
    // Auth
    'auth.login': 'Einloggen',
    'auth.name': 'Name',
    'auth.passkey': 'Mit Passkey anmelden',
    'auth.passkeyFailed':
        'Passkey-Anmeldung fehlgeschlagen. Bitte versuche es mit '
        'E-Mail und Passwort.',
    'auth.password': 'Passwort',
    'auth.passwordConfirm': 'Neues Passwort wiederholen',
    'auth.passwordCurrent': 'Aktuelles Passwort',
    'auth.passwordHint': 'Mindestens 8 Zeichen',
    'auth.passwordHintStrong':
        'Mindestens 8 Zeichen, mit Groß- und '
        'Kleinbuchstaben, einer Zahl und einem Sonderzeichen',
    'auth.passwordNew': 'Neues Passwort',
    'auth.privacyConsent':
        'Mit der Registrierung akzeptierst du die Datenschutzerklärung: '
        'auch die Verarbeitung der Angaben, aus denen sich deine sexuelle '
        'Orientierung ergibt (Art. 9 DSGVO). Du kannst das jederzeit '
        'widerrufen.',
    'auth.privacyConsentLink': 'Datenschutzerklärung lesen',
    'auth.register': 'Registrieren',
    'auth.registerTitle': 'Konto erstellen',
    'auth.showPassword': 'Passwort anzeigen',
    'auth.toLogin': 'Schon ein Konto? Einloggen',
    'auth.toRegister': 'Noch kein Konto? Registrieren',
    'auth.welcomeBack': 'Willkommen zurück',
    'captcha.err.badSitekey':
        'Der Sicherheitscheck ist serverseitig nicht korrekt konfiguriert. '
        'Bitte melde es dem Support.',
    'captcha.err.blocked':
        'Der Sicherheitscheck wird blockiert. Bitte erlaube '
        'challenges.cloudflare.com und versuche es erneut.',
    'captcha.err.botDetected':
        'Der Sicherheitscheck hat die Anfrage als Bot-Verhalten '
        'eingestuft. Bitte versuche es gleich noch einmal.',
    'captcha.err.clock':
        'Die Uhrzeit des Geräts stimmt nicht. Bitte stelle automatische '
        'Zeit ein und versuche es erneut.',
    'captcha.err.timeout':
        'Der Sicherheitscheck hat zu lange gebraucht. Bitte versuche es '
        'noch einmal.',
    'captcha.retry': 'Erneut versuchen',
    'email.addressChangeFailed':
        'Die Adresse konnte nicht geändert werden: {error}',
    'email.addressChanged':
        'Adresse geändert. Eine neue Bestätigungsmail ist unterwegs.',
    'email.addressHint': 'An diese Adresse ging die Bestätigungsmail.',
    'email.addressLabel': 'E-Mail-Adresse',
    'email.body':
        'Wir haben dir eine Bestätigungsemail gesendet. Bitte klicke auf '
        'den Link in der Email, um deinen Account zu aktivieren. Danach '
        'geht es automatisch weiter.',
    'email.cancel': 'Registrierung abbrechen',
    'email.cancelBody':
        'Dein noch unbestätigter Account wird dabei in Supabase '
        'gelöscht. Bereits gemachte Angaben gehen verloren.',
    'email.cancelConfirm': 'Ja, Konto löschen',
    'email.cancelExpired':
        'Anmeldedaten abgelaufen - melde dich einfach erneut an, die '
        'Bestätigung wird dann erneut gesendet.',
    'email.cancelKeep': 'Doch fortfahren',
    'email.cancelTitle': 'Registrierung abbrechen?',
    'email.captchaNeeded':
        'Bitte bestätige das CAPTCHA - ohne geht es nicht weiter.',
    'email.changeAddress': 'Adresse ändern',
    'email.changeAddressBody':
        'Ist die Adresse falsch? Ändere sie hier. Das Konto wird '
        'gelöscht und mit der neuen Adresse neu angelegt - du '
        'bekommst eine neue Bestätigungsmail.',
    'email.changeAddressTitle': 'E-Mail-Adresse ändern',
    'email.confirmed': 'Email bestätigt!',
    'email.continueBtn': 'Ich habe die Mail bestätigt: Weiter',
    'email.cooldown': 'Erneut senden in {s}s',
    'email.deleteFailed': 'Löschen fehlgeschlagen: {error}',
    'email.deleted': 'Registrierung abgebrochen, Konto gelöscht.',
    'email.demoContinue': 'In der Demo kannst du direkt fortfahren.',
    'email.dnsHint':
        'Kommt der Link in der Email nicht durch? Das kann an aktiven DNS '
        'Filtern oder VPNs (z. B. DNS Forge) liegen, die Tracking Links '
        'blockieren. Deaktiviere den Filter vorübergehend und klicke den '
        'Link erneut. Nach der Bestätigung kannst du ihn wieder aktivieren.',
    'email.heading': 'Bestätige deine Emailadresse',
    'email.logout': 'Abmelden',
    'email.newAddress': 'Neue E-Mail-Adresse',
    'email.rateLimited': 'Zu viele Anfragen. Bitte warte einen Moment.',
    'email.reportIssue': 'Problem melden',
    'email.resend': 'Bestätigungsmail erneut senden',
    'email.resent':
        'Bestätigungsemail wurde erneut gesendet. Bitte prüfe auch '
        'deinen Spamordner.',
    'email.sending': 'Wird gesendet...',
    'email.sent': 'Email gesendet',
    'email.title': 'Email bestätigen',
    'email.waiting': 'Wir warten auf die Bestätigung...',
    'forgot.body':
        'Gib deine Emailadresse ein. Wir senden dir einen Link, um dein '
        'Passwort zurückzusetzen.',
    'forgot.email': 'Email',
    'forgot.heading': 'Passwort zurücksetzen',
    'forgot.sendLink': 'Link senden',
    'forgot.sending': 'Sende …',
    'forgot.sentBody':
        'Wenn ein Konto mit dieser Email existiert, haben wir einen Link '
        'zum Zurücksetzen gesendet.',
    'forgot.sentBox':
        'Falls ein Konto mit dieser Email existiert, wurde ein Link '
        'gesendet.',
    'forgot.title': 'Passwort vergessen',
    'forgot.toLogin': 'Zurück zum Login',
    'mfa.activeBody':
        'Dein Konto ist mit einer Authenticator-App geschützt. Bei der '
        'Anmeldung wird zusätzlich zum Passwort der aktuelle Code abgefragt.',
    'mfa.activeTitle': '2FA ist aktiviert',
    'mfa.body': 'Gib den Code aus deiner Authenticator-App ein',
    'mfa.confirmBody':
        'Gib den aktuellen 6-stelligen Code aus deiner '
        'Authenticator-App ein, um die Einrichtung zu bestätigen:',
    'mfa.confirmStep': '2. Code eingeben',
    'mfa.copied': 'Schlüssel kopiert. Wird in 30 s automatisch gelöscht.',
    'mfa.doneBody':
        'Ab jetzt wirst du bei jedem Login nach dem Code aus deiner '
        'Authenticator-App gefragt.',
    'mfa.doneTitle': 'Zwei-Faktor-Schutz aktiv!',
    'mfa.introBody':
        'Mit einer Authenticator-App (z. B. Google Authenticator, Aegis '
        'oder 2FAS) erstellst du bei jedem Login einen einmaligen Code. '
        'Nur mit diesem Code kann sich jemand in dein Konto einloggen, '
        'auch wenn dein Passwort gestohlen wurde.',
    'mfa.introSkip':
        'Du kannst diesen Schritt überspringen und die Einrichtung '
        'jederzeit nachholen.',
    'mfa.introTitle': 'Schütze dein Konto mit einem zweiten Faktor',
    'mfa.manualKey':
        'Kein Scan möglich? Trage diesen Schlüssel manuell ein '
        '(antippen zum Kopieren):',
    'mfa.paste': 'Einfügen',
    'mfa.scanBody':
        'Öffne deine Authenticator-App (z. B. Google Authenticator, '
        'Aegis oder 2FAS) und füge den Eintrag per QR-Scan hinzu.',
    'mfa.scanStep': '1. QR-Code scannen',
    'mfa.setupBackQr': 'Zurück zum QR-Code',
    'mfa.setupLater': 'Später erinnern',
    'mfa.setupNext': 'Weiter: Code eingeben',
    'mfa.setupNextHint':
        'Danach gibst du den 6-stelligen Code aus deiner '
        'Authenticator-App einmal ein, um die Einrichtung zu bestätigen.',
    'mfa.setupScan': 'Mit Authenticator-App einrichten',
    'mfa.setupTitle': 'Konto absichern',
    'mfa.title': 'Sicherheitscode',
    'onb.next': 'Weiter',
    'passkey.deleteBody':
        '"{name}" wird von deinem Konto entfernt. Die Anmeldung damit '
        'ist danach nicht mehr möglich. Der Passkey bleibt ggf. auf dem '
        'Gerät gespeichert.',
    'passkey.err.assetLinks':
        'Die App konnte sich nicht mit auth.thestia.de verkn\u00fcpfen '
        '(Digital Asset Links). Die Verkn\u00fcpfung pr\u00fcft den '
        'Fingerabdruck des Signaturzertifikats der installierten App. '
        'Bei einer Neuinstallation aus dem Play Store ist das ein '
        'anderes Zertifikat als bei einem lokalen Build - dann passt '
        'der Fingerabdruck in der Datei noch nicht.',
    'passkey.err.cancelledLogin': 'Passkey-Anmeldung abgebrochen.',
    'passkey.err.captcha':
        'Der Sicherheitscheck fehlte oder ist abgelaufen. '
        'Bitte versuche es erneut.',
    'passkey.err.invalidState':
        'Auf diesem Gerät existiert bereits ein Passkey für dieses Konto.',
    'passkey.err.noCredentialLogin':
        'Kein Passkey für dieses Konto gefunden. Richte zuerst einen '
        'unter Einstellungen ein.',
    'passkey.err.noCredentialRegister':
        'Kein Passkey-Speicher verfügbar. Prüfe Sperrbildschirm und '
        'Google Play Services.',
    'passkey.err.notAllowedLogin':
        'Passkey-Anmeldung wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
    'passkey.err.notAllowedRegister':
        'Passkey-Einrichtung wurde abgebrochen oder ist abgelaufen. '
        'Vergewissere dich, dass dein Gerät einen Sperrbildschirm '
        '(PIN, Muster oder Biometrie) hat, und versuche es erneut.',
    'passkey.err.pluginMissing':
        'Die Passkey-Funktion ist in dieser Version der App nicht '
        'verfügbar. Bitte melde es dem Support - es ist ein Fehler im '
        'Build, nicht auf deinem Gerät.',
    'passkey.err.rpIdMismatch':
        'Die Server-Konfiguration passt nicht zur App (RP-ID/Hostname). '
        'Bitte melde es dem Support.',
    'passkey.err.securityError':
        'Die App konnte ihre Domain-Zugehörigkeit nicht nachweisen '
        '(Passkey-Domain-Verknüpfung). Prüfe, ob die neueste App-Version '
        'installiert ist, und melde es dem Support, falls es bleibt.',
    'passkey.err.serverRejected':
        'Der Server hat die Passkey-Anfrage abgelehnt. Bitte prüfe in '
        'den Supabase-Einstellungen, ob "Passkeys" aktiviert ist und die '
        'RP-ID auf auth.thestia.de gesetzt ist.{reason}',
    'passkey.err.syncAccount':
        'Der Passkey konnte nicht verschlüsselt gespeichert werden. '
        'Stelle sicher, dass du auf dem Gerät mit einem Google-Konto '
        'angemeldet bist und die Google Play Services aktuell sind.',
    'passkey.err.timeoutLogin':
        'Zeitüberschreitung bei der Passkey-Anmeldung. Bitte versuche es '
        'gleichzeitig am Bildschirm erneut.',
    'passkey.err.timeoutRegister':
        'Zeitüberschreitung bei der Passkey-Einrichtung. Bitte versuche '
        'es gleichzeitig am Bildschirm erneut.',
    'passkey.err.unknownLogin':
        'Passkey-Anmeldung fehlgeschlagen. Bitte versuche es später '
        'erneut.',
    // Passkey-Dialog in den Einstellungen (Server-Bestätigung)
    'settings.passkeyExistsTitle': 'Passkey existiert bereits',
    'passkey.err.unknownRegister':
        'Passkey-Einrichtung fehlgeschlagen. Bitte versuche es später '
        'erneut.',
    'passkey.err.verificationFailed':
        'Der Server konnte den Passkey nicht bestätigen. Wahrscheinlich '
        'fehlt der Ursprung (apk-key-hash) der installierten App in der '
        'Passkey-Konfiguration des Servers - siehe '
        'docs/technik/PASSKEYS_SERVER_SETUP.md. Alternativ: alten Passkey unter '
        '"Passkeys verwalten" löschen und erneut anlegen.',
    'passkey.loadError':
        'Passkeys konnten nicht geladen werden. Bitte später erneut versuchen.',
    'passkey.managerHint':
        '{count} registriert - tippe zum Umbenennen, Papierkorb zum '
        'Entfernen',
    // Passkey-Fallbacks im Login (keine AppException)
    'auth.passkeyCancelled': 'Passkey-Anmeldung abgebrochen.',
    'passkey.managerSub': 'Registrierte Passkeys auf deinem Konto',
    'passkey.renameFailed': 'Umbenennen fehlgeschlagen.',
    'passkey.renameHint': 'z. B. Pixel 8',
    'passkey.renameLabel': 'Anzeigename',
    'passkey.renameTitle': 'Passkey umbenennen',
    'passkey.stepUpHint':
        'Zum Anzeigen der Passkeys ist eine 2FA-Bestätigung nötig.',
    'reset.body':
        'Wähle ein neues Passwort für dein Konto. Es muss mindestens 8 '
        'Zeichen lang sein und Buchstaben und Zahlen enthalten.',
    'reset.doneBody':
        'Dein neues Passwort wurde gespeichert. Aus Sicherheitsgründen '
        'wurdest du auf allen Geräten abgemeldet. Bitte melde dich neu an.',
    'reset.doneTitle': 'Passwort geändert',
    'reset.heading': 'Neues Passwort festlegen',
    'reset.mismatch': 'Die Passwörter stimmen nicht überein.',
    'reset.newPassword': 'Neues Passwort',
    'reset.repeat': 'Passwort wiederholen',
    'reset.repeatMissing': 'Bitte wiederhole das Passwort',
    'reset.save': 'Passwort speichern',
    'reset.title': 'Neues Passwort',
    'reset.toLogin': 'Zum Login',
    'signup.body':
        'Schön, dass du da bist. Gleich geht es mit deiner Einrichtung '
        'los - Schritt für Schritt, alles kann später geändert werden.',
    'signup.start': 'Jetzt einrichten',
    'signup.title': 'Willkommen bei Thestia!',
    'unban.backToLogin': 'Zurück zur Anmeldung',
    'unban.body':
        'Diese E-Mail-Adresse ist auf der Plattform gesperrt. Wenn du '
        'glaubst, dass ein Fehler vorliegt, sende einen '
        'Entsperrungsantrag. Wir prüfen den Fall.',
    'unban.doneBody':
        'Dein Entsperrungsantrag wurde an den Support übermittelt. Wir '
        'prüfen den Fall und melden uns per E-Mail.',
    'unban.doneTitle': 'Antrag gesendet',
    'unban.email': 'E-Mail-Adresse',
    'unban.emailInvalid': 'Bitte gib eine gültige E-Mail-Adresse ein.',
    'unban.emailMissing': 'Bitte gib deine E-Mail-Adresse ein.',
    'unban.heading': 'Konto gesperrt?',
    'unban.reason': 'Begründung',
    'unban.reasonHint':
        'Erkläre kurz, warum dein Konto entsperrt werden sollte '
        '(mindestens 20 Zeichen).',
    'unban.reasonShort':
        'Bitte gib eine Begründung mit mindestens 20 Zeichen an.',
    'unban.send': 'Antrag senden',
    'unban.title': 'Entsperrungsantrag',
    'welcome.b1':
        'Hier lernst du Menschen wirklich kennen, bevor du ihr Foto '
        'siehst: am Anfang zählt die Persönlichkeit, nicht das Aussehen. '
        'Und weil wir dich zurück ins echte Leben bringen wollen, gibt es '
        'hier Begegnungen, die wirklich stattfinden - die Dating Hour am '
        'Samstag, Transit Spark im Zug oder im Café, das Zufallschat.',
    'welcome.b2':
        'Chatte zuerst blind und lerne die Person hinter dem Profil '
        'kennen. Erst wenn ihr euch beide gemocht habt, werden die Fotos '
        'freigeschaltet.',
    'welcome.b3':
        'Alle Nachrichten und Anrufe sind Ende zu Ende verschlüsselt '
        '(E2E). Niemand außer dir und deinem Gegenüber kann mitlesen, '
        'auch wir nicht. Deine Daten gehören dir.\n\nHochgeladene Fotos '
        'werden automatisch auf unangemessene Inhalte geprüft. Diese '
        'Prüfung erfolgt DSGVO konform und ohne dauerhafte Speicherung '
        'deiner Bilder bei Drittanbietern.',
    'welcome.start': 'Los geht es',
    'welcome.t2': 'Blind Chat und Match',
    'welcome.t3': 'Deine Privatsphäre',
  },
  'en': {
    'auth.ageConfirmRequired':
        'Please confirm that your date of birth is correct.',
    'auth.ageConfirmSub':
        'False age information endangers others, especially young users, '
        'and leads to a permanent ban.',
    'auth.ageConfirmTitle': 'My date of birth is correct',
    'auth.birthDate': 'Date of birth',
    'auth.birthDateHint': 'DD MM YYYY',
    'auth.birthDateMissing': 'Please choose your date of birth.',
    'auth.birthDatePick': 'Please select',
    'auth.captcha': 'Security check',
    'auth.captchaLogin': 'Please complete the security check to log in.',

    'captcha.err.domainNotAuthorized':
        'This address is not allowed for the security check. The security '
        'check runs on auth.thestia.de.',
    'auth.captchaRegister': 'Please complete the security check to sign up.',
    'auth.email': 'Email',
    'auth.forgot': 'Forgot password?',
    'auth.gender': 'Gender',
    'auth.hidePassword': 'Hide password',
    'auth.keepLoggedIn': 'Stay logged in',
    'auth.keepLoggedInSub':
        'Stay automatically logged in when you close the app (recommended).',
    'auth.liabilityNote':
        'Note: Thestia cannot verify every detail. Never rely on profile '
        'information alone, only meet in public places and report '
        'suspected false age immediately.',
    'auth.lockedOut':
        'Too many failed sign-in attempts. Please wait {minutes} minute(s) '
        'and try again.',
    'auth.lockedOut10':
        'Too many failed sign-in attempts. Sign-in is locked for {minutes} '
        'minutes.',
    'auth.login': 'Log in',
    'auth.name': 'Name',
    'auth.passkey': 'Sign in with Passkey',
    'auth.passkeyFailed':
        'Passkey sign-in failed. Please try with email and password.',
    'auth.password': 'Password',
    'auth.passwordConfirm': 'Repeat new password',
    'auth.passwordCurrent': 'Current password',
    'auth.passwordHint': 'At least 8 characters',
    'auth.passwordHintStrong':
        'At least 8 characters, with upper and lower '
        'case letters, a number and a special character',
    'auth.passwordNew': 'New password',
    'auth.privacyConsent':
        'By registering you accept the privacy policy - including the '
        'processing of the information from which your sexual orientation '
        'can be inferred (Art. 9 GDPR). You can withdraw your consent at '
        'any time.',
    'auth.privacyConsentLink': 'Read the privacy policy',
    'auth.register': 'Sign up',
    'auth.registerTitle': 'Create account',
    'auth.showPassword': 'Show password',
    'auth.toLogin': 'Already have an account? Log in',
    'auth.toRegister': 'No account yet? Sign up',
    'auth.welcomeBack': 'Welcome back',
    'captcha.err.badSitekey':
        'The security check is not configured correctly on the server. '
        'Please report it to support.',
    'captcha.err.blocked':
        'The security check is being blocked. Please allow '
        'challenges.cloudflare.com and try again.',
    'captcha.err.botDetected':
        'The security check classified the request as bot behaviour. '
        'Please try again in a moment.',
    'captcha.err.clock':
        'The device clock is wrong. Please enable automatic time and try '
        'again.',
    'captcha.err.timeout':
        'The security check took too long. Please try again.',
    'captcha.retry': 'Try again',
    'email.addressChangeFailed': 'The address could not be changed: {error}',
    'email.addressChanged':
        'Address changed. A new confirmation email is on its way.',
    'email.addressHint': 'The confirmation email went to this address.',
    'email.addressLabel': 'Email address',
    'email.body':
        'We sent you a confirmation email. Please click the link in the '
        'email to activate your account. Afterwards it continues '
        'automatically.',
    'email.cancel': 'Cancel registration',
    'email.cancelBody':
        'Your not yet confirmed account will be deleted in Supabase. '
        'Any details already entered will be lost.',
    'email.cancelConfirm': 'Yes, delete account',
    'email.cancelExpired':
        'Credentials expired - just sign up again, the confirmation '
        'will be re-sent.',
    'email.cancelKeep': 'Keep going',
    'email.cancelTitle': 'Cancel registration?',
    'email.captchaNeeded':
        'Please confirm the CAPTCHA - without it we cannot continue.',
    'email.changeAddress': 'Change address',
    'email.changeAddressBody':
        'Wrong address? Change it here. The account is deleted and '
        'recreated with the new address - you will get a new '
        'confirmation email.',
    'email.changeAddressTitle': 'Change email address',
    'email.confirmed': 'Email confirmed!',
    'email.continueBtn': 'I confirmed the email: Continue',
    'email.cooldown': 'Resend in {s}s',
    'email.deleteFailed': 'Delete failed: {error}',
    'email.deleted': 'Registration cancelled, account deleted.',
    'email.demoContinue': 'In the demo you can continue directly.',
    'email.dnsHint':
        'Email link not coming through? This can be caused by active DNS '
        'filters or VPNs (e.g. DNS Forge) blocking tracking links. '
        'Temporarily disable the filter and click the link again. You can '
        're-enable it after confirmation.',
    'email.heading': 'Confirm your email address',
    'email.logout': 'Log out',
    'email.newAddress': 'New email address',
    'email.rateLimited': 'Too many requests. Please wait a moment.',
    'email.reportIssue': 'Report issue',
    'email.resend': 'Resend confirmation email',
    'email.resent':
        'Confirmation email has been resent. Please also check your '
        'spam folder.',
    'email.sending': 'Sending...',
    'email.sent': 'Email sent',
    'email.title': 'Confirm email',
    'email.waiting': 'Waiting for confirmation...',
    'forgot.body':
        'Enter your email address. We will send you a link to reset your '
        'password.',
    'forgot.email': 'Email',
    'forgot.heading': 'Reset password',
    'forgot.sendLink': 'Send link',
    'forgot.sending': 'Sending…',
    'forgot.sentBody':
        'If an account with this email exists, we sent a reset link.',
    'forgot.sentBox': 'If an account with this email exists, a link was sent.',
    'forgot.title': 'Forgot password',
    'forgot.toLogin': 'Back to login',
    'mfa.activeBody':
        'Your account is protected with an authenticator app. When '
        'logging in, the current code is requested in addition to your '
        'password.',
    'mfa.activeTitle': '2FA is enabled',
    'mfa.body': 'Enter the code from your authenticator app',
    'mfa.confirmBody':
        'Enter the current 6-digit code from your authenticator app to '
        'confirm setup:',
    'mfa.confirmStep': '2. Enter code',
    'mfa.copied': 'Key copied. Will be deleted automatically in 30 s.',
    'mfa.doneBody':
        'From now on you will be asked for the code from your '
        'authenticator app at every login.',
    'mfa.doneTitle': 'Two-factor protection active!',
    'mfa.introBody':
        'With an authenticator app (e.g. Google Authenticator, Aegis or '
        '2FAS) you create a one-time code at every login. Only with this '
        'code can someone log into your account, even if your password '
        'was stolen.',
    'mfa.introSkip': 'You can skip this step and complete setup anytime later.',
    'mfa.introTitle': 'Protect your account with a second factor',
    'mfa.manualKey': 'No scan possible? Enter this key manually (tap to copy):',
    'mfa.paste': 'Paste',
    'mfa.scanBody':
        'Open your authenticator app (e.g. Google Authenticator, Aegis '
        'or 2FAS) and add the entry via QR scan.',
    'mfa.scanStep': '1. Scan QR code',
    'mfa.setupBackQr': 'Back to QR code',
    'mfa.setupLater': 'Remind later',
    'mfa.setupNext': 'Next: enter code',
    'mfa.setupNextHint':
        'Afterwards, enter the 6-digit code from your authenticator '
        'app once to confirm setup.',
    'mfa.setupScan': 'Set up with authenticator app',
    'mfa.setupTitle': 'Secure account',
    'mfa.title': 'Security code',
    'onb.next': 'Next',
    'passkey.deleteBody':
        '"{name}" will be removed from your account. You will no longer '
        'be able to sign in with it. The passkey may remain stored on '
        'the device.',
    'passkey.err.assetLinks':
        'The app could not associate itself with auth.thestia.de '
        '(Digital Asset Links). The association checks the fingerprint '
        'of the installed app\u2019s signing certificate. A fresh install '
        'from the Play Store carries a different certificate than a '
        'local build - the fingerprint in the file does not match yet.',
    'passkey.err.cancelledLogin': 'Passkey sign-in cancelled.',
    'passkey.err.captcha':
        'The security check was missing or expired. Please try again.',
    'passkey.err.invalidState':
        'A passkey for this account already exists on this device.',
    'passkey.err.noCredentialLogin':
        'No passkey found for this account. Set one up under Settings '
        'first.',
    'passkey.err.noCredentialRegister':
        'No passkey storage available. Check screen lock and Google Play '
        'Services.',
    'passkey.err.notAllowedLogin':
        'The passkey sign-in was cancelled or expired. Make sure your '
        'device has a screen lock (PIN, pattern or biometrics) and try '
        'again.',
    'passkey.err.notAllowedRegister':
        'The passkey setup was cancelled or expired. Make sure your '
        'device has a screen lock (PIN, pattern or biometrics) and try '
        'again.',
    'passkey.err.pluginMissing':
        'The passkey feature is not available in this version of the app. '
        'Please report it to support - it is a build error, not a problem '
        'on your device.',
    'passkey.err.rpIdMismatch':
        'The server configuration does not match the app (RP ID / '
        'hostname). Please report it to support.',
    'passkey.err.securityError':
        'The app could not prove its domain association '
        '(passkey domain link). Check whether the latest app version is '
        'installed, and report it to support if it persists.',
    'passkey.err.serverRejected':
        'The server rejected the passkey request. Please check in the '
        'Supabase settings whether "Passkeys" is enabled and the RP ID '
        'is set to auth.thestia.de.{reason}',
    'passkey.err.syncAccount':
        'The passkey could not be stored encrypted. Make sure you are '
        'signed in with a Google account on the device and that Google '
        'Play Services are up to date.',
    'passkey.err.timeoutLogin':
        'Passkey sign-in timed out. Please try again while the dialog is '
        'visible on screen.',
    'passkey.err.timeoutRegister':
        'Passkey setup timed out. Please try again while the dialog is '
        'visible on screen.',
    'passkey.err.unknownLogin':
        'Passkey sign-in failed. Please try again later.',
    // Passkey dialog in settings (server confirmation)
    'settings.passkeyExistsTitle': 'Passkey already exists',
    'passkey.err.unknownRegister':
        'Passkey setup failed. Please try again later.',
    'passkey.err.verificationFailed':
        'The server could not confirm the passkey. Most likely the '
        'origin (apk-key-hash) of the installed app is missing in the '
        'server passkey configuration - see '
        'docs/technik/PASSKEYS_SERVER_SETUP.md. Alternatively delete the old '
        'passkey under "Manage passkeys" and create it again.',
    'passkey.loadError':
        'Passkeys could not be loaded. Please try again later.',
    'passkey.managerHint':
        '{count} registered - tap to rename, trash icon to remove',
    // Passkey fallbacks on the login screen (not an AppException)
    'auth.passkeyCancelled': 'Passkey sign-in cancelled.',
    'passkey.managerSub': 'Passkeys registered on your account',
    'passkey.renameFailed': 'Renaming failed.',
    'passkey.renameHint': 'e.g. Pixel 8',
    'passkey.renameLabel': 'Display name',
    'passkey.renameTitle': 'Rename passkey',
    'passkey.stepUpHint': 'Showing your passkeys requires a 2FA confirmation.',
    'reset.body':
        'Choose a new password for your account. It must be at least 8 '
        'characters long and contain letters and numbers.',
    'reset.doneBody':
        'Your new password has been saved. For security reasons you were '
        'logged out on all devices. Please log in again.',
    'reset.doneTitle': 'Password changed',
    'reset.heading': 'Set new password',
    'reset.mismatch': 'Passwords do not match.',
    'reset.newPassword': 'New password',
    'reset.repeat': 'Repeat password',
    'reset.repeatMissing': 'Please repeat the password',
    'reset.save': 'Save password',
    'reset.title': 'New password',
    'reset.toLogin': 'To login',
    'signup.body':
        'Glad you are here. Your setup starts right away - step by step, '
        'everything can be changed later.',
    'signup.start': 'Start setup',
    'signup.title': 'Welcome to Thestia!',
    'unban.backToLogin': 'Back to login',
    'unban.body':
        'This email address is banned on the platform. If you believe '
        'this is a mistake, send an unban request. We will review the '
        'case.',
    'unban.doneBody':
        'Your unban request was submitted to support. We will review the '
        'case and contact you by email.',
    'unban.doneTitle': 'Request sent',
    'unban.email': 'Email address',
    'unban.emailInvalid': 'Please enter a valid email address.',
    'unban.emailMissing': 'Please enter your email address.',
    'unban.heading': 'Account banned?',
    'unban.reason': 'Reason',
    'unban.reasonHint':
        'Briefly explain why your account should be unbanned '
        '(at least 20 characters).',
    'unban.reasonShort': 'Please provide a reason with at least 20 characters.',
    'unban.send': 'Send request',
    'unban.title': 'Unban request',
    'welcome.b1':
        'Here you really get to know people before you see their photo: at '
        'the beginning, personality counts, not looks. And because we want '
        'to bring you back into real life, there are encounters here that '
        'really happen - the Dating Hour on Saturday, Transit Spark on a '
        'train or in a cafe, the random chat.',
    'welcome.b2':
        'First chat blind and get to know the person behind the profile. '
        'Photos are only unlocked once you both liked each other.',
    'welcome.b3':
        'All messages and calls are end-to-end encrypted (E2E). Nobody '
        'except you and your counterpart can read along, not even us. '
        'Your data belongs to you.\n\nUploaded photos are automatically '
        'checked for inappropriate content. This check is GDPR compliant '
        'and does not permanently store your images with third parties.',
    'welcome.start': 'Let us go',
    'welcome.t1': 'Dating that brings you back into real life.',
    'welcome.t2': 'Blind Chat and Match',
    'welcome.t3': 'Your privacy',
  },
};
