# WispDating v0.7.1-Beta – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


Das Aufräum-Update zu v0.7.0: Die Sprach-Umstellung ist jetzt komplett,
einige Ecken wurden poliert und ein wichtiger Passkey-Fehler ist
behoben. Danke an alle Tester von v0.7.0!

## Hinzugefügt

**Einstellungen überleben Neuinstallationen** Entfernung, Altersspanne,
„Ich suche", Bundesland-Filter, Ort und Geschlechts-Filter werden jetzt
zusätzlich sicher auf dem Server gespeichert und nach der Anmeldung
automatisch wiederhergestellt - nichts geht mehr verloren.

**Moderation: Nutzer sperren mit Begründung** Im Team-Bereich gibt es
jetzt ein Formular zum Sperren von Konten (E-Mail oder User-ID +
verpflichtende Begründung). Mit User-ID wird der Account sofort
gesperrt; der Betroffene kann optional per E-Mail informiert werden und
hat weiterhin den Weg über den Entsperrungsantrag. Entsperren ist mit
einem Klick möglich.

**Bild-Meldung mit KI-Vorprüfung** Chat-Bilder werden nie automatisch
gescannt - deine Bilder bleiben Ende-zu-Ende-verschlüsselt. Meldest du
aber ein Bild, prüft eine KI genau dieses eine Bild sofort auf
unangemessene Inhalte. Du siehst das Ergebnis direkt: Bestätigt die KI
deine Meldung, wird unser Team automatisch mit Bild, deinem Report und
dem KI-Ergebnis informiert. Sieht die KI kein Problem, du aber schon,
kannst du eine manuelle Prüfung durch unser Team veranlassen.

Hinweis: Diese automatische Vorprüfung ist optional konfigurierbar.
Ist sie nicht aktiv, funktioniert die Meldung genauso - dein Bild geht
dann direkt (mit deinem Report) zur manuellen Prüfung an unser Team.
Ausblick: In einer künftigen Version (0.8.0) läuft die KI vollständig
lokal in der App - dann verlässt das gemeldete Bild das Gerät vor der
Prüfung überhaupt nicht mehr.

## Behoben

**Viereck in der Statusleiste** Server-Push-Nachrichten zeigten neben
der Uhrzeit weiterhin ein Viereck (das App-Launcher-Symbol). Jetzt
erscheint dort das runde Wisp-Zeichen.

**Profil nach Neuinstallation nicht mehr leer** Bei einer Neuinstallation
blieben Name, Bio und alle Profildaten leer - der Abgriff auf dem Server
fragte eine Datenbank-Spalte ab, die es dort nie gab, und schlug deshalb
immer fehl. Auf dem alten Gerät war das nicht aufgefallen, weil dort eine
lokale Kopie lag. Das ist behoben (plus Wiederholungsversuch bei
Netzproblemen).

**Einrichtung erscheint garantiert nie wieder** Wer die Einrichtung
einmal abgeschlossen hat, sieht sie bei keiner Anmeldung und keiner
Neuinstallation erneut - auch nicht kurz und auch dann nicht, wenn
einzelne Punkte übersprungen wurden oder das Netz bei der Anmeldung
zickt. (Technisch: neues Gesamt-Flag serverseitig; bestehende Konten
wurden automatisch als fertig markiert.)

**Sprach-Button im Anmelde-Look** Das Übersetzen-Symbol auf Anmelde- und
Registrierungs-Screen ist jetzt ein runder Button in der Hauptfarbe der
App - gleicher Stil wie der „Einloggen"-Button, nur rund.

**Benachrichtigungs-Icon rund** In der Statusleiste erschien neben der
Uhrzeit ein Viereck - jetzt das runde Wisp-Zeichen.

**Einrichtung nach Neuinstallation zuverlässig weg** Bisher konnten
kurzzeitige Netzprobleme beim Login dazu führen, dass die Einrichtung
erneut erschien, obwohl sie längst abgeschlossen war: Der Abruf des
Server-Stands hatte ein knappes Zeitlimit ohne Wiederholung, und beim
Speichern des Abschlusses zählte ein still fehlgeschlagener Schreibvorgang
als Erfolg. Beides ist jetzt abgesichert (mehrere Versuche, Kontrolle
durch Zurücklesen, sichtbarer Hinweis falls es doch nicht klappt).

**Passkey-Login funktioniert wieder** Bei aktiviertem Sicherheitscheck
(CAPTCHA) verlangt der Server auch für den Passkey-Login ein Bestätigungs-
Token. Die App ließ diesen Schritt aus, sodass der Server die Anfrage
ablehnte („Server hat die Passkeyanfrage abgelehnt“) – noch bevor der
Fingerabdruck-Dialog erschien. Jetzt erscheint zuerst der gewohnte
Sicherheitscheck, danach die Passkey-Abfrage.

**Stadt/Ort wird nach der Einrichtung übernommen** Bei Standort-Erkennung
und manueller Eingabe blieb der Ortsname nur im Eingabefeld - er wurde nie
ins Profil-Feld `city` geschrieben und vom nächsten Server-Sync mit leer
überschrieben. Jetzt wird der Ortsname lokal im Profil UND serverseitig
persistiert.

**Keine Registrierung mit vergebener E-Mail** Wer sich mit einer
E-Mail-Adresse registrierte, die es schon gab, landete beim
„E-Mail bestätigen" - aber es kam nie eine Mail (der Server meldet da
keinen Fehler, damit niemand Adressen abfragen kann). Jetzt sagt die App
direkt: bereits registriert, bitte einloggen oder Passwort zurücksetzen.

**Ladekreis ab dem allerersten Moment** Beim Start war während des
Ladens nur das stehende Logo zu sehen. Jetzt dreht sich direkt ein
Ladekreis darunter, wie gewohnt.

**Deutsch funktioniert jetzt überall** Wer die App auf Deutsch gestellt
hatte, sah beim Anmelden einen Fehlerbildschirm. Ursache war ein fehlendes
Sprachpaket unter der Haube. Login und Registrierung funktionieren jetzt
in beiden Sprachen.

**Einrichtung erscheint nicht mehr erneut** Der Abschluss der Einrichtung
wurde nur „nach bestem Bemühen" auf dem Server gesichert. Schlug das
still fehl, kam die Einrichtung nach der nächsten Anmeldung wieder. Jetzt
wirst du bei einem Fehlschlag informiert, und die App heilt den Stand beim
nächsten Login von selbst. Bei einer ganz neuen Registrierung erscheint
die Einrichtung dafür garantiert genau einmal.

**Standort-Erkennung ohne Einfrieren** Wer „Standort ermitteln" drückte,
während er die Altersspanne anpasste, konnte die App einfrieren. Das ist
behoben. Zusätzlich rutscht der linke Regler der Altersspanne nicht mehr
von selbst zurück.

**Audio-Vorstellung** Wer die Aufnahme wiederholte, bekam einen Fehler
(„Ressource existiert bereits"). Erneutes Aufnehmen überschreibt jetzt.

**2FA „Später erinnern"** Der Button hat nicht zurückgeführt. Jetzt kommst
du zuverlässig zurück, egal woher du die 2FA-Einrichtung geöffnet hast.

**App-Start-Logo** Beim Start wurde das runde Benachrichtigungs-Icon
gezeigt, außerdem so groß gerendert, dass die Schrift abgeschnitten war.
Jetzt startet die App mit dem vollständigen WispDating-Logo in richtiger
Größe.

**Farbwelten komplett** Die Rahmen von Eingabefeldern (z. B. in der
Einrichtung und beim Profil bearbeiten) folgten hartnäckig der alten
Pink-Farbe. Jetzt übernehmen alle fünf neuen Farbwelten auch die Rahmen.

**Registrierung** Ein Server-Rest aus der Invite-Code-Zeit hat die offene
Registrierung blockiert. Ist behoben (Server-Update 063, siehe Hinweis
unten).

**Begrüßung** Ohne hinterlegten Namen heißt es jetzt „Hallo, du!" statt
des holprigen „Hallo, schönen Menschen!"

## Neu

**Ortsname statt Koordinaten** Wenn die App deinen Standort automatisch
erkennt, trägt sie jetzt deinen Ortsnamen ein (z. B. „Berlin, Berlin")
statt Zahlen. Deine genaue Position wird dabei weiterhin nie angezeigt.

**Sprach-Button neu** Das Übersetzen-Symbol öffnet ein kleines Menü zum
Umschalten zwischen Deutsch und Englisch. Er sitzt jetzt auf Höhe der
Überschrift (die doppelte Variante und die überflüssige „Einloggen"-
Zeile sind weg, alles rückt nach oben).

**Schutz für ungespeicherte Profil-Änderungen** Wenn du „Profil
bearbeiten" mit Änderungen verlässt (Tab-Wechsel oder Zurück), fragt die
App: Speichern, Verwerfen oder bleiben? Und schlägt das Speichern an
einer Validierung fehl, steht der Hinweis direkt am Speichern-Button.

## Geändert

**Einheitliches Applogo** Alle Logo-Varianten (App-Icon, Adaptive-Icon,
Splash, Benachrichtigung) stammen jetzt aus einer einzigen Quelldatei.
Hinweis: Das Applogo und dessen Implementierung sind noch in Arbeit -
Feinschliff folgt in einem der nächsten Updates.

**Sprache klarer bedienbar** In der Anmeldung hat das Übersetzungs-Symbol
jetzt einen farbigen Kreis-Hintergrund (passt sich jedem Design an). In
den Einstellungen ist jetzt das ganze Feld „Sprache" bedienbar und klappt
nach unten auf.

**Einstellungen aufgeräumt** „Account löschen" gibt es nur noch unter
„Datenschutz & Account" (inkl. 2FA-Bestätigung). Die Passkey-Diagnose ist
für Endnutzer nicht mehr sichtbar.

**Datenschutz & Account** Auftragsverarbeiter aktualisiert (Brevo,
Cloudflare, Netlify ergänzt, Hugging Face entfernt). Unter
„Einwilligungen" führen Buttons direkt zu den Standort- und
Benachrichtigungs-Einstellungen deines Geräts.

**Einstellungen & Datenschutz jetzt komplett zweisprachig** (Deutsch/
Englisch)

**Kleinere Korrekturen** „Keine neuen Funken"-Karte schneidet bei großen
Schriftgrößen keine Buchstaben mehr ab; der Entdecken-Hinweis sagt jetzt
„Funke" statt „Match".


- **Einrichtung nur noch per Button**: Swipen zwischen den Schritten ist
  deaktiviert. Die Buttons führen die nötigen Prüfungen und Speicherungen
  aus. Wer vorher swipe-te, übersprang sie, und Angaben landeten nicht im
  Profil.
- Englisch ist jetzt auch auf dem Anmelde-Screen vollständig (inkl.
  Sicherheitscheck und allen Fehlermeldungen)
- Alle Aufklappmenüs sind abgerundet, auch in der Einrichtung
  (Beziehungsart, Filter, Bundesland)
- Texte wurden überarbeitet: keine Gedankenstriche mehr in Sätzen

## Für die Technik-Interessierten

- flutter_localizations integriert (Material-Texte für de/en)
- Reverse-Geocoding über den Plattform-Geocoder, Fallback auf grobe Region
- Passkeys: assetlinks.json im Format der Android-API (Fingerprints mit
  Doppelpunkten) plus web-Eintrag; die apk-key-hash-Origins wurden auf die
  tatsächlichen Signing-Keys korrigiert (Release UND Debug)
- Server-Migration 063: Invite-Reste von Bestandsservern entfernt

## Für Betreiber (vor dem Verteilen)

1. `supabase db push` (Migration 063)
2. `passkey-assets/` auf Netlify deployen (korrigierte assetlinks.json)
3. Supabase Dashboard → Authentication → WebAuthn: Origins korrigieren
   (falschen apk-key-hash löschen, Release- und Debug-Hash eintragen)
4. Optional: assetlinks.json auch unter wispdating.de hinterlegen
   (siehe passkey-assets/ASSETLINKS_ROOTDOMAIN.md)

Feedback? Wie immer über den Bug-Report in den Einstellungen. Viel Spaß
beim Funken sprühen!
