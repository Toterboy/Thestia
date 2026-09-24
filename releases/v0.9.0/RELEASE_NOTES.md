# WispDating v0.9.0-Beta – Release Notes

**Transit Spark** – der Nahbereichs-Funke. Plus Server-Härtung und
Entdecken-Neuaufbau.

## Neu (das Wichtigste)

- **Video-Verifizierung mit lokaler KI-Triage**: Selbstvideo mit
  Liveness-Challenge, Altersschätzung auf dem Gerät (Mehrframe-
  Median über 6 Frames). Abweichung über 2 Jahre oder kein klares
  Gesicht: manuelle Prüfung. Konto bleibt nutzbar, Badge erst nach
  Prüfung.
- **Transit Spark (Experimentell)**: Radar für Begegnungen unterwegs
  (anonyme Token, „Blicke getauscht", Soft-Ping, Merkmal-Tags).
- **Relay-Fallback**: Nachrichten ohne P2P Signal-verschlüsselt
  zwischenspeichern (E2E bleibt gewahrt).
- **Personalisierte Quiz-Fragen** (ohne LLM), **Entdecken neu**,
  **Onboarding als Interview**, **zweisprachig** (DE/EN).
- **Altersschutz-Paket**: „Falsches Alter"-Meldung, Geburtsdatum
  gesperrt, Altersdifferenz-Warnung ab 10 Jahren.
- **Herzensstärken** (Momente, Freundschaft, Erinnerungsliste),
  **gespeicherte Profile**, **Eisbrecher-Fragen**, **Geburtstags-Stile**.

## Sicherheit (v0.9.0, Manipulationsschutz)

- **Play Integrity** (nur Play, erst mit Play-Eintrag scharf):
  Fehlendes Verdict heißt manuelle Prüfung, nie Ablehnung.
- **Stichproben-Audit**: Auto-Freigaben landen im Admin-Tab mit
  Video, Bestätigen und Entziehen (Migration 120).
- **Modell-Integrität** (SHA-256-Check, fail-closed),
  **TLS-Pinning** für allen App-Traffic, **Dart-Obfuskierung**.
- **Aufnahme-Hinweise**: Kein Kopfbedeckung/Kopfhörer/Brille/Maske,
  Gesicht muss frei erkennbar sein.

## Behoben (das Wichtigste)

- **Video-Einreichung**: Upsert-Upload, Timeouts statt Hänger,
  echte Fehlermeldungen, Kamera-Retry.
- **Nachrichten**: PreKey-Fixes, Relay-Retry, schnelleres Polling.
- **Funken**: Serverseitige Matches (nie doppelt/einseitig),
  72-h-Auto-Kühlung. **Zufallschat**: Relay bei ICE-Failure.
- **Login-Sperre** (10/10 Min), **Chat zuerst, Quiz später**.

## Behoben (Nachtrag, Build 28)

- **Standort-Eingabe**: „Ort liegt mehr als 15 km entfernt" erschien
  direkt beim Tippen (Geokodieren lief bei JEDEM Tastenanschlag und
  löschte den Text). Jetzt: Geokodieren erst bei Tipppause, der
  getippte Text bleibt, „Ort nicht gefunden" ist eine eigene,
  korrekte Meldung (gilt für Onboarding UND Profil-Bearbeitung).
- **Verifiziert-Badge** steht jetzt direkt neben dem
  Persönlichkeitstyp statt in einer eigenen Zeile darunter.
- **Account-Löschen-Fix**: Migration 122 ergänzt fehlende
  SELECT-Grants (PostgREST braucht sie für Filter-DELETEs) –
  „Konto löschen" läuft seither fehlerfrei durch.

## Unterstützte Versionen

**v0.9.0 (Build 28) und höher** werden unterstützt. Alle älteren
Versionen (v0.8.x und älter) sind **End of Support** (seit
24.09.2026): keine Bug- oder Security-Fixes mehr, bitte
aktualisieren. Ältere Builds erhalten beim Start automatisch einen
Update-Hinweis (serverseitiges Mindest-Build-Gate). Siehe
[SUPPORT.md](../../SUPPORT.md).
