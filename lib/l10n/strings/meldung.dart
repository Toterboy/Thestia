// Die Texte des Themas 'meldung' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsMeldung = {
  'de': {
    'report.aiEscalated':
        'Bild, dein Report und das KI-Ergebnis wurden automatisch an '
        'unser Team gesendet.',
    'report.aiNotNotified':
        'Hinweis: Das Team konnte nicht per E-Mail benachrichtigt werden '
        '- deine Meldung ist trotzdem gespeichert.',
    'report.aiResult': 'KI-Ergebnis',
    'report.analyzing': 'Bild wird lokal analysiert…',
    'report.checkingSub': 'Die KI prüft das gemeldete Bild.',
    'report.checkingTitle': 'Bild wird geprüft…',
    'report.confirmed': 'Meldung bestätigt',
    'report.detailsOptional': 'Zusätzliche Details (optional)',
    'report.failedTitle': 'Meldung fehlgeschlagen',
    'report.forwardBtn': 'Zur manuellen Prüfung',
    'report.forwardFailed':
        'Weiterleitung fehlgeschlagen. Bitte später erneut versuchen.',
    'report.forwardedBody':
        'Deine Meldung wurde zur manuellen Prüfung an unser Team '
        'weitergeleitet - inklusive Bild, deinem Report und dem '
        'KI-Ergebnis. Danke für deine Hilfe!',
    'report.forwardedTitle': 'Weitergeleitet',
    'report.imageTitle': 'Bild melden: {name}',
    'report.imageUnavailable': 'Dieses Bild kann leider nicht gemeldet werden.',
    'report.noLocalModel':
        'Lokale Prüfung nicht verfügbar (Modell fehlt). Die Meldung '
        'läuft über den serverseitigen Fallback.',
    'report.retryLater': 'Bitte später erneut versuchen.',
    'report.sendDone': 'Meldung gesendet. Danke für deine Hilfe!',
    'report.sendNotDelivered':
        'Meldung gespeichert, aber nicht an unser Team übermittelt. Bitte '
        'versuche es erneut. Bei einem Hinweis auf Kindesmissbrauch '
        'schreib bitte zusätzlich an kinderschutz@thestia.de.',
    'report.sendReport': 'Meldung absenden',
    'report.type.childSafety': 'Hinweis auf Kindesmissbrauch (CSAE/CSAM)',
    'report.type.default': 'Meldung',
    'report.type.fakeProfile': 'Fake Profil / Identitätsmissbrauch',
    'report.type.harassment': 'Belästigung / Beleidigungen',
    'report.type.inappropriateContent':
        'Unangemessene Inhalte (Bilder/Nachrichten)',
    'report.type.other': 'Sonstiges',
    'report.type.spam': 'Spam / Werbung',
    'report.type.wrongAge': 'Falsches Alter / Alter stimmt nicht',
    'report.userTooltip': 'Nutzer melden',
  },
  'en': {
    'report.aiEscalated':
        'Image, your report and the AI result were automatically sent '
        'to our team.',
    'report.aiNotNotified':
        'Note: The team could not be notified by email - your report '
        'is saved anyway.',
    'report.aiResult': 'AI result',
    'report.analyzing': 'Analyzing image locally…',
    'report.checkingSub': 'The AI is checking the reported image.',
    'report.checkingTitle': 'Checking image…',
    'report.confirmed': 'Report confirmed',
    'report.detailsOptional': 'Additional details (optional)',
    'report.failedTitle': 'Report failed',
    'report.forwardBtn': 'Forward for manual review',
    'report.forwardFailed': 'Forwarding failed. Please try again later.',
    'report.forwardedBody':
        'Your report was forwarded to our team for manual review - '
        'including image, your report and the AI result. Thank you for '
        'your help!',
    'report.forwardedTitle': 'Forwarded',
    'report.imageTitle': 'Report image: {name}',
    'report.imageUnavailable': 'This image cannot be reported, unfortunately.',
    'report.noLocalModel':
        'Local check unavailable (model missing). The report uses the '
        'server-side fallback.',
    'report.retryLater': 'Please try again later.',
    'report.sendDone': 'Report sent. Thank you for your help!',
    'report.sendNotDelivered':
        'Report saved, but not delivered to our team. Please try again. '
        'In case of a child safety concern, also write to '
        'kinderschutz@thestia.de.',
    'report.sendReport': 'Send report',
    'report.type.childSafety': 'Child sexual abuse concern (CSAE/CSAM)',
    'report.type.default': 'Report',
    'report.type.fakeProfile': 'Fake profile / identity abuse',
    'report.type.harassment': 'Harassment / insults',
    'report.type.inappropriateContent':
        'Inappropriate content (images/messages)',
    'report.type.other': 'Other',
    'report.type.spam': 'Spam / advertising',
    'report.type.wrongAge': 'Wrong age / age does not match',
    'report.userTooltip': 'Report user',
  },
};
