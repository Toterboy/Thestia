// Die Texte des Themas 'grundlagen' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsGrundlagen = {
  'de': {
    'ai.cloudBadge': 'Cloud-KI',
    'ai.localBadge': 'On-Device-KI',
    'appearance.dark': 'Dunkel',
    'appearance.system': 'System',
    'appearanceDesc.dark': 'Immer dunkle Oberfläche, schon am Morgen.',
    'appearanceDesc.light': 'Immer helle Oberfläche, auch am Abend.',
    'appearanceDesc.system':
        'Folgt deinem Gerät: hell am Tag, dunkel bei Dunkelmodus.',
    'common.back': 'Zurück',
    'common.cancel': 'Abbrechen',
    'common.check': 'Prüfen',
    'common.close': 'Schließen',
    // Quiz "Wie gut kenn ich mein Match"
    'quiz.title': 'Kennenlern-Quiz',
    'common.confirm': 'Bestätigen',
    'common.continue': 'Weiter',
    'common.copy': 'Kopieren',
    // Einstellungen: Backup + Passkeys
    'settings.backupPw': 'Passwort (min. 8 Zeichen)',
    'common.discard': 'Verwerfen',
    'common.done': 'Fertig',
    'common.errorOccurred': 'Es ist ein Fehler aufgetreten:',
    'common.errorWith': 'Fehler: {error}',
    'common.hint': 'Hinweis',
    'common.later': 'Später',
    'common.loading': 'Lädt…',
    'common.new': 'NEU',
    'common.ok': 'OK',
    'common.refresh': 'Aktualisieren',
    'common.retry': 'Erneut versuchen',
    // 404-Fehlerseite
    'error.notFoundTitle': 'Seite nicht gefunden',
    'common.save': 'Speichern',
    'common.skip': 'Überspringen',
    'common.unknownError': 'Unbekannter Fehler',
    'common.whatHappened': 'Was ist passiert?',
    'common.years': 'Jahre',
    'distance.bucketOver': 'über {km} km',
    'distance.bucketRange': '{from} bis {to} km',
    'distance.bucketUnder': 'unter {km} km',
    'distance.bucketUnknown': 'Entfernung unbekannt',
    'error.alreadyRegistered':
        'Diese Emailadresse ist bereits registriert. Bitte melde dich '
        'direkt an oder setze dein Passwort zurück.',
    'error.captchaRejected':
        'Der Sicherheitscheck wurde vom Server '
        'abgelehnt. Bitte versuche es erneut.',
    // eigener Fall für den 20-Sekunden-Timeout aus login_screen.dart:
    // er sagt "der Server ist nicht erreichbar", nicht "irgendetwas ist
    // schiefgelaufen". Ohne diesen Zweig landet der Timeout in
    // error.generic und ist von einem CAPTCHA-Fehler nicht zu unterscheiden.
    'error.serverUnreachable':
        'Der Server hat nicht geantwortet. Prüfe deine Internetverbindung '
        'und versuche es erneut.',
    'error.generic': 'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
    // Admin-Bereich (nur für Moderation sichtbar)
    'admin.deniedTitle': 'Zugriff verweigert',
    'error.goHome': 'Zur Startseite',
    // Melden: KI-Bestätigung
    'report.aiConfirm':
        'Danke! Die KI stuft das Bild ebenfalls als unangemessen ein '
        '(Score {score}%).',
    'error.loginFailed':
        'Anmeldung fehlgeschlagen. Bitte versuche es '
        'erneut.',
    'error.notConfirmed': 'Bitte bestätige zuerst deine Emailadresse.',
    'error.notFoundBody':
        'Diese Seite existiert nicht (mehr). Kein Problem, du kommst '
        'gleich weiter.',
    'error.rateLimited':
        'Zu viele Anfragen in kurzer Zeit. Bitte warte '
        'einen Moment und versuche es erneut.',
    'error.signupFailed':
        'Registrierung auf dem Server fehlgeschlagen. '
        'Bitte versuche es später erneut.',
    'error.weakPassword':
        'Das Passwort ist zu schwach. Bitte wähle ein '
        'längeres Passwort mit Groß-/Kleinbuchstaben, Zahlen und '
        'Sonderzeichen.',
    'friends.badge': 'Freundschaft',
    'friends.toggleHint':
        'Diese Verbindung ist eine Freundschaft - kein romantischer '
        'Funke. Ihr könnt es jederzeit umschalten.',
    'gender.diverse': 'Divers',
    'gender.female': 'Weiblich',
    'gender.femaleTrans': 'Weiblich (M to F)',
    'gender.male': 'Männlich',
    'gender.maleTrans': 'Männlich (F to M)',
    'gender.other': 'Eigenes / Anderes',
    'genderpref.all': 'Alle',
    'keyboard.backspace': 'Löschen',
    'keyboard.emoji': 'Emoji',
    'keyboard.enter': 'Enter',
    'keyboard.hide': 'Tastatur ausblenden',
    'keyboard.paste': 'Einfügen',

    'chat.block': 'Nutzer blockieren',
    'keyboard.shift': 'Groß- und Kleinschreibung',
    'keyboard.space': 'Leertaste',
    'keyboard.symbols': 'Zahlen und Zeichen',
    'language.english': 'Englisch',
    // Navigation
    'nav.home': 'Aktuelles',
    'language.german': 'Deutsch',
    'location.disclosureAccept': 'Standort freigeben',
    'location.disclosureBody':
        'Für die Umkreis-Anzeige und die Altersprüfung braucht Thestia '
        'deinen ungefähren Standort. Er wird nur einmalig abgefragt, '
        'nicht an den Server weitergegeben und nach der Prüfung '
        'gelöscht. Auf älteren Android-Versionen ist er außerdem '
        'nötig, damit das Transit-Radar andere Geräte in der Nähe '
        'erkennen kann.',
    'music.dislikedTitle': 'Diese Genres mag ich nicht (freiwillig)',
    'music.exclude': 'Genre ausschließen…',
    'music.excludeHint':
        'Dieses Genre beeinflusst dein Matching negativ - du siehst '
        'weniger Personen mit diesem Geschmack.',
    'music.excludeNoMatch': 'Kein Genre gefunden.',
    'music.excludeSearch': 'Genre suchen …',
    'music.excludeTitle': 'Genre ausschließen',
    'music.genre.klassik': 'Klassik',
    'music.likedTitle': 'Diese Genres mag ich',
    'nav.discover': 'Entdecken',
    'nav.interests': 'Interessen',
    'nav.profile': 'Profil',
    // Settings (Kern)
    'settings.title': 'Einstellungen',
    'nav.unsavedBody':
        'Deine Profil-Änderungen wurden noch nicht gespeichert. Was '
        'möchtest du tun?',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email oder Passwort ist falsch.',
    'nav.unsavedTitle': 'Ungespeicherte Änderungen',
    'startup.failedBody':
        'Bitte schließe die App komplett und versuche es erneut.',
    'startupFail.continue': 'Trotzdem fortfahren',
    'startupFail.copied': 'Kopiert. In eine Nachricht einfügen und senden.',
    'startupFail.copy': 'Text kopieren',
    'startupFail.errorLabel': 'Fehler',
    'startupFail.explainEarly':
        'Die App wurde beendet, bevor ihre Logik starten konnte. Das '
        'liegt im nativen Teil der App oder in einem Plugin, das beim '
        'Laden fehlschlägt.',
    'startupFail.explainLate':
        'Die App wurde mitten im Start beendet. Der Schritt oben zeigt, '
        'wo es passiert ist.',
    'startupFail.heading': 'Der letzte Start ist nicht durchgelaufen',
    'startupFail.hint': 'Der Text enthält keine persönlichen Daten.',
    'startupFail.noStep': 'keiner (Absturz vor dem App-Start)',
    'startupFail.share': 'Text senden',
    'startupFail.shareFailed': 'Senden nicht möglich. Bitte den Text kopieren.',
    'startupFail.stepLabel': 'Letzter erreichter Schritt',
    'theme.classic': 'Classic Thestia',
    'theme.colorScheme': 'Farbschema',
    'theme.forest': 'Wald',
    'theme.lavender': 'Lavendel',
    'theme.ocean': 'Ozean',
    'theme.slate': 'Schiefer',
    'theme.sunset': 'Sonnenuntergang',
    'update.body':
        'Deine Version von Thestia unterstützt nicht mehr alle '
        'Server-Funktionen. Bitte aktualisiere die App, um '
        'weiterzumachen.',
    'update.later': 'Trotzdem fortfahren',
    // Video-Verifizierung
    'verify.title': 'Video-Verifizierung',
    'update.now': 'Jetzt aktualisieren',
    'update.required': 'Update erforderlich',
    'validation.ageEmpty': 'Bitte gib dein Alter ein',
    'validation.ageInvalid': 'Bitte gib ein gültiges Alter ein',
    'validation.ageMin':
        'Du musst mindestens {age} Jahre alt sein, um diese App zu nutzen',
    'validation.ageNumber': 'Bitte eine Zahl eingeben',
    'validation.bioLong': 'Maximal 300 Zeichen',
    'validation.birthEmpty': 'Bitte wähle dein Geburtsdatum',
    'validation.birthFuture':
        'Das Geburtsdatum darf nicht in der Zukunft liegen',
    'validation.birthInvalid': 'Bitte gib ein gültiges Geburtsdatum ein',
    'validation.emailEmpty': 'Bitte gib deine Email ein',
    'validation.emailInvalid': 'Bitte gib eine gültige Emailadresse ein',
    'validation.emailTld':
        'Bitte gib eine Email mit gültiger Domainendung ein '
        '(z. B. .de, .com, .net, .org)',
    'validation.field': 'Feld',
    'validation.nameEmpty': 'Bitte gib einen Namen ein',
    'validation.nameShort': 'Name ist zu kurz',
    'validation.passwordCommon':
        'Dieses Passwort ist zu häufig. Bitte wähle ein sichereres.',
    'validation.passwordDigit': 'Das Passwort braucht mindestens eine Zahl',
    'validation.passwordEmpty': 'Bitte gib ein Passwort ein',
    'validation.passwordLength': 'Das Passwort braucht mindestens 8 Zeichen',
    'validation.passwordLetter':
        'Das Passwort braucht mindestens einen Buchstaben',
    'validation.pwChars': '8 Zeichen',
    'validation.pwDigit': 'eine Zahl',
    'validation.pwLower': 'einen Kleinbuchstaben',
    'validation.pwMedium': 'Mittel',
    'validation.pwMissing': 'Das Passwort braucht: {list}',
    'validation.pwSpecial': 'ein Sonderzeichen',
    'validation.pwStrong': 'Stark',
    'validation.pwUpper': 'einen Großbuchstaben',
    'validation.pwWeak': 'Schwach',
    'validation.required': '{field} darf nicht leer sein',
  },
  'en': {
    'ai.cloudBadge': 'Cloud AI',
    'ai.localBadge': 'On-device AI',
    'appearance.dark': 'Dark',
    'appearance.light': 'Light',
    'appearance.system': 'System',
    'appearanceDesc.dark': 'Always a dark interface, starting in the morning.',
    'appearanceDesc.light': 'Always a light interface, even in the evening.',
    'appearanceDesc.system':
        'Follows your device: light by day, dark when it is in dark mode.',
    'common.back': 'Back',
    'common.cancel': 'Cancel',
    'common.check': 'Check',
    'common.close': 'Close',
    // Quiz "How well do I know my match"
    'quiz.title': 'Getting-to-know quiz',
    'common.confirm': 'Confirm',
    'common.continue': 'Continue',
    'common.copy': 'Copy',
    // Settings: backup + passkeys
    'settings.backupPw': 'Password (min. 8 characters)',
    'common.discard': 'Discard',
    'common.done': 'Done',
    'common.errorOccurred': 'An error occurred:',
    'common.errorWith': 'Error: {error}',
    'common.hint': 'Note',
    'common.later': 'Later',
    'common.loading': 'Loading…',
    'common.new': 'NEW',
    'common.ok': 'OK',
    'common.refresh': 'Refresh',
    'common.retry': 'Try again',
    // 404 error page
    'error.notFoundTitle': 'Page not found',
    'common.save': 'Save',
    'common.skip': 'Skip',
    'common.unknownError': 'Unknown error',
    'common.whatHappened': 'What happened?',
    'common.years': 'years',
    'distance.bucketOver': 'over {km} km',
    'distance.bucketRange': '{from} to {to} km',
    'distance.bucketUnder': 'under {km} km',
    'distance.bucketUnknown': 'Distance unknown',
    'error.alreadyRegistered':
        'This email address is already registered. Please log in directly '
        'or reset your password.',
    'error.captchaRejected':
        'The security check was rejected by the server. '
        'Please try again.',
    // Own case for the 20-second timeout in login_screen.dart: it says
    // "the server did not answer", not "something went wrong". Without
    // this branch the timeout lands in error.generic and cannot be told
    // apart from a CAPTCHA failure.
    'error.serverUnreachable':
        'The server did not respond. Check your internet connection '
        'and try again.',
    'error.generic': 'Something went wrong. Please try again.',
    // Admin area (visible for moderation only)
    'admin.deniedTitle': 'Access denied',
    'error.goHome': 'To home page',
    // Reporting: AI confirmation
    'report.aiConfirm':
        'Thanks! The AI also flags the image as inappropriate '
        '(score {score}%).',
    'error.loginFailed': 'Log-in failed. Please try again.',
    'error.notConfirmed': 'Please confirm your email address first.',
    'error.notFoundBody':
        'This page does not (or no longer) exist. No problem, you will '
        'be on your way shortly.',
    'error.rateLimited':
        'Too many requests in a short time. Please wait a '
        'moment and try again.',
    'error.signupFailed':
        'Sign-up failed on the server. Please try again '
        'later.',
    'error.weakPassword':
        'The password is too weak. Please choose a longer '
        'one with upper/lower case letters, numbers and special characters.',
    'friends.badge': 'Friendship',
    'friends.toggleHint':
        'This connection is a friendship - not a romantic spark. You '
        'can switch it back at any time.',
    'gender.diverse': 'Diverse',
    'gender.female': 'Female',
    'gender.femaleTrans': 'Female (M to F)',
    'gender.male': 'Male',
    'gender.maleTrans': 'Male (F to M)',
    'gender.other': 'Own / Other',
    'genderpref.all': 'All',
    'keyboard.backspace': 'Delete',
    'keyboard.emoji': 'Emoji',
    'keyboard.enter': 'Enter',
    'keyboard.hide': 'Hide keyboard',
    'keyboard.paste': 'Paste',

    'chat.block': 'Block user',
    'keyboard.shift': 'Upper and lower case',
    'keyboard.space': 'Space',
    'keyboard.symbols': 'Numbers and symbols',
    'language.english': 'English',
    'language.german': 'German',
    'location.disclosureAccept': 'Share location',
    'location.disclosureBody':
        'Thestia needs your approximate location for the distance '
        'display and the age check. It is queried once, never sent '
        'to the server, and deleted after the check. On older '
        'Android versions it is also required so that the transit '
        'radar can detect nearby devices.',
    'music.dislikedTitle': 'Genres I dislike (optional)',
    'music.exclude': 'Exclude genre…',
    'music.excludeHint':
        'This genre negatively influences your matching - you will see '
        'fewer people with this taste.',
    'music.excludeNoMatch': 'No genre found.',
    'music.excludeSearch': 'Search genre …',
    'music.excludeTitle': 'Exclude genre',
    'music.genre.klassik': 'Classical',
    'music.likedTitle': 'Genres I like',
    'nav.discover': 'Discover',
    'nav.home': 'Home',
    'nav.interests': 'Interests',
    'nav.profile': 'Profile',
    'nav.unsavedBody':
        'Your profile changes have not been saved yet. What would you '
        'like to do?',
    // Fehler (Auth)
    'error.invalidCredentials': 'Email or password is wrong.',
    'nav.unsavedTitle': 'Unsaved changes',
    'startup.failedBody': 'Please close the app completely and try again.',
    'startupFail.continue': 'Continue anyway',
    'startupFail.copied': 'Copied. Paste it into a message and send it.',
    'startupFail.copy': 'Copy text',
    'startupFail.errorLabel': 'Error',
    'startupFail.explainEarly':
        'The app was stopped before its logic could start. This is in the '
        'native part of the app or in a plugin that fails to load.',
    'startupFail.explainLate':
        'The app was stopped during startup. The step above shows where.',
    'startupFail.heading': 'The last start did not complete',
    'startupFail.hint': 'The text contains no personal data.',
    'startupFail.noStep': 'none (crashed before the app logic started)',
    'startupFail.share': 'Send text',
    'startupFail.shareFailed': 'Sending is not possible. Please copy the text.',
    'startupFail.stepLabel': 'Last step reached',
    'theme.classic': 'Classic Thestia',
    'theme.colorScheme': 'Color scheme',
    'theme.forest': 'Forest',
    'theme.lavender': 'Lavender',
    'theme.ocean': 'Ocean',
    'theme.slate': 'Slate',
    'theme.sunset': 'Sunset',
    'update.body':
        'Your version of Thestia no longer supports all server features. '
        'Please update the app to continue.',
    'update.later': 'Continue anyway',
    // Video verification
    'verify.title': 'Video verification',
    'update.now': 'Update now',
    'update.required': 'Update required',
    'validation.ageEmpty': 'Please enter your age',
    'validation.ageInvalid': 'Please enter a valid age',
    'validation.ageMin': 'You must be at least {age} years old to use this app',
    'validation.ageNumber': 'Please enter a number',
    'validation.bioLong': 'Maximum 300 characters',
    'validation.birthEmpty': 'Please pick your birth date',
    'validation.birthFuture': 'The birth date must not be in the future',
    'validation.birthInvalid': 'Please enter a valid birth date',
    'validation.emailEmpty': 'Please enter your email',
    'validation.emailInvalid': 'Please enter a valid email address',
    'validation.emailTld':
        'Please enter an email with a valid domain ending '
        '(e.g. .de, .com, .net, .org)',
    'validation.field': 'Field',
    'validation.nameEmpty': 'Please enter a name',
    'validation.nameShort': 'Name is too short',
    'validation.passwordCommon':
        'This password is too common. Please choose a safer one.',
    'validation.passwordDigit': 'The password needs at least one digit',
    'validation.passwordEmpty': 'Please enter a password',
    'validation.passwordLength': 'The password needs at least 8 characters',
    'validation.passwordLetter': 'The password needs at least one letter',
    'validation.pwChars': '8 characters',
    'validation.pwDigit': 'a digit',
    'validation.pwLower': 'a lowercase letter',
    'validation.pwMedium': 'Medium',
    'validation.pwMissing': 'The password needs: {list}',
    'validation.pwSpecial': 'a special character',
    'validation.pwStrong': 'Strong',
    'validation.pwUpper': 'an uppercase letter',
    'validation.pwWeak': 'Weak',
    'validation.required': '{field} must not be empty',
  },
};
