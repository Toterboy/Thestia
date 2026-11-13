# Changelog – Thestia

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
und folgt der [Semantic Versioning Specification (SemVer)](https://semver.org/lang/de/).
Solange die Versionsnummer mit `0.` beginnt (Initial Development Phase nach SemVer §4),
können sich Schnittstellen und Verhalten jederzeit ändern.

## [0.10.0] – Elternfreigabe, Aufsicht und Admin-Posteingang (Build 31, 2026-10-30 bis 2026-11-03)

### Sicherheits-Review (13.11.2026) – Fundstellen geschlossen

Ein vollständiger Durchgang über Funktion, Sicherheit und Datenschutz hat
**vier echte Lücken** gefunden. Alle sind behoben:

- **Transit Spark: die Kandidatenliste hat alle Personen in der Nähe
  preisgegeben** (Migration 215). Die Beschreibung, nach der gefiltert
  wurde, kam ungeprüft vom Client. Der Merkmals-Katalog ist aber für
  jeden angemeldeten Nutzer lesbar – wer ihn vollständig übergibt, traf
  damit **jedes** aktive Signal: Die Liste lieferte alle Personen im
  45-Minuten-Fenster, mit echter User-ID, freier Notiz und selbst
  genanntem Ort. Und der Zuwink an eine benannte Person war an
  **beliebige** nahe Erwachsene möglich (5 je 30 Minuten). Jetzt kommt
  die Beschreibung **serverseitig aus dem eigenen Signal** des Aufrufers
  – der Server prüft sie selbst. Nebenbei war das „höchstens 20
  Kandidaten" wirkungslos (das Limit stand hinter dem Aggregat).
- **Die Datenschutzerklärung hat vier Dinge falsch gesagt** (jetzt
  Version 23): Das Vorstellungs-Audio liegt nicht clientseitig
  verschlüsselt auf dem Server und wird nicht erst bei einem Funke
  freigegeben (im Kandidaten-Deck wird es schon vor dem Like
  abgespielt – das ist der Zweck des Modus); die Zeitzone wird bei jedem
  Start gemeldet und stand nicht im Datenkatalog; beim WebRTC-Aufbau
  gehen SDP und ICE-Kandidaten (mit der lokalen IP-Adresse) über
  Supabase Realtime; und das Transit-Token ist nicht „anonym" im Sinne
  von „der Server kennt die Person nicht". Das Data-Safety-Blatt
  antwortete außerdem auf zwei Console-Fragen falsch („Dritte: nein" –
  es gibt acht Dienstleister; „Einreichung zur Prüfung: nein" – es gibt
  „Daten löschen" und die Auskunft).
- **Fehlertexte landeten im Systemprotokoll des Release-Builds**
  (`dumpErrorToConsole` lief unbedingt). Exception-Texte können
  personenbezogene Daten enthalten; das Crash-Journal redigiert, dieser
  Weg nicht. Im Release bleibt jetzt nur das redigierte Journal.
- **Probe.exe** (ein .NET-Audiomesswerkzeug) lag im Repository. Kein
  Geheimnis, aber ein Windows-Binary im Quellstand einer
  veröffentlichten App ist Lieferketten-Rauschen. Entfernt, und
  `*.exe`/`*.dll`/`*.so`/`*.jar` stehen jetzt in der `.gitignore`.

### Die eigene Tastatur (13.11.2026, Build 54)

- **Die Handytastatur kann nicht mehr mitlesen** (Wunsch des Betreibers:
  "dass die Handytastatur nicht tracken kann was man schreibt"). Beim
  Chat hat die App jetzt **ihre eigene Tastatur**. Die Systemtastatur
  wird gar nicht erst geöffnet: Das Eingabefeld steht auf `readOnly`, und
  auf Android und iOS entsteht bei einem solchen Feld keine
  Eingabeverbindung - es gibt also nichts, was die Tastatur des Geräts
  sehen könnte. Kein Buchstabe, kein Cursor, kein Lernvorgang.
  * Bedienung wie gewohnt: Tippen auf das Feld öffnet die App-Tastatur,
    Groß/Klein, Umlaute, Zahlen, Emoji, Löschen und Enter sind da. Die
    **Belegung folgt der Sprache der App**: Deutsch gibt QWERTZ mit den
    Umlaut-Tasten, Englisch die englische QWERTY-Belegung. Eine
    **Hardwaretastatur** (Tablet mit Tastaturhülle) funktioniert
    weiterhin - auch dort läuft nichts über die Systemtastatur.
  * **Einfügen** aus der Zwischenablage gibt es als eigene Taste (mit
    `readOnly` wäre es sonst deaktiviert).
  * Betroffen sind alle drei Chats: der 1:1-Chat, der Zufallschat und
    der Dating-Hour-Chat.
- **Und überall sonst lernt die Tastatur nicht aus deinen Angaben**:
  In jedem Eingabefeld der App steht jetzt
  `enableIMEPersonalizedLearning: false`. Auf Android heißt das: die
  Tastatur darf aus dem, was du eintippst, nichts in ihr Wörterbuch
  übernehmen und keine personalisierten Vorschläge daraus machen. In den
  Feldern mit persönlichem Text (Vorstellung, Meldungen, Notizen,
  Kontaktdaten) sind zusätzlich Autokorrektur und Vorschläge
  abgeschaltet.
  * **Ehrlich zur Grenze:** Der Schalter gilt nur auf Android - für iOS
    gibt es keine Entsprechung. Deshalb ist der Weg über die eigene
    Tastatur der einzige, der auf **beiden** Plattformen dasselbe
    verspricht. Und: In den Feldern, in denen weiterhin die
    Systemtastatur läuft (Profil, Notizen), sieht die Tastatur den Text
    weiterhin - sie darf ihn nur nicht **lernen**.

### Neu (11.11.2026)

- **Die kleine Zahl in der Kachel stimmt jetzt überall** (Idee des
  Betreibers): Bis jetzt zählte die App die Nachrichten im **lokalen**
  Verlauf – und der entsteht erst, wenn der Chat auf diesem Gerät geöffnet
  wurde. Bei einem nie geöffneten Funke stand deshalb **überhaupt keine**
  Zahl, und auf zwei Geräten standen verschiedene. Der Zähler sitzt jetzt
  **serverseitig**: er zählt jede Nachricht genau einmal und stimmt damit
  auf allen Geräten.
- **Nachricht löschen für alle – wie bei WhatsApp:** Ein langer Druck auf
  eine eigene Textnachricht bietet „Für alle löschen" an. Beim Gegenüber
  steht dann „Diese Nachricht wurde gelöscht".
  *Zur Datenschutz-Frage des Betreibers: Das ist mit dem bestehenden
  E2E-Modell vereinbar.* Der Server speichert **nur die Tatsache**, dass
  eine Nachricht gelöscht wurde – **keinen Text, keine Chiffre, keinen
  Inhalt**. Er weiß damit nichts über den Inhalt, das er nicht schon beim
  Zustellen sieht. Ehrlich gesagt werden muss: die bereits zugestellte
  Kopie beim Gegenüber kann nicht zurückgerufen werden – dort ist die
  Nachricht schon gelesen. Bei WhatsApp ist das genauso.
- **Transit Spark: mehrere mit derselben Beschreibung** (Wunsch des
  Betreibers): Bisher bekam man **eine** Person zu sehen. Jetzt zeigt die
  App **alle** Personen in der Nähe, deren Beschreibung passt – und man
  kann **mehreren** zuwinken (bis zu fünf Zuwinke in 30 Minuten). Der
  Server prüft die Nähe immer selbst: ein Zuwinken an eine beliebige
  Person ist nicht möglich.
- **Transit Spark: den ungefähren Ort angeben** (Wunsch des Betreibers):
  „Zug, Wagen 3" oder „Messe, Halle 2 bei den Toiletten". Der Ort ist eine
  **Selbstauskunft** – die App ermittelt nichts, es wird kein Standort
  gespeichert. Wer in der Nähe ist, sieht deinen Ort nur, wenn er selbst
  einen nennt.
- **Die Nah-Liste verschweigt ihre Größe nicht mehr**: Wer 25 Menschen in
  der Nähe hatte, sah 10 – ohne Hinweis. Jetzt steht die Gesamtzahl da.
- **Die Kategorie-Sicht ist keine Sackgasse mehr**: Ist eine Kategorie
  leer, sagt die App jetzt, in welchen Kategorien Menschen sind.

### Behoben

- **Nachrichten kommen jetzt an** (09.11.2026): Eine Benachrichtigung kam
  an, aber die Nachricht selbst war unsichtbar. Der Grund war eine
  doppelte Buchführung: Der Chat-Screen holte die verschlüsselten
  Relay-Nachrichten nur über das *lokale* Match - und das lokale Match
  eines Server-Funken entsteht erst, wenn der Chat geöffnet wird. Fehlte
  es, brach der Abruf komplett ab und die Nachricht blieb liegen. Dasselbe
  galt für den globalen Relay-Eingang, der Server-Funken nicht zuordnen
  konnte. Beide Wege holen das Match jetzt nach, bevor sie abbrechen.
- **Der Ungelesen-Zähler wurde nie erhöht** (09.11.2026): Es gab nur
  eine Stelle, die ihn zurücksetzte - nie eine, die ihn erhöhte. Badge,
  Hervorhebung und die Sortierung "ungelesene Chats oben" konnten damit
  gar nicht greifen. Der Zähler wird jetzt beim Eintreffen einer
  Nachricht vom Partner geführt (außer der Chat ist gerade offen).
- **Ein Tap auf die Benachrichtigung führt zum Interessen-Screen**
  (09.11.2026): Der Zielpfad wurde gesetzt, aber es gab keinen Handler,
  der ihn auswertete - der Tap öffnete die App und sonst nichts. Jetzt
  werden alle drei Wege verbunden: lokale Benachrichtigung, FCM-Push im
  Hintergrund und FCM-Push bei beendeter App.
- **Der Vorstellungs-Player läuft nicht mehr über** (09.11.2026): Der
  Fortschrittsbalken stand neben dem Knopf und lief in der schmalen
  Kachel aus dem Bereich. Er sitzt jetzt darunter und erscheint nur,
  während tatsächlich etwas läuft.
- **Die Bilder im Chat sind kleiner** (09.11.2026): Sie füllten die ganze
  Zeile der Blase aus. Jetzt sind sie auf eine 160-Pixel-Kachel
  begrenzt - ein Vorschaubild statt des Vollbilds.
- **"Funke bestätigen" bei vorhandenem Funke** (09.11.2026): Wer mit
  dieser Person schon einen Funke hat, bekommt jetzt den Hinweis statt
  eines Knopfes, der nichts Neues bewirkt.
- **Die Reiterleiste bleibt bei "Mit anderen verbinden" sichtbar**
  (09.11.2026): Die QR-Screens lagen außerhalb des Haupt-Navigators und
  waren dadurch Vollbild-Screens ohne Leiste.
- **Der Zufallschat findet keine bekannten Personen** (09.11.2026): Wer
  mit jemandem schon einen Funke hat, ist dort jetzt ausgeschlossen -
  ebenso blockierte Personen (in beide Richtungen). Die Regel gilt auch
  beim Reconnect in eine laufende Session.
- **Transit Spark vergibt genau eine Person** (09.11.2026): Zwei
  gleichzeitige Aufrufe konnten dieselbe Person beanspruchen - sie bekam
  dann zwei Funken. Die Auswahl ist jetzt gesperrt und eindeutig. Wer
  bei Transit Spark schon einen Funke hat, wird darauf hingewiesen
  ("Ihr habt schon einen Funken") statt auf einen neuen Funke zu
  glauben.

### Hinzugefügt

- **Eigener Screen für die Elterneinstellungen:** Der Bereich „Kinderschutz &
  Elternzugriff" lag als große Karte mitten in den Einstellungen (mit
  PIN-Dialog, Benachrichtigungs-Rhythmus und Nutzungszeit) und hat den
  Einstellungs-Screen zugeballert. Jetzt steht dort ein Eintrag mit dem
  aktuellen Status; die Einstellungen selbst liegen auf einem eigenen
  Screen (`/guardian-settings`), weiterhin durch die PIN des
  Elternteils geschützt. Das Freigabe-Ende mit 18 bleibt ohne PIN
  möglich – das entscheidet der Jugendliche selbst.

- **Drei-Schritte-Leitfaden für die Audio-Vorstellung** (03.11.2026):
  Während der Aufnahme begleitet die App die Vorstellung mit drei
  Winkeln in fester Reihenfolge: „Wer bist du?", „Was macht dich
  aus?", „Warum bist du hier?". Die Schritte laufen von selbst (alle
  15 Sekunden ein neuer Winkel); ein Tipp auf einen Schritt übernimmt
  dauerhaft die Steuerung, und nach dem dritten bleibt der dritte
  stehen. Pflicht bleibt Text UND Audio - der Leitfaden ist eine Stütze,
  kein Fragebogen. Für die Text-Vorstellung gab es die rotierenden
  Prompt-Karten schon seit 0.9.2.
- **Das englische Store-Listing ist vollständig** (03.11.2026): Die
  englische Liste hatte keine Phone-Screenshots, und die Tablet-Bilder
  waren Kopien der deutschen - ein englisches Feature-Graphic über
  deutschen Screenshots mit deutschen Headlines. Jetzt sind Render,
  Headlines, Tablet-Bilder und Feature-Graphic je Sprache eigenständig
  (englischer Claim: „Person, not picture."). Der Renderer läuft je
  Sprache (`STORE_SHOTS_LANG=en`), der Compositor hat eigene Quellen,
  Texte und Ausgaben, und die Textprüfung gilt für beide Sprachen.
- **Elternfreigabe für 16- und 17-Jährige:** Direkt nach dem
  Willkommens-Screen kann die E-Mail-Adresse eines Elternteils
  eingetragen werden. Sie muss von der eigenen Kontoadresse abweichen –
  sonst würde sich der Jugendliche selbst als Elternteil eintragen.
  Der Elternteil bekommt eine E-Mail mit einem Link, bestätigt dort die
  Freigabe und kann sie jederzeit widerrufen. **Die Zustimmung ist
  freiwillig**: nach § 3a JUG kann eine Person ab dem vollendeten
  16. Lebensjahr selbst einwilligen, und niemand wird an der Nutzung
  gehindert, weil die Zustimmung ausbleibt.
- **Der Elternteil ist Genehmiger, nicht Nutzer:** Es gibt kein
  Elternkonto. Er sieht weder Nachrichten noch Profile noch den
  Standort des Jugendlichen.
- **Eltern-Benachrichtigung bei neuen Funken:** Entsteht ein Funke (ein
  gegenseitiges „Du magst mich" – nicht schon ein einzelnes Like),
  bekommt der Elternteil eine kurze Nachricht. Die Häufigkeit legt er
  selbst fest: täglich, wöchentlich, monatlich oder gar nicht. **Dabei
  werden keine Namen, Profile oder Inhalte weitergegeben** – er erfährt
  nur, *dass* ein Funke entstanden ist.
- **Nutzungszeit per PIN gesichert:** Der Elternteil kann ein
  Zeitfenster festlegen, in dem die App genutzt werden darf. Die
  Einstellung ist mit einer vierstelligen PIN geschützt; die PIN wird
  nur auf dem Server geprüft (bcrypt) und ist auf dem Gerät des
  Jugendlichen nicht gespeichert. Nach fünf Fehlversuchen ist die
  Prüfung für eine Stunde gesperrt.
- **Entscheidung mit 18:** Wer bei der Registrierung 16 oder 17 war,
  bekommt mit 18 einen eigenen Screen: Elternzugriff beenden, für 1 bis
  6 Monate behalten oder erstmal weiter behalten. Der Bereich bleibt
  auch ab 18 in den Einstellungen sichtbar, damit die Freigabe geordnet
  werden kann.
- **Neuer Einstellungsabschnitt „Kinderschutz & Elternzugriff"** mit
  dem Stand der Freigabe, dem Benachrichtigungs-Rhythmus, der
  Nutzungszeit und der Frage, wie lange der Zugriff bestehen soll.
- **Eltern-Portal** unter `auth.thestia.de/eltern`: bestätigen,
  einstellen, widerrufen.

- **Daten löschen ohne das Konto zu löschen:** Unter *Datenschutz &
  Account* gibt es jetzt einen eigenen Eintrag. Du kreuzt an, was
  verschwinden soll - Profilfotos, Standortdaten, Profilangaben, Likes,
  Funken, deine gesendeten Nachrichten, Geräte und Schlüssel, Stimmung
  und Verlauf, Meldungen, Transit-Spark-Daten oder die elterliche
  Freigabe - und bestätigst. Das Konto, deine E-Mail und dein Passwort
  bleiben. „Alle Daten löschen" entfernt sämtliche Daten zum Konto und
  lässt das Konto selbst bestehen. Die Löschung ist unwiderruflich; was
  auch die Gegenseite betrifft (Funken beenden den Chat für beide),
  steht bei der jeweiligen Kategorie.
- **Der Suchfilter hat jetzt drei echte Modi:** „Entfernung (km)",
  „Bundesland" und „Ganz Deutschland" filtern auch unterschiedlich.
  Vorher filterten die beiden letzten Modi dasselbe - gar nichts: der
  Bundesland-Vergleich fehlte vollständig, und niemand hat es gemerkt,
  weil die Liste plausibel aussah. Bei 16 und 17 gilt weiterhin:
  höchstens 25 km oder nur das gleiche Bundesland.

### Sicherheit

- **Die Website trägt jetzt Sicherheits-Header** (04.11.2026): Auf
  keiner Seite waren `X-Frame-Options`, `X-Content-Type-Options`,
  `Referrer-Policy`, `Permissions-Policy`, HSTS oder ein CSP-**Header**
  gesetzt. Die Startseite hatte nur eine `meta`-CSP - und eine
  `meta`-CSP kann `frame-ancestors` gar nicht abbilden. Damit waren
  zwei Clickjacking-Angriffe möglich: die CAPTCHA-Seite
  (`auth.thestia.de`) ließ sich in jedem `<iframe>` einbetten, und das
  Eltern-Portal (`/eltern/einstellungen?token=…`) ließ sich framen -
  samt der Schaltflächen „Freigabe bestätigen" und „Freigabe
  widerrufen".
- **Der Berechtigungs-Token des Eltern-Portals wird nicht mehr
  zwischengespeichert** (04.11.2026): Das Portal bekommt den Token aus
  der URL. „public"-Cache hätte die Seite mit dem Token in der
  Cache-Adresse gespeichert, und ohne `Referrer-Policy` landet der
  Token bei jedem internen Klick im Referer-Header - also in den
  Server-Logs. Jetzt `no-store` und `no-referrer`; der
  Sprachumschalter nimmt den Token mit.
- **Die interne Betriebsnotiz zum App-Link-Aufbau wird nicht mehr
  veröffentlicht** (04.11.2026): `ASSETLINKS_ROOTDOMAIN.md` nennt die
  Stellen, an denen ein Angreifer nachsehen würde (Debug-Keystore,
  `key.properties`, Supabase-Redirect-Allowlist). Sie liegt jetzt in
  `deploy/`; ein Redirect fängt die bereits veröffentlichte Datei ab.

- **Keine Session-Fixierung über einen Deep-Link:** „thestia://" ist
  ein exportiertes Custom Scheme – jede App auf dem Gerät konnte die
  Thestia-App mit einer URI starten. Übernahm die App eine URI mit
  `access_token` oder `token_hash`, legte sie eine Session für genau
  dieses Konto an, ohne dass der Nutzer den Link in seiner E-Mail
  geöffnet haben musste. Eine bösartige App konnte so den
  Passwort-Reset-Screen mit dem Konto des Angreifers öffnen; alles,
  was der Nutzer danach hochlädt, wäre im Konto des Angreifers
  gelandet. Beide genutzten Flows sind ohnehin PKCE-basiert (der Link
  enthält einen Code, der nur mit dem geräteeigenen Verifier
  einlösbar ist) – die abgelehnten Formen waren ungenutzte
  Freiheitsgrade und genau die Angriffsfläche.
- **FLAG_SECURE auf allen Bildschirmen:** Das Flag saß bisher nur in
  der Haupt-Activity. Auf dem Bild-Crop (Profilbild) war der
  Screenshot-Schutz nicht gesetzt – dort konnte also ein Foto gemacht
  werden. Jetzt setzt ein Lifecycle-Callback das Flag auf jeder
  Activity, die nicht von uns stammt.
- **Der Captcha-Bridge prüft das Token-Format:** Der JavaScript-Kanal
  des Sicherheitschecks nimmt Nachrichten von jeder im WebView
  geladenen Seite an. Jetzt wird nur ein String im Turnstile-Format
  („0." + erlaubte Zeichen) als Token akzeptiert.
- **Downloads nur von eigenen Hosts:** Die signierte URL aus der
  Edge-Funktion wurde ungeprüft geladen. Jetzt werden Schema und Host
  geprüft – eine manipulierte Backend-Antwort kann die App nicht mehr
  auf einen fremden Host schicken.
- **Der UnifiedPush-Endpunkt muss HTTPS sein:** Sonst würden die
  Push-Metadaten im Klartext übertragen.
- **Das BLE-Funk-Radio schweigt im Hintergrund:** Siehe Akku.

### Akku

- **Das Bluetooth-Radio wird abgeschaltet, wenn die App in den
  Hintergrund geht.** Das Advertising lief bis zu 45 Minuten im
  ~100-ms-Takt weiter, auch wenn der Nutzer die App nicht ansah –
  der eigene Kommentar am Dateianfang sagte „Vordergrund-Betrieb",
  die Umsetzung folgte ihm nicht. Das war der größte Einzelposten
  (und zugleich ein Datenschutzproblem: Funkaktivität ohne sichtbare
  Anzeige).
- **Kein Polling im Hintergrund:** Der Transit-Radar (alle 15 s ein
  Server-Request), der Dating-Hour-Screen (30 s) und der Quiz-Warte-
  poller (3 s) laufen jetzt nur im Vordergrund. Der Screen bleibt im
  Backstack gemountet – vorher liefen die Timer unbegrenzt weiter.
- **Der Ticker der Nutzungszeit-Sperre läuft nur, wenn überhaupt eine
  Nutzungszeit begrenzt ist** – vorher 2880 Weckrufe am Tag bei jedem
  Nutzer, unabhängig davon.
- **Die Bildverarbeitung läuft im Hintergrund-Isolate** (Chat-
  Hintergrund, Fehlerbericht). Das `image`-Paket ist reines Dart und
  blockierte den UI-Thread; bei einem großen Foto hing der Bildschirm
  sichtbar.

### Suchradius für 16- und 17-Jährige begrenzt: höchstens 25 km oder
  nur das gleiche Bundesland. „Ganz Deutschland" ist gesperrt und wird
  serverseitig wie 25 km behandelt. Ab 18 bleibt alles frei wählbar.
  Beim Umsetzen kam heraus: der Modus „Bundesland" hatte nie einen
  serverseitigen Filter – server-seitig hießen „Bundesland" und „Ganz
  Deutschland" beide „kein Radius". Die Bundesland-Bedingung ist neu.
- **Der Token der Freigabe wird nur als Hash gespeichert** und ist nach
  14 Tagen ungültig.
- **Jede Anfrage, Bestätigung und jeder Widerruf wird protokolliert**
  (Art. 5 Abs. 2 DSGVO).
- **Datenschutzerklärung** um einen eigenen Abschnitt zur Elternaufsicht
  erweitert (Version 20); die DSFA führt die neue Maßnahme und ihre
  Grenzen.

### Behoben

- **Die CI war an einer Zeile rot, obwohl lokal alles grün war**
  (04.11.2026, Läufe #265, #266 und #268): In `test/web_pages_test.dart`
  stand `'${assets.path}/${url}'`. Die Klammern um `url` sind überflüssig,
  und Dart meldet das als *Hinweis* (`unnecessary_brace_in_string_interps`).
  Die CI ruft `flutter analyze --fatal-infos` auf – dort ist ein Hinweis
  ein **Fehler**. Lokal läuft `flutter analyze` ohne diese Flag und meldet
  „No issues found". Deshalb blieb die CI drei Läufe lang rot, während
  die lokale Prüfung grün war. Der Schritt „Tests" wurde danach gar nicht
  mehr ausgeführt, ein dahinterliegender Fehler wäre unsichtbar
  geblieben. (Geprüft über die öffentliche GitHub-API: In allen drei
  Läufen war ausschließlich der Job `analyze-and-test` rot, und zwar
  nur im Schritt „Analyze". Die übrigen fünf Jobs waren grün.)

- **Der MFA-Step-up bei der Konto-Löschung war wirkungslos**
  (04.11.2026, Audit der Edge Functions): Die Funktion `delete-account`
  rief `client.auth.mfa.listFactors(userId)` auf - das ist aber die
  *Nutzer*-API: sie nimmt kein Argument, braucht eine Session des
  Clients (der Service-Key-Client hat keine) und liefert deshalb
  `{ data: null }`. Die Faktorenliste war immer leer, die Prüfung
  immer „erfüllt". Ein Konto mit aktiviertem TOTP ließ sich mit einem
  einfachen aal1-Token unwiderruflich löschen. Jetzt wird die
  *Admin*-API benutzt (`client.auth.admin.mfa.listFactors({ userId })`)
  und fail-closed blockiert, wenn die API fehlt oder fehlschlägt.
- **Die selektive Datenlöschung löschte die Rate-Limit-Zähler
  nicht** (04.11.2026): `delete-user-data` filterte auf
  `rate_limit_hits.identifier` - diese Spalte gibt es nicht (die
  Tabelle hat nur `bucket_key`, `window_start` und `hit_count`).
  PostgREST antwortete mit einem Spaltenfehler, die Kategorie „alles"
  meldete dauerhaft `ok:false`, und die Zähler blieben stehen. Jetzt
  wird über `bucket_key` gelöscht.
- **Das IP-Limit war umgehbar** (04.11.2026): Die Client-IP wurde zuerst
  aus `x-client-ip` gelesen. Das ist *kein* Header von Supabase oder
  Cloudflare (sondern eine Vercel/Netlify-Konvention) - Edge Functions
  reichen unbekannte Client-Header unverändert durch. Mit
  `x-client-ip: 1.2.3.4` pro Anfrage bekam jede Anfrage ein neues
  Limit-Key. Jetzt zuerst `cf-connecting-ip` (den Cloudflare bei jeder
  Anfrage neu setzt) und aus `x-forwarded-for` der **letzte** Eintrag
  (Cloudflare hängt die echte IP an - der erste ist der vom Client
  frei wählbare).
- **Das Rate-Limit im Entsperrungsantrag war fail-open**
  (04.11.2026): `request-unban` wertete den Fehler der RPC nicht aus -
  bei einem Stoerfall fiel die 3/h-Bremse ersatzlos weg, und die
  Entsperrungsanträge wurden eine Mail-Bombardierung von
  `support@thestia.de`. Jetzt fail-closed wie in allen anderen
  Funktionen.
- **E-Mail-Adressen wurden ungefiltert in ein LIKE-Muster gebaut**
  (04.11.2026): In SQL ist `%` ein Platzhalter und `_` matcht ein
  beliebiges Zeichen. Eine Adresse wie `%@beispiel.de` löschte dadurch
  die Rate-Limit-Buckets *aller* Adressen auf dieser Domain. Die
  Muster werden jetzt maskiert (`escapeLike`).
- **Die elterliche Nutzungszeit konnte ungewollt gelöscht werden**
  (04.11.2026, Migration 173): `set_guardian_portal_settings` schrieb
  `usage_start_min = p_usage_start_min` *ohne* `coalesce` - fehlte der
  Wert im Request, war die Beschränkung weg, während
  `usage_limit_enabled` weiter „aktiv" anzeigte. Jetzt mit `coalesce`
  und Bereichsprüfung (0–1439 Minuten, Ende > Beginn). Eine aktive
  Nutzungszeit braucht jetzt auch eine Zeit.
- **Die Versionsangabe der Datenschutzerklärung widersprach ihrer
  eigenen Historie** (04.11.2026): Sie nannte Version 17 (Oktober),
  die Historie reichte bis Version 22 (November).
- **Die englische Datenschutzerklärung nannte die alte Aufbewahrungs-
  frist** (04.11.2026): Sie versprach das Verifikationsvideo „30 Tage
  nach der Einreichung" zu löschen, die deutsche Fassung und die
  Versionshistorie sagten korrekt „30 Tage nach der Freigabe"
  (Migration 171). Die englische Tabelle war beim Umsetzen nicht
  mitgezogen worden.
- **Das Crash-Journal speicherte Rohdaten** (04.11.2026): Der Kommentar
  versprach „keine Nutzertexte, keine Geräte-Serials, keine PII",
  gespeichert wurden aber der rohe Fehlertext und der rohe Stack.
  Ein Supabase-Fehler kann die E-Mail-Adresse enthalten, und das
  Journal wird dem Nutzer per Bug-Report angeboten - die Daten wären
  also über das Gerät hinausgegangen. Jetzt werden E-Mail-Adressen,
  Bearer-Token, JWTs und lange Hex-Schlüssel redigiert; UUID und
  Dateipfade bleiben (ohne sie ist der Absturz nicht zuordenbar).
- **Die Kapsel des Datenlösch-Wegs versprach ein Formular, das es nicht
  gibt** (04.11.2026): Der Text auf `/daten-loeschen` sagte „die Seite
  `/konto-loeschen` öffnen und das Formular ausfüllen" - im gesamten
  Publish-Ordner gibt es kein einziges `<form>`. Der Weg 3 ist
  tatsächlich die App oder die E-Mail; der Text sagt das jetzt.

- **Die englische Startseite verlinkte die deutschen Pflichtseiten**
  (04.11.2026): „Legal notice" und „Privacy" fuehrten zu den deutschen
  Texten. Jetzt zeigen alle Links auf die englischen Seiten
  (`/en/...`, die in `_redirects` auf die englischen Dateien zeigen).
- **Die Startseite und die `.well-known`-Dateien fielen durch die
  Cache-Regeln** (04.11.2026): Netlify wendet die `_headers`-Regeln auf
  den *aufgerufenen* Pfad an - die Regel für `/index.html` galt also
  nicht für `/`. Die wichtigste Seite des Projekts lieferte deshalb
  `max-age=0` statt der 5-Minuten-Regel, und genau die Datei, die
  Android bei jeder App-Link-Prüfung neu abruft, ebenfalls.
- **Die `_redirects` spiegeln jetzt die Regeln aus `netlify.toml`**
  (04.11.2026): Ob die Konfigurationsdatei bei einem Drag-&-Drop-Upload
  ausgewertet wird, lässt sich aus dem Repo nicht belegen. Im
  Live-Stand vom 04.11.2026 war `robots.txt` auf *beiden* Hosts die
  gesperrte Fassung und `sitemap.xml` gab es gar nicht - die
  oeffentliche Seite war also für Suchmaschinen gesperrt. Die Regeln
  zeigen auf dieselben Ziele wie in der TOML, deshalb ist die
  Spiegelung unschaedlich.

### Hinzugefügt

- **Das Store-Listing nennt jetzt beide Kanäle** (05.11.2026): Bisher
  stand dort „Ab 16 Jahren, mit Elternfreigabe für 16- und 17-Jährige".
  Das ist im Play Store falsch - Google verlangt für Dating-Apps
  zwingend eine Altersgrenze von 18, die 16+-Pfade sind im
  Play-Store-Build also gar nicht erreichbar. Jetzt steht dort: im Play
  Store ab 18 Jahren, in anderen Kanälen (F-Droid) ab 16 Jahren mit
  Elternfreigabe. Eine Invariante sichert das ab.
- **Die Nutzungsbedingungen sind jetzt auch in der App** (05.11.2026):
  Die Seiten gab es seit dem 05.11. (passkey-assets/
  nutzungsbedingungen.html), in der App gab es aber keinen Link darauf.
  Jetzt steht die Kachel neben der Datenschutzerklärung und dem
  Impressum - Play verlangt für jede App eine erreichbare Adresse der
  Nutzungsbedingungen.

- **Das Impressum ist jetzt vollständig, die Nutzungsbedingungen gibt es
  überhaupt** (05.11.2026): Die Rechtslage wurde recherchiert und das
  Ergebnis umgesetzt.
  * **Die Anschrift steht jetzt auf der Seite selbst** (§ 5 Abs. 1 Nr. 1
    DDG). Vorher verwies das Impressum auf das Google-Play-Entwickler-
    profil - damit hing die gesetzlich geforderte ladungsfähige Anschrift
    an einer fremden Plattform. Fällt das Profil aus, hat das Impressum
    gar keine Anschrift. Der Verweis bleibt als Zusatz, ersetzt aber
    nichts. Als sichtbarer Platzhalter markiert, damit die Seite nicht
    mit einer erfundenen Adresse online geht.
  * **Der Abschnitt „EU-Streitschlichtung" ist raus** (DE + EN): Die
    ODR-Plattform der EU ist seit dem 20.07.2025 abgeschaltet
    (VO (EU) 2024/3228). Der Absatz behauptete das Gegenteil.
  * **Die App hat jetzt einen Impressum-Einstieg** (in den
    Datenschutz-Einstellungen): Die App ist selbst ein digitaler Dienst
    im Sinne des § 5 DDG - die Informationspflichten gelten für sie,
    nicht nur für die Website.
  * **Die Nutzungsbedingungen gibt es jetzt** (neu, DE + EN): Mindestalter
    16, Elternfreigabe für 16/17-Jährige, Verhaltensregeln,
    Sonderregeln für Minderjährige, Moderation mit Begründungspflicht und
    Widerspruchsweg, Daten und Löschung, Haftung, Open Source. Damit
    liegen die nach DSA Art. 16 geforderten Bedingungen vor.
  * **Die Meldestelle nennt jetzt auch den Meldeweg für rechtswidrige
    Inhalte** (DSA Art. 18, Bundesnetzagentur). Vorher gab es dort nur
    den Polizei-Weg für Kindesmissbrauch.
- **Drei Behauptungen auf der Website stimmen jetzt mit dem Code überein**
  (05.11.2026, gefunden bei der Bestandsaufnahme):
  * „Die Nutzungszeit ist eine Hausregel auf dem Gerät" - sie wird seit
    Migration 176 auch **serverseitig** erzwungen (Dating Hour). Nur der
    WebRTC-Chat bleibt clientseitig, und das steht jetzt so da.
  * „Das Funken-Ereignis wird nach dem Versand gelöscht" - im Code wird
    nur der Versandzeitpunkt gesetzt.
  * „Der Altersnachweis bleibt bestehen" - beim Löschen aller Daten geht
    er mit.
- **Die Nutzung durch 16- und 17-Jährige ist jetzt vollständig
  dokumentiert** (`docs/MINDERJAEHRIGE-NUTZUNG.md`, 18 KB): Jede
  Altersregel, der komplette Freigabe-Ablauf, was der Elternteil darf
  und was nicht, die Nutzungszeit, der 18. Geburtstag, die Daten und ihre
  Löschwege, die Moderation, die Rechtsgrundlagen und die
  Store-Angaben - jeweils mit Datei und Zeile. Dazu vier Lücken, die
  eine Entscheidung brauchen (siehe das Dokument).

- **Der Standort-Check ist jetzt atomar** (04.11.2026, Migration 180):
  Bisher las die Funktion die alte Position, rief `check-location` auf
  (zwei Netzwerkaufrufe) und schrieb erst danach. In diesem Zeitfenster
  konnten zwei Aufrufe parallel laufen: Beide rechneten gegen dieselbe
  veraltete Basis, und der normale Pfad schrieb das Verdachtsflag mit
  dem Ergebnis der *eigenen* Prüfung - ein späterer, unauffälliger
  Aufruf konnte ein gerade gesetztes Flag wieder auf false setzen.
  Jetzt passiert alles in **einer** Datenbanktransaktion unter einer
  Zeilensperre (`SELECT ... FOR UPDATE`). *Bewiesen:* Zwei gleichzeitige
  Aufrufe auf die Live-Datenbank - der zweite wartete 1,7 s, bis der
  erste die Sperre freigab (datenbankseitig gemessen: 1667 ms).
- **Das Admin-Review hat jetzt eine Bremse und eine Spur**
  (04.11.2026, Migration 180/181): Der Review-Pfad war die einzige
  Aktion ohne Rate-Limit - mit einem geleakten Admin-Token ließ sich
  massenhaft freigeben oder verweigern. Und es gab keinen einzigen
  Eintrag darüber, wer wen wann freigegeben hat. Jetzt prüft die
  *Datenbank* selbst, dass der Aufrufer Admin ist, begrenzt auf 60
  Reviews pro Admin und Stunde und schreibt jeden Vorgang in eine neue
  Tabelle `admin_action_audit` - in derselben Transaktion wie die
  Änderung. Ein Review ohne Spur ist damit nicht mehr möglich.
- **Die App sagt jetzt, was mit der E-Mail des Elternteils passiert**
  (04.11.2026): Nach dem Ende der Freigabe sah der Screen aus wie
  "es gab nie eine Freigabe". Jetzt steht dort "Die Freigabe ist
  beendet" - und, dass die E-Mail-Adresse des Elternteils dabei
  gelöscht wurde. Der Server meldet den Löschzeitpunkt mit, die App
  behauptet es also nicht ohne Beleg.
- **BEFUND im Emulator-Test: Die App erfuhr nie, dass die Freigabe
  beendet war** (04.11.2026, Migration 182): Die RPC, die den Stand
  meldet, suchte die Freigabe mit `status IN
  ('pending','active','expired')` - "revoked" fehlte. Bei einer
  widerrufenen Freigabe fand sie keine Zeile und meldete "keine
  Freigabe" zurück. Die neue Anzeige ("Die Freigabe ist beendet")
  wäre also **nie** erschienen.
  *Warum der Widget-Test das nicht gefunden hat:* Er fuettert das
  Modell direkt mit dem Status. Nur der Weg App -> Server -> App findet
  einen Fehler in der RPC. Genau deshalb wurde die App auf einem
  echten Android-Emulator durchgetippt - Registrierung, Login,
  Onboarding, Einstellungen, Elternbereich - und der Zustand in der
  Datenbank von Hand gesetzt. Beide Faelle wurden danach am echten
  Gerät nachgewiesen: aktive Freigabe (zeigt die Eltern-Adresse und
  die Einstellungen) und beendete Freigabe (zeigt "Die Freigabe ist
  beendet" und dass die Adresse geloescht wurde).
- **Die Tabellen der Website sind abgerundet** (04.11.2026): Das pinke
  Element (der Tabellenkopf) bei "Daten löschen" hatte eckige Ecken,
  weil die Tabellen nicht in der abgerundeten Hülle lagen. Jetzt tun
  sie das.
- **Der Freigabe-Link für Elternteile gilt nur noch 24 Stunden**
  (04.11.2026, Migration 179): Bisher war er 14 Tage gültig - und ein
  Link, der zwei Wochen in einem Postkasten liegt, wird irgendwann von
  einer fremden Person benutzt. Die Frist steht jetzt im Server
  (`token_expires_at = now() + interval '24 hours'`), nicht nur im
  Text. Auch die offenen Links aus dem Bestand wurden auf 24 Stunden
  gekürzt.
- **Die E-Mail-Adresse des Elternteils verschwindet mit der Freigabe**
  (04.11.2026, Migration 179): Endet die Freigabe, wird die Adresse
  gelöscht - sie wird dann für nichts mehr gebraucht (keine
  Benachrichtigungen, kein Zugang zum Elternportal). Das gilt für alle
  drei Wege: der Jugendliche beendet, der Elternteil widerruft, der
  Zugriff endet sofort. **Eine Ausnahme:** Wer „noch einen Monat
  behalten" wählt, hat die Freigabe noch nicht beendet - dann bleibt
  die Adresse bis nach dem Monat stehen und wird erst dann gelöscht
  (der Cron räumt sie ab). Wann gelöscht wurde, steht in
  `email_deleted_at`.
- **Jede Website-Seite hat jetzt eine englische Fassung** (04.11.2026):
  Die Bestätigungsseite war die letzte ohne. Alle 20 Seiten sind jetzt
  zweisprachig, jede verlinkt auf die andere Fassung, und eine neue
  Dauerprüfung (`tool/check_publish_folder.py`) sagt es, wenn eine
  Seite fehlt.
- **Die Kopfschaltflächen der Website sitzen wieder auf gleicher Höhe**
  (04.11.2026): Der Modus-Knopf (Hell/Dunkel) und der Sprachknopf waren
  im Elternbereich 5,6 px versetzt. Ursache war eine seiten-eigene
  Formular-Regel, die auch den Modus-Knopf traf - er ist ja ein
  `label`. Die Kopf-Knöpfe bekommen jetzt kein `margin` mehr, und ihr
  Kürzel sitzt mittig im Knopf.

- **Der Freigabe-Link für Elternteile gilt nur noch 24 Stunden**
  (04.11.2026, Migration 179): Bisher war er 14 Tage gültig - und ein
  Link, der zwei Wochen in einem Postkasten liegt, wird irgendwann von
  einer fremden Person benutzt. Die Frist steht jetzt im Server
  (`token_expires_at = now() + interval '24 hours'`), nicht nur im Text.
  Auch die offenen Links aus dem Bestand wurden auf 24 Stunden gekürzt.
- **Die E-Mail-Adresse des Elternteils verschwindet mit der Freigabe**
  (04.11.2026, Migration 179): Endet die Freigabe, wird die Adresse
  gelöscht - sie wird dann für nichts mehr gebraucht (keine
  Benachrichtigungen, kein Zugang zum Elternportal). Das gilt für alle
  drei Wege: der Jugendliche beendet, der Elternteil widerruft, der
  Zugriff endet sofort. **Eine Ausnahme:** Wer „noch einen Monat
  behalten" wählt, hat die Freigabe noch nicht beendet - dann bleibt
  die Adresse bis nach dem Monat stehen und wird erst dann gelöscht
  (der Cron räumt sie ab). Wann gelöscht wurde, steht in
  `email_deleted_at`.
- **Jede Website-Seite hat jetzt eine englische Fassung** (04.11.2026):
  Die Bestätigungsseite war die letzte ohne. Alle 20 Seiten sind jetzt
  zweisprachig, jede verlinkt auf die andere Fassung, und eine neue
  Dauerprüfung (`tool/check_publish_folder.py`) sagt es, wenn eine
  Seite fehlt.
- **Die Kopfschaltflächen der Website sitzen wieder auf gleicher Höhe**
  (04.11.2026): Der Modus-Knopf (Hell/Dunkel) und der Sprachknopf waren
  im Elternbereich 5,6 px versetzt. Ursache war eine seiten-eigene
  Formular-Regel, die auch den Modus-Knopf traf - er ist ja ein
  `label`. Die Kopf-Knöpfe bekommen jetzt kein `margin` mehr, und ihr
  Kürzel sitzt mittig im Knopf.
- **Die Tabellen sind abgerundet** (04.11.2026): Das pinke Element
  (der Tabellenkopf) bei „Daten löschen" hatte eckige Ecken, weil die
  Tabellen nicht in der abgerundeten Hülle lagen. Jetzt tun sie das.

- **Die Dating Hour bekommt einen ausblendbaren Timer und zwei
  Fristen** (04.11.2026, Migration 177): Die 5 Minuten sind jetzt eine
  *Entscheidungsphase*, nicht das Ende des Gesprächs. Nach 5 Minuten
  steht mittig im Chat ein sanfter Hinweis („Ihr habt Zeit, in Ruhe zu
  entscheiden"), der Chat bleibt bedienbar, und erst nach 10 Minuten
  entsteht automatisch ein beidseitiger Funke. Der Grund: Wenn auf einer
  Seite die Verbindung abbricht und das Gespräch weiterläuft, sollen
  zwei, die sich gut verstanden haben, trotzdem ihr Match bekommen -
  nicht nur, weil niemand auf „Ablehnen" geklickt hat.
- **Der automatische Funke ist als solcher gekennzeichnet** (04.11.2026):
  Auf dem Interessen-Screen trägt er ein dezentes Kennzeichen, und beim
  Antippen wird *einmal* gefragt: passt das zu euch, oder soll die
  Person verschwinden? Wer sie behalten will, verliert nur den Hinweis.
  Wer sie entfernen will, verliert sie - wie bei einem normalen
  Funke.
- **Das Gespräch lässt sich jederzeit beenden** (04.11.2026): Von einer
  Seite aus, ohne Begründung. Ein beendetes Gespräch bekommt *keinen*
  automatischen Funke - „beenden" ist ein aktives „ich will das nicht",
  kein passives „es ist nichts passiert".
- **Der Timer ist aus- und wieder einblendbar** (04.11.2026): Nicht
  jeder möchte, dass ein Gespräch nach Zeit aussieht.

- **`tool/check_local_ci.ps1` – die CI-Gates lokal laufen lassen**
  (04.11.2026): Das Skript spiegelt die vier Jobs aus
  `.github/workflows/ci.yml` und benutzt dieselben Flags: der Analyzer
  mit `--fatal-infos`, die Tests mit der `.env` aus `.env.example`,
  `python3` mit Rückfall auf `python`. Ohne diesen Spiegel bleibt man
  der Meinung, alles sei grün, während die CI rot ist – genau das ist
  dreimal passiert. Aufruf:

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\tool\check_local_ci.ps1
  ```

### Bekannte Grenzen

- Die Nutzungszeit ist eine Hausregel auf dem Gerät des Jugendlichen.
  Sie verhindert die versehentliche Überschreitung, ist aber kein
  technisches Verbot – ein gerootetes Gerät kommt an ihr vorbei.
  **Die Durchsetzung passiert ausschließlich im Client** (die
  Datenbank speichert nur die Minutenwerte, keine Filter- oder
  Gate-Funktion prüft sie). Das ist bewusst so: die Minuten sind
  „Minuten seit Mitternacht in der Zeitzone des Geräts", und der
  Server kennt die Zeitzone des Geräts nicht zuverlässig. Eine
  serverseitige Durchsetzung würde deshalb in der falschen
  Zeitzone arbeiten. Wer das ändern will, muss die Zeitzone mit dem
  Gerät zuverlässig übermitteln – das ist eine eigene Aufgabe.
- Die rechtliche Prüfung (§ 3a JUG, Art. 8 DSGVO, Verantwortlichkeit
  für die Einrichtung eines kindlichen Kontos) steht aus. Sie ist in
  der DSFA und in der Roadmap festgehalten.

### Nachtrag vom 30./31.10.2026

### Hinzugefügt

- **Sicherheits-Aufklärung vor dem Setup:** Nach der E-Mail-Bestätigung
  fragt die App, ob bereits eine Dating-App benutzt wurde und ob die
  Gefahren beim Online-Dating bewusst sind. Bei „Nein" folgt eine
  Aufklärung aus fünf horizontal wischbaren Seiten (maximal fünf
  Minuten). Der Fortschritt liegt lokal und wird nach einem Neustart
  fortgesetzt; ist er nicht wiederherstellbar, beginnt die Aufklärung
  von vorn. Der Abschluss wird als eigenes Setup-Flag gespeichert.
- **„Connect to others" statt „QR Code scannen Modi":** Zusätzlich zum
  QR-Code (eigenes Profil, Scannen, Code eingeben) lassen sich
  Telefonnummer und Handles für Signal, Threema, Instagram, Snapchat,
  Discord und eigene Apps hinterlegen. Signal und Threema sind als
  empfohlen markiert, Instagram, Snapchat und Discord als „nicht
  empfohlen". Telefonnummer und Handles werden ausschließlich
  verschlüsselt im Keystore/Keychain (`SecureNamespaces.contacts`)
  gespeichert und nur beim aktiven Teilen oder Kopieren weitergegeben.
- **Öffentliche Seite „Sicher daten":** Ausführliche Fassung der
  Aufklärung unter `/dating-sicherheit` im Design der übrigen
  Thestia-Seiten (statisch, Dark/Light-Modus, kein JavaScript).
- **QR-Schnellzugriff auf „Aktuelles":** QR-Symbol neben den
  Einstellungen öffnet das Menü direkt.

### Behoben

- **Die Dating Hour hat seit dem 03.11.2026 nicht mehr gepaart**
  (04.11.2026, Migration 176): `match_dating_hour_round` prüfte den
  *Aufrufer* auf Verifikation - und die Funktion wird ausschließlich vom
  Cron aufgerufen (alle 30 Sekunden), also **ohne JWT**. `auth.uid()`
  ist dort `NULL`, `verification_granted(NULL)` ist `false` - der Cron
  warf bei der ersten aktiven Veranstaltung `verification_required`
  und brach damit die **gesamte Runde** ab. Die App ruft die Funktion
  nicht selbst auf (nur `join_dating_hour`), der Cron war der einzige
  Weg - es wurde also überhaupt nicht mehr gepaart. Das wöchentliche
  Event mit den Fünf-Minuten-Gesprächen hat damit nicht funktioniert.
  Jetzt wird der Aufrufer nur geprüft, wenn er selbst handelt; die
  Teilnehmer werden in der Schleife geprüft (das war ohnehin schon so).
- **Die elterliche Nutzungszeit wird jetzt serverseitig geprüft**
  (04.11.2026, Migration 176): Bisher galt sie ausschließlich im
  Client - und der Client ist patchbar. Die Zusage gegenüber dem
  Elternteil war damit nicht belastbar. Der Server kann sie jetzt
  prüfen, weil er die Zeitzone des Geräts kennt: Die App meldet sie
  bei jedem Start (IANA-Name, z. B. `Europe/Berlin`), und der Server
  rechnet damit selbst - inklusive Sommerzeit. Geprüft wird je
  Teilnehmer der Dating Hour, nicht je Veranstaltung (eine
  Beschränkung darf nur die betroffene Person betreffen).
  *Ehrliche Grenze:* Der Chat läuft Ende-zu-Ende verschlüsselt über
  WebRTC - der Server ist dort nicht im Pfad und kann einen Chat nicht
  unterbinden. Für den Chat bleibt die clientseitige Sperre die
  einzige Schranke.
- **`admin-ban` muss nicht mehr die GoTrue-Nutzerliste abklopfen**
  (04.11.2026, Migration 176): Die Funktion suchte die User-ID zu
  einer E-Mail-Adresse durch Blättern in der GoTrue-Admin-API (bis zu
  25 Seiten à 200 Nutzer). `profiles` speicherte die Adresse gar
  nicht. Jetzt steht sie dort (aus `auth.users`, indexiert) - die
  Suche ist eine Abfrage.
- **Der Testschalter `?ansicht=captcha` war auf jedem Host aktiv**
  (04.11.2026): Er zwang die Sicherheitscheck-Ansicht auch auf
  `thestia.de` - dort wurde der Turnstile-Script von Cloudflare
  geladen, obwohl der Sitekey nur für `auth.thestia.de` freigeschaltet
  ist (Fehler 110200, verbrauchte Netlify-Credits). Der Schalter ist
  jetzt auf localhost beschränkt.
- **Innere Betriebsnotizen standen in den veröffentlichten Seiten**
  (04.11.2026): Der Impressums-Kommentar verwies auf Impressumsdienste
  und darauf, dass die Seite noch unvollständig sei; im Kinderschutz
  stand ein erledigter „ANPASSEN"-Eintrag. Beides ist über
  `view-source` sichtbar gewesen - jetzt entfernt.

- **Die Website war an zehn Seiten für Suchmaschinen gesperrt**
  (04.11.2026): Auf `daten-loeschen`, `konto-loeschen`, `kinderschutz`
  und `eltern` (je Deutsch und Englisch) stand ein hartes
  `<meta name="robots" content="noindex">`. Die Seiten waren erreichbar,
  aber nicht indexierbar - und die ersten drei sind die URLs, die im
  Play Console bzw. vom Gesetz gefordert sind. Der Anforderung
  „auffindbar auf thestia.de" war damit nicht entsprochen. Jetzt sind
  die Seiten auffindbar, und `noindex` steht nur noch dort, wo es
  richtig ist: im Eltern-Portal (die URL trägt den Token des
  Elternteils) und auf der transienten Bestätigungsseite.
- **16 Seiten hatten kein canonical-Tag:** `thestia.de` und
  `auth.thestia.de` sind ein Netlify-Projekt - dieselben Dateien sind
  unter beiden Hosts erreichbar. Ohne canonical weiß eine Suchmaschine
  nicht, welche Fassung die Originalseite ist. Jetzt zeigt jede
  öffentliche Seite auf ihre kanonische Adresse.
- **Die englischen Seiten verlinkten die deutschen Pflichtseiten**
  (04.11.2026): Sieben englische Seiten zeigten in ihren Fußzeilen
  und Textlinks auf deutsche Texte. Der Sprachumschalter ist dabei
  unverändert - er zeigt absichtlich auf die deutsche Fassung.
- **Der Impressums-Link zeigte auf einen Host, den es nicht gibt**
  (04.11.2026): Der Linktext lautete `kinderschutz.thestia.de`, das
  Ziel war `auth.thestia.de/kinderschutz` - und der Auth-Host ist für
  den Sicherheitscheck da, nicht für die öffentliche Meldestelle.
- **Im Bug-Report waren beliebige Dateien als „Screenshot" möglich**
  (04.11.2026): Geprüft wurde nur die Größe. Jetzt wird jeder Anhang
  an den Magic Bytes geprüft (JPEG/PNG/WebP), und der Dateiname ergibt
  sich aus dem erkannten Typ - der Client kann also auch keine
  Endung mehr bestimmen.
- **Ein gemeldetes Bild musste gar kein Bild sein** (04.11.2026): Die
  Längenprüfung allein ließ jeden Byte-Haufen als Bild durch - er ging
  als `reported_image.jpg` an die Moderation und lief durch den
  NSFW-Scanner, der mit Daten arbeiten musste, die kein Bild sind.
- **Ein PreKey-Bundle durfte beliebig groß und unsinnig sein**
  (04.11.2026): Die Prüfung sah nur nach dem Typ. Jetzt gilt eine
  Whitelist der sieben Felder, die Base64-Felder werden auf Länge und
  Alphabet geprüft, die IDs müssen ganze Zahlen im uint32-Bereich
  sein.
- **Die Verwaltung war über zwei Admin-Konzepte erreichbar**
  (04.11.2026): `admin-ban` prüfte das Secret `ADMIN_UUID`,
  `verification-media` und `verify-account` das Spaltenflag
  `profiles.is_admin`. Zwei Konzepte für dieselbe Frage sind zwei
  Wahrheiten. Jetzt gilt überall das Flag (Migration 175 setzt es für
  das bisherige Adminkonto); das Secret bleibt nur noch eine
  Bauvariable für die Admin-Variante der App.
- **`admin-ban` hatte keine Bremse** (04.11.2026): Ohne Limit konnte
  ein kompromittiertes Admin-Konto die GoTrue-Nutzerliste (25 Seiten à
  200 Nutzer je Anfrage) missbrauchen. Jetzt: 60 Aktionen pro Stunde.
- **Der SSRF-Wächter gab bei DNS-Fehlern nach** (04.11.2026): Der
  Fehlerpfad war fail-open, obwohl der Kommentar das Gegenteil
  behauptete. Eine fehlgeschlagene Auflösung bedeutet, dass der Host
  nicht existiert - jetzt fail-closed.
- **Das Verdachtsflag am Standort ließ sich zurücksetzen**
  (04.11.2026): Ohne Vorposition wurde `is_location_suspicious` auf
  `false` gesetzt - wer seine eigene Zeile löscht, konnte die
  Geschwindigkeitsprüfung zurücksetzen. Das Flag wird jetzt nur noch
  gesetzt, nie gelöscht.
- **Zwei Secret-Namen für dasselbe Geheimnis** (04.11.2026):
  `THESTIA_INTERNAL_SECRET` und `INTERNAL_SECRET`. Bei einer Rotation
  wäre eine Seite stehen geblieben. Jetzt ist `THESTIA_INTERNAL_SECRET`
  der kanonische Name.
- **Eine Edge Function war zerlegt und kam trotzdem ins Repository**
  (04.11.2026): Die bis dahin genutzte Syntaxprüfung
  (`node --experimental-strip-types --check`) meldet sich *nicht* -
  sie meldete auch die kaputte Datei als gültig. Jetzt prüft
  `tool/check_edge_syntax.py` mit esbuild (einem echten
  TypeScript-Parser) alle 24 Dateien, und der Prüfer ist Teil der CI.


- **Passkeys gingen im Release-Build gar nicht** (31.10.2026): `supabase_flutter`
  hängt nur am `passkeys_platform_interface`, NICHT am app-seitigen
  `passkeys`-Paket. Flutter baut ein Endorsed-Plugin (`passkeys_android`)
  aber nur ein, wenn die App selbst vom App-Facing-Paket abhängt. Im
  Release-APK fehlten deshalb **beides**: die Plugin-Klassen und die
  Berechtigung `CREDENTIAL_MANAGER_SET_ORIGIN`. Jeder Passkey-Versuch
  endete mit „MissingPluginException" — unabhängig von Gerät und Server.
  Fix: `passkeys` ist jetzt eine direkte, exakt gepinnte Abhängigkeit;
  ein Test verhindert die Regression.
- **Der Sicherheitscheck wird nur noch verlangt, wenn der Server ihn
  wirklich braucht**: Der Passkey-Zugriff versucht es zuerst ohne Token
  und fragt den Sicherheitscheck erst ab, wenn der Server ein CAPTCHA
  verlangt (vorher kam die Abfrage immer).
- **Passkey-Fehler sagen jetzt, was los ist**: Auch unerwartete Fehler
  laufen durch das Fehler-Mapping und werden konkret benannt, statt
  „fehlgeschlagen" zu melden.
- **Doppelter Scroll-View im eigenen Profil** (31.10.2026, beim Rendern
  gefunden): Beim Umbau auf die flächige Geburtstags-Tönung war
  `SingleChildScrollView` zweimal ineinander geschachtelt. Der innere
  Scroll-View schluckt die Wischgeste - die Seite ließ sich dadurch
  schlechter scrollen.
- **Geburtstags-Chip lief seitlich aus dem Rand**: Der Text war nicht
  umbruchfähig - bei großer Schrift (bis 3,2×) wurde der Chip breiter
  als der Bildschirm (RenderFlex-Overflow). Der Text bricht jetzt um.
- **Transit Spark: der Text verschiebt sich beim Moduswechsel nicht
  mehr**: Flutter zählt den Rahmen der Kachel zum Innenabstand - mit
  dem dickeren Rand der ausgewählten Kachel wanderte der Text um einen
  Pixel. Der Rahmen hat jetzt überall dieselbe Breite.

### Geändert

- **Das Logo im Begrüßungsbild ist größer** (170 statt 120 dp): Es war
  auf einem 360 dp breiten Screen ein kleines Bild, und im
  Store-Screenshot landete es bei nur 193 px — die Wortmarke „Thestia"
  war im Listing nicht mehr zu lesen. Die Quelle ist 941×941 px, es
  wird also nicht hochskaliert.
- **Das Mindestalter ist festgelegt: 16 Jahre** (Betreiberentscheidung
  03.11.2026). Die App ist nicht für unter 16-Jährige gedacht, und das
  wird nicht nur angezeigt, sondern erzwungen: im Registrierungsformular,
  im Datenbank-Constraint (`chk_profiles_birth_date_age`, greift auch bei
  manipuliertem Client) und bei der serverseitigen Altersannahme. Der
  BLE-Nahbereich ist für unter 18-Jährige serverseitig gesperrt.
- **Profil-Menü mit Rand nach oben** (31.10.2026): Der Griff und die drei
  Optionen kleben nicht mehr an der Oberkante des Blattes.
- **Ladekreise sind abgerundet**: Alle Ladeindikatoren der App bekommen
  runde Enden (zentral in der Theme, ohne Änderung an den Stellen selbst).
- **Der Name im Profil bleibt mittig**: Das Verifiziert- und das
  Neu-Konto-Abzeichen stehen daneben, verschieben den Namen aber nicht
  mehr - auch nicht beim fremden Profil.
- **Verifizierung und Mood sind auch bei anderen sichtbar**: Das
  Verifiziert-Abzeichen steht jetzt neben dem Namen in den Listen (erhaltene
  Likes, Funken) und natürlich im Profil - und es verschiebt den Namen
  dabei nicht mehr. Das Mood des Tages war im fremden Profil schon sichtbar
  (jetzt durch einen Test abgesichert).
- **Accessibility der neuen Bildschirme** (31.10.2026, beim Rendern
  gefunden): Der Haupt-Knopf der Sicherheits-Aufklärung lag auf einem
  390×844-Telefon 108 Pixel unterhalb des Bildschirmrands - man musste
  scrollen, um weiterzukommen. Die Aktionen stehen jetzt fest am unteren
  Rand, nur der Text scrollt. Bei 3,2-facher Schrift sprengten außerdem
  der Zeit-Hinweis, das „nicht empfohlen"-Abzeichen und der
  „Kopieren"-Knopf den Bildschirm (RenderFlex-Overflow). Die
  Dock-Beschriftung war auf 16 Pixel Höhe begrenzt und wäre bei großer
  Schrift abgeschnitten worden - sie wächst jetzt mit.
- **Dock:** Alle vier Tabs (Aktuelles, Entdecken, Interessen, Profil)
  zeigen dauerhaft ihre Beschriftung; der aktive Tab ist farblich und
  fett hervorgehoben.
- **Tab-Wischen:** Gebremstes Finger-Following, Widerstand am Rand und
  Feder-Rücklauf machen den Wechsel zwischen den Haupttabs ruhiger.
- **Transit Spark:** Der Funke über dem Zug verwendet dasselbe
  `funkeMitSchleier`-Motiv wie „Find your Spark" und sitzt oben rechts;
  die Zug-Geometrie bleibt unverändert.
- **Interessen:** „Gesendet" und „Erhalten" starten eingeklappt, der
  Funken-Bereich bleibt sichtbar und wird beim Öffnen nach unten
  geschoben. Öffnen/Schließen und der Wechsel zwischen den beiden
  Panels sind animiert; die Funken-Überschrift ist zentriert.
- **Profil-Vorschau und echtes Profil:** Bild und alle übrigen Angaben
  sind zentriert; der Geburtstags-Stil tönt die gesamte Fläche, nicht
  nur den Avatar-Rahmen.
- **Datenschutzerklärung Version 17:** Neuer Abschnitt 3c zu lokalen
  Kontaktdaten und zur Sicherheits-Aufklärung; README und Roadmap
  ergänzt.
- **Neue Tests:** Render-Tests für „Connect to others" und die
  Sicherheits-Aufklärung (kein Absturz, kein Overflow, Schritte
  durchklickbar) sowie für die drei umgebauten Screens (Interessen,
  eigenes Profil, fremdes Profil) inklusive Textgrößen-Prüfung bis 3,2×.
  Dazu Accessibility-Tests für beide neuen Screens und das Dock sowie
  ein Regressionstest, der verhindert, dass der Passkey-Plugin wieder aus
  dem Build verschwindet.

### Nachtrag: Build 33 (06.11.2026) - P2P reparariert und drei Blocker behoben

Der Build 33 enthaelt dieselbe Version (0.10.0) mit einer neuen
Build-Nummer, weil Android ein Update nur installiert, wenn die
Build-Nummer höher ist. Build 32 wurde für den zurueckgenommenen
Stand 0.11.0 verwendet und wird deshalb nicht wiederverwendet.

#### Behoben

- **Das Ende-zu-Ende-Chat war tot** (06.11.2026, live am echten
  Server gemessen): Der Realtime-Client setzt in seiner
  `send()`-Methode `payload['type'] = 'broadcast'`. Die App las aber
  ebenfalls `type` - und der Wert war damit immer `'broadcast'`.
  **Jede** Signaling-Nachricht (Offer, Answer, ICE-Kandidat,
  Relay-Weckmeldung) wurde stillschweigend verworfen, ohne jede
  Fehlermeldung. Live gemessen: gesendet wurde
  `{kind: relay-ping, from: 11111111-…}`, empfangen wurde
  `{event: signal, from: 11111111-…, kind: relay-ping, type: broadcast}`.
  Das Feld der App heisst jetzt `kind` - `type` ist vom
  Realtime-Client reserviert.
- **Der Neuversuch des Handshakes konnte die Verbindung nicht mehr
  reparieren:** Zwischen Offer und Answer lag kein Generationszaehler -
  eine Antwort zu einem alten Angebot kam an und wurde verworfen,
  während der neue Aufbau schon lief. Der Zähler trennt die
  Versuche jetzt sauber.
- **Ein verbrauchter Einmal-Schlüssel wurde wiederbelebt:** Wurde ein
  PreKey zweimal angeboten, uebernahm der zweite Peer ihn erneut.
  Jetzt wird ein verbrauchter Schlüssel wirklich entfernt.
- **Ein fehlendes PreKey-Bundle brach den ganzen Aufbau ab:** Kam vom
  Partner kein Bundle (404), wurde nicht weiter versucht - die anderen
  Schlüssel des Partners wurden nicht mehr probiert.
- **Nach dem Login blieb der Login-Screen mit einer Fehlermeldung
  stehen** (06.11.2026, live im Emulator gefunden): Die Anmeldung war
  erfolgreich (`[AuthNotifier] login erfolgreich`), danach warf die App
  einen `CircularDependencyError`. Ursache: `login()` und
  `loginWithPasskey()` riefen `_ref.invalidate(emailConfirmedProvider)`.
  Der Erzeuger dieses Providers hoert im Konstruktor auf den
  `authProvider` - die Invalidierung läuft also im `authProvider`
  selbst, Riverpod erkennt den Kreis und wirft. Die Invalidierung
  entfällt; ihre Absicht (sofort prüfen statt auf den 3-s-Poller zu
  warten) erreicht der Notifier selbst über seinen eigenen Listener.
- **Die App konnte beim Start in einen Fehlerzustand geraten**
  (06.11.2026, live im Emulator gefunden - Android zeigte "Thestia
  isn't responding"): `app.dart` setzte in `initState` den
  `globalRelayInboxProvider`. Riverpod verbietet Provider-
  Schreibzugriffe im Lebenszyklus ("Tried to modify a provider while
  the widget tree was building"). Die Zuweisung wartet jetzt einen
  Frame (`addPostFrameCallback`).
- **Der Dialog "Chat-Hintergrund" blieb leer und der Chat war damit
  unbrauchbar** (06.11.2026, live im Emulator gefunden): Flutter packt
  den Inhalt eines `AlertDialog` in ein `IntrinsicWidth` und fragt
  damit die intrinsische Breite der Kinder ab. Eine Liste
  (`GridView`/`ListView`) kann die nicht liefern - Flutter wirft "Render
  Viewport does not support returning intrinsic dimensions". Der Picker
  bekommt jetzt eine feste Breite; die Liste scrollt intern. **Wichtig
  für den Test:** Dieser Dialog erscheint beim *ersten* Chat-Besuch -
  wer den Chat nicht aufbekommt, testet das P2P nie.
- **Fünf Stellen mit `setState` nach `dispose`** (06.11.2026,
  systematischer Audit aller 227 Dateien unter `lib/`): Nach einem
  `await` (Serveraufruf, Bildauswahl) wurde `setState` gerufen, ohne den
  `mounted` zu prüfen. Navigiert der Nutzer in dieser Zeit weg, ist das
  im Debug-Build ein Absturz ("setState() called after dispose()"). Der
  Analyzer sieht das nicht - er prueft den BuildContext, nicht den State.

#### Geaendert

- **Die P2P-Diagnose ist auch im Store-Build sichtbar** (06.11.2026):
  Die internen Meldungen des WebRTC-Service gingen nur in den
  Debug-Log. Im Store-Build - dem, in dem der Betreiber testet - war
  deshalb nicht zu sehen, woran der Aufbau scheiterte. Der Service
  meldet seine Probleme jetzt auf einem Stream, und die Diagnosezeile
  im Chat zeigt den letzten Eintrag. Die Texte enthalten keine
  personenbezogenen Daten; Ausnahmen werden nur als Typ genannt.

#### Neu (Pruefwerkzeuge)

- **Vier neue Waechter**, alle in der CI und im lokalen Spiegel
  (`tool/check_local_ci.ps1`): `check_async_setstate.py` (findet
  `setState` nach einem `await` ohne `mounted`-Check), `check_provider_
  in_lifecycle.py` (findet Provider-Schreibzugriffe in `initState` und
  `build`), `check_no_empty_catches.py` und `check_web_pages.py` mit
  Selbsttest. Der erste Wächter fand fünf echte Faelle, der zweite
  einen - beide gegen Negativproben geprüft.

### Nachtrag: Build 34 bis 41 (06./07.11.2026) - vier Befunde vom Betreiber

1. **Der Elternbereich lädt ewig lang.** Der Abruf des Aufsichtsstands
   schlug fehl (keine Sitzung beim App-Start, Netz, Server) - und der
   Bildschirm zeigte für *jeden* Fehler einen endlosen Ladekreis. Der
   Provider wird beim App-Start erzeugt, also bevor die Sitzung sicher
   wiederhergestellt ist; niemand hat je wieder nachgesehen. Jetzt
   unterscheidet der Zustand "lädt" von "gescheitert": es gibt einen
   Grund und einen Knopf ("Erneut versuchen"), der Provider versucht es
   selbst mit wachsender Wartezeit erneut und lädt neu, sobald sich
   jemand anmeldet. Beide Serveraufrufe haben jetzt eine Zeitgrenze.
2. **Die Überschrift im Transit-Blatt lag in der Statusleiste.** Das
   Merkmals-Sheet reicht bis an den oberen Bildschirmrand; jetzt rückt
   der Inhalt unter die Systemleiste (`useSafeArea`).
3. **Mehr Haarfarben**: von 8 auf 14 (dunkelbraun, hellbraun, Kupferrot,
   Platinblond, Silbergrau, Salz und Pfeffer). Die App bietet nur Werte
   an, die der Server kennt - Migration 184 erweitert den Katalog auf
   dem Produktivsystem.
4. **BLE auf Android 16 und 11:**
   - Android 16 zählte über 100 "Thestia-Geräte", obwohl höchstens eines
     in der Nähe war: Die Hersteller-ID 0xFFFF ist die reservierte
     SIG-Nummer und wird von vielen echten Geräten benutzt; die alte
     Prüfung las "irgendwas nach dem Marker" als Token. Ein Token ist
     jetzt **exakt 20 Hexzeichen** - alles andere wird verworfen. Und:
     jedes Token wird nur einmal gemeldet (vorher löste jede
     Advertisement im ~100-ms-Takt einen Bildschirm-Neuaufbau aus).
   - Android 11 fand gar keins: Der BLE-Scan ist auf Android 10/11 nur
     mit der **genauen** Standort-Berechtigung erlaubt, die war per
     `tools:node="remove"` komplett entfernt. Android hat den Scan still
     blockiert. Jetzt ist sie mit `maxSdkVersion="30"` deklariert (auf
     aktuellen Geräten ändert sich nichts - dort reicht
     `BLUETOOTH_SCAN`).
   - Das "Bad request" war der Serverfehler bei leerer Token-Liste. Die
     App sagt jetzt selbst: "Kein Gerät in Reichweite."
   - Die Anzeige zählt jetzt "Thestia-Signale" statt "Thestia-Geräte":
     ein Gerät liefert mehrere Signale, weil sein Token alle 6-14
     Minuten wechselt.

#### Datenschutz und Store

5. **Die Standort-Berechtigung wird nur noch angefragt, wo sie
   technisch nötig ist.** Der BLE-Pfad fragte den Standort auf *jeder*
   Android-Version an - auch dort, wo er nicht gebraucht wird. Ab
   Android 12 reicht `BLUETOOTH_SCAN` mit `neverForLocation`; dort wird
   der Standort für das Radar nicht mehr abgefragt (und der
   Standort-Dienst muss nicht mehr eingeschaltet sein).
6. **Prominente Standort-Offenlegung** (Google Play verlangt sie für
   empfindliche Berechtigungen, wie die App sie für Kamera und Mikrofon
   schon hatte): ein Dialog an allen drei Stellen, an denen die App den
   Standort anfragt - Transit Spark (nur auf Android 11 und älter),
   "Standort erkennen" im Profil und in den Datenschutz-Einstellungen.
   Er erscheint nur, wenn wirklich angefragt wird, und wird einmalig
   bestätigt.
7. **Der Verifizierungs-Standort liegt auf dem 5-km-Raster.** Auf
   Android 11 und älter ist die genaue Standort-Berechtigung Pflicht
   (für den BLE-Scan), und dort gibt es keine Wahl zwischen "ungefähr"
   und "genau" - die Wahl kam erst mit Android 12. Die App hätte damit
   einen exakten Standort bekommen und lokal gespeichert, obwohl sie
   verspricht, den genauen Standort nicht zu speichern. Der
   Verifizierungs-Standort geht jetzt durch dasselbe 5-km-Raster wie
   das Profil. Die Datenschutzerklärung sagt das jetzt ausdrücklich.
8. **Der Zähler im Transit-Radar zählt die frischen Begegnungen**
   (45 Minuten - das Fenster, in dem der Server sie zuordnen kann)
   statt aller zwei Stunden.
9. **Der Generator der Datenschutzerklärung formatiert seine Ausgabe
   jetzt selbst.** Vorher blieb nach einem Lauf die unformatierte Fassung
   stehen - und die CI prüft `dart format --set-exit-if-changed`. Der
   Generator konnte also das Format-Gate brechen, ohne dass etwas
   inhaltlich falsch war.

10. **Die Löschpunkte stehen ganz unten.** In den Einstellungen stand
    "Daten löschen" zwischen "Geräte" und "Datenschutz & Konto" - ein
    zerstörerischer Eintrag mitten in der Liste. Beide Lösch-Wege
    ("Daten löschen", "Konto löschen") stehen jetzt in einem eigenen
    Abschnitt ganz unten, nach "Abmelden", und im Datenschutz-Bereich
    stehen sie zusammen. Der Lösch-Ablauf (MFA-Step-up, Bestätigung,
    Löschung) ist jetzt eine gemeinsame Funktion für beide Bildschirme -
    er existiert nur einmal.

11. **Die Website hat ein Favicon.** In der Google-Suche stand neben
    "Thestia" ein allgemeiner Globus-Knopf statt des Logos - die Seite
    hatte gar kein Favicon. Jetzt gibt es `favicon.png` (192×192),
    `favicon.ico` (16-256) und `favicon.svg` (die Marke), und alle 22
    Seiten verweisen darauf. Der falsche Suchtext war eine Folge der
    `robots.txt`: Die sperrende Fassung galt auch für `thestia.de`, also
    war die Seite nicht auffindbar, und Google zeigte die
    Captcha-Fehlermeldung, die im HTML steht. Der Host-Rewrite (öffentlicher
    Host indexierbar, Auth-Host gesperrt) ist jetzt live.

12. **Der Deployment-Prüfer prüft `robots.txt` am richtigen Host.** Er
    verglich die Datei gegen `auth.thestia.de` - wo absichtlich die
    sperrende Fassung liegt. Er meldete deshalb immer eine Abweichung,
    obwohl alles stimmte. Ein Gate, das immer anschlägt, wird irgendwann
    ignoriert.

13. **Die Nutzungsbedingungen waren nicht erreichbar** - der
    Netlify-Upload war dem Repository hinterher. Sie sind jetzt live (und
    im Sitemap, das die Suchmaschine findet).

14. **Die Release-Abnahme prüft den richtigen Ordner - und das AAB.**
    `tool/check_release_consistency.py` hatte fest auf `releases/v0.9.2`
    gestanden. Die Abnahme von v0.10.0 hätte damit die Dateien von
    v0.9.2 geprüft und "9 Artefakte: ein Build, Versionen ok" gemeldet -
    für Dateien, die zwei Versionen alt waren. Der Ordner folgt jetzt
    der Version aus `pubspec.yaml` (`--dir` überschreibt das).
    Und das **AAB** wird überhaupt geprüft: es ist die Datei, die in
    den Play Store geht, und sie war bis jetzt außerhalb jeder
    Prüfung. Ein AAB aus einem alten Build (etwa versionCode 37) wäre
    beim Upload eine Katastrophe - der Store nimmt die niedrigere
    versionCode nicht an, und der Fehler fällt erst nach dem Upload
    auf. Das Gate liest das Protobuff-Manifest direkt aus dem AAB
    und vergleicht versionCode, versionName und die Berechtigungen mit
    den APKs.

15. **Die Abnahme hätte den richtigen Build abgelehnt.** Auf der
    Verbotsliste stand `ACCESS_FINE_LOCATION` - richtig für v0.9.2,
    falsch für v0.10.0: auf Android 11 und älter verlangt Android für
    den BLE-Scan die genaue Standortberechtigung (Befund vom
    06.11.2026). Die Regel lautet jetzt nicht mehr "darf nicht
    vorkommen", sondern "wenn, dann nur mit `maxSdkVersion=30`".
    Zusätzlich sind jetzt die Berechtigungen verboten, die niemand
    braucht (`ACCESS_BACKGROUND_LOCATION`, `READ_CONTACTS`,
    `READ_CALL_LOG`, `READ_SMS`, `QUERY_ALL_PACKAGES`).

16. **Ein Selbsttest für das Release-Gate.** Der baut ein synthetisches
    AAB und prüft, dass der Leser die Werte findet und dass die
    Regeln anschlagen - inklusive des Negativfalls
    ("`ACCESS_FINE_LOCATION` ohne Obergrenze"). Ein Gate, das man nie
    rot gesehen hat, ist kein Gate.

17. **Die Berechtigungs-Begründungen für das Play-Formular liegen
    fertig vor** (`releases/v0.10.0/PLAY-BEREECHTIGUNGEN.md`): zum
    Kopieren in die Console, je Berechtigung, plus der
    Data-Safety-Eintrag. Alle Angaben sind am Artefakt geprüft
    (`aapt2 dump permissions`, Manifest aus dem AAB) und an der
    Datenschutzerklärung und dem Code belegt. Dabei kam ein Irrtum
    heraus: die **Kamera-Berechtigung ist im fertigen Artefakt
    enthalten** - sie kommt aus dem Manifest des Kamera-Pakets
    (`camera_android_camerax`) und steht deshalb nicht im eigenen
    Manifest, aber Play prüft das fertige Artefakt. Sie muss also im
    Formular mit begründet werden.

18. **Der Store-Text für den aktuellen Build wird geprüft.** Der Store
    zeigt den Änderungstext anhand der VERSION-CODE. Fehlt die Datei
    `changelogs/<versionCode>.txt` in einer der beiden Sprachen,
    erscheint beim Upload kein "Was ist neu". Das war bei jedem
    Versionssprung möglich und wurde bisher nicht gemeldet. Neues Gate:
    `tool/check_store_changelog.py`.

19. **Der Admin-Build war Build 33 - und niemand konnte es sehen.**
    BEFUND (07.11.2026, Betreiber): "Aktuell ist bei Transit Spark bei
    der Aussehen auswahl die Schrift noch immer in der Statusleiste.
    Sind die APKs veraltet?" **Ja.** Der Fix (Befund vom 06.11.) steckte
    im Build 38, aber die Admin-APKs im Release-Ordner waren noch
    Build 33 vom 06.11. 19:00 - also von *vor* dem Fix. Der Betreiber
    hat eine alte Datei getestet.
    Drei Dinge machten das unsichtbar:
    * Beide heißen "v0.10.0" und sehen auf dem Bildschirm gleich aus.
    * Die App zeigte **nirgends** eine Build-Nummer - es gab nichts, was
      man hätte vergleichen können.
    * Das Release-Gate meldete den alten Admin-Build nur als
      **Warnung**, und eine Warnung wird ignoriert.
    Behoben:
    * Die Versionsfußzeile zeigt jetzt die Build-Nummer:
      "Version 0.10.0 (39)".
    * Der Admin-Build bekommt eine eigene Build-Nummer (Basis + 9000,
      z. B. 9039). Er ist damit auf dem Gerät erkennbar und lässt sich
      über dem öffentlichen Build installieren.
    * Das Release-Gate prüft die Build-Nummer der Admin-APK **jetzt als
      Fehler** - und prüft zusätzlich, ob der Admin-Build älter ist als
      der Quellstand (vorher: nur eine Warnung).
    Der eigentliche Fehler - die Überschrift in der Statusleiste - war
    im Code **schon** behoben. Das hier behebt die Ursache des
    Irrtums.

20. **Der Überschrift-Fehler ist jetzt durch einen Test abgesichert.**
    Der Test öffnet die Merkmals-Auswahl über genau den Weg, den die
    App geht (deshalb ist die Funktion `showTransitTagPickerSheet`
    öffentlich) und misst, wo die Überschrift landet: sie muss
    unterhalb der Statusleiste liegen. **Gegenprobe:** ohne den
    `useSafeArea` landet sie bei y=20, die Statusleiste endet bei
    y=28 - genau der gemeldete Fehler. Der Test schlägt also genau
    dann an, wenn der Fehler da ist.

21. **In den Release Notes stand eine falsche Aussage zum Support.**
    Dort stand „v0.9.2 (Build 30) bleibt unterstützt, bis v0.10.0
    veröffentlicht ist". Das ist seit **Migration 156** falsch: das
    serverseitige Mindest-Build-Gate steht auf 31, also bekommt auch
    v0.9.2 bereits beim Start den Update-Hinweis. Richtig ist: ab
    v0.10.0 (Build 31+) wird unterstützt, alles darunter ist End of
    Support. Der Text geht in den Store - eine falsche Angabe dort
    ist ein Versprechen, das die App nicht einlösen kann.
    (README und SUPPORT.md waren schon korrekt; nur die Release Notes
    waren beim Durchgehen der Dokumente noch auf dem alten Stand.)

22. **In den alten Release-Ordnern liegen 16 Admin-APKs mit der alten
    UUID.** Sie tragen die UUID, die laut `docs/ADMIN-UUID.md` als
    kompromittiert gilt, und sie sind von den aktuellen Admin-Builds
    nicht zu unterscheiden – derselbe Fehlgriff wie oben, nur über
    einen anderen Ordner. Das Release-Gate meldet sie jetzt als
    Warnung, mit dem Rat, sie vor einem Admin-Einsatz zu löschen.
    (Die Dateien selbst zu löschen ist Betreiber-Arbeit – sie liegen
    in `releases/`, das ist nicht im Repository.)

23. **Transit Spark: mit genau zwei Geräten war ein Match mathematisch
    unmöglich.** BEFUND (07.11.2026, Betreiber): „Beide Geräte suchen
    eine Person bei Transit Spark (Beide haben gleiche beschreibung
    und beide haben sich gegenseitig blicke getauscht/gefunkt, aber gibt
    keinen Funken.)"

    **Die Ursache** (an den echten Daten des Betreibers belegt): Das
    Signal enthielt die Tokens der *Geräte*, die der Absender gesehen
    hatte – nicht den eigenen Token des Absenders. Gesucht wurde mit
    `s.tokens && v_clean`, also mit derselben Menge:

    ```
    A sendet -> Signal A.tokens = {Token von B}
    B sendet -> Signal B.tokens = {Token von A}
    A sucht  -> {Token von A} && {Token von B} = LEER
    ```

    Zwei Personen sehen nur einander, niemals sich selbst. Ihre
    Token-Mengen sind deshalb disjunkt – die Bedingung konnte nie
    stimmen. Mit drei Geräten wäre es über das gemeinsame dritte Token
    gegangen; deshalb ist der Fehler nie aufgefallen.

    **Die Lösung** (Migration 185): Der eigene Token wird mitgeschickt
    und in einer eigenen Spalte `self_token` gespeichert. Damit lässt
    sich die Frage stellen, die die Sache überhaupt meint: *HAT DER
    ANDERE MICH GESEHEN?* – denn der eigene Token des anderen steht in
    dessen Sichtungsliste, wenn der andere mich gesehen hat. Die
    Bedingung wird symmetrisch:

    ```
    s.self_token = ANY(v_clean)   -- ich habe IHN gesehen
    p_self_token = ANY(s.tokens)   -- ER hat MICH gesehen
    ```

    Das ist genau „Blicke getauscht". Und weil der Match an die
    Identität gebunden ist, kann es nicht mehr passieren, dass zwei
    Personen matchen, die nur dasselbe dritte Gerät gesehen haben.

    **Abgesichert:** Die Migration enthält einen Selbsttest, der den
    Fall des Betreibers nachstellt (zwei Personen, gleiche
    Beschreibung, je ein Token) – und den Falschtreffer (zwei
    Personen mit gemeinsamem drittem Gerät). Der Test läuft in einem
    SAVEPOINT und wird zurückgerollt; bricht er ab, wird die Migration
    nicht ausgerollt – dann fällt der Fehler beim Deployen auf, nicht
    beim Benutzen. Auf der Client-Seite gibt es einen Test, dass der
    eigene Token wirklich mitgeschickt wird und dass ohne ihn gar
    nicht erst gesendet wird (ein Versuch ohne ihn kann keinen Match
    finden und würde den Nutzer mit einem stillen „kein Match"
    im Glauben lassen, es sei niemand in der Nähe).

24. **Ausgefallene Haarfarben** (Migration 186): BEFUND (07.11.2026,
    Betreiber): „Zudem soll bei Haarfarben auch noch sowas wie lila
    usw. sein." Die Palette hat jetzt 18 Werte statt 14 – neu: lila,
    rosa, blau, grün. Sie benutzen die vorhandenen Farb-Slugs (`purple`,
    `pink`, `blue`, `green`); die Farbe selbst ist dieselbe wie in der
    Kleidung, eindeutig bleibt die Angabe durch den Merkmals-Slug
    (`hair_color:purple` ist etwas anderes als `hemd:purple`).

    **Und ein Werkzeug, das die Brücke prüft:** App und Server führen
    dieselben Merkmale zweimal – in `lib/models/transit_models.dart`
    und in `public.transit_tag_catalog`. Die RPC baut ihre Whitelist
    aus der Server-Tabelle; **ein Wert, den der Server nicht kennt,
    wird beim Senden stillschweigend weggefiltert.** Bietet die App eine
    solche Farbe an, sieht der Nutzer keinen Fehler: er wählt sie, sie
    verschwindet, der Funke kommt nie. `tool/check_transit_catalog.py`
    vergleicht deshalb beide Seiten.

25. **Die Chat-Hintergrund-Auswahl muss nicht mehr gescrollt werden.**
    BEFUND (07.11.2026, Betreiber): „Das mit Chat Hintergrund, dass man
    da scrollen muss ist nur so mittel gut bei den Einstellungen." Der
    Picker hatte ein festes `SizedBox(height: 280)` – bei sieben
    Mustern sind das drei Reihen, von denen 280 Pixel nur zwei zeigen.
    Die Höhe wird jetzt aus der Kachelgröße berechnet: so viele Reihen,
    wie Muster da sind, und keine mehr. Auf einem kleinen Bildschirm
    nimmt der Dialog 60 Prozent des Platzes – dort wird gescrollt,
    weil es nicht anders geht.

26. **Die Haarfarben-Auswahl ist ein Raster statt einer Reihe.**
    BEFUND (07.11.2026, Betreiber): „Vielleicht kann man das auch
    schöner als eine Reihe an Farben machen." Bei 18 Haarfarben brach
    eine Wrap-Reihe in mehrere Reihen um, und die Reihen saßen nicht
    auf einer Linie. Die Farben liegen jetzt in einem gleichmäßigen
    Raster, und der Name der gewählten Farbe steht als Text dabei –
    man muss nicht raten, welcher Kreis gerade gewählt ist.

27. **Das Push-Reife-Gate hatte eine Lücke – und einen Absturz.**
    Die Migration 185 hat eine neue Variante von
    `match_proximity_spark` angelegt. Das Gate meldete daraufhin drei
    Befunde:
    * Zwei davon waren **formal falsch**: Das Gate verglich jede
      Migrationsdatei mit *allen* jemals angelegten Signaturen. Eine
      Migration kann aber keine Signatur revoken, die es noch gar nicht
      gibt – Migration 131 und 156 wurden zu Recht gemeldet, obwohl
      ihre Sperre vollständig war.
    * Einer war **echt**: Die neue Funktion (SECURITY DEFINER) war
      **für alle aufrufbar** – auch ohne jedes JWT. Der Postgres-
      DEFAULT-Grant ist „EXECUTE … TO PUBLIC", und `PUBLIC` umfasst
      `anon` mit. Jetzt ist sie wie ihre ältere Schwester gesperrt
      (`REVOKE … FROM PUBLIC, anon`), mit einer Kontrolle, die live
      prüft, dass `anon` sie nicht mehr aufrufen darf und
      `authenticated` sie weiterhin darf.
    * Und das Gate **stürzte ab**, statt zu prüfen: `os` war nicht
      importiert. Das ist die schlimmste Sorte von Fehler – ein Gate,
      das still nichts tut.

    Die Regel lautet jetzt: **jede angelegte Variante muss gesperrt
    sein** – von der Datei selbst oder von einer anderen, und
    **zeitlich** richtig: Migration 123 macht einen Sweep über alle
    Funktionen (er arbeitet über `pg_proc` und erfasst damit den
    Bestand zur Zeit der Migration). Eine Variante, die **vor** dem
    Sweep angelegt wurde, ist also gesperrt – eine, die **danach**
    angelegt wurde, muss die anlegende Migration selbst sperren. Genau
    das ist der Fall der Migration 185.

    Und der Negativfall ist belegt: ohne den REVOKE meldet das Gate
    `match_proximity_spark wird hier angelegt, aber (text[], text[],
    text, text[], text, text) wird NICHT revokt`.

28. **Warum es immer neue Probleme gab – und was dagegen kommt.**
    BEFUND (07.11.2026, Betreiber): „wie es die ganze Zeit neue
    Probleme geben kann, wenn du es immer prüfst. Bitte deck das mit
    tests besser ab oder irgendwie anders sinnvoll."

    Die ehrliche Antwort: **Die Tests prüfen den Code. Sie prüfen
    nicht, ob die ausgelieferte Datei den geprüften Code enthält.**
    Genau da sind beide Fehler passiert:
    * Die Admin-APK im Release-Ordner war Build 33, der Quellstand
      Build 38. Der Betreiber hat sie getestet und einen Fehler gemeldet,
      den es nicht mehr gab.
    * In den alten Release-Ordnern lagen 16 Admin-APKs mit der alten,
      als kompromittiert geltenden UUID.

    Beides sind **Auslieferungsfehler**, keine Codefehler – und gegen
    die kann kein Test der App etwas tun. Neu ist deshalb
    `tool/check_release_version.py`: Es prüft für jedes Artefakt, ob
    die Build-Nummer zum Quellstand passt, ob es nach der letzten
    Quellzeile gebaut wurde und ob der Text des aktuellen Quellstands
    im kompilierten Code steht. Der Negativfall ist belegt: das Gate
    meldet eine falsche Build-Nummer, ein zu altes Artefakt **und**
    einen Build mit altem Code.

29. **Haarlänge und Frisur – mit Werten statt als Merkmal.**
    BEFUND (07.11.2026, Betreiber): „Ja kannst du auch mit aufnehmen,
    also Hairstyle und so."

    Der Server kannte `hair_length` und `hair_style` schon – aber als
    blosse Merkmale waren sie wertlos („hat Haarlaenge?"). Migration
    187 gibt dem Katalog deshalb eine **Werteliste**: neben „slug"
    (Ja/Nein) und „slug:farbe" gibt es jetzt „slug:wert"
    („hair_style:lockig"). Die App bietet 7 Haarlängen und 8 Frisuren
    an, mit Texten in beiden Sprachen.

30. **Zwei Fehler, die der neue Test gefunden hat – und die man beim
    Testen auf dem Gerät nicht gesehen hätte:**
    * **Haarlänge und Frisur schlossen sich aus.** Je Kategorie ist nur
      *ein* Merkmal erlaubt (sonst könnte jemand „Hemd" UND „Bluse"
      wählen). Beide lagen aber in der Kategorie `hair` – man konnte
      also nur eines von beiden angeben. Migration 188 gibt ihnen
      eigene Kategorien.
    * **„Frisur" stand zweimal auf dem Bildschirm:** als Kategorie und
      als Merkmal. Die Kategorie-Überschrift entfällt jetzt bei
      Kategorien mit nur einem Merkmal.

    Und das Redesign, um das der Betreiber gebeten hat („es so schon
    echt voll"): Die **Haare stehen jetzt oben** (vorher ganz hinten –
    der Bildschirm heißt „Wie siehst du gerade aus?"); der
    Kategorie-Filter ist **ein Chip mit Menü** statt eines Bandes aus
    acht Chips; die **Werte stehen direkt unter dem Merkmal**, das sie
    brauchen; und ein **Fortschrittsbalken** zeigt, wie viele Merkmale
    noch fehlen.

31. **Dating Hour: die Partner konnten sich nie finden.**
    BEFUND (07.11.2026, Betreiber): „Bei Dating Hour finden sich die
    Partner nicht (zwei user drin (meine geräte)) und es passiert
    nichts. Es steht, dass die sich suchen, aber finden niemanden."

    **Die Ursache:** Die Paarungsrunde sagte
    `ON CONFLICT (event_id, user_a, user_b) DO NOTHING` – der
    Unique-Index lautet aber `… WHERE (ended_at IS NULL)`. Ein
    **partieller** Index trägt ein `ON CONFLICT`-Ziel nur, wenn die
    Bedingung **genau dieselbe** ist; sonst antwortet der Server mit
    `42P10`. **Die Paarungsrunde konnte also nie eine Sitzung
    anlegen.** Im Cron-Log fällt so etwas nicht auf – der Cron läuft
    alle 30 Minuten, und in der App sieht man nur „sie suchen sich" und
    wartet. (Migration 190.)

    Dazu kam, dass der Cron alle **30** Minuten lief, das Event aber nur
    **60** Minuten dauert: wer in der ersten halben Stunde beitritt,
    bekam keine Runde mehr. Jetzt läuft der Cron alle **5** Minuten,
    und die App löst die Runde **sofort nach dem Beitritt** aus.

    **Nachgewiesen:** Vorher 2 Teilnahmen und 0 Sitzungen, nach der
    Reparatur erzeugt derselbe Aufruf eine Sitzung.

32. **Der Bild-Missbrauchsschutz hat nie gearbeitet.**
    `register_chat_image_hash` schreibt in `public.chat_image_hashes` –
    **die Tabelle gibt es nicht.** Migration 068 hat sie angelegt, ist
    aber beim Anwenden gescheitert; die Historie wurde trotzdem
    fortgeschrieben, und Migration 108 legte die Funktion neu an und
    verwies auf die Tabelle. Damit sah alles fertig aus, aber jede
    Meldung eines Chat-Bildes schlug mit „relation does not exist"
    fehl. Der Bild-Prüfhash aus der Datenschutzerklärung war also
    wirkungslos. (Migration 190 legt die Tabelle nach.)

33. **Der Geburtstag war in der Nacht falsch - für die andere Person.**
    BEFUND (07.11.2026, Betreiber): „Geburtstagsvorschau."

    **Die Ursache (live gemessen):** Der Server rechnet in **UTC**, die
    App rechnet lokal. Zwischen 22:00 UTC und Mitternacht sieht der
    Nutzer **seinen** Geburtstag (Rahmen, Chip) - die andere Person
    aber keinen: der Server rechnet noch den Vortag. Umgekehrt gilt
    es am Vorabend.

    Der Betreiber hat an seinem Geburtstag (07.11.) in der App seinen
    Geburtstagsstil gesehen, bei der anderen Person aber nicht.

    **Jetzt** (Migration 195) rechnet der Server den Geburtstag in der
    **Zeitzone des Betrachtenden** - die kennt die Datenbank bereits
    (`profiles.timezone`). Und die App meldet ihre Zeitzone bei **jedem
    Start** (bisher tat das nur der Elternbereich), weil sie sich mit
    dem Reisen ändert.

    Die gespeicherte Zone wird nur verwendet, wenn sie ein echter
    Zonenname ist - sonst würde ein manipulierter Spaltenwert die
    ganze Profilabfrage scheitern lassen.

34. **Der Transit-Funke hat nie einen Match angelegt - er war unsichtbar.**
    BEFUND (07.11.2026, Betreiber): „Der Funke entsteht, aber es ist
    nichts sichtbar." Und später, nach dem Test auf zwei echten
    Geräten: „Funke wurde angezeigt, ist dann aber wieder verschwunden."

    **Die Ursache (live gelesen, nicht vermutet):** Ein Match entsteht
    ausschließlich durch einen INSERT in `public.matches` - und den
    macht **nur** `create_match_if_mutual`. Der direkte Client-INSERT
    ist seit Migration 040 per RLS gesperrt.

    Transit Spark legte aber **nur Likes** an: `match_proximity_spark`
    (beide Überladungen) und `accept_soft_ping`. Keine der beiden ruft
    `create_match_if_mutual` auf - und kann es auch nicht, sie setzen
    für **beide** Seiten die Likes, ohne dass ein Client-Hook läuft.

    *Die Likes sind für die App unsichtbar:* Die Chatliste liest aus
    `matches`, nicht aus `likes`. Der Funke „entstand" (die Likes waren
    da, der Ping erschien) - aber er erschien nirgends.

    Migration 194 legt den Match jetzt in beiden Funktionen selbst an
    (mit denselben Regeln wie `create_match_if_mutual`, also bleibt es
    bei **einem** Match je Paar) und gibt die `match_id` zurück, damit
    die App direkt in den Chat führen kann.

    *Nachgewiesen live:* Match → Ping in der Liste → „Annehmen" →
    `match_id: 10` → **eine Zeile in `public.matches`** → der Funke ist
    in der Chatliste sichtbar.

35. **„Ausblenden" hat den Funken unwiderruflich gelöscht.**
    Der Knopf löscht die Zeile - ohne Rückfrage. Und er sitzt genau
    dort, wo der Finger schon liegt, wenn die Liste gerade gewachsen
    ist: ein unbedachter Tipp vernichtet den Funken. Jetzt fragt die
    App vorher nach. Und nach dem Annehmen sagt sie, was passiert ist,
    und bietet den Chat an - als Knopf, nicht als Zwang.

36. **Mein Aufräum-Skript hat den Test des Betreibers gelöscht.**
    Der erste Teil des Befunds „Funke wurde angezeigt, ist dann aber
    wieder verschwunden" war **mein Verschulden**: Das Skript, das die
    Testdaten des Live-Nachweises aufräumte, hat pauschal alle Likes
    und Matches zwischen den beiden Testkonten im Zeitfenster gelöscht -
    auch die des Betreibers, der gerade selbst getestet hat.

    Das Werkzeug räumt jetzt **nur** auf, was es selbst angelegt hat
    (Vorher-Nachher-Vergleich), und es **bricht ab**, wenn zwischen den
    Testkonten schon etwas liegt - dann testet der Betreiber gerade,
    und das Werkzeug legt sich nicht dazwischen.


    BEFUND (07.11.2026, Betreiber): „Meine Vorstellung stimmt auch nicht,
    da beide Nutzer eine Vorstellung gemacht haben aber hier steht, dass
    keine hinterlegt wurde (also bei Profil und dann meine Vorstellung)."

    **Die Daten waren da:** beide Testkonten hatten einen Vorstellungstext
    und eine Audio-Datei im Speicher (live geprüft). Der Fehler lag im
    Client: `UserProfile.fromJson` wird aus **drei** Quellen gelesen
    (Server-Antwort, von Hand gebaute Maps, lokaler Cache) - und die
    benutzten **drei** Schreibweisen. Der Parser kannte nur eine.
    Die Vorstellung kam deshalb **nie** an: im Cache nach jedem
    Neustart, beim Serverabruf sofort.

    Beide Parser lesen jetzt **alle** Schreibweisen eines Feldes. Dazu
    kommt der Abgleich mit dem Server beim Start (damit die Vorschau
    zeigt, was andere wirklich sehen) und ein Test mit neun Fällen.

    *Und das Werkzeug, das so etwas findet:*
    `tool/check_profile_cache_keys.py` vergleicht, was `toJson()`
    schreibt, was `fromJson()` liest und was die Server-Zuordnung
    kennt - und meldet jedes Feld, das verloren geht.

37. **Die Vorstellung ließ sich nicht abhören.**
    BEFUND (07.11.2026, Betreiber): „Vorstellung von anderen nicht
    abhörbar. Sie lädt nicht oder braucht seeeeeeehr lange."

    **Die Server-Kette war in Ordnung** (live geprüft: signierte URL,
    HTTP 200, `audio/mp4`, 95 KB, gültige MP4-Datei). Der Fehler lag
    im Abspiel-Widget: `await _player.play()` - just_audio liefert das
    Future **erst fertig, wenn die Aufnahme zu Ende ist**. Die ganze
    Abspielzeit blieb der Lade-Spinner stehen: „lädt nicht oder
    braucht seeeeeeehr lange".

    `play()` wird nicht mehr abgewartet, und das Laden hat ein
    Zeitlimit mit einer verständlichen Meldung statt eines
    endlosen Spinners. Dieselbe Falle gab es an **drei** Stellen
    (Intro-Player, eigene Vorstellung, Sprachnachricht im Chat) - sie
    sind alle behoben.

38. **Der Funke war für die Gegenseite unsichtbar.**
    BEFUND (07.11.2026, Betreiber): „Der Funke entsteht, aber es ist
    nichts sichtbar."

    Die Paarung meldete den Treffer **nur dem Absender**. Für die
    Gegenseite entstand kein sichtbarer Eintrag: kein Soft-Ping, keine
    Meldung. Der Match lag zwar in der Datenbank (die Likes), aber
    ohne Realtime blieb ihre Chatliste alt.

    Die Paarung legt jetzt für die Gegenseite einen **Soft-Ping**
    an - wie bei einem ausdrücklichen „Zuzwinken". Der Eingang des
    Transit-Radars pollt alle 15 Sekunden: der Funke ist damit binnen
    Sekunden sichtbar. *Nachgewiesen live:* Match, dann Ping in der
    Liste, dann „Annehmen", dann steht der Match.

    *Und derselbe Fehler noch an einer zweiten Stelle:* Es gibt **zwei**
    Überladungen der Paarungsfunktion - die aktuelle (mit dem eigenen
    Token) und der Legacy-Stand für ältere Clients. Nur die aktuelle
    legte einen Ping an. Jetzt verhalten sich beide gleich (Migration
    193).

39. **Zwei Funktionen, die der Server nicht ausführen durfte.**
    * **„Entblockieren" ging nie.** Der Aufruf antwortete mit
      `403 permission denied for function unblock_user`: Die Funktion
      existiert, aber die Rolle `authenticated` hatte **kein**
      Ausführungsrecht. Bei der Rechte-Widerruf-Migration (123) war
      sie vergessen worden - ihre Schwester `block_user` hatte das
      Recht, `unblock_user` nicht. Die Liste war da, das Entblockieren
      nicht.
    * **„Annehmen" ging nie.** Dieselbe Lücke bei `accept_soft_ping`:
      Der Empfänger sah den Funken und beim Tippen auf „Annehmen"
      passierte nichts.

    *Beide Rechte sind nachgezogen (Migration 192), live geprüft.*

    *Und das Werkzeug, das beides findet:*
    `tool/check_function_grants.py` sammelt **alle** RPC-Aufrufe des
    Clients (Dart und Edge Functions) und fragt die Produktivdatenbank,
    welche Rechte die Rollen wirklich haben. Es meldet jede aufgerufene
    Funktion, die der Server nicht ausführen kann.

40. **Der Zufallschat verlor Nachrichten.**
    BEFUND (07.11.2026, Betreiber): Zufallschat ohne Nachrichten.

    The Zufallschat sendete **ausschließlich** über den P2P-Kanal.
    Der Relay-Fallback gab es nur, wenn der Bildschirm schon im
    Relay-Modus war - der wird aber erst eingeschaltet, wenn ICE
    **definitiv** gescheitert ist. In der Zeit davor (der Handshake
    dauert, und ohne TURN kommt er oft nicht zustande) landete die
    Nachricht in der Outbox: der Absender sah sein Echo, der Partner
    nichts.

    Der Zufallschat hat jetzt denselben Dreistufen-Weg wie der normale
    Chat: P2P, dann E2E-Relay, dann Outbox.

41. **Bedienung: Profilbild, Geburtstag, Wartebereich, Bestätigung.**
    * **Doppeltes Profilbild** (Fremdprofil): Unter dem echten Bild
      stand ein Verlaufsblock mit Personen-Icon - der las sich wie ein
      zweites, kaputtes Bild. Der Block ist weg; die Bilder (Hauptbild
      plus die weiteren Fotos) zeigt der Avatar-Baustein.
    * **Profilvorschau = was andere sehen:** Die Vorschau zeichnete
      einen Kreis, das echte Profil ein abgerundetes Rechteck. Beide
      benutzen jetzt **denselben** Baustein (`ProfileAvatarBox`) - sie
      können nicht mehr auseinanderlaufen.
    * **Dating-Hour-Wartebereich mit Theme-Farbe:** Der Wartezustand
      war fest grau. Jetzt kommt die Farbe aus dem gewählten Theme.
    * **Kein Chat-Erzwang (mit Abfrage):** Nach der Paarung im
      Dating Hour kommt jetzt eine Rückfrage (reinschauen oder später),
      statt den Chat aufzudrängen.
    * **Heart-Bestätigung schneller:** Die Funke-Animation blockierte
      den Bildschirm 1,9 Sekunden und war nicht abbrechbar. Jetzt 1,1
      Sekunden - und ein Tippen schließt sie sofort.
    * **Dauer der Sprachnachricht:** Kam keine Dauer mit, stand dort
      „0:00", obwohl die Datei eine echte Länge hat. Die Länge wird
      jetzt beim Laden aus der Datei gelesen.

42. **Der CI hat einen Fehler von mir gefunden - und das ist der Punkt.**
    Beim neuen Test für den gemeinsamen Profilbild-Baustein fehlte ein
    `const`. Der Analyzer meldete das **lokal nicht** (der Test war nach
    dem letzten Analyzer-Lauf entstanden), der CI aber sofort:
    `prefer_const_constructors` in `analyze-and-test`.

    Das ist genau die Antwort auf die Frage, warum es immer neue
    Probleme gab: **ein Test prüft den Quelltext, der CI prüft den
    Quelltext bei jedem Commit, und die Werkzeuge prüfen den Server und
    die ausgelieferte Datei.** Ein Fehler, den man beim Testen auf dem
    Gerät nicht sieht, fällt spätestens beim CI auf - wenn man die
    Kette laufen lässt.

    *Und die Regel daraus: Bevor gepusht wird, laufen Analyzer und
    Tests. Der CI ist die letzte Instanz, keine erste.*

### Nachtrag: Build 42 bis 46 (07./08.11.2026) - die zweite Befundrunde und die Verifikation

43. **Das Relay hat nie funktioniert - Nachrichten kamen nicht an.**
    BEFUND (07.11.2026, Betreiber): „Nachrichten kommen noch immer
    nicht an."

    **Die Ursache (live gemessen):** Der Aufruf von `relay_store`
    antwortete mit `HTTP 400 - query has no destination for result
    data`. Die Funktion endete mit:

        INSERT INTO public.direct_message_relay ...
        RETURNING id;
      END;

    In PL/pgSQL ist ein blosses `RETURNING id;` **kein RETURN** - es ist
    nur ein SQL-Befehl, dessen Ergebnis verworfen wird. Die Funktion
    lief ins Ende, ohne einen Wert zu liefern.

    **Das heisst: das Relay hat nie funktioniert.** Jede Nachricht,
    die über den Relay-Weg ging - also genau dann, wenn der Direktkanal
    nicht steht (im Mobilfunk, hinter einem Router oder ohne TURN) -
    wurde verworfen. Der Empfänger sah nichts. (Migration 196.)

44. **Wenn beide sich liken, entsteht jetzt ein Funke.**
    BEFUND (07.11.2026, Betreiber): „Wenn beide sich liken entsteht kein
    Funke."

    `like_user` legte nur einen **offenen** Like an. Der Match entstand
    nur, wenn die Gegenseite den Like von Hand annahm - ein
    beidseitiger Like hatte aber nichts zu entscheiden. Der Weg, der
    auf dem Server schon bereitliegt (`create_match_if_mutual`), wird
    von der App nirgends benutzt. (Migration 197.)

    Und: **„Man kann nicht von einer Person einen Like haben, mit der
    man schon einen Funken hat."** Bei einem bestehenden Funke tat
    `like_user` nichts - der Like wurde **stillschweigend geschluckt**.
    Jetzt gibt die Funktion das Ergebnis zurück, und die App sagt es.

45. **Das Auge mit dem Strich blendet jetzt aus, statt abzulehnen.**
    BEFUND (07.11.2026, Betreiber): „Das Auge mit dem Strich ist like
    abgelehnt, aber man würde eher sowas wie ausblenden oder ignorieren
    darunter verstehen."

    Die Schaltfläche war mit „Ignorieren" beschriftet, rief aber das
    **Ablehnen** auf - die andere Person sah die Ablehnung. Jetzt
    blendet sie nur aus (`ignore_like`, Migration 198): der Like
    verschwindet aus der Liste, die Gegenseite erfährt nichts.

46. **Der Chat-Hintergrund verschwindet nicht mehr.**
    BEFUND (07.11.2026, Betreiber): „Der Hintergrund, den man auswählt,
    wird nicht gespeichert."

    Das Schreiben in den Keystore kann scheitern (bei gleichzeitigem
    Zugriff). Der Fehler wurde nur protokolliert: die Oberfläche zeigte
    den neuen Hintergrund trotzdem an - beim nächsten Start war er weg.
    Jetzt wird dreimal versucht (mit kurzer Pause) und, wenn es nicht
    klappt, **gemeldet** statt still zu scheitern.

47. **Die Markierung der gewählten Farbe wird nicht mehr abgeschnitten.**
    BEFUND (07.11.2026, Betreiber): „Wenn man eine Farbe auswählt, welche
    am Rand ist, ist die Markierung, dass man diese Farbe ausgewählt
    hat, etwas abgeschnitten."

    Die Markierung war ein Schatten, der **nach außen** über die Kachel
    ragte - am Rand des Rasters wurde er abgeschnitten. Jetzt ist sie
    ein Rahmen **innerhalb** der Kachel.

48. **Beim Wechsel vom Transit Spark in den Chat wird gefragt.**
    BEFUND (07.11.2026, Betreiber): „Wenn man von Transit Spark in
    einen Chat geht, soll auch wenn Transit Spark noch an ist gefragt
    werden, ob es an bleiben soll."

    Dieselbe Frage wie beim Verlassen des Radar-Bildschirms: weiterlaufen
    lassen oder stoppen? Das Radar sendet sonst im Hintergrund weiter,
    ohne dass der Nutzer das entschieden hat.

49. **Ein Werkzeug gegen die stille Relay-Klasse.**
    `tool/check_function_returns.py` findet Funktionen, die einen Wert
    zurückgeben **sollten**, aber kein `RETURN` haben - der Aufruf
    scheitert dann mit „query has no destination for result data", ohne
    dass irgendwo ein Fehler sichtbar wird. Der Selbsttest (eine
    absichtlich kaputte Funktion) beweist, dass der Prüfer sie findet.

50. **Ein Werkzeug, das die stummen Fehler findet.**
    `tool/check_on_conflict.py` fragt die Produktivdatenbank ab und
    vergleicht **jedes** `ON CONFLICT`-Ziel mit den tatsächlichen
    Indizes. Es hat beide Fehler gefunden (Befunde 31 und 32) – und
    es findet alle 26 Funktionen mit `ON CONFLICT` auf einmal.
    Dazu `tool/check_migration_history.py` (jede Migration aus dem
    Repository ist auch angewandt) und
    `tool/check_release_version.py` (die ausgelieferten Artefakte
    tragen den aktuellen Code).

51. **Die Verschlüsselung ist belegt - und mein Verdacht war falsch.**
     FRAGE DES BETREIBERS (08.11.2026): „Bist du dir jetzt sicher, dass
     der Chat und alle Modi reibungslos laufen?"

     Die ehrliche Antwort war: **nein**. Zwei Dinge waren unbelegt -
     und das eine davon war ein echter Fehler in meiner Prüfung: Der
     erste Live-Nachweis hat eine **Nutzlast abgelegt, die keine war**
     (base64 von „Hallo"). Damit war die Server-Kette belegt, aber
     **nicht die Krypto**. Wenn die Krypto kaputt wäre, kaemen die
     Nachrichten weiterhin nicht an - und genau das war die gemeldete
     Symptom.

     Drei Nachweise schliessen die Luecke jetzt:

     - `test/signal_first_message_test.dart` beweist an den echten
       Bausteinen der Bibliothek: die **erste** Nachricht traegt den
       PreKey und lässt sich **ohne vorhandene Sitzung**
       entschluesseln. Damit ist belegt, dass eine unbekannte Person
       die erste Nachricht überhaupt lesen kann.
     - `test/live_prekey_bundle_test.dart` holt das **echte** Bundle
       eines echten Kontos vom Server und prueft die Signatur des
       Signed Pre Keys gegen die Identity-Key. Passt die nicht, kann
       die App keine Sitzung aufbauen und damit **keine** Nachricht
       verschluesseln - ohne dass irgendwo ein Fehler sichtbar wird.
     - Beide Tests sind live gelaufen und gruen.

     **Die wichtigste Lehre daraus:** Mein Verdacht, die Krypto sei
     kaputt, war **falsch**. Der Test hat es widerlegt, **bevor** die
     App angefasst wurde. Genau dafür ist der Test da - ein
     Verdacht, der aus einem Test kommt, ist eine Vermutung; ein
     Verdacht, der durch einen Test widerlegt ist, ist eine Tatsache.

52. **Der komplette Weg läuft jetzt in einem einzigen Test.**
     `test/live_message_flow_test.dart` macht den ganzen Weg in einem
     Lauf: beide Konten liken sich -> es entsteht ein **Funke**
     (bzw. ein Match) -> das PreKey-Bundle wird geholt -> die Sitzung
     wird gebaut -> die Nachricht wird **verschlüsselt** -> im Relay
     abgelegt -> vom Empfänger abgeholt.

     Live geprüft: alles gruen. Und die Nutzlast, die im Relay
     landet, enthaelt den Klartext **nicht** - sie ist verschlüsselt.

     Das entschluesseln selbst passiert dort bewusst **nicht**: es
     braucht den privaten PreKey des Empfaengers, und der liegt nur auf
     dem Gerät, das ihn erzeugt hat (der Server kennt nur den
     oeffentlichen Teil). Die Krypto ist stattdessen in den beiden
     Tests oben belegt - zusammen ergibt das die vollstaendige Kette.

     Der PreKey-Endpunkt gibt das Bundle eines Partners nur heraus,
     wenn zwischen beiden eine **Beziehung** besteht (Match oder
     Transit-Signal); sonst antwortet er mit 404 „nicht verfuegbar".
     Das ist richtig so - ohne Beziehung bekommt niemand die
     Schlüssel eines Fremden. Die Live-Tests bauen die Beziehung
     deshalb vorher auf und prüfen dabei gleich, ob der beidseitige
     Like wirklich einen Match ergibt (Befund 44).

56. **Build 48: das SDK ist aktualisiert - die letzte Luecke ist zu.**
     Das Dart-/Flutter-SDK stand auf **3.44.6 / Dart 3.12.2** und war
     damit vom Advisory GHSA-frr6-h895-5pxp (High) betroffen. Jetzt läuft
     der Build auf **Flutter 3.47.9 / Dart 3.13.7** (das aktuelle Stable
     mit dem Fix). Die CI pinnt die Version jetzt fest, und
     `tool/check_sdk_security.py` ist **blockierend** im CI: ein
     Rueckfall auf eine alte Version wird rot, statt stillschweigend zu
     passieren.

     **Warum das erst jetzt wirkt:** Der Fix steckt in der Binary - ein
     SDK-Update allein genuegt nicht. Erst der neue Build traegt ihn auf
     die Geräte. Wer noch Build 47 (oder aelter) installiert hat,
     benutzt weiterhin den alten Trust-Store; die App weist ihn im
     Startbildschirm darauf hin (Mindestversions-Gate).

     **Der Formatter hat sich mit Dart 3.13 minimal geaendert** (zwei
     Dateien wurden angepasst) - kein Grund, den Sprung zu verschieben.

     **Eine Ueberraschung, die das Update mitgebracht hat:** Mit dem
     neuen SDK hat sich `path_provider_android` auf 2.3.1 aufgeloest,
     das über `jni_flutter` an das Paket `jni` haengt. Der
     Release-Build brach daraufhin ab: „Missing class
     org.jni_zero.JniZeroJni" - R8 findet die zur Build-Zeit erzeugten
     Java-Klassen des JNI-Pakets nicht im Klassenpfad. Der Dart-Code
     nutzt `jni` gar nicht, es ist rein transitiv. Behoben mit der vom
     Android-Gradle-Plugin selbst erzeugten Regel
     (`-dontwarn org.jni_zero.JniZeroJni`) in
     `android/app/proguard-rules.pro`.

     **Die Lehre daraus:** Ein SDK-Update ändert nicht nur die
     Formatierung, sondern löst die Abhaengigkeiten neu auf. Das ist
     der Grund, warum ein Update nie „nur ein Update" ist - es gehoert
     immer mit einem vollstaendigen Release-Durchlauf zusammen.

58. **Zwei Sicherheitsmechanismen waren stumm - jetzt sind sie an.**
     BEFUND (08.11.2026, Betreiber): „kannst du das update machen?"
     (das Mindestversions-Gate). Beim Setzen des Gates fand sich:
     **Das Gate hat noch nie funktioniert.**

     Die App liest `app_config` direkt über PostgREST
     (`lib/services/app_config_service.dart`). Die Policy aus Migration
     034 („No direct app_config access") hat aber `USING (false)` für
     die Rolle `authenticated` - der Client bekam also IMMER eine
     leere Liste. Live geprüft: HTTP 200 mit `[]`.

     **Damit waren zwei Mechanismen stumm:**
     - `min_app_version_build`: der Update-Hinweis beim Start für zu
       alte Clients erschien **nie**. Der Wert wurde gesetzt (9, 29, 30
       - jetzt 48), war aber unerreichbar. Alte Builds liefen weiter -
       und deren Zertifikatspruefung akzeptiert die gesperrten
       Zwischenzertifikate noch (Advisory GHSA-frr6-h895-5pxp, High).
     - `transit_spark_enabled`: die **Notbremse** für Transit Spark -
       der Schalter, mit dem der Betreiber das Feature abschalten
       kann, wenn der BLE-Geraetetest nicht besteht - war ebenfalls
       stumm. Der Code behandelt den Wert als „fail-open" (Feature
       an), also hat der Schalter nichts bewirkt.

     **Behoben (Migration 202):** Genau die zwei Werte, die die App
     ausdruecklich abfragt, sind jetzt für angemeldete Clients lesbar.
     Die interne Konfiguration (AAL2-Pflicht,
     E-Mail-Bestaetigungspflicht, Aufbewahrungsfristen, Quiz-Abklingzeit)
     bleibt gesperrt.

     **Warum der Entwurf trotzdem richtig war:** Der Entwurf war
     richtig - `app_config` ist eine interne Konfiguration und soll
     nicht wholesale lesbar sein. Aber die beiden Werte, die die App
     braucht, müssen es sein.

     **Und warum es nicht auffiel:** Beide Aufrufe behandeln einen
     fehlenden Wert als „fail-open" - kein Update-Hinweis, Feature an.
     Weder am Bildschirm noch im Log war zu sehen, dass die Schalter
     nicht ankommen. Genau die Fehlerklasse, die sich in den letzten
     Wochen wiederholt hat.

     **Das Werkzeug dagegen:** `tool/check_app_config_readable.py`
     fragt live genau so ab, wie es die App tut (mit einem echten
     Benutzer-Token) und schlaegt an, wenn ein benoetigter Wert fehlt
     ODER ein interner Wert lesbar ist. Ohne die Schlüssel sagt es
     SKIP, damit der CI nicht rot wird.

     **Und das Mindestversions-Gate selbst (Migration 201) steht jetzt
     auf 48** - mit dem Fail-Fast-Beweis, dass der Wert wirklich
     gesetzt ist.

57. **Sicherheitspruefung gegen bekannte Schwachstellen (08.11.2026).**
     BEFUND (Betreiber): „Check im Internet einmal, ob es bestimmte
     Sicherheitsluecken gibt, die Thestia haben könnte und pruef die App
     dann darauf."

     **Die Methode:** Alle 274 Pakete aus `pubspec.lock` wurden gegen die
     OSV-Datenbank (Google) und die GitHub Advisory Database abgefragt,
     dazu der WebRTC-SDK, die Flutter-Engine (Skia, libpng), der
     Dart-SDK, die GitHub Actions und die Maven-Abhaengigkeiten des
     Android-Builds. Jede gefundene Luecke wurde gegen den eigenen Code
     geprüft.

     **Das Ergebnis:** Kein einziges der 274 Pakete ist von einer
     bekannten Advisory betroffen. Zwei Luecken waren es - der
     **Flutter-/Dart-SDK** und der **WebRTC-SDK im lokalen Fork**.

     **Luecke 1 (High): der Dart-/Flutter-SDK ist zu alt.**
     Advisory GHSA-frr6-h895-5pxp (23.10.2026): Im Oktober 2026 wurden
     die privaten Schlüssel von acht Zwischenzertifikaten der CA
     *eMudhra* oeffentlich als kompromittiert gemeldet. Wer sie hat,
     kann gueltige TLS-Zertifikate für beliebige Domains FAELSCHEN.
     `dart:io` prueft auf Android mit einem EINGEBAUTEN BoringSSL und
     liest die Sperrliste des Betriebssystems NICHT - ein Angreifer im
     Netzpfad kann also ein gefaelschtes Zertifikat für `*.supabase.co`
     vortaeuschen. Betroffen: Flutter < 3.47.8 / Dart < 3.13.7.
     Thestia hatte **3.44.6 / 3.12.2** - also **betroffen**.
     (iOS, macOS und Web sind nicht betroffen.)

     **Die App-Prüfung:** Drei Datenpfade liefen ungeschuetzt:
     Supabase **Realtime** (WebSocket), die Passkey-Registrierung und
     der Storage-URL-Download. Sie gingen über den System-Root-Store -
     und Dart ruft den Pin-Callback nur auf, wenn die System-Validierung
     FEHLGESCHLAGEN ist. Ein vom System akzeptiertes Zertifikat
     umging das Pinning also vollstaendig.

     **Behoben (wirkt sofort, ohne SDK-Update):**
     - Der Realtime-WebSocket bekommt einen eigenen Transport mit dem
       **gepinnten** Client (`lib/utils/pinned_realtime_transport.dart`).
       Über diesen Kanal laufen Chat-Events, Transit-Signaling und
       die Soft-Pings.
     - Passkey und Storage nutzen den `IOClient` mit dem strikten
       Pinning-Client (leerer Root-Store, fail-closed).
     - Supabase REST und das WebRTC-Signaling waren bereits über den
       strikten Client gepinnt. Play Integrity und FCM laufen nativ
       und nutzen den Trust-Store des Betriebssystems (geschuetzt).

     **Luecke 2 (Medium): der WebRTC-SDK im lokalen Fork.**
     `flutter_webrtc` ist in Thestia kein Pub-Paket, sondern ein Fork
     (`third_party/flutter_webrtc`). Er zog den nativen WebRTC-SDK aus
     Maven: `io.github.webrtc-sdk:android:144.7559.09` - und der
     enthaelt die kompromittierte eMudhra-CA noch in seiner eigenen
     CA-Liste. **Behoben:** Die Version ist jetzt `150.7871.04` - exakt
     die Version, die der Upstream-1.6.3 verwendet („drop compromised
     eMudhra CA root"). Der Build läuft durch.

     **Luecke 3 (Mittel): die Flutter-Engine (Skia, libpng).** Beides
     hatte 2026 Luecken, die nur ein SDK-Update behebt. Das Risiko ist
     gering, weil die App keine fremden Webseiten rendert - aber es ist
     nicht null.

     **Noch offen: das SDK-Update** auf Flutter 3.47.9 / Dart 3.13.7
     (das aktuelle Stable mit dem Fix). Es ist die Ursachenbehebung und
     behebt auch die Engine-Luecken - aber es steckt erst in der
     Binary, also sind danach ein Neubau und eine erneute Verteilung
     noetig. `tool/check_sdk_security.py` prueft die Untergrenzen (SDK
     in der CI, lokal installierte Version, WebRTC-SDK) und macht den
     offenen Punkt sichtbar, statt ihn zu uebergehen.

     **Geprüft und NICHT betroffen:** Guava (Build-Abhaengigkeit, nicht
     im APK), die Firebase-Plugins (kein Firestore, FCM läuft nativ),
     `actions/download-artifact` (wird nicht verwendet), `dio_http2_adapter`
     und `jose` (nicht verwendet), der Pub-Entpack-CVE (Dart zu neu),
     `libwebrtc` (Video-Leak - Thestia nutzt WebRTC nur für Text) und
     `onnxruntime` (Modell kommt aus dem Asset und ist SHA-256-geprüft).
     **Und der Server:** Das Produktivsystem läuft auf **PostgreSQL
     17.6**; die 17er-Linie ist bei **17.11**. Dazwischen liegen 39
     CVEs, 25 davon mit CVSS ab 7.0. Geprüft wurde jede einzelne gegen
     die App: `pgcrypto` ist installiert, aber die CVE liegt in der
     PGP-**Entschlüsselung** (die App nutzt `crypt()` für die PIN, und
     das `extensions`-Schema ist für den Client nicht exponiert);
     `regexp` ist über den Transit-Notiztext erreichbar, aber der Text
     wird auf 140 Zeichen gekuerzt; `intarray`, `spi` und `pg_trgm` sind
     nicht installiert; `oidvector` liegt in `pg_catalog` und nicht im
     exponierten `public`-Schema. **Kein betroffener Pfad ist von der
     App aus erreichbar.** Die PostgreSQL-Version gehoert trotzdem zur
     Supabase-Plattform und lässt sich aus dem Repository heraus nicht
     ändern - das Update muss der Betreiber im Supabase-Dashboard
     anstossen.

     **Das Update wurde am 08.11.2026 durchgefuehrt.** Die Plattform
     hatte es freigegeben (17.6.1.147 -> 17.11.0.018, ohne
     Validierungsfehler und ohne Warnungen). Der Wechsel dauerte rund
     fünf Minuten.

     **Das Backup, das davor lag** (für diesen Plan gab es weder einen
     PITR-Restore-Punkt noch ein Plattform-Backup - beides ist ein
     Pro-Feature):
     `releases/backup-db-2026-11-08/pg-dump-data.sql` (275 Zeilen in 41
     Tabellen, mit Header und `COMMIT`) und dieselben Daten als JSON.
     **Die Wiederherstellung wurde getestet**, nicht nur behauptet: Der
     Import lief in einer Transaktion, die Zeilenzahlen stimmten exakt,
     und nach dem Rollback war der Datenbestand unveraendert. Das
     Schema steht weiterhin in den Migrationen des Repositorys - die
     Datei enthaelt nur die Daten.

     Das vollstaendige Audit mit Quellen liegt in
     `docs/SICHERHEITSPRUEFUNG-2026-11-08.md`.

54. **Keine doppelten Benachrichtigungen für das Selbe.**
     BEFUND (08.11.2026, Betreiber): „Keine doppelten Benachrichtigungen
     für das Selbe."

     **Die Ursache (live gemessen, nicht vermutet):** Der Like-Versand
     lief **zweimal**. Einmal über den DB-Trigger
     (`notify_push_trigger`) und einmal über einen Aufruf der App
     (`notify-user` mit `kind='likes'`). Dazu kam der Transit-Weg: der
     legt für EINEN Funke drei Zeilen an - zwei technische Likes, ein
     Match und einen Soft-Ping - und erzeugte damit **vier** Push-
     Aufrufe. Beide Seiten bekamen je **zwei** Meldungen für ein
     Ereignis, und die Like-Meldung war inhaltlich falsch: im Radar
     wird kein Profil geliked, sondern gefunkt.

     **Das Werkzeug, das zählt:** `tool/measure_push_duplicates.sql`
     zählt die Push-Aufrufe, ohne dass eine einzige Nachricht rausgeht
     (Transaktion plus ROLLBACK - der pg_net-Worker sieht uncommittete
     Zeilen einer anderen Sitzung nicht). `tool/check_push_duplicates.py`
     macht daraus ein Gate: statisch (kein Client darf `notify-user` mit
     `kind='likes'` aufrufen, und die Edge Function muss solche Aufrufe
     ablehnen) und live (die vier Szenarien).

     **Die Regel ab jetzt: ein Ereignis, eine Meldung.**

     - Ein technischer Transit-Like (kein Profil-Like) erzeugt **keine**
       Meldung. Er ist über `likes.source = 'transit'` markiert.
     - Ein Like, aus dem ein Funke wird, erzeugt **nur** die
       Funke-Meldung. Der Match entsteht darum **vor** dem Like-Insert
       (`like_user`, `create_match_if_mutual`).
     - Ein Soft-Ping, zu dem es schon einen Funke gibt, erzeugt **keine**
       Meldung. Der Ping bleibt - er macht den Funke im Radar sichtbar.
     - `notify-user` lehnt Like-Pushes von **Clients** ab (HTTP 400,
       `kind_server_only`). Der Like-Versand ist Sache des Servers.

     **Live gemessen nach der Reparatur:**

     | Ereignis | vorher | jetzt |
     |---|---|---|
     | Transit-Funke (beide Seiten) | 4 (je 2 pro Seite) | **2** (je 1 pro Seite) |
     | einseitiger Profil-Like | 2 | **1** |
     | gegenseitiger Like | 4 | **2** (der Match) + 0 (der zweite Like) |
     | manueller „Zuzwinken" | 0 | **1** |

     **Ein Fund, der dabei auffiel:** `notify_soft_ping_trigger` war
     seit der Secret-Umbenennung (Migration 146) **tot** - es suchte
     `wisp_internal_secret` (gibt es nicht mehr) und schickte den
     alten Header `x-wisp-internal`. Der manuelle „Zuzwinken" hat
     darum seit dem 06.11.2026 **keine** Meldung mehr erzeugt. Beides
     ist mit repariert.

     **Die Formulierung der Like-Meldung hat sich vereinheitlicht:**
     Der Trigger schickte bisher „Du hast ein neues Like! / Jemand hat
     dein Profil geliked.", der Client-Pfad „Jemand hat deine
     Vorstellung entdeckt.". Welcher Weg der Push genommen hat, war
     damit am Text erkennbar - und die App rief den Client-Pfad
     zusätzlich auf. Jetzt gilt für jeden Profil-Like derselbe Text:
     „Jemand hat deine Vorstellung entdeckt."

53. **Was damit nicht belegt ist - und was aufgeraeumt wird.**
     Die Live-Tests legen echte Zeilen an (zwei Likes, ein Match).
     `tool/cleanup_transit_testdata.sql` nimmt sie wieder weg und
     prueft danach, dass nichts mehr da ist; die Konten selbst bleiben
     unberuehrt.

     **Ehrlich benannt** (ausführlich in `releases/v0.10.0/
     TESTANLEITUNG.md`, Abschnitt 7):

     - Der **P2P-Direktkanal** (Offer -> Answer -> ICE) ist auf zwei
       echten Geräten **nie** durchgelaufen. Er braucht die beiden
       Handys nebeneinander.
     - **Ohne TURN** kein P2P hinter CGNAT. Der Weg über den Server
       funktioniert, ist aber langsamer.
     - **Bild- und Sprachnachrichten** sind nicht Ende-zu-Ende
       geprüft (sie nehmen einen anderen Weg als der Nachrichtentext).
     - Der **Login auf dem Emulator** scheitert am CAPTCHA. Die
       Bildschirmablaeufe (Radar-Dialoge, Dating-Hour, Audio-Player,
       Profilvorschau) sind deshalb über **Widget-Tests** belegt, nicht
       über eine Sitzung auf einem Gerät.


59. **Die Passkey-Verknuepfung war kaputt - und niemand konnte es sehen.**
     BEFUND (08.11.2026, bei der Vorbereitung des Hosterwechsels):
     Die Datei `assetlinks.json` nennt die Fingerabdruecke, gegen die
     Android die **Zertifikatskette des Webservers** prueft. Live
     gemessen: die Kette von `thestia.de` hat fünf Zertifikate, und
     **keiner** der drei eingetragenen Fingerabdruecke stand darin.

     Das alte Gate hat das nicht gesehen: `check_passkey_assetlinks.py`
     verglich die LIVE-Datei nur mit der LOKALEN Datei ("3 Zertifikate
     identisch") - die echte TLS-Kette pruefte niemand. Ein
     veralteter Deploy fiel damit nicht auf, obwohl die
     Passkey-Anmeldung auf Android daran haengt.

     **Dazu kam ein zweiter Grund, warum die Datei nicht altern konnte:**
     Das Leaf-Zertifikat wird alle 90 Tage erneuert (Let's Encrypt).
     Steht nur das Leaf in der Liste, ist sie danach ungueltig. Die
     Datei enthaelt deshalb jetzt die **stabilen** Glieder der Kette
     (Root und Zwischenzertifikate) - plus die beiden App-Keys (Debug
     und Release, `CN=Thestia`), denn die gehoeren zur App und nie zum
     Webserver.

     **Das Gate prueft jetzt die Kette** und meldet, wenn ein stabiles
     Glied in der Datei fehlt. Das Werkzeug `tool/update_assetlinks.py`
     liest die Kette live, schreibt die Datei und macht die Gegenprobe -
     nach einem Hosterwechsel einmal laufen lassen, dann passt es
     wieder.

60. **Der Hosterwechsel ist vorbereitet - die Website kann auf
     Cloudflare Pages.**
     BEFUND (Betreiber): "Meine Credits bei Netlify sind fast leer und
     ich brauche mehr, damit ich oefter deployen kann." Netlify Free hat
     300 Credits pro Monat, und nach der aktuellen Preisliste kostet
     ein **Production-Deploy 15 Credits** - das sind 20 Deploys im
     Monat, egal ob mit oder ohne Build. Genau daran stoesst er.

     **Die Lösung ist ein Hoster, der gar keinen Build braucht:**
     Cloudflare Pages. Ein Deploy ist dort ein **Ordner-Upload**
     (Drag & Drop), also kein Build und keine Credits. 0 EUR, keine
     Bandbreitengrenze (Fair Use), 100 Domains und 20.000 Dateien je
     Projekt (hier: 2 und 49). Die Website selbst ist 2,04 MB
     statisches HTML - die Auslieferung ist überall gleich schnell,
     es gibt keinen Leistungsunterschied.

     **Der Publish-Ordner ist jetzt bei beiden Hostern einsatzbereit.**
     Zwei Syntax-Unterschiede wurden live in der Cloudflare-Doku
     belegt und im Ordner ausgeraeumt:

     - `_redirects` kennt bei Cloudflare nur `[Quelle] [Ziel] [Code]`
       mit einer **Zahl** als Code. Das Netlify-Ausrufezeichen ("!"
       = erzwungen) hätte die ganze Regel ignoriert - und das betraf
       genau die Datei `/.well-known/assetlinks.json`, ohne die die
       Passkeys auf Android ausfallen. Für Netlify ändert sich
       nichts, weil an diesen Quelladressen keine Datei liegt.
     - Cloudflare kann **keine** domain-bezogenen Regeln. Die Regel, die
       `auth.thestia.de` eine gesperrte `robots.txt` gibt, wird dort
       ignoriert. Der Ersatz steht jetzt in `_headers`:
       `X-Robots-Tag: noindex` für `https://auth.thestia.de/*` - die
       standardsmaessige Form, die Google und Bing folgen. `thestia.de`
       bleibt indexierbar.

     **Der Auth-Host ist damit an beiden Hostern gesperrt** - nur auf
     zwei Wegen, weil die Hoster unterschiedliche Moeglichkeiten haben.

     **Das Prüfen ist schaerfer geworden:**
     `tool/check_publish_folder.py` prueft jetzt, dass der Ordner
     keine Netlify-Syntax mehr traegt, die Cloudflare nicht kennt -
     und dass der Ersatz für die domain-bezogene Regel wirklich
     vorhanden ist. `tool/check_websites_live.py` kann mit `--host`
     jeden weiteren Host prüfen (etwa das Pages-Projekt, BEVOR der
     DNS umgestellt wird), prueft die Sicherheits-Header an der
     **Antwort des Servers** statt an der Datei - und vergleicht die
     live ausgelieferte `assetlinks.json` mit dem Publish-Ordner. Der
     Deploy wird damit sichtbar, auch wenn er zurueckliegt.

     **Die Anleitung liegt in `docs/WEBSITE-HOSTING.md`** (mit den
     gemessenen DNS-Werten für die Mail und die Domain). Wichtig:
     die **Apex-Domain** `thestia.de` geht bei Cloudflare Pages nur
     über Cloudflare-DNS, die Subdomain `auth.thestia.de` per CNAME.
     Die Nameserver werden erst umgestellt, **nachdem** der neue Host
     geprüft ist - dann ist der Rollback eine Zeile.

     **Ein Detail, das beim Umstellen leicht verloren geht:** die
     DNS-Aufliste enthaelt die **DMARC-Record**
     (`_dmarc.thestia.de`: `v=DMARC1; p=none; rua=mailto:rua@dmarc.
     brevo.com`) neben den beiden MX-Eintraege für die Mail. Wird die
     Domain zu Cloudflare gezogen, wandern alle Eintraege - wer nur
     die MX-Records uebernimmt, verliert die DMARC-Policy im
     Hintergrund. Ein DKIM-Eintrag wurde bei den ueblichen Selektoren
     nicht gefunden (in der SPF-Liste steht ohnehin nur Spaceships
     Weiterleitung).

     **An der App ändert sich nichts:** die App laedt die
     CAPTCHA-Seite von `https://auth.thestia.de/` - dieselbe Adresse
     wie heute - und das Zertifikat der Website ist nicht gepinnt
     (`cert_pinning.dart` pinnt nur Supabase und den Hugging-Face-
     Router). Die einzige Kopplung ist die Passkey-Verknuepfung über
     die RP-ID, und die läuft über die `assetlinks.json` (Schritt 6
     der Anleitung).

61. **Ein altes Vercel-Projekt lief noch - und die alte Domain mit.**
     BEFUND (Betreiber, 08.11.2026): "Außerdem ist bei Vercel
     irgendwas von dir hochgeladen. Der deployment storage ist bei
     7,77/10 GB."

     **Was es ist:** ein Vercel-Projekt `blind-date-app`, am 24.07.2026
     mit dem CLI angelegt (die Verknuepfung liegt in `.vercel/`, das
     nicht im Repository ist). Es liefert unter
     `https://blind-date-app.vercel.app` eine **alte Landingpage**
     ("Blind Date | Real Conversations") - ein React-Build von vor der
     Umbenennung.

     **Und die alte Domain zeigt ebenfalls darauf:** `theblinddate.in`
     hat Nameserver von Vercel (`ns1/ns2.vercel-dns.com`) und leitet
     auf `www.theblinddate.in` weiter (307). Die Seite traegt
     `<meta name="robots" content="index, follow">` - sie ist also
     **indexierbar**, während die echte Seite inzwischen "Thestia"
     heisst. Zwei offene Punkte also: eine alte, indexierbare
     Dating-Seite unter der alten Marke und der Deployment-Speicher
     von 7,77 GB (Hobby: 10 GB inklusive).

     **Geprüft, nicht vermutet:** Live gemessen liefert das Projekt
     außer `index.html`, `manifest.json` und den Icons die index.html
     als Ersatz (SPA-Fallback). Die **APKs, der Datenbank-Backup-Dump
     und der `releases/`-Ordner sind NICHT oeffentlich abrufbar** - das
     wurde an jedem einzelnen Pfad nachgemessen. Es gab also keinen
     Datenabfluss; weg sind nur Speicher und eine veraltete Seite.

     **Das Aufraeumen** steht in `docs/WEBSITE-HOSTING.md`. Wichtig
     ist die Reihenfolge: alte Deployments loeschen UND die
     Git-Verknuepfung trennen - sonst legt jeder Push wieder ein
     Deployment an und der Speicher fuellt sich von selbst. Für die
     alte Domain gibt es zwei Wege: loeschen oder per **301** auf
     `thestia.de` weiterleiten (302 wäre wirkungslos für die
     Suchmaschinen).

62. **Die Web-Version braucht einen anderen Hoster als die Website.**
     BEFUND (Betreiber, 08.11.2026): "Ich möchte ja wie auch in der
     Roadmap steht, spaeter auch ne web version der App anbieten. Mir
     ist EU sehr wichtig (ideal DE oder CH)."

     Die Roadmap (v0.12.0, "Web-Bridge, Transit-Reachability &
     Zero-Install") nennt **Flutter Web auf Codeberg Pages** - das ist
     möglich: Codeberg Pages kann eigene Domains mit Zertifikat
     ("Hosted in Europe", Codeberg e.V., Berlin) und kennt eigene
     404-Seiten für den SPA-Fallback. **ABER:** die Web-App stellt
     andere Anforderungen als die 2-MB-Website. `main.dart.js`
     (2-6 MB) plus CanvasKit/WASM (rund 8 MB) bedeuten **10-20 MB pro
     Erstaufruf** - bei Netlify sind das 20 Credits je GB, also rund
     **1.000 Aufrufe im Monat** (die Website schafft 19.000). Netlify
     Free fällt für die Web-App damit weg.

     **Der sinnvolle Split:** die Rechtsseiten bleiben auf Netlify (sie
     kosten fast keine Credits), die Web-App kommt unter
     `web.thestia.de` auf einen EU-Hoster - eine CNAME-Zeile bei
     Spaceship, **kein Nameserver-Wechsel, keine Mail-Risiken**, und
     `auth.thestia.de` (Passkey-Verknuepfung) bleibt unangetastet.

     **Die EU-Kandidaten** (Preise live geprüft am 08.11.2026):
     netcup Cloud Web Hosting ab **2,17 EUR/Monat** (SSH, Let's
     Encrypt), Hetzner Cloud + Caddy **4,49-5,99 EUR/Monat** mit 20 TB
     Traffic inklusive, Codeberg Pages 0 EUR, Cloudflare Pages 0 EUR
     (US-Firma, aber EU-Knoten - und für eine Website ohne
     personenbezogene Daten datenschutzrechtlich unkritisch).

     **UND: es gibt Studentenrabatte.** **Infomaniak (Schweiz)** gibt
     **1 Webhosting (250 GB, 20 Websites) + 1 Mail-Service kostenlos**
     für die Dauer des Studiums (bis vier Jahre, jaehrlich mit den
     gleichen Unterlagen erneuern) - Bedingungen: Studentenausweis
     oder Schulbescheinigung, Personalausweis und die offizielle
     Schueler-Mail-Adresse der Schule; die Domain muss man nicht
     kaufen, die eigene (`thestia.de`) darf verwendet werden.
     netcup hat dauerhafte Gutscheine (30 % auf die Webhosting-Tarife),
     IONOS einen UNiDAYS-Rabatt, Hetzner 20 EUR Startguthaben. Die
     Angebote im Detail: `docs/WEBSITE-HOSTING.md`.

63. **Die Apache-Konfiguration für Infomaniak ist erzeugt - und
     kann nicht veralten.**
     BEFUND (Betreiber): "Infomaniak vorbereiten." Infomaniak (CH)
     hostet im Studentenprogramm kostenlos, fährt Apache und lässt
     mod_rewrite und .htaccess zu ("enabled by default on all
     Infomaniak infrastructures", Doku vom 08.11.2026).

     **Das Problem:** die Website hat zwei Konfigurationsdateien, die
     nur Netlify und Cloudflare Pages lesen - `_redirects` (38
     Rewrite-Regeln) und `_headers` (41 Header-Bloecke mit CSP, HSTS,
     Cache-Regeln). Bei Apache muesste beides von Hand in eine
     `.htaccess` uebersetzt werden: 40 Zeilen, die bei jeder Änderung
     nachgezogen werden mussten - und stillschweigend veralten
     können (die Seite läuft dann weiter, nur ohne den Schutz).

     **Die Lösung:** `tool/make_htaccess.py` erzeugt die Datei aus
     beiden Quellen. Die Uebersetzung sitzt damit an genau einer
     Stelle. Zwei Fehler, die beim ersten Versuch passiert sind und
     jetzt im Selbsttest feststeckt:

     - **Die Punkte in den Mustern mussten escaped werden.** Ohne
       Escape passte `^auth.thestia.de$` auch auf `authXthestiaYde`,
       und `^.well-known/assetlinks.json$` auf jede Datei.
     - **Der Auth-Host war doppelt abgedeckt** (einmal über den
       `_headers`-Block, einmal als eigener Block). Jetzt steht jede
       Regel genau einmal da.

     **Und ein Gate verhindert das Veralten:** `check_publish_folder.py`
     erzeugt die `.htaccess` neu und vergleicht sie mit der Datei auf
     der Platte. Wer `_headers` oder `_redirects` ändert, bekommt
     rot: "webhosting/.htaccess ist veraltet - Reparieren: python
     tool/make_htaccess.py". Die Drift-Prüfung ist getestet (sie
     schlaegt bei einer absichtlichen Abweichung an).

     **Die Datei liegt bewusst AUSSERHALB des Publish-Ordners**
     (`webhosting/`): Netlify und Cloudflare Pages wuerden sie als
     statische Datei ausliefern. `webhosting/README.md` enthaelt den
     Upload (SFTP und rsync), die Zwei-Website-Frage und die
     Nacharbeiten nach dem Zertifikatswechsel.

     **Die Anleitung für Infomaniak** steht in
     `docs/WEBSITE-HOSTING.md`: Studentenprogramm, Website anlegen,
     Zertifikat, hochladen, DNS (nur ein A-Record und ein CNAME - die
     Mail-Records bleiben unangetastet, weil die DNS bei Spaceship
     bleibt) und die Pruefkommandos.

64. **Fünf Fehler aus der Betreiber-Runde vom 09.11.2026 - alle gefunden,
     alle behoben.**
     BEFUND (Betreiber): „Wenn Bild geöffnet und zurück swipe, dann im
     Hintergrund zurück, aber Bild noch offen. Bei 3 Punkte Menü ist über
     Eisbrecher Fragen ein Strich einfach so aber keine Überschrift oder
     so. Die Bilder sind nicht sichtbar, wenn hochgeladen. Die App
     Version ist wahrscheinlich veraltet. Ich habe aber keinen update
     erforderlich screen beim admin apk. Bei Vorstellung anhören im Chat
     soll eine Zeitanzeige mit Balken sein, falls noch nicht vorhanden."

     **(a) DER ADMIN-BUILD WAR VOM VERSIONS-GATE AUSGENOMMEN.** Das
     Gate verglich die rohe Build-Nummer. Der Admin-Build trägt die
     Basis + 9000 (`build_release.ps1`) - 9048 ist aber IMMER grösser
     als jedes Mindest-Build. **Der Admin-Build wurde deshalb nie
     gesperrt**, egal wie streng der Serverwert war. Jetzt wird die
     BASIS verglichen (`baseBuildNumber`), mit Tests für 9048 → 48 und
     für normale Builds.

     **(b) DIE CHAT-BILDER WAREN EINE ATTRAPPE.** Die Nachricht kam
     korrekt an (E2E-entschlüsselt, als Daten-URL in `mediaUrl`) - die
     Blase zeichnete aber einen Farbverlauf mit Bild-Symbol. Jetzt wird
     das Bild angezeigt (mit Verpixel-Schutz, Base64-Cache gegen
     Mehrfach-Dekodieren). Dasselbe galt für das Vollbild und das
     View-Once-Bild.

     **(c) DIE PROFILBILDER VERSCHWANDEN NACH DEM SPEICHERN.** Nach
     dem Speichern wurden die Future der Kacheln 1 und 2 verworfen - die
     Kacheln fielen auf das Platzhalter-Symbol zurück, bis die App neu
     gestartet wurde (das erste Bild wurde neu geladen, die beiden
     weiteren nicht). Und: eine ERSETZTE Datei blieb als Wrack im
     Speicher liegen, weil die Liste eine lückenlose Galerie ist, der
     Pfad aber den Kachel-Index nennt. Beides ist behoben.

     **(d) DAS 3-PUNKTE-MENÜ HATTE EINEN TRENNER OHNE ÜBERSCHRIFT.** Der
     erste Strich stand ganz oben im Menü (er trennte nichts), und nur
     die Gruppe „Sicherheit" hatte eine Überschrift. Jetzt: kein
     führender Strich, und jede Gruppe hat ihre Überschrift
     (Gespräch / Sicherheit / Verbindung).

     **(e) DIE VORSTELLUNG HATTE KEINE ZEITANZEIGE.** Der Abspiel-Knopf
     allein sagte nichts über Länge und Fortschritt. Jetzt gibt es
     Balken und Zeitanzeige (0:04 / 0:32) - im Chat wie im Profil.

     **Dazu der Wisch im Hintergrund:** Das Bild lag auf dem Navigator
     der Shell, und der Reiter-Wechsel sitzt darüber. Die Sperrfläche
     eines Dialogs schluckt Tipps, aber KEINE waagerechte Wischgeste -
     die landete im Reiter-Wechsel: der Hintergrund wechselte, das Bild
     blieb offen. Und das View-Once-Fenster verbot mit `canPop: false`
     jeden Pop - **auch den Zurück-Wisch des Systems**. Jetzt schließt
     die Wischgeste das Bild (und der Pop ist erlaubt).

65. **„Zurück liken" und „Funke bestätigen" waren dasselbe.**
     BEFUND (Betreiber): „Zurück liken und Funke bestätigen läuft doch
     aufs selbe hinaus. Like und Funke einer Person nicht gleichzeitig
     möglich oder?"

     **Die Antwort aus dem Server (Migration 197, live):** Beide
     Knöpfe riefen den Weg, bei dem sofort ein Funke entsteht. „Zurück
     liken" rief `like_user` - und diese Funktion legt bei einem
     BEIDSEITIGEN Like sofort einen Funke an (Zeile 127-136). Auf der
     Karte mit den erhaltenen Likes hat die andere Seite aber IMMER
     schon geliked - „Zurück liken" erzeugte dort also immer genau
     denselben Funke wie der Knopf daneben. Der Kommentar am Knopf
     behauptete das Gegenteil („ohne sofort einen Funken daraus zu
     machen") - das konnte der Server gar nicht.

     **Der Knopf ist deshalb weg.** Zwei Knöpfe, die dasselbe tun, sind
     schlimmer als einer.

     **Und zur zweiten Frage:** Like und Funke GIBT es gleichzeitig. Ein
     angenommener Like bleibt in der Tabelle stehen, während der Funke
     existiert. Dass ein NEUER Like zu einer Person mit schon
     bestehendem Funke verschwindet, ist eine bewusste Entscheidung
     (Migration 197): der Server meldet `already_matched`, und die App
     sagt „Mit {name} habt ihr schon einen Funken." - das war die
     Antwort auf genau diese Frage vom 07.11.2026.

66. **Ein gescheiterter Server-Sync ging verloren - jetzt wird er
     nachgeholt.**
     BEFUND (Betreiber): „Server Sync ist fehlgeschlagen. Wenn Daten
     aktuell nicht synchronisiert werden können, soll dies Nachträglich
     gehen."

     DER GRUND: Der Praeferenz-Sync (Suchradius, Altersspanne,
     Geschlechterfilter, Filtermodus) scheiterte - und dann war die
     Änderung weg. Der Server behielt den alten Wert, die Altersspanne
     (die es NUR auf dem Server gibt) war überhaupt nirgends mehr, und
     der Fehler stand nur im Log - für den Nutzer unsichtbar.

     JETZT: Die Änderung wird **vorgemerkt** (im sicheren
     Speicher, zusammen mit der Altersspanne) und beim nächsten Start
     **nachgeholt**. Der Marker loescht sich, sobald der Server sie
     angenommen hat. Der bestehende Drei-Versuche-Wiederholversuch
     bleibt.

67. **Find your Spark wird ausgebaut - und Gruppen/Foren kommen danach.**
     BEFUND (Betreiber): „Der Modus Find your Spark soll erweitert
     werden... dann entweder Zufallsvorstellung oder Vorstellungen
     anderer nach Kategorien ansehen. Also Kategorien sind die
     Interessens-Kategorien. Auf diesen neuen Teil mit den Kategorien
     soll ein Bereich mit 18+ sein, wo von 18 bis 99+ alle gesehen
     werden (Aber man kann nach Alter filtern mit Regler) und ein 16-17
     Bereich ohne Vorstellung mit Alter darüber. Wichtig ist, dass diese
     Grenze wirklich klappt... Natürlich da dann E2E immer. Verschlüsselt
     auf Server speichern."

     Der Ausbau steht jetzt in der ROADMAP (Abschnitt 0.12.0, Punkt 9)
     mit der Architektur: Einstieg mit Vorstellungs-Check (ohne
     Doppelaufforderung), dann Zufall oder Kategorie; die Kategorie-Abfrage
     läuft **serverseitig** und wendet dieselbe
     `age_compatible_bidirectional`-Regel an (Minderjaehrige nur
     Minderjaehrige, Erwachsene nur Erwachsene); der Altersregler im
     18+-Bereich geht bis 99 (`maxFilterAge`), im 16/17-Bereich endet er
     bei 17; die Vorstellung wird **verschlüsselt auf dem Server**
     gehalten und erst auf dem Gerät entschluesselt (E2E wie bei den
     Profilbildern).

     **Vom Betreiber entschieden (09.11.2026):** Die Vorstellung
     bleibt Pflicht - auch in der Erweiterung und auch für
     16-/17-Jaehrige. **Sie darf rein TEXTLICH sein**: das Audio ist
     optional und wird erst bei einem Funke gehoert (dort, wo die
     Vorstellung heute ohnehin über `match-media` freigegeben wird);
     die Kategorie-Sicht zeigt Text und Interessen, nicht die
     Aufnahme. Und: **16- und 17-Jaehrige sehen KEINE 18+-Personen** -
     die Trennung ist serverseitig und gilt für jeden Abrufweg.

     **Gruppen und Foren** (Abschnitt 0.12.0, Punkt 10) sind als
     SPÄTERER Schritt eingetragen - mit derselben Alterstrennung
     (serverseitig erzwungen), einem Moderationsweg und einem eigenen
     Eintrag in der Datenschutzerklaerung.

68. **Das Logo in der Suche war nur ein Herz - jetzt ist es das
     ThestiaIcon, und es ist rund.**
     BEFUND (Betreiber, 09.11.2026): „Jedoch ist das Logo nur ein Herz
     und nicht das ThestiaIcon Logo. Das Runde sollte dabei auch die
     Farben von dem Abgerundeten haben (Hier muss das Bild Rund sein)."

     **Zwei Fehler, einer davon in jeder Datei sichtbar:**

     **(a) `favicon.svg` war die MARKE - ein Herz.** Und weil das SVG im
     HTML als Icon deklariert war, zeigte der Browser-Tab genau das.
     Der Browser nimmt das LETZTE passende Icon - das SVG gewinnt also
     gegen die PNG. Die PNG enthielt zwar schon das ganze ThestiaIcon,
     sie wurde aber nie benutzt. Jetzt enthalten alle drei Dateien
     dasselbe Bild: das **runde** ThestiaIcon aus der einzigen
     Logo-Quelle (`assets/images/thestia_icon_base.png`). Das SVG
     bettet das PNG ein - das Artwork ist eine Rastergrafik, und eine
     „vektorisierte" Marke wäre eine ANDERE Marke (genau der Fehler,
     den der Betreiber gemeldet hat).

     **(b) Das runde Launcher-Icon war blass.** Zwei Ursachen, beide
     gefunden: Der Hintergrund-Kreis (Radius = halbe Leinwand) wurde in
     eine kleinere Maske gelegt (Radius = 72/108) - sichtbar blieb nur
     die **Mitte** des Verlaufs, die satten Randbereiche (pink oben
     links, violett unten rechts) lagen außerhalb. Und das Herz war
     **halbtransparent**: Die Alpha des Vordergrunds wurde aus der
     Farbe berechnet (`min(r,g,b)` zwischen 88 und 168) - das betraf
     auch die magentafarbene Lippe des Herzens (min = 104-169): Sie
     bekam nur 20-100 % Deckkraft und wurde über dem Verlauf zu rosa
     Milchglas. Gemessen: 81 % der opaken Pixel lagen unter 0,95
     Deckkraft. Die Schwelle ist jetzt 88-104: das Artwork ist voll
     deckend, nur der Verlauf fällt weg.

     **DER RUNDE SCHNITT** steht jetzt in `tool/logo_round.py` (Python,
     weil die Favicons mit Pillow erzeugt werden) - dieselbe Rechnung
     wie in `tool/generate_round_logo.dart`. Beide Wege wurden
     gegeneinander geprüft: mittlere Abweichung 0,81 je Kanal
     (nur die Anti-Aliasing-Pixel am Kreisrand unterscheiden sich).

     **DIE DOMAIN-FRAGE (gleiche Runde, live geprüft):** `thestia.de`
     ist **nicht** blockiert. Die ausgelieferte `robots.txt` sagt
     `User-agent: * / Allow: /` - auch für einen Googlebot (mit
     dessen User-Agent nachgemessen). Gesperrt ist **nur**
     `auth.thestia.de` (das ist der Sicherheitscheck der App, das
     ist Absicht). Die HTTP->HTTPS-Umleitung und die Sitemap stimmen
     auch. Wenn die Search Console für eine Adresse „blocked by
     robots.txt" anzeigt, ist es entweder eine Adresse unter
     `auth.thestia.de` (korrekt) oder der Stand von Google ist noch
     der alte (der Cache der robots.txt wird erst bei einem neuen
     Abruf erneuert - die „URL-Inspektion" mit „Neuer Abruf
     anfordern" erledigt das).

     **UND DIE VERCEL-DOMAIN:** Die alte Domain `theblinddate.in` ist
     **bei GoDaddy registriert** (RDAP-Abfrage), ihre Nameserver
     zeigen aber auf Vercel. Das Projekt und die Domain liegen in
     einem **anderen Vercel-Team** (`team_0UCJ…` aus der lokalen
     Verknuepfung), das die aktuelle Anmeldung nicht sieht - deshalb
     war das `vercel project remove` wirkungslos, und die Seite
     liefert weiter die alte Landingpage. Abschalten lässt sich auf
     zwei Wegen: die Nameserver bei GoDaddy umstellen (schnellster
     Weg, kein altes Login noetig) oder im alten Vercel-Team
     `vercel domains rm theblinddate.in` ausfuehren.

69. **„Find your Spark" kann jetzt nach Interessen - und die Vorstellung
     darf rein textlich sein.**
     BEFUND (Betreiber): "Der Modus Find your Spark soll erweitert
     werden. Wenn man auf ihn drauf drückt, kommt wie gehabt erst, dass
     man seine Vorstellung machen muss (Muss geprüft werden, ob man
     schon gemacht hat oder nicht, damit nicht doppelt), dann entweder
     Zufallsvorstellung oder Vorstellungen anderer nach Kategorien
     ansehen. Also Kategorien sind die Interessens-Kategorien. Auf
     diesen neuen Teil mit den Kategorien soll ein Bereich mit 18+ sein,
     wo von 18 bis 99+ alle gesehen werden (Aber man kann nach Alter
     filtern mit Regler) und ein 16-17 Bereich ohne Vorstellung mit
     Alter darüber. Wichtig ist, dass diese Grenze wirklich klappt, wie
     auch überall anders auch, damit die Kinder/Jugend geschützt sind.
     Natürlich da dann E2E immer. Verschlüsselt auf Server speichern."

     **DER ABLAUF:** "Find your Spark" fragt zuerst die eigene
     Vorstellung ab - aber **nur, wenn es noch keine gibt** (vorher
     stand die Abfrage da, auch wenn die Vorstellung schon da war).
     Danach kommt die Wahl: *Zufallsvorstellung* (wie bisher) oder
     *Nach Kategorie*.

     **DIE KATEGORIE-SICHT:** Die Kategorien sind die Interessen
     (Musik, Sport, Gaming, Reisen, ...). Jede Kategorie zeigt ihre
     Zahl - sonst wäre das Stöbern blind (man tippt auf "Sport" und
     sieht niemanden und weiß nicht, ob die Funktion kaputt ist). Der
     Altersregler (18 bis 99+, bei 16/17 bis 17) ist derselbe wie
     sonst in der App.

     **DIE ALTERSSGRENZE - server-seitig, nicht im Client:** Die
     Abfrage liest aus `public_profiles`, und die Sicht filtert über
     `profile_discovery_visible_full` (Migration 203/204). Ein
     16-Jähriger sieht damit ausschließlich 16- und 17-Jährige, ein
     Erwachsener ausschließlich Erwachsene - auch dann, wenn jemand die
     App manipuliert. Die gewünschte Altersspanne wird zusätzlich
     serverseitig begrenzt (`max_age_range_min`, Obergrenze 17 bzw.
     99). **Zwei Fail-Fast-Beweise in den Migrationen** prüfen, dass
     die Sicht die Schutzabfrage noch enthält: ohne sie würde die
     Kategorie-Sicht still zur Lücke.

     **E2E bleibt:** Die Kategorie-Sicht zeigt den **Text** der
     Vorstellung und die Interessen. Die **Aufnahme** ist optional
     (vorher Pflicht) und wird - wie bisher - erst beim Funke
     freigegeben (match-media, serverseitig geprüft).

     **KEIN NEUER MINOR-BUMP:** Die Linie **0.10.0** ist offen (nie
     im Store veröffentlicht) und traegt die neuen Funktionen bereits -
     sie ist ohnehin schon ein MINOR (die Standort-Privatisierung ist
     eine Änderung der Datenverarbeitung). Der Ausbau gehoert deshalb
     zu 0.10.0, Build 49. Der Roadmap-Plan für den Ausbau ist damit
     umgesetzt; die Gruppen und Foren stehen als spaeterer Schritt in
     der Roadmap (0.12.0).

     **Die Datenschutzerklärung** hat einen eigenen Eintrag
     bekommen: Die Kategorie-Sicht ist eine neue Sichtbarkeit (andere
     finden dich über deine Interessen) - mit derselben Altersgrenze
     und ohne Audio.

## [0.10.0] - 2026-10-24 (Build 31)

### Sicherheit

- **Client-Schreibschutz für Verifikationsfelder repariert** (Migration 156):
  Migration 155 hatte die Trigger-Funktion mit `pg_has_role(current_user, …)`
  neu definiert. Im `SECURITY DEFINER`-Kontext ist `current_user` der
  Owner der Funktion, nicht die aufrufende Rolle – die Prüfung war damit
  **fail-open** und die `RAISE EXCEPTION` wurde nie ausgelöst. Jeder
  angemeldete Nutzer konnte per Data API `is_verified = true`,
  `verified_age = 100` oder `verification_status = 'approved'` selbst
  setzen – Badge, Modus-Sperren und der Jugendschutz-Filter waren damit
  client-kontrolliert. Der Trigger liest jetzt wieder den Role-Claim aus
  dem JWT (Muster aus 056/061/095); `is_location_suspicious` ist wieder
  geschützt
- **Meldeweg für Kindesmissbrauch funktioniert wieder** (Migration 156):
  Der Client sendet `ReportType.name` (camelCase), die Server-Whitelist
  kannte nur snake_case – **vier von sieben** Meldetypen wurden serverseitig
  abgewiesen, darunter `childSafety` und `inappropriateContent` (NSFW-
  Bildmeldungen). Die App zeigte trotzdem die grüne Bestätigung, weil der
  Fehler nur geloggt wurde. Die Whitelist kennt jetzt beide Schreibweisen,
  Meldungen vom Typ `childSafety` stehen in der Admin-Liste vorn, und
  der Nutzer wird gewarnt, wenn die Übermittlung nicht geklappt hat
- **Automatische Verifikations-Freigabe war tot** (seit Migration 151):
  Der Client lädt das Video verschlüsselt als `video.mp4.enc` hoch,
  `verify-account` prüfte aber auf `video.mp4` – der Auto-Pfad endete
  immer mit HTTP 400. Bei einer Ablehnung wurde zusätzlich das falsche
  Objekt gelöscht, das Chiffrat blieb liegen (DSGVO Art. 17)
- **Verifiziertes Alter ist konservativ** (Migration 156): `verified_age`
  wird als das **jüngere** von KI-Schätzung und angegebener Alter
  gesetzt. Die KI-Schätzung ist ein Client-Wert und keine unabhängige
  Messung; ein zu junges Ergebnis schließt nur Begegnungen aus, ein zu
  altes hätte eine minderjährige Person als erwachsen behandelt
- **Verifikationsstatus wird vom Server gelesen**: `is_verified` war der
  einzige serverseitige Wert, der nachgezogen wurde. Der Dreifachzustand
  (unverifiziert / wird geprüft / verifiziert) blieb lokal stehen – wer
  eingereicht hatte, sah weiterhin „nicht verifiziert“ und die
  Modus-Sperren blieben ohne erkennbaren Grund bestehen. Zusätzlich zeigt
  die App das Verifikations-Abzeichen bei fremden Profilen jetzt an – die
  Information lieferte der Server, sie wurde nur nie gelesen
- **Kein TURN-Server mehr**: `ice-config` liefert nur noch STUN. Der
  TURN-Provider (Betreiber, Server-Standort) fiel in der
  Datenschutzerklärung weg; die Messung ergab, dass der eingesetzte
  TURN-Dienst auf einen Test-Netz-Bereich zeigte. Wiedereinführung steht
  als offener Punkt in der Roadmap
- **Alle 7 Overflows behoben** und die stillen Funktionsausfälle
  gefunden: `favorite_song`, `favorite_band` und `birthday_style` wurden
  gelesen, aber nie gespeichert – der Profil-Edit schrieb sie mit einem
  leeren Wert zurück. Ebenso `distance_filter_mode` (Snake-Case),
  `relationship_type`/`preferred_state` (zwei Writes statt einem) und
  `personality_type` (serverseitig statt lokal). `show_distance` und die
  Push-Schalter lesen ihre Werte jetzt tatsächlich vom Server

### Datenschutz

- **Datenschutzerklärung Version 14** mit Klartext-Hinweisen zu
  Transit-Merkmalen, 24-h-Frist, verifiziertem Alter, beidseitiger
  Sichtbarkeit, Kontaktweg und Lösch-URL
- **Öffentliche Kontakt- und Löscheseiten**: `kinderschutz.thestia.de`
  (Kontaktperson Thoralf Illg, `kinderschutz@thestia.de`),
  `konto-loeschen.thestia.de` und die Datenschutzerklärung unter
  `datenschutz.thestia.de` – jeweils mit Rewrite auf der Website
- **Video-Verschlüsselung**: AES-256-GCM clientseitig, der Schlüssel
  liegt in `verification_video_keys` (ohne Client-Zugriff), im Bucket
  nur Chiffrat. Die Admin-Sichtung erzeugt eine 20-Minuten-Vorschau, die
  ein Cron wieder entfernt
- **Jugendschutz**: das verifizierte Alter ist maßgeblich, die
  Altersspanne wird beidseitig geprüft, die Untergrenze liegt bei
  (eigenes Alter − 10), und Vorschlagslisten gibt es nur für
  verifizierte Konten

### Features

- **Transit-Merkmale mit Kategorien** (top/bottom/head/shoes/accessory/
  hair/eyes): die Beschreibung einer Person ist jetzt über eine
  serverseitige Katalogtabelle definiert, mit Suche, Kategoriefilter,
  höchstens einem Wert je Kategorie und höchstens acht insgesamt
- **Nähefunk-Icons**: eigene Symbole für Transit Spark, Zufallschat und
  „Find your Spark“, dazu ein rundes Launcher-Icon
- **Play-Child-Safety-Standards**: eigener Meldetyp
  (`ReportType.childSafety`), eigener Abschnitt in den Community-
  Richtlinien mit Link auf die Kontaktseite, `cg.6` in den Richtlinien
  auf Deutsch und Englisch

### Behoben

- **Passwort-Reset und erneutes Senden der Bestätigungsmail**: der
  E-Mail-Hook antwortete auf alle Aktionen außer „signup“ mit HTTP 422 –
  GoTrue wertet das als Fehler und bricht den Auth-Request ab. Es kam
  keine Mail an, und der Nutzer sah eine Fehlermeldung. Der Hook
  versendet jetzt je Aktion die passende Mail (Bestätigung, Reset,
  E-Mail-Wechsel, Magic Link)
- **HOOK_SECRET**: das Secret war 64 Hex-Zeichen, die Function hat
  Base64 dekodiert – die Signaturprüfung schlug deshalb immer fehl
  (401). Die Function akzeptiert jetzt Base64, Hex und Rohbytes;
  `tool/check_hook_secret.py` prüft den Dashboard-Wert gegen die
  laufende Function
- **Neue Tabellen brauchen ein GRANT**: Supabase gibt ab 30.10.2026
  neuen Tabellen im Schema `public` keine automatischen Data-API-Rechte
  mehr. `profile_locations` und `transit_soft_pings` hatten dadurch gar
  kein Grant – der Standort wurde nie gespeichert und eine Funke
  konnte nicht weggeklickt werden (Migration 147)
- **Build-30-Clients sind abgeschaltet**: Migration 138 hat die Spalten
  `city`/`location_lat`/`location_lng` entfernt, Build 30 fragt sie aber
  ab. `min_app_version_build` steht jetzt auf 31
- **Anzeigealter = Filteralter**: die Projektion zeigte das deklarierte
  Alter, gefiltert wurde nach dem effektiven
- **Mehrere Überläufe**: fünf Auswahlfelder, die Fotoleiste, die
  Abschnittsüberschrift, die Chat-Hintergrund-Schaltfläche und die
  Knöpfe im Kopfzeile

### Geändert

- **Toter Code entfernt**: sieben Dateien, 90 ungenutzte Sprachschlüssel,
  zwei Widgetklassen und die Route `/onboarding`
- **CI repariert**: ungültiges YAML ließ alle Jobs ausfallen, der
  Datenschutz-Check ist jetzt `continue-on-error` (Netlify ist ein
  externer Zustand)
- **Paket-Updates**: `camera`, `flutter_local_notifications`,
  `permission_handler`, `shared_preferences`, `url_launcher`,
  `flutter_secure_storage` und `image` auf die aktuellen
  Sicherheits-Patches gehoben

## [0.9.2] – 2026-10-04 (Build 30)

### Sicherheit

- **Serverseitig erzwungene E-Mail-Bestätigung** (Migration 128): ohne
  bestaetigte Adresse sind Matches, Likes und das Nachrichten-Relay nicht
  mehr möglich. Vorher pruefte **keine** der 122 Migrationen den Status
- **Optionale AAL2-Pflicht** pro Konto (`profiles.mfa_required`), mit
  Kill-Switch in `app_config`, damit sie im Notfall ohne Deploy
  abzuschalten ist
- **Antwortschluessel-Exploit geschlossen**: `quiz_shuffle_for_match` war
  eine reine Permutationsfunktion und für die Rolle `anon` aufrufbar.
  Über 24 Permutationen liess sich der korrekte Antwortindex ermitteln -
  damit war der AES-Schlüssel scharfer Profilfotos erreichbar, ohne eine
  einzige richtige Antwort. Ursache war nicht eine fehlende, sondern eine
  unvollstaendige Berechtigung: `REVOKE ... FROM anon` greift nicht, weil
  Rechte über die Pseudo-Rolle `PUBLIC` vererbt werden (Migration 123)
- **Erzwungener Jugendschutz und Blockier-Prüfung** für Zufallschat und
  Dating Hour wiederhergestellt - Migrationen 102/096 hatten die Regeln
  aus 056/058 überschrieben. Zusätzlich als Tabellen-Trigger, damit ein
  spaeteres `CREATE OR REPLACE` die Function nicht mehr aushebeln kann
- **Safety-Number erzwingbar**: Chat-Versand erst nach Vergleich der
  Sicherheitsnummern
- **Certifikat-Pinning strikt**: bisher entschied der Callback, ob
  überhaupt geprüft wurde - eine nachinstallierte Fremd-CA kam durch
- **Kein Rate-Limit-Bypass mehr** in `verify-account`,
  `cancel-registration` und `report-image` (fail-open bei DB-Fehlern) sowie
  in `delete-account` (MFA-Prüfung war fail-open). `x-forwarded-for` wird
  jetzt geparst - Header-Rotation umging jedes IP-Limit
- **`prekeys` prueft die Beziehung** (kein Bundle-Harvesting) und gibt bei
  404 keine Existenz-Auskunft
- **`.env` ist kein App-Asset mehr** (im gebauten APK verifiziert nicht
  enthalten); Konfiguration läuft über `--dart-define`
- **Keystore-Namespaces mit Migration**: ohne sie waeren nach dem Update
  alle Nutzer abgemeldet gewesen und Signal-Keys unlesbar geworden

### Neu

- **Rotierende Vorstellungs-Prompts**: 4 Themen mit je drei offenen Fragen
  statt vier fester Chips
- **Mindest-Build-Gate auf 30** gesetzt (Migration 132) – Support **ab
  v0.9.2**, alle aelteren Builds (v0.8.x, v0.9.0, v0.9.1) sind ohne
  Security-Fixes. Grund ist nicht Versionspolitik, sondern die
  Alterssperre für Transit Spark: aeltere Clients enthalten sie
  nicht und wuerden sie umgehen. Migration 130 (Gate 29) galt für
  v0.9.1 und wurde hiermit überschrieben
- **Naehefunk (Transit Spark) gehaertet**: Advertising mit
  unregelmaessigen Abstaenden statt starrem ~100-ms-Takt, Token-Rotation
  ohne festes Raster, Scan-Filter auf die eigene Hersteller-ID, gepulstes
  Scannen statt 45 Minuten Dauerscan

### Geaendert

- **Dependency-Hygiene in CI**: 16 sicherheitsrelevante Pakete exakt
  gepinnt, `pub outdated`-/CVE-Report, Security-Invarianten und
  SBOM-Erzeugung als CI-Job
- **Zertifikats-Pins und Konfiguration** kommen nicht mehr aus
  gebuendelten Dateien im APK
- **iOS**: `NSPhotoLibraryUsageDescription` ergaenzt - ohne den Eintrag
  wäre die App beim Oeffnen der Fotomediathek abgestuerzt
- **Discovery**: Distanz-, Alters-, Pausen- und Reziprozitaetsfilter
  werden jetzt serverseitig in einer zentralen Regel geprüft
- **Quiz-Cooldown** greift bei jedem Versuch (vorher gar nicht)

### Behoben

- **Standort wird nach 30 Tagen automatisch geloescht** (Migration 129,
  taeglicher Cron) statt unbegrenzt gespeichert
- **`match_bucket_list`**: `match_id` und `created_by` sind nicht mehr
  aenderbar, Statuswechsel sind gedrosselt
- **`check_email_ban_status`** gibt keinen internen Moderations-Freitext
  mehr nach aussen
- **Bilder**: Groessen-, Pixel- und Dimensionsbudget werden vor dem Decode
  geprüft (`image` 4.10.1), damit eine Decompression-Bomb nicht mehr den
  Speicher des Geraets frisst
- **WispDating-Reste** in Gradle, PWA-Manifest und Log-Tag entfernt
- **Speicher-Namespaces mit abwartbarer Migration**, damit die app-weite
  Keystore-Reset-Kaskade nicht mehr greift

## [0.9.1] – 2026-09-25

### Sicherheit (Build 22)

- **Video-Verifizierung, Mehrframe-Median**: Altersschätzung aus bis
  zu 6 Frames (5 Video-Frames + 1 Selfie), Median statt Einzelbild;
  2-Jahre-Regel und manuelle Prüfung unverändert.
- **Stichproben-Audit** (Migration 120, live): Admin-Tab listet
  Auto-Freigaben mit Video, Bestätigen und Entziehen.
- **Play Integrity** (nur Play-Builds, `docs/PLAY_INTEGRITY.md`):
  Token + serverseitige Verdict-Prüfung in `verify-account/action
  "auto"` (deployed); ohne Play-Eintrag/Secret fällt alles sicher
  auf manuell zurück.
- **Modell-Integrität**: SHA-256-Check der ONNX-Modelle (fail-closed
  in manuell). **TLS-Pinning** für allen Dart-Traffic.
- **Dart-Obfuskierung** in Release-Builds (R8-Keep-Regel für den
  Reflection-geladenen Integrity-Helper). Abgelaufener
  Supabase-Leaf-Pin erneuert (gültig bis 24.11.2026).
- **Kontolöschung vollständig (DSGVO Art. 17)**: `delete-account`
  löscht zusätzlich Bug-Reports, Meldungen gegen den Nutzer und
  Rate-Limit-Reste (Rest via CASCADE, live per pg_constraint
  verifiziert); lokal werden Chat-Verlauf, Melde-Entwürfe und
  Crash-Journal mitgelöscht (auch bei Logout gegen Kontowechsel-
  Reste). Erhalten bleiben nur der irreversible Tombstone-Hash,
  Admin-Auditspalten und die Sperrliste.
- **API-Keys umgestellt (Legacy anon/service_role -> Publishable/
  Secret)**: Client liest nur noch `SUPABASE_PUBLISHABLE_KEY`, alle
  18 Edge Functions nutzen ausschließlich die sb_-Quellen
  (`SUPABASE_SECRET_KEY` / `SUPABASE_SECRET_KEYS`, supabase-js
  2.44.0); alle Legacy-JWT-Fallbacks sind entfernt (inkl. Secret
  `WISP_SERVICE_ROLE_KEY`). Legacy anon/service_role-Keys im
  Dashboard deaktiviert; Migration 122 ergänzt die SELECT-Grants,
  die PostgREST für Filter-DELETEs benötigt.
- **Versions-Support**: v0.9.0 (Build 28) ist die unterste
  unterstützte Version. v0.8.x und älter sind End-of-Support
  (seit 24.09.2026, siehe [SUPPORT.md](SUPPORT.md)); sie erhalten
  beim Start einen Update-Hinweis (serverseitig
  `app_config.min_app_version_build = 28`).
- **Behoben (Build 28)**: Standort-Eingabe (Onboarding + Profil):
  Geokodieren läuft erst bei Tipppause (Debounce), der getippte
  Text wird nicht mehr gelöscht, „Ort nicht gefunden" ist eine
  eigene Meldung. Verifiziert-Badge steht im eigenen Profil neben
  dem Persönlichkeitstyp.

Server: Migrationen **086, 087 + 088** einspielen + Edge Functions
`notify-user` erneut deployen.

### Behoben

- **Vorstellung mit Audio ging bei Aktualisierung/Neuinstallation
  verloren**: Der Intro-Upload setzte keinen Content-Type - der
  MIME-Whitelist-Bucket (nur Bilder) verweigerte ihn still. Migration
  088 erlaubt audio/mp4 (+mpeg); der Upload setzt jetzt explizit
  `audio/mp4`. Zusätzlich schreibt "Profil bearbeiten" die
  Intro-Felder nur noch, wenn sie geändert wurden (kein
  Stale-Null-Overwrite aus veralteten Screen-Zuständen).

- **„Bad state: DataChannel nicht verbunden"** (Zufallschat, QR-Chat,
  Ideen-Rad-Vorschläge): Sendungen vor verbundenem DataChannel landen
  jetzt in einer Outbox und werden AUTOMATISCH verschickt, sobald der
  Kanal offen ist (max. 50, pro Chat-Session, kein Transport in den
  falschen Chat).
- **„Dieser Chat existiert nicht mehr" beim Öffnen aus dem Funken-Tab**:
  Server-Matches existierten nur serverseitig; der Chat-Screen lädt sie
  jetzt via `list_my_matches_with_state` lokal nach (gleiche Match-ID,
  P2P-Aufbau danach).
- **Radar startete auf Android 11 nicht**: Beim Radar-Start fehlten die
  Laufzeit-Berechtigungen komplett. Jetzt Pre-Flight: Android ≤ 11
  STANDORT (Pflicht für BLE-Scan), Android 12+ BLUETOOTH_SCAN/CONNECT,
  iOS Bluetooth - plus vorhandener Bluetooth-Prompt.

- **QR-Scan öffnete nur ein „Fenster" statt des Chats**: Der Scanner
  navigierte zur PARTNER-ID (`/chat/<peerId>`), der Chat-Screen suchte
  aber nach der lokal generierten MATCH-ID → „Dieser Chat existiert
  nicht mehr". Jetzt wird mit der Match-ID navigiert
  (`findOrCreateMatch` liefert das Match), Regressionstests ergänzt.
- **QR-Kontakt hieß "Unbekannt"**: Nach dem Scan wird das echte
  Profil (Name, Alter, Interessen, Vorstellung) via
  `get_public_profile` geladen und der lokale Kontakt befüllt - auch
  nachträglich im Chat-Screen (Fallback, falls der Scan offline war).
- **Empfangender Like konnte die Vorstellung nicht anhören**: Der
  Chat zeigt jetzt eine Vorstellungs-Karte (Text + Audio-Player) für
  BEIDE Seiten; im „Erhalten"-Tab bleibt der Player (solange das
  Profil eine Audio-Vorstellung hat).

- **QR-Scan = erstmal nur Like** (kein sofortiger Chat): Online entsteht
  der Chat erst, wenn die gescannte Person annimmt (Funken-Tab
  „Erhalten"). Offline wird das Profil lokal gespeichert (max. 5) und
  das Like beim späteren Öffnen des Chats automatisch nachgeholt.
- **Radar-Verlassen**: Dialog „Radar laufen lassen?" (Stoppen/Weiter-
  laufen) mit Merk-Checkbox „zukünftig automatisch so beibehalten".

### Geändert

- **KEINE Streaks**: Flamme mit Tageszähler ("Funke-Streak") aus Chat-
  AppBar und Funken-Liste entfernt, Widget gelöscht.
- **Chat zuerst, Quiz später**: Match-Kacheln im Funken-Tab öffnen
  IMMER den Chat (vorher direkt das Quiz); das Quiz-Gate blockiert
  Text/Bild/Sprachnachricht/Anruf nicht mehr - es schaltet
  ausschließlich das Profilfoto frei (weiterhin serverseitig
  erzwungen via match-media). Banner im Chat verweist aufs Quiz.
- **P2P-Fehler entschärft**: Wenn die andere Seite (noch) nicht im
  Chat ist, erscheint keine rote Fehlermeldung mehr - der orange
  E2E-Badge zeigt "Verbindung wird aufgebaut".
- **Push bei erhaltenem Like** (QR-Scan): `notify-user` unterstützt
  das Kind `likes` (fixer Server-Text, Like-Beziehungsprüfung,
  Einzel-Schalter `notify_likes` respektiert).

### Neu

- **Mehrere Profilbilder (max. 3, abgerundet-rechteckig)**: Im Profil
  bis zu drei Bilder (primäres + 2 zusätzliche), Anzeige abgerundet
  rechteckig statt rund; Entfernen per Knopf, Upload bleibt lokal
  NSFW-geprüft und verschlüsselt (Slot 0 bleibt match-media-kompatibel
  unter avatar.jpg).
- **"Ich suche"-Reziprozität (Migration 088)**: Wer NACH FREUNDEN
  sucht, findet nur Personen, die ebenfalls Freunde suchen - und
  umgekehrt; Freunde-Sucher bekommen im Chat KEINE Date-Vorschläge
  (Meet-Intent + Ideen-Rad ausgeblendet).
- **Transit Spark: 2-Stunden-Ruhezeit**: Gesehene Geräte bleiben nach
  dem Radar-Ende 2 Stunden sichtbar (zum Nachschauen/Anschreiben in
  Ruhe); Button "Gesehene Geräte ansehen (2 Stunden)" unten auf der
  Radar-Seite. Die eigenen Presence-Tokens bleiben weiterhin sofort
  entfernt (Privacy).

- **Personalisierte Quiz-Fragen (Migrationen 086 + 087, ohne LLM)**:
  `start_quiz_attempt` zieht bevorzugt Fragen aus dem PARTNER-Profil:
  - **Lückentext aus der Vorstellung (087)**: „Vorstellung von Anna:
    ›Ich verbringe mein Wochenende gern ___.‹ Welches Wort gehört in
    die Lücke?" – korrekt = echtes Wort ihrer Vorstellung, Ablenker =
    weitere Worte aus derselben Vorstellung (mit Präfix-Guard gegen
    film/filme-Fallen); Stoppwörter werden gefiltert, Intro-Änderung
    verwirft veraltete Fragen, Best-Effort mit Fallback-Kette.
  - „Welches dieser Interessen gehört zu <Name>?" und „Wie alt ist
    <Name>?" (086).
  - Deterministisch aus (Match, Versuchszahl) generiert, damit BEIDE
    dieselbe Frage bekommen; korrekte Antwort bleibt serverseitig,
    Optionen werden wie bisher pro Match gemischt. Fällt nichts an,
    greift der generische Pool (075). Bewusst KEIN Cloud-LLM
    (Datenschutz: die Vorstellung verlässt den Server nicht) – ein
    lokales Modell am Gerät könnte die Antwort ohnehin nicht
    cheatsicher erzeugen.
- **Neues Design für Sprachnachrichten im Chat**: Play/Pause-Knopf,
  Wellenform (deterministische Balken aus der Message-ID - beide
  Seiten sehen dieselbe Form), Fortschritt-Färbung und Dauer; nach
  dem Anhören wird die entschlüsselte Datei gelöscht (M-17) und der
  Zustand „angehört" verständlich angezeigt.
- **Gespeicherte Profile (max. 5, lokal)**: QR-Kontakte sind jetzt
  PERSISTENT (AES-256-verschlüsselt, SecureHive) - gescannte Profile
  überleben den App-Neustart, damit man sie später anschreiben kann,
  wenn man unterwegs kein Internet hatte. Maximum 5 (kein stilles
  Verdrängen: beim Scan öffnet ein Auswahl-Dialog zum Löschen),
  einzeln löschbar (Funken-Tab „Gespeicherte Profile" + Lesezeichen-
  Aktion im Profil-Detail). Profil-Updates (Name/Vorstellung nach dem
  Online-Fetch) werden sofort persistiert; offline gescannte Kontakte
  bleiben „Unbekannt" und laden ihren Namen automatisch, sobald
  wieder Internet da ist.

## 0.9.1 – Nachtrag (Build 29, 2026-09-25)

- **Umbenennung WispDating zu Thestia**: neue App-ID `com.thestia.app`.
  Neuinstallation noetig, **Konto und Daten bleiben erhalten**. Passkeys
  sind an die alte Domain gebunden und mussten neu angelegt werden
- **Chat-Hintergruende**: Muster (Punkte, Linien, Herzen, Sterne, Wellen)
- **Willkommens-Screen** nach der E-Mail-Bestätigung
- **Pausiert-Hinweis**: bei pausiertem Profil zeigt "Aktuelles" einen
  Hinweis
- **Benachrichtigungs-Herz** in der Statusleiste
- **Neue Kontaktwege**: Bug-Reports und Bild-Meldungen
- **Neue Adressen**: `thestia.de` (App-Links, Bestaetigungs-Mails)
- **Betrieb**: FCM läuft über ein neues Firebase-Projekt
- **Offen geblieben**: das Mindest-Build-Gate war für 29 vorgesehen,
  wurde aber nicht gesetzt (Migration 076 legte 9 fest). In v0.9.2
  nachgeholt (Migration 130)

## [0.9.0] – Beta – 2026-09-08

Server: Migrationen **080, 081, 082** einspielen (Reihenfolge).

### Neu

- **Transit Spark (Experimentell)** – der Nahbereichs-Funke: „Blicke
  getauscht, sich nicht getraut?" Zwei-Phasen-Architektur: Geräte in
  BLE-Nähe (3–10 m) tauschen anonyme, zufällige Encounter-Tokens aus
  (Phase 1, lokal, 45 Minuten gecacht); tippt später eine Person auf
  „Blicke getauscht" und die andere ebenfalls, matcht der Server die
  Tokens (Phase 2, asynchron – auch Stunden später).
  - Matching per SECURITY-DEFINER-RPC `match_proximity_spark`: Token-
    Overlap + alterskompatibel + nicht blockiert → gegenseitige Likes
    erzeugen den Funke über die Bestandspipeline (Match + Push
    „Neuer Funke" automatisch)
  - **Merkmal-Tags**: 1–3 Merkmale (z. B. schwarzer Hoodie, Lanyard)
    schärfen das Matching – serverseitig auf einen festen Katalog
    whitelisted, keine Freitext-Daten (082)
  - **Modus-Wahl**: „Bahn/Café" vs. „Messe/Event" – im Messe-Modus
    zählen nur starke BLE-Signale (echter Sichtkontakt; clientseitig)
  - Token-Rotation alle 10 Minuten, Rate-Limit (1 Signal / 2 min),
    Radar-Stop jederzeit, Daten-Cleanup (45 min Fenster / 24 h Cron)
  - Radar-Screen zweisprachig (DE/EN): Countdown, Encounter-Zähler,
    Tag-Auswahl, Match-Dialog
- **Entdecken-Seite neu strukturiert**: Modi nach Zweck gruppiert –
  „Menschen kennenlernen" (Find your Match, Dating Hour), „Direkt
  verbinden" (Zufallschat), „Unterwegs" (QR-Code, Transit Spark) –
  mit NEU-Badge für frische Modi.
- **Onboarding als Interview**: Thestia stellt Fragen statt eines
  Formulars – eine Frage pro Screen in Chat-Optik (Sprechblase, warmer
  Ton), dezente Fortschritts-Dots, alles überspringbar. Keine neuen
  Datenpunkte, kein Belohnungs-Mechanismus; komplett zweisprachig.

### Geändert

- **public_profiles-View ersetzt (Option A, 080)**: Fremde Profil-
  Lesezugriffe laufen ausschließlich über die SECURITY-DEFINER-Funktionen
  `get_public_profile`/`get_public_profiles` – löst den wiederkehrenden
  Advisor-Befund „security_definer_view". Die View bleibt im Doppel-
  betrieb für Alt-Clients bestehen (Entfernung in Folgemigration).

## [0.8.0] – Nachtrag 2 – 2026-09-07

Server: Migrationen **066** (falls fehlend), **074, 075, 076, 077, 078**
einspielen; Gegenprobe mit `supabase/check_columns.sql`.

### Neu

- **Profilbilder Ende-zu-Ende-verschlüsselt**: Avatare werden VOR dem
  Upload clientseitig per AES-256-GCM verschlüsselt (Zufalls-Schlüssel
  pro Bild) - der Server sieht ausschließlich Ciphertext. Der Schlüssel
  steckt im `photos`-Eintrag (`pfad|key|iv`); jeder berechtigte
  Betrachter entschlüsselt lokal. Alte, unverschlüsselte Avatare
  bleiben lesbar (AvatarCrypto, Migration 077)
- **Profilbilder serverseitig**: Die `photos`-Spalte existierte
  serverseitig bisher gar nicht (Avatare waren rein lokal!). Neu:
  Migration 077 (Spalte + öffentlicher View), Upload-Referenz wird
  verifiziert gespeichert, `fetchOwnProfile` lädt sie zurück - das Bild
  übersteht Neuinstallationen und ist im öffentlichen Profil sichtbar
- **NSFW-Prüfung on-device wirklich aktiv**: Der still außer Kraft
  gesetzte Check funktioniert jetzt - die gebündelte Modell-Datei
  nutzte ONNX-IR-Version 10 (Runtime unterstützt max. 9, gepatcht),
  der Output-Tensor brauchte Batch-Dimension-Flattening und die
  Pixel-Vorverarbeitung die vom Modell erwartete 0-255-Skalierung.
  Neuer permanenter Test (`image_safety_model_test.dart`) führt echte
  Inferenz aus und verhindert Still-Ausfälle. Klassen-Reihenfolge
  [NSFL, NSFW, SFW] gegen die Modell-Doku verifiziert
- **Profilbild-Änderung mit Speichern-Dialog**: Bildauswahl läuft jetzt
  wie alle anderen Angaben über den Dirty-Flag - lokale Vorschau,
  Upload erst beim Speichern, Abbrechen verwirft (das Bild war nie auf
  dem Server); NSFW-Check erfolgt bereits bei der Auswahl
- **Migrationen-robuste Daten-Sync** (Fix „App merkt sich nichts mehr"):
  Profil-Laden zweistufig (mit/ohne 077-Spalten), alle Profil-Writes
  selbstheilend (PostgREST „missing column" wird automatisch aus dem
  Body entfernt), Präferenz-Laden dreistufig inkl. Theme (`theme_name`
  bleibt erhalten) - eine fehlende Spalte kann nie wieder Name, Bio,
  Theme oder Radius gemeinsam auslöschen
- **Sync-Fehler sichtbar**: Profil-Speichern zeigt im SnackBar die
  genaue Server-Fehlerursache (z. B. fehlende Migration), statt still
  „ohne Sync" zu melden; `supabase/check_columns.sql` als
  Spalten-Diagnose für den Server
- **Pausenmodus in die Profil-Sichtbarkeit integriert** (Dopplung
  aufgelöst): „Wer kann mein Profil sehen?" ist jetzt DIE eine Steuerung
  - Jeder / Nur Funken / Unsichtbar (Pausiert) mit Bestätigungsdialog;
  der frühere separate Schalter ist entfernt, `paused` bleibt
  konsistent abgeleitet (auch über Server-Sync)
- **Chat-Verlauf: drei Modi** statt fester 200er-Grenze: Aus /
  200 Nachrichten / Kompletter Verlauf (Standard), verschlüsselt
  (AES-256, SecureHive)
- **Angemeldete Geräte mit echtem Modell**: `device_info_plus` liefert
  Hersteller + Modellkennung (z. B. „Samsung SM-S921B") - nach
  Neuinstallation ist das „zweite Gerät" eindeutig zuordenbar
  (auth_devices.device_model, Migration 078)
- **Vollständige Zweisprachigkeit in neueren Bereichen**: Farbschemata
  (Ozean→Ocean u. a.), Stimmungs-Chips, Entdecken-Modi und
  Sichtbarkeits-Optionen sind jetzt zweisprachig; Sichtbarkeits-Optionen
  haben Untertitel-Erklärungen
- **Konsequente „Funken"-Sprache**: Alle verbliebenen deutschen
  „Match"-Formulierungen heißen „Funke(n)" (u. a. „Neuer Funke!",
  „Funke bestätigen", Dating-Hour-Texte, Datenschutzhinweise);
  „Discovery" heißt auf Deutsch „Entdecken"
- **Abgerundete Klick-Animation**: Der Ripple folgt global der
  24-px-Kartenrundung (ListTileTheme in Light + Dark)

### Behoben

- `public_profiles`-View: Migration 077 hing an Postgres'
  Append-Regel für Views („cannot change name of view column") -
  `photos` steht jetzt korrekt am Ende der Spaltenliste

## [0.8.0] – Nachtrag (Build 12) – 2026-09-05

### Neu

- **Dating Hour über 20 hinaus**: 20 ist nur das MINDESTZIEL - der
  Teilnehmer-Zähler nennt jetzt die echte Gesamtzahl („Mindestziel
  erreicht: 37 Teilnehmer!"), mit Hinweis, dass mehr beliebig möglich
  ist; serverseitig gab es nie ein Limit
- **Chat-Export & -Import (Gerätewechsel/Reinstall)**: Der Datenexport
  enthält jetzt (bei aktivem verschlüsseltem Verlauf) die Chat-
  Nachrichten inkl. QR-Kontakte; der Import stellt Chats mit
  ORIGINAL-Match-IDs wieder her und aktiviert die Persistenz implizit
- **Kleinere APKs / AAB**: build_release.ps1 mit `-SplitPerAbi`
  (pro-CPU-APKs: arm64 77 MB statt 167 MB) und `-Aab` (Play-App-Bundle)

## [0.8.0] – 2026-09-05

Geschmack & Matching: der große Feature-Meilenstein (Roadmap 0.8.0).
Server: Migrationen **074** + **075** einspielen.

### Neu

- **Musik-Geschmack**: Im Profil-Editor Genres wählen, die man mag
  (Mehrfachauswahl, inkl. „Instrumental") - und freiwillig solche, die man
  explizit nicht mag. Der Geschmack fließt mit 30 % in den Verbindungs-
  Score ein (Gemeinsamkeiten positiv, Konflikte negativ), ist im
  eigenen Profil sichtbar und wird im Profil anderer mit hervorgehobener
  „Gleicher Geschmack"-Anzeige angezeigt (Migration 074)
- **Verbindungs-Score sichtbar**: Find-your-Match-Kandidaten zeigen jetzt
  „Match: X %" - serverseitig berechnet aus Distanz (40 %), gemeinsamen
  Interessen (30 %) und Musik (30 %); die Kandidaten sind danach sortiert
- **Pausenmodus**: Das eigene Profil lässt sich pausieren (Einstellungen)
  - unsichtbar in Discovery und Find-your-Match, bestehende Funken und
  Chats bleiben bestehen (profiles.paused, Migration 076)
- **Habit-Dealbreaker**: Schalter im Profil-Editor - nur noch Kandidaten,
  deren Konsum (Rauchen/Alkohol/Drogen) maximal so hoch ist wie der
  eigene; serverseitig im Matching erzwungen (profiles.habits_dealbreaker,
  Migration 076)
- **Kleinere APKs / AAB**: `build_release.ps1` unterstützt jetzt
  `-SplitPerAbi` (pro-CPU-APKs, ~77 MB statt 167 MB) und `-Aab` (Play-
  App-Bundle); die nativen Bibliotheken sind sonst dreifach enthalten
- **Mindestversions-Gate**: app_config.min_app_version_build - Clients
  unterhalb der Mindestversion zeigen beim Start einen Update-Screen
  (mit Rückfallebene „Trotzdem fortfahren"), Migration 076
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim
  nächsten Start fragt die App, ob ein Report über den Bug-Report-Kanal
  gesendet werden soll (datenschutzfreundlich statt Cloud-Crashlytics,
  nichts verlässt das Gerät ohne Bestätigung)
- **Verschlüsselter Chat-Verlauf (Opt-in)**: Einstellungen → Sicherheit
  im Chat - speichert die letzten 200 Nachrichten pro Chat AES-256-
  verschlüsselt via SecureHive (Key im Keystore); Standard bleibt
  reiner Arbeitsspeicher (N-8-Design bleibt, jetzt als bewusste Wahl)
- **Kontext-Icebreaker**: Gemeinsame Interessen erscheinen als
  Vorschlags-Chip im Chat (vom Nutzer deaktivierbar über das Chat-Menü)
- **E-Mail- und Passwort-Wechsel in-app** (Datenschutz & Account): mit
  Re-Auth per aktuellem Passwort; E-Mail-Wechsel mit Bestätigungs-Links
  an beide Adressen
- **Daten-Import**: JSON-Datenexport kann wieder eingespielt werden
  (Profil, Einstellungen, Präferenzen)
- **Meldungs-Feedback**: Safety Center zeigt eigene Meldungen mit Status
  (list_my_reports, Migration 076)
- **Blockierliste**: Safety Center listet blockierte Nutzer mit
  Entblocken-Button (list_blocked_users, Migration 076)
- **Inaktive Funken als „Erschlossene Funken"**: Gekühlte Verbindungen
  rutschen still an das Ende des Interessen-Feeds - ohne Countdown, ohne
  Ablauf-Benachrichtigung, ohne Verlängerungsdruck (Migration 074)
- **Re-Funke ohne Druck**: Gekühlte Verbindungen mit einem Tap wieder
  entzünden (RPC respark_match) - jederzeit, ohne Frist
- **Chats verwalten**: Im Funken-Feed „Verwalten" antippen, Chats
  mehrfach auswählen und aus der eigenen Liste entfernen (nur für mich,
  RPC hide_match) - einzeln oder alle auf einmal
- **Ehrliches Beenden**: „Funke beenden" zeigt jetzt vorbereitete,
  freundliche Absage-Texte zur Wahl - oder „Ruhig enden lassen" (ohne
  Nachricht). Ghosting aktiv erschweren (RPC cool_match)
- **Ideen-Rad im Meet-Intent** (Test): „Dreh das Rad" wählt aus den
  bestehenden Date-Kategorien einen Vorschlag, der als E2E-Nachricht
  geteilt und im Chat bestätigt wird
- **Dating Hour: Frage-Karten für Schüchterne**: Drei thematische sanfte
  Fragen (Reise/Alltag/Träume, rotieren pro Stunde) - ein Tap übernimmt
- **Quiz-Fragen-Pool**: 60 echte Fragen ersetzen die 5 Platzhalter
  (Migration 075, idempotent); die korrekte Antwort rotiert über die
  Optionspositionen
- **UI-Einstellungen serverseitig**: Blind Mode, Foto-Freigabe,
  Sichtbarkeit, Dark Mode, Benachrichtigungs-Schalter und Bild-Blur
  werden in profiles.ui_prefs gespiegelt (Migration 074) und nach
  Neuinstallation/Login wiederhergestellt - sensible Inhalte (Chats,
  E2E-Identität) bleiben ausgenommen

### NSFW on-device (Scaffold)

- **Lokale Bildmoderation implementiert** (Migration-frei, Paket
  `onnxruntime` 1.4.1): Der neue `ImageSafetyService` lädt
  `assets/models/image-safety-classifier-xs.onnx` lazy (OrtEnv + Session
  einmalig), preprocesset gemeldete Bilder auf 224x224 RGB (NCHW-Float32,
  0..1) und klassifiziert rein on-device in die Klassen
  [NSFL, NSFW, SFW] (inkl. Softmax-Fallback bei Logits)
- **Human-in-the-Loop im Meldedialog**: Die lokale Prüfung startet erst
  mit dem Öffnen des Meldedialogs (niemals beim Senden/Empfangen, E2E
  bleibt unangetastet); das Ergebnis wird transparent angezeigt
  (Warnung ab 0.65 für NSFW/NSFL, sonst neutrale Bestätigung); Übertragung
  erfolgt NUR nach aktivem Tippen auf "Meldung absenden" - Abbruch
  verwirft das Bild aus dem Speicher
- **Report-Payload erweitert**: letzte 3 Textnachrichten als Kontext,
  SHA-256-pseudonymisierte Reporter-ID und das lokale KI-Ergebnis gehen
  mit; KEINE automatischen Kontosperren (manuelles Team-Review)
- **Noch offen**: die Modell-Datei selbst muss in
  `assets/models/image-safety-classifier-xs.onnx` abgelegt werden (Fehlt
  sie, deaktiviert sich die lokale Prüfung automatisch und der
  serverseitige Fallback-Scan aus 0.7.1 greift)
- Offen ist außerdem der i18n-Rest (zweisprachige Screens)

## [0.7.3] – Nachtrag (Build 9) – 2026-09-05

### Neu

- **Ladekreis bei der Passkey-Anmeldung**: Die Passwort-Anmeldung zeigt
  seit 0.7.3 direkt nach dem Tap den großen, nicht-abwischbaren
  „Anmeldung läuft…"-Kreis - der Passkey-Pfad zeigt ihn jetzt genauso
- **Suchradius wird zuverlässig gespeichert (wie der Name)**: Regler-
  Änderungen (Entfernung, Altersspanne, Suchradius-Modus) werden jetzt
  entprellt (1,5 s) automatisch serverseitig gesichert - auch ohne
  Speichern-Knopf; „Speichern" wartet auf den Server-Sync und meldet
  einen Fehlschlag klar statt still zu schlucken
- **Scroll-Hinweis auf der Profil-Seite**: dezenter, design-passender
  „Strich" am rechten Rand zeigt, dass die Seite weiter nach unten geht
  (Profil-/Bug-melden-Buttons waren ohne Scrollen unsichtbar); er
  blendet sich am Seitenende aus

### Behoben

- **„Server-Sync fehlgeschlagen" beim Profil-Speichern (Ursache)**: Die
  Schreib-Verifikation las zur Kontrolle die VOLLSTÄNDIGE Flags-Zeile -
  fehlte nur EINE andere Spalte auf dem Server (z. B. 071 nicht
  eingespielt), scheiterte jede Verifikation und damit jeder Speicher-
  vorgang. Jetzt wird gezielt nur der geschriebene Schlüssel zurückgelesen;
  ist allein die Kontrolle nicht möglich (Schema/Netz), gilt der Schreib-
  vorgang als erfolgt. Zusätzlich Fallbacks beim Laden: Präferenzen/Flags
  kommen auch dann zurück, wenn 071-Spalten fehlen (dann ohne Theme)
- **Profildaten nach Passkey-Anmeldung leer**: Der Passkey-Pfad lief
  früher NUR über den GoTrue-Event-Listener und übersprang die Nachläufe
  der Passwort-Anmeldung - Token-Persistenz, das Setzen der Signal-User-ID
  und der explizite Server-Sync (Profil, Präferenzen, Flags) fehlten, so
  dass Name & Co. nach der Anmeldung leer blieben. Die Passkey-Anmeldung
  läuft jetzt über [AuthNotifier.loginWithPasskey] mit IDENTISCHEM Ablauf
  wie die Passwort-Anmeldung; die Demo-Implementierung weist den Flow
  erwartungsgemäß ab
- **Fehlalarme der Schreib-Verifikation bei Listen-Spalten**: Der
  Zurücklesen-Vergleich in updateSetupFlagsAndVerify ist jetzt
  typensicher (PostgREST liefert List<dynamic>, der Client
  List<String>) - vorher gab es 3 unnötige Schreibversuche und ein
  „fehlgeschlagen", obwohl gespeichert war
- **Geräte-Liste: Reparatur-Skript** `supabase/repair_auth_devices.sql`
  (idempotent, mit Prüf-Report: Tabelle/RLS/Policies) für Fälle, in
  denen 071 teilweise eingespielt wurde; Gerätename korrekt formatiert
  (z. B. „Android (SDK 34)")

## [0.7.3] – Nachtrag (Build 8) – 2026-09-05

### Behoben

- **Passkey-Registrierung (Ursache definitiv identifiziert)**: In den
  „Relying Party Origins" des Servers standen SHA-1-Fingerprints (20 Byte)
  der Signatur-Keys - `android:apk-key-hash` verlangt SHA-256 (32 Byte),
  der Abgleich konnte nie matchen. Fix ist serverseitig (Dashboard Origins
  ersetzen - exakte Werte in `docs/PASSKEYS_SERVER_SETUP.md`), die App
  unterstützt die Diagnose: Debug-Builds loggen jetzt den gesendeten
  WebAuthn-Origin, die Fehlermeldung verweist auf die Setup-Doku

### Server

- Migration **073** (Härtung `auth_devices`): Längen-Constraints für
  client-gesetzte Werte + Cap von 20 Geräte-Einträgen pro Konto
  (Trigger mit Upsert-Schonung, gehärteter `search_path`)

## [0.7.3] – Nachtrag (Build 7) – 2026-09-05

### Behoben

- **Speichern-Nachfrage im Profil-Editor (Tab-Wechsel) endgültig
  repariert**: Die Bottom-Navigation ermittelte die aktive Unter-Route
  über den Router-Delegates-Kontext - das blieb je nach Zeitpunkt stumm.
  Der Schutz prüft jetzt direkt den Dirty-Flag (der Editor setzt ihn beim
  Verlassen zurück); Widget-Tests verifizieren Textfeld-, Regler- und
  PopScope-Verhalten
- **Geräte-Liste: Fehler sichtbar statt stummer Abbruch**: Fehlgeschlagene
  Registrierung/Listung zeigt jetzt die bereinigte Ursache (Tabelle fehlt
  = Migration 071 fehlt, RLS, Netz, Sitzung) als Hinweis über der Liste
  bzw. als klarer Fehlerzustand
- **Passkey "Der Server konnte den Passkey nicht bestätigen"**: Die
  Meldung verweist jetzt auf die neue Verwaltung; vor dem Anlegen wird
  transparent auf bereits existierende Passkeys hingewiesen (deren
  Alt-Einträge die Registrierung blockieren können)

### Neu

- **Passkeys verwalten** (Einstellungen): Listet alle am Konto
  registrierten Passkeys (Name, erstellt, zuletzt genutzt) und erlaubt
  Umbenennen/Löschen - damit lassen sich Alt-/Defekt-Einträge entfernen,
  wenn der Server eine NEUE Registrierung nicht bestätigt
- **Server**: Migration 072 konsolidiert die öffentliche Profil-View
  (`public_profiles`, bewusster Definer-Modus - Datenschutz: exakte
  Geburtsdaten/Koordinaten bleiben serverseitig) und dokumentiert den
  Advisor-Befund als intentional; Migration 071 bleibt Voraussetzung für
  die Geräte-Liste

## [0.7.3] – Nachtrag (Build 6) – 2026-09-05

Neue Funktionen und Reparaturen (Konto-Datenhalt, Geräteübersicht, Regler).

Hinweis: Die Roadmap-Punkte für 0.8.0 (Geschmack & Matching, Musik-Genres,
on-device-Moderation, i18n-Ausbau) sind hier NICHT enthalten - diese Version
bleibt ein 0.7.x-Patch/Polish-Release.

### Neu

- **Angemeldete Geräte** (Einstellungen → Datenschutz & Account): Zeigt alle
  Geräte, auf denen das Konto eingeloggt ist (Gerätename, App-Version,
  letzte Aktivität, eigenes Gerät markiert). Mit einem Tastendruck meldet
  man sich ÜBERALL außer auf dem aktuellen Gerät ab
  (`signOut(scope: others)`; Migration 071 mit `auth_devices`-Tabelle,
  RLS-gesichert)
- **Themefarbe gehört zum Konto** (Migration 071, `profiles.theme_name`):
  Die Farbschema-Wahl wird serverseitig gespeichert und direkt beim Login
  wieder angewendet - auch nach einer App-Neuinstallation
- **Entfernung & Alter überstehen Neuinstallation**: Die maximale
  Entfernung wird zusätzlich in die App-Einstellungen gespiegelt (z. B.
  Dating-Hour-Filter), die Altersspanne kommt weiterhin aus dem Profil -
  beide werden nach Login/Neuinstallation serverseitig wiederhergestellt

### Behoben

- **Altersspannen-Regler eingefroren ("18-18")**: Die Regler für
  Mindest-/Höchstalter verwendeten die aktuell gewählten Werte als
  Slider-Grenzen - bei 18-18 war der Spielraum null, die Regler ließen
  sich nicht bewegen und wirkten ausgegraut. Jetzt sind es zwei gekoppelte
  Slider mit den statischen Sicherheitsgrenzen (16-99), die sich beim
  Ziehen gegenseitig mitnehmen - im Profil-Editor, in der Einrichtung und
  in den Dating-Hour-Präferenzen (gemeinsames Widget `AgeRangeSliders`,
  der dortige RangeSlider frohr bei identischen Werten ebenfalls ein)
- **Speichern-Dialog im Profil-Editor erschien nie bei Reglern/Dropdowns**:
  Änderungen an Geburtsdatum, Altersspanne, Entfernung, Suchradius-Modus
  und Bundesland-Filter lösten die "Ungespeicherte Änderungen"-Nachfrage
  nicht aus (und wurden still übernommen). Jetzt führt jede dieser
  Änderungen zur Nachfrage; "Verwerfen" setzt die Regler auf den Stand
  beim Öffnen zurück. Auch die Zurück-GESTE fragt jetzt zuverlässig (der
  Dirty-Flag wurde beobachtet statt nur post-frame gesetzt)
- **Weißes Viereck bei Benachrichtigungen behoben (echte Ursache)**: Das
  Notification-Icon wurde vom Branding-Tool ohne Alpha-Kanal erzeugt
  (`Image()`-Default = RGB) - Android zeigte daher ein volles weißes
  Quadrat statt der Herz-Silhouette. Das Icon ist jetzt ein echtes
  RGBA-Asset; beide Icon-Tools sind gegen stillen Alpha-Verlust gehärtet
- **Passkey-Erstellen: "Anfrage abgebrochen von Thestia" / "credential
  verification failed"**: Der Plugin-Authenticator brach vor JEDER
  Zeremonie eine laufende Operation ab - das konnte die eigene neue
  Anfrage mit abwürgen. Thestia nutzt jetzt einen eigenen Authenticator ohne
  dieses Vorabbrechen, plus Doppel-Tap-Schutz an der Kachel und im
  Service (nur eine Zeremonie gleichzeitig). Server-"Verifikation
  fehlgeschlagen" bekommt eine verständliche Meldung mit Lösungshinweis
- **"Speichern fehlgeschlagen"-Fehlalarme bei Präferenzen**: Die
  Schreib-Verifikation las die Präferenz-Spalten beim Zurücklesen nicht
  (`max_distance_km`, `age_range_min/max`, ...) - das Speichern von
  Entfernung/Altersspanne wurde deshalb IMMER als fehlgeschlagen gemeldet,
  obwohl es geschrieben war
- **Dating-Hour-Regeln erscheinen nur noch EINMAL** (Migration 071,
  `profiles.dating_hour_intro_seen`): Der Intro-Flow (Regeln + Erklärung)
  hängt jetzt am Konto statt am Gerät - nach Neuinstallation/Neu-Anmelden
  kommt er nicht wieder

## [0.7.3] – 2026-08-30

Fix-Release: Usability und Stabilität.

### Behoben (Nachtrag +4)

- **2FA-Status zuverlässig**: Der MFA-Status wird beim Laden mit
  Session-Auffrischung und Wiederholung versucht - die Einstellungs-Kachel
  und der MFA-Screen zeigen den echten Stand (vorher: „nicht eingerichtet"
  trotz aktiver 2FA, wenn der Status-Abruf fehlschlug)
- **Passkey-Anlegen bei aktiver 2FA mit klarer Meldung**: Existiert schon
  ein verifizierter Faktor, erscheint jetzt „2FA ist für dieses Konto
  bereits aktiviert." statt einer kryptischen Ablehnung
- **„Später erinnern" schließt die 2FA-Seite** statt sie endlos neu zu
  öffnen (PopScope-Sperre wurde vom programmatischen Verlassen nicht
  aufgehoben)
- **Profil-Editor: Tab-Wechsel fragt zuverlässig** - Reine Textfeld-
  Änderungen lösten keinen Rebuild aus, der Dirty-Flag blieb dadurch false
  und die Nachfrage beim Tab-Wechsel unterblieb (Listener halten ihn jetzt
  synchron); der Zurück-Button im AppBar fragt ebenfalls explizit
- **Altersspanne 18-18 jetzt erhöhenbar** - Die RangeSlider ließ bei
  identischen Werten nur den unteren Regler greifen; im Profil-Editor sind
  es jetzt zwei getrennte Regler (Mindest-/Höchstalter), die sich beim
  Verschieben gegenseitig mitnehmen
- **Passkey-Fehler transparent**: Bei einer Server-Ablehnung wird jetzt
  der kurze Server-Grund in der Meldung mit angezeigt (z. B. "AAL2
  required") - für die Ursachensuche statt einer pauschalen Ablehnung
- **Profil-Editor: Tab-Wechsel zuverlässig erkannt** - Die Nachfrage nach
  ungespeicherten Änderungen griff beim Reiter-Wechsel nicht, weil die
  Route-Erkennung im Shell-Kontext die Unterseite nicht sah (jetzt über
  die volle URI gelöst)
- **Alle Dropdowns abgerundet** - Die fünf Dropdowns im Profil-Editor
  (Geschlecht, „Was suchst du?", Land, Bundesland, Suchradius-Modus)
  folgen jetzt ebenfalls der 16-px-Rundung
- **Dating-Hour-Meldung präzisiert**: „Präferenzen gespeichert. Deine
  Teilnahme meldest du über ‚Ich bin dabei' am Event-Tag an." (statt der
  verwirrenden Formulierung „Du bist noch nicht angemeldet")

### Behoben

- **Automatische Abmeldung nach Stunden behoben**: Der Session-Token läuft
  nach ~1 h ab; war die App länger im Hintergrund, schlug der einzige
  Auffrischungsversuch beim Öffnen fehl und man war ausgeloggt - obwohl
  „Angemeldet bleiben" aktiv war. Jetzt wird beim Start mehrfach mit
  Pausen aufgefrischt; nur bei echtem Token-Verlust bleibt man
  ausgeloggt
- **Passkey-Erstellen trotz 2FA**: Der 2FA-Status wurde aus einem Cache
  gelesen, der veraltet oder nie geladen war - dadurch griff die 2FA-
  Bestätigung vor dem Anlegen nicht und der Server lehnte ab. Jetzt wird
  der Status frisch geladen
- **2FA-Anzeige**: Die Einstellungs-Kachel zeigt den aktuellen 2FA-Stand
  jetzt beim Antippen frisch vom Server (vorher konnte ein alter/leerer
  Stand angezeigt werden)
- **Benachrichtigungs-Symbol**: Das Statusleisten-Icon war praktisch leer
  (nur ~300 weiße Pixel aus einer zu sparsamen Logo-Rampe). Jetzt eine
  klare Herz-Silhouette
- **Dating-Hour-Zeit: Fallback gehärtet** - Schlägt der Abruf der
  Serverzeit beim Start/bei App-Rückkehr fehl, versucht die App es jetzt
  mehrfach mit Pausen (vorher: sofortiger Fallback auf die lokale
  Gerätezeit, wodurch die Dating-Hour-Anzeige von der Geräte-Zeitzone
  abhing). Das Warn-Banner bleibt solange sichtbar, bis eine Serverzeit
  verifiziert ist; die harte Beitritts-Prüfung läuft unverändert
  serverseitig
- **Zurück-Geste in der Dating Hour**: führt jetzt jeweils zur Seite
  davor (z. B. von den Präferenzen zurück zum Event) statt zur
  Haupt-Navigation
- **Altersspanne im Profil-Editor ergänzt** (fehlte dort komplett, mit
  altersbasierter Klemmung wie in der Einrichtung)
- **Ladekreis direkt nach dem Anmelde-Klick**: Nicht-abwischbarer
  Ladekreis („Anmeldung läuft…") erscheint sofort, damit keine tote Phase
  entsteht

### Hinzugefügt

- **Dating Hour: Teilnehmer-Fortschritt** (Migration 068): „X von 20
  Teilnehmern" mit Fortschrittsbalken im Event-Screen - man sieht, ob das
  Ziel erreicht ist und wie viele noch fehlen

## [0.7.2] – 2026-08-28

Dating-Hour-Release: Zeit-Fix, Fairness-Regeln und Admin-Polish.

### Hinzugefügt

- **Dating Hour: Mindestteilnehmer** – Erst ab 20 angemeldeten Personen
  startet das Event; darunter fällt es aus (klare Meldung im Event-Screen)
  und die Regeln-Karte weist darauf hin
- **Dating Hour: keine Partner-Dopplungen mehr** – Das Matching bevorzugt
  Personen, mit denen es noch NIE eine Dating-Hour-Session gab; erst wenn
  keine unbesuchte Kombination übrig ist, wird wiederholt (Migration 067)
- **Dating Hour: Altersdifferenz-Hinweis** – Liegen mindestens 10 Jahre
  zwischen beiden Chat-Partnern, erscheint ein respektvoller Hinweis-Banner
  im Event-Chat
- **Dating-Hour-Präferenzen bleiben erhalten** – Die zuletzt genutzten
  Präferenzen (Alter, Geschlecht, besonderes Merkmal, Entfernung,
  Gewohnheiten) werden global serverseitig gemerkt (Migration 067) und
  vorbelegen den Präferenzen-Screen – auch nach Neuinstallation
- **Mood of the Day öffentlich** – Die fehlende Server-Infrastruktur
  (Migration 024, idempotent nachgezogen in 067) ermöglicht es nun:
  eigener Mood setzbar und für andere sichtbar
- **Admin-Bereich im App-Look** – Listen jetzt als Karten konsistent zur
  restlichen Nutzeroberfläche

### Behoben

- **Dating Hour startet zur richtigen Zeit** – Die Startzeit war als
  20:00 UTC gespeichert (= 21/22 Uhr deutscher Zeit). Jetzt korrekt
  20:00 Europe/Berlin, mit automatischer Sommer-/Winterzeit-Umstellung.
  Bestehende zukünftige Events werden korrigiert (Migration 067)
- **Admin-Bereich: Blackscreen beim Verlassen behoben** (falscher
  Navigator-Pop auf einer GoRouter-Route)
- **Zurück-Geste in der Dating Hour beendet nicht mehr die App**, sondern
  navigiert zur Haupt-Navigation (gilt für alle Dating-Hour-Screens)
- **Formulierung korrigiert**: „Niemand außer euch beiden kann eure
  Nachrichten lesen (Signal-Protokoll)" statt des sprachlichen Fehlers
- **Passkey-Erstellung mit aktivierter 2FA**: Vor dem Anlegen eines
  Passkeys erfolgt jetzt automatisch die 2FA-Bestätigung – der Server
  verlangt sie, ohne sie schlug die Erstellung mit einer kryptischen
  Ablehnung fehl

## [0.7.1] – 2026-08-26

Polish- und Fix-Release zu 0.7.0 (das nie veröffentlicht wurde): Sprach-
Complettierung, Farbwelt-Rahmen, App-Start-Logo, 2FA-Navigation und
Passkey-Konfiguration.

### Hinzugefügt

- **Bild-Meldungen: Nachweis-Pflicht (Lückenfix)**: Beim Senden eines
  Chat-Bildes wird nur dessen SHA-256-Hash serverseitig registriert
  (Migration 068, niemals das Bild). Eine Meldung wird nur akzeptiert,
  wenn der Hash nachweist, dass dieses Bild tatsächlich zwischen den
  beiden Chat-Partnern geflossen ist - beliebige fremde Bilder können
  nicht mehr untergeschoben werden
- **Dating Hour: konsistente Teilnehmer-Zählung** - Die Mindestteilnehmer-
  Prüfung zählt wie die Anzeige nur Accounts, die mindestens 24 Stunden
  alt sind (Migration 070): kurzlebige Fake-Accounts können das Event
  weder "startbar" machen noch die Fortschrittsanzeige täuschen
- **Präferenzen überleben Neuinstallationen** (Migration 066): Entfernung,
  Altersspanne, "Ich suche" (Beziehungsart), Bundesland-Filter, Ort und
  Geschlechts-Filter werden jetzt zusätzlich serverseitig gespeichert
  (verschlüsselter Transport, RLS-geschützt) und nach der Anmeldung
  automatisch wiederhergestellt - vorher gingen sie bei einer
  Neuinstallation verloren. Gespeichert wird beim Abschluss der
  Einrichtung und beim Speichern im Profil-Editor
- **Admin: Nutzer sperren/entsperren mit Begründung** (versteckter
  Admin-Bereich): Im „Sperren"-Tab gibt es jetzt ein Formular
  (E-Mail oder User-ID + Pflicht-Begründung). Die neue Edge Function
  `admin-ban` (nur für die Admin-ID aufrufbar) hinterlegt die E-Mail in
  der Sperr-Tabelle (blockiert Neu-Registrierung) und sperrt bei Angabe
  einer User-ID zusätzlich den bestehenden Account sofort (Sessions
  ungültig). Optional erhält der Nutzer eine E-Mail mit Begründung und
  Hinweis auf den Entsperrungsantrag. Entsperren per Button in der Liste
- **Bild-Meldung mit KI-Vorprüfung (NSFW, melde-basiert)**: Chat-Bilder
  werden bewusst NIE automatisch beim Senden gescannt (E2E). Erst eine
  Meldung durch den Empfänger prüft exakt dieses eine Bild automatisch
  per NSFW-KI (neue Edge Function `report-image`, NSFW-Klassifikator,
  Token nur als Function-Secret). Der Meldende sieht das KI-Ergebnis
  SOFORT: Bestätigt die KI, gehen Bild, Report und KI-Ergebnis
  automatisch per E-Mail an das Team. Widerspricht die KI, kann der
  Meldende (falls die KI falsch liegt) eine manuelle Prüfung veranlassen -
  auch dann gehen Bild, Report und KI-Ergebnis an das Team. Migration
  064 erweitert photo_moderation um Reporter-/Eskalations-Spalten.
  Der frühere (deaktivierte) Auto-Scan beim Senden wurde entfernt

### Behoben

- **Profil nach Neuinstallation leer behoben (wichtig)**: Der
  Profil-Ladevorgang fragte eine Datenbank-Spalte (mood) ab, die in den
  Migrationen nie existiert hatte - der Abruf schlug dadurch IMMER fehl,
  und nach einer Neuinstallation blieben Name, Bio, Geburtsdatum usw.
  leer (auf dem alten Gerät unsichtbar, weil dort eine lokale Kopie
  lag). Die Spalte ist aus der Abfrage entfernt; der Abruf hat jetzt
  zusätzlich einen Wiederholungsversuch bei Netzproblemen
- **Einrichtung erscheint garantiert NIE wieder (auch nicht kurz)**:
  Neues Gesamt-Flag onboarding_done (Migration 065, mit Rückstandsaufholung
  für Bestandsnutzer): Sobald die Einrichtungskette einmal abgeschlossen
  ist, erzwingt der Router Einstellungen & Privatsphäre und den
  Persönlichkeitstest bei keiner Anmeldung und keiner Neuinstallation
  wieder - unabhängig von übersprungenen Punkten. Zusätzlich: Schlägt der
  Server-Abgleich komplett fehl, erscheint die Einrichtung ebenfalls
  nicht (nur bei einer frischen Registrierung läuft sie natürlich)
- **Sprach-Button wie der Anmelde-Button**: Das Übersetzen-Symbol auf
  Anmelde- und Registrierungs-Screen sitzt jetzt auf einem runden,
  in Primärfarbe gefüllten Button - gleicher Look wie "Einloggen",
  nur rund statt breit
- **Passkey-Diagnose entfernt**: Das Entwickler-Werkzeug ist jetzt auch
  aus dem Debug-Build der Einstellungen raus (Code im Repository bleibt
  für die Fehlersuche erhalten)
- **Doppelte Registrierung abgefangen**: Supabase meldet bei bereits
  registrierter E-Mail keinen Fehler ( Schutz vor E-Mail-Enumeration),
  sondern liefert still den bestehenden Nutzer zurück - die App schickte
  den Nutzer an den "E-Mail bestätigen"-Screen, ohne dass je eine
  Bestätigungs-Mail kam. Jetzt erscheint direkt die Meldung "Diese
  Emailadresse ist bereits registriert" mit Hinweis auf Login bzw.
  Passwort-Reset
- **Ladekreis ab dem allerersten Moment**: Während der Initialisierung
  (bis zu 4 s) war nur das statische Splash-Logo ohne jeden Ladehinweis
  zu sehen. Jetzt erscheint unmittelbar nach dem Start Logo + drehender
  Ladekreis
- **Deutsch funktioniert jetzt überall**: Die App crashte bei gesetzter
  Sprache Deutsch mit "No MaterialLocalizations found" (fehlende
  Lokalisierungs-Delegates) - Login/Registrierung waren unbenutzbar
- **2FA "Später erinnern"**: Ein Sync-Fehler blockierte die Rückkehr aus
  dem "Konto absichern"-Dialog
- **Einrichtung erscheint nicht mehr erneut**: Der Server-Stand wurde nur
  "best-effort" gesichert (stiller Fehlschlag) - jetzt mit sichtbarem
  Hinweis UND Selbstheilung beim nächsten Login (lokale erledigt-Flags
  werden zum Server nachgezogen). Die Selbstheilung greift erst nach dem
  ersten Server-Sync, damit veraltete lokale Reste (z. B. von einer
  früheren Installation) die Einrichtung bei einer NEUEN Registrierung
  nicht überspringen
- **Standort-Erkennung ohne Einfrieren**: "Standort ermitteln" während
  der Altersspannen-Anpassung konnte die App zum Einfrieren bringen
  (doppelter, gleichzeitiger GPS-Aufruf durch Text-Validierung); der
  Start-Thumb der Altersspanne rutschte außerdem bei jedem Neuaufbau
  auf 16 zurück
- **Benachrichtigungs-Icon in der Statusleiste rund statt Viereck**:
  Das Small-Icon nutzte das voll opake Launcher-Icon; jetzt die rund
  maskierte Silhouette (drawable/notification_icon.png). Zusätzlich
  setzt der Push-Versand (notify-user) jetzt explizit dieses Icon -
  vorher zeigte das System bei Server-Push-Nachrichten weiterhin ein
  Viereck neben der Uhrzeit
- **„Keine neuen Funken"-Karte**: Abgeschnittene Buchstaben bei großen
  Systemschriften behoben (Kanten-Clipping der Card deaktiviert)
- **Audio-Vorstellung**: Erneutes Hochladen schlug mit StorageException
  409 "Duplicate" fehl - jetzt mit Upsert
- **App-Start-Logo**: Es wurde das runde Benachrichtigungs-Icon statt des
  vollständigen Logos gezeigt, außerdem zu groß gerendert (Schrift
  abgeschnitten). Jetzt korrektes, skaliertes Logo inkl. Android-12+
  Kreis-Maske
- **Farbwelten**: Rahmen von Eingabefeldern folgten hartcodiert der
  Classic-Pink; jetzt übernimmt jede Farbwelt (Ozean, Wald, Sonnen-
  untergang, Lavendel, Schiefer) auch die Rahmen
- **Registrierung**: Migration 063 entfernt Invite-Reste von
  Bestandsservern (Invite-Enforcement blockierte die offene
  Registrierung mit "database error saving new user")
- Begrüßung ohne Namen jetzt "Hallo, du!" statt "Hallo, schönen Menschen!"
- **Stadt/Ort wird nach der Einrichtung übernommen**: Bei Standort-Erkennung
  und manueller Eingabe blieb der Ortsname nur im Eingabefeld (und in den
  Nutzer-Präferenzen) - er wurde nie in das Profil-Feld `city` geschrieben
  und vom nächsten Server-Sync (fetchOwnProfile) mit leer überschrieben.
  Jetzt wird der Ortsname lokal im Profil UND serverseitig persistiert
  (sowie die GPS-Koordinaten weiterhin via process-location-check)
- **Passkey-Login mit aktiver CAPTCHA**: Der Server verlangt bei
  aktivierter Dashboard-CAPTCHA auch für den Passkey-Login ein Token -
  die App rief die Zeremonie aber ohne Token auf, und GoTrue lehnte mit
  "Server hat die Passkey-Anfrage abgelehnt" ab (noch vor dem Biometrie-
  Dialog). Jetzt erscheint - wie beim Passwort-Login - zuerst der
  Sicherheitscheck; zusätzlich bekommt der Abbruch-/Ablauf-Fall eine
  eigene, verständliche Meldung
- **Einrichtung erscheint nach Neuinstallation nicht mehr erneut
  (Zuverlässigkeit)**: Zwei Lücken geschlossen. (1) Beim Login nach
  Neuinstallation wurden die serverseitigen Setup-Flags mit hartem
  3-Sekunden-Timeout und OHNE Retry geholt - ein transienter
  Netzfehler ließ die Einrichtung wieder erscheinen, obwohl der Server
  sie als abgeschlossen hatte; außerdem übersprang ein Profil-Fehler
  den Flags-Fetch komplett. Flags werden jetzt entkoppelt mit 3
  Versuchen (8 s Timeout) geholt. (2) Beim Abspeichern des
  Einrichtungs-Stands galt ein stiller 0-Zeilen-Update als "Erfolg";
  jetzt wird nach dem Schreiben zurückgelesen und bei Abweichung
  retries, und auch der Persönlichkeitstest meldet einen Fehlschlag
  sichtbar statt fire-and-forget

### Geändert

- **Applogo: EINZIGE Quelle `wispdating_icon_base.png`**: Launcher-Icons
  (rund, Light/Dark), Adaptive-Icon-Foreground, native Splash-Bilder und
  Notification-Icon werden jetzt ausnahmslos aus dem Basis-Icon generiert
  (verwaiste/veraltete Logo-Assets entfernt; Welcome-Screen precachte noch
  ein nicht mehr vorhandenes Asset). HINWEIS: Das Applogo und dessen
  Implementierung sind noch IN ARBEIT - Feinschliff (Größen, Masken,
  Farbwelten) folgt
- **Einstellungen: Sprachfeld aufklappbar** - statt eines kleinen Icons
  ist das gesamte Feld „Sprache" bedienbar und klappt nach unten auf
  (Sprachwahl per Radio-Liste)
- **Login: Sprach-Icon mit Kreis-Hintergrund** in `primaryContainer` -
  hebt sich damit in jedem Theme (Light/Dark, alle Farbwelten) klar ab
- **Einstellungen: „Account löschen" entfernt** (existiert vollständig
  unter Datenschutz & Account; der 2FA-Step-up vor der Löschung ist
  dorthin mitgezogen). Die Passkey-Diagnose ist jetzt ein reines
  Debug-Werkzeug und für Endnutzer nicht mehr sichtbar
- **Datenschutz & Account**: Auftragsverarbeiter aktualisiert - Brevo
  (Transaktions-E-Mails), Cloudflare (CAPTCHA/TURN) und Netlify (Auth-/
  CAPTCHA-Seite) ergänzt, Hugging Face entfernt (unbenutzt). Unter
  „Einwilligungen" führen jetzt Buttons direkt zu den System-Einstellungen
  (Standortfreigabe) bzw. App-Einstellungen (Push)
- **Einstellungen & Datenschutz komplett zweisprachig** (DE/EN): Alle
  sichtbaren Listen-Texte der beiden Screens sind übersetzt
- **Einrichtung: Swipen deaktiviert** - nur die Buttons führen die
  pro Schritt erforderliche Validierung/Speicherung aus; vorher konnten
  per Swipe Schritte übersprungen werden, wodurch Angaben nicht ins
  Profil übernommen wurden
- **Profil bearbeiten**: Ungespeicherte Änderungen fragen beim Verlassen
  (Tab-Wechsel und Zurück) nach Speichern/Verwerfen; nach fehlge-
  schlagener Validierung erscheint ein Hinweis direkt am Speichern-Button
- Sprach-Button: Übersetzen-Symbol mit Popup-Menü (Deutsch/Englisch),
  nur noch ein Button, positioniert auf Höhe der Überschrift; die
  "Einloggen"-Kopfzeile entfällt, Inhalt rückt höher
- Englisch vervollständigt: Login-/Registrierungs-Screen, Sicherheits-
  check-Dialog und alle Auth-Fehlermeldungen sind zweisprachig
- Standort-Autoerkennung trägt einen ORTSNAMEN ein (Plattform-Reverse-
  Geocoder) statt Koordinaten; Fallback: grobe Region
- Alle Aufklappmenüs abgerundet (16 px, konsistent zum Rest der App):
  Geschlecht bei Registrierung, Beziehungsart/Filter/Bundesland in der
  Einrichtung
- Texte: keine Gedankenstriche mehr in Nutzersichtbaren Sätzen
- Entdecken-Hinweis: „nach einem Funke bestehst" statt „nach einem
  Match bestehst" (Konsistenz zur Funke-Benennung)
- Interne Aufräumarbeiten (Verschlüsselungs-Review): Signal-Skalar-
  Metadaten (Registrierungs-ID, PreKey-Cursor, aktiver SignedPreKey)
  liegen jetzt in einer eigenen verschlüsselten Box statt zweckentfremdet
  im Identity-Adapter (inkl. Migration für Bestandsinstallationen);
  SignedPreKey-Lade-/Rotationslogik vereinfacht (verbrauchte Keys werden
  nicht mehr versehentlich reaktiviert)

### Sicherheit

- Passkeys: assetlinks.json korrigiert (Fingerprint-Format mit
  Doppelpunkten wie von der Android-API geliefert, ergänzter web-Eintrag)
  und die apk-key-hash-Origins auf die tatsächlichen Keystores korrigiert
  (Release + Debug); Root-Domain-Datei für App-Links dokumentiert
- Demo-Modus: Credential-Hashing auf 600.000 PBKDF2-Iterationen angehoben
  (OWASP-2023-Empfehlung, identisch zur Backup-KDF)
- Datenschutz-Entwurf (intern) angelegt

## [0.7.0] – 2026-08-26

Security- & Privacy-Release: Umsetzung des umfassenden Sicherheitsaudits
(App, Edge Functions, Datenbank). **Enthält Pflicht-Migrationen (056–062)
und Edge-Function-Updates – zuerst ausrollen** (siehe
`releases/v0.7.0/RELEASE_NOTES.md`).

### Sicherheit

- **Jugendschutz serverseitig erzwungen**: Alters-Sichtbarkeits- und
  Paarungsregeln (16–17 getrennt; stufenweise ab 18) gelten jetzt in
  Profil-Sicht, Feeds, Likes, Matches, Random Chat und Dating Hour
- **Geburtsdatum unveränderlich** nach Registrierung (serverseitig)
- **Session im Keystore/Keychain** statt Klartext-Speicher
  (Access-/Refresh-Token)
- **E2E (Signal Protocol) repariert**: PreKeys überleben Neustarts,
  Bundle wird automatisch veröffentlicht, One-Time-Key-Rotation,
  SignedPreKey-Rotation (90 Tage), persistenter Identity-Trust mit
  Blockade + Warn-Dialog bei Schlüsselwechsel
- **Account-Löschung vollständig**: Storage-Objekte (Avatare,
  Intro-Audios, Verifizierungs-Videos) und alle lokalen Schlüssel/Daten
  werden entfernt; Fehler werden angezeigt statt verschwiegen
- **Anti-Trilateration**: max. 5 Standort-Änderungen/Tag,
  Speed-Plausibilität serverseitig, ~1-km-Rundung „at rest",
  gedrosselte Distanzabfragen
- Like-/Report-/Dating-Hour-Rate-Limits inkl. Schließung des direkten
  DB-Pfads für Likes
- Dating-Hour: Regressionen aus Migration 055 behoben (Blockier-Schutz
  wiederhergestellt, Scheduler wieder intern), Entscheidungen nach
  Session-Ende unveränderlich
- WebRTC: autorisierte Private Channels für Signaling, optionaler TURN
  (kurzlebige Credentials), SSRF-Guard für UnifiedPush-Endpunkte
- Cert-Pinning: Rotation-Fallback nur noch bei exakt gepinntem Intermediate

### Geändert

- **Registrierung ohne Einladungscode**: Invite-System komplett entfernt
  (Tabelle + RPCs gelöscht); Schutz läuft über CAPTCHA (Dashboard-Pflicht!)
  und Rate-Limits
- Passwort-Reset meldet alle Geräte ab (Global-SignOut)
- Match-Profil zeigt Alter statt Geburtsdatum; Anti-Fraud-Flag verlässt
  den Server nicht mehr
- Quiz-Antwortoptionen werden pro Match gemischt (kein „immer Antwort 1")
- Standort-Anzeige als grobe Region (~11 km) statt Koordinaten
- Entschlüsselte Sprachnachrichten werden nach dem Anhören gelöscht;
  Verifizierungs-Videos liegen app-privat statt im System-Temp
- Bilder werden vor Versand/Upload neu enkodiert (EXIF/GPS garantiert
  entfernt)

### Behoben

- Entschlüsselte Voice-Notes akkumulierten im Temp-Verzeichnis ohne
  Löschung
- Geburtsdaten fremder Nutzer konnten in Release-Logs landen
  (Debug-Guards ergänzt)
- `city`/`state`-Spalten fehlten in den Migrationen (Schema-Drift behoben)
- Doppelte Random-Chat-Warteschlangen pro Nutzer ausgeschlossen
  (partieller Unique-Index)

### Intern

- Persistente DB-Rate-Limits in `prekeys` und `process-location-check`;
  konstante Zeitvergleiche; `user_reports`-Retention (180 Tage);
  Standard-Privilegien für künftige Tabellen entfernt; `prekeys` own-only

## [0.6.1] – 2026-08-24 *(interner Stand, nie veröffentlicht – geht mit 0.7.0 erstmals raus)*

### Behoben

- **Automatischer Logout behoben**: Beim App-Neustart wurde die Session
  verworfen und dabei lokale Daten (Profil, Einstellungen, Präferenzen)
  mitgelöscht. Jetzt bleibt alles erhalten; nach erneutem Login ist
  sofort alles wieder da
- **CI-Pipeline grün**: Flutter auf 3.44.6 gepinnt (webview_flutter braucht
  Dart ≥ 3.10), `.env` wird im Workflow erzeugt, Actions auf v5,
  Signing-Prüfung wirft nur noch bei echten Release-Builds
- KGP-Warnung für `unifiedpush_android` behoben (lokaler Fork)
- Encoding-Nachbereinigung: doppelt kodierte Umlaute in diversen Dateien
  repariert

### Hinzugefügt

- **„Angemeldet bleiben"-Schalter** im Login (standardmäßig aktiv; wer ihn
  deaktiviert, wird beim App-Start bewusst zum Login geführt)
- **Sprache Deutsch/Englisch** – umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung); Kernbereiche sind zweisprachig
- **Passkey-Diagnose** (Einstellungen → E2E-Identität): prüft Domain-
  Verknüpfung und Gerät und zeigt die genaue Ursache bei Passkey-Problemen
- **Dating Hour**: Gewohnheiten (Rauchen/Alkohol/Drogen) als weiche
  Matching-Präferenz wählbar; Anzeige als Chips im Event-Chat
- **„Funke"-Animation** beim Entstehen eines Funkens (Herz + Partikel)
- **Funke-Streak**: Flamme + Tageszähler seit dem Funke – in den Funken
  und im Chat-Header, ganz ohne Schreibpflicht
- **Gemeinsame Interessen** im fremden Profil hervorgehoben
- **Sichtbarer E2E-Status** im Chat-Header (Chip: grün = P2P verbunden)
- Einrichtung: Gewohnheiten jetzt Schritt 5; Profil- und Vorstellungs-
  Angaben sind Pflicht (Bio, mindestens ein Interesse, Text + Audio)
- Passkey und 2FA werden am Ende der Einrichtung **dringend empfohlen**
  (mit Direkt-Sprung zum Einrichten)
- **Neues Thestia-Logo**: rundes Logo überall (App, Splash day/night,
  Launcher-Icons, Adaptive-Icon, Fastlane) – generiert aus der neuen
  Basis-Grafik, Schriftzug vollständig lesbar
- App-Logo mit Dark-Variante (keine weißen Flächen mehr), Splash kleiner
- Desktop/Web: NavigationRail auf breiten Screens

### Geändert

- **„Match" heißt jetzt „Funke"** (Technik unverändert)
- Captcha-Dialog an die Cloudflare-Fenstergröße angepasst
- Theme-Picker mit einheitlichen Kachelgrößen
- Bild-Zuschnitt folgt dem aktiven Farbschema
- App-Titel überall „Thestia"

## [0.6.0] – 2026-08-24

### Hinzugefügt

- **Erscheinungsbilder**: 6 Farbschemata (Classic Thestia, Ozean, Wald,
  Sonnenuntergang, Lavendel, Schiefer) – wählbar in der Einrichtung
  (Schritt „Darstellung") und in den Einstellungen; gilt für Light UND Dark
- **Verschlüsseltes E2E-Key-Backup**: private Signal-Identität per
  Passwort (PBKDF2 + AES-256-GCM) sichern und auf neuem Gerät
  wiederherstellen; PreKeys werden nach dem Restore automatisch erneuert
- **Safety Center**: zentrale Hilfe-Seite bei Belästigung/Stalking mit
  direkten Hilfetelefonen (116 016, 116 006), In-App-Maßnahmen und
  Stalking-Leitfaden
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt,
  Freischalten nur nach Bestätigung; einzelne Bilder direkt melden →
  manuelle Prüfung durch den Support
- **Push ohne Google (UnifiedPush)**: F-Droid-Variante kann über eine
  Distributor-App (z. B. ntfy) Push empfangen – komplett ohne Firebase
- **Build-Flavors** `play` / `fdroid`: die fdroid-Variante enthält kein
  google-services-Plugin und startet ohne Firebase (`--dart-define=FDROID=true`)
- **Desktop-/Web-Navigation**: ab 1000 px Breite NavigationRail statt
  Bottom-Bar
- **Fastlane-Metadaten** (de/en) als Vorbereitung für die F-Droid-Einreichung
- CI-Job für den Google-freien F-Droid-Build

### Geändert

- **„Match" heißt jetzt „Funke"** – deutsche, warme Bezeichnung für die
  entstehende Verbindung (Technik und Datenmodell unverändert)
- **Angemeldet bleiben**: neuer Schalter im Login (standardmäßig AN).
  Ein automatischer Logout löscht keine lokalen Daten mehr – nach erneutem
  Login ist dein Profil wieder da
- **Einrichtung**: Gewohnheiten sind jetzt Schritt 5 (vor den
  Sicherheitsschritten); die Schritte Filter, Profil und Vorstellung sind
  Pflicht (Bio, mindestens ein Interesse, Text- UND Audio-Vorstellung)
- **Dating Hour**: Gewohnheiten als weiche Matching-Präferenz (wählbar in
  den Präferenzen, Anzeige als Chips im Event-Chat)
- **Passkey & 2FA werden dringend empfohlen**: deutlicher Hinweis am Ende
  der Einrichtung mit Direkt-Sprung zum Einrichten; neue Passkey-Diagnose
  in den Einstellungen zeigt die genaue Ursache bei Problemen
- **Sprache Deutsch/Englisch**: umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung)
- **Captcha-Dialog** kompakter (an die Cloudflare-Fenstergröße angepasst)
- **Splash/Logo**: kleiner (60 %), Dark-Variante des Logos ohne weiße
  Flächen (App + nativer Splash in night-Dichteordnern)
- **Theme-Picker**: einheitliche Kachelgrößen
- Registrierung ist jetzt **ohne Einladungscode** offen (Bot-Schutz weiter
  über optionales CAPTCHA + Rate-Limits)
- GPS-Button beim Standortfeld sitzt als suffixIcon exakt am Eingabefeld –
  auch bei großer Systemschrift
- App-Titel überall „Thestia"

### Behoben

- **CI**: Actions auf v5 (Node-20-Deprecation behoben), `.env` wird im
  Workflow aus der Beispiel-Datei erzeugt (fehlendes Asset brach den
  Asset-Build ab)

### Entfernt

- **Präsenz-Metadaten komplett gestrichen**: kein Online-Status, kein
  „schreibt gerade…", keine Lesebestätigungen (siehe ADR-0007) – Dating
  soll zurück ins echte Leben

### Sicherheit

- Profil-PII (Geburtsdatum, Koordinaten) aus dem Klartext-Speicher in den
  Keystore migriert
- Cloud-Backups deaktiviert (`allowBackup=false`)
- Server: Feld-Whitelist für Partnerprofile, Blockier-Check bei Likes,
  Rate-Limits (u. a. QR-Codes), JWT-Pflicht für PreKey-Bundles,
  Beziehungspflicht für Push, search_path-Härtung aller SECURITY-DEFINER-
  Funktionen, Distanz nur in 5-km-Schritten (max. 200 km)
- Release-Build bricht ohne echtes Signing ab (kein stiller Debug-Fallback)

## [0.5.0] – 2026-08-23

### Erste öffentliche Beta 🎉

Thestia dreht das Prinzip klassischer Dating-Apps um: **Persönlichkeit zuerst**.
Fotos sieht man erst nach einem echten Kennenlernen – und alle Kommunikation läuft
Ende-zu-Ende-verschlüsselt direkt zwischen den Geräten.

### Hinzugefügt

- **Find your Match** – Blind-Matching über Vorstellungen (Text + Sprachnachricht,
  je 10 s bis 5 Min); Fotos erst nach gegenseitigem Bestätigen
- **Quiz „Wie gut kenn ich mein Match"** – Chat, Bilder und Anrufe werden bei
  Find-your-Match-Matches erst nach bestandenem Quiz freigeschaltet (serverseitig erzwungen)
- **Zufallschat** – anonymes Peer-to-Peer-Gespräch mit zufälliger Gegenstelle
- **QR Code** – Verbindung per Scan oder manuellem 8-stelligen Code (serverseitig auflösbar)
- **Dating Hour** – wöchentliches Event mit zufälligen 5-Minuten-Gesprächen;
  Match nur bei beidseitigem „Ja"; serverzeitbasiert (Anti-Cheat)
- **Spice Questions** – Eisbrecher-Fragen im Chat; Antworten werden erst sichtbar,
  wenn beide geantwortet haben
- **Profil**: Mood of the Day, Gewohnheiten (Rauchen/Alkohol/Drogen), Interessen,
  Bio, Bundesland, Land, Persönlichkeitstest (MBTI-Stil)
- **Entfernungsanzeige** in km zu anderen Nutzern (5-km-Schritte, serverseitig
  berechnet – exakte Koordinaten verlassen den Server nie)
- **Video-Verifizierung** (Beta): privater Upload, persönliche Prüfung durch den
  Support, Verifiziert-Badge im Profil
- **2FA** via Authenticator-App (TOTP) und **Passkeys** für passwortloses Login
- **Push-Benachrichtigungen** (nur Metadaten) mit Master- und Einzelschaltern;
  Dating-Hour-Erinnerung funktioniert auch bei geschlossener App
- **Bug Report** mit Screenshots; Privacy-Screen mit JSON-Datenexport
- Account-Löschung mit vollständiger lokaler Datenentfernung (DSGVO)

### Geändert

- Altersschutz-System: 16-/17-Jährige sind ab 20 Jahren unsichtbar, Filtergrenzen
  und Foto-Sichtbarkeit folgen gestuften Regeln
- Session-Restore synchron beim Start; serverseitige Validierung im Hintergrund

### Sicherheit

- Ende-zu-Ende-Verschlüsselung (Signal Protocol) + WebRTC-Peer-to-Peer mit
  Cert-Pinning für alle Supabase-Endpunkte
- Serverseitige Härtung: RLS auf allen Tabellen, Rate-Limits (Likes, Push,
  QR-Code-Abfragen), PreKey-Bundles nur mit gültigem JWT
- Lokale Speicherung: Tokens und Profil-PII ausschließlich im Keystore/Keychain,
  Hive AES-verschlüsselt
