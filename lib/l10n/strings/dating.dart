// Die Texte des Themas 'dating' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsDating = {
  'de': {
    'dh.autoMatch.badge': 'Automatisch',
    'dh.autoMatch.body':
        'Aus eurem Gespräch ist automatisch ein Funke geworden. '
        'Passt das zu euch?',
    'dh.autoMatch.done': 'Alles klar, der Hinweis ist weg.',
    'dh.autoMatch.failed': 'Der Hinweis konnte nicht entfernt werden.',
    'dh.autoMatch.keep': 'Behalten',
    'dh.autoMatch.remove': 'Person entfernen',
    'dh.autoMatch.title': 'Automatischer Funke',
    'dh.chat.accept': 'Annehmen',
    'dh.chat.backToOverview': 'Zurück zur Übersicht',
    'dh.chat.bannerNoMatch': 'Kein Funke diesmal, aber weiter so!',
    'dh.chat.bothMustAccept':
        'Beide müssen "Annehmen" drücken für einen Funken.',
    'dh.chat.decline': 'Ablehnen',
    'dh.chat.e2e': 'Ende zu Ende verschlüsselt',
    'dh.chat.endConversation': 'Gespräch beenden',
    'dh.chat.endConversationBody':
        'Wenn du das Gespräch beendest, entsteht daraus kein Funke. '
        'Das ist völlig in Ordnung. Wenn sich euer Gespräch richtig '
        'angefühlt hat, entscheidet ihr einfach beide dafür.',
    'dh.chat.endConversationDone': 'Das Gespräch ist beendet.',
    'dh.chat.endConversationTitle': 'Gespräch beenden?',
    'dh.chat.fiveMinutesDone':
        'Die 5 Minuten sind um. Ihr habt Zeit, in Ruhe zu entscheiden, '
        'was ihr von eurem Gespräch haltet.',
    'dh.chat.hint': 'Nachricht...',
    'dh.chat.icebreakerBtn': 'Gesprächsstarter senden',
    'dh.chat.keepSearching': 'Weiter suchen',
    'dh.chat.leaveBody':
        'Wenn du den Chat verlässt, gilt das als "Ablehnen". Möchtest du '
        'wirklich gehen?',
    'dh.chat.leaveDecline': 'Verlassen & Ablehnen',
    'dh.chat.leaveTitle': 'Chat verlassen?',
    'dh.chat.noSpark': 'Kein Funke',
    'dh.chat.resultPending':
        'Sobald beide entschieden haben, erfährst du das Ergebnis.',
    'dh.chat.sayHello': 'Sag hallo zu {name}!',
    'dh.chat.sendFailed': 'Nachricht konnte nicht gesendet werden.',
    'dh.chat.sparkJumped': 'Ein Funke ist übersprungen! Chat wird geöffnet...',
    // Das Banner, das im Chat steht (BEFUND 18.11.2026: der Text war
    // fest in Deutsch verdrahtet - in der englischen Fassung stand
    // trotzdem Deutsch da).
    'dh.chat.bannerMatch': 'Ein Funke ist übersprungen!',
    'dh.chat.stay': 'Bleiben',
    'dh.chat.timeUp': 'Die 5 Minuten sind um!\nMöchtest du euch wiedersehen?',
    'dh.chat.timerHide': 'Timer ausblenden',
    'dh.chat.timerShow': 'Timer anzeigen',
    'dh.chat.voted': 'Du hast abgestimmt. Warte auf deine Gegenseite...',
    'dh.duration.hour': '{h} Stunde',
    'dh.duration.hours': '{h} Stunden',
    // Safety Center
    'safety.centerTitle': 'Safety Center',
    'dh.duration.minute': '{m} Minute',
    'dh.duration.minutes': '{m} Minuten',
    'dh.event.autoJoinAsk':
        'Das Event ist für heute vorbei. Möchtest du beim nächsten '
        'Mal automatisch dabei sein?',
    'dh.event.autoJoinFailed': 'Auto-Beitritt fehlgeschlagen: {error}',
    'dh.event.autoJoinOff': 'Alles klar, du wirst beim nächsten Mal gefragt.',
    'dh.event.autoJoinOn':
        'Du bist beim nächsten Dating Hour automatisch dabei.',
    'dh.event.bye': 'Bis zum nächsten Mal!',
    'dh.event.cancelledToday':
        'Heute fällt die Dating Hour aus: Es haben sich nicht genug '
        'Personen angemeldet.',
    'dh.event.chatLater': 'Später',
    'dh.event.chatNow': 'Jetzt chatten',
    'dh.event.chipNotParticipating': 'Nicht angemeldet',
    'dh.event.chipParticipating': 'Du nimmst teil',
    'dh.event.ended': 'Dating Hour beendet',
    'dh.event.genderMixHint':
        'Gesucht wird jemand des anderen Geschlechts - das Event ist für '
        'alle Heterosexuellen. Hast du im Profil ausdrücklich nur dein '
        'eigenes Geschlecht gewählt, suchen wir in dieser Gruppe.',
    'dh.event.join': 'Ich bin dabei',
    'dh.event.joinConfirmBody':
        'Du wirst nur dann mit jemandem verbunden, wenn du jetzt '
        'bestätigst. Du kannst jederzeit aussteigen.',
    'dh.event.joinConfirmTitle': 'Am Event teilnehmen?',
    'dh.event.joinNow': 'Jetzt beitreten & chatten',
    'dh.event.joined': 'Du nimmst am Dating Hour Event teil!',
    'dh.event.leave': 'Raus',
    'dh.event.left': 'Du hast das Event verlassen.',
    'dh.event.liveNow': 'LIVE: Dating Hour läuft!',
    'dh.event.loadError': 'Fehler beim Laden',
    'dh.event.loadErrorFull': 'Fehler beim Laden: {error}',
    'dh.event.localTimeWarn':
        'Countdown und Status basieren auf der lokalen Gerätezeit. '
        'Die Server-Zeit konnte nicht verifiziert werden.',
    'dh.event.nextAt': 'Nächste Dating Hour am {date}',
    'dh.event.noThanks': 'Nein, danke',
    'dh.event.nonePlanned': 'Aktuell ist kein Dating Hour Event geplant.',
    'dh.event.pairedBody':
        'Dein Gegenüber wartet im Chat. Möchtest du jetzt reinschauen?',
    'dh.event.pairedTitle': 'Du wurdest gepaart',
    'dh.event.participants': '{n} Teilnehmer dabei',
    'dh.event.participantsSub':
        'Die Dating Hour findet immer statt, egal wie viele mitmachen. '
        'Reicht es nicht für ein Paar, bekommst du diesmal kein Gespräch.',
    'dh.event.participatingLive': 'Du nimmst teil! Chats laufen.',
    'dh.event.participatingWaiting': 'Du nimmst teil! Warte auf den Start.',

    'dh.rules.title': 'Dating Hour Regeln',
    'dh.event.prefsNote': '(änderbar in den Präferenzen).',
    'dh.event.remaining': 'Noch {d}',
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
    'dh.event.rule.8':
        'Die Dating Hour findet immer statt, egal wie viele mitmachen. '
        'Es gibt keine Mindestanzahl mehr.',
    'dh.event.rule.9':
        'Die Erstellung von Fake Accounts ist strengstens untersagt.',

    'profile.edit.filters': 'Filter & Präferenzen',
    'dh.event.searchingPartner': 'Wir suchen gerade einen Partner...',
    'dh.event.startIn': 'Start in {d}',
    // Dating-Hour-Regeln-Detailzeilen (Event-Screen, Regeln-Karte)
    'dh.event.rulesTitle': 'Wichtige Regeln',
    'dh.event.startingSoon': 'Dating Hour startet gleich',
    'dh.event.title': 'Dating Hour',
    'dh.event.toChat': 'Zum Chat',
    'dh.event.welcomeBack':
        'Willkommen zurück! Du bist automatisch wieder dabei.',
    'dh.event.yesPlease': 'Ja, gerne',
    'dh.feature.e2eSub':
        'Niemand außer euch beiden kann eure Nachrichten lesen (Signal-Protokoll).',
    'dh.feature.e2eTitle': 'Ende zu Ende verschlüsselt',
    'dh.feature.noPhotos':
        'Keine Fotos, keine Bios, nur 5 Minuten echtes Gespräch.',
    'dh.feature.realChat': 'Echter Chat statt Profil Check',
    'dh.gender.all': 'Alle Geschlechter',
    'dh.gender.men': 'Männer',
    'dh.gender.nonBinary': 'Nichtbinäre Personen',
    'dh.gender.women': 'Frauen',
    'dh.how.intro':
        'Die Dating Hour läuft jeden Samstag von 20:00 bis 21:00 Uhr. '
        'Hier ist der Ablauf im Überblick:',
    'dh.how.next': 'Zur Dating Hour',
    'dh.how.step1.body':
        'Wähle deine Präferenzen und trete dem samstäglichen Event '
        'bei. Du kannst jederzeit wieder austreten.',
    'dh.how.step1.title': 'Beitreten',
    'dh.how.step2.body':
        'Die App verbindet dich mit einer passenden Person. Sobald beide '
        'bereit sind, startet der 5 Minuten Chat.',
    'dh.how.step2.title': 'Warten auf eine Zuordnung',
    'dh.how.step3.body':
        'Lerne die Person in einem kurzen, zeitlich begrenzten Gespräch '
        'kennen. Fotos werden je nach Einstellung angezeigt.',
    'dh.how.step3.title': '5 Minuten chatten',
    'dh.how.step4.body':
        'Nach dem Gespräch entscheidest du, ob du den Kontakt verlängern '
        'möchtest.',
    'dh.how.step4.title': 'Entscheidung',
    'dh.how.step5.body':
        'Wenn beide sich für eine Verlängerung entscheiden, entsteht ein '
        'Funke und ihr könnt weiter chatten.',
    'dh.how.step5.title': 'Funken',
    'dh.how.title': 'Wie funktioniert Dating Hour?',
    'dh.info.liveSub':
        'Du wirst live mit einer anderen Person verbunden, die genau jetzt ebenfalls aktiv einen Dating Hour Partner sucht.',
    'dh.info.liveTitle': 'Live mit echten Personen',
    'dh.info.retrySub':
        'Bei "Ablehnen" sucht der Algorithmus sofort jemand Neues.',
    'dh.info.retryTitle': 'Kein Funke? Neue Chance!',
    'dh.info.timeSub': 'Danach entscheiden beide: "Annehmen" oder "Ablehnen".',
    'dh.info.timeTitle': '5 Minuten Zeit',
    'dh.info.title': 'Wie funktioniert Dating Hour?',
    'dh.nextEventIn': 'Nächstes Event in',
    'dh.prefs.ageRange': '{min} bis {max} Jahre',
    'dh.prefs.ageSection': 'Altersbereich',
    'dh.prefs.autoJoin': 'Automatisch wieder dabei sein',
    'dh.prefs.autoJoinHint':
        'Wenn aktiviert, nimmst du am nächsten Dating Hour '
        'automatisch teil, sobald es läuft.',
    'dh.prefs.genderSection': 'Ich suche...',
    'dh.prefs.habits': 'Gewohnheiten (optional)',
    'dh.prefs.habitsHint2':
        'Personen mit passenden Gewohnheiten werden dir bei den '
        'Funken-Vorschlägen zuerst vorgeschlagen, ausgeschlossen wird niemand.',
    'dh.prefs.header': 'Deine Dating Hour Präferenzen',
    'dh.prefs.intro':
        'Diese Einstellungen helfen uns, dich mit passenden Personen zu '
        'verbinden. Du kannst sie vor jedem Event anpassen.',
    'dh.prefs.joinSection': 'Teilnahme',
    'dh.prefs.save': 'Präferenzen speichern',
    'dh.prefs.saveHint2':
        'Speichern meldet dich NICHT an. Deine Teilnahme bestätigst '
        'du separat mit "Ich bin dabei" auf dem Event-Screen.',
    'dh.prefs.savedHint':
        'Präferenzen gespeichert. Deine Teilnahme meldest du über "Ich bin dabei" am Event-Tag an.',
    'dh.prefs.setBtn': 'Präferenzen festlegen',
    'dh.prefs.title': 'Dating Hour: Präferenzen',
    'dh.prefs.trait.adventure': 'Abenteuerlust',
    'dh.prefs.trait.downToEarth': 'Bodenständigkeit',
    'dh.prefs.trait.empathy': 'Empathie',
    'dh.prefs.trait.honesty': 'Ehrlichkeit',
    'dh.prefs.trait.humor': 'Humor',
    'dh.prefs.trait.intelligence': 'Intelligenz',
    'dh.prefs.trait.openness': 'Offenheit',
    'dh.prefs.trait.passion': 'Leidenschaft',
    'dh.prefs.trait.reliability': 'Zuverlässigkeit',
    'dh.prefs.trait.spontaneity': 'Spontanität',
    'dh.prefs.traitHint2':
        'Wähle eine Eigenschaft oder gib deine eigene ein. '
        'Dies fließt als weicher Faktor bei den Funken-Vorschlägen ein.',
    'dh.prefs.traitHintField':
        'z. B. "Gute Laune", "Tiefgründige Gespräche"...',
    'dh.prefs.traitOwn': 'Eigene Eigenschaft eingeben',
    'dh.prefs.traitSection': 'Was du an anderen besonders magst',
    'dh.rules.1.body':
        'Behandele deinen Gegenüber mit Respekt. Keine Beleidigungen, '
        'Diskriminierung oder unerwünschte Nachrichten.',
    'dh.rules.1.title': 'Respektvoll bleiben',
    'dh.rules.2.body':
        'Gib keine Adressen, Telefonnummern oder Kontodetails preis. '
        'Bleibt zunächst in der App.',
    'dh.rules.2.title': 'Keine persönlichen Daten teilen',
    'dh.rules.3.body':
        'Nutze nur echte Angaben und aktuelle Bilder. Fake Profile oder '
        'Identitätsdiebstahl werden gemeldet.',
    'dh.rules.3.title': 'Ehrliches Profil',
    'dh.rules.4.body':
        'Jeder Chat dauert maximal 5 Minuten. Danach entscheidest du, ob '
        'du den Funken verlängern möchtest.',
    'dh.rules.4.title': '5 Minuten Regel',
    'dh.rules.5.body':
        'Sende keine intimen Bilder oder unerwünschten Content. Verstöße '
        'führen zur sofortigen Sperrung.',
    'dh.rules.5.title': 'Keine unerwünschten Bilder',
    'dh.rules.6.body':
        'Die Dating Hour ist erst ab 16 Jahren freigegeben. Jüngere '
        'Nutzer werden automatisch ausgeschlossen.',
    'dh.rules.6.title': 'Minderjährigenschutz',
    'dh.rules.7.body':
        'Im Event kommen Menschen des jeweils anderen Geschlechts '
        'zusammen: Das Event ist für alle Heterosexuellen. Hast du im '
        'Profil ausdrücklich nur dein eigenes Geschlecht gewählt, '
        'kommst du mit Menschen dieses Geschlechts zusammen. Findet sich '
        'niemand Passendes, wartest du - lieber warten als jemanden '
        'gegen deinen Wunsch.',
    'dh.rules.7.title': 'Wer mit wem zusammenkommt',
    'dh.rules.acceptedTitle': 'Regeln akzeptiert',
    'dh.rules.bodyFun': 'Viel Spaß bei der Dating Hour!',
    'dh.rules.introLong':
        'Bitte lies diese Regeln aufmerksam durch, bevor du an der Dating '
        'Hour teilnimmst.',
    'dh.rules.next': 'Weiter',
    'dh.searching': 'Suche läuft...',
  },
  'en': {
    'dh.autoMatch.badge': 'Automatic',
    'dh.autoMatch.body':
        'Your conversation has become a spark automatically. '
        'Does that feel right to you?',
    'dh.autoMatch.done': 'All good, the hint is gone.',
    'dh.autoMatch.failed': 'The hint could not be removed.',
    'dh.autoMatch.keep': 'Keep',
    'dh.autoMatch.remove': 'Remove the person',
    'dh.autoMatch.title': 'Automatic spark',
    'dh.chat.backToOverview': 'Back to overview',
    'dh.chat.bannerMatch': 'A spark jumped!',
    'dh.chat.bannerNoMatch': 'No spark this time - but keep going!',
    'dh.chat.bothMustAccept': 'Both must press "Accept" for a spark.',
    'dh.chat.decline': 'Decline', 'dh.chat.accept': 'Accept',
    'dh.chat.e2e': 'End-to-end encrypted',
    'dh.chat.endConversation': 'End the conversation',
    'dh.chat.endConversationBody':
        'If you end the conversation, it will not become a spark. '
        'That is completely fine. If your conversation felt right, you '
        'can both decide for it.',
    'dh.chat.endConversationDone': 'The conversation has ended.',
    'dh.chat.endConversationTitle': 'End the conversation?',
    'dh.chat.fiveMinutesDone':
        'The 5 minutes are up. Take your time and decide at ease what '
        'you think of your conversation.',
    'dh.chat.hint': 'Message...',
    'dh.chat.icebreakerBtn': 'Send conversation starter',
    'dh.chat.keepSearching': 'Keep searching',
    'dh.chat.leaveBody':
        'Leaving the chat counts as "declining". Do you really want to '
        'go?',
    'dh.chat.leaveDecline': 'Leave & decline',
    'dh.chat.leaveTitle': 'Leave chat?',
    'dh.chat.noSpark': 'No spark',
    'dh.chat.resultPending':
        'As soon as both have decided, you will see the result.',
    'dh.chat.sayHello': 'Say hi to {name}!',
    'dh.chat.sendFailed': 'Message could not be sent.',
    'dh.chat.sparkJumped': 'A spark jumped! Opening the chat...',
    'dh.chat.stay': 'Stay',
    'dh.chat.timeUp':
        'The 5 minutes are up!\nWould you like to see each other again?',
    'dh.chat.timerHide': 'Hide the timer',
    'dh.chat.timerShow': 'Show the timer',
    'dh.chat.voted': 'You have voted. Waiting for the other side...',
    'dh.duration.hour': '{h} hour',
    'dh.duration.hours': '{h} hours',
    // Safety center
    'safety.centerTitle': 'Safety center',
    'dh.duration.minute': '{m} minute',
    'dh.duration.minutes': '{m} minutes',
    'dh.event.autoJoinAsk':
        "Today's event is over. Would you like to automatically join "
        'the next one?',
    'dh.event.autoJoinFailed': 'Auto-join failed: {error}',
    'dh.event.autoJoinOff': 'Alright, you will be asked next time.',
    'dh.event.autoJoinOn': 'You will automatically join the next Dating Hour.',
    'dh.event.bye': 'See you next time!',
    'dh.event.cancelledToday':
        "Today's Dating Hour is cancelled: not enough people signed up.",
    'dh.event.chatLater': 'Later',
    'dh.event.chatNow': 'Chat now',
    'dh.event.chipNotParticipating': 'Not registered',
    'dh.event.chipParticipating': "You're participating",
    'dh.event.ended': 'Dating hour ended',
    'dh.event.genderMixHint':
        'We are looking for someone of the other gender - the event is '
        'for heterosexual people. If you have explicitly chosen only your '
        'own gender in the profile, we look in that group.',
    'dh.event.join': 'I am in',
    'dh.event.joinConfirmBody':
        'You will only be matched with someone if you confirm now. '
        'You can drop out any time.',
    'dh.event.joinConfirmTitle': 'Join the event?',
    'dh.event.joinNow': 'Join now & chat',
    'dh.event.joined': "You're in for the Dating Hour event!",
    'dh.event.leave': 'Leave',
    'dh.event.left': 'You left the event.',
    'dh.event.liveNow': 'LIVE: Dating Hour is running!',
    'dh.event.loadError': 'Loading error',
    'dh.event.loadErrorFull': 'Loading failed: {error}',
    'dh.event.localTimeWarn':
        'Countdown and status are based on the local device time. '
        'The server time could not be verified.',
    'dh.event.nextAt': 'Next Dating Hour on {date}',
    'dh.event.noThanks': 'No, thanks',
    'dh.event.nonePlanned': 'Currently no Dating Hour event is planned.',
    'dh.event.pairedBody':
        'Your partner is waiting in the chat. Do you want to look in now?',
    'dh.event.pairedTitle': 'You have been paired',
    'dh.event.participants': '{n} participants joined',
    'dh.event.participantsSub':
        'The Dating Hour always takes place, no matter how many join. If '
        'there is nobody to pair you with, you get no conversation this time.',
    'dh.event.participatingLive': "You're in! Chats are running.",
    'dh.event.participatingWaiting': "You're in! Waiting for the start.",

    'dh.rules.title': 'Dating Hour rules',
    'dh.event.prefsNote': '(changeable in the preferences).',
    'dh.event.remaining': '{d} left',
    'dh.event.rule.1':
        'Saturdays 20:00 to 21:00 (you can already join beforehand).',
    'dh.event.rule.2':
        'Connected directly in a 1:1 chat, without viewing profiles first.',
    'dh.event.rule.3': '5 minutes of chat, then decide: "Accept" or "Decline".',
    'dh.event.rule.4': 'A spark only forms if BOTH sides "Accept".',
    'dh.event.rule.5': 'On "Decline" (or timeout): automatic new matching.',
    'dh.event.rule.6': 'During a chat: ONLY this chat is allowed.',
    'dh.event.rule.7': 'End at 21:00; ongoing chats are finished.',
    'dh.event.rule.8':
        'The Dating Hour always takes place, no matter how many join. '
        'There is no minimum number anymore.',
    'dh.event.rule.9': 'Creating fake accounts is strictly prohibited.',

    'profile.edit.filters': 'Filters & preferences',
    'dh.event.searchingPartner': 'Looking for a partner for you...',
    'dh.event.startIn': 'Starts in {d}',
    // Dating Hour rules detail lines (event screen, rules card)
    'dh.event.rulesTitle': 'Important rules',
    'dh.event.startingSoon': 'Dating Hour starts soon',
    'dh.event.title': 'Dating Hour',
    'dh.event.toChat': 'To chat',
    'dh.event.welcomeBack': 'Welcome back! You are automatically in.',
    'dh.event.yesPlease': 'Yes, please',
    'dh.feature.e2eSub':
        'Nobody but the two of you can read your messages (Signal protocol).',
    'dh.feature.e2eTitle': 'End-to-end encrypted',
    'dh.feature.noPhotos':
        'No photos, no bios, just 5 minutes of real conversation.',
    'dh.feature.realChat': 'Real chat instead of profile check',
    'dh.gender.all': 'All genders',
    'dh.gender.men': 'Men',
    'dh.gender.nonBinary': 'Non-binary people',
    'dh.gender.women': 'Women',
    'dh.how.intro':
        'The Dating Hour takes place every Saturday from 20:00 to 21:00. '
        'Here is the flow at a glance:',
    'dh.how.next': 'Go to Dating Hour',
    'dh.how.step1.body':
        'Choose your preferences and join the Saturday event. You can '
        'leave at any time.',
    'dh.how.step1.title': 'Join',
    'dh.how.step2.body':
        'The app connects you with a matching person. As soon as both '
        'are ready, the 5 minute chat starts.',
    'dh.how.step2.title': 'Waiting for a match',
    'dh.how.step3.body':
        'Get to know the person in a short, time-limited conversation. '
        'Photos are shown depending on your settings.',
    'dh.how.step3.title': 'Chat for 5 minutes',
    'dh.how.step4.body':
        'After the chat you decide whether you want to extend the '
        'contact.',
    'dh.how.step4.title': 'Decision',
    'dh.how.step5.body':
        'If both decide to extend, a spark is created and you can keep '
        'chatting.',
    'dh.how.step5.title': 'Sparks',
    'dh.how.title': 'How does Dating Hour work?',
    'dh.info.liveSub':
        'You are connected live with another person who is also actively looking for a Dating Hour partner right now.',
    'dh.info.liveTitle': 'Live with real people',
    'dh.info.retrySub':
        'On "Decline" the algorithm immediately looks for someone new.',
    'dh.info.retryTitle': 'No spark? New chance!',
    'dh.info.timeSub': 'Then both decide: "Accept" or "Decline".',
    'dh.info.timeTitle': '5 minutes',
    'dh.info.title': 'How does Dating Hour work?',
    'dh.nextEventIn': 'Next event in',
    'dh.prefs.ageRange': '{min} to {max} years',
    'dh.prefs.ageSection': 'Age range',
    'dh.prefs.autoJoin': 'Automatically join again',
    'dh.prefs.autoJoinHint':
        'If enabled, you will automatically take part in the next '
        'Dating Hour once it starts.',
    'dh.prefs.genderSection': 'I am looking for...',
    'dh.prefs.habits': 'Habits (optional)',
    'dh.prefs.habitsHint2':
        'People with matching habits will be suggested to you first '
        'in match suggestions, nobody is excluded.',
    'dh.prefs.header': 'Your Dating Hour preferences',
    'dh.prefs.intro':
        'These settings help us connect you with matching people. '
        'You can adjust them before every event.',
    'dh.prefs.joinSection': 'Participation',
    'dh.prefs.save': 'Save preferences',
    'dh.prefs.saveHint2':
        'Saving does NOT sign you up. You confirm your participation '
        'separately with "I am in" on the event screen.',
    'dh.prefs.savedHint':
        'Preferences saved. You join via "I am in" on the event day.',
    'dh.prefs.setBtn': 'Set preferences',
    'dh.prefs.title': 'Dating Hour: preferences',
    'dh.prefs.trait.adventure': 'Love of adventure',
    'dh.prefs.trait.downToEarth': 'Down-to-earth attitude',
    'dh.prefs.trait.empathy': 'Empathy',
    'dh.prefs.trait.honesty': 'Honesty',
    'dh.prefs.trait.humor': 'Humor',
    'dh.prefs.trait.intelligence': 'Intelligence',
    'dh.prefs.trait.openness': 'Openness',
    'dh.prefs.trait.passion': 'Passion',
    'dh.prefs.trait.reliability': 'Reliability',
    'dh.prefs.trait.spontaneity': 'Spontaneity',
    'dh.prefs.traitHint2':
        'Choose a trait or enter your own. '
        'This counts as a soft factor in match suggestions.',
    'dh.prefs.traitHintField': 'e.g. "Good vibes", "Deep conversations"...',
    'dh.prefs.traitOwn': 'Enter custom trait',
    'dh.prefs.traitSection': 'What you especially like in others',
    'dh.rules.1.body':
        'Treat your counterpart with respect. No insults, discrimination '
        'or unwanted messages.',
    'dh.rules.1.title': 'Stay respectful',
    'dh.rules.2.body':
        'Do not share addresses, phone numbers or account details. Stay '
        'in the app for now.',
    'dh.rules.2.title': 'No sharing of personal data',
    'dh.rules.3.body':
        'Use only real information and current pictures. Fake profiles '
        'or identity theft will be reported.',
    'dh.rules.3.title': 'Honest profile',
    'dh.rules.4.body':
        'Each chat lasts a maximum of 5 minutes. Afterwards you decide '
        'whether you want to extend the match.',
    'dh.rules.4.title': '5 minute rule',
    'dh.rules.5.body':
        'Do not send intimate pictures or unwanted content. Violations '
        'lead to an immediate ban.',
    'dh.rules.5.title': 'No unwanted pictures',
    'dh.rules.6.body':
        'The Dating Hour is only available from age 16. Younger users '
        'are automatically excluded.',
    'dh.rules.6.title': 'Minor protection',
    'dh.rules.7.body':
        'In the event, people of the respective other gender are brought '
        'together: the event is for heterosexual people. If you have '
        'explicitly chosen only your own gender in the profile, you are '
        'brought together with people of that gender. If there is nobody '
        'matching, you wait - rather than sitting opposite someone you '
        'did not choose.',
    'dh.rules.7.title': 'Who gets paired with whom',
    'dh.rules.acceptedTitle': 'Rules accepted',
    'dh.rules.bodyFun': 'Have fun at the Dating Hour!',
    'dh.rules.introLong':
        'Please read these rules carefully before taking part in the '
        'Dating Hour.',
    'dh.rules.next': 'Next',
    'dh.searching': 'Searching...',
  },
};
