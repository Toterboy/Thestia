# Fragen für die datenschutzrechtliche Klärung

Zum Mitnehmen zu einer Beratung bei der Landesdatenschutzbehörde, bei
einem externen Datenschutzbeauftragten oder einem Anwalt. Entweder aus
drucken oder als Mail anhängen.

Hintergrund in einem Satz: Thestia ist eine Dating-App (Flutter +
Supabase) mit BLE-Nahbereichsfunke, Standort, Altersverifikation und
Ende-zu-Ende-Chats; Betreiber ist eine Einzelperson, keine
Mitarbeitenden. Ein Entwurf der Abschätzung liegt in
[DSFA.md](DSFA.md).

> **Die Fragen stehen absichtlich als Fragen, nicht als Aussagen.** Eine
> Beratung, die man mit fertigen Positionen aufsucht, bekommt eine
> Bestätigung. Eine Beratung, die man mit offenen Fragen aufsucht,
> bekommt eine Prüfung.

## A. Muss ich überhaupt eine DSFA machen?

1. Erfüllt die Verarbeitung in Ihren Augen zwei oder mehr der neun
   Kriterien der DSK-Muss-Liste? Welche sehen Sie als erfüllt an, welche
   nicht – und warum unterscheiden wir uns hier gegebenenfalls?
2. Genügt die Dokumentation einer **begründeten Entscheidung**, dass
   keine DSFA erforderlich ist, oder erwarten Sie eine DSFA für den
   Betrieb mit Minderjährigen?

## B. Jugendschutz – der Kern

3. Welches Mindestalter ist für eine Dating-App in Deutschland
   vertretbar, und welche Rechtsgrundlage trägt die Altersprüfung?
4. Reichen AI-gestützte Alters-Triage plus manuelle Queue für
   Abweichler, oder ist das als Altersnachweis zu unsicher?
5. Reicht eine serverseitige Altersprüfung, oder braucht es eine
   **Verifizierung durch eine Behörde** oder ein zertifiziertes
   Verfahren (z. B. Ausweisscheck per Video, „ Jugendschutz-Zertifikat"
   nachJuSchG)?
6. Wie ist mit der **2-Jahres-Regel** umzugehen? Wer im Januar 2009
   geboren wurde, ist im Januar 2026 volljährig, kurz darauf nicht
   mehr. Braucht es ein Datum oder eine wiederkehrende Prüfung?
7. Welche Einwilligungskonstruktion ist bei Minderjährigen nötig
   (§ 25 Abs. 2 TDDDG), und wer muss zustimmen – jeder Sorgeberechtigte
   oder die Jugendlichen selbst?
8. Darf eine Dating-App Minderjährige überhaupt als Nutzer haben, und
   falls ja: Welche zusätzlichen Vorkehrungen sind zwingend?

## C. Funk und Standort – der Kern

9. Ist die BLE-Erfassung im öffentlichen Raum eine **systematische
   Überwachung** im Sinne der Kriterien? Funk-Metadaten sind
   beobachtbar, ein Foto wird nicht übertragen. Wo verläuft die Grenze?
10. Reicht die Einwilligung als Rechtsgrundlage, oder kommt für
    Erwachsene berechtigtes Interesse in Betracht – und falls ja, mit
    welchen Auflagen?
11. Wann ist die Erfassung **auf ein Absolutely notwendiges Maß zu
    beschränken** (Art. 5 Abs. 1 lit. c DSGVO)? Ist ein 45-Minuten-Cache
    für Begegnungstokens vertretbar, oder sollte er kürzer sein?
12. Sollen BLE-Nahbereich und Live-Board für Minderjährige
    überhaupt abschaltbar sein – und wäre ein Standard-aus für diese
    Altersgruppe verlangend oder nur empfohlen?
13. Reichen die geplanten Vorkehrungen (Token-Rotation, Jitter,
    beidseitiges Signal)? Was fehlt aus Ihrer Sicht?

## D. Profil und Scoring

14. Ist der Verbindungs-Score (Distanz, Interessen, Musik) **Scoring
    im Sinne der Kriterien**, und löst er Art. 22 DSGVO aus – obwohl er
    niemanden automatisch ausschließt?
15. Welche Rechtsgrundlage trägt die Profilbildung, berechtigtes
    Interesse oder Einwilligung? Was ändert sich, wenn der Nutzer den
    Score nicht abzuschalten kann?
16. Ist eine **Profilbildung über Verknüpfung von Daten** (BLE-Merkmale
    plus Profilangaben) unzulässig, solange sie nicht einwilligungsbasiert
    erfolgt?

## E. Geheimschutz des Chats

17. Endet die Ende-zu-Ende-Verschlüsselung beim Betreiber, obwohl der
    Server nur Chiffrat sieht? Wie ist das gegenüber Nutzern zu
    kommunizieren, damit „verschlüsselt" nicht zu „niemand außer dir
    sieht" verkürzt wird?
18. Genügt es, den Relay-Fall zu benennen, oder ist die Aussage
    irreführend, weil der Server sieht **wer** mit wem kommuniziert?
19. Was ist bei **Metadaten** zu beachten – Nutzungsdauer,
    Nachrichtenfrequenz, Tageszeiten?

## F. Drittanbieter

20. Welche Anbieter brauchen zwingend einen
    Auftragsverarbeitungsvertrag, und welche brauchen eher einen
    Vertrag über die Verarbeitung im Auftrag (Art. 28)?
21. Wie ist mit Anbietern ohne EU-Datenstandort umzugehen – welche
    Angemessenheitsbeschlüsse gelten, und genügt ein
    Standardvertragsklausel-Set?
22. Reicht Firebase für Push, obwohl die Verarbeitung außerhalb der EU
    stattfindet – oder muss die Zustellung in einen EU-Raum verlegt
    werden?
23. Muss ich die Subunternehmerlisten der Anbieter in die
    Datenschutzerklärung übernehmen, und in welchem Umfang?

## G. Betreuungspflichten

24. Muss ich für diese Verarbeitung einen **Datenschutzbeauftragten**
    benennen, auch unterhalb der Schwelle von 20 Beschäftigten?
25. Falls nein: Lohnt sich ein externer Datenschutzbeauftragter für
    ein Projekt dieser Größe, und in welchem Umfang (Stundenkontingent
    statt laufend)?
26. Welche **Verzeichnisse** muss ich führen, und wo ist die Grenze
    zur Dokumentationspflicht für kleine Verantwortliche?
27. Muss ich die DSFA selbst erstellen, oder reicht ein externer
    Berater – und in wessen Namen steht sie?

## H. Vor dem Launch zu klären

28. Was muss **vor** dem ersten echten Nutzer erledigt sein, und was
    darf nachlaufen?
29. Welche Frist gilt für die Beseitigung eines Verstoßes, wenn die
    Aufsichtsbehörde ihn beanstandet?
30. Gibt es etwas, das Sie in meiner Abschätzung als zu vorsichtig oder
    zu lax markiert haben?

## Mitnehmen

- [DSFA.md](DSFA.md) – der Entwurf
- [THREAT-MODEL.md](THREAT-MODEL.md) – was das System tatsächlich tut
- [DATENSCHUTZ.md](DATENSCHUTZ.md) – die aktuelle Erklärung
- Übersicht der Verarbeitungstätigkeiten: die Tabellen in
  `supabase/migrations/` (Spalten mit personenbezogenen Daten) und die
  Aufzählung der Subunternehmer in Abschnitt 6 der
  Datenschutzerklärung

Wenn die Antwort auf eine Frage „das kommt darauf an" lautet: die
Bedingungen für das „darauf an" notieren. Das ist der Teil, der später
in der Abschätzung steht und sie belastbar macht.
