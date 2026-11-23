# Elternaufsicht fuer 16- und 17-Jaehrige

Aus der Roadmap (Stand 23.11.2026) in ein eigenes Dokument verschoben:
die Roadmap soll eine Liste sein, kein Entwurf. Die Aufsicht ist
umgesetzt (v0.10.0) - die offenen Punkte stehen in Abschnitt 4.

## Der Plan

> **Status: umgesetzt in v0.10.0 (03.11.2026).** Aufgeschrieben am
> 24.10.2026 auf Wunsch des Betreibers, umgesetzt am 03.11.2026.
> Der Wunsch ist klar: 16- und 17-Jährige sollen die App nutzen können –
> mit Zustimmung der Eltern, die die App herunterladen und dem Kind zur
> Verfügung stellen. Eine Weitergabe an Personen, die nicht geeignet sind
> (etwa unter 16-Jährige), ist in keinem Fall erlaubt.
>
> **UMGESETZT (in v0.10.0):** Migrationen 165 (Freigabe, Audit-Trail,
> Digest-Trigger, Cron), 166 (Portal-Status), 167 (Änderungen nur mit
> PIN); Edge Functions `guardian-consent` und `guardian-digest`;
> Eltern-Portal unter `auth.thestia.de/eltern`; App: Freigabe-Screen nach
> dem Willkommens-Screen, Einstellungsabschnitt „Kinderschutz &
> Elternzugriff", Übergangs-Screen mit 18, PIN-geschützte Nutzungszeit.
>
> Dieser Block hält fest, was das rechtlich und technisch bedeutet, was
> Google Play zulässt und was es nicht zulässt. Er ist eine
> Entscheidungsgrundlage, kein Umsetzungsplan.

### 1. Was Google Play zulässt – und was nicht

Die maßgebliche Regel ist die „Age-Restricted Content and Functionality"
im Developer Programme Policy. Sie kennt **zwei** Fälle:

1. **„Apps whose core functionality is to facilitate matchmaking or
   dating."** → Diese Apps **müssen** Play-Werkzeuge benutzen, um
   Minderjährige auszusperren (Restrict Minor Access, Zielgruppe 18+).
   Eine Ausnahme gibt es hier nicht.
2. **„Apps where matchmaking or dating is an incidental feature are not
   required to block minors, provided that they implement appropriate
   age-verification safeguards to prevent minors from accessing those
   specific features."** → Nur wenn die Begegnungsfunktion **nicht** der
   Kern der App ist. Dann genügt ein belastbarer Altersnachweis, statt
   die Minderjährigen komplett zu sperren.

Thestia ist eine Dating-App mit Dating-Kern → **Fall 1**. Die
Eltern-Einwilligung öffnet den Play-Kanal also **nicht** für 16-Jährige.
Das ist keine Auslegungsfrage und keine Verhandlungsposition: Play hat
das in der Policy formuliert, und der Support hat es am 24.10.2026
bestätigt (es gibt keine Vorab-Prüfung, nur die reguläre Prüfung bei
Einreichung).

Interessant für das technische Design ist trotzdem Fall 2, denn Play
formuliert dort die Anforderung, an der sich das Modell messen lassen
muss: *„It is your responsibility to ensure that your age-gating
mechanism is robust and effective. Simple age gates that can be easily
circumvented may not be considered reasonable."* Ein einfaches Häkchen
„ich bin 16“ wäre also weder für Play noch für den Jugendschutz
ausreichend. Genau das ist der Maßstab, an dem unten entworfen wird.

**Folge für die Verteilung:**

- **Play-Kanal:** Zielgruppe 18+, Restrict Minor Access aktiv. Die
  16+-Pfade sind im Play-Build nicht erreichbar. Ob die F-Droid-Variante
  (eigener Build ohne Firebase/Play Integrity) neben dem Play-Build
  vertrieben werden darf, ist eine Rechtsfrage, die vor einer
  Entscheidung juristisch zu klären ist – hier steht sie offen.

- **Nicht-Play-Kanäle:** Dort gilt nicht die Play-Policy, sondern das
  deutsche Recht. Das ist der Ort, an dem das Modell unten seinen Sinn
  hätte.
**ENTSCHEIDUNG 05.11.2026: Der 16+-Pfad bleibt (bewusst).**

Bei der Bestandsaufnahme vom 05.11.2026 (siehe
`docs/recht/MINDERJAEHRIGE-NUTZUNG.md`) wurde die Frage gestellt, ob der
Minderjährigen-Pfad (Elternfreigabe, Nutzungszeit, Aufsicht) ganz
entfernt werden soll. Entscheidung: **er bleibt.** Begründung:

- Die technische Absicherung für 16- und 17-Jährige ist vollständig
  und serverseitig erzwungen (Altersgrenzen, Sichtbarkeitsregeln,
  Suchradius, keine Entfernungsanzeige, Transit Spark ab 18, Audit-Trail).
  Sie wird auch für die Verifikation von Erwachsenen gebraucht.
- Der Parentschutz ist ein Verkaufsargument gegenüber Familien, und die
  Elternseite (`/eltern`) erklärt ihn ausführlich.
- Der Aufwand des Entfernens (rund 25 Dateien, zwei Migrationen, zwei
  Edge Functions, Website und Store-Text) steht in keinem Verhältnis zu
  einem Nutzen, solange der **Play-Kanal** die 16+-Pfade ohnehin nicht
  ausliefert.


**Die Store-Frage ist entschieden (05.11.2026):** Das Listing nennt
beides, ohne zu verschweigen, dass es zwei Kanäle gibt:

> Im Play Store ab 18 Jahren: Google verlangt für Dating-Apps ohnehin
> eine Altersgrenze von 18. In anderen Kanälen (F-Droid) ist die App ab
> 16 Jahren mit Elternfreigabe nutzbar – für Erwachsene bleiben
> Minderjährige unsichtbar

Damit stimmen Listing und Wirklichkeit überein: der Kanal gibt 18+ her,
die App kann 16+. Eine Invariante (`tool/checks/check_security_invariants.py`)
sichert das ab - schreibt jemand wieder „ab 16 Jahren, mit
Elternfreigabe" ins Listing, schlägt sie an.

**Bleiben würde Weg 2:** den Minderjährigen-Pfad ganz entfernen. Das ist
eine Markt- und Rechtsfrage, keine technische; die technische Umsetzung
steht in `docs/recht/MINDERJAEHRIGE-NUTZUNG.md` (Abschnitt 9).

### 2. Der juristische Anker (Deutschland)

- **DSGVO Art. 8:** Die Einwilligung für Dienste, die sich an Kinder
  richten, bedarf bei Minderjährigen der Zustimmung der
  Sorgeberechtigten; die Mitgliedstaaten dürfen das Alter selbst
  festlegen.
- **§ 3a JUG** (früher § 5 TMG): In Deutschland kann eine Person ab dem
  **vollendeten 16. Lebensjahr** selbst einwilligen. Darunter ist die
  Zustimmung der Sorgeberechtigten erforderlich.

Damit deckt sich das Modell mit dem bestehenden Altersdesign der App
(16 ↔ 16/17 erlaubt, Erwachsene untereinander): Die App müsste also
**zwei** getrennte Nachweiswege haben – einen elterlichen
Einwilligungsweg für 13–15 (nur wenn das überhaupt gewollt wird) und
einen Selbsteinwilligungsweg ab 16. Der Vorschlag des Betreibers deckt
sich mit dem Gesetz für 16 und 17: dort genügt die eigene Einwilligung,
die Zustimmung der Eltern ist freiwillig, aber der **Nachweis** des
Alters bleibt zwingend.

> **Rechtlich prüfen lassen (Medienrecht/Datenschutz), bevor das
> umgesetzt wird.** Dieser Block ist keine Rechtsberatung. Zu prüfen sind
> mindestens: Art. 8 DSGVO, § 3a JUG, die Einwilligungsform, die
> Nachweispflicht des Betreibers, die Frage der Weitergabe des Kontos
> und die Frage, ob eine Dating-App besondere Kategorien personenbezogener
> Daten verarbeitet.

### 3. Technischer Entwurf: was „mit Zustimmung der Eltern" serverseitig heißen muss

Die Anforderung des Betreibers enthält die entscheidende Einschränkung
selbst: **keine Weitergabe an nicht geeignete Personen.** Ein
Einwilligungs-Häkchen im Registrierungsformular wäre wertlos, weil es
sich kopieren ließe. Der Nachweis muss also serverseitig hängen.

**Kernpunkt: Das Konto gehört dem verifizierten Kind, nicht dem
Elternteil.** Der Elternteil ist Genehmiger, nicht Nutzer. Damit ist die
Weitergabe technisch ausgeschlossen: Ein Konto, das einem 16-Jährigen
gehört, wird von einem anderen nicht benutzt – es existiert nur für
diesen einen, verifizierten Menschen.

Vorgesehene Bausteine (noch nicht umgesetzt):

| Baustein | Zweck | Aufwand | Stand |
|---|---|---|---|
| `profiles.supervised` (bool) | Konto steht unter Aufsicht | klein | ✅ Migration 165 |
| `profiles.consent_state` (`none`/`pending`/`granted`/`revoked`) | Stand der Einwilligung, serverseitig | klein | ✅ Migration 165 |
| `profiles.consent_parent_ref` | Verweis auf den Einwilligungsdatensatz, **kein** Konto des Elternteils | klein | ✅ Migration 165 |
| `profiles.consent_verified_at` / `consent_revoked_at` | Nachweiszeitpunkt und Widerruf | klein | ✅ Migration 165 |
| Einwilligungs-Flow (Elternseite) | Eltern bestätigen per Einmal-Link an ihre eigene Adresse; der Link ist an die **konkrete, verifizierte** Minderperson gebunden | mittel | ✅ Eltern-Portal `auth.thestia.de/eltern`, Token nur als Hash gespeichert |
| Widerrufs-Flow | Eltern widerrufen per Link; der Server setzt `consent_state='revoked'` und sperrt die Funktionen | mittel | ✅ Migration 165 |
| Kopplung an die Altersprüfung | Das bestehende Video-Alter entscheidet; die Einwilligung gilt **nur** für das Alter 16/17 und **nur** für dieses Konto | mittel | ✅ `guardian_eligible_age()` - das **verifizierte** Alter |
| Aufsichtsmodus | Eltern können einzelne Funktionen abschalten (BLE/Transit Spark, Zufallschat, Standort) | groß | 🟡 teilweise: Nutzungszeit per PIN gesetzt; das Abschalten einzelner Funktionen ist nicht gebaut |
| Audit-Trail | Jede Einwilligung und jeder Widerruf wird protokolliert (wer, wann, für wen) | mittel | ✅ `guardian_consent_audit` |
| Eltern-Benachrichtigung | Elternteil erfährt, dass ein Funke entstanden ist - ohne Namen, Profile oder Inhalte | mittel | ✅ Digest per `pg_cron`, Frequenz daily/weekly/monthly/none |
| Entscheidung mit 18 | Jugendlicher entscheidet: Zugriff beenden, 1-6 Monate behalten oder erstmal behalten | mittel | ✅ `set_guardian_access_policy()`, Übergangs-Screen in der App |
| Nutzungszeit | Zeitfenster, in dem die App genutzt werden darf | mittel | ✅ PIN-geschützt (`set_guardian_settings_with_pin`), Sperre in der App |

**Regeln, die daraus zwingend folgen:**

1. Ein 16-/17-Jähriger muss sein Alter **serverseitig verifiziert**
   haben (das gibt es bereits: Video-Verifikation). Eine Einwilligung
   ohne Altersnachweis ist wertlos – sonst bestätigt ein 14-Jähriger
   einfach, er sei 16.
2. Die Einwilligung ist an **eine** Minderperson und **eine** Elternadresse
   gebunden. Sie ist nicht übertragbar und nicht wiederholbar.
3. Die Einwilligung ist **widerrufbar**, und der Widerruf wirkt
   serverseitig sofort – nicht erst beim nächsten Login.
4. **Keine Vollversion.** Ein beaufsichtigtes Konto bekommt keine
   Funktionen, die für diese Altersgruppe grundsätzlich gesperrt sind
   (Transit Spark/BLE ist bereits serverseitig auf 18+ gesperrt,
   Migration 131; der Zufallschat ist für Volljährige gedacht).
5. Der **Kontaktweg** bleibt bei den Sorgeberechtigten: Meldungen zu
   einem beaufsichtigten Konto gehen an die Eltern, nicht an das Kind.
6. Kein Volltext-Profil, keine exakte Standortanzeige, keine
   Weitergabe der Kontaktdaten an Minderjährige (Datenschutz-Folgen).

### 4. Offene Entscheidungen (bewusst nicht getroffen)

- [x] Wird das Modell **überhaupt** umgesetzt – oder bleibt es bei 18+
      und wird nur dokumentiert? → **Umgesetzt (03.11.2026).**
- [ ] Gilt es nur für 16/17 (Selbsteinwilligung ab 16) oder auch für
      13–15 (elterliche Einwilligung)? Play erlaubt in keinem Fall
      unter 18; die Entscheidung betrifft also nur Nicht-Play-Kanäle.
- [ ] Welche Kanäle dürfen das beaufsichtigte Konto ausliefern, und ist
      das rechtlich sauber?
- [ ] Aufsichtsmodus: welche Funktionen werden per Elternentscheid
      abgeschaltet, und wie wird das im Kind-Account sichtbar gemacht,
      ohne dass es wie eine Überwachung wirkt?
- [ ] Wie verhält sich das Modell zur Verifikation (Video) und zur
      Altersspanne? Ein beaufsichtigtes Konto braucht eigene Regeln im
      Jugendschutz-Filter.
- [ ] Prüfung durch eine Rechtsberatung (Medienrecht/Datenschutz), bevor
      irgendetwas davon live geht. → **OFFEN.** Die Technik ist live
      (Migrationen 165-167), die rechtliche Prüfung steht aus. Der
      Kernpunkt ist in der DSFA (Abschnitt 5, Punkt 6) festgehalten:
      Form und Nachweis der Einwilligung nach § 3a JUG und Art. 8 DSGVO,
      die Verantwortlichkeit für die Einrichtung eines kindlichen
      Kontos und die Einordnung der Nutzungszeit.
