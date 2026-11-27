// Die Texte des Themas 'chat' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsChat = {
  'de': {
    'call.icebreakerHint':
        'Stöbere in der Sammlung und stelle die Frage laut - '
        'zum Weiterreden, wenn es still wird.',
    'call.icebreakerTitle': 'Eisbrecher-Fragen',
    'chat.ageGapHint':
        'Hinweis: Ihr seid {my} und {other} Jahre alt. Profile können '
        'falsche Angaben enthalten. Bleib vorsichtig, triff dich nur '
        'öffentlich und melde Verdacht auf falsches Alter.',
    'chat.backToSparks': 'Zurück zu den Funken',
    'chat.blockAction': 'Blockieren',
    'chat.blockBody':
        '{name} wird dauerhaft blockiert: Der Funke wird beendet und diese '
        'Person kann dich nicht mehr liken, einen Funke setzen oder dir '
        'Nachrichten senden. Die Blockierung kann später über den '
        'Support-Dialog nicht aufgehoben werden. Nur du selbst kannst sie '
        'in den Einstellungen entfernen.',
    'chat.blockFailed': 'Blockieren fehlgeschlagen. Bitte versuche es erneut.',
    'chat.blockSub':
        'Keine Nachrichten, Likes oder Funken mehr von dieser Person.',
    'chat.blockTitle': 'Nutzer blockieren?',
    'chat.blockedDone': '{name} wurde blockiert.',
    'chat.blurred': 'Verpixelt',
    'chat.call': 'Audio Anruf',
    // Vorstellung im Chat + Kennenlern-Quiz-Banner (Chat zuerst)
    'chat.introTitle': 'Vorstellung',
    'chat.callBatteryHint':
        'Anrufe brauchen dauerhaft Mikrofon und Funk und verbrauchen '
        'merklich mehr Akku.',
    'chat.callE2eInfo':
        'Sprache ist Ende-zu-Ende verschlüsselt und läuft direkt '
        'Peer zu Peer (Push to Talk).',
    'chat.callMicDenied': 'Mikrofon-Zugriff verweigert.',
    'chat.callMuted': 'Stumm',
    'chat.callNetHint':
        'Hinweis: Sprachanrufe laufen direkt zwischen den Geräten und '
        'funktionieren nur im WLAN zuverlässig. Im Mobilfunknetz sollten '
        'Anrufe nicht gestartet werden.',
    'chat.callPttHold': 'Gedrückt halten zum Sprechen',
    'chat.callStatusConnected': 'Verbunden',
    'chat.callStatusConnecting': 'Verbinde…',
    'chat.callStatusDeclined': 'Anruf abgelehnt',
    'chat.callStatusEnded': 'Anruf beendet',
    'chat.callStatusRecording': 'Aufnahme… {s} s',
    'chat.callStatusRingingIn': 'Eingehender Anruf…',
    'chat.callStatusRingingOut': 'Es klingelt…',
    'chat.callStatusUnreachable': 'Keine direkte Verbindung möglich',
    'chat.callUnmuted': 'Mikrofon',
    'chat.callVoiceFailed': 'Sprachpaket konnte nicht gesendet werden.',
    'chat.camera': 'Kamera',
    'chat.close': 'Schließen',
    'chat.closeImageHint':
        'Schließen (Bild kann danach nicht mehr angesehen werden)',
    'chat.connDiag': 'Technik: ICE {ice} - automatischer Neuversuch läuft.',
    'chat.connError': 'Letzter Fehler: {error}',
    'chat.connProblem': 'Problem: {problem}',
    // Datenschutz: TOTP-Bestätigung
    'privacy.totpTitle': 'Konto bestätigen',
    'chat.connectionHeader': 'Verbindung',
    'chat.conversationHeader': 'Gespräch',
    'chat.coolSpark': 'Funke kühlen',
    'chat.coolSparkDone':
        'Funke gekühlt. Ihr findet euch unter „Erschlossene Funken" wieder.',
    'chat.coolSparkError': 'Funke konnte nicht gekühlt werden: {error}',
    'chat.dateIdea': 'Idee für ein Date: {idea} ✨ Was meinst du?',
    'chat.deleteForAllAction': 'Für alle löschen',
    'chat.deleteForAllBody':
        'Die Nachricht wird für alle gelöscht. Bei deinem Gegenüber '
        'erscheint an ihrer Stelle ein Hinweis.',
    'chat.deleteForAllFailed': 'Die Nachricht konnte nicht gelöscht werden.',
    'chat.deleteForAllNotPossible': 'Das geht nur bei Chats mit einem Funke.',
    'chat.deleteForAllTitle': 'Nachricht löschen?',
    'chat.deletedNotice': 'Diese Nachricht wurde gelöscht.',
    'chat.e2eReady': 'Ende-zu-Ende verschlüsselt (Signal-Protokoll via P2P)',
    'chat.e2eWaiting': 'E2E-Verbindung wird aufgebaut.',
    'chat.empty': 'Schreib die erste Nachricht! 😊',
    // Die eigene Tastatur (v0.10.1): die Systemtastatur sieht nichts.
    'keyboard.letters': 'Buchstaben',
    'chat.end': 'Funke beenden',
    'chat.endSilent': 'Ruhig enden lassen',
    'chat.endSilentSub': 'Ohne Nachricht',
    'chat.endSparkBody':
        'Der Funke wandert bei euch beiden in "Erschlossene Funken", ganz '
        'ohne Countdown und ohne Benachrichtigung. Ein Re-Funke ist '
        'jederzeit mit einem Tap möglich.',
    'chat.endSparkTitle': 'Funke beenden: ehrlich und freundlich',
    'chat.gallery': 'Galerie',
    'chat.gone': 'Dieser Chat existiert nicht mehr.',
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
    'chat.hint': 'Nachricht...',
    'chat.icebreakerOff': 'Interessen-Vorschläge ausblenden',
    'chat.icebreakerOn': 'Interessen-Vorschläge anzeigen',
    'chat.icebreakerSuggestBody':
        'Ihr habt euch noch nichts geschrieben. Wie wäre es mit '
        'einer Eisbrecher-Frage an dein Gegenüber?',
    'chat.icebreakerSuggestLater': 'Später',
    // Sicherheits-Aufklärung vor dem Setup (30.10.2026)
    'safetyOnboarding.title': 'Sicher unterwegs',
    'chat.icebreakerSuggestSend': 'Frage senden',
    'chat.icebreakerSuggestTitle': 'Gesprächseinstieg gefällig?',
    'chat.icebreakerText':
        'Wir teilen das Interesse "{interest}". Erzähl mir davon: was war '
        'dein Highlight dazu? 😊',
    'chat.idea.bowling': 'Bowling oder Billard',
    'chat.idea.coffeeCake': 'Kaffee & Kuchen',
    'chat.idea.iceCream': 'Eis essen',
    'chat.idea.liveMusic': 'Live-Musik',
    'chat.idea.market': 'Markt bummeln',
    'chat.idea.minigolf': 'Minigolf',
    'chat.idea.movieNight': 'Kinoabend',
    'chat.idea.museum': 'Museum oder Ausstellung',
    'chat.idea.stargazing': 'Sterne beobachten',
    'chat.idea.walk': 'Gemeinsam spazieren gehen',
    'chat.ideaHide': 'Date-Rad für diesen Chat ausblenden',
    'chat.ideaWheelBtn': 'Dreh das Rad, Date-Idee finden',
    'chat.identityVerifiedHint':
        'Nur aktivieren, wenn die Nummern übereinstimmen.',
    'chat.identityVerifiedTitle': 'Identität bestätigt',
    'chat.imageBlurredHint':
        'Verpixelte Bildnachricht. Doppeltippen zum Anzeigen nach '
        'Warnung, lang drücken zum Melden.',
    'chat.imageHint':
        'Bildnachricht. Doppeltippen für Vollbild, lang drücken zum '
        'Melden.',
    'chat.imagePrepareFailed':
        'Bild konnte nicht sicher aufbereitet werden und wurde nicht '
        'gesendet.',
    'chat.imageSend': 'Bild senden',
    'chat.imageSendFailed': 'Senden fehlgeschlagen',
    'chat.imageSendFailedBody':
        'Das Bild konnte nicht gesendet werden.\n\n{error}',
    'chat.imageSourcePrompt': 'Wähle eine Quelle für das zu sendende Bild.',
    // Umschalten zwischen der System- und der App-Tastatur (27.11.2026).
    'chat.keyboardToApp': 'Zur App-Tastatur wechseln',
    'chat.keyboardToSystem': 'Zur Systemtastatur wechseln',
    'chat.micDisclosureAccept': 'Mikrofon freigeben',
    'chat.micDisclosureBody':
        'Um eine Sprachnachricht aufzunehmen, braucht die App Zugriff auf '
        'das Mikrofon. Die Aufnahme startet erst, wenn du unten '
        'bestätigst, und läuft nur während des Aufnehmens. '
        'Sie wird als Datei verschlüsselt gespeichert und nur an deinen '
        'Gegenüber gesendet. Ohne Mikrofon kannst du weiter schreiben.',
    'chat.more': 'Weitere Optionen',
    // Nachricht überdenken (NUTZERWUNSCH 26.11.2026): Vor dem Senden
    // fragen, wie der Nutzer die Nachricht selbst versteht.
    'chat.nachrichtPruefAbZeichen': 'Ab {n} Zeichen',
    'chat.nachrichtPruefAus': 'Aus - es wird nicht nachgefragt',
    'chat.nachrichtPruefBogen':
        'Vor dem Senden fragt die App, wie du die Nachricht selbst '
        'verstehst. Du entscheidest, ob das für alle Kontakte gilt oder '
        'nur für diesen einen.',
    'chat.nachrichtPruefFeld': 'Meine eigene Deutung',
    'chat.nachrichtPruefFrage': 'Wie verstehst du diese Nachricht selbst?',
    'chat.nachrichtPruefGlobal': 'Für alle Kontakte',
    'chat.nachrichtPruefHinweis':
        'Deine Deutung bleibt nur auf diesem Gerät - sie wird nicht '
        'mitgesendet und nirgends gespeichert.',
    'chat.nachrichtPruefImmer': 'Bei jeder Nachricht',
    'chat.nachrichtPruefManuell': 'Nur über den Knopf im Eingabefeld',
    'chat.nachrichtPruefNurKontakt': 'Nur für {name}',
    'chat.nachrichtPruefSchwelle': 'Ab wie vielen Zeichen wird gefragt?',
    'chat.nachrichtPruefSenden': 'So senden',
    'chat.nachrichtPruefTitle': 'Nachricht überdenken',
    'chat.nachrichtPruefZurueck': 'Zurück zum Text',
    'chat.nachrichtPruefKnopf': 'Nachricht überdenken',
    'chat.photosAfterSpark': 'Fotos nach Funke sichtbar',
    'chat.queuedHint':
        'Offline - Nachricht wartet in der Warteschlange und wird bei der '
        'nächsten direkten Verbindung zugestellt.',
    'chat.quizBanner':
        'Das Kennenlern-Quiz schaltet das Profilfoto frei. Chatten ist '
        'unabhängig möglich.',
    'chat.quizOpen': 'Zum Quiz',
    // Herzensstärken (v0.9.2): Erinnerung, Freundschaft, Erinnerungsliste
    'milestone.sparkDay': 'Euer erster Tag',
    'chat.quizUnavailable': 'Das Kennenlern-Quiz gibt es nur für Funken-Chats.',
    'chat.reconnectStillFailing': 'Verbindung weiterhin fehlgeschlagen.',
    'chat.recordingHint': 'Aufnahme: {s} s',
    'chat.relayBanner':
        'Kein P2P möglich. Nachrichten sind Ende-zu-Ende verschlüsselt, '
        'laufen über das Relay und kommen an, sobald der Chat geöffnet '
        'wird.',
    'chat.relayBannerShort': 'Kein P2P möglich',
    'chat.reportImage': 'Bild melden',
    'chat.reportImageSub': 'Wird mit Kontext an den Support übermittelt.',
    'chat.reportTooltip': 'Nutzer melden',
    'chat.requireVerifiedHint':
        'Senden erst erlauben, wenn ihr die Safety-Nummern verglichen habt. Das schützt davor, dass jemand die Schlüssel eurer Chats ersetzt und mitliest.',
    'chat.requireVerifiedTitle': 'Schlüssel immer prüfen',
    'chat.retry': 'Wiederholen',
    'chat.revealAction': 'Anzeigen',
    'chat.revealBody':
        'Dieses Bild ist verpixelt, um dich vor unangemessenen Inhalten zu '
        'schützen. Es kann Inhalte enthalten, die du als störend '
        'empfindest.\n\nDu kannst es danach direkt melden.',
    'chat.revealTitle': 'Bild anzeigen?',
    'chat.safetyChangedAccept': 'Nummer geprüft: akzeptieren',
    'chat.safetyChangedBody':
        'Der Verschlüsselungsschlüssel deines Kontakts hat sich geändert. '
        'Das kann nach einer Neuinstallation passieren - oder darauf '
        'hindeuten, dass sich jemand in die Verbindung einschleichen '
        'will.\n\nVergleiche die Sicherheitsnummer über einen zweiten '
        'Kanal (z. B. Anruf oder persönlich), bevor du fortfährst.',
    'chat.safetyChangedCancel': 'Abbrechen',
    'chat.safetyChangedTitle': 'Sicherheitsnummer hat sich geändert',
    'chat.safetyCompare':
        'Vergleiche diese Nummer mit {name}, am besten persönlich oder '
        'telefonisch:',
    'chat.safetyNotConnected':
        'Noch keine verschlüsselte Verbindung zu {name} aufgebaut. Die '
        'Nummer erscheint nach der ersten Nachricht.',
    'chat.safetyNumber': 'Sicherheitsnummer',
    'chat.safetyNumberHint':
        'Prüfe die Sicherheitsnummer mit {name} - damit stellen wir sicher, '
        'dass niemand dazwischenfunkt.',
    'chat.safetyNumberTooltip': 'Sicherheitsnummer (E2E-Verifikation)',
    'chat.securityHeader': 'Sicherheit',
    'chat.spiceTooltip': 'Eisbrecher-Fragen (Spice Questions)',
    'chat.spiceUnavailable':
        'Eisbrecher-Fragen gibt es nur für Funken-Chats (nicht für '
        'gespeicherte Kontakte).',
    'chat.viewOnce': 'Einmalig',
    'chat.viewedOnce': 'Bereits angesehen',
    'chat.voiceCancel': 'Aufnahme abbrechen',
    'chat.voiceCancelled': 'Aufnahme abgebrochen',
    'chat.voiceListened': 'angehört',
    // Chat-Dialoge & Steuerung (zweisprachig)
    'chat.you': 'Du',
    'chat.voiceOnlyOnce':
        'Wiedergabe nicht möglich - die Nachricht wurde '
        'bereits angehört.',
    'chat.voiceRecordFailed': 'Aufnahme fehlgeschlagen: {error}',
    // Prominente Mikrofon-Offenlegung (Google Play verlangt eine
    // sichtbare Begründung VOR der Berechtigungsanfrage).
    'chat.micDisclosureTitle': 'Sprachnachricht aufnehmen',
    'chat.voiceStartFailed': 'Aufnahme konnte nicht gestartet werden: {error}',
    'chat.voiceStopSend': 'Aufnahme beenden & senden',
    'chat.voiceTooShort': 'Aufnahme zu kurz (< 1 s), verworfen.',
    'chat.voiceTooltip': 'Sprachnachricht',
    'chat.wheelAgain': 'Nochmal drehen',
    'chat.wheelHint':
        'Passt das? Schick den Vorschlag, deine Gegenstelle kann einfach '
        'antworten.',
    'chat.wheelSend': 'Vorschlag senden',
    'chat.wheelSpin': 'Drehen',
    'chat.wheelTitle': 'Dreh das Rad',
    'chatbg.badImage': 'Diese Datei ist kein unterstütztes Bild.',
    'chatbg.custom': 'Eigenes Bild',
    'chatbg.dots': 'Punkte',
    'chatbg.hearts': 'Herzen',
    'chatbg.hintBody':
        'Wähle einen Hintergrund für eure Chats. Das ändert nichts an den '
        'Nachrichten - es ist nur eine Fläche hinter dem Text.',
    'chatbg.hintDone': 'Hintergrund gesetzt.',
    'chatbg.hintTitle': 'Chat-Hintergrund',
    'chatbg.lines': 'Linien',
    'chatbg.none': 'Keiner',
    'chatbg.stars': 'Sterne',
    'chatbg.tooLarge': 'Bild zu groß (max. 8 MB), bitte ein kleineres wählen.',
    'chatbg.waves': 'Wellen',
    'chathist.all.sub': 'Verschlüsselt, ohne Limit.',
    'chathist.all.title': 'Kompletter Verlauf',
    'chathist.cap200.sub': 'Verschlüsselt, max. 200 pro Chat.',
    'chathist.cap200.title': '200 Nachrichten pro Chat',
    'chathist.deleteHint': 'Deaktivieren löscht die Historie.',
    'chathist.dialogTitle': 'Chat-Verlauf speichern',
    'chathist.mode.all': 'An (kompletter Verlauf)',
    'chathist.mode.cap200': 'An (200 Nachrichten)',
    'chathist.mode.off': 'Aus',
    'chathist.modeWord': 'Modus:',
    'chathist.off.sub': 'Chats sind nach dem Neustart weg.',
    'chathist.off.title': 'Gar nichts (nur Arbeitsspeicher)',
    'chathist.tileSubPrefix': 'Verschlüsselt (AES-256) auf diesem Gerät.',
    'chathist.tileTitle': 'Chat-Verlauf lokal speichern',
  },
  'en': {
    'call.icebreakerHint':
        'Browse the collection and ask the question out loud - '
        'to keep talking when it goes quiet.',
    'call.icebreakerTitle': 'Icebreaker questions',
    'chat.ageGapHint':
        'Note: you are {my} and {other} years old. Profiles may contain '
        'false information. Stay cautious, only meet in public and report '
        'suspected false age.',
    'chat.backToSparks': 'Back to sparks',
    'chat.blockAction': 'Block',
    'chat.blockBody':
        '{name} will be blocked permanently: the spark is ended and this '
        'person can no longer like you, spark you or send you messages. '
        'Blocking cannot be undone via the support dialog later. Only you '
        'can remove it in the settings.',
    'chat.blockFailed': 'Blocking failed. Please try again.',
    'chat.blockSub': 'No messages, likes or sparks from this person anymore.',
    'chat.blockTitle': 'Block user?',
    'chat.blockedDone': '{name} was blocked.',
    'chat.blurred': 'Blurred',
    'chat.call': 'Audio call',
    // Intro in chat + getting-to-know-you quiz banner (chat first)
    'chat.introTitle': 'Intro',
    'chat.callBatteryHint':
        'Calls continuously use microphone and radio and noticeably '
        'drain the battery.',
    'chat.callE2eInfo':
        'Voice is end-to-end encrypted and runs directly peer to peer '
        '(push to talk).',
    'chat.callMicDenied': 'Microphone access denied.',
    'chat.callMuted': 'Muted',
    'chat.callNetHint':
        'Note: Voice calls run directly between devices and are only '
        'reliable on WiFi. Calls should not be started on mobile '
        'networks.',
    'chat.callPttHold': 'Press and hold to talk',
    'chat.callStatusConnected': 'Connected',
    'chat.callStatusConnecting': 'Connecting…',
    'chat.callStatusDeclined': 'Call declined',
    'chat.callStatusEnded': 'Call ended',
    'chat.callStatusRecording': 'Recording… {s} s',
    'chat.callStatusRingingIn': 'Incoming call…',
    'chat.callStatusRingingOut': 'Ringing…',
    'chat.callStatusUnreachable': 'No direct connection possible',
    'chat.callUnmuted': 'Microphone',
    'chat.callVoiceFailed': 'Voice packet could not be sent.',
    'chat.camera': 'Camera',
    'chat.close': 'Close',
    'chat.closeImageHint':
        'Close (the image can no longer be viewed afterwards)',
    'chat.connDiag': 'Tech: ICE {ice} - automatic retry in progress.',
    'chat.connError': 'Last error: {error}',
    'chat.connProblem': 'Problem: {problem}',
    // Privacy: TOTP confirmation
    'privacy.totpTitle': 'Confirm account',
    'chat.connectionHeader': 'Connection',
    'chat.conversationHeader': 'Conversation',
    'chat.coolSpark': 'Cool spark',
    'chat.coolSparkDone':
        'Spark cooled - you will find it under "Settled sparks" again.',
    'chat.coolSparkError': 'Could not cool the spark: {error}',
    'chat.dateIdea': 'Date idea: {idea} ✨ What do you think?',
    'chat.deleteForAllAction': 'Delete for everyone',
    'chat.deleteForAllBody':
        'The message will be deleted for everyone. On the other side '
        'a notice takes its place.',
    'chat.deleteForAllFailed': 'The message could not be deleted.',
    'chat.deleteForAllNotPossible': 'This only works in chats with a spark.',
    'chat.deleteForAllTitle': 'Delete message?',
    'chat.deletedNotice': 'This message was deleted.',
    'chat.e2eReady': 'End-to-end encrypted (Signal protocol via P2P)',
    'chat.e2eWaiting': 'E2E connection is being established.',
    'chat.empty': 'Write the first message! 😊',
    // The app's own keyboard (v0.10.1): the system keyboard sees nothing.
    'keyboard.letters': 'Letters',
    'chat.end': 'End spark',
    'chat.endSilent': 'Let it end quietly',
    'chat.endSilentSub': 'Without a message',
    'chat.endSparkBody':
        'The spark moves to "Cooled sparks" for both of you - without '
        'countdown, without notification. Re-sparking is one tap away at '
        'any time.',
    'chat.endSparkTitle': 'End spark - honestly & kindly',
    'chat.gallery': 'Gallery',
    'chat.gone': 'This chat no longer exists.',
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
    'chat.hint': 'Message...',
    'chat.icebreakerOff': 'Hide interest suggestions',
    'chat.icebreakerOn': 'Show interest suggestions',
    'chat.icebreakerSuggestBody':
        'You have not exchanged messages yet. How about an '
        'icebreaker question for your counterpart?',
    'chat.icebreakerSuggestLater': 'Later',
    // Safety education before setup (30 Oct 2026)
    'safetyOnboarding.title': 'Staying safe',
    'chat.icebreakerSuggestSend': 'Send question',
    'chat.icebreakerSuggestTitle': 'Need a conversation starter?',
    'chat.icebreakerText':
        'We share the interest "{interest}". Tell me about it: what was '
        'your highlight there? 😊',
    'chat.idea.bowling': 'Bowling or billiards',
    'chat.idea.coffeeCake': 'Coffee & cake',
    'chat.idea.iceCream': 'Getting ice cream',
    'chat.idea.liveMusic': 'Live music',
    'chat.idea.market': 'Strolling through a market',
    'chat.idea.minigolf': 'Mini golf',
    'chat.idea.movieNight': 'Movie night',
    'chat.idea.museum': 'Museum or exhibition',
    'chat.idea.stargazing': 'Stargazing',
    'chat.idea.walk': 'Going for a walk together',
    'chat.ideaHide': 'Hide date wheel for this chat',
    'chat.ideaWheelBtn': 'Spin the wheel, find a date idea',
    'chat.identityVerifiedHint': 'Only enable if the numbers match.',
    'chat.identityVerifiedTitle': 'Identity verified',
    'chat.imageBlurredHint':
        'Pixelated image message. Double-tap to show after the '
        'warning, long-press to report.',
    'chat.imageHint':
        'Image message. Double-tap for fullscreen, long-press to '
        'report.',
    'chat.imagePrepareFailed':
        'Image could not be prepared securely and was not sent.',
    'chat.imageSend': 'Send image',
    'chat.imageSendFailed': 'Sending failed',
    'chat.imageSendFailedBody': 'The image could not be sent.\n\n{error}',
    'chat.imageSourcePrompt': 'Choose a source for the image to send.',
    // Switch between the system and the app keyboard (27 Nov 2026).
    'chat.keyboardToApp': "Switch to the app's own keyboard",
    'chat.keyboardToSystem': 'Switch to the system keyboard',
    'chat.micDisclosureAccept': 'Allow microphone',
    'chat.micDisclosureBody':
        'To record a voice message, the app needs access to the '
        'microphone. Recording starts only after you confirm below '
        'and runs only while you are recording. It is stored as an '
        'encrypted file and sent only to your match. Without the '
        'microphone you can keep typing.',
    'chat.micDisclosureTitle': 'Record a voice message',
    'chat.more': 'More options',
    // Think before sending (request 26.11.2026): before a message goes
    // out, the app asks how the sender reads it themselves.
    'chat.nachrichtPruefAbZeichen': 'From {n} characters',
    'chat.nachrichtPruefAus': 'Off - nothing is asked',
    'chat.nachrichtPruefBogen':
        'Before sending, the app asks how you read the message yourself. '
        'You decide whether that applies to all contacts or only to this '
        'one.',
    'chat.nachrichtPruefFeld': 'My own reading',
    'chat.nachrichtPruefFrage': 'How do you read this message yourself?',
    'chat.nachrichtPruefGlobal': 'For all contacts',
    'chat.nachrichtPruefHinweis':
        'Your reading stays on this device - it is not sent along and not '
        'stored anywhere.',
    'chat.nachrichtPruefImmer': 'For every message',
    'chat.nachrichtPruefManuell': 'Only via the button in the input field',
    'chat.nachrichtPruefNurKontakt': 'Only for {name}',
    'chat.nachrichtPruefSchwelle': 'From how many characters is it asked?',
    'chat.nachrichtPruefSenden': 'Send it this way',
    'chat.nachrichtPruefTitle': 'Think before sending',
    'chat.nachrichtPruefZurueck': 'Back to the text',
    'chat.nachrichtPruefKnopf': 'Think before sending',
    'chat.photosAfterSpark': 'Photos visible after spark',
    'chat.queuedHint':
        'Offline - message is queued and will be delivered on the next '
        'direct connection.',
    'chat.quizBanner':
        'The getting-to-know-you quiz unlocks the profile photo. Chatting '
        'works independently.',
    'chat.quizOpen': 'Take quiz',
    // Herzensstärken (v0.9.2): Erinnerung, Freundschaft, Erinnerungsliste
    'milestone.sparkDay': 'Your first day',
    'chat.quizUnavailable':
        'The getting-to-know-you quiz is only available for spark chats.',
    'chat.reconnectStillFailing': 'Connection still failing.',
    'chat.recordingHint': 'Recording: {s} s',
    'chat.relayBanner':
        'No P2P available. Messages stay end-to-end encrypted, travel '
        'via the relay and arrive once the chat is opened.',
    'chat.relayBannerShort': 'No P2P available',
    'chat.reportImage': 'Report image',
    'chat.reportImageSub': 'Sent with context to the support team.',
    'chat.reportTooltip': 'Report user',
    'chat.requireVerifiedHint':
        'Only allow sending after you compared the safety numbers. This protects against someone substituting your chat keys.',
    'chat.requireVerifiedTitle': 'Always verify keys',
    'chat.retry': 'Retry',
    'chat.revealAction': 'Show',
    'chat.revealBody':
        'This image is blurred to protect you from inappropriate content. '
        'It may contain content you find disturbing.\n\nYou can report it '
        'directly afterwards.',
    'chat.revealTitle': 'Show image?',
    'chat.safetyChangedAccept': 'Verified: accept',
    'chat.safetyChangedBody':
        'The encryption key of your contact has changed. This can happen '
        'after a reinstall - or it may indicate that someone is trying to '
        'intercept the conversation.\n\nVerify the safety number through '
        'a second channel (e.g. a call or in person) before continuing.',
    'chat.safetyChangedCancel': 'Cancel',
    'chat.safetyChangedTitle': 'Safety number has changed',
    'chat.safetyCompare':
        'Compare this number with {name}, ideally in person or by phone:',
    'chat.safetyNotConnected':
        'No encrypted connection to {name} established yet. The number '
        'appears after the first message.',
    'chat.safetyNumber': 'Safety number',
    'chat.safetyNumberHint':
        'Check the safety number with {name} - that way we make sure '
        'nobody is intercepting your conversation.',
    'chat.safetyNumberTooltip': 'Safety number (E2E verification)',
    'chat.securityHeader': 'Security',
    'chat.spiceTooltip': 'Icebreaker questions (Spice Questions)',
    'chat.spiceUnavailable':
        'Icebreaker questions are only available for spark chats (not for '
        'saved contacts).',
    'chat.viewOnce': 'Once',
    'chat.viewedOnce': 'Already viewed',
    'chat.voiceCancel': 'Cancel recording',
    'chat.voiceCancelled': 'Recording cancelled',
    'chat.voiceListened': 'listened',
    // Chat dialogs & controls
    'chat.you': 'You',
    'chat.voiceOnlyOnce':
        'Playback not possible - the message was already '
        'listened to.',
    'chat.voiceRecordFailed': 'Recording failed: {error}',
    'chat.voiceStartFailed': 'Recording could not be started: {error}',
    'chat.voiceStopSend': 'Stop recording & send',
    'chat.voiceTooShort': 'Recording too short (< 1 s), discarded.',
    'chat.voiceTooltip': 'Voice message',
    'chat.wheelAgain': 'Spin again',
    'chat.wheelHint':
        'Like it? Send the suggestion - your counterpart can simply reply.',
    'chat.wheelSend': 'Send suggestion',
    'chat.wheelSpin': 'Spin',
    'chat.wheelTitle': 'Spin the wheel',
    'chatbg.badImage': 'This file is not a supported image.',
    'chatbg.custom': 'Own picture',
    'chatbg.dots': 'Dots',
    'chatbg.hearts': 'Hearts',
    'chatbg.hintBody':
        'Pick a background for your chats. It changes nothing about the '
        'messages - it is just a surface behind the text.',
    'chatbg.hintDone': 'Background set.',
    'chatbg.hintTitle': 'Chat background',
    'chatbg.lines': 'Lines',
    'chatbg.none': 'None',
    'chatbg.stars': 'Stars',
    'chatbg.tooLarge':
        'Image too large (max. 8 MB), please choose a smaller one.',
    'chatbg.waves': 'Waves',
    'chathist.all.sub': 'Encrypted, no limit.',
    'chathist.all.title': 'Full history',
    'chathist.cap200.sub': 'Encrypted, max. 200 per chat.',
    'chathist.cap200.title': '200 messages per chat',
    'chathist.deleteHint': 'Disabling deletes the history.',
    'chathist.dialogTitle': 'Save chat history',
    'chathist.mode.all': 'On (full history)',
    'chathist.mode.cap200': 'On (200 messages)',
    'chathist.mode.off': 'Off',
    'chathist.modeWord': 'Mode:',
    'chathist.off.sub': 'Chats are gone after restart.',
    'chathist.off.title': 'Nothing (RAM only)',
    'chathist.tileSubPrefix': 'Encrypted (AES-256) on this device.',
    'chathist.tileTitle': 'Save chat history locally',
  },
};
