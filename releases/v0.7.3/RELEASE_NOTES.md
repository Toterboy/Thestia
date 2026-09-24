# WispDating v0.7.3-Beta – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


Fix-Release: Stabilität und Usability. Danke an alle Tester von v0.7.2!

## Neu

- **Angemeldete Geräte**: Einstellungen → Datenschutz & Account →
  „Angemeldete Geräte". Zeigt alle Geräte, auf denen du eingeloggt bist,
  und meldet dich mit einem Tastendruck überall außer auf diesem Gerät ab.
- **Passkeys verwalten**: Einstellungen listen alle Passkeys des Kontos
  (Name, erstellt, zuletzt genutzt) und erlauben Umbenennen/Löschen.
- **Themefarbe bleibt am Konto**: Die Farbwahl wird serverseitig
  gespeichert und direkt beim Login wieder angewendet – auch nach einer
  App-Neuinstallation. Gleiches gilt für Entfernung und Altersspanne.
- **Suchradius dauerhaft gespeichert**: Änderungen an Entfernung,
  Altersspanne und Suchradius-Modus sichern sich automatisch (entprellt)
  auf dem Server – „Speichern" wartet auf den Server-Sync und meldet
  Fehlschläge klar.
- **Dating-Hour-Regeln** erscheinen jetzt nur noch einmal pro Konto,
  nicht bei jeder Neuinstallation erneut.
- **Altersspanne im Profil-Editor**: mit altersbasierter Klemmung und
  zwei gekoppelten Reglern (Mindest-/Höchstalter).
- **Passkey-Anmeldung mit Ladekreis**: derselbe klare „Anmeldung läuft…"-
  Kreis wie bei der Passwort-Anmeldung.
- **Profil-Seite**: dezenter Strich am rechten Rand zeigt, dass die Seite
  weiter nach unten geht (Profil-/Bug-melden-Buttons nicht mehr versteckt).
- **Bild-Meldungen: Nachweis-Pflicht**: Beim Senden eines Chat-Bildes wird
  nur dessen Prüfsumme (kein Bild!) serverseitig registriert. Wird ein
  Bild gemeldet, wird geprüft, ob es tatsächlich in diesem Chat geflossen
  ist – untergeschobene fremde Bilder werden abgelehnt.
- **Dating Hour: konsistente Zählung**: Die 20-Teilnehmer-Prüfung zählt
  nur mindestens 24 Stunden alte Konten – kurzlebige Fake-Accounts können
  das Event weder starten noch die Anzeige täuschen.
- **Dating Hour: Teilnehmer-Fortschritt**: Im Event-Screen steht „X von
  20 Teilnehmern" mit Fortschrittsbalken.

## Behoben

- **Name & Daten nach Passkey-Anmeldung leer**: Die Passkey-Anmeldung
  durchlief nicht dieselbe Kette wie die Passwort-Anmeldung (Token-
  Speicherung, Signal-User-ID, Server-Sync) – jetzt identischer Ablauf.
- **Passkey erstellen trotz 2FA**: Der 2FA-Status wurde aus einem ver-
  alteten oder nie geladenen Cache gelesen, die erforderliche Bestätigung
  fehlte und der Server lehnte still ab. Jetzt frisch geladen.
- **Passkey + 2FA**: Die Bestätigungsabfrage erscheint zuverlässig; ist
  der Passkey schon vorhanden, gibt es eine klare Meldung statt einer
  kryptischen Ablehnung.
- **Passkey-Erstellen „Anfrage abgebrochen"**: Doppelte Anläufe werden
  verhindert (Pre-Cancel-Race + Doppel-Tap-Schutz).
- **Passkey-Fehler mit Grund**: Lehnt der Server ab, wird der kurze
  Server-Grund in der Meldung angezeigt.
- **2FA klar angezeigt**: Die Einstellungs-Kache zeigt den aktuellen
  Stand direkt vom Server statt aus dem Zwischenspeicher.
- **„Später erinnern" schließt die 2FA-Seite** jetzt ordentlich, statt
  sie immer wieder zu öffnen.
- **Automatische Abmeldung nach Stunden**: Der Sitzungs-Token läuft nach
  etwa einer Stunde ab; schlug die einmalige Auffrischung fehl (z. B.
  kurz kein Netz), war man draußen. Jetzt wird mehrfach aufgefrischt.
- **Ladekreis beim Anmelden**: Direkt nach „Einloggen" erscheint
  „Anmeldung läuft…" – keine tote Phase mehr.
- **Speichern-Nachfrage im Profil-Editor** greift jetzt zuverlässig auch
  bei Tab-Wechsel und Bottom-Navigation – verifiziert durch neue
  Widget-Tests.
- **Altersspanne 18–18 entklemmt**: Bei identischen Werten froren die
  Regler ein; jetzt zwei getrennte Slider, die sich mitnehmen.
- **Weißes Viereck bei Benachrichtigungen** behoben (Icon hatte keinen
  Alpha-Kanal); jetzt eine klare Herz-Silhouette.
- **Alle Dropdowns abgerundet**: Die fünf Dropdowns im Profil-Editor
  folgen der 16-px-Rundung.
- **Dating-Hour-Zeit robuster**: Schlägt der Serverzeit-Abruf fehl,
  versucht die App es mehrfach (Retry + Backoff), bevor sie auf die
  Gerätezeit zurückfällt; die Beitritts-Prüfung bleibt serverseitig.
- **Zurück-Geste in der Dating Hour** führt zur Seite davor statt zur
  Haupt-Navigation.
- **Dating-Hour-Meldung präzisiert**: „Deine Teilnahme meldest du über
  ‚Ich bin dabei' am Event-Tag an."
- **Server-Sync robuster**: Die Schreib-Verifikation liest gezielt nur
  die geschriebenen Schlüssel zurück; Präferenzen/Flags fallen bei
  fehlenden 071-Spalten automatisch auf den Kern-Umfang zurück.
- **Geräte-Liste**: zeigt bei Problemen die konkrete Ursache (z. B.
  „Migration 071 fehlt auf dem Server") und formatierte Gerätenamen.

## Server (vor dem Rollout)

1. Migrationen **068** (Teilnehmer-Zähler, Bild-Hash), **071** (Geräte,
   Theme, DH-Intro), **072** (öffentliche Profil-View) und **073**
   (Geräte-Härtung) einspielen – für die Geräte-Tabelle alternativ das
   idempotente `supabase/repair_auth_devices.sql`.
2. Passkey-„Relying Party Origins" auf die **SHA-256**-Werte setzen
   (SHA-1 matcht nie): Anleitung mit Werten und Symptom-Tabelle in
   `docs/PASSKEYS_SERVER_SETUP.md`. Der Debug-Key gehört nur in lokale
   Umgebungen, nicht in die Produktions-Origins.
