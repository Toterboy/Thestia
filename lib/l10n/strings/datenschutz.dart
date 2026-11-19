// Die Texte des Themas 'privacy' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fuegt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsDatenschutz = {
  'de': {
    'del.accountHint':
        'Du willst das ganze Konto loswerden? Das geht auch - damit '
        'verschwindet alles, auch die Anmeldung.',
    'del.accountLink': 'Konto vollständig löschen',
    'del.allBtn': 'Alle Daten löschen (Konto bleibt)',
    'del.allText':
        'Löscht sämtliche Daten zu deinem Konto: Profil, Fotos, '
        'Standort, Likes, Funken, Nachrichten, Geräte, Verlauf und '
        'Meldungen. Dein Konto bleibt - du kannst dich weiter anmelden, '
        'findest dort aber nichts mehr.',
    'del.allTitle': 'Alles löschen',
    'del.confirmText': 'Folgende Daten werden gelöscht:',
    'del.confirmTitle': 'Daten löschen?',
    'del.deleteBtn': 'Löschen',
    'del.doneText':
        'Die gewählten Daten sind gelöscht. Dein Konto bleibt bestehen.',
    'del.doneTitle': 'Gelöscht',
    'del.elternaufsicht': 'Elternaufsicht',
    'del.elternaufsichtSub':
        'Die Freigabe deiner Eltern: sie wird beendet und deine Eltern '
        'erhalten keine Nachrichten mehr.',
    'del.fotos': 'Profilfotos',
    'del.fotosSub':
        'Alle Bilder im Profil, auch die in der Cloud gespeicherten.',
    'del.funken': 'Funken',
    'del.funkenSub':
        'Alle Funken (Matches). Achtung: damit endet der Chat - auch für '
        'die andere Person.',
    'del.geraete': 'Geräte und Schlüssel',
    'del.geraeteSub':
        'Deine Geräteliste, Passkeys, Push-Schlüssel und Prekeys. Nach '
        'dem Löschen musst du neue Geräte wieder anmelden.',
    'del.intro':
        'Du kannst einzelne Daten löschen, ohne dein Konto aufzugeben.',
    'del.intro2':
        'Die Löschung ist unwiderruflich - es gibt kein Wiederherstellen. '
        'Dein Konto, deine E-Mail-Adresse und dein Passwort bleiben.',
    'del.irreversible': 'Das lässt sich nicht rückgängig machen.',
    'del.likes': 'Likes',
    'del.likesSub': 'Die von dir gesetzten und die von dir erhaltenen Likes.',
    'del.meldungen': 'Meldungen und Berichte',
    'del.meldungenSub':
        'Deine Meldungen über andere und die Fehlerberichte, die du '
        'geschickt hast.',
    'del.nachrichten': 'Nachrichten',
    'del.nachrichtenSub':
        'Die von dir gesendeten Nachrichten. Empfangene Nachrichten sind '
        'Daten der anderen Person - die verschwinden dort.',
    'del.partialText':
        'Ein Teil konnte nicht gelöscht werden. Melde dich gern beim '
        'Support - dann schauen wir gemeinsam darauf.',
    'del.partialTitle': 'Teilweise gelöscht',
    'del.profil': 'Profilangaben',
    'del.profilSub':
        'Bio, Interessen, Musik, Vorstellung, Audio und deine Gewohnheiten.',
    'del.standort': 'Standortdaten',
    'del.standortSub':
        'Deine Koordinaten und dein Bundesland. Danach sieht niemand mehr, '
        'wie weit weg du bist.',
    'del.stimmung': 'Stimmung und Verlauf',
    'del.stimmungSub': 'Deine täglichen Stimmungsangaben und der Verlauf.',
    'del.transit': 'Transit Spark',
    'del.transitSub':
        'Deine Nahbereichs-Signale, deine Anwesenheit und die Grüße, die '
        'dir gesendet wurden.',
    'privacy.accountInfo':
        'E-Mail- und Passwort-Änderungen erfordern dein aktuelles '
        'Passwort. Bei E-Mail-Wechsel bestätigst du die neue Adresse '
        'über einen Link in beiden Postfächern.',
    'privacy.accountSection': 'Anmeldung',
    'privacy.changeEmail': 'E-Mail-Adresse ändern',
    'privacy.changeEmailInfo':
        'Du erhältst einen Bestätigungs-Link an deine alte UND neue '
        'Adresse. Die Änderung wird erst nach Bestätigung aktiv.',
    'privacy.changeEmailSent':
        'Bestätigungs-Link an beide E-Mail-Adressen gesendet.',
    'privacy.changeFailed': 'Änderung fehlgeschlagen',
    'privacy.changePassword': 'Passwort ändern',
    'privacy.changePasswordDone': 'Passwort geändert.',
    'privacy.consent': 'Einwilligungen',
    'privacy.dangerZone': 'Gefahrenzone',
    'privacy.dataInfo':
        'Thestia speichert Profilinformationen, Standortdaten (nur wenn du '
        'sie freigibst), Fotos, Chats, Likes und Funken. Alle Daten '
        'werden verschlüsselt übertragen und nur so lange gespeichert, '
        'wie dein Account aktiv ist.',
    'privacy.deleteAccount': 'Account dauerhaft löschen',
    'privacy.deleteAccountSub':
        'DSGVO Art. 17: Recht auf Löschung. Alle Daten werden entfernt.',
    'privacy.deleteBody':
        'Dieser Schritt kann nicht rückgängig gemacht werden. Alle deine '
        'Daten (Profil, Fotos, Chats, Funken, Likes) werden dauerhaft '
        'gelöscht.',
    'privacy.deleteConfirm': 'Endgültig löschen',
    'privacy.deleteFailed': 'Account konnte nicht gelöscht werden',
    'privacy.deleteTitle': 'Account löschen?',
    'privacy.export': 'Meine Daten exportieren',
    'privacy.exportFailed': 'Export fehlgeschlagen',
    'privacy.exportSub': 'JSON Download aller personenbezogenen Daten',
    'privacy.import': 'Daten importieren',
    'privacy.importApply': 'Importieren',
    'privacy.importBody':
        'Füge hier den Inhalt deiner Export-Datei (thestia_data_export.json) '
        'ein. Profil, Einstellungen und Präferenzen werden '
        'wiederhergestellt.',
    'privacy.importDone': 'Daten erfolgreich importiert.',
    'privacy.importFailed': 'Import fehlgeschlagen',
    'privacy.importHint': '{ ... JSON hier einfügen ... }',
    'privacy.importInvalid':
        'Das eingefügte JSON konnte nicht gelesen '
        'werden. Bitte prüfe den Inhalt.',
    'privacy.importSub': 'JSON-Datenexport wiederherstellen',
    'privacy.importTitle': 'Daten importieren',
    'privacy.imprintFailed':
        'Das Impressum konnte nicht geöffnet werden. Bitte öffne '
        'https://thestia.de/impressum im Browser.',
    'privacy.imprintSub':
        'Anbieterkennzeichnung nach § 5 DDG - Anschrift und Kontakt',
    'privacy.imprintTitle': 'Impressum',
    'privacy.location': 'Standortfreigabe',
    'privacy.locationSub':
        'Du kannst die Standortfreigabe in den Systemeinstellungen deines '
        'Geräts jederzeit widerrufen.',
    'privacy.noTurnSub':
        'Die Verbindung zwischen zwei Geräten entsteht direkt. Kommt sie '
        'nicht zustande, läuft der Chat verschlüsselt über den Server '
        'des Betreibers - der sieht dann, wer mit wem schreibt, aber '
        'nicht den Inhalt.',
    'privacy.noTurnTitle': 'Kein TURN-Relay-Server',
    'privacy.policySub':
        'Was wir erheben, warum, und wie lange. Vollständiger Text.',
    'privacy.policyTitle': 'Datenschutzerklärung',
    'privacy.processorBrevo': 'Transaktions-E-Mails (Bestätigung, Reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile)',
    'privacy.processorGoogle':
        'Push-Benachrichtigungen - nur in der Play-Store-Fassung '
        '(Firebase); im F-Droid-Build läuft UnifiedPush',
    'privacy.processorNetlify': 'Hosting der Anmelde-/CAPTCHA-Seite',
    'privacy.processorStun':
        'Ermittlung der öffentlichen IP-Adresse für die Direktverbindung '
        '(STUN) - keine Chat-Inhalte',
    'privacy.processorStunNames': 'Nextcloud, OVH, VoIPGate, VoIPStunt',
    'privacy.processorSupabase': 'Hosting, Datenbank, Authentifizierung (EU)',
    'privacy.processors': 'Auftragsverarbeiter',
    'privacy.processorsInfo':
        'Folgende Dienstleister (Art. 28 DSGVO) verarbeiten Daten im '
        'Auftrag. Chat-Inhalte sind Ende-zu-Ende-verschlüsselt und werden '
        'von keinem Dienstleister verarbeitet.',
    'privacy.push': 'Push Benachrichtigungen',
    'privacy.pushSub':
        'Öffnet die App-Einstellungen deines Geräts, dort kannst du die '
        'Benachrichtigungen steuern.',
    'privacy.termsSub': 'Was beim Benutzen der App erlaubt ist und was nicht',
    'privacy.termsTitle': 'Nutzungsbedingungen',
    'privacy.termsWeb': 'Die Webfassung im Browser öffnen',
    'privacy.totpConfirm': 'Bestätigen',
    // Melden (Nutzer + Bilder)
    'report.userTitle': 'Nutzer melden: {name}',
    'privacy.totpLabel': 'TOTP-Code (Authenticator-App)',
    'privacy.validator.invalidEmail': 'Ungültig',
    'privacy.validator.mismatch': 'Nicht identisch',
    'privacy.validator.tooShort': 'Zu kurz',
    'privacy.yourData': 'Deine Daten',
  },
  'en': {
    'del.accountHint':
        'Want to get rid of the whole account? That works too - everything '
        'disappears, including the sign-in.',
    'del.accountLink': 'Delete account completely',
    'del.allBtn': 'Delete all data (keep account)',
    'del.allText':
        'Deletes all data associated with your account: profile, photos, '
        'location, likes, sparks, messages, devices, history and reports. '
        'Your account stays - you can still sign in, but you will find '
        'nothing there.',
    'del.allTitle': 'Delete everything',
    'del.confirmText': 'The following data will be deleted:',
    'del.confirmTitle': 'Delete data?',
    'del.deleteBtn': 'Delete',
    'del.doneText':
        'The selected data has been deleted. Your account still exists.',
    'del.doneTitle': 'Deleted',
    'del.elternaufsicht': 'Parental access',
    'del.elternaufsichtSub':
        'Your parents\' consent ends and they no longer receive any '
        'notifications.',
    'del.fotos': 'Profile photos',
    'del.fotosSub':
        'All images in the profile, including the ones stored in the cloud.',
    'del.funken': 'Sparks',
    'del.funkenSub':
        'All sparks (matches). Note: this ends the chat - for the other '
        'person as well.',
    'del.geraete': 'Devices and keys',
    'del.geraeteSub':
        'Your device list, passkeys, push keys and prekeys. After deleting '
        'them you have to register new devices again.',
    'del.intro':
        'You can delete individual pieces of data without giving up your '
        'account.',
    'del.intro2':
        'Deletion is irreversible - there is no undo. Your account, your '
        'email address and your password stay.',
    'del.irreversible': 'This cannot be undone.',
    'del.likes': 'Likes',
    'del.likesSub': 'The likes you gave and the likes you received.',
    'del.meldungen': 'Reports and bug reports',
    'del.meldungenSub':
        'Your reports about others and the error reports you sent.',
    'del.nachrichten': 'Messages',
    'del.nachrichtenSub':
        'The messages you sent. Received messages belong to the other '
        'person - they disappear on their side.',
    'del.partialText':
        'Some of it could not be deleted. Feel free to contact support - '
        'we will look at it together.',
    'del.partialTitle': 'Partially deleted',
    'del.profil': 'Profile details',
    'del.profilSub':
        'Bio, interests, music, introduction, audio and your habits.',
    'del.standort': 'Location data',
    'del.standortSub':
        'Your coordinates and your federal state. Afterwards nobody sees '
        'how far away you are.',
    'del.stimmung': 'Mood and history',
    'del.stimmungSub': 'Your daily mood entries and the history.',
    'del.transit': 'Transit Spark',
    'del.transitSub':
        'Your nearby signals, your presence and the greetings you '
        'received.',
    'privacy.accountInfo':
        'Email and password changes require your current password. For '
        'email changes you confirm the new address via a link sent to '
        'both inboxes.',
    'privacy.accountSection': 'Sign-in',
    'privacy.changeEmail': 'Change email address',
    'privacy.changeEmailInfo':
        'You will receive a confirmation link at your old AND new '
        'address. The change only becomes active after confirmation.',
    'privacy.changeEmailSent':
        'Confirmation link sent to both email addresses.',
    'privacy.changeFailed': 'Change failed',
    'privacy.changePassword': 'Change password',
    'privacy.changePasswordDone': 'Password changed.',
    'privacy.consent': 'Consents',
    'privacy.dangerZone': 'Danger zone',
    'privacy.dataInfo':
        'Thestia stores profile information, location data (only if you '
        'share it), photos, chats, likes and matches. All data is '
        'transferred encrypted and stored only as long as your account is '
        'active.',
    'privacy.deleteAccount': 'Delete account permanently',
    'privacy.deleteAccountSub':
        'GDPR Art. 17: Right to erasure. All data will be removed.',
    'privacy.deleteBody':
        'This step cannot be undone. All your data (profile, photos, '
        'chats, matches, likes) will be permanently deleted.',
    'privacy.deleteConfirm': 'Delete permanently',
    'privacy.deleteFailed': 'Account could not be deleted',
    'privacy.deleteTitle': 'Delete account?',
    'privacy.export': 'Export my data',
    'privacy.exportFailed': 'Export failed',
    'privacy.exportSub': 'JSON download of all personal data',
    'privacy.import': 'Import my data',
    'privacy.importApply': 'Import',
    'privacy.importBody':
        'Paste the contents of your export file '
        '(thestia_data_export.json) here. Profile, settings and '
        'preferences will be restored.',
    'privacy.importDone': 'Data imported successfully.',
    'privacy.importFailed': 'Import failed',
    'privacy.importHint': '{ ... paste JSON here ... }',
    'privacy.importInvalid':
        'The pasted JSON could not be read. Please check the content.',
    'privacy.importSub': 'Restore your JSON data export',
    'privacy.importTitle': 'Import data',
    'privacy.imprintFailed':
        'The imprint could not be opened. Please open '
        'https://thestia.de/impressum in your browser.',
    'privacy.imprintSub':
        'Provider identification pursuant to Sec. 5 DDG - address and contact',
    'privacy.imprintTitle': 'Imprint',
    'privacy.location': 'Location sharing',
    'privacy.locationSub':
        'You can revoke location sharing at any time in your device\'s '
        'system settings.',
    'privacy.noTurnSub':
        'The connection between two devices is established directly. If it '
        'does not come up, the chat runs encrypted through the '
        'operator'
        's server - which then sees who is chatting with '
        'whom, but not the contents.',
    'privacy.noTurnTitle': 'No TURN relay server',
    'privacy.policySub': 'What we collect, why, and for how long. Full text.',
    'privacy.policyTitle': 'Privacy policy',
    'privacy.processorBrevo': 'Transactional emails (confirmation, reset)',
    'privacy.processorCloudflare': 'CAPTCHA (Turnstile)',
    'privacy.processorGoogle':
        'Push notifications - Play Store build only (Firebase); the '
        'F-Droid build uses UnifiedPush',
    'privacy.processorNetlify': 'Hosting of the auth/CAPTCHA page',
    'privacy.processorStun':
        'Determination of your public IP address for the direct connection '
        '(STUN) - no chat contents',
    'privacy.processorStunNames': 'Nextcloud, OVH, VoIPGate, VoIPStunt',
    'privacy.processorSupabase': 'Hosting, database, authentication (EU)',
    'privacy.processors': 'Processors',
    'privacy.processorsInfo':
        'The following service providers (Art. 28 GDPR) process data on '
        'our behalf. Chat content is end-to-end encrypted and is not '
        'processed by any provider.',
    'privacy.push': 'Push notifications',
    'privacy.pushSub':
        'Opens your device\'s app settings, where you can control '
        'notifications.',
    'privacy.termsSub': 'What is allowed when using the app, and what is not',
    'privacy.termsTitle': 'Terms of use',
    'privacy.termsWeb': 'Open the web version in the browser',
    'privacy.totpConfirm': 'Confirm',
    // Reporting (users + images)
    'report.userTitle': 'Report user: {name}',
    'privacy.totpLabel': 'TOTP code (authenticator app)',
    'privacy.validator.invalidEmail': 'Invalid',
    'privacy.validator.mismatch': 'Does not match',
    'privacy.validator.tooShort': 'Too short',
    'privacy.yourData': 'Your data',
  },
};
