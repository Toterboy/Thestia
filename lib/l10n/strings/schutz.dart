// Die Texte des Themas 'schutz' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fuegt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsSchutz = {
  'de': {
    'guardian.accessGrace': '{months} Monat(e) länger',
    'guardian.accessIndefinite': 'Bis ich es beende',
    'guardian.accessText':
        'Du bestimmst, bis wann dein Elternteil Zugriff behält. Die Nutzung '
        'der App bleibt davon unberührt.',
    'guardian.accessTitle': 'Wie lange bleibt der Zugriff?',
    'guardian.accessUntil': 'Zugriff bis {date}',
    'guardian.accessUntil18': 'Bis zum 18. Geburtstag',
    'guardian.activeText': 'Dein Konto steht unter Aufsicht von {email}.',
    'guardian.activeTitle': 'Freigabe aktiv',
    'guardian.confirmEndText':
        'Damit endet die Freigabe sofort. Dein Elternteil bekommt keine '
        'Benachrichtigungen mehr.',
    'guardian.confirmEndTitle': 'Elternzugriff beenden?',
    'guardian.emailHint': 'name@beispiel.de',
    'guardian.emailLabel': 'E-Mail-Adresse eines Elternteils',
    'guardian.endAccessBtn': 'Elternzugriff beenden',
    // Der Stand liess sich nicht laden (Netz, Server, Sitzung).
    // Vorher zeigte der Bildschirm hier einen endlosen Ladekreis -
    // der Nutzer hatte keinen Weg aus dem Bereich heraus.
    'guardian.loadErrorTitle': 'Stand nicht geladen',
    'guardian.endedText':
        'Die elterliche Freigabe wurde beendet und gilt nicht mehr.',
    'guardian.endedTextEmailDeleted':
        'Die elterliche Freigabe wurde beendet. Die E-Mail-Adresse des '
        'Elternteils wurde dabei gelöscht - sie wird nicht mehr gebraucht '
        'und nicht mehr aufbewahrt.',
    'guardian.endedTextEmailPending':
        'Die elterliche Freigabe wurde beendet. Die E-Mail-Adresse des '
        'Elternteils wird mit dem Ende der Freigabe gelöscht.',
    'guardian.endedTitle': 'Die Freigabe ist beendet',
    'guardian.errorGeneric':
        'Das hat nicht geklappt. Bitte später noch einmal versuchen.',
    'guardian.errorInvalidEmail':
        'Bitte eine gültige E-Mail-Adresse eintragen.',
    'guardian.errorNotEligible':
        'Die Elternfreigabe ist nur für 16- und 17-Jährige vorgesehen.',
    'guardian.errorRateLimited':
        'Zu viele Anfragen. Bitte später noch einmal versuchen.',
    'guardian.errorSameEmail':
        'Das ist deine eigene E-Mail-Adresse. Bitte die eines Elternteils '
        'eintragen.',
    'guardian.graceLabel': 'Nachfrist: {months} Monat(e)',
    'guardian.gracePicker': 'Monate',
    'guardian.loadErrorText':
        'Der Stand der Aufsicht liess sich gerade nicht abrufen. '
        'Pruefe deine Internetverbindung und versuche es noch '
        'einmal.',
    'guardian.noConsentText':
        'Für Konten ab 18 ist keine Freigabe nötig. Wenn du 16 oder 17 bist, '
        'kannst du hier einen Elternteil eintragen - dann bekommt er eine '
        'E-Mail und entscheidet selbst.',
    'guardian.noConsentTitle': 'Keine Elternfreigabe',
    'guardian.notifyFrequency.daily': 'Täglich',
    'guardian.notifyFrequency.monthly': 'Monatlich',
    'guardian.notifyFrequency.none': 'Gar nicht',
    'guardian.notifyFrequency.weekly': 'Wöchentlich',
    'guardian.notifyFrequencyLabel': 'Rhythmus',
    'guardian.notifyText':
        'Dein Elternteil wird benachrichtigt, wenn ein Funke entsteht - in '
        'dem Rhythmus, den er selbst gewählt hat. Namen und Profile werden '
        'nicht weitergegeben.',
    'guardian.notifyTitle': 'Benachrichtigungen',
    'guardian.pendingText':
        'Wir haben {email} eine E-Mail geschickt. Erst wenn dein Elternteil '
        'den Link in der Mail bestätigt, ist die Freigabe aktiv.',
    'guardian.pendingTitle': 'Warte auf die Bestätigung',
    'guardian.pinLocked': 'Mit PIN entsperren',
    'guardian.pinText':
        'Bitte die vierstellige PIN eingeben, die dein Elternteil festgelegt '
        'hat.',
    'guardian.pinTitle': 'Elternbereich',
    'guardian.pinUnlocked': 'Entsperrt',
    'guardian.pinWrong': 'Die PIN stimmt nicht.',
    'guardian.requestBtn': 'Elternfreigabe anfordern',
    'guardian.requestIntro':
        'Für 16- und 17-Jährige sieht Thestia vor, dass die '
        'Sorgeberechtigten zustimmen. Dein Elternteil bekommt eine E-Mail '
        'mit einem Link und entscheidet dort selbst. Die Zustimmung ist '
        'freiwillig - und du kannst sie jederzeit widerrufen.',
    'guardian.requestScreenTitle': 'Elternfreigabe',
    'guardian.retry': 'Erneut versuchen',
    'guardian.saveBtn': 'Speichern',
    'guardian.sectionIntro':
        'Hier steht, ob dein Konto unter Aufsicht steht. Für 16- und '
        '17-Jährige sieht Thestia vor, dass die Sorgeberechtigten zustimmen.',
    'guardian.sectionTitle': 'Kinderschutz & Elternzugriff',
    'guardian.sendBtn': 'Anfrage senden',
    'guardian.sentText':
        'Wir haben {email} geschickt. Bitte deinen Elternteil, den Link in '
        'der E-Mail zu öffnen - erst danach ist die Freigabe aktiv.',
    'guardian.sentTitle': 'Anfrage ist raus',
    'guardian.skipBtn': 'Später - ohne Freigabe fortfahren',
    'guardian.transitionBtn': 'Jetzt entscheiden',
    'guardian.transitionEnd': 'Zugriff jetzt beenden',
    'guardian.transitionGrace': 'Noch {months} Monat(e) behalten',
    'guardian.transitionKeep': 'Erstmal weiter behalten',
    'guardian.transitionText':
        'Seit deinem 18. Geburtstag entscheidest du selbst, ob dein '
        'Elternteil weiter Zugriff hat. Bis du etwas änderst, bleibt der '
        'Zugriff bestehen.',
    'guardian.transitionTitle': 'Du bist jetzt 18',
    'guardian.unlockTitle': 'Elternbereich entsperren',
    'guardian.usageFrom': 'von',
    'guardian.usageLockHint':
        'Sprich mit deinen Elternteilen - die Einstellung lässt sich im '
        'Elternbereich ändern.',

    // ===================================================================
    // Selektive Datenloeschung (v0.10.0)
    // ===================================================================
    'del.title': 'Daten löschen',
    'guardian.usageLockText':
        'Die Nutzungszeit endet heute um {time}. Morgen geht es weiter.',
    'guardian.usageLockTitle': 'Deine Nutzungszeit ist heute vorbei',
    'guardian.usageNone': 'Keine Begrenzung',
    'guardian.usagePinNote':
        'Die Einstellung ist mit einer PIN geschützt. Sie kann nur mit '
        'dieser PIN geändert werden.',
    'guardian.usageText':
        'Dein Elternteil kann ein Zeitfenster festlegen, in dem die App '
        'genutzt werden darf. Außerhalb steht in der App ein Hinweis.',
    'guardian.usageTitle': 'Nutzungszeit',
    'guardian.usageTo': 'bis',
    'guardian.usageToggleLabel': 'Nutzungszeit begrenzen',
    'guardian.usageWindow': 'Erlaubt von {from} bis {to}',
    'safety.ageBody':
        'Manche geben ein falsches Alter an. Das gefährdet besonders junge '
        'Nutzer und führt bei Nachweis zum dauerhaften Ausschluss. Schütze '
        'dich: Glaube keiner Altersangabe blind. Bei großer Altersdifferenz '
        'warnt dich der Chat. Triff dich nur an öffentlichen Orten, nimm '
        'beim ersten Treffen dein Handy mit und sag einer Vertrauensperson '
        'Bescheid. Melde Verdacht auf falsches Alter sofort über den '
        'Meldegrund "Falsches Alter". Thestia kann Angaben nicht lückenlos '
        'prüfen und übernimmt keine Gewähr für deren Richtigkeit.',
    'safety.ageTitle': 'Alter und Täuschung',
    'safety.blockSomeone': 'Jemanden blockieren',
    'safety.blockSomeoneBody':
        'Chat-Menü (drei Punkte) - Blockieren. Likes und Funken werden '
        'entfernt; künftige Interaktionen werden serverseitig verhindert. '
        'Die Person erfährt nicht davon.',
    'safety.blockedUsers': 'Blockierte Nutzer',
    'safety.blockedUsersSub':
        'Nutzer, die du blockiert hast - hier kannst du sie wieder '
        'entsperren.',
    'safety.hotline1': 'Hilfetelefon "Gewalt gegen Frauen"',
    'safety.hotline1Sub': '116 016 - kostenlos, 24/7, anonym',
    'safety.hotline2': 'TelefonSeelsorge',
    'safety.hotline2Sub': '0800 111 0 111 - kostenlos, 24/7',
    'safety.hotline3': 'klicksafe (Cybermobbing & Beratung)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Hilfetelefon Stalking (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.linkFailed': 'Konnte Link nicht öffnen.',
    'safety.myReports': 'Meine Meldungen',
    'safety.myReportsSub':
        'Meldungen, die du geschrieben hast, und ihr Bearbeitungsstand.',
    'safety.noBlocked': 'Du hast niemanden blockiert.',
    'safety.noReports': 'Du hast bisher keine Meldungen geschrieben.',
    'safety.protectOwnImages': 'Eigene Bilder schützen',
    'safety.protectOwnImagesBody':
        'Bilder eingehender Nachrichten sind standardmäßig verpixelt '
        '(Einstellungen - Sicherheit im Chat). Eigene Fotos bleiben bis '
        'zum gegenseitigen Quiz-Erfolg grundsätzlich verborgen.',
    'safety.reportSomeone': 'Jemanden melden',
    'safety.reportSomeoneBody':
        'Im Chat über das Flag-Symbol oben rechts oder per langem Drücken '
        'auf ein Bild. Deine letzten Nachrichten werden transparent als '
        'Kontext übermittelt und vom Support persönlich geprüft.',
    'safety.sectionHelp': 'Sofort Hilfe',
    'safety.sectionProtect': 'Schutz in Thestia',
    'safety.stalkingBody':
        'Wenn dir jemand online (oder offline) nachstellt: 1. Nicht '
        'antworten, Kontakt bewusst abbrechen. 2. Alles dokumentieren: '
        'Screenshots mit Datum, Chatverlauf, Profilnamen. 3. In-App '
        'blockieren und uns über die Melde-Funktion informieren. Wir '
        'können Accounts dauerhaft sperren. 4. Passwörter ändern und 2FA '
        'aktivieren (Einstellungen). 5. Bei Bedrohung oder Angst: Polizei '
        '(110) bzw. 116 006 kontaktieren.',
    'safety.stalkingGuide': 'Stalking-Leitfaden',
    'safety.unblock': 'Entblocken',
    // Stimmung
    'mood.title': 'Stimmung des Tages',
    'safety.unblockFailed':
        'Entblocken fehlgeschlagen. Bitte erneut versuchen.',
    'safetyOnboarding.ack1':
        'Deine Daten gehören dir: Teile Telefonnummer, Adresse oder '
        'Arbeitsplatz erst, wenn du sicher bist.',
    'safetyOnboarding.ack2':
        'Niemand muss dich zu etwas drängen, weder zu einem Treffen '
        'noch zu Bildern noch zu Geld.',
    'safetyOnboarding.ack3':
        'Melden und Blockieren sind jederzeit möglich. Du musst dich '
        'nicht erklären.',
    'safetyOnboarding.ackBody':
        'Thestia verbindet Menschen, die sich noch nicht kennen. Genau '
        'darin liegt die Chance und das Risiko. Nimm dir zwei Minuten '
        'für die wichtigsten Regeln.',
    'safetyOnboarding.ackButton': 'Ich habe verstanden',
    'safetyOnboarding.ackTitle': 'Bevor du loslegst',
    'safetyOnboarding.back': 'Zurück',
    'safetyOnboarding.edu1Body':
        'Fotos, Namen und Berufe lassen sich fälschen. Ein Profil ist '
        'kein Beweis. Frag nach einem kurzen Video-Call oder einem '
        'öffentlichen Treffen, bevor du persönliche Dinge teilst.',
    'safetyOnboarding.edu1Hint':
        'Vertrauen wächst. Es kommt nicht mit dem ersten Foto.',
    'safetyOnboarding.edu1Title': 'Nicht alles ist echt',
    'safetyOnboarding.edu2Body':
        'Telefonnummer, Adresse, Arbeitgeber und Ausweisfotos sind '
        'sensibel. Teile sie erst, wenn du die Person gut kennst. '
        'Screenshots können alles weitergeben, auch verschwindende '
        'Nachrichten.',
    'safetyOnboarding.edu2Hint':
        'Ein Screenshot ist schneller gemacht, als du denkst.',
    'safetyOnboarding.edu2Title': 'Deine Daten gehören dir',
    'safetyOnboarding.edu3Body':
        'Triff dich tagsüber an einem öffentlichen Ort. Sag einer '
        'Person, die du kennst, wo du bist und wann du zurück sein '
        'willst. Sorge selbst für deinen Heimweg.',
    'safetyOnboarding.edu3Hint':
        'Du musst niemandem deine Adresse nennen, auch nicht beim '
        'Abholen.',
    'safetyOnboarding.edu3Title': 'Das erste Treffen',
    'safetyOnboarding.edu4Body':
        'Ein Ja gilt nur für genau das, was gerade passiert. Ein Nein, '
        'ein Zögern oder ein Rückzug ist ein Nein. Niemand schuldet dir '
        'Bilder, Zeit oder Nähe, du schuldest sie auch niemandem.',
    'safetyOnboarding.edu4Hint':
        'Druck ist kein Kennenlernen. Du darfst jederzeit gehen.',
    'safetyOnboarding.edu4Title': 'Grenzen und Konsens',
    'safetyOnboarding.edu5Body':
        'Du kannst Profile melden und blockieren, ohne dich zu '
        'rechtfertigen. Bei Bedrohung, Stalking oder Gewalt hilft die '
        'Polizei (110) oder der Notruf (112). Im Safety Center findest '
        'du weitere Wege.',
    'safetyOnboarding.edu5Hint': 'Hilfe zu holen ist Stärke, nicht Schwäche.',
    // "Connect to others": Kontaktdaten teilen
    'contactShare.title': 'Mit anderen verbinden',
    'safetyOnboarding.edu5Title': 'Hilfe holen',
    'safetyOnboarding.educationTitle': 'Sicher daten',
    'safetyOnboarding.finish': 'Fertig',
    'safetyOnboarding.moreInfo': 'Ausführliche Fassung lesen',
    'safetyOnboarding.next': 'Weiter',
    'safetyOnboarding.no': 'Nein',
    'safetyOnboarding.progress': 'Seite {current} von {total}',
    'safetyOnboarding.q1Body':
        'Es gibt keine richtige Antwort. Die Frage hilft uns nur, dich '
        'dort abzuholen, wo du gerade stehst.',
    'safetyOnboarding.q1Title': 'Hast du schon einmal eine Dating-App benutzt?',
    'safetyOnboarding.q2Body':
        'Zum Beispiel Fake-Profile, ungewollte Bilder, Druck oder '
        'Betrug. Wenn du unsicher bist, zeigen wir dir die wichtigsten '
        'Punkte.',
    'safetyOnboarding.q2Title':
        'Sind dir die Gefahren beim Online-Dating bewusst?',
    'safetyOnboarding.timeHint':
        'Die Aufklärung dauert höchstens 5 Minuten. Dein Fortschritt '
        'bleibt gespeichert.',
    'safetyOnboarding.timer': 'noch {min} Min.',
    'safetyOnboarding.yes': 'Ja',
  },
  'en': {
    'guardian.accessGrace': '{months} month(s) longer',
    'guardian.accessIndefinite': 'Until I end it',
    'guardian.accessText':
        'You decide until when your parent keeps access. Your own use of '
        'the app is not affected.',
    'guardian.accessTitle': 'How long does access remain?',
    'guardian.accessUntil': 'Access until {date}',
    'guardian.accessUntil18': 'Until your 18th birthday',
    'guardian.activeText': 'Your account is supervised by {email}.',
    'guardian.activeTitle': 'Consent active',
    'guardian.confirmEndText':
        'The consent ends immediately. Your parent will no longer receive '
        'notifications.',
    'guardian.confirmEndTitle': 'End parental access?',
    'guardian.emailHint': 'name@example.com',
    'guardian.emailLabel': 'Email address of a parent',
    'guardian.endAccessBtn': 'End parental access',
    'guardian.endedText':
        'The parental approval has ended and no longer applies.',
    'guardian.endedTextEmailDeleted':
        'The parental approval has ended. The parent\'s email address was '
        'deleted with it - it is no longer needed and no longer kept.',
    'guardian.endedTextEmailPending':
        'The parental approval has ended. The parent\'s email address is '
        'deleted when the approval ends.',
    'guardian.endedTitle': 'The approval has ended',
    'guardian.errorGeneric': 'That did not work. Please try again later.',
    'guardian.errorInvalidEmail': 'Please enter a valid email address.',
    'guardian.errorNotEligible':
        'Parental consent is only provided for 16- and 17-year-olds.',
    'guardian.errorRateLimited': 'Too many requests. Please try again later.',
    'guardian.errorSameEmail':
        'That is your own email address. Please enter the address of a '
        'parent.',
    'guardian.graceLabel': 'Grace period: {months} month(s)',
    'guardian.gracePicker': 'Months',
    'guardian.loadErrorText':
        'The supervision status could not be fetched right now. '
        'Check your connection and try again.',
    'guardian.loadErrorTitle': 'Status not loaded',
    'guardian.noConsentText':
        'For accounts aged 18 and over, no consent is needed. If you are 16 '
        'or 17, you can add a parent here - they receive an email and '
        'decide for themselves.',
    'guardian.noConsentTitle': 'No parental consent',
    'guardian.notifyFrequency.daily': 'Daily',
    'guardian.notifyFrequency.monthly': 'Monthly',
    'guardian.notifyFrequency.none': 'Never',
    'guardian.notifyFrequency.weekly': 'Weekly',
    'guardian.notifyFrequencyLabel': 'Interval',
    'guardian.notifyText':
        'Your parent is notified when a spark appears - at the interval '
        'they chose themselves. No names and no profiles are passed on.',
    'guardian.notifyTitle': 'Notifications',
    'guardian.pendingText':
        'We sent an email to {email}. The consent only becomes active once '
        'your parent opens the link in that email.',
    'guardian.pendingTitle': 'Waiting for confirmation',
    'guardian.pinLocked': 'Unlock with PIN',
    'guardian.pinText': 'Please enter the four-digit PIN your parent set.',
    'guardian.pinTitle': 'Parent area',
    'guardian.pinUnlocked': 'Unlocked',
    'guardian.pinWrong': 'The PIN is not correct.',
    'guardian.requestBtn': 'Request parental consent',
    'guardian.requestIntro':
        'For 16- and 17-year-olds, Thestia provides for the consent of '
        'those with parental responsibility. Your parent receives an email '
        'with a link and decides there. The consent is voluntary - and you '
        'can revoke it at any time.',
    'guardian.requestScreenTitle': 'Parental consent',
    'guardian.retry': 'Try again',
    'guardian.saveBtn': 'Save',
    'guardian.sectionIntro':
        'This is where you can see whether your account is supervised. For '
        '16- and 17-year-olds, Thestia provides for the consent of those '
        'with parental responsibility.',
    'guardian.sectionTitle': 'Child safety & parental access',
    'guardian.sendBtn': 'Send request',
    'guardian.sentText':
        'We sent an email to {email}. Please ask your parent to open the '
        'link in it - only then does the consent become active.',
    'guardian.sentTitle': 'Request sent',
    'guardian.skipBtn': 'Later - continue without consent',
    'guardian.transitionBtn': 'Decide now',
    'guardian.transitionEnd': 'End access now',
    'guardian.transitionGrace': 'Keep it for {months} more month(s)',
    'guardian.transitionKeep': 'Keep it for now',
    'guardian.transitionText':
        'Since your 18th birthday, you decide yourself whether your parent '
        'keeps access. Until you change something, access remains.',
    'guardian.transitionTitle': 'You are 18 now',
    'guardian.unlockTitle': 'Unlock the parent area',
    'guardian.usageFrom': 'from',
    'guardian.usageLockHint':
        'Talk to your parents - the setting can be changed in the parent '
        'area.',

    // ===================================================================
    // Selective data deletion (v0.10.0)
    // ===================================================================
    'del.title': 'Delete data',
    'guardian.usageLockText':
        'Usage time ends today at {time}. Tomorrow it starts again.',
    'guardian.usageLockTitle': 'Your usage time is over for today',
    'guardian.usageNone': 'No limit',
    'guardian.usagePinNote':
        'This setting is protected by a PIN. It can only be changed with '
        'that PIN.',
    'guardian.usageText':
        'Your parent can set a time window in which the app may be used. '
        'Outside that window, the app shows a notice.',
    'guardian.usageTitle': 'Usage time',
    'guardian.usageTo': 'until',
    'guardian.usageToggleLabel': 'Limit usage time',
    'guardian.usageWindow': 'Allowed from {from} until {to}',
    'safety.ageBody':
        'Some people state a false age. This particularly endangers young '
        'users and leads to a permanent ban when proven. Protect yourself: '
        'never blindly trust an age claim. The chat warns you about large '
        'age differences. Only meet in public places, bring your phone to '
        'a first meeting and tell a trusted person. Report suspected false '
        'age immediately via the "Wrong age" report reason. Thestia cannot '
        'verify every detail and gives no guarantee for their accuracy.',
    'safety.ageTitle': 'Age and deception',
    'safety.blockSomeone': 'Block someone',
    'safety.blockSomeoneBody':
        'Chat menu (three dots) - Block. Likes and sparks are removed; '
        'future interactions are prevented server-side. The person is not '
        'notified.',
    'safety.blockedUsers': 'Blocked users',
    'safety.blockedUsersSub':
        'People you blocked - you can unblock them again here.',
    'safety.hotline1': 'Help hotline "Violence against women"',
    'safety.hotline1Sub': '116 016 - free, 24/7, anonymous',
    'safety.hotline2': 'Telephone counselling',
    'safety.hotline2Sub': '0800 111 0 111 - free, 24/7',
    'safety.hotline3': 'klicksafe (cyberbullying & counselling)',
    'safety.hotline3Sub': 'klicksafe.de',
    'safety.hotline4': 'Stalking helpline (Weisser Ring)',
    'safety.hotline4Sub': 'weisser-ring.de - 116 006',
    'safety.linkFailed': 'Could not open link.',
    'safety.myReports': 'My reports',
    'safety.myReportsSub': 'Reports you wrote and the status of their review.',
    'safety.noBlocked': 'You have not blocked anyone.',
    'safety.noReports': 'You have not written any reports yet.',
    'safety.protectOwnImages': 'Protect your own images',
    'safety.protectOwnImagesBody':
        'Images in incoming messages are blurred by default (settings - '
        'chat safety). Your own photos remain hidden until mutual quiz '
        'success.',
    'safety.reportSomeone': 'Report someone',
    'safety.reportSomeoneBody':
        'In the chat via the flag icon at the top right, or by long-pressing '
        'an image. Your last messages are transparently submitted as context '
        'and personally reviewed by support.',
    'safety.sectionHelp': 'Immediate help',
    'safety.sectionProtect': 'Protection in Thestia',
    'safety.stalkingBody':
        'If someone is stalking you online (or offline): 1. Do not reply, '
        'deliberately end contact. 2. Document everything: screenshots with '
        'dates, chat history, profile names. 3. Block in the app and inform '
        'us via the report function. We can permanently suspend accounts. '
        '4. Change passwords and enable 2FA (settings). 5. If threatened or '
        'afraid: contact the police (110) or 116 006.',
    'safety.stalkingGuide': 'Stalking guide',
    'safety.unblock': 'Unblock',
    // Mood
    'mood.title': 'Mood of the day',
    'safety.unblockFailed': 'Unblock failed. Please try again.',
    'safetyOnboarding.ack1':
        'Your data belongs to you: share your phone number, address or '
        'workplace only when you are sure.',
    'safetyOnboarding.ack2':
        'Nobody has to pressure you into anything - not into a meeting, '
        'not into photos, not into money.',
    'safetyOnboarding.ack3':
        'You can report and block at any time. You do not have to '
        'explain yourself.',
    'safetyOnboarding.ackBody':
        'Thestia connects people who do not know each other yet. That is '
        'where the opportunity lies - and the risk. Take two minutes for '
        'the most important rules.',
    'safetyOnboarding.ackButton': 'I understand',
    'safetyOnboarding.ackTitle': 'Before you start',
    'safetyOnboarding.back': 'Back',
    'safetyOnboarding.edu1Body':
        'Photos, names and jobs can be faked. A profile is not proof. '
        'Ask for a short video call or a public meeting before you share '
        'personal things.',
    'safetyOnboarding.edu1Hint':
        'Trust grows - it does not arrive with the first photo.',
    'safetyOnboarding.edu1Title': 'Not everything is real',
    'safetyOnboarding.edu2Body':
        'Phone numbers, addresses, employers and ID photos are sensitive. '
        'Share them only when you know the person well. Screenshots can '
        'pass on everything - even disappearing messages.',
    'safetyOnboarding.edu2Hint': 'A screenshot is taken faster than you think.',
    'safetyOnboarding.edu2Title': 'Your data belongs to you',
    'safetyOnboarding.edu3Body':
        'Meet during the day in a public place. Tell someone you know '
        'where you are and when you want to be back. Arrange your own '
        'way home.',
    'safetyOnboarding.edu3Hint':
        'You do not have to give anyone your address - not even for a '
        'pickup.',
    'safetyOnboarding.edu3Title': 'The first meeting',
    'safetyOnboarding.edu4Body':
        'A yes only applies to exactly what is happening. A no, a pause '
        'or pulling back is a no. Nobody owes you photos, time or '
        'closeness - and you do not owe them to anyone either.',
    'safetyOnboarding.edu4Hint':
        'Pressure is not getting to know someone. You may leave at any '
        'time.',
    'safetyOnboarding.edu4Title': 'Boundaries and consent',
    'safetyOnboarding.edu5Body':
        'You can report and block profiles without justifying yourself. '
        'For threats, stalking or violence, contact the police (110) or '
        'the emergency line (112). The Safety Center lists more ways to '
        'get help.',
    'safetyOnboarding.edu5Hint': 'Getting help is strength, not weakness.',
    // "Connect to others": sharing contact details
    'contactShare.title': 'Connect to others',
    'safetyOnboarding.edu5Title': 'Getting help',
    'safetyOnboarding.educationTitle': 'Dating safely',
    'safetyOnboarding.finish': 'Done',
    'safetyOnboarding.moreInfo': 'Read the long version',
    'safetyOnboarding.next': 'Next',
    'safetyOnboarding.no': 'No',
    'safetyOnboarding.progress': 'Page {current} of {total}',
    'safetyOnboarding.q1Body':
        'There is no right answer. The question only helps us meet you '
        'where you are right now.',
    'safetyOnboarding.q1Title': 'Have you used a dating app before?',
    'safetyOnboarding.q2Body':
        'For example fake profiles, unsolicited images, pressure or '
        'fraud. If you are unsure, we will show you the most important '
        'points.',
    'safetyOnboarding.q2Title':
        'Are you aware of the dangers of online dating?',
    'safetyOnboarding.timeHint':
        'This takes at most 5 minutes. Your progress is saved.',
    'safetyOnboarding.timer': '{min} min left',
    'safetyOnboarding.yes': 'Yes',
  },
};
