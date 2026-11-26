// Die Texte des Themas 'verwaltung' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fügt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsVerwaltung = {
  'de': {
    'admin.actionFailed': 'Aktion fehlgeschlagen (Status {status}).',
    'admin.ageAi': 'Alter: Angabe {stated}, KI {est} (Abweichung {dev})',
    'admin.ageNoAi': 'Alter: Angabe {stated} (keine KI-Schätzung)',
    'admin.appealFinding': 'Lokaler Befund: {label} ({score} %)',
    'admin.appealSubmitted': 'Eingereicht: {time}',
    'admin.approve': 'Freigeben',
    'admin.approveTooltip': 'Genehmigen',
    'admin.attachments': 'Anhänge: {count} · {time}',
    'admin.auditEmpty': 'Keine Auto-Freigaben zur Stichprobe.',
    'admin.auditTitle': 'Stichproben: Auto-Freigaben',
    'admin.ban': 'Sperren',
    'admin.banFailed': 'Sperren fehlgeschlagen.',
    'admin.banHint':
        'Hinweis: Mit User-ID wird zusätzlich der bestehende Account '
        'sofort gesperrt (Sessions ungültig). Mit nur E-Mail ist die '
        'Neu-Registrierung blockiert.',
    'admin.banReason': 'Begründung (Pflicht)',
    'admin.banReasonHint': 'Warum wird der Nutzer gesperrt?',
    'admin.banTarget': 'E-Mail oder User-ID',
    'admin.banTargetHint': 'z. B. aus der Meldungs-Mail kopiert',
    'admin.banUser': 'Nutzer sperren',
    'admin.banned': 'Nutzer gesperrt.',
    'admin.bannedBy': '{time} · von {by}',
    'admin.browserOpenFailed': 'Browser konnte URL nicht öffnen',
    'admin.cancel': 'Abbrechen',
    'admin.close': 'Schließen',
    'admin.decideFailed': 'Entscheidung fehlgeschlagen: {error}',
    'admin.deniedBody': 'Du hast keine Berechtigung, diesen Bereich zu öffnen.',
    'admin.emptyAppealsTitle': 'Keine Einsprüche',
    'admin.emptyBansTitle': 'Keine Sperren',
    'admin.emptyBugsTitle': 'Keine neuen Bugs',
    'admin.emptyModerationTitle': 'Keine offenen Moderationen',
    'admin.emptyReportsTitle': 'Nichts zu bearbeiten',
    'admin.emptyVerificationsTitle': 'Keine offenen Verifizierungen',
    'admin.error': 'Fehler: {error}',
    'admin.locationsCheckedAt': 'Letzte Prüfung: {date}',
    'admin.locationsEmpty': 'Kein Profil ist beim Standort-Check aufgefallen.',
    'admin.locationsHint':
        'Diese Profile sind beim Standort-Check aufgefallen: der '
        'Standort sprang um mehr als 15 km oder die '
        'Fortbewegungsgeschwindigkeit lag über 300 km/h. Das ist ein '
        'Hinweis, kein Verstoß - niemand wird dadurch aus der '
        'Discovery genommen und niemand gesperrt.',
    'admin.locationsTitle': 'Auffällige Standort-Prüfungen',
    'admin.locationsUnverified': 'Altersprüfung offen',
    'admin.locationsVerified': 'Altersprüfung abgeschlossen',
    'admin.mailAll': 'Alle',
    'admin.mailDatenschutz': 'Datenschutz',
    'admin.mailEmptyBody': '(kein Text)',
    'admin.mailEmptyText':
        'Hier landen die Mails, die an die Adresse des Betreibers gehen. '
        'Je nach Postfach kommen sie erst nach dem nächsten Abruf hier an.',
    'admin.mailEmptyTitle': 'Keine Mails',
    'admin.mailKinderschutz': 'Kinderschutz',
    'admin.mailPresse': 'Presse',
    'admin.mailReadOnly':
        'Nur zum Lesen - antworten geht über das Mail-Programm.',
    'admin.mailSonstiges': 'Sonstiges',
    'admin.mailSupport': 'Support',
    'admin.mailWithoutSubject': '(ohne Betreff)',
    'admin.messagesAttached': '{count} Nachricht(en) beigelegt',
    'admin.metricNewBugs': 'Neue Bugs',
    'admin.metricNewBugsSub': 'letzte 24 Stunden',
    'admin.metricPendingChecks': 'Offene Prüfungen',
    'admin.minChars': 'Mindestens 3 Zeichen',
    'admin.minorCase':
        'Minderjährigenfall - bitte von Hand prüfen. Personen bis 21 '
        'Jahre werden nie automatisch freigegeben.',
    'admin.noAppeals': 'Keine offenen Bild-Einsprüche.',
    'admin.noBans': 'Keine Sperren vorhanden.',
    'admin.noBugs': 'Keine Bug-Reports vorhanden.',
    'admin.noDescription': '(ohne Beschreibung)',
    'admin.noModeration': 'Keine ausstehenden Moderationen.',
    'admin.noReports': 'Keine Meldungen vorhanden.',
    'admin.noVerifications': 'Keine offenen Verifizierungen.',
    'admin.noVideoUrl': 'keine Video-URL erhalten',
    'admin.notifySub':
        'Enthält die Begründung und den Weg zum Entsperrungsantrag',
    'admin.notifyUser': 'Nutzer per E-Mail informieren',
    'admin.rejectTooltip': 'Ablehnen',
    'admin.rejectWithVideo': 'Ablehnen (Video wird gelöscht)',
    'admin.reportResolveFailed': 'Konnte Meldung nicht abschließen: {error}',
    'admin.reportedUser': 'Gemeldeter Nutzer: {id}',
    'admin.reporter': 'Reporter: {id} (gehasht)',
    'admin.required': 'Pflichtfeld',
    'admin.resolved': 'Bearbeitet',
    'admin.retry': 'Erneut versuchen',
    'admin.reviewFailed': 'Review fehlgeschlagen: {error}',
    'admin.searchBans': 'Sperren durchsuchen',
    'admin.searchBansClear': 'Suche leeren',
    'admin.searchBansEmpty':
        'Keine Sperre passt zu dieser Suche. Suchbegriff löschen oder '
        'anders schreiben.',
    'admin.searchBansHint': 'E-Mail, Begründung oder Person',
    'admin.searchBansResult': '{count} von {total} Sperren',
    'admin.statusApproved': 'Freigegeben',
    'admin.statusNotified': 'Quittiert',
    // Admin-Überarbeitung (ROADMAP Zeile 807): Kennzahlen-Zeile,
    // Suche im Sperren-Tab, einheitliche Leerzustände.
    'admin.metricOpenReports': 'Offene Meldungen',
    'admin.statusOpen': 'Offen',
    'admin.statusPending': 'ausstehend',
    'admin.statusRejected': 'Abgelehnt',
    'admin.tabAppeals': 'Bild-Prüfung',
    'admin.tabBans': 'Sperren',
    'admin.tabBugs': 'Bug-Reports',
    'admin.tabLocations': 'Standort',
    'admin.tabMail': 'Post',
    'admin.tabModeration': 'Moderation',
    'admin.tabReports': 'Meldungen',
    'admin.tabVerification': 'Verifizierung',
    'admin.title': 'Admin-Bereich',
    'admin.unban': 'Entsperren',
    'admin.unbanBody':
        '{email} kann sich wieder registrieren und anmelden. Der '
        'Entsperrungsantrag sollte vorher geprüft worden sein.',
    'admin.unbanFailed': 'Entsperren fehlgeschlagen.',
    'admin.unbanTitle': 'Entsperren?',
    'admin.unbanned': '{email} wurde entsperrt.',
    'admin.unknown': 'unbekannt',
    'admin.user': 'Nutzer: {id}',
    'admin.videoFailed': 'Video konnte nicht geladen werden: {error}',
    'admin.watchVideo': 'Video ansehen',
    'verify.autoBody':
        'Die Altersprüfung war unauffällig. Du erhältst sofort das '
        'Verifiziert-Zeichen. Dein Video bleibt für Stichproben erhalten.',
    'verify.autoTitle': 'Verifiziert!',
    'verify.badge': 'Verifiziert',
    'verify.cameraDisclosureAccept': 'Kamera freigeben',
    'verify.cameraDisclosureBody':
        'Um dein Alter zu schätzen, braucht die App Zugriff auf Kamera und Mikrofon. Die Aufnahme startet erst, wenn du unten bestätigst. Das Bild wird ausgewertet und danach nicht gespeichert.',
    'verify.cameraDisclosureTitle': 'Kamera und Mikrofon für die Altersprüfung',
    'verify.cameraError': 'Kamera konnte nicht initialisiert werden: {error}',
    // Prominente Kamera-Offenlegung: Google Play verlangt für CAMERA
    // dieselbe vorangezeigte Begründung wie für das Mikrofon. Ohne
    // Kamera ist die Altersprüfung nicht möglich - deshalb endet eine
    // Ablehnung in einem erklärenden Zustand und nicht in einer Sackgasse.
    // Der Text nennt auch den Ton: die Challenge "speakNumber" verlangt
    // eine gesprochene Zahl, und die Aufnahme läuft mit
    // enableAudio: true. Wer nur die Kamera ankündigt, hält RECORD_AUDIO
    // für mitgeteilt - das wäre eine unvollständige Offenlegung.
    'verify.cameraDeclined':
        'Ohne Kamera können wir dein Alter nicht einschätzen. Du kannst sie jederzeit in den Einstellungen erlauben.',
    'verify.challenge.action.smile': 'lächeln',
    // Chat-Details + Anruf
    'chat.title': 'Chat',
    'verify.challenge.base.makeGesture': 'Mache die angezeigte Geste.',
    'verify.challenge.base.smile': 'Lächle kurz in die Kamera.',
    'verify.challenge.base.speakNumber': 'Sage die angezeigte Zahl laut vor.',
    'verify.challenge.base.turnHead': 'Drehe den Kopf langsam.',
    'verify.challenge.direction.left_right': 'links und rechts',
    'verify.challenge.direction.right_left': 'rechts und links',
    'verify.challenge.gesture.blink': 'Einmal blinzeln',
    'verify.challenge.gesture.brows': 'Augenbrauen hochziehen',
    'verify.challenge.gesture.tongue': 'Zunge rausstrecken',
    'verify.challenge.task': 'Deine Aufgabe:',
    'verify.cleanupBody':
        'Die Verifizierung ist fertig. Standort, Kamera und Mikrofon '
        'brauchst du dafür nicht mehr - möchtest du sie wieder '
        'deaktivieren?',
    'verify.cleanupLater': 'Später',
    'verify.cleanupLocation': 'Standort',
    'verify.cleanupOpen': 'Kamera & Mikrofon',
    'verify.cleanupTitle': 'Berechtigungen wieder deaktivieren?',
    'verify.cta': 'Jetzt verifizieren',
    'verify.ctaSub':
        'Kurzes Selbstvideo. Eine lokale KI prüft dein Alter auf dem '
        'Gerät, auffällige Fälle sieht der Support persönlich.',
    'verify.doneTitle': 'Verifizierung',
    'verify.errorTitle': 'Fehler',
    'verify.info.1': 'Das Video wird **lokal verschlüsselt** gespeichert.',
    'verify.info.2':
        'Nach dem Einreichen liegt es in einem **privaten Speicher**. Nur '
        'der Support kann es zur Prüfung ansehen.',
    'verify.info.3':
        'Es dient der **persönlichen Prüfung durch den Support** '
        '(Mensch-Verifizierung).',
    'verify.info.4':
        'Es wird **niemals** öffentlich angezeigt oder an Dritte '
        'weitergegeben.',
    'verify.info.5':
        'Du kannst es jederzeit löschen; bei Ablehnung wird es automatisch '
        'entfernt.',
    'verify.info.6':
        'Nimm **Kopfbedeckung, Kopfhörer, Sonnenbrille und Maske ab**: '
        'Das Gesicht muss frei erkennbar sein, sonst prüft der Support '
        'manuell nach.',
    'verify.infoAiLimits':
        'Die Altersschätzung ist eine KI-Schätzung und kann '
        'ungenau sein. Sie ersetzt keine Prüfung durch Menschen: '
        'Abweichungen und Zweifelsfälle werden von Hand geprüft.',
    'verify.infoBody':
        'Um sicherzugehen, dass echte Menschen die App nutzen, machst du '
        'ein kurzes Selbstvideo (5 bis 15 Sekunden).',
    'verify.infoCardTitle': 'Was passiert mit deinem Video?',
    'verify.locationBody':
        'Zusätzlich fragen wir **einmalig** deinen GPS-Standort ab. Dies '
        'hilft uns, massenhaft Fake-Accounts vom selben Ort oder Gerät zu '
        'erkennen. Der Standort wird **nur** für diese Sicherheitsprüfung '
        'gespeichert und nicht für Matching genutzt.',
    'verify.locationTitle': 'Einmalige Standortabfrage',
    'verify.otherUnderReview': 'Verifizierung läuft',
    'verify.pendingBody':
        'Dein Video wurde sicher übermittelt. Der Support prüft es '
        'persönlich, auch dein angegebenes Alter. Sobald es freigegeben '
        'ist, erscheint das Verifiziert-Zeichen in deinem Profil. Dein '
        'Konto bleibt bis dahin voll nutzbar.',
    'verify.pendingChip': 'Prüfung läuft',
    'verify.pendingHint':
        'Dein Video wird vom Support geprüft. Das dauert meist nur '
        'wenige Stunden.',
    'verify.pendingReason.deviation':
        'Warum manuell? Die KI-Schätzung weicht {years} Jahre von deinem '
        'angegebenen Alter ab - der Support gleicht das mit deinem Video ab.',
    'verify.pendingReason.faces':
        'Warum manuell? Es wurde nicht genau ein Gesicht erkannt - '
        'der Support prüft dein Video persönlich.',
    'verify.pendingReason.noAi':
        'Warum manuell? Die Alters-KI konnte auf diesem Gerät nicht '
        'laufen - der Support prüft dein Video persönlich.',
    'verify.pendingReason.noStated':
        'Warum manuell? Dein angegebenes Alter konnte nicht verifiziert '
        'werden - der Support prüft dein Video persönlich.',
    'verify.pendingTitle': 'Video eingereicht!',
    'verify.processing':
        'Video wird ausgewertet. Bitte kurz warten, das kann bis zu '
        'einer halben Minute dauern.',
    'verify.recordFaceHint':
        'Gesicht frei zeigen: keine Kopfbedeckung, Kopfhörer oder '
        'Sonnenbrille.',
    'verify.recordHint':
        'Mindestens 5 Sekunden, maximal 15 Sekunden aufnehmen.',
    'verify.recording': 'Aufnahme: {s} s',
    'verify.start': 'Video-Verifizierung starten',
    'verify.stateUnderReview': 'Wird geprüft',
    // Der Hinweis auf "Aktuelles" (Startbildschirm). Eigene Texte, weil
    // die für den Modus-Sperr-Dialog geschrieben sind ("Für diesen
    // Modus musst du ...") - auf dem Startbildschirm geht es nicht um
    // einen Modus, sondern um den Vollzugang.
    'home.verifyHintUnverifiedTitle': 'Dein Profil ist noch nicht verifiziert',
    'verify.stateUnverified': 'Nicht verifiziert',
    'verify.stopHint': 'Tippe erneut zum Stoppen (Auto-Stopp bei 15 s)',
    'verify.submitFailed':
        'Einreichen fehlgeschlagen. Bitte prüfe deine Internetverbindung '
        'und versuche es erneut.',
    'verify.taskTitle': 'Deine Aufgabe:',
    'verify.toApp': 'Zur App',
  },
  'en': {
    'admin.actionFailed': 'Action failed (status {status}).',
    'admin.ageAi': 'Age: stated {stated}, AI {est} (deviation {dev})',
    'admin.ageNoAi': 'Age: stated {stated} (no AI estimate)',
    'admin.appealFinding': 'Local finding: {label} ({score} %)',
    'admin.appealSubmitted': 'Submitted: {time}',
    'admin.approve': 'Approve',
    'admin.approveTooltip': 'Approve',
    'admin.attachments': 'Attachments: {count} · {time}',
    'admin.auditEmpty': 'No auto approvals to spot-check.',
    'admin.auditTitle': 'Spot checks: auto approvals',
    'admin.ban': 'Ban',
    'admin.banFailed': 'Ban failed.',
    'admin.banHint':
        'Note: With a user ID, the existing account is additionally '
        'banned immediately (sessions invalid). With only an email, '
        're-registration is blocked.',
    'admin.banReason': 'Reason (required)',
    'admin.banReasonHint': 'Why is the user being banned?',
    'admin.banTarget': 'Email or user ID',
    'admin.banTargetHint': 'e.g. copied from the report email',
    'admin.banUser': 'Ban user',
    'admin.banned': 'User banned.',
    'admin.bannedBy': '{time} · by {by}',
    'admin.browserOpenFailed': 'Browser could not open URL',
    'admin.cancel': 'Cancel',
    'admin.close': 'Close',
    'admin.decideFailed': 'Decision failed: {error}',
    'admin.deniedBody': 'You do not have permission to open this area.',
    'admin.emptyAppealsTitle': 'No appeals',
    'admin.emptyBansTitle': 'No bans',
    'admin.emptyBugsTitle': 'No new bugs',
    'admin.emptyModerationTitle': 'No open moderations',
    'admin.emptyReportsTitle': 'Nothing to handle',
    'admin.emptyVerificationsTitle': 'No open verifications',
    'admin.error': 'Error: {error}',
    'admin.locationsCheckedAt': 'Last check: {date}',
    'admin.locationsEmpty': 'No profile stood out during the location check.',
    'admin.locationsHint':
        'These profiles stood out during the location check: the '
        'location jumped by more than 15 km or the speed of travel '
        'was above 300 km/h. This is a hint, not an offence - nobody '
        'is removed from discovery and nobody is banned because of '
        'it.',
    'admin.locationsTitle': 'Suspicious location checks',
    'admin.locationsUnverified': 'Age verification pending',
    'admin.locationsVerified': 'Age verification completed',
    'admin.mailAll': 'All',
    'admin.mailDatenschutz': 'Privacy',
    'admin.mailEmptyBody': '(no text)',
    'admin.mailEmptyText':
        'Emails sent to the operator address end up here. Depending on the '
        'mailbox, they arrive after the next fetch.',
    'admin.mailEmptyTitle': 'No emails',
    'admin.mailKinderschutz': 'Child safety',
    'admin.mailPresse': 'Press',
    'admin.mailReadOnly': 'Read only - replies go through your email program.',
    'admin.mailSonstiges': 'Other',
    'admin.mailSupport': 'Support',
    'admin.mailWithoutSubject': '(no subject)',
    'admin.messagesAttached': '{count} message(s) attached',
    'admin.metricNewBugs': 'New bugs',
    'admin.metricNewBugsSub': 'last 24 hours',
    'admin.metricPendingChecks': 'Open checks',
    'admin.minChars': 'At least 3 characters',
    'admin.minorCase':
        'Minor case - please review by hand. People aged 21 or younger '
        'are never approved automatically.',
    'admin.noAppeals': 'No pending image appeals.',
    'admin.noBans': 'No bans.',
    'admin.noBugs': 'No bug reports.',
    'admin.noDescription': '(no description)',
    'admin.noModeration': 'No pending moderation.',
    'admin.noReports': 'No reports.',
    'admin.noVerifications': 'No pending verifications.',
    'admin.noVideoUrl': 'no video URL received',
    'admin.notifySub': 'Contains the reason and how to request unban',
    'admin.notifyUser': 'Notify user by email',
    'admin.rejectTooltip': 'Reject',
    'admin.rejectWithVideo': 'Reject (video will be deleted)',
    'admin.reportResolveFailed': 'Could not resolve report: {error}',
    'admin.reportedUser': 'Reported user: {id}',
    'admin.reporter': 'Reporter: {id} (hashed)',
    'admin.required': 'Required',
    'admin.resolved': 'Resolved',
    'admin.retry': 'Try again',
    'admin.reviewFailed': 'Review failed: {error}',
    'admin.searchBans': 'Search bans',
    'admin.searchBansClear': 'Clear search',
    'admin.searchBansEmpty':
        'No ban matches this search. Clear the search term or try a '
        'different one.',
    'admin.searchBansHint': 'Email, reason or person',
    'admin.searchBansResult': '{count} of {total} bans',
    'admin.statusApproved': 'Approved',
    'admin.statusNotified': 'Acknowledged',
    // Admin rework (ROADMAP line 807): metrics row,
    // search in the bans tab, uniform empty states.
    'admin.metricOpenReports': 'Open reports',
    'admin.statusOpen': 'Open',
    'admin.statusPending': 'pending',
    'admin.statusRejected': 'Rejected',
    'admin.tabAppeals': 'Image review',
    'admin.tabBans': 'Bans',
    'admin.tabBugs': 'Bug reports',
    'admin.tabLocations': 'Location',
    'admin.tabMail': 'Inbox',
    'admin.tabModeration': 'Moderation',
    'admin.tabReports': 'Reports',
    'admin.tabVerification': 'Verification',
    'admin.title': 'Admin area',
    'admin.unban': 'Unban',
    'admin.unbanBody':
        '{email} can register and sign in again. The unban request '
        'should have been reviewed first.',
    'admin.unbanFailed': 'Unban failed.',
    'admin.unbanTitle': 'Unban?',
    'admin.unbanned': '{email} was unbanned.',
    'admin.unknown': 'unknown',
    'admin.user': 'User: {id}',
    'admin.videoFailed': 'Video could not be loaded: {error}',
    'admin.watchVideo': 'Watch video',
    'verify.autoBody':
        'The age check was inconspicuous. You immediately receive the '
        'verified badge. Your video is kept for spot checks.',
    'verify.autoTitle': 'Verified!',
    'verify.badge': 'Verified',
    'verify.cameraDisclosureAccept': 'Allow camera',
    'verify.cameraDisclosureBody':
        'To estimate your age, the app needs access to the camera and the microphone. Capture starts only after you confirm below. The image is evaluated and not saved afterwards.',
    'verify.cameraDisclosureTitle':
        'Camera and microphone for age verification',
    'verify.cameraError': 'Camera could not be initialized: {error}',
    // Prominent camera disclosure: Google Play requires the same up-front
    // explanation for CAMERA as for the microphone. Without a camera the
    // age check is impossible, so declining ends in an explanatory state
    // rather than a dead end. The text names audio too: the "speakNumber"
    // challenge needs a spoken number and recording runs with
    // enableAudio: true. Announcing only the camera would leave
    // RECORD_AUDIO undisclosed.
    'verify.cameraDeclined':
        'Without the camera we cannot estimate your age. You can allow it in the settings at any time.',
    'verify.challenge.action.smile': 'smile',
    // Chat details + call
    'chat.title': 'Chat',
    'verify.challenge.base.makeGesture': 'Do the displayed gesture.',
    'verify.challenge.base.smile': 'Smile briefly into the camera.',
    'verify.challenge.base.speakNumber': 'Say the displayed number out loud.',
    'verify.challenge.base.turnHead': 'Slowly turn your head.',
    'verify.challenge.direction.left_right': 'left and right',
    'verify.challenge.direction.right_left': 'right and left',
    'verify.challenge.gesture.blink': 'Blink once',
    'verify.challenge.gesture.brows': 'Raise your eyebrows',
    'verify.challenge.gesture.tongue': 'Stick out your tongue',
    'verify.challenge.task': 'Your task:',
    'verify.cleanupBody':
        'Verification is complete. You no longer need location, camera '
        'and microphone for it - would you like to turn them off again?',
    'verify.cleanupLater': 'Later',
    'verify.cleanupLocation': 'Location',
    'verify.cleanupOpen': 'Camera & microphone',
    'verify.cleanupTitle': 'Revoke permissions again?',
    'verify.cta': 'Verify now',
    'verify.ctaSub':
        'Short selfie video. A local AI checks your age on-device, '
        'conspicuous cases are seen personally by support.',
    'verify.doneTitle': 'Verification',
    'verify.errorTitle': 'Error',
    'verify.info.1': 'The video is stored **encrypted locally**.',
    'verify.info.2':
        'After submission it sits in **private storage**. Only support '
        'can view it for review.',
    'verify.info.3':
        'It serves **personal review by support** (human verification).',
    'verify.info.4':
        'It is **never** shown publicly or shared with third parties.',
    'verify.info.5':
        'You can delete it any time; if rejected it is removed '
        'automatically.',
    'verify.info.6':
        'Take off **headwear, headphones, sunglasses and masks**: '
        'Your face must be fully visible, otherwise support reviews '
        'manually.',
    'verify.infoAiLimits':
        'The age estimate is an AI estimate and can be inaccurate. It '
        'does not replace a check by a person: deviations and doubtful '
        'cases are reviewed by hand.',
    'verify.infoBody':
        'To make sure real people use the app, you record a short selfie '
        'video (5 to 15 seconds).',
    'verify.infoCardTitle': 'What happens to your video?',
    'verify.locationBody':
        'We additionally ask for your GPS location **once**. This helps '
        'us detect masses of fake accounts from the same place or device. '
        'The location is stored **only** for this security check and not '
        'used for matching.',
    'verify.locationTitle': 'One-time location check',
    'verify.otherUnderReview': 'Verification in progress',
    'verify.pendingBody':
        'Your video was transmitted securely. Support reviews it '
        'personally, including your stated age. Once approved, the '
        'verified badge appears in your profile. Your account remains '
        'fully usable until then.',
    'verify.pendingChip': 'Review in progress',
    'verify.pendingHint':
        'Your video is being reviewed by support. This usually takes '
        'only a few hours.',
    'verify.pendingReason.deviation':
        'Why manual? The AI estimate deviates {years} years from your '
        'stated age - support will reconcile this with your video.',
    'verify.pendingReason.faces':
        'Why manual? Exactly one face could not be detected - '
        'support will review your video personally.',
    'verify.pendingReason.noAi':
        'Why manual? The age AI could not run on this device - '
        'support will review your video personally.',
    'verify.pendingReason.noStated':
        'Why manual? Your stated age could not be verified - '
        'support will review your video personally.',
    'verify.pendingTitle': 'Video submitted!',
    'verify.processing':
        'Processing your video. Please wait, this can take up to half '
        'a minute.',
    'verify.recordFaceHint':
        'Keep your face visible: no headwear, headphones or sunglasses.',
    'verify.recordHint': 'Record at least 5 seconds, at most 15 seconds.',
    'verify.recording': 'Recording: {s} s',
    'verify.start': 'Start video verification',
    'verify.stateUnderReview': 'Under review',
    // The hint on the home screen ("Aktuelles"). Own texts, because the
    // ones for the mode-lock dialog ("For this mode you have to ...") do
    // not fit here - this is about full access, not about one mode.
    'home.verifyHintUnverifiedTitle': 'Your profile is not verified yet',
    'verify.stateUnverified': 'Not verified',
    'verify.stopHint': 'Tap again to stop (auto-stop at 15 s)',
    'verify.submitFailed':
        'Submission failed. Please check your internet connection and '
        'try again.',
    'verify.taskTitle': 'Your task:',
    'verify.toApp': 'To the app',
  },
};
