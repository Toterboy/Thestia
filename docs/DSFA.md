# Datenschutzfolgeabschätzung (DSFA) – Thestia

> **ENTWURF. Kein geprüftes Rechtsdokument.**
> Diese Abschätzung ist nach Art. 35 DSGVO erforderlich, weil
> systematisch ein öffentlich zugänglicher Raum erfasst wird und
> Minderjährige betroffen sind. Sie ist fachlich erstellt, aber **nicht
> rechtlich geprüft**. Vor dem Launch ist eine datenschutzrechtliche
> Prüfung einzuholen. Offene Punkte sind unten ausdrücklich als
> ungeklärt markiert und nicht wegformuliert.

Stand 2026-09-28. Betrifft `com.thestia.app` (Build 30 / v0.9.2) und die
Zusatzdienste Supabase, Firebase, Cloudflare, Brevo, Netlify.

## 1. Ergebnis in einem Satz

Die Verarbeitung ist **notwendig für den Kernzweck der App** (Menschen
im öffentlichen Raum finden), aber sie geht bei BLE-Nahbereich,
Altersverifikation und Drittlandtransfers **über das hinaus, was der
Kernzweck erfordert**, und ist deshalb an drei Stellen nur mit
Vorkehrungen vertretbar.

## 2. Warum eine DSFA erforderlich ist

Art. 35 Abs. 3 lit. a und c DSGVO verlangen sie, wenn die Verarbeitung
voraussichtlich ein hohes Risiko für die Rechte betroffener Personen
darstellt, insbesondere wenn

- **lit. a:** ein öffentlich zugänglicher Bereich systematisch
  überwacht wird. Transit Spark erfasst Anwesenheit im öffentlichen
  Raum; für 0.11.0 ist ein Live-Board mit präzisen Positionsmerkmalen
  geplant.
- **lit. c:** Daten Minderjähriger verarbeitet werden. Die App ist
  ausdrücklich auch für unter 18-Jährige nutzbar; der Jugendschutz ist
  ein Kernmerkmal.

Zusätzlich einschlägig: **Art. 8** (Einwilligung bei Kindern, § 25
Abs. 2 TDDDG in Deutschland), **Art. 28** (Auftragsverarbeitung),
**Art. 44 ff.** (Drittlandtransfer), **Art. 9** (Krisen-Erkennung im
geplanten Sanctuary).

## 3. Beschreibung der Verarbeitung

### 3.1 Zweck und Rechtsgrundlage

| Verarbeitung | Zweck | Rechtsgrundlage (Entwurf) |
|---|---|---|
| Konto, Authentifizierung | Zugang | Art. 6 Abs. 1 lit. b |
| Profildaten, Präferenzen | Matching | lit. b, teils lit. f |
| Ende-zu-Ende-Chats | Kommunikation | lit. b; E2E-Schlüssel Art. 6 |
| Bild-Upload, Moderation | Sicherheit, Missbrauchsschutz | lit. f; **Berechtigtes Interesse ist zu prüfen – Profiling von Personen ist nach Art. 22 ausgeschlossen** |
| Standort (geraundet) | Matching, Nächhefunke | lit. b / Einwilligung |
| **BLE-Nahbereich** | Nahbereichs-Funke | **Art. 6 Abs. 1 lit. f, eng ausgelegt** – siehe 4.1 |
| Altersverifikation | Jugendschutz | lit. b / Einwilligung |
| Verhaltensanalyse (Score) | Matching | lit. f, **Profiling möglich** |
| NSFW-Bildprüfung on-device | Sicherheit | lit. f |
| Crash- und Nutzungsdaten | Stabilität | lit. f |

### 3.2 Betroffene Personen

Alle Nutzenden, ausdrücklich auch **Minderjährige**. Personen in der
Nähe, ohne Konto, werden als potenziell betroffen geführt, weil ihre
Anwesenheit im Raum protokolliert wird (Begegnungscache) und weil
Funk-Metadaten sie identifizierbar machen können.

### 3.3 Datenkategorien

- **Identifizierend:** Pseudonyme Nutzer-ID, E-Mail, Gerätekennungen
- **Besonders sensible:** politische Meinung, Gesundheit und
  **biometrische Daten** (Alters-Triage, optische Merkmale via BLE)
  sowie – im geplanten Sanctuary – Hinweise auf psychische Verfassung
  aus der Krisen-Erkennung
- **Standort:** gerundete Koordinaten (5 km), Zeitstempel; im
  geplanten Live-Board: Linie, Zugnummer, Sitzbereich, optische
  Merkmale
- **Kommunikation:** Nachrichten als Chiffrat; Metadaten
  (Empfänger, Zeitpunkt, Frequenz) im Klartext

## 4. Risiken

### 4.1 Hoch: BLE-Nahbereich und Funk-Metadaten

**Risiko:** Wiedererkennbare Anwesenheitsmuster. Ein Gerät mit
rotierendem Token kann über die Sendeintervalle über Sitzungen hinweg
zugeordnet werden. In einem begrenzten Umfeld (Schule, Arbeitsplatz,
Kongress) entsteht ein Bewegungsprofil ohne Accounts.

**Bewertung:** Bei Erwachsenen mit aktivem Transit Spark vertretbar,
wenn die Maßnahmen greifen. **Bei Minderjährigen nicht vertretbar** –
eine funkbasierte Standortverfolgung in einem Umfeld mit
Schulfreunden ist ein reales Risiko. Siehe 5.

**Maßnahmen:** Token-Rotation, Jitter der Intervalle, gepulstes
Scanning, serverseitige Prüfung von Jugendschutz und Blockierliste,
doppeltes Signal als Voraussetzung für einen Funke. **RPA wird nicht
behauptet** – die App kann die Advertise-Adresse nicht erzwingen.

### 4.2 Hoch: Profiling über den Matching-Score

**Risiko:** Der Verbindungs-Score (Distanz, Interessen, Musik) ist ein
Profil im Sinne des Art. 4 Abs. 4 DSGVO. Automatisierte
Entscheidungen mit erheblicher Wirkung sind zu prüfen – hier gibt es
keine Entscheidung *über* Personen, nur die Reihung. Das schließt das
Verbot des Profilings von Personen nach Art. 22 Abs. 1 nicht aus.

**Maßnahmen:** Der Score ist einseitig und transparent, kein
automatischer Ausschluss. Nutzer können die verwendeten Faktoren
einschränken. **Zu klären:** Bedarf es einer Einwilligung statt
berechtigtem Interesse?

### 4.3 Hoch: Altersverifikation und Minderjährigenschutz

**Risiko:** Fehlerhafte Freigabe (17-Jährige gilt als volljährig) oder
zu strenge Sperre. Beides mit erheblichen Folgen für den Betroffenen.

**Maßnahmen:** Manuelle Queue für Abweichler, KI-Alters-Triage nur
als Vorstufe, serverseitige Prüfung in jeder matchenden RPC.
**Offen:** Mindestalter nicht festgelegt, kein Widerspruchsverfahren,
keine Aufbewahrungsregel für Verifizierungsmedien.

### 4.4 Hoch: Drittlandtransfer

**Risiko:** Kein belegter Verarbeitungsort für die Moderation
(Brevo, Cloudflare, Firebase). Bild-Meldungen verlassen die EU.
Fehlende Auftragsverarbeitungsverträge sind ein eigenes Risiko.

**Maßnahmen:** Auftragsverarbeitungsverträge, Drittlandtransfer nur
mit Angemessenheitsbeschluss oder Standardvertragsklauseln.
**Offen:** Vertragstatus je Anbieter nicht dokumentiert.

### 4.5 Mittel: Standort und Live-Board (geplant)

**Risiko:** Waggon-Angaben plus Zeit korrelieren zu einem
Bewegungsprofil. Ein Live-Board mit Sitzbereich ist eine
Nahbereichsverfolgung.

**Maßnahmen:** Präzise Angaben erst nach beidseitigem Funke
sichtbar, Board-Einträge löschen nach 24 h, kein dauerhaft mitlesbarer
Feed. **Offen:** Aufbewahrung der Check-in-Rohdaten selbst; die
BSSID- und Geschwindigkeitserkennung aus 0.11.0 wären kontinuierliche
präzise Standorterfassung und stehen im Konflikt mit der Zusage im
Date-Safety-Check-in.

### 4.6 Mittel: Krisen-Erkennung im Sanctuary (geplant)

**Risiko:** Verarbeitung von Hinweisen auf psychische Verfassung.
Besonders sensible Daten mit erheblicher Fehlerrisiko-Erwartung. Eine
Erkennung auf Regex-Basis verfehlt Umschreibungen, was falsche
Sicherheit erzeugt.

**Maßnahmen:** On-device, flüchtig, nicht abschaltbare Schutzschicht
unterhalb der Prompt-Ebene, Notrufnummern, keine Meldung an Dritte
ohne Einwilligung. **Offen:** Rechtsgrundlage, ob das Feature
Minderjährigen zugänglich sein soll, Bewertung als Nicht-Medizinprodukt.

### 4.7 Mittel: Meldesystem als Beleidigungsinstrument

**Risiko:** Gezielte Meldungen zur Denunziation, mit Identifizierung
des Meldenden. Umgekehrt: Moderate Missbrauchswege in beide Richtungen.

**Maßnahmen:** Reporter-Pseudonymisierung, Bild-Blur, manuelle
Prüfung, Nachweis-Pflicht, Blockier- und Melde-Schutz greifen wie
überall.

## 5. Zusätzliche Vorkehrungen wegen Minderjähriger

1. **BLE-Nahbereich für unter 18-Jährige abschaltbar, im Zweifel
   standardmäßig aus.** Die Verfolgbarkeit funkbasierter Signale wiegt
   schwerer als der Nutzen in dieser Altersgruppe. Derzeit ist
   Transit Spark **nicht** nach Alter beschränkt.
2. **Standort standardmäßig auf 25 km** für Minderjährige, mit
   Hinweis auf elterliche Sichtbarkeit.
3. **Kein Live-Board und kein Same-Train-Matching unter 18.** Beides
   setzt Standort in einem beweglichen, nicht privaten Umfeld voraus.
4. **Sanctuary: Altersabfrage vor Zugang, Hinweis auf professionelle
   Hilfe** statt eigener Krisenbewertung durch ein Sprachmodell.
5. **Keine Profilbilder als Pflicht** in dieser Altersgruppe.

Diese Punkte sind **Vorschläge der fachlichen Einschätzung**, keine
geprüfte Rechtsposition. Die Entscheidung trifft der Betreiber
gemeinsam mit der Rechtsberatung.

## 6. Restrisiko nach Umsetzung

| Risiko | Restniveau | Begründung |
|---|---|---|
| Funk-Metadaten | **nicht vollständig beseitigt** | BLE lässt keine völlige Funk-Unsichtbarkeit zu |
| Verhaltensprofil aus dem Score | **nicht vollständig beseitigt** | Matching erfordert Sortierung; Transparenz statt Verzicht |
| Fehler der Alters-Triage | **nur reduziert** | Zweite Instanz nur bei Abweichung; 2-Jahres-Regel ist eine Annahme |
| Drittlandtransfer | **nicht vollständig beseitigt** | Brevo und Cloudflare sind nicht in der EU |
| Verfolgung Minderjähriger | **reduziert, nicht ausgeschlossen** | abhängig von Einhaltung der Punkte in 5 |

## 7. Ungeklärte Punkte – vor Launch zu klären

- [ ] Rechtsgrundlage für BLE-Nahbereich bei Minderjährigen
- [ ] Mindestalter festlegen
- [ ] Auftragsverarbeitungsverträge und Transferort je Anbieter
- [ ] Art. 22 DSGVO für den Matching-Score
- [ ] Aufbewahrungsfrist für Verifizierungsmedien
- [ ] Widerspruchsverfahren bei Altersablehnung
- [ ] Bewertung der Krisen-Erkennung als Nicht-Medizinprodukt
- [ ] Verfügbarkeit des Live-Boards für Minderjährige
- [ ] Verbindliche Bewertung des BSSID-/Geschwindigkeitsabgleichs

## 8. Wiedervorlage

Bei jeder Änderung, die eines der Punkte in 4 oder 5 berührt, ist diese
Abschätzung fortzuschreiben. Zuständig ist die Rolle
[Technische Leitung](INCIDENT-RESPONSE.md).
