// Die Texte des Themas 'geräte' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsGeraete = {
  'de': {
    'contactShare.add': 'Hinzufügen',
    'contactShare.addCustom': 'Weitere App hinzufügen',
    'contactShare.apps': 'Apps',
    'contactShare.copied': 'In die Zwischenablage kopiert.',
    'contactShare.copy': 'Kopieren',
    'contactShare.customApp': 'App-Name',
    'contactShare.customAppHint': 'z. B. Telegram',
    'contactShare.customEntry': 'Eigene App',
    'contactShare.customNeedsName': 'Bitte App-Namen und Handle ausfüllen.',
    'contactShare.discord': 'Discord',
    'contactShare.empty':
        'Noch keine Kontaktdaten gespeichert. Trage Telefonnummer oder '
        'einen Handle ein und tippe auf Speichern.',
    'contactShare.handle': 'Name / Handle',
    'contactShare.handleHint': '@name oder ID',
    'contactShare.handleMissing':
        'Bitte gib einen Handle ein oder schalte die App aus.',
    'contactShare.instagram': 'Instagram',
    'contactShare.intro':
        'Speichere hier, wie dich andere außerhalb von Thestia erreichen '
        'können. Du entscheidest bei jedem Teilen neu.',
    'contactShare.invalidPhone': 'Bitte gib eine gültige Telefonnummer ein.',
    'contactShare.loadFailed':
        'Kontaktdaten konnten nicht geladen werden. Deine Angaben sind '
        'weiterhin sicher auf diesem Gerät.',
    'contactShare.none': 'Nicht angegeben',
    'contactShare.notRecommended': 'nicht empfohlen',
    'contactShare.notRecommendedHint':
        'Instagram, Snapchat und Discord sind keine sicheren Messenger. '
        'Nutze sie nur, wenn du das möchtest.',
    'contactShare.phone': 'Telefonnummer',
    'contactShare.phoneHint': 'z. B. +49 170 1234567',
    'contactShare.phonePrivacy':
        'Deine Nummer bleibt verschlüsselt auf diesem Gerät und wird nie '
        'an unsere Server gesendet.',
    'contactShare.qrCardSub': 'Kontaktdaten lokal speichern und teilen',
    'contactShare.qrCardTitle': 'Telefon & Social Media',
    'contactShare.recommended': 'empfohlen',
    'contactShare.remove': 'Entfernen',
    'contactShare.save': 'Speichern',
    'contactShare.saveFailed':
        'Speichern fehlgeschlagen. Bitte versuche es erneut.',
    'contactShare.saved': 'Kontaktdaten gespeichert.',
    'contactShare.share': 'Kontaktdaten teilen',
    'contactShare.shareFailed': 'Teilen ist gerade nicht möglich.',
    'contactShare.shareFooter':
        'Geteilt mit Thestia. Meine Nummer bleibt auf meinem Gerät.',
    'contactShare.shareIntro': 'So kannst du mich erreichen:',
    'contactShare.shareTitle': 'Meine Kontaktdaten',
    'contactShare.signal': 'Signal',
    'contactShare.snapchat': 'Snapchat',
    'contactShare.subtitle':
        'Teile deine Kontaktdaten, aber nur wenn du willst.',
    'contactShare.threema': 'Threema',
    'devices.activeHoursA': 'aktiv vor',
    'devices.activeHoursB': 'Std.',
    'devices.activeLastSeen': 'zuletzt aktiv am',
    'devices.activeMinutesA': 'aktiv vor',
    'devices.activeMinutesB': 'Min.',
    'devices.activeNow': 'gerade aktiv',
    'devices.current': 'Dieses Gerät',
    'devices.empty':
        'Keine weiteren Geräte registriert. Öffne Thestia auf einem anderen '
        'Gerät (mindestens diese Version), damit es sich in der Liste zeigt.',
    'devices.hint':
        'Hier siehst du, auf welchen Geräten du aktuell angemeldet bist. '
        'Über "Überall abmelden" beendest du alle anderen Sitzungen. '
        'Dieses Gerät bleibt angemeldet.',
    'devices.logoutBody':
        'Du wirst auf allen anderen Geräten abgemeldet. Die Sitzung auf '
        'diesem Gerät bleibt bestehen. Die anderen Geräte müssen sich '
        'danach neu anmelden.',
    'devices.logoutBtn': 'Überall abmelden',
    'devices.logoutBtnLong': 'Überall abmelden (außer diesem Gerät)',
    'devices.logoutDone': 'Alle anderen Geräte wurden abgemeldet.',
    'devices.logoutFailed':
        'Abmelden ist fehlgeschlagen. Bitte prüfe deine Verbindung und '
        'versuche es erneut.',
    'devices.logoutNote':
        'Die anderen Geräte werden sofort abgemeldet und müssen sich beim '
        'nächsten Öffnen neu einloggen.',
    'devices.logoutTitle': 'Überall abmelden?',
    'devices.retry': 'Erneut versuchen',
    'devices.signingOut': 'Melde ab …',
    'devices.title': 'Angemeldete Geräte',
    'qr.choiceTitle': 'Was möchtest du tun?',
    'qr.codeHint': 'z. B. A1B2C3D4',
    'qr.copied': 'Code in die Zwischenablage kopiert',
    'qr.copyTooltip': 'Code kopieren',
    'qr.enterCode': 'Code eingeben',
    'qr.enterCodeHint':
        'Gib den 8 stelligen Code der Person ein,\ndie du finden möchtest.',
    'qr.enterCodeSub': 'Den 8 stelligen Code manuell eintippen',
    'qr.enterFullCode': 'Bitte gib den vollständigen 8 stelligen Code ein.',
    'qr.invalidCode':
        'Dieser QR-Code ist kein Thestia-Profilcode. Bitte scanne den '
        'persönlichen QR-Code aus der App.',
    'qr.likeFailed': 'Like konnte nicht gesendet werden: {error}',
    'qr.limitBody':
        'Es sind bereits 5 Profile lokal gespeichert. Entferne in der Liste '
        'zuerst eines, dann scanne erneut.',
    'qr.limitEmpty':
        'Keine gespeicherten Profile mehr vorhanden - '
        'jetzt erneut scannen.',
    'qr.myCode': 'Mein QR Code',
    'qr.noUserFound': 'Kein Nutzer mit diesem Code gefunden.',
    // QR-Scan = erstmal Like (nicht direkt ein Chat)
    'qr.likeSent':
        'Like gesendet! Sobald die Person annimmt, entsteht euer Funke '
        'und damit der Chat.',
    'qr.ownCode': 'Das ist dein eigener Code!',
    'qr.resolveFailed': 'Code konnte nicht aufgelöst werden.',
    'qr.savedDeleteTooltip': 'Gespeichertes Profil entfernen',
    'qr.savedOffline':
        'Kein Internet - Profil lokal gespeichert. Du kannst die Person '
        'später anschreiben ("Gespeicherte Profile").',
    'qr.scanSub': 'Kamera öffnen und Code einscannen',
    'qr.scanTitle': 'QR Code scannen',
    'qr.searchUser': 'Nutzer suchen',
    'qr.shareHint':
        'Teile diesen Code oder den QR Code mit anderen. Sie können dich damit in der App finden und direkt anschreiben.',
    'qr.shareSub': 'Damit andere dich finden können',
    'qr.showMine': 'Meinen QR Code zeigen',
    'qr.showMineBtn': 'Meinen eigenen Code anzeigen',
    'qr.yourCode': 'Dein Code',
    'whatsnew.cta': 'Los geht\'s',
    'whatsnew.inputsTitle': 'Neu zum Auswählen',
    'whatsnew.title': 'Neu in dieser Version',
    'whatsnew.v090.birthdayStyles':
        '5 schicke Geburtstags-Stile für dein Profil (unten auswählen '
        'oder später im Profil-Bearbeiten).',
    // Build 30 (v0.9.2). EIN Key pro Anzeigepunkt, jeder Punkt ein
    // vollständiger Satz - siehe Bug-Hinweis in
    // lib/services/server/whats_new_service.dart: bei hartkodiertem Text
    // waren es Satzbausteine, und die Abschneidegrenze zerschnitt
    // mitten im Satz. Außerdem waren diese Zeilen überhaupt nicht
    // übersetzt, englische Nutzer sahen deutschen Text.
    'whatsnew.v092.rotatingPrompts':
        'Vorstellungen, die sich nicht wiederholen: Die Ideen-Karten '
        'rotieren jetzt, statt immer dieselben vier zu zeigen.',
    'whatsnew.v090.bucketList':
        'Gemeinsame Erinnerungsliste im Chat: Das wollt ihr zusammen '
        'erleben - ankreuzbar, ohne Druck.',
    'whatsnew.v090.friendship':
        'Freundschafts-Modus: Verbindungen sind jetzt ausdrücklich als '
        'Freundschaft kennzeichnbar.',
    'whatsnew.v090.sparkMoments':
        'Erinnerungs-Momente im Chat: erster Tag, Quiz-Bestehen und '
        'Jubiläen werden ehrlich gewürdigt.',
    'whatsnew.v092.emailRequired':
        'Wichtig: Eine bestätigte E-Mail-Adresse ist jetzt '
        'Voraussetzung für Funken, Daumen und Nachrichten.',
    'whatsnew.v092.proximityJitter':
        'Nähefunk sendet jetzt unregelmäßig statt im festen Takt und '
        'hört nur noch Signale von Thestia.',
    // v0.10.0 (Build 31): Standort-Privatisierung
    'whatsnew.v1000.noCity':
        'Dein Profil nennt jetzt nur noch dein Bundesland. Ein Ort, eine '
        'Stadt oder ein Adressbereich wird nicht mehr gespeichert und '
        'niemandem angezeigt.',
    'whatsnew.v092.safetyNumber':
        'Neu: Du kannst festlegen, dass ein Chat erst nach dem Vergleich '
        'der Sicherheitsnummern beginnt.',
    'whatsnew.v1000.distanceOptIn':
        'Andere sehen erst dann eine ungefähre Entfernung, wenn du das '
        'einschaltest. Selbst dann nur grobe Stufen von 10 km, nie eine '
        'Zahl.',
    // Sprachnachrichten im Chat (Einmal-Anhören, M-17)
    'chat.voiceOnce':
        'Diese Sprachnachricht wurde bereits angehört und entfernt '
        '(Datenschutz: entschlüsselte Audio-Reste werden gelöscht).',
    'whatsnew.v1000.grid':
        'Deine Position wird nur als Rasterpunkt im Abstand von 5 km '
        'gespeichert. Die Rasterung passiert auf dem Server, nicht nur '
        'in der App.',
    'whatsnew.v1020.birthdayPrivacy':
        'Der Geburtstag ist jetzt nur noch für Menschen sichtbar, mit denen du '
        'ein Match hast. So verrät dein Profil nicht mehr dein genaues '
        'Geburtsdatum.',
    'whatsnew.v1020.safetyOffer':
        'Neu: Im Chat erscheint ein Hinweis, die Sicherheitsnummer mit deinem '
        'Gegenüber zu vergleichen - so stellt ihr sicher, dass niemand '
        'dazwischenfunkt.',
  },
  'en': {
    'contactShare.add': 'Add',
    'contactShare.addCustom': 'Add another app',
    'contactShare.apps': 'Apps',
    'contactShare.copied': 'Copied to clipboard.',
    'contactShare.copy': 'Copy',
    'contactShare.customApp': 'App name',
    'contactShare.customAppHint': 'e.g. Telegram',
    'contactShare.customEntry': 'Custom app',
    'contactShare.customNeedsName': 'Please fill in app name and handle.',
    'contactShare.discord': 'Discord',
    'contactShare.empty':
        'No contact details saved yet. Enter a phone number or a handle '
        'and tap Save.',
    'contactShare.handle': 'Name / handle',
    'contactShare.handleHint': '@name or ID',
    'contactShare.handleMissing': 'Please enter a handle or turn the app off.',
    'contactShare.instagram': 'Instagram',
    'contactShare.intro':
        'Save how others can reach you outside Thestia. You decide anew '
        'every time you share.',
    'contactShare.invalidPhone': 'Please enter a valid phone number.',
    'contactShare.loadFailed':
        'Contact details could not be loaded. Your data is still safe on '
        'this device.',
    'contactShare.none': 'Not provided',
    'contactShare.notRecommended': 'not recommended',
    'contactShare.notRecommendedHint':
        'Instagram, Snapchat and Discord are not secure messengers. Use '
        'them only if you want to.',
    'contactShare.phone': 'Phone number',
    'contactShare.phoneHint': 'e.g. +49 170 1234567',
    'contactShare.phonePrivacy':
        'Your number stays encrypted on this device and is never sent to '
        'our servers.',
    'contactShare.qrCardSub': 'Store and share contact details locally',
    'contactShare.qrCardTitle': 'Phone & social media',
    'contactShare.recommended': 'recommended',
    'contactShare.remove': 'Remove',
    'contactShare.save': 'Save',
    'contactShare.saveFailed': 'Saving failed. Please try again.',
    'contactShare.saved': 'Contact details saved.',
    'contactShare.share': 'Share contact details',
    'contactShare.shareFailed': 'Sharing is currently not possible.',
    'contactShare.shareFooter':
        'Shared with Thestia. My number stays on my device.',
    'contactShare.shareIntro': 'Here is how you can reach me:',
    'contactShare.shareTitle': 'My contact details',
    'contactShare.signal': 'Signal',
    'contactShare.snapchat': 'Snapchat',
    'contactShare.subtitle':
        'Share your contact details - only if you want to.',
    'contactShare.threema': 'Threema',
    'devices.activeHoursA': 'active',
    'devices.activeHoursB': 'h ago',
    'devices.activeLastSeen': 'last active on',
    'devices.activeMinutesA': 'active',
    'devices.activeMinutesB': 'min ago',
    'devices.activeNow': 'active right now',
    'devices.current': 'This device',
    'devices.empty':
        'No other devices registered. Open Thestia on another device (at '
        'least this version) so it shows up in the list.',
    'devices.hint':
        'Here you can see which devices are currently signed in. Use '
        '"Sign out everywhere" to end all other sessions. This device '
        'stays signed in.',
    'devices.logoutBody':
        'You will be signed out on all other devices. The session on this '
        'device stays active. The other devices will need to sign in '
        'again afterwards.',
    'devices.logoutBtn': 'Sign out everywhere',
    'devices.logoutBtnLong': 'Sign out everywhere (except this device)',
    'devices.logoutDone': 'All other devices have been signed out.',
    'devices.logoutFailed':
        'Signing out failed. Please check your connection and try again.',
    'devices.logoutNote':
        'The other devices will be signed out immediately and must log in '
        'again the next time they open the app.',
    'devices.logoutTitle': 'Sign out everywhere?',
    'devices.retry': 'Try again',
    'devices.signingOut': 'Signing out…',
    'devices.title': 'Signed-in devices',
    'qr.choiceTitle': 'What would you like to do?',
    'qr.codeHint': 'e.g. A1B2C3D4',
    'qr.copied': 'Code copied to clipboard',
    'qr.copyTooltip': 'Copy code',
    'qr.enterCode': 'Enter code',
    'qr.enterCodeHint':
        'Enter the 8-digit code of the person\nyou want to find.',
    'qr.enterCodeSub': 'Type the 8-digit code manually',
    'qr.enterFullCode': 'Please enter the full 8-digit code.',
    'qr.invalidCode':
        'This QR code is not a Thestia profile code. Please scan the personal '
        'QR code from the app.',
    'qr.likeFailed': 'Like could not be sent: {error}',
    'qr.limitBody':
        '5 profiles are already saved locally. Remove one from the list '
        'first, then scan again.',
    'qr.limitEmpty': 'No saved profiles left - scan again now.',
    'qr.myCode': 'My QR code',
    'qr.noUserFound': 'No user found with this code.',
    // QR scan = like first (no instant chat)
    'qr.likeSent':
        'Like sent! As soon as the person accepts it, your chat opens up.',
    'qr.ownCode': 'That is your own code!',
    'qr.resolveFailed': 'Could not resolve the code.',
    'qr.savedDeleteTooltip': 'Remove saved profile',
    'qr.savedOffline':
        'No internet - profile saved locally. You can write to the person '
        'later ("Saved profiles").',
    'qr.scanSub': 'Open the camera and scan a code',
    'qr.scanTitle': 'Scan QR code',
    'qr.searchUser': 'Search user',
    'qr.shareHint':
        'Share this code or the QR code with others. They can find you in the app and message you directly.',
    'qr.shareSub': 'So others can find you',
    'qr.showMine': 'Show my QR code',
    'qr.showMineBtn': 'Show my own code',
    'qr.yourCode': 'Your code',
    'whatsnew.cta': "Let's go",
    'whatsnew.inputsTitle': 'New choices',
    'whatsnew.title': 'New in this version',
    'whatsnew.v090.birthdayStyles':
        '5 tasteful birthday styles for your profile (choose below or '
        'later in profile editing).',
    // Build 30 (v0.9.2) - siehe deutsche Fassung oben.
    'whatsnew.v092.rotatingPrompts':
        'Introductions that do not repeat: the prompt cards now rotate '
        'instead of always showing the same four.',
    'whatsnew.v090.bucketList':
        'Shared memory list in the chat: things you want to experience '
        'together - checkable, no pressure.',
    'whatsnew.v090.friendship':
        'Friendship mode: connections can now be explicitly marked as '
        'friendship.',
    'whatsnew.v090.sparkMoments':
        'Milestones in the chat: first day, quiz passed and '
        'anniversaries are acknowledged honestly.',
    'whatsnew.v092.emailRequired':
        'Important: a confirmed email address is now required for '
        'sparks, thumbs and messages.',
    'whatsnew.v092.proximityJitter':
        'Proximity now sends at irregular intervals instead of a fixed '
        'rhythm, and listens only for Thestia signals.',
    // v0.10.0 (Build 31): location privacy
    'whatsnew.v1000.noCity':
        'Your profile now names only your state. No city, place or '
        'address area is stored or shown to anyone.',
    'whatsnew.v092.safetyNumber':
        'New: you can require a chat to start only after comparing '
        'safety numbers.',
    'whatsnew.v1000.distanceOptIn':
        'Others see an approximate distance only after you switch it '
        'on. Even then just coarse 10 km steps, never a number.',
    // Voice messages (listen once, M-17)
    'chat.voiceOnce':
        'This voice message was already listened to and removed (privacy: '
        'decrypted audio remains are deleted).',
    'whatsnew.v1000.grid':
        'Your position is stored only as a grid point at 5 km. The '
        'snapping happens on the server, not just in the app.',
    'whatsnew.v1020.birthdayPrivacy':
        'The birthday is now only visible to people you have matched with. '
        'That way your profile no longer reveals your exact date of birth.',
    'whatsnew.v1020.safetyOffer':
        'New: the chat now shows a hint to compare the safety number with '
        'your partner - that way you both make sure nobody is '
        'intercepting your conversation.',
  },
};
