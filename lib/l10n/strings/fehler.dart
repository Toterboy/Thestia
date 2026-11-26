// Die Texte des Themas 'fehler' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsFehler = {
  'de': {
    'bug.camera': 'Kamera',
    'bug.descLabel': 'Beschreibung *',
    'bug.descLong': 'Maximal {n} Zeichen erlaubt.',
    'bug.descMissing': 'Bitte gib eine kurze Beschreibung ein.',
    'bug.descShort': 'Beschreibung zu kurz.',
    'bug.gallery': 'Galerie',
    'bug.github': 'Bug auf GitHub melden',
    'bug.githubBody':
        'Diese Meldung ist öffentlich auf GitHub sichtbar. Trage dein '
        'Problem dort als Issue ein.',
    'bug.limits':
        'Erlaubt sind maximal {images} Bilder im Format jpg, jpeg oder '
        'png und {text} Zeichen Text. Es werden keine weiteren '
        'persönlichen Daten versendet.',
    'bug.preview': 'Vorschau',
    'bug.privateBody':
        'Alternativ kannst du den Bug auch direkt und privat per Email '
        'melden. Die Meldung wird über Brevo an das Support-Team '
        'weitergeleitet. Sie ist nicht öffentlich einsehbar.',
    'bug.send': 'Absenden',
    'bug.title': 'Bug melden',
    'bugreport.badFormat':
        'Bitte wähle eine Bilddatei im Format jpg, jpeg oder png.',
    'bugreport.defaultSummary': 'Bug Report',
    'bugreport.maxImages': 'Maximal {n} Bilder erlaubt.',
    'bugreport.notSent':
        'Übermittlung konnte nicht abgeschlossen werden. '
        'Bitte versuche es später erneut.',
    'bugreport.prepareFailed':
        'Screenshot konnte nicht aufbereitet werden '
        '(Metadaten-Entfernung fehlgeschlagen) und wurde nicht angehängt.',
    'bugreport.sendFailed':
        'Übermittlung fehlgeschlagen. Bitte versuche es später erneut.',
    'bugreport.sent': 'Danke, dein Bug Report wurde übermittelt',
  },
  'en': {
    'bug.camera': 'Camera',
    'bug.descLabel': 'Description *',
    'bug.descLong': 'At most {n} characters allowed.',
    'bug.descMissing': 'Please enter a short description.',
    'bug.descShort': 'Description too short.',
    'bug.gallery': 'Gallery',
    'bug.github': 'Report bug on GitHub',
    'bug.githubBody':
        'This report is publicly visible on GitHub. Please file your '
        'issue there.',
    'bug.limits':
        'At most {images} images in jpg, jpeg or png format and {text} '
        'characters of text are allowed. No further personal data is sent.',
    'bug.preview': 'Preview',
    'bug.privateBody':
        'Alternatively you can report the bug directly and privately by '
        'email. The report is forwarded via Brevo to the support team. '
        'It is not publicly visible.',
    'bug.send': 'Send',
    'bug.title': 'Report bug',
    'bugreport.badFormat':
        'Please choose an image file in jpg, jpeg or png format.',
    'bugreport.defaultSummary': 'Bug Report',
    'bugreport.maxImages': 'Maximum {n} images allowed.',
    'bugreport.notSent':
        'Submission could not be completed. '
        'Please try again later.',
    'bugreport.prepareFailed':
        'Screenshot could not be prepared '
        '(metadata removal failed) and was not attached.',
    'bugreport.sendFailed': 'Submission failed. Please try again later.',
    'bugreport.sent': 'Thanks, your bug report has been submitted',
  },
};
