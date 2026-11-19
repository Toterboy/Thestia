// Die Texte des Themas 'profile' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fuegt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsProfil = {
  'de': {
    'profile.aboutMe': 'Über mich',
    'profile.ageUnknown': 'Alter unbekannt',
    'profile.appeal.applied': 'Profilbild übernommen.',
    'profile.appeal.approvedBody':
        'Dein Einspruch wurde geprüft: Das Bild ist freigegeben. Möchtest '
        'du es jetzt als Profilbild verwenden?',
    'profile.appeal.approvedTitle': 'Bild freigegeben',
    'profile.appeal.okBtn': 'Verstanden',
    'profile.appeal.rejectedBody':
        'Dein Einspruch wurde geprüft: Das Bild wurde abgelehnt und kann '
        'nicht verwendet werden. Wähle bitte ein anderes Profilbild.',
    'profile.appeal.rejectedTitle': 'Bild abgelehnt',
    'profile.appeal.useBtn': 'Jetzt verwenden',
    'profile.bugReportBtn': 'Bug melden',
    'profile.detail.aboutMe': 'Über mich',
    // Gespeicherte Profile (lokal, max. 5)
    'profile.detail.savedSave': 'Profil lokal speichern (später anschreiben)',
    'profile.detail.blockUser': 'Blockieren',
    'profile.detail.commonWithYou': 'Gemeinsam mit dir',
    'profile.detail.favoriteBand': 'Lieblingsband: {band}',
    'profile.detail.favoriteSong': 'Lieblingssong: {song}',
    'profile.detail.interests': 'Interessen',
    'profile.detail.more': 'Weitere',
    'profile.detail.music': 'Musik',
    'profile.detail.noBio': 'Noch keine Bio.',
    'profile.detail.noMusic': 'Kein Musik-Geschmack angegeben.',
    'profile.detail.photosLockedHint':
        'Fotos erscheinen hier, sobald das Kennenlern-Quiz bestanden ist '
        'und die Person ein Profilbild hochgeladen hat.',
    'profile.detail.reportUser': 'Nutzer melden',
    'profile.detail.retry': 'Erneut versuchen',
    'profile.detail.sameTaste': 'Gleicher Geschmack',
    'profile.detail.savedDone':
        '{name} lokal gespeichert. Du kannst {name} später anschreiben.',
    'profile.detail.savedRemove': 'Gespeichertes Profil entfernen',
    'profile.detail.savedRemoved': '{name} wurde entfernt.',
    'profile.detail.title': 'Profil',
    'profile.detail.type': 'Typ {t}',
    'profile.detail.unavailable': 'Dieses Profil ist derzeit nicht verfügbar.',
    'profile.donateBtn': 'Unterstützen',
    'profile.donateNotConfigured':
        'Für diese App ist noch keine Spendenadresse hinterlegt. '
        'Es wurde nichts abgebucht und nichts verbucht.',
    'profile.donateOpenFailed': 'Die Seite ließ sich nicht öffnen.',
    'profile.donateTitle': 'App unterstützen',
    'profile.edit.appealFailed':
        'Einspruch konnte nicht eingereicht werden. Bitte später erneut.',
    'profile.edit.appealSubmitted':
        'Einspruch eingereicht. Wir benachrichtigen dich über das Ergebnis.',
    'profile.edit.bio': 'Bio',
    'profile.edit.birthDate': 'Geburtsdatum',
    'profile.edit.birthDateHint': 'TT. MM. JJJJ',
    'profile.edit.birthDateLocked':
        'Aus Schutz vor Alters-Täuschung kann das Geburtsdatum nach der '
        'Registrierung nicht mehr geändert werden.',
    'profile.edit.birthDateMissing': 'Bitte wähle dein Geburtsdatum',
    'profile.edit.birthDatePick': 'Bitte auswählen',
    'profile.edit.country': 'Land',
    'profile.edit.distanceKm': 'Entfernung in km',
    'profile.edit.favoriteBand': 'Lieblingsband',
    'profile.edit.favoriteBandHint': 'z. B. Band oder Künstler …',
    'profile.edit.favoriteSong': 'Lieblingssong',
    'profile.edit.favoriteSongHint': 'z. B. Songtitel …',
    'profile.edit.gender': 'Geschlecht',
    'profile.edit.gpsTooltip': 'Standort erkennen (GPS)',
    'profile.edit.habits': 'Gewohnheiten',
    'profile.edit.habitsDealbreaker': 'Dealbreaker: gleicher Konsum',
    'profile.edit.habitsDealbreakerSub':
        'Zeig mir nur Personen, die maximal so viel konsumieren wie ich.',
    'profile.edit.habitsSub':
        'Wie stehst du dazu? Diese Angaben beeinflussen, wen du bei '
        '"Find your Spark" siehst. Es werden nur Personen gezeigt, die '
        'maximal so viel konsumieren wie du.',
    'profile.edit.interests': 'Interessen',
    'profile.edit.location': 'Standort',
    'profile.edit.locationDetected': 'Standort erkannt und übernommen.',
    'profile.edit.locationFailed':
        'Standort konnte nicht ermittelt werden. Bitte gib ihn manuell '
        'ein oder erlaube den Zugriff.',
    'profile.edit.locationSuspicious':
        'Hinweis: Dieser Standort weicht deutlich von deinen bisherigen '
        'Standorten auf diesem Gerät ab.',
    'profile.edit.lookingFor': 'Ich suche',
    'profile.edit.maxAgeLabel': 'Höchstalter',
    'profile.edit.maxDistance': 'Maximale Entfernung: {km} km',
    'profile.edit.minAgeLabel': 'Mindestalter',
    'profile.edit.missingFields':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert).',
    'profile.edit.missingFieldsHint':
        'Es fehlen noch Angaben oder einige Felder sind fehlerhaft (rot '
        'markiert). Bitte prüfe das Formular.',
    'profile.edit.modeGermany': 'Ganz Deutschland',
    'profile.edit.music': 'Musik',
    'profile.edit.musicSub':
        'Welche Musik beschreibt dich? Dein Geschmack fließt in den '
        'Verbindungs-Score ein.',
    'profile.edit.name': 'Name',
    'profile.edit.noGeoLimit':
        'Keine geografische Einschränkung, Suche in ganz Deutschland.',
    'profile.edit.personality': 'Persönlichkeitstest',
    'profile.edit.personalityDone':
        'Du hast den Test abgeschlossen. Du kannst ihn jederzeit '
        'wiederholen.',
    'profile.edit.personalityOpen': 'Zeig anderen, wer du wirklich bist.',
    'profile.edit.personalityRetake': 'Test wiederholen',
    'profile.edit.personalityStart': 'Persönlichkeitstest starten',
    'profile.edit.photoNsfwAppeal': 'Einspruch einlegen',
    'profile.edit.photoNsfwBody':
        'Dieses Bild wurde lokal auf deinem Gerät als potenziell '
        'anstößig eingestuft und wird nicht hochgeladen.',
    'profile.edit.photoNsfwNotUploaded':
        'Das Bild wird nicht als Profilbild hochgeladen.',
    'profile.edit.photoNsfwOther': 'Anderes Bild wählen',
    'profile.edit.photoNsfwTitle': 'Bild nicht freigegeben',
    'profile.edit.photoNsfwUnderstood': 'Verstanden',
    'profile.edit.photoNsfwVerdict': 'Lokaler Befund: {label} ({score} %).',
    'profile.edit.photoOkBody': 'Dein Bild ist okay und kann verwendet werden.',
    'profile.edit.photoOkBtn': 'Weiter',
    'profile.edit.photoOkTitle': 'Bild geprüft',
    'profile.edit.photoUploadError': 'Fehler beim Hochladen: {error}',
    'profile.edit.radiusMinorHint':
        'In deinem Alter gilt höchstens 25 km Radius - oder nur Personen '
        'aus deinem eigenen Bundesland.',
    'profile.edit.radiusMode': 'Suchradius definieren über',
    'profile.edit.rel.casual': 'Lockere Bekanntschaft',
    'profile.edit.rel.dating': 'Ernsthaftes Dating',
    'profile.edit.rel.friends': 'Freundschaft',
    'profile.edit.rel.open': 'Offen für alles',
    'profile.edit.rel.relationship': 'Feste Beziehung',
    'profile.edit.relationship': 'Was suchst du?',
    'profile.edit.saved': 'Profil gespeichert',
    'profile.edit.savedNoSync':
        'Lokal gespeichert. Server-Sync fehlgeschlagen, bitte später '
        'erneut speichern.',
    'profile.edit.state': 'Bundesland',
    'profile.edit.stateHint': 'Bitte wählen',
    'profile.edit.stateNotApplicable':
        'Bundesland entfällt außerhalb Deutschlands.',
    'profile.edit.title': 'Profil bearbeiten',
    'profile.edit.unsavedBody':
        'Deine Profiländerungen wurden noch nicht gespeichert. Was '
        'möchtest du tun?',
    'profile.edit.unsavedDiscard': 'Verwerfen',
    'profile.edit.unsavedTitle': 'Ungespeicherte Änderungen',
    'profile.interests': 'Interessen',
    'profile.intro.audioEmpty': 'Noch keine Audio-Vorstellung hinterlegt.',
    'profile.intro.audioLoadError':
        'Audio-Vorstellung konnte nicht geladen werden.',
    'profile.intro.audioMissing': 'Audio-Vorstellung nicht gefunden.',
    'profile.intro.empty': 'Du hast noch keine Text-Vorstellung hinterlegt.',
    'profile.intro.hint':
        'Andere lernen dich über diese Vorstellung kennen, bevor sie ein Foto sehen. Bearbeiten kannst du sie unter Profil bearbeiten.',
    'profile.intro.listen': 'Audio-Vorstellung anhören',
    // Intro-Editor (Audio-Recorder-UX)
    'intro.title': 'Meine Vorstellung',
    'profile.intro.stop': 'Stopp',
    'profile.intro.title': 'Meine Vorstellung',
    'profile.menu.edit': 'Profil bearbeiten',
    'profile.menu.editSub': 'Daten, Interessen und Vorstellung ändern',
    'profile.menu.introPreview': 'Vorstellung Vorschau',
    'profile.menu.introPreviewSub': 'Deine Text- und Audio-Vorstellung ansehen',
    'profile.menu.preview': 'Profil Vorschau',
    'profile.menu.previewSub': 'So sehen dich andere',
    'profile.newAccountTooltip':
        'Account ist jünger als 7 Tage. Ein Hinweis, kein Beweis.',
    // Startprotokoll: der Bildschirm, der erscheint, wenn der letzte
    // Startversuch gestorben ist. Ohne Computer, ohne Konsole.
    'startupFail.title': 'Startprotokoll',
    'profile.noBio': 'Noch keine Bio.',
    'profile.preview.aboutMe': 'Über mich',
    'profile.preview.hint':
        'So sehen dich andere Nutzer (inkl. Altersschutz & Blind Mode):',
    'profile.preview.interests': 'Interessen',
    'profile.preview.modeBirthday': 'Geburtstag',
    'profile.preview.modeNormal': 'Normal',
    'profile.preview.noBio': 'Noch keine Bio.',
    'profile.preview.note':
        'Hinweis: Die tatsächliche Sichtbarkeit hängt vom Alter und den Einstellungen der jeweiligen Betrachter ab.',
    'profile.preview.photoHidden':
        'Deine Fotos sind aufgrund deiner Einstellungen (Persönlichkeit vor Aussehen / Altersschutz) für andere nicht sichtbar.',
    'profile.preview.title': 'Profil Vorschau',
    'profile.preview.type': 'Typ',
    'profile.profileBtn': 'Profil',
    'profile.qrTooltip': 'Mein QR Code',
    'profile.title': 'Mein Profil',
    'profile.typePrefix': 'Typ',
    // Hinweis auf ein frisches Konto. Bewusst ohne Datum: ein exaktes
    // Erstellungsdatum waere ein Datenleck, und ein Hinweis ist kein
    // Beweis - auch echte neue Nutzer fallen darunter.
    'profile.newAccountBadge': 'Neu',
    'profile.unknown': 'Unbekannt',
    'profile.years': 'Jahre',
  },
  'en': {
    'profile.aboutMe': 'About me',
    'profile.ageUnknown': 'Age unknown',
    'profile.appeal.applied': 'Profile picture updated.',
    'profile.appeal.approvedBody':
        'Your appeal has been reviewed: the image is approved. Would you '
        'like to use it as your profile picture now?',
    'profile.appeal.approvedTitle': 'Image approved',
    'profile.appeal.okBtn': 'Understood',
    'profile.appeal.rejectedBody':
        'Your appeal has been reviewed: the image was rejected and cannot '
        'be used. Please choose a different profile picture.',
    'profile.appeal.rejectedTitle': 'Image rejected',
    'profile.appeal.useBtn': 'Use now',
    'profile.bugReportBtn': 'Report a bug',
    'profile.detail.aboutMe': 'About me',
    // Saved profiles (local, max. 5)
    'profile.detail.savedSave': 'Save profile locally (write later)',
    'profile.detail.blockUser': 'Block',
    'profile.detail.commonWithYou': 'Shared with you',
    'profile.detail.favoriteBand': 'Favorite band: {band}',
    'profile.detail.favoriteSong': 'Favorite song: {song}',
    'profile.detail.interests': 'Interests',
    'profile.detail.more': 'More',
    'profile.detail.music': 'Music',
    'profile.detail.noBio': 'No bio yet.',
    'profile.detail.noMusic': 'No music taste given.',
    'profile.detail.photosLockedHint':
        'Photos appear here once the getting-to-know quiz is passed '
        'and the person has uploaded a profile picture.',
    'profile.detail.reportUser': 'Report user',
    'profile.detail.retry': 'Try again',
    'profile.detail.sameTaste': 'Same taste',
    'profile.detail.savedDone':
        '{name} saved locally. You can write to {name} later.',
    'profile.detail.savedRemove': 'Remove saved profile',
    'profile.detail.savedRemoved': '{name} was removed.',
    'profile.detail.title': 'Profile',
    'profile.detail.type': 'Type {t}',
    'profile.detail.unavailable': 'This profile is currently unavailable.',
    'profile.donateBtn': 'Support',
    'profile.donateNotConfigured':
        'No donation address is configured for this app yet. '
        'Nothing was charged and nothing was booked.',
    'profile.donateOpenFailed': 'The page could not be opened.',
    'profile.donateTitle': 'Support the app',
    'profile.edit.appealFailed':
        'Appeal could not be submitted. Please try again later.',
    'profile.edit.appealSubmitted':
        'Appeal submitted. We will notify you about the decision.',
    'profile.edit.bio': 'Bio',
    'profile.edit.birthDate': 'Date of birth',
    'profile.edit.birthDateHint': 'DD. MM. YYYY',
    'profile.edit.birthDateLocked':
        'To protect against age deception, the birth date cannot be '
        'changed after registration.',
    'profile.edit.birthDateMissing': 'Please choose your date of birth',
    'profile.edit.birthDatePick': 'Please select',
    'profile.edit.country': 'Country',
    'profile.edit.distanceKm': 'Distance in km',
    'profile.edit.favoriteBand': 'Favorite band',
    'profile.edit.favoriteBandHint': 'e.g. band or artist …',
    'profile.edit.favoriteSong': 'Favorite song',
    'profile.edit.favoriteSongHint': 'e.g. song title …',
    'profile.edit.gender': 'Gender',
    'profile.edit.gpsTooltip': 'Detect location (GPS)',
    'profile.edit.habits': 'Habits',
    'profile.edit.habitsDealbreaker': 'Dealbreaker: same consumption',
    'profile.edit.habitsDealbreakerSub':
        'Only show me people who consume at most as much as I do.',
    'profile.edit.habitsSub':
        'How do you feel about these? Your answers influence who you see '
        'in "Find your Spark". Only people who consume at most as much '
        'as you do are shown.',
    'profile.edit.interests': 'Interests',
    'profile.edit.location': 'Location',
    'profile.edit.locationDetected': 'Location detected and applied.',
    'profile.edit.locationFailed':
        'Location could not be determined. Please enter it manually or '
        'grant permission.',
    'profile.edit.locationSuspicious':
        'Note: This location differs greatly from your previous locations '
        'on this device.',
    'profile.edit.lookingFor': 'I am looking for',
    'profile.edit.maxAgeLabel': 'Maximum age',
    'profile.edit.maxDistance': 'Maximum distance: {km} km',
    'profile.edit.minAgeLabel': 'Minimum age',
    'profile.edit.missingFields':
        'Some information is missing or some fields are invalid (marked '
        'in red).',
    'profile.edit.missingFieldsHint':
        'Some information is missing or some fields are invalid (marked '
        'in red). Please check the form.',
    'profile.edit.modeGermany': 'All of Germany',
    'profile.edit.music': 'Music',
    'profile.edit.musicSub':
        'Which music describes you? Your taste flows into the connection '
        'score.',
    'profile.edit.name': 'Name',
    'profile.edit.noGeoLimit':
        'No geographic restriction, searching all of Germany.',
    'profile.edit.personality': 'Personality test',
    'profile.edit.personalityDone':
        'You have completed the test. You can retake it at any time.',
    'profile.edit.personalityOpen': 'Show others who you really are.',
    'profile.edit.personalityRetake': 'Retake test',
    'profile.edit.personalityStart': 'Start personality test',
    'profile.edit.photoNsfwAppeal': 'Appeal',
    'profile.edit.photoNsfwBody':
        'This image was classified on your device as potentially '
        'inappropriate and will not be uploaded.',
    'profile.edit.photoNsfwNotUploaded':
        'This image will not be uploaded as your profile picture.',
    'profile.edit.photoNsfwOther': 'Choose another image',
    'profile.edit.photoNsfwTitle': 'Image not approved',
    'profile.edit.photoNsfwUnderstood': 'Understood',
    'profile.edit.photoNsfwVerdict': 'Local verdict: {label} ({score} %).',
    'profile.edit.photoOkBody': 'Your image is fine and can be used.',
    'profile.edit.photoOkBtn': 'Continue',
    'profile.edit.photoOkTitle': 'Image checked',
    'profile.edit.photoUploadError': 'Upload failed: {error}',
    'profile.edit.radiusMinorHint':
        'At your age, the radius is at most 25 km - or only people from '
        'your own federal state.',
    'profile.edit.radiusMode': 'Define search radius by',
    'profile.edit.rel.casual': 'Casual acquaintance',
    'profile.edit.rel.dating': 'Serious dating',
    'profile.edit.rel.friends': 'Friendship',
    'profile.edit.rel.open': 'Open to anything',
    'profile.edit.rel.relationship': 'Committed relationship',
    'profile.edit.relationship': 'What are you looking for?',
    'profile.edit.saved': 'Profile saved',
    'profile.edit.savedNoSync':
        'Saved locally. Server sync failed, please save again later.',
    'profile.edit.state': 'Federal state',
    'profile.edit.stateHint': 'Please select',
    'profile.edit.stateNotApplicable':
        'Federal state only applies within Germany.',
    'profile.edit.title': 'Edit profile',
    'profile.edit.unsavedBody':
        'Your profile changes have not been saved yet. What would you '
        'like to do?',
    'profile.edit.unsavedDiscard': 'Discard',
    'profile.edit.unsavedTitle': 'Unsaved changes',
    'profile.interests': 'Interests',
    'profile.intro.audioEmpty': 'No audio intro recorded yet.',
    'profile.intro.audioLoadError': 'Audio intro could not be loaded.',
    'profile.intro.audioMissing': 'Audio intro not found.',
    'profile.intro.empty': 'You have not added a text intro yet.',
    'profile.intro.hint':
        'Others get to know you through this intro before they see a photo. You can edit it under Edit profile.',
    'profile.intro.listen': 'Listen to audio intro',
    // Intro editor (audio recorder UX)
    'intro.title': 'My intro',
    'profile.intro.stop': 'Stop',
    'profile.intro.title': 'My intro',
    'profile.menu.edit': 'Edit profile',
    'profile.menu.editSub': 'Change details, interests and intro',
    'profile.menu.introPreview': 'Intro preview',
    'profile.menu.introPreviewSub': 'View your text and audio intro',
    'profile.menu.preview': 'Profile preview',
    'profile.menu.previewSub': 'How others see you',
    'profile.newAccountBadge': 'New',
    'profile.newAccountTooltip':
        'Account is younger than 7 days. An indication, not proof.',
    // Startup log: the screen shown when the last start attempt died.
    'startupFail.title': 'Startup log',
    'profile.noBio': 'No bio yet.',
    'profile.preview.aboutMe': 'About me',
    'profile.preview.hint':
        'This is how other users see you (incl. age protection & blind mode):',
    'profile.preview.interests': 'Interests',
    'profile.preview.modeBirthday': 'Birthday',
    'profile.preview.modeNormal': 'Normal',
    'profile.preview.noBio': 'No bio yet.',
    'profile.preview.note':
        'Note: Actual visibility depends on the age and settings of each viewer.',
    'profile.preview.photoHidden':
        'Your photos are not visible to others due to your settings (personality first / age protection).',
    'profile.preview.title': 'Profile preview',
    'profile.preview.type': 'Type',
    'profile.profileBtn': 'Profile',
    'profile.qrTooltip': 'My QR code',
    'profile.title': 'My profile',
    'profile.typePrefix': 'Type',
    'profile.unknown': 'Unknown',
    'profile.years': 'years',
  },
};
