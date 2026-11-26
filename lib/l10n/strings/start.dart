// Die Texte des Themas 'start' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsStart = {
  'de': {
    'birthday.pickHint':
        'Wähle, wie dein Profil an deinem Geburtstag aussieht.',
    'birthday.style.classic': 'Klassisch',
    'birthday.style.midnight': 'Mitternacht',
    'birthday.style.mono': 'Mono',
    'birthday.style.rose': 'Rosé',
    'birthday.style.sage': 'Salbei',
    'birthday.styleTitle': 'Geburtstags-Stil',
    'birthday.todayTitle': 'Alles Gute zum Geburtstag!',
    'bucket.add': 'Hinzufügen',
    'bucket.addHint': 'Was wollt ihr zusammen unternehmen?',
    'bucket.empty':
        'Noch leer. Schreibt eure ersten Ideen auf - große und kleine.',
    'bucket.hint':
        'Das wollt ihr gemeinsam erleben. Beide können Einträge '
        'hinzufügen und abhaken.',
    'bucket.mine': 'von dir',
    'bucket.staleNote':
        'Eure Erinnerungsliste wartet seit {days} Tagen - Lust, etwas '
        'davon anzupacken?',
    'bucket.theirs': 'von {name}',
    'bucket.title': 'Erinnerungsliste',
    'fym.introSaved': 'Vorstellung gespeichert. Viel Spaß beim Kennenlernen!',
    'home.discover': 'Leute entdecken',
    'home.discoverSub': 'Lerne Leute über ihre Vorstellung kennen.',
    'home.fallbackName': 'du',
    'home.likesSub': 'Likes führen zu Funken, wenn beide sich mögen.',
    'home.noLikes': 'Keine neuen Likes',
    'home.noMessages': 'Keine neuen Nachrichten',
    'home.noMessagesSub':
        'Wenn du Funken hast, erscheinen hier neue Nachrichten.',
    'home.noSparks': 'Keine neuen Funken',
    'home.qrTooltip': 'Mit anderen verbinden',
    'home.randomChat': 'Zufallschat starten',
    // Find your Match
    'match.required': 'Bitte schreibe einen Text für deine Vorstellung.',
    'home.settingsTooltip': 'Einstellungen & Privatsphäre',
    'home.verifyHintAction': 'Jetzt verifizieren',
    'home.verifyHintReviewBody':
        'Du wartest auf das Ergebnis. Bis dahin kannst du Zufallschat '
        'und QR-Code-Scannen nutzen.',
    'home.verifyHintReviewTitle': 'Deine Prüfung läuft noch',
    'home.verifyHintUnverifiedBody':
        'Mit einem kurzen Video bestätigst du dein Alter - danach sind '
        'alle Modi freigeschaltet. Die Prüfung dauert meist nur einen '
        'Moment.',
    'home.viewAll': 'Alle ansehen',
    'home.viewCount': '{count} ansehen',
    'milestone.dismiss': 'Schließen',
    'milestone.month1': 'Ein Monat',
    'milestone.month1Body':
        'Ein Monat Funkentanz: {date} bis heute. Was war euer bestes '
        'Gespräch?',
    'milestone.month3': 'Drei Monate',
    'milestone.month3Body':
        'Drei Monate seit {date}. Manche Verbindungen brauchen Zeit - '
        'ihr habt sie ihr gegeben.',
    'milestone.quizPassed': 'Quiz bestanden',
    'milestone.quizPassedBody':
        'Ihr habt euch am {date} im Quiz gekannt - das Foto ist seitdem '
        'frei.',
    'milestone.sparkDayBody':
        'Am {date} habt ihr euch gefunden. Manchmal hilft ein Blick '
        'darauf, warum ihr geschrieben habt.',
    'milestone.title': 'Erinnere dich daran',
    'milestone.year1': 'Ein Jahr',
    'milestone.year1Body':
        'Ein Jahr! Vom ersten Funken am {date} bis hierher - das '
        ' verdient einen ehrlichen Respekt.',
  },
  'en': {
    'birthday.pickHint': 'Choose how your profile looks on your birthday.',
    'birthday.style.classic': 'Classic',
    'birthday.style.midnight': 'Midnight',
    'birthday.style.mono': 'Mono',
    'birthday.style.rose': 'Rosé',
    'birthday.style.sage': 'Sage',
    'birthday.styleTitle': 'Birthday style',
    'birthday.todayTitle': 'Happy birthday!',
    'bucket.add': 'Add',
    'bucket.addHint': 'What do you want to do together?',
    'bucket.empty':
        'Empty so far. Write down your first ideas - big and small.',
    'bucket.hint':
        'Things you want to experience together. Both of you can add '
        'and check off entries.',
    'bucket.mine': 'by you',
    'bucket.staleNote':
        'Your memory list has been waiting for {days} days - feel like '
        'picking something from it?',
    'bucket.theirs': 'by {name}',
    'bucket.title': 'Memory list',
    'fym.introSaved': 'Intro saved. Enjoy getting to know each other!',
    'home.discover': 'Discover people',
    'home.discoverSub': 'Get to know people through their intro.',
    'home.fallbackName': 'you',
    'home.likesSub': 'Likes become sparks when you both like each other.',
    'home.noLikes': 'No new likes',
    'home.noMessages': 'No new messages',
    'home.noMessagesSub': 'New messages appear here once you have sparks.',
    'home.noSparks': 'No new sparks',
    'home.qrTooltip': 'Connect to others',
    'home.randomChat': 'Start random chat',
    // Find your Match
    'match.required': 'Please write a text for your intro.',
    'home.settingsTooltip': 'Settings & privacy',
    'home.verifyHintAction': 'Verify now',
    'home.verifyHintReviewBody':
        'You are waiting for the result. Until then you can use the random '
        'chat and scan QR codes.',
    'home.verifyHintReviewTitle': 'Your review is still running',
    'home.verifyHintUnverifiedBody':
        'Confirm your age with a short video - afterwards every mode is '
        'unlocked. The review usually takes only a moment.',
    'home.viewAll': 'View all',
    'home.viewCount': 'View {count}',
    'milestone.dismiss': 'Close',
    'milestone.month1': 'One month',
    'milestone.month1Body':
        'One month of sparks: {date} until today. What was your best '
        'conversation?',
    'milestone.month3': 'Three months',
    'milestone.month3Body':
        'Three months since {date}. Some connections need time - you '
        'gave it to them.',
    'milestone.quizPassed': 'Quiz passed',
    'milestone.quizPassedBody':
        'You knew each other in the quiz on {date} - the photo has been '
        'unlocked since then.',
    'milestone.sparkDayBody':
        'You found each other on {date}. Sometimes it helps to look '
        'back at why you started writing.',
    'milestone.title': 'Remember this',
    'milestone.year1': 'One year',
    'milestone.year1Body':
        'One year! From the first spark on {date} to here - that '
        'deserves honest respect.',
  },
};
