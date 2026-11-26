// Die Texte des Themas 'vorstellung' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsVorstellung = {
  'de': {
    'interests.alreadySpark': 'Ihr habt schon einen Funken',
    'interests.archiveSpark': 'Archivieren',
    'interests.archiveSparkDone': 'Funke archiviert.',
    'interests.coolBtn': 'Funke kühlen',
    'interests.cooledDone': 'Funke mit {name} gekühlt.',
    'interests.cooledSub':
        'Funken, die eine Weile ruhen. Der Chat bleibt erhalten - jederzeit '
        'wieder entzündbar.',
    'interests.cooledTitle': 'Archivierte Funken',
    'interests.decline': 'Ignorieren',
    'interests.deleteSavedBody':
        '{name} wird lokal gelöscht. Der zugehörige Chat-Verlauf geht damit '
        'verloren.',
    // QR-Flow
    'qr.menuTitle': 'Mit anderen verbinden',
    'interests.deleteSavedTitle': 'Gespeichertes Profil entfernen?',
    'interests.deleteSpark': 'Funke löschen',
    'interests.deleteSparkBody':
        'Der Funke verschwindet aus deiner Liste. Der Chat bleibt erhalten, '
        'der Funke kann nicht wieder entzündet werden.',
    'interests.deleteSparkDone': 'Funke gelöscht.',
    'interests.deleteSparkTitle': 'Funke löschen?',
    'interests.emptyReceivedBody':
        'Sobald dich jemand über seine Vorstellung mag, erscheint er hier '
        'und du entscheidest über Funke oder Ablehnung.',
    'interests.emptyReceivedTitle': 'Noch keine erhaltenen Likes',
    'interests.emptySentBody':
        'Lerne Leute über ihre Vorstellung kennen ("Find your Spark") oder '
        'swipe blind durch Profile.',
    'interests.emptySentTitle': 'Du hast noch niemanden geliked',
    'interests.emptySparksBody':
        'Bestätige erhaltene Likes, um Funken zu bekommen. Danach kannst du '
        'direkt chatten und optional das Kennenlern-Quiz für das Foto '
        'spielen.',
    'interests.emptySparksTitle': 'Noch keine Funken',
    'interests.hiddenCount': '{n} Chat(s) aus der Liste entfernt.',
    'interests.hiddenOne': '{name} aus der Liste entfernt.',
    'interests.hideFailed':
        '{failed} von {total} konnten nicht entfernt werden. Bitte erneut '
        'versuchen.',
    'interests.hideOneBtn': 'Aus Liste entfernen',
    'interests.hideSelected': 'Ausblenden ({n})',
    'interests.likeBack': 'Zurück liken',
    'interests.likeBackDone':
        'Dein Like ist bei {name}. Ein Funke entsteht, sobald sie dich '
        'auch mag.',
    'interests.likeDaysAgo': 'Vor {days} Tagen gesendet',
    'interests.likeDeclined': 'Like von {name} abgelehnt.',
    'interests.likeIgnored': '{name} ist ausgeblendet.',
    'interests.likeOn': 'Gesendet am {date}',
    'interests.likeWithdrawTooltip': 'Like zurückziehen',
    'interests.likeWithdrawn': 'Like zurückgezogen.',
    'interests.likeYesterday': 'Gestern gesendet',
    'interests.likedYou': 'Hat dich geliked',

    'interests.likeToday': 'Heute gesendet',
    'interests.manage': 'Verwalten',
    'interests.matchesSub': 'Bestätigte gegenseitige Likes',
    // Gespeicherte Profile (lokal, max. 5, zum Nachschreiben)
    'qr.limitTitle': 'Maximum erreicht',
    'interests.noBio': 'Keine Bio',
    'interests.photoUnlocked': 'Foto freigeschaltet',
    'interests.pinSpark': 'Fixieren',
    'interests.pinSparkOff': 'Fixierung aufgehoben',

    'interests.pinnedSub': 'Deine ausgewählten Funken - immer oben.',
    'interests.pinSparkOn': 'Funke fixiert',
    'interests.pinnedSection': 'Fixiert',
    'interests.quizPending': 'Foto-Freischaltung: Kennenlern-Quiz',
    'interests.resparkBtn': 'Re-Funke',
    'interests.resparkDone': 'Funke mit {name} ist wieder aktiv.',
    'interests.resparkFailed':
        'Re-Funke fehlgeschlagen. Bitte erneut versuchen.',
    'interests.savedSub':
        'Lokal gespeichert (max. 5) - zum Nachschreiben, wenn du unterwegs '
        'kein Internet hattest',
    'interests.savedTileSub': 'Gespeichert - später anschreiben',
    'interests.savedTitle': 'Gespeicherte Profile',
    'interests.sparkAccepted':
        'Ein Funke mit {name} ist entstanden! Ihr könnt direkt chatten.',
    'interests.sparkConfirmBtn': 'Funke bestätigen',
    'interests.sparksLoadFailed':
        'Die Funken konnten nicht geladen werden. Bitte Netz prüfen und neu laden.',
    'interests.sparksSub':
        'Deine Begegnungen - sie stehen immer hier, unter den Likes.',
    'interests.sparksTitle': 'Funken',
    'interests.tabReceived': 'Erhalten',
    'interests.tabSent': 'Gesendet',
    'interests.tabSparks': 'Funken',
    'interests.unarchiveSpark': 'Wieder aktivieren',
    'intro.audioTitle': 'Audio-Vorstellung',
    'intro.audioTitleRequired': 'Audio-Vorstellung *',
    'intro.delete': 'Entfernen',
    'intro.deleteBody': 'Die gespeicherte Aufnahme wird endgültig gelöscht.',
    'intro.deleteTitle': 'Audio-Vorstellung entfernen?',
    'intro.deleteTooltip': 'Audio-Vorstellung entfernen',
    'intro.discard': 'Verwerfen',
    'intro.discardBody': 'Die laufende Aufnahme wird gelöscht.',
    'intro.discardKeep': 'Behalten',
    'intro.discardTitle': 'Aufnahme verwerfen?',
    'intro.guide.hint': 'Tippe einen Schritt an, um ihn selbst zu wählen.',
    'intro.guide.step1': 'Wer bist du?',
    'intro.guide.step2': 'Was macht dich aus?',
    'intro.guide.step3': 'Warum bist du hier?',
    'intro.hintOptional':
        'So lernst du andere kennen, bevor ein Foto zu sehen ist. Du '
        'kannst diesen Schritt auch überspringen und alles später '
        'ergänzen.',
    'intro.hintRequired':
        'So lernst du andere kennen, bevor ein Foto zu sehen ist. '
        'Der Text ist Pflicht - eine Aufnahme ist optional.',
    'intro.listen': 'Vorstellung anhören',
    // Audio-Review-Sheet (Anhören vor dem Senden)
    'intro.review.title': 'Aufnahme prüfen',
    'intro.micDenied': 'Mikrofon-Zugriff verweigert.',
    'intro.pause': 'Pause',
    'intro.pausedState': 'Pausiert',
    'intro.prompt.dream': 'Wovon träumst du gerade?',
    'intro.prompt.dream.learn': 'Was möchtest du unbedingt einmal lernen?',
    'intro.prompt.dream.trip':
        'Wohin würdest du fahren, wenn Geld keine Rolle spielt?',
    // Leitfaden für die Audio-Vorstellung (3 Schritte, ROADMAP 0.10.0)
    'intro.guide.title': 'Leitfaden für deine Vorstellung',
    'intro.prompt.everyday.coffee':
        'Wie sieht dein idealer Kaffee aus, und wo trinkst du ihn?',
    'intro.prompt.everyday.sunday':
        'Wie sieht dein ganz gewöhnlicher Sonntag aus?',
    'intro.prompt.friends': 'Was schätzen deine Freunde an dir?',
    'intro.prompt.humor.embarrassing':
        'Was war dein peinlichster Moment, über den du immer noch lachst?',
    'intro.prompt.humor.silent':
        'Was bringt dich zum Lachen, das niemand mitbekommt?',
    'intro.prompt.laugh': 'Worüber kannst du richtig lachen?',
    'intro.prompt.people.call':
        'Wann hast du zuletzt jemanden einfach nur angerufen, ohne Grund?',
    'intro.prompt.people.proud': 'Wofür hat dich zuletzt jemand gelobt?',
    'intro.prompt.weekend': 'Was machst du am liebsten am Wochenende?',
    'intro.promptTitle': 'Brauchst du Ideen? Tippe eine Frage an:',
    'intro.rangeHint':
        '{min} bis {max} Sekunden. Du kannst jede Aufnahme vor dem '
        'Speichern anhören.',
    'intro.record': 'Aufnehmen',
    // Stille-Erkennung (v0.10.0): eine Aufnahme kann die Mindestlänge
    // haben und trotzdem nichts enthalten. Diese Texte sind die einzige
    // Stelle, an der der Nutzer davon erfährt wird.
    'intro.silenceHint': 'Noch kein Ton - bitte sprechen',
    'intro.recordFailed': 'Aufnahme fehlgeschlagen: {error}',
    'intro.recordingState': 'Aufnahme läuft …',
    'intro.removed': 'Audio-Vorstellung entfernt.',
    'intro.rerecord': 'Neu aufnehmen',
    'intro.resume': 'Weiter',
    'intro.review.confirm': 'Verwenden & hochladen',
    'intro.review.discard': 'Verwerfen',
    'intro.review.length': 'Länge: {length}',
    'intro.review.lengthMin': 'Länge: {length} (mindestens {min} s)',
    'intro.review.listen': 'Anhören',
    'intro.review.loadError':
        'Vorschau nicht abspielbar. Du kannst die Aufnahme trotzdem '
        'verwenden oder verwerfen.',
    'intro.review.pause': 'Pause',
    'intro.review.rerecord': 'Neu aufnehmen',
    'intro.review.send': 'Senden',
    'intro.review.tooShort':
        'Die Aufnahme ist zu kurz (mindestens {min} Sekunden). '
        'Bitte nimm sie neu auf.',
    'intro.saved': 'Audio-Vorstellung hochgeladen.',
    'intro.savedState':
        'Aufgenommen. Du kannst sie neu aufnehmen oder entfernen.',
    'intro.silentBody':
        'In dieser Aufnahme wurde nichts gesagt. Sprich ein paar '
        'Worte und versuch es noch einmal.',
    'intro.silentTitle': 'Da war nichts zu hören',
    'intro.stop': 'Stopp',
    'intro.stopListen': 'Fertig',
    'intro.text': 'Vorstellung (Text)',
    'intro.textHint': 'z. B. wer du bist und wonach du suchst',
    'intro.textRequired': 'Vorstellung (Text) *',
    'intro.unavailable': 'Vorstellung nicht abrufbar',
    'intro.unplayable': 'Vorstellung nicht abspielbar',
    'intro.voiceDetected': 'Stimme erkannt',
    'mood.adventurous': 'Abenteuerlustig',
    'mood.change': 'Ändern',
    'mood.changeHint': 'Tippe, um deine Stimmung zu ändern.',
    'mood.current': 'Aktuelle Stimmung',
    // Aktuelles (Home)
    'home.title': 'Aktuelles',
    'mood.explainer':
        'Dein Mood hilft uns, dir passendere Vorschläge zu machen.',
    'mood.flirty': 'Flirty',
    'mood.happy': 'Glücklich',
    'mood.noneSelected': 'Kein Mood ausgewählt',
    'mood.question': 'Wie fühlst du dich heute?',
    'mood.relaxed': 'Entspannt',
    'mood.save': 'Speichern',
    'mood.saved': 'Mood gespeichert',
    'mood.saving': 'Speichern...',
    'mood.select': 'Wählen',
    'mood.selectHint': 'Tippe, um deine Stimmung des Tages zu wählen.',
    'mood.thoughtful': 'Nachdenklich',
    'mood.tired': 'Müde',
    'mood.today': 'Heute',
  },
  'en': {
    'interests.alreadySpark': 'You already have a spark',
    'interests.archiveSpark': 'Archive',
    'interests.archiveSparkDone': 'Spark archived.',
    'interests.coolBtn': 'Cool down spark',
    'interests.cooledDone': 'Spark with {name} cooled down.',
    'interests.cooledSub':
        'Quietly ended - also automatically after 3 days without a '
        'message. The chat is kept, can be re-sparked any time',
    'interests.cooledTitle': 'Archived sparks',
    'interests.decline': 'Ignore',
    'interests.deleteSavedBody':
        '{name} will be deleted locally. The related chat history is lost '
        'with it.',
    // QR flow
    'qr.menuTitle': 'Connect to others',
    'interests.deleteSavedTitle': 'Remove saved profile?',
    'interests.deleteSpark': 'Delete spark',
    'interests.deleteSparkBody':
        'The spark disappears from your list. The chat is kept, the spark '
        'cannot be re-lit.',
    'interests.deleteSparkDone': 'Spark deleted.',
    'interests.deleteSparkTitle': 'Delete spark?',
    'interests.emptyReceivedBody':
        'As soon as someone likes your intro, they appear here and you '
        'decide on spark or decline.',
    'interests.emptyReceivedTitle': 'No received likes yet',
    'interests.emptySentBody':
        'Meet people through their intro ("Find your Spark") or swipe '
        'profiles blindly.',
    'interests.emptySentTitle': 'You have not liked anyone yet',
    'interests.emptySparksBody':
        'Confirm received likes to get sparks. Afterwards you can chat '
        'right away and optionally play the quiz for the photo.',
    'interests.emptySparksTitle': 'No sparks yet',
    'interests.hiddenCount': '{n} chat(s) removed from the list.',
    'interests.hiddenOne': '{name} removed from the list.',
    'interests.hideFailed':
        '{failed} of {total} could not be removed. Please try again.',
    'interests.hideOneBtn': 'Remove from list',
    'interests.hideSelected': 'Hide ({n})',
    'interests.likeBack': 'Like back',
    'interests.likeBackDone':
        'Your like reached {name}. A spark forms as soon as they like you '
        'too.',
    'interests.likeDaysAgo': 'Sent {days} days ago',
    'interests.likeDeclined': 'Like from {name} declined.',
    'interests.likeIgnored': '{name} is hidden.',
    'interests.likeOn': 'Sent on {date}',
    'interests.likeWithdrawTooltip': 'Withdraw like',
    'interests.likeWithdrawn': 'Like withdrawn.',
    'interests.likeYesterday': 'Sent yesterday',
    'interests.likedYou': 'Liked you',

    'interests.likeToday': 'Sent today',
    'interests.manage': 'Manage',
    'interests.matchesSub': 'Confirmed mutual likes',
    // Saved profiles (local, max. 5, for writing later)
    'qr.limitTitle': 'Maximum reached',
    'interests.noBio': 'No bio',
    'interests.photoUnlocked': 'Photo unlocked',
    'interests.pinSpark': 'Pin',
    'interests.pinSparkOff': 'Unpinned',

    'interests.pinnedSub': 'Your chosen sparks - always on top.',
    'interests.pinSparkOn': 'Spark pinned',
    'interests.pinnedSection': 'Pinned',
    'interests.quizPending': 'Photo unlock: getting-to-know quiz',
    'interests.resparkBtn': 'Re-spark',
    'interests.resparkDone': 'Spark with {name} is active again.',
    'interests.resparkFailed': 'Re-spark failed. Please try again.',
    'interests.savedSub':
        'Stored locally (max. 5) - to write to them later when you had no '
        'internet on the go',
    'interests.savedTileSub': 'Saved - write later',
    'interests.savedTitle': 'Saved profiles',
    'interests.sparkAccepted':
        'A spark with {name} was created! You can chat right away.',
    'interests.sparkConfirmBtn': 'Confirm spark',
    'interests.sparksLoadFailed':
        'The sparks could not be loaded. Please check your connection and try again.',
    'interests.sparksSub':
        'Your encounters - they are always here, below the likes.',
    'interests.sparksTitle': 'Sparks',
    'interests.tabReceived': 'Received',
    'interests.tabSent': 'Sent',
    'interests.tabSparks': 'Sparks',
    'interests.unarchiveSpark': 'Make active again',
    'intro.audioTitle': 'Audio intro',
    'intro.audioTitleRequired': 'Audio intro *',
    'intro.delete': 'Remove',
    'intro.deleteBody': 'The saved recording will be permanently deleted.',
    'intro.deleteTitle': 'Remove audio intro?',
    'intro.deleteTooltip': 'Remove audio intro',
    'intro.discard': 'Discard',
    'intro.discardBody': 'The current recording will be deleted.',
    'intro.discardKeep': 'Keep it',
    'intro.discardTitle': 'Discard recording?',
    'intro.guide.hint': 'Tap a step to choose it yourself.',
    'intro.guide.step1': 'Who are you?',
    'intro.guide.step2': 'What makes you tick?',
    'intro.guide.step3': 'Why are you here?',
    'intro.hintOptional':
        'This is how you get to know others before a photo is shown. '
        'You can skip this step and add everything later.',
    'intro.hintRequired':
        'This is how you get to know others before a photo is shown. '
        'The text is required - a recording is optional.',
    'intro.listen': 'Listen to introduction',
    // Audio review sheet (listen before sending)
    'intro.review.title': 'Check your recording',
    'intro.micDenied': 'Microphone access denied.',
    'intro.pause': 'Pause',
    'intro.pausedState': 'Paused',
    'intro.prompt.dream': 'What are you dreaming of right now?',
    'intro.prompt.dream.learn': 'What would you really like to learn?',
    'intro.prompt.dream.trip':
        'Where would you travel if money were no object?',
    // Guide for the audio intro (3 steps, roadmap 0.10.0)
    'intro.guide.title': 'Guide for your intro',
    'intro.prompt.everyday.coffee':
        'What does your ideal coffee look like, and where do you drink it?',
    'intro.prompt.everyday.sunday':
        'What does an ordinary Sunday look like for you?',
    'intro.prompt.friends': 'What do your friends appreciate about you?',
    'intro.prompt.humor.embarrassing':
        'What is your most embarrassing moment that still makes you laugh?',
    'intro.prompt.humor.silent':
        'What makes you laugh when nobody is watching?',
    'intro.prompt.laugh': 'What makes you really laugh?',
    'intro.prompt.people.call':
        'When did you last call someone just because, with no reason?',
    'intro.prompt.people.proud': 'What did someone recently praise you for?',
    'intro.prompt.weekend': 'What do you enjoy most on weekends?',
    'intro.promptTitle': 'Need ideas? Tap a question:',
    'intro.rangeHint':
        '{min} to {max} seconds. You can listen to every recording '
        'before saving.',
    'intro.record': 'Record',
    // Silence detection (v0.10.0): a recording can meet the minimum
    // length and still contain nothing. These strings are the only
    // place the user is told about it.
    'intro.silenceHint': 'No sound yet - please speak',
    'intro.recordFailed': 'Recording failed: {error}',
    'intro.recordingState': 'Recording …',
    'intro.removed': 'Audio intro removed.',
    'intro.rerecord': 'Re-record',
    'intro.resume': 'Resume',
    'intro.review.confirm': 'Use & upload',
    'intro.review.discard': 'Discard',
    'intro.review.length': 'Length: {length}',
    'intro.review.lengthMin': 'Length: {length} (minimum {min} s)',
    'intro.review.listen': 'Listen',
    'intro.review.loadError':
        'Preview not playable. You can still use or discard the '
        'recording.',
    'intro.review.pause': 'Pause',
    'intro.review.rerecord': 'Re-record',
    'intro.review.send': 'Send',
    'intro.review.tooShort':
        'The recording is too short (minimum {min} seconds). '
        'Please record it again.',
    'intro.saved': 'Audio intro uploaded.',
    'intro.savedState': 'Recorded. You can re-record or remove it.',
    'intro.silentBody':
        'Nothing was said in this recording. Say a few words '
        'and try again.',
    'intro.silentTitle': 'There was nothing to hear',
    'intro.stop': 'Stop',
    'intro.stopListen': 'Done',
    'intro.text': 'Intro (text)',
    'intro.textHint': 'e.g. who you are and what you are looking for',
    'intro.textRequired': 'Intro (text) *',
    'intro.unavailable': 'Introduction unavailable',
    'intro.unplayable': 'Introduction cannot be played',
    'intro.voiceDetected': 'Voice detected',
    'mood.adventurous': 'Adventurous',
    'mood.change': 'Change',
    'mood.changeHint': 'Tap to change your mood.',
    'mood.current': 'Current mood',
    // Home (latest)
    'home.title': 'Latest',
    'mood.explainer': 'Your mood helps us suggest better matches for you.',
    'mood.flirty': 'Flirty',
    'mood.happy': 'Happy',
    'mood.noneSelected': 'No mood selected',
    'mood.question': 'How are you feeling today?',
    'mood.relaxed': 'Relaxed',
    'mood.save': 'Save',
    'mood.saved': 'Mood saved',
    'mood.saving': 'Saving...',
    'mood.select': 'Choose',
    'mood.selectHint': 'Tap to choose your mood of the day.',
    'mood.thoughtful': 'Thoughtful',
    'mood.tired': 'Tired',
    'mood.today': 'Today',
  },
};
