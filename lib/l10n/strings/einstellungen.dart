// Die Texte des Themas 'settings' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fuegt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsEinstellungen = {
  'de': {
    'paused.homeBody':
        'Du bist für neue Personen unsichtbar. Tippen zum Entpausieren.',
    'paused.homeTitle': 'Dein Profil ist pausiert',
    'paused.popupBody':
        'Solange dein Profil pausiert ist, kannst du keine Entdecken-Modi '
        'nutzen. Beende die Pause in den Einstellungen, um weiterzumachen.',
    'paused.popupTitle': 'Profil pausiert',
    'paused.toSettings': 'Zu den Einstellungen',

    // ===================================================================
    // Elternfreigabe und Aufsicht (v0.10.0)
    // ===================================================================
    'location.disclosureTitle': 'Standort freigeben?',
    'settings.appearance': 'Darstellung',
    // AppearanceSelector: Wert + Erklaerung je Modus. Die Erklaerung
    // sagt, was die Wahl TUT - das unterscheidet 'System' (folgt dem
    // Geraet) von 'Hell'/'Dunkel' (erzwingen etwas). Ohne das sind drei
    // gleich aussehende Zeilen, in denen die Voreinstellung nicht von
    // einer bewussten Entscheidung unterscheidbar ist.
    'appearance.light': 'Hell',
    'settings.backupChoosePw': 'Backup-Passwort wählen',
    'settings.backupCodeTitle': 'Dein Backup-Code',
    'settings.backupCopied': 'Backup-Code kopiert.',
    'settings.backupCreate': 'Backup erstellen',
    'settings.backupCreateBtn': 'Backup erstellen',
    'settings.backupCreateFailed': 'Backup konnte nicht erstellt werden.',
    'settings.backupCreateSub': 'Erzeugt einen verschlüsselten Code',
    'settings.backupKeepSafe':
        'Bewahre Code UND Passwort sicher auf (z. B. Passwort-Manager). '
        'Ohne beides ist eine Wiederherstellung unmöglich.',
    'settings.backupPasteCode': 'Backup-Code einfügen',
    'settings.backupPwMismatch': 'Passwörter stimmen nicht überein',
    'settings.backupPwRepeat': 'Passwort wiederholen',
    'settings.backupPwShort': 'Zu kurz (min. 8)',
    'settings.backupRestore': 'Backup wiederherstellen',
    'settings.backupRestoreSub': 'Überschreibt die aktuelle E2E-Identität',
    'settings.blur': 'Bilder verpixelt anzeigen',
    'settings.blurSub':
        'Schutz vor unangemessenen Inhalten: Bilder deiner Gegenstelle '
        'werden erst nach Bestätigung gezeigt (lang drücken zum Melden).',
    'settings.chatBg': 'Chat-Hintergrund',
    'settings.chatBgSub':
        'Muster oder eigenes Bild für deine Chats. Gilt für alle Chats.',
    'settings.chatSafety': 'Chat, Verlauf & Datenschutz',
    'settings.codeInvalid': 'Ungültiger oder abgelaufener Code.',
    'settings.colors': 'Farbwelt',
    'settings.communityRules': 'Community Regeln',
    'settings.communityRulesSub': 'Respektvoller Umgang & Verhaltensregeln',
    'settings.communitySafety': 'Community & Sicherheit',
    'settings.delete': 'Löschen',
    'settings.deleteData': 'Daten löschen',
    'settings.deleteDataSub':
        'Einzelne Daten löschen, ohne das Konto aufzugeben.',
    'settings.deleteFailed': 'Löschen fehlgeschlagen.',
    'settings.devices': 'Angemeldete Geräte',
    'settings.devicesSub': 'Wo bin ich eingeloggt? Überall abmelden',
    'settings.e2e': 'E2E-Identität',
    'settings.keyBackup': 'Verschlüsseltes Key-Backup',
    'settings.keyBackupSub':
        'Sichert die private Identität deiner Ende-zu-Ende-Verschlüsselung '
        '(passwortverschlüsselt, AES-256-GCM). Nur damit kannst du nach '
        'Gerätewechsel wieder verschlüsselt chatten. Verlust von Backup '
        'UND Passwort ist unwiederbringlich.',
    'settings.language': 'Sprache',
    'settings.localDataNote':
        'Deine Daten werden nur lokal auf diesem Gerät gespeichert. Es '
        'werden keine unnötigen Berechtigungen angefordert.',
    'settings.logout': 'Abmelden',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privatsphäre',
    'settings.notifications': 'Benachrichtigungen',
    'settings.notifyDatingHour': 'Dating Hour Erinnerung',
    'settings.notifyDatingHourSub': '10 Minuten vor Beginn, wenn du dabei bist',
    'settings.notifyFunken': 'Neue Funken',
    'settings.notifyFunkenSub': 'Wenn ein Funke entsteht',
    'settings.notifyLikes': 'Neue Likes',
    'settings.notifyLikesSub': 'Wenn dich jemand liked',
    'settings.notifyMessages': 'Chat Nachrichten',
    'settings.notifyMessagesSub': 'Wenn dir jemand schreibt',
    'settings.passkeyCreate': 'Passkey erstellen',
    'settings.passkeyCreateSub':
        'Biometrischer Login (FaceID/TouchID) ohne Passwort',
    'settings.passkeyCreated': 'Passkey wurde erstellt.',
    'settings.passkeyCreatedAt': 'Erstellt {date}',
    'settings.passkeyDeleteTitle': 'Passkey löschen?',
    'settings.passkeyDeleted': 'Passkey gelöscht.',
    'settings.passkeyExistsAbort': 'Abbrechen',
    'settings.passkeyExistsBody':
        'Auf deinem Konto sind bereits {count} Passkey(s) registriert. '
        'Wenn das Anlegen wieder an der Server-Bestätigung scheitert, '
        'lösche die alten Einträge unter "Passkeys verwalten" und '
        'versuche es erneut.\n\nTrotzdem einen weiteren Passkey '
        'erstellen?',
    'settings.passkeyExistsContinue': 'Weiter erstellen',
    'settings.passkeyFailed': 'Passkey-Erstellung fehlgeschlagen.',
    // Passkey-Bestaetigungs-/Fehlertexte (Services ohne BuildContext)
    'passkey.err.cancelledRegister': 'Passkey-Einrichtung abgebrochen.',
    'settings.passkeyLastUsed': 'Zuletzt genutzt {date}',
    'settings.passkeyRename': 'Umbenennen',
    'settings.passkeyWaitConfirm': 'Warte auf Bestätigung …',
    // "Passkeys verwalten"-Karte
    'passkey.name': 'Passkey',
    'settings.passkeysManage': 'Passkeys verwalten',
    'settings.pauseConfirmBody':
        'Dein Profil wird in Entdecken und Find your Spark nicht mehr '
        'angezeigt. Bestehende Funken und Chats bleiben bestehen. Du kannst '
        'die Pause jederzeit beenden.',
    'settings.pauseConfirmBtn': 'Pausieren',
    'settings.pauseConfirmTitle': 'Profil pausieren?',
    'settings.pauseOff': 'Pause beendet. Dein Profil ist wieder sichtbar.',
    'settings.pauseOn':
        'Profil pausiert. Du bist unsichtbar, bis du die Pause beendest.',
    'settings.privacyAccount': 'Datenschutz & Account',
    'settings.privacyAccountSub':
        'Gespeicherte Daten, Einwilligungen, Account löschen',
    'settings.push': 'Push Benachrichtigungen',
    'settings.pushEnable': 'Benachrichtigungen aktivieren',
    'settings.pushEnableSub':
        'Nachrichten, Likes, Funken und Event Erinnerungen',
    'settings.restoreBtn': 'Wiederherstellen',
    'settings.restoreConfirmTitle': 'Identität wiederherstellen?',
    'settings.restoreEnterTitle': 'Backup eingeben',
    'settings.restoreFailed':
        'Wiederherstellung fehlgeschlagen. Prüfe Code und Passwort.',
    'settings.restoreOverwrite':
        'Die aktuelle E2E-Identität auf diesem Gerät wird ÜBERSCHRIEBEN '
        '(bestehende verschlüsselte Sitzungen gehen verloren). Verwende nur '
        'ein Backup deines eigenen Kontos.',
    'settings.restorePw': 'Backup-Passwort',
    'settings.restored': 'E2E-Identität wiederhergestellt.',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Hilfe bei Belästigung oder Stalking, Blockieren, Melden',
    // Datenschutz & Account
    'privacy.title': 'Datenschutz & Account',
    'settings.saveFailed':
        'Die Einstellung konnte nicht gespeichert werden. Bitte einmal neu versuchen.',
    'settings.showDistance': 'Entfernung anzeigen',
    // NUTZERWUNSCH (22.11.2026): Die Punkte und die Gewohnheiten
    // einzeln fuer das oeffentliche Profil an- und auschalten.
    'settings.showFavoriteBand': 'Lieblings-Künstler',
    'settings.showFavoriteSong': 'Lieblingssong',
    'settings.showHabitsAlcohol': 'Alkohol',
    'settings.showHabitsDrugs': 'Drogen',
    'settings.showHabitsSmoking': 'Rauchen',
    'settings.showMusicDisliked': 'Abgelehnte Musik-Genres',
    'settings.showMusicLiked': 'Gemagte Musik-Genres',
    'settings.publicProfileFields': 'Was andere über mich sehen',
    'settings.publicProfileFieldsSub':
        'Diese Angaben stehen in deinem öffentlichen Profil. Du '
        'kannst jeden Punkt einzeln abschalten.',
    'settings.showDistanceSub':
        'Zeigt anderen nur ungefähr, wie weit weg du bist - in Stufen '
        'von 10 km. Aus ist der Standard; dein genauer Standort bleibt '
        'immer privat.',
    'settings.showDistanceSubMinor':
        'In deinem Alter bleibt die Entfernung aus. Der genaue Standort '
        'bleibt ohnehin immer privat - und in deinem Umfeld wäre die '
        'ungefähre Angabe mehr, als sie sein sollte.',
    'settings.twoFactor': 'Zwei-Faktor-Schutz (2FA)',
    'settings.twoFactorActive': 'Aktiv: Login nur mit Authenticator-Code',
    'settings.twoFactorSetup': 'Login zusätzlich mit Authenticator-App sichern',
    'settings.unifiedPush': 'Push ohne Google (UnifiedPush)',
    'settings.unifiedPushOff':
        'Benötigt eine Distributor-App wie ntfy (F-Droid). FCM bleibt in '
        'der Play-Variante aktiv.',
    'settings.unifiedPushOn': 'Aktiv - Endpunkt ist hinterlegt.',
    'settings.visEveryone': 'Jeder',
    'settings.visEveryoneSub':
        'Dein Profil erscheint in Entdecken und Find your Spark.',
    'settings.visHidden': 'Unsichtbar (Pausiert)',
    'settings.visHiddenSub':
        'Pausenmodus: unsichtbar für alle neuen Personen. Funken und Chats '
        'bleiben bestehen.',
    'settings.visMatchesOnly': 'Nur Funken',
    'settings.visMatchesSub':
        'Nur Personen, mit denen du einen Funken hast, sehen dein Profil.',
    'settings.whoCanSee': 'Wer kann mein Profil sehen?',
    'setup.abortBody':
        'Möchtest du die Einrichtung wirklich abbrechen? Deine bisherigen '
        'Angaben werden gespeichert.',
    'setup.abortContinue': 'Weiter machen',
    'setup.appbarTitle': 'Einstellungen & Privatsphäre',
    'setup.birthdaySub':
        'Einmal im Jahr, an einem einzigen Tag. Waehle eine Richtung.',
    'setup.filterSub': 'Wen möchtest du kennenlernen?',
    'setup.flagsWarn':
        'Hinweis: Der Einrichtungs-Stand konnte nicht auf dem Server '
        'gesichert werden. Die Einrichtung erscheint beim nächsten Login '
        'möglicherweise erneut.',
    'setup.hintBio': 'Bitte schreibe eine kurze Bio (Über mich).',
    'setup.hintInterests': 'Bitte wähle mindestens ein Interesse.',
    'setup.hintIntro':
        'Deine Vorstellung braucht Text UND Audio. Andere sollen dich '
        'kennenlernen, bevor sie dein Foto sehen.',
    'setup.locationDetectFail':
        'Standort konnte nicht ermittelt werden. Bitte gib ihn manuell ein '
        'oder erlaube den Zugriff.',
    'setup.locationDone': 'Bundesland erkannt und übernommen.',
    // v0.10.0: GPS ohne Geocoder-Treffer. Nicht raten: das Bundesland
    // bleibt leer und der Nutzer wählt es von Hand aus der Liste.
    'setup.locationStateUnknown':
        'Dein Bundesland wurde nicht erkannt. Bitte wähle es unten aus.',
    'setup.locationError': 'Fehler bei der Standortermittlung: {error}',
    // Setup: Seiten-Inhalte
    'setupp.visibilitySub':
        'Wer darf dein Profil sehen? Wie soll die App aussehen?',
    'setup.locationSuspicious':
        'Hinweis: Dieser Standort weicht deutlich von deinen bisherigen '
        'Standorten auf diesem Gerät ab. Falls das stimmt, wähle ihn '
        'trotzdem - andernfalls gib deinen Ort bitte manuell ein.',
    'setup.musicSub': 'Gemaeckte, die du magst und solche, die du nicht magst.',
    'setup.nudgeBody':
        'Sichere dein Konto jetzt mit einem Passkey oder der '
        'Zwei-Faktor-Authentisierung. Ohne zweiten Faktor kann jeder '
        'mit deinem Passwort dein Konto übernehmen. Bei einer '
        'Dating-App besonders heikel.',
    'setup.nudgeMfa': '2FA einrichten',
    'setup.nudgePasskey': 'Passkey einrichten',
    'setup.nudgeSkip': 'Trotzdem fortfahren',
    'setup.passkeyAlreadyThere': 'Passkey ist schon eingerichtet.',
    // Erst-Einrichtung als Interview (Thestia-Fragen-Bubbles)
    'setupq.visibility':
        'Wie privat magst du bleiben, und wie soll die App aussehen?',
    // Setup: Dialoge, Validierung, Status
    'setup.abortTitle': 'Einrichtung abbrechen?',
    'setup.passkeyDone':
        'Passkey eingerichtet. Du kannst dich künftig damit anmelden.',
    'setup.photoTooltip': 'Profilbild wählen',
    'setup.pleasePick': 'Bitte wählen',
    'setup.stepOf': 'Schritt {n} von {of}',
    'setupp.appearance': 'Darstellung',
    'setupp.bioHint': 'z. B. Hobbys, was dir wichtig ist',
    'setupp.bioLabel': 'Über mich (Bio)',
    'setupp.changeLater':
        'Diese Einstellungen kannst du später jederzeit in den '
        'Einstellungen ändern.',
    // Interessen-Tab
    'interests.title': 'Interessen',
    'setupp.colorWorld': 'Farbwelt',
    'setupp.countryLabel': 'Land',
    'setupp.distance': 'Entfernung',
    'setupp.filterLabel': 'Filter',
    'setupp.finish': "Akzeptieren & los geht's",
    'setupp.germanyNote': 'Es werden Profile aus ganz Deutschland angezeigt.',
    // v0.10.0: Es wird kein Ort mehr abgefragt, nur das Bundesland.
    'setupp.detectState': 'Mein Bundesland automatisch erkennen',
    'setupp.guidelinesBan':
        'Verstöße führen zu Verwarnung bis zur dauerhaften Sperrung.',
    'setupp.guidelinesIntroBody':
        'Diese App lebt von einem respektvollen, wertschätzenden Umgang '
        'miteinander, unabhängig von Herkunft, Geschlecht, Religion oder '
        'Lebensentwurf.',
    'setupp.guidelinesIntroTitle': 'Wertegemeinschaft',
    'setupp.guidelinesSub':
        'Bitte akzeptiere die Regeln der App, um fortzufahren.',
    'setupp.guidelinesWarn':
        'Bei Verstoß kann der Zugang dauerhaft gesperrt werden.',
    'setupp.habitsHint':
        'Es werden nur Personen gezeigt, die maximal so viel konsumieren '
        'wie du. Du kannst das später in den Einstellungen oder im Profil '
        'ändern.',
    'setupp.habitsSub':
        'Wie stehst du zu Rauchen, Alkohol und Drogen? Diese Angaben '
        'beeinflussen, wen du bei "Find your Spark" siehst.',
    'setupp.introSub':
        'Erzähl von dir, als Text und gesprochen. Beides wird anderen '
        'gezeigt, bevor sie dein Foto sehen. Du kannst den Schritt mit '
        '"Überspringen" auch auslassen.',
    'setupp.laterHint':
        'Du kannst die Einrichtung jederzeit später in den Einstellungen '
        'nachholen.',
    'setupp.lookingFor': 'Ich suche',
    'setupp.maxDistance': 'Maximale Entfernung: {km} km',
    'setupp.mfaActive':
        'Zwei-Faktor-Schutz ist aktiv. Bei jedem Login wirst du nach dem '
        'Code aus deiner Authenticator-App gefragt.',
    'setupp.mfaBody':
        'Ein zweiter Faktor schützt dein Konto, selbst wenn dein Passwort '
        'gestohlen wird. Du brauchst eine Authenticator-App (z. B. Google '
        'Authenticator, Aegis oder 2FAS).',
    'setupp.mfaDone': '2FA eingerichtet',
    'setupp.mfaStart': 'Jetzt einrichten',
    'setupp.passkeyBody':
        'Ein Passkey ist die sicherste und bequemste Anmeldeart: Kein '
        'Passwort, das du merken oder vergessen kannst, und schwerer zu '
        'stehlen als ein Passwort.',
    'setupp.passkeyDone': 'Passkey eingerichtet',
    'setupp.passkeyStart': 'Passkey jetzt einrichten',
    'setupp.passkeySub':
        'Melde dich künftig ohne Passwort an, per Fingerabdruck oder '
        'Gesicht. Optional, du kannst diesen Schritt überspringen.',
    'setupp.photoDone': 'Profilbild hochgeladen.',
    'setupp.photoFail':
        'Upload fehlgeschlagen. Du kannst das Bild jederzeit später im '
        'Profil festlegen.',
    'setupp.profileSub':
        'Ein Bild, ein paar Worte über dich und deine Interessen helfen '
        'anderen, dich kennenzulernen. Bio und mindestens ein Interesse '
        'braucht die App - alles Weitere kannst du später ändern.',
    'setupp.radiusMinorHint':
        'In deinem Alter gilt höchstens 25 km Radius - oder nur Personen '
        'aus deinem eigenen Bundesland.',
    'setupp.relType': 'Beziehungsart',
    'setupp.stateLabel': 'Bundesland',
    'setupp.stateOptional': 'Bundesland (optional)',
    'setupq.filter': 'Wonach soll Thestia jemanden für dich suchen?',
    'setupq.guidelines':
        'Magst du unsere Wertegemeinschaft und ihre Regeln akzeptieren?',
    // Passkey-Einrichtung in der Erst-Einrichtung
    'setup.passkeySetupFailed':
        'Passkey-Setup fehlgeschlagen oder abgebrochen. Du kannst es '
        'später jederzeit in den Einstellungen nachholen.',
    // Sicherheitshinweis vor dem Abschluss
    'setup.nudgeTitle': 'Dringend empfohlen',
    'setupq.habits': 'Wie stehst du zu Rauchen, Alkohol und Drogen?',
    // v0.10.0: Geburtstags-Stil als eigene Seite der Einrichtung.
    'setupq.birthday': 'Wie soll dein Profil an deinem Geburtstag aussehen?',
    'setupq.intro': 'Wie klingst du? Erzähl von dir, als Text und gesprochen.',
    'setupq.mfa': 'Magst du zusätzlich einen zweiten Faktor einrichten?',
    'setupq.music': 'Was hoerst du gern?',
    'setupq.passkey':
        'Magst du dein Konto mit einem Passkey absichern? Geht schnell.',
    'setupq.profile':
        'Was macht dich aus? Ein Bild, ein paar Worte, deine Interessen.',
  },
  'en': {
    'paused.homeBody': 'You are invisible to new people. Tap to unpause.',
    'paused.homeTitle': 'Your profile is paused',
    'paused.popupBody':
        'While your profile is paused, you cannot use Discovery modes. '
        'End the pause in settings to continue.',
    'paused.popupTitle': 'Profile paused',
    'paused.toSettings': 'To settings',

    // ===================================================================
    // Guardian consent and supervision (v0.10.0)
    // ===================================================================
    'location.disclosureTitle': 'Share your location?',
    'settings.appearance': 'Appearance',
    'settings.backupChoosePw': 'Choose backup password',
    'settings.backupCodeTitle': 'Your backup code',
    'settings.backupCopied': 'Backup code copied.',
    'settings.backupCreate': 'Create backup',
    'settings.backupCreateBtn': 'Create backup',
    'settings.backupCreateFailed': 'Backup could not be created.',
    'settings.backupCreateSub': 'Generates an encrypted code',
    'settings.backupKeepSafe':
        'Keep the code AND password safe (e.g. password manager). '
        'Without both, restore is impossible.',
    'settings.backupPasteCode': 'Paste backup code',
    'settings.backupPwMismatch': 'Passwords do not match',
    'settings.backupPwRepeat': 'Repeat password',
    'settings.backupPwShort': 'Too short (min. 8)',
    'settings.backupRestore': 'Restore backup',
    'settings.backupRestoreSub': 'Overwrites the current E2E identity',
    'settings.blur': 'Show pictures pixelated',
    'settings.blurSub':
        'Protection from inappropriate content: images from your match are '
        'only shown after confirmation (long press to report).',
    'settings.chatBg': 'Chat background',
    'settings.chatBgSub':
        'Pattern or own picture for your chats. Applies to all chats.',
    'settings.chatSafety': 'Chat, history & privacy',
    'settings.codeInvalid': 'Invalid or expired code.',
    'settings.colors': 'Color scheme',
    'settings.communityRules': 'Community rules',
    'settings.communityRulesSub': 'Respectful conduct & rules of behavior',
    'settings.communitySafety': 'Community & safety',
    'settings.delete': 'Delete',
    'settings.deleteData': 'Delete data',
    'settings.deleteDataSub':
        'Delete individual pieces of data without giving up your account.',
    'settings.deleteFailed': 'Deletion failed.',
    'settings.devices': 'Signed-in devices',
    'settings.devicesSub': 'Where am I logged in? Sign out everywhere',
    'settings.e2e': 'E2E identity',
    'settings.keyBackup': 'Encrypted key backup',
    'settings.keyBackupSub':
        'Backs up the private identity of your end-to-end encryption '
        '(password-encrypted, AES-256-GCM). Only with it can you chat '
        'encrypted again after switching devices. Losing both backup AND '
        'password is irreversible.',
    'settings.language': 'Language',
    'settings.localDataNote':
        'Your data is stored only locally on this device. No unnecessary '
        'permissions are requested.',
    'settings.logout': 'Log out',
    // Settings (Vollständigkeit)
    'settings.privacySection': 'Privacy',
    'settings.notifications': 'Notifications',
    'settings.notifyDatingHour': 'Dating Hour reminder',
    'settings.notifyDatingHourSub': '10 minutes before start, if joined',
    'settings.notifyFunken': 'New sparks',
    'settings.notifyFunkenSub': 'When a spark is created',
    'settings.notifyLikes': 'New likes',
    'settings.notifyLikesSub': 'When someone likes you',
    'settings.notifyMessages': 'Chat messages',
    'settings.notifyMessagesSub': 'When someone writes to you',
    'settings.passkeyCreate': 'Create passkey',
    'settings.passkeyCreateSub':
        'Biometric login (FaceID/TouchID) without a password',
    'settings.passkeyCreated': 'Passkey created.',
    'settings.passkeyCreatedAt': 'Created {date}',
    'settings.passkeyDeleteTitle': 'Delete passkey?',
    'settings.passkeyDeleted': 'Passkey deleted.',
    'settings.passkeyExistsAbort': 'Cancel',
    'settings.passkeyExistsBody':
        'Your account already has {count} passkey(s) registered. If '
        'creating another one keeps failing at server confirmation, '
        'delete the old entries under "Manage passkeys" and try '
        'again.\n\nCreate another passkey anyway?',
    'settings.passkeyExistsContinue': 'Create anyway',
    'settings.passkeyFailed': 'Passkey creation failed.',
    // Passkey confirmation / error texts (services without BuildContext)
    'passkey.err.cancelledRegister': 'Passkey setup cancelled.',
    'settings.passkeyLastUsed': 'Last used {date}',
    'settings.passkeyRename': 'Rename',
    'settings.passkeyWaitConfirm': 'Waiting for confirmation …',
    // "Manage passkeys" card
    'passkey.name': 'Passkey',
    'settings.passkeysManage': 'Manage passkeys',
    'settings.pauseConfirmBody':
        'Your profile will no longer appear in Discovery and Find your '
        'Match. Existing sparks and chats remain. You can end the pause '
        'at any time.',
    'settings.pauseConfirmBtn': 'Pause',
    'settings.pauseConfirmTitle': 'Pause profile?',
    'settings.pauseOff': 'Pause ended. Your profile is visible again.',
    'settings.pauseOn':
        'Profile paused. You are invisible until you end the pause.',
    'settings.privacyAccount': 'Privacy & account',
    'settings.privacyAccountSub': 'Stored data, consents, delete account',
    'settings.push': 'Push notifications',
    'settings.pushEnable': 'Enable notifications',
    'settings.pushEnableSub': 'Messages, likes, sparks and event reminders',
    'settings.restoreBtn': 'Restore',
    'settings.restoreConfirmTitle': 'Restore identity?',
    'settings.restoreEnterTitle': 'Enter backup',
    'settings.restoreFailed': 'Restore failed. Check code and password.',
    'settings.restoreOverwrite':
        'The current E2E identity on this device will be OVERWRITTEN '
        '(existing encrypted sessions are lost). Only use a backup of '
        'your own account.',
    'settings.restorePw': 'Backup password',
    'settings.restored': 'E2E identity restored.',
    'settings.safetyCenter': 'Safety Center',
    'settings.safetyCenterSub':
        'Help with harassment or stalking, blocking, reporting',
    // Privacy & account
    'privacy.title': 'Privacy & account',
    'settings.saveFailed': 'The setting could not be saved. Please try again.',
    'settings.showDistance': 'Show distance',
    // NUTZERWUNSCH (22.11.2026): Die Punkte und die Gewohnheiten
    // einzeln fuer das oeffentliche Profil an- und auschalten.
    'settings.showFavoriteBand': 'Favourite artist',
    'settings.showFavoriteSong': 'Favourite song',
    'settings.showHabitsAlcohol': 'Alcohol',
    'settings.showHabitsDrugs': 'Drugs',
    'settings.showHabitsSmoking': 'Smoking',
    'settings.showMusicDisliked': 'Music genres I dislike',
    'settings.showMusicLiked': 'Music genres I like',
    'settings.publicProfileFields': 'What others see about me',
    'settings.publicProfileFieldsSub':
        'These details appear in your public profile. You can switch off '
        'each one separately.',
    'settings.showDistanceSub':
        'Shows others roughly how far away you are, in 10 km steps. '
        'Off by default; your exact location stays private.',
    'settings.showDistanceSubMinor':
        'At your age, the distance stays off. Your exact location is '
        'private either way - and in your surroundings, an approximate '
        'figure would tell more than it should.',
    'settings.title': 'Settings',
    'settings.twoFactor': 'Two-factor protection (2FA)',
    'settings.twoFactorActive': 'Active: login only with authenticator code',
    'settings.twoFactorSetup': 'Secure your login with an authenticator app',
    'settings.unifiedPush': 'Push without Google (UnifiedPush)',
    'settings.unifiedPushOff':
        'Requires a distributor app like ntfy (F-Droid). FCM stays active '
        'in the Play variant.',
    'settings.unifiedPushOn': 'Active - endpoint registered.',
    'settings.visEveryone': 'Everyone',
    'settings.visEveryoneSub':
        'Your profile appears in Discovery and Find your Spark.',
    'settings.visHidden': 'Invisible (paused)',
    'settings.visHiddenSub':
        'Pause mode: invisible to all new people. Sparks and chats remain.',
    'settings.visMatchesOnly': 'Sparks only',
    'settings.visMatchesSub':
        'Only people you have a spark with can see your profile.',
    'settings.whoCanSee': 'Who can see my profile?',
    'setup.abortBody':
        'Do you really want to cancel the setup? Your entries so far are '
        'saved.',
    'setup.abortContinue': 'Keep going',
    'setup.appbarTitle': 'Settings & privacy',
    'setup.birthdaySub': 'Once a year, on a single day. Pick a direction.',
    'setup.filterSub': 'Who would you like to meet?',
    'setup.flagsWarn':
        'Note: The setup state could not be saved to the server. The setup '
        'may appear again on your next login.',
    'setup.hintBio': 'Please write a short bio (about me).',
    'setup.hintInterests': 'Please pick at least one interest.',
    'setup.hintIntro':
        'Your intro needs text AND audio. Others should get to know you '
        'before they see your photo.',
    'setup.locationDetectFail':
        'Location could not be detected. Please enter it manually or grant '
        'access.',
    'setup.locationDone': 'State detected and applied.',
    // v0.10.0: GPS without a geocoder hit. Not guessed: the state stays
    // empty and the user picks it from the list.
    'setup.locationStateUnknown':
        'Your state could not be detected. Please pick it below.',
    'setup.locationError': 'Location detection failed: {error}',
    // Setup: page content
    'setupp.visibilitySub':
        'Who may see your profile? How should the app look?',
    'setup.locationSuspicious':
        'Note: This location differs clearly from your previous locations '
        'on this device. If that is correct, choose it anyway - otherwise '
        'please enter your place manually.',
    'setup.musicSub': 'Tastes you enjoy, and ones you would rather skip.',
    'setup.nudgeBody':
        'Secure your account now with a passkey or two-factor '
        'authentication. Without a second factor anyone with your '
        'password can take over your account - especially risky for a '
        'dating app.',
    'setup.nudgeMfa': 'Set up 2FA',
    'setup.nudgePasskey': 'Set up passkey',
    'setup.nudgeSkip': 'Continue anyway',
    'setup.passkeyAlreadyThere': 'Passkey is already set up.',
    // One-time setup as interview (Thestia question bubbles)
    'setupq.visibility':
        'How private would you like to stay - and how should the app look?',
    'setup.passkeyDone': 'Passkey set up. You can now sign in with it.',
    'setup.photoTooltip': 'Choose profile picture',
    'setup.pleasePick': 'Please choose',
    'setup.stepOf': 'Step {n} of {of}',
    'setupp.appearance': 'Appearance',
    'setupp.bioHint': 'e.g. hobbies, what matters to you',
    'setupp.bioLabel': 'About me (bio)',
    'setupp.changeLater':
        'You can change these settings any time later in the settings.',
    // Interests tab
    'interests.title': 'Interests',
    'setupp.colorWorld': 'Color scheme',
    'setupp.countryLabel': 'Country',
    'setupp.distance': 'Distance',
    'setupp.filterLabel': 'Filter',
    'setupp.finish': 'Accept & let\'s go',
    'setupp.germanyNote': 'Profiles from all over Germany are shown.',
    // v0.10.0: No city is asked for any more, only the state.
    'setupp.detectState': 'Detect my state automatically',
    'setupp.guidelinesBan':
        'Violations lead to warnings up to a permanent ban.',
    'setupp.guidelinesIntroBody':
        'This app thrives on respectful, appreciative interaction, '
        'regardless of origin, gender, religion or way of life.',
    'setupp.guidelinesIntroTitle': 'Community of values',
    'setupp.guidelinesSub': 'Please accept the app\'s rules to continue.',
    'setupp.guidelinesWarn':
        'In case of violations access can be blocked permanently.',
    'setupp.habitsHint':
        'Only people who consume at most as much as you are shown. You can '
        'change this later in settings or in your profile.',
    'setupp.habitsSub':
        'How do you feel about smoking, alcohol and drugs? These answers '
        'influence who you see in "Find your Spark".',
    'setupp.introSub':
        'Tell people about yourself, in text and out loud. Both are shown '
        'before they see your photo. You can skip this step with '
        '"Skip".',
    'setupp.laterHint':
        'You can complete the setup any time later in the settings.',
    'setupp.lookingFor': 'I am looking for',
    'setupp.maxDistance': 'Maximum distance: {km} km',
    'setupp.mfaActive':
        'Two-factor protection is active. Every sign-in will ask for the '
        'code from your authenticator app.',
    'setupp.mfaBody':
        'A second factor protects your account even if your password is '
        'stolen. You need an authenticator app (e.g. Google Authenticator, '
        'Aegis or 2FAS).',
    'setupp.mfaDone': '2FA set up',
    'setupp.mfaStart': 'Set up now',
    'setupp.passkeyBody':
        'A passkey is the most secure and convenient sign-in method: no '
        'password to remember or forget, and harder to steal than a '
        'password.',
    'setupp.passkeyDone': 'Passkey set up',
    'setupp.passkeyStart': 'Set up passkey now',
    'setupp.passkeySub':
        'Sign in without a password in the future, via fingerprint or face. '
        'Optional, you can skip this step.',
    'setupp.photoDone': 'Profile photo uploaded.',
    'setupp.photoFail':
        'Upload failed. You can set the photo later in your profile.',
    'setupp.profileSub':
        'A photo, a few words about you and your interests help others '
        'get to know you. The app needs a bio and at least one interest '
        '- everything else you can change later.',
    'setupp.radiusMinorHint':
        'At your age, the radius is at most 25 km - or only people from '
        'your own federal state.',
    'setupp.relType': 'Relationship type',
    'setupp.stateLabel': 'Federal state',
    'setupp.stateOptional': 'Federal state (optional)',
    'setupq.filter': 'What should Thestia search for on your behalf?',
    'setupq.guidelines':
        'Would you like to accept our community of values and its rules?',
    // Passkey setup during one-time setup
    'setup.passkeySetupFailed':
        'Passkey setup failed or was cancelled. You can do it later any '
        'time in the settings.',
    // Security nudge before finishing
    'setup.nudgeTitle': 'Strongly recommended',
    'setupq.habits': 'How do you feel about smoking, alcohol and drugs?',
    // v0.10.0: birthday style as its own setup page.
    'setupq.birthday': 'How should your profile look on your birthday?',
    'setupq.intro':
        'How do you sound? Tell about yourself - in text and voice.',
    'setupq.mfa': 'Would you like to add a second factor on top?',
    'setupq.music': 'What do you like to listen to?',
    'setupq.passkey':
        'Would you like to secure your account with a passkey? It is quick.',
    'setupq.profile':
        'What makes you you? A photo, a few words, your interests.',
  },
};
