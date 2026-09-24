# WispDating v0.8.1 – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


**Stabilität & Profilbild-Sicherheit** – Follow-up zu v0.8.0.

## Neu

- **Profilbild-Prüfung mit klarem Ergebnis-Popup**: Nach dem Zuschneiden
  zeigt die App sofort das Ergebnis der lokalen NSFW-Prüfung – Haken mit
  „Dein Bild ist okay" oder X mit dem lokalen Befund.
- **Einspruchs-Verfahren**: Bei einem Befund gibt es drei Wege –
  „Verstanden" (Bild verwerfen), „Anderes Bild wählen" oder **„Einspruch
  einlegen"**. Das abgelehnte Bild wird dabei NIEMALS als Profilbild
  hochgeladen: Es geht in einen geschützten Prüfungsbereich (nur
  Eigentümer + Team lesen können ihn), wo das Team es manuell freigeben
  oder ablehnen kann.
- **Entscheidungs-Benachrichtigung**: Nach der Prüfung erhält der Nutzer
  eine Push-Benachrichtigung; in der App kann ein freigegebenes Bild mit
  einem Tap als Profilbild übernommen werden (dabei wird es erst JETZT
  clientseitig verschlüsselt und hochgeladen), bei Ablehnung wird das
  Bild aufgeräumt.
- **Admin: neuer Reiter „Bild-Prüfung"** mit Bildvorschau, Befund,
  Eingangsdatum und Freigeben/Ablehnen.
- **Safety Center komplett zweisprachig** (Sofort-Hilfe, Hotlines,
  Schutz-Abschnitte, Stalking-Leitfaden).

## Behoben

- **App-Freeze/ANR behoben**: Dekodieren + Neu-Encodieren von Fotos
  (EXIF-Entfernung bei jedem Chat-Bild-Versand und Profilbild-Pick)
  lief im UI-Thread und konnte die App mehrere Sekunden komplett
  einfrieren. Diese Operationen laufen jetzt in Hintergrund-Isolates –
  ebenso die Avatar-Entschlüsselung und die NSFW-Bildvorverarbeitung.
- **Profilbild-Vorschau sofort**: Das gewählte Bild erscheint direkt im
  Editor; Profil, Vorschau und QR-Teilen laden Bilder ohne Wartezeit
  (Speicher-Cache); der QR-Screen zeigt jetzt das echte Profilbild.
- **Sichtbarkeits-Meldung**: Beim Wechsel Jeder ↔ Nur Funken erscheint
  keine „Pause beendet"-Meldung mehr.
- **Dating Hour**: „Täglich" korrigiert zu „samstags".
- **Runde Klick-Animation** in Admin- und Interessen-TabBars.
- **Analyzer**: 0 Issues.

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.8.1-play.apk | Google Play / direkte Verteilung (Firebase-Push) |
| WispDating-v0.8.1-fdroid.apk | F-Droid (ohne Google, UnifiedPush) |
| WispDating-v0.8.1-play-arm64.apk | Play, nur arm64 (klein) |
| WispDating-v0.8.1-play-armv7.apk | Play, nur armv7 (klein) |
| WispDating-v0.8.1-fdroid-arm64.apk | F-Droid, nur arm64 (klein) |
| admin/WispDating-v0.8.1-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.8.1-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |

## Vor dem Rollout

1. Migration **079** einspielen (Bild-Einsprüche: Tabelle, RLS, RPCs,
   Storage-Admin-Policy, Push-Trigger).
2. Admins: Nach dem Update erscheint der neue Reiter „Bild-Prüfung".
3. Passkey-Origins unverändert (SHA-256, siehe
   docs/PASSKEYS_SERVER_SETUP.md).
