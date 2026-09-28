# Incident Response

Stand 2026-09-28. Öffentlich, damit die Zusage in
[SECURITY.md](../SECURITY.md) nachprüfbar ist.

**Zwei verschiedene 72-Stunden-Fristen – nicht verwechseln:**

| Frist | Objekt | Rechtsgrundlage | Verbindlich |
|---|---|---|---|
| Antwort an einen Hinweisgeber | freiwillig zugesagt | keine | **nein** – bewusst ohne Frist zugesagt, weil eine nicht haltbare Zusage mehr schadet als keine |
| Meldung einer Datenpanne an die Aufsichtsbehörde | ab Kenntnis der Panne | **Art. 33 DSGVO** | **ja** – nicht verhandelbar |
| Information betroffener Nutzer | bei hohem Risiko | Art. 34 DSGVO | **ja** |

Der Rest dieses Dokuments betrifft ausschließlich die gesetzlichen
Fristen und den technischen Ablauf.

## Rollen

Rollen werden nicht über Namen geführt, sondern über Funktion. Eine
Person kann mehrere Rollen haben.

| Rolle | Aufgabe |
|---|---|
| **Meldungsannahme** | Eingehende Meldungen lesen, triagieren, an die technische Rolle weitergeben |
| **Technische Leitung** | Bewertet Auswirkung, entscheidet über Maßnahmen, führt die Uhr |
| **Betrieb** | Führt technische Maßnahmen aus: Keys rotieren, Deployments stoppen, Daten löschen |
| **Kommunikation** | Nutzerinformation, Statusmeldung, ggf. Meldung an die Aufsicht |

**Vorbedingung:** Für jede Rolle muss benannt sein, wer sie besetzt – und
wer es ist, wenn diese Person nicht erreichbar ist. Steht das nicht in
diesem Dokument, ist es unerledigt. Die Namen stehen bewusst nicht
hier, sondern in einer internen Zuordnung.

**Für ein Ein-Personen-Projekt ist das die Mindestbesetzung:** Eine
Rolle pro Person, mit einer Vertretung. Sind alle Rollen bei derselben
Person, ist das zu dokumentieren – nicht weil es günstiger ist, sondern
damit die Lücke im Ernstfall sichtbar wird.

## Triage: was zuerst entschieden wird

Ohne festgelegte Frist, aber **binnen eines Tages** nach Eingang einer
Meldung, weil eine unbehandelte Meldung das eigentliche Risiko ist:

1. **Betrifft es Nutzerdaten?** Wenn ja: alles Weitere ist zweitrangig.
2. **Ist es aktiv ausnutzbar?** Ein Exploit in einem ausgelieferten
   Build ist ein Vorfall, ein Fehlerbild in der eigenen Datenbank
   ebenfalls.
3. **Sind Meldedaten betroffen?** (Bild-Uploads, Reporter-Identität)
4. **Ist der Angreifer ein Nutzer mit Konto?** Dann Zugriffsschutz
   (Passkey-Origin, Sessions widerrufen), nicht nur die Schwachstelle.

## Schweregrade

| Grad | Kriterium | Frist |
|---|---|---|
| **S1 – kritisch** | Aktive Exfiltration, übernommene Konten, Meldedaten offengelegt, Signier-Key kompromittiert | Meldung an Aufsicht binnen **72 h** (Art. 33 DSGVO), Nutzerwarnung binnen 24 h |
| **S2 – hoch** | Ausnutzbar, aber kein Hinweis auf Exfiltration; betrifft die Integrität der Zugriffskontrolle | Behebung binnen 7 Tagen, Zwischenmeldung an Meldende |
| **S3 – mittel** | Erschwerung, aber keine Umgehung; unvollständige Härtung | Behebung im nächsten Release |
| **S4 – niedrig** | Theoretisch, nicht erreichbar, oder hardening | Wird aufgenommen, priorisiert nach Risiko |

Die 72-Stunden-Frist nach Art. 33 DSGVO gilt für die Meldung an die
zuständige Aufsichtsbehörde, nicht für die Behebung. Wird die Frist
nicht erreicht, ist die Verzögerung zu begründen.

## Meldeweg gegen Schwachstellenweg

Beide laufen in dieselbe Poststelle, werden aber unterschiedlich
bewertet: Ein Hinweis von Nutzern hat unbekannte Reichweite, ein
Forschungsfund kommt mit vollständiger Analyse. Deshalb beginnt die
technische Bewertung bei Hinweisen **vor** der klassifizierten
Behebungsfrist.

## Reaktionsablauf

**Bei Meldung**
1. Antworten, wenn eine Antwort zugesagt wurde – ohne Frist
   zuzusagen. Lieber spät und ehrlich als fristgerecht erfunden
2. Triage binnen eines Tages, Grad einstufen
3. Bei S1: sofortige Eindämmung, auch mitten im Release

**Bei S1 konkret**
1. **Eindämmen zuerst, Ursache später.** Ein Feature abschalten
   (serverseitiges Flag), Migrationen stoppen, Edge Function
   zurückziehen – eine Ursachenanalyse im laufenden Betrieb ist zweitrangig
2. Betroffene Zugangsdaten für ungültig erklären:
   `auth.admin.signOut(user_id, 'global')`, Passkeys und E2E-Identität
   prüfen
3. Umfang bestimmen: welche Daten, welcher Zeitraum, wie viele Nutzer
4. Rechtsberatung zur Meldepflicht einholen
5. Meldung an die Aufsicht **binnen 72 h ab Kenntnis** – gesetzliche
   Frist nach Art. 33 DSGVO, nicht die Antwortfrist aus
   `SECURITY.md`. Kenntnis heißt: die Meldung ist eingegangen und als
   Datenpanne eingeordnet, nicht dass alles verstanden ist

**Bei kompromittiertem Signing-Key**
Es gibt keinen Rollback. Play App Signing schützt die
Store-Installationen, nicht die eigene Signaturidentität. Ein
verlorener Key bedeutet: Play-Key-Reset beantragen, und
`assetlinks.json` muss den **neuen** Fingerabdruck erhalten, sonst
funktionieren Passkeys im neuen Build nicht.

**Verdacht auf kompromittierten Firebase-API-Key**
Der Key ist ein Client-Identifier, aber unbeschränkt missbrauchbar
(Quota, kostenpflichtige APIs). Ohne Zugriff auf die Google Cloud
Console lässt sich das nur durch Deaktivieren des Projekts lösen – ein
Grund, den Zugang zu klären.

## Nach dem Vorfall

Innerhalb von 14 Tagen:
- Was ist passiert und wann?
- Welche Maßnahmen wurden wann getroffen?
- Welche Meldungen gingen an wen?
- **Was wird geändert, damit es nicht wieder passiert?** Konkret und
  nachprüfbar – idealerweise als Eintrag im
  [ROADMAP](../ROADMAP.md) oder als neue Regel in
  `tool/check_security_invariants.py`

Ein Vorfall ohne Konsequenz ist zweimal derselbe Vorfall.
