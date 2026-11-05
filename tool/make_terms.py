"""Erzeugt die Nutzungsbedingungen (DE + EN).

WARUM (Recherche 05.11.2026): Fuer eine Webanwendung mit
Nutzergeneriertem Inhalt verlangt DSA Art. 16 die "Bedingungen fuer die
Vereinbarung von Leistungen" (Nutzungsbedingungen) und Art. 17 eine
Erklaerungspflicht fuer Moderationsentscheidungen. Play Store und
F-Droid verlangen zusaetzlich eine "User-Generated-Content-Policy".

Die Seiten entstehen aus einem Generator (tool/make_terms.py), damit
beide Sprachfassungen nicht auseinanderlaufen und die Seiten bei
Aenderungen neu erzeugt werden koennen.

Die Inhalte sind bewusst auf das beschraenkt, was das Projekt
tatsaechlich tut:
  * Mindestalter 16, ab 18 volljährig
  * elterliche Freigabe fuer 16/17-Jaehrige
  * Verhaltensregeln (Respekt, keine Belästigung, kein Nacktbild etc.)
  * Moderation und Rechte bei Verstossen
  * Haftung und Freischaltung
  * Daten und ihre Loeschung (Verweis auf die Datenschutzerklaerung)
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / 'passkey-assets'

DE = {
    'titel': 'Nutzungsbedingungen',
    'lead': 'Diese Bedingungen gelten für die Nutzung der App Thestia und der Website thestia.de.',
    'bloecke': [
        ('h2', '1. Wer diese Bedingungen akzeptiert'),
        ('p', 'Mit der Registrierung in der App Thestia akzeptierst du diese '
              'Nutzungsbedingungen. Wer die App im Auftrag einer anderen '
              'Person nutzt, muss deren Einwilligung vorliegen.'),
        ('h2', '2. Mindestalter'),
        ('p', 'Thestia ist ab 16 Jahren nutzbar. Wer 16 oder 17 Jahre alt '
              'ist, kann die App auch ohne Zustimmung der '
              'Sorgeberechtigten nutzen: Nach § 3a JUG kann eine Person ab '
              'dem vollendeten 16. Lebensjahr selbst einwilligen, und '
              'niemand wird an der Nutzung gehindert, weil eine Zustimmung '
              'ausbleibt.'),
        ('p', 'Die Elternfreigabe ist freiwillig. Wenn du 16 oder 17 bist '
              'und dir die elterliche Aufsicht wichtig ist, kannst du sie '
              'anfordern: Du bekommst dann ein Zeitfenster, in dem die App '
              'genutzt werden darf, Hinweise auf neue Funken und einen '
              'geschützten Bereich für deine Eltern. Die Freigabe ist '
              'jederzeit und ohne Angabe von Gründen widerrufbar. Mit dem '
              'Ende der Freigabe endet auch die Aufsicht, und die '
              'E-Mail-Adresse der Eltern wird gelöscht.'),
        ('p', 'Egal ob eine Elternfreigabe vorliegt: Für 16- und '
              '17-Jährige gelten immer die Regeln aus Abschnitt 4. Ab dem '
              '18. Geburtstag entscheidet die Person selbst über den '
              'Zugang der Sorgeberechtigten.'),
        ('h2', '3. Was du auf Thestia tust'),
        ('ul', [
            'Du behandelst andere Menschen mit Respekt. Beleidigungen, '
            'Belästigungen, Mobbing und rassistische, sexistische, '
            'homophobe oder andere menschenfeindliche Äußerungen sind '
            'untersagt.',
            'Du versuchst nicht, andere zu täuschen - weder mit falschen '
            'Angaben zu Person, Alter oder Geschlecht noch mit '
            'fremden Bildern, die du nicht selbst aufgenommen hast.',
            'Du lädst keine Inhalte hoch, die gegen das Gesetz '
            'verstoßen, die Rechte Dritter verletzen oder die '
            'Privatsphäre anderer verletzen. Das betrifft auch '
            'Nacktbilder und Bilder von Personen, die das Foto nicht '
            'freigegeben haben.',
            'Du verbreitest keine Inhalte, die eine Person gegen '
            'Willen identifizierbar machen, und du machst keine '
            'Screenshots oder Aufnahmen von Chats mit anderen Personen, '
            'um sie ohne deren Einwilligung weiterzugeben.',
            'Du nutzt keine automatisierten Werkzeuge, um Nutzer '
            'zu massenhaft anzuschreiben oder Inhalte automatisch '
            'zu verbreiten.',
        ]),
        ('h2', '4. Minderjährige und besondere Schutzbedürfnisse'),
        ('p', 'Für 16- und 17-Jährige gelten zusätzlich diese Regeln:'),
        ('ul', [
            'Du siehst nur andere 16- und 17-Jährige, und nur diese '
            'sehen dich. Die Begegnungen sind beidseitig gefiltert: '
            'Wer 18 oder älter ist, erreicht dich nicht.',
            'Deine Entfernung wird nicht angezeigt, auch nicht grob.',
            'Dein Suchradius ist begrenzt: höchstens 25 Kilometer oder '
            'Personen im selben Bundesland.',
            'Transit Spark, die Nahbereichs-Funktion für Begegnungen '
            'unterwegs, steht dir nicht zur Verfügung. Sie ist ab 18 '
            'Jahren.',
            'Deine Fotos sind nur für andere 16- und 17-Jährige '
            'sichtbar, und die Einstellung dafür kannst du nicht '
            'ändern.',
            'Es ist verboten, Sex, Nacktheit oder sexuelle Handlungen '
            'anzubieten oder darzustellen.',
            'Wird ein Kind oder Jugendlicher Opfer sexueller '
            'Gewalt oder Ausbeutung, gilt die Meldestelle auf '
            'thestia.de/kinderschutz. Wir melden bestätigte Fälle an '
            'die zuständigen Stellen und sperren das betroffene Konto '
            'sofort.',
        ]),
        ('h2', '5. Moderation, Sperren und Begründung'),
        ('p', 'Wir prüfen gemeldete Inhalte und Verhaltensweisen. Bei '
              'einem Verstoß können wir Inhalte entfernen, Funktionen '
              'einschränken und Konten sperren.'),
        ('p', 'Wenn wir eine Entscheidung über einen gemeldeten Inhalt '
              'oder ein Konto treffen, teilen wir die tragenden Gründe '
              'mit. Du kannst gegen die Entscheidung Widerspruch '
              'einlegen - schreibe dazu an moderation@thestia.de. Die '
              'Widerspruchsprüfung erfolgt durch eine Person, die nicht '
              'an der ursprünglichen Entscheidung beteiligt war.'),
        ('h2', '6. Deine Daten'),
        ('p', 'Wie wir deine Daten verarbeiten, steht in der '
              'Datenschutzerklärung. Dort ist auch beschrieben, wie '
              'lange wir sie speichern und wie du deine Daten '
              'exportierst oder löschen lässt. Für 16- und '
              '17-Jährige endet die Freigabe automatisch mit dem Ende '
              'der Aufsicht; dabei wird auch die E-Mail-Adresse des '
              'Elternteils gelöscht.'),
        ('h2', '7. Haftung und Freischaltung'),
        ('p', 'Thestia wird ohne Gewähr bereitgestellt. Für die '
              'Richtigkeit, Vollständigkeit oder Aktualität der Inhalte '
              'anderer Nutzer haften wir nicht. Eine Haftung für '
              'entgangene Chancen, entgangenen Gewinn oder sonstige '
              'Schäden ist ausgeschlossen, soweit gesetzlich zulässig.'),
        ('p', 'Die App ist ein Open-Source-Projekt unter der GNU '
              'Affero General Public License, Version 3. Der Quellcode '
              'ist öffentlich einsehbar. Das gilt auch für diese '
              'Bedingungen: Wer den Quellcode weiterverbreitet, '
              'muss diese Änderungen ebenfalls verbreiten.'),
        ('h2', '8. Änderungen'),
        ('p', 'Wir passen diese Bedingungen an, wenn sich die App oder '
              'das Recht ändert. Über wesentliche Änderungen '
              'informieren wir dich in der App, bevor sie in Kraft '
              'treten.'),
        ('h2', '9. Kontakt'),
        ('p', 'Fragen zu diesen Bedingungen beantwortet '
              'support@thestia.de. Das Impressum mit der ladungsfähigen '
              'Anschrift findest du unter thestia.de/impressum.'),
    ],
}

EN = {
    'titel': 'Terms of use',
    'lead': 'These terms apply to the use of the Thestia app and of the website thestia.de.',
    'bloecke': [
        ('h2', '1. Who accepts these terms'),
        ('p', 'By registering in the Thestia app you accept these terms of '
              'use. If you use the app on behalf of someone else, their '
              'consent must be in place.'),
        ('h2', '2. Minimum age'),
        ('p', 'Thestia may be used from the age of 16. Someone aged 16 or '
              '17 can also use the app without the consent of those with '
              'parental responsibility: under Sec. 3a JUG a person may '
              'consent themselves from their 16th birthday onwards, and '
              'nobody is prevented from using the app because consent is '
              'missing.'),
        ('p', 'The parental approval is voluntary. If you are 16 or 17 and '
              'you value the supervision by your parents, you can request '
              'it: you then get a time window in which the app may be '
              'used, notices about new sparks and a protected area for '
              'your parents. The approval can be revoked at any time and '
              'without giving reasons. When it ends, the supervision ends '
              'as well, and the parents\' email address is deleted.'),
        ('p', 'Whether or not a parental approval exists: for 16 and 17 year '
              'olds the rules in section 4 always apply. From the 18th '
              'birthday onwards, the person decides themselves about the '
              'access of their parents.'),
        ('h2', '3. What you do on Thestia'),
        ('ul', [
            'You treat other people with respect. Insults, harassment, '
            'bullying and racist, sexist, homophobic or otherwise '
            'hostile statements are not allowed.',
            'You do not deceive others - neither with false details about '
            'person, age or gender, nor with photos of other people that '
            'you did not take yourself.',
            'You do not upload content that breaks the law, infringes the '
            'rights of others or violates the privacy of others. This '
            'includes nude images and photos of people who did not '
            'consent to the photo.',
            'You do not spread content that makes a person identifiable '
            'against their will, and you do not take or share screenshots '
            'or recordings of chats with other people without their '
            'consent.',
            'You do not use automated tools to message users in bulk or to '
            'spread content automatically.',
        ]),
        ('h2', '4. Minors and people who need particular protection'),
        ('p', 'These additional rules apply to 16 and 17 year olds:'),
        ('ul', [
            'You only see other 16 and 17 year olds, and only they see '
            'you. Encounters are filtered on both sides: anyone aged 18 or '
            'older cannot reach you.',
            'Your distance is not shown, not even roughly.',
            'Your search radius is limited: at most 25 kilometres or '
            'people in the same federal state.',
            'Transit Spark, the proximity feature for encounters on the '
            'move, is not available to you. It is for 18 year olds and '
            'older.',
            'Your photos are only visible to other 16 and 17 year olds, '
            'and you cannot change that setting.',
            'It is forbidden to offer or depict sex, nudity or sexual acts.',
            'If a child or young person is a victim of sexual violence or '
            'exploitation, the reporting point at thestia.de/kinderschutz '
            'applies. We report confirmed cases to the competent bodies '
            'and suspend the account concerned immediately.',
        ]),
        ('h2', '5. Moderation, suspension and reasons'),
        ('p', 'We review reported content and behaviour. In case of a '
              'breach we may remove content, restrict functions and '
              'suspend accounts.'),
        ('p', 'When we decide on a reported item or an account, we '
              'communicate the reasons on which the decision is based. '
              'You can object to the decision - write to '
              'moderation@thestia.de. The objection is reviewed by a '
              'person who was not involved in the original decision.'),
        ('h2', '6. Your data'),
        ('p', 'How we process your data is set out in the privacy '
              'policy. It also describes how long we keep the data and how '
              'you can export or have your data deleted. For 16 and 17 '
              'year olds, the approval ends automatically together with the '
              'supervision; the parent\'s email address is deleted as '
              'well.'),
        ('h2', '7. Liability and open source'),
        ('p', 'Thestia is provided without guarantee. We are not liable '
              'for the correctness, completeness or timeliness of content '
              'provided by other users. Liability for lost opportunity, '
              'lost profit or other damage is excluded as far as legally '
              'permitted.'),
        ('p', 'The app is an open source project under the GNU Affero '
              'General Public License, version 3. The source code is '
              'publicly available. This also applies to these terms: '
              'whoever redistributes the source code must also '
              'redistribute these changes.'),
        ('h2', '8. Changes'),
        ('p', 'We adapt these terms when the app or the law changes. We '
              'will inform you in the app about material changes before '
              'they take effect.'),
        ('h2', '9. Contact'),
        ('p', 'support@thestia.de answers questions about these terms. '
              'The imprint with the serviceable address is at '
              'thestia.de/impressum.'),
    ],
}


# Design und Sprachknopf kommen aus tool/web_theme.py. Damit ist die
# Seite genau so gebaut, wie apply_theme sie erzeugt - und der
# Idempotenz-Gate der CI ("Web-Theme wiederholbar") ist erfuellt.
import sys as _sys
_sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from web_theme import (CSS, KOPF_HTML,  # noqa: E402
                       beschreibung, sprachknopf)


def seite(sprache, daten, pfad):
    if sprache == 'de':
        canonical = 'https://thestia.de/nutzungsbedingungen'
        sprach_ziel = '/en/nutzungsbedingungen'
        sprach_label = 'EN'
    else:
        canonical = 'https://thestia.de/en/nutzungsbedingungen'
        sprach_ziel = '/nutzungsbedingungen'
        sprach_label = 'DE'

    teile = ['<!DOCTYPE html>', '<html lang="%s">' % sprache, '<head>',
             '  <meta charset="UTF-8">',
             '  <meta name="viewport" content="width=device-width, '
             'initial-scale=1">',
             '  <link rel="canonical" href="%s">' % canonical,
             '  <title>%s - Thestia</title>' % daten['titel'],
             '  <meta name="description" content="%s">'
             % beschreibung('nutzungsbedingungen.html', sprache),
             '  <style>',
             # Eigenes CSS VOR dem gemeinsamen (siehe Kommentar oben:
             # sonst ist strip_theme/apply_theme nicht wiederholbar).
             '    body {',
             '        font-family: -apple-system, BlinkMacSystemFont, '
             '"Segoe UI", Roboto, sans-serif;',
             '        max-width: 44rem; margin: 0 auto; padding: 3rem 1.5rem;',
             '    }',
             '%s</style>' % CSS,
             '</head>',
             '<body>',
             *KOPF_HTML.replace(
                 '__SPRACHKNOPF__',
                 sprachknopf(sprach_ziel, sprach_label)).split('\n'),
             '<main class="inhalt">',
             '<h1>%s</h1>' % daten['titel'],
             '<p class="lead">%s</p>' % daten['lead']]
    for art, inhalt in daten['bloecke']:
        if art == 'h2':
            teile.append('  <h2>%s</h2>' % inhalt)
        elif art == 'p':
            teile.append('  <p>%s</p>' % inhalt)
        elif art == 'ul':
            teile.append('  <ul>')
            for li in inhalt:
                teile.append('    <li>%s</li>' % li)
            teile.append('  </ul>')
    teile.append('</main>')
    teile.append('</body>')
    teile.append('</html>')
    pfad.write_text('\n'.join(teile) + '\n', encoding='utf-8', newline='\n')
    print('  %-34s %d Bloecke' % (str(pfad.relative_to(ROOT)), len(daten['bloecke'])))


seite('de', DE, A / 'nutzungsbedingungen.html')
seite('en', EN, A / 'en' / 'nutzungsbedingungen.html')
print('fertig')
