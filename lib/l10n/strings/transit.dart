// Die Texte des Themas 'transit' (Deutsch und Englisch).
//
// DER WEG: Die Texte sind nach Themen getrennt, damit keine Datei
// zu lang wird (Grenze: 1000 Zeilen - siehe
// test/code_datei_groessen_test.dart). app_strings.dart fuegt sie
// wieder zusammen.

const Map<String, Map<String, String>> stringsTransit = {
  'de': {
    'transit.accept': 'Funke annehmen',
    'transit.acceptDone': 'Funke angenommen - der Chat ist bereit.',
    'transit.active':
        'Radar aktiv - du bist sichtbar für Thestia-Geräte in der Nähe.',
    'transit.adultOnly.body':
        'Transit Spark zeigt dir in Echtzeit, wer gerade in deiner Nähe '
        'ist. Diese Funktion steht nur volljährigen Personen zur '
        'Verfügung - auf der App-Seite wie auch serverseitig gesperrt.',
    'transit.adultOnly.missingAge':
        'Für Transit Spark brauchen wir dein Geburtsdatum. Hinterlege es '
        'in deinen Profildaten, dann prüfen wir dein Alter - solange das '
        'nicht belegt ist, bleibt die Funktion gesperrt.',
    // DER SLOGAN (14.11.2026, Betreiber): "Dating, das dich ins echte
    // Leben zurückführt." Er steht als Überschrift des ersten
    // Willkommens-Bildschirms - das ist der erste Satz, den ein
    // Nutzer von der App liest.
    'welcome.t1': 'Dating, das dich ins echte Leben zurückführt.',
    'transit.adultOnly.title': 'Transit Spark nur ab 18',
    'transit.advertiseBody':
        'Zum Senden deiner Anwesenheit braucht die App die '
        'Bluetooth-Werbungs-Berechtigung (Android 12+). Bitte erteile sie '
        'und starte das Radar erneut.',
    'transit.alreadySparkBody':
        'Diese Person hast du schon einmal getroffen. '
        'Der Funke ist noch da - schau in deine Chats.',
    'transit.alreadySparkTitle': 'Ihr habt schon einen Funken',
    'transit.batteryHint':
        'Aktives Radar braucht Bluetooth und scannt dauerhaft. Das '
        'verbraucht merklich mehr Akku. Stoppe das Radar, wenn du es '
        'nicht mehr brauchst.',
    'transit.btBody':
        'Für Transit Spark muss Bluetooth eingeschaltet sein. Soll es jetzt aktiviert werden?',
    'transit.btEnable': 'Jetzt aktivieren',
    'transit.btTitle': 'Bluetooth aktivieren',
    'transit.candidateAnonymous': 'Jemand in der Nähe',
    'transit.candidateWave': 'Zuwinken',
    'transit.candidateWaveFailed': 'Das hat nicht geklappt',
    'transit.candidateWaved': 'Zugewinkt',
    'transit.candidatesHint':
        'Sie sind in der Nähe und haben ähnliche Merkmale. Du kannst '
        'mehreren zuwinken.',
    'transit.candidatesTitle': 'Menschen mit deiner Beschreibung',
    'transit.cat.accessory': 'Accessoires',
    'transit.cat.bottom': 'Unterteil',
    'transit.cat.eyes': 'Augen',
    'transit.cat.hair': 'Haar',
    // Eigene Kategorien (Migration 188): Haarlaenge und Frisur sind
    // keine Alternative, sondern zwei Angaben.
    'transit.cat.hair_length': 'Haarlänge',
    'transit.cat.hair_style': 'Frisur',
    'transit.cat.head': 'Kopf',
    'transit.cat.shoes': 'Schuhe',
    'transit.cat.top': 'Oberteil',
    'transit.categoryAll': 'Alle',
    'transit.cleanupBody':
        'Radar ist aus. Bluetooth und Standort bleiben an - schalte sie '
        'selbst in den Einstellungen aus, die App darf das nicht.',
    'transit.cleanupLater': 'Später',
    'transit.cleanupOpenBluetooth': 'Bluetooth',
    'transit.cleanupOpenLocation': 'Standort',
    'transit.cleanupTitle': 'Nach Radar ausschalten?',
    'transit.cleanupToggle': 'Nach Radar erinnern',
    'transit.cleanupToggleSub':
        'Aus. Fragt nach Radar-Ende, ob du Bluetooth/Standort '
        'ausschalten willst.',
    'transit.color.amber': 'Bernstein',
    'transit.color.auburn': 'Kastanienrot',
    'transit.color.bald': 'Glatze',
    'transit.color.black': 'Schwarz',
    'transit.color.blonde': 'Blond',
    // Neue Haarfarben (06.11.2026).
    'transit.color.darkbrown': 'Dunkelbraun',
    'transit.color.blue': 'Blau',
    'transit.color.bluegrey': 'Blaugrau',
    'transit.color.brown': 'Braun',
    'transit.color.copper': 'Kupferrot',
    'transit.color.green': 'Grün',
    'transit.color.grey': 'Grau',
    'transit.color.hazel': 'Haselnussbraun',
    'transit.color.lightbrown': 'Hellbraun',
    'transit.color.orange': 'Orange',
    'transit.color.pink': 'Pink',
    'transit.color.platinum': 'Platinblond',
    'transit.color.purple': 'Lila',
    'transit.color.red': 'Rot',
    'transit.color.saltpepper': 'Salz und Pfeffer',
    'transit.color.silver': 'Silbergrau',
    'transit.color.teal': 'Türkis',
    // Die Werte der Merkmale mit Werteliste (Migration 187).
    //
    // BEFUND (07.11.2026, Betreiber): "also Hairstyle und so" - als
    // blosse Merkmale waren Haarlaenge und Frisur wertlos ("hat
    // Haarlaenge?"). Deshalb gibt es jetzt echte Werte.
    'transit.value.kurz': 'Kurz',
    'transit.color.white': 'Weiß',
    'transit.color.yellow': 'Gelb',
    'transit.colorOptional': 'Farbe (optional)',
    'transit.exchanged': 'Blicke getauscht',
    'transit.exitBody':
        'Das Radar läuft noch. Du kannst es beim Verlassen der Seite '
        'stoppen oder im Hintergrund weiterlaufen lassen (Fenster läuft '
        'weiter, Funke auch Stunden später möglich).',
    'transit.exitKeep': 'Weiterlaufen lassen',
    'transit.exitRemember': 'Zukünftig automatisch so beibehalten',
    // 2-Stunden-Ruhezeit gesehener Personen (088-Runde)
    'transit.retainedBtn': 'Gesehene Geräte ansehen (2 Stunden)',
    'transit.exitStop': 'Radar stoppen',
    'transit.featureDisabled':
        'Transit Spark ist gerade eingeschränkt. Bitte versuche es später '
        'noch einmal.',
    'transit.greet': 'Grüßen',
    'transit.greetSection': 'Gesehene Geräte in dieser Session',
    'transit.hoursAgo': 'vor {count} Std.',
    'transit.howBody':
        'Aktiviere das Radar, wenn du unterwegs bist (Zug, Café, Messe). '
        'Dein Gerät tauscht mit anderen Thestia-Geräten in nächster Nähe '
        'anonyme, zufällige Token aus - ohne Namen, ohne Standort, ohne '
        'Fotos. Tippe später auf "Blicke getauscht": Spürt die andere '
        'Person denselben Moment und funkt ebenfalls, entsteht ein Funke.',
    'transit.howTitle': 'Wie funktioniert das?',
    'transit.ignore': 'Ausblenden',
    'transit.ignoreConfirmBody':
        'Er verschwindet dann aus deiner Liste. Der Absender sieht nichts '
        'davon - du kannst ihn auch einfach annehmen.',
    'transit.ignoreConfirmOk': 'Ausblenden',
    'transit.ignoreConfirmTitle': 'Diesen Funke ausblenden?',
    'transit.inactive': 'Radar aus. Aktiviere es, wenn du unterwegs bist.',
    'transit.inboxTitle': 'Grüße für dich',
    'transit.justNow': 'gerade eben',
    'transit.later': 'Später',
    'transit.limitHint': 'Je Kategorie nur ein Merkmal.',
    'transit.locationActiveBody':
        'Dein Standort ist jetzt eingeschaltet. Tippe auf "Radar starten", '
        'um direkt mit deinen bereits gewählten Merkmalen zu beginnen - '
        'du musst nichts neu eingeben.',
    'transit.locationActiveBtn': 'Radar starten',
    'transit.locationActiveTitle': 'Standort aktiviert',
    'transit.locationBody':
        'Für das Radar muss der Standort-DIENST (GPS) eingeschaltet sein '
        '(Android braucht das für BLE-Scans, besonders Android 11). Die App '
        'kann ihn nicht selbst einschalten - bitte aktiviere ihn in den '
        'Systemeinstellungen und starte das Radar danach erneut.',
    'transit.locationOpen': 'Einstellungen öffnen',
    'transit.locationTitle': 'Standort einschalten',
    'transit.matchBody':
        'Die Person hat denselben Moment gespürt. Schaut in eure Funken - '
        'ihr könnt jetzt chatten.',
    'transit.matchTitle': 'Funke übergesprungen!',
    'transit.minutesAgo': 'vor {count} Min.',
    'transit.mode.convention': 'Nur direkt daneben',
    'transit.mode.transit': 'Normal',
    'transit.modeDesc.convention':
        'Eng begrenzt: nur Personen unmittelbar neben dir zählen. Ideal '
        'für volle Messen, Konzerte und Events.',
    'transit.modeDesc.transit':
        'Übliche Reichweite: Begegnungen im Vorbeigehen, z. B. auf der '
        'Straße als Fußgänger, im Zug oder im Café.',
    'transit.modeLabel': 'Wie weit soll die Erkennung reichen?',
    'transit.nameDecisionBody':
        'Wenn du bei Transit Spark jemandem zuwinkst, kann die Person '
        'deinen Namen sehen. Du kannst das hier entscheiden und es '
        'später ändern.',
    'transit.nameDecisionBoundary':
        'Wichtig: Das schützt nur deinen Namen. Wer neben dir steht, '
        'erkennt dich trotzdem.',
    'transit.nameDecisionHide': 'Nein, bleib anonym',
    'transit.nameDecisionShow': 'Ja, mein Name darf sichtbar sein',
    'transit.nameDecisionTitle': 'Soll dein Name sichtbar sein?',
    'transit.nearbyCount':
        '{count} Personen in der Nähe - du siehst {shown} davon.',
    'transit.noDevices':
        'Kein Gerät in Reichweite. Warte, bis jemand in der Nähe '
        'ist, und versuche es dann noch einmal.',
    // BEFUND (07.11.2026): Das Radar sendet noch kein Signal. Ohne den
    // eigenen Token kann der Server keinen Match finden - das wird
    // gesagt, statt still nichts zu tun.
    'transit.ownTokenMissing':
        'Das Radar sendet noch kein Signal. Warte einen Moment und '
        'versuche es dann noch einmal.',
    // Der Server kennt die neue Fassung der Transit-Spark-Funktion
    // noch nicht (Migration 185). Dann kann die App keinen Match
    // finden - die Meldung sagt es, statt still zu scheitern.
    'transit.serverTooOld':
        'Die App ist zu alt für den Server. Bitte aktualisiere sie.',
    'transit.noEncounters': 'Noch keine Geräte in Reichweite gewesen.',
    'transit.openSparks': 'Zu den Funken',
    'transit.permissionBody':
        'Ohne diese Berechtigung kann das Radar nicht starten. Bitte erteile '
        'sie in den App-Einstellungen und versuche es erneut.',
    'transit.permissionOpen': 'App-Einstellungen öffnen',
    'transit.permissionTitle': 'Berechtigung nötig',
    'transit.pingCustomHint': 'Optional: eine kurze eigene Zeile …',
    'transit.pingSend': 'Gruß senden',
    'transit.pingSent':
        'Gruß gesendet. 48 Stunden Zeitfenster - mehr '
        'nicht.',
    'transit.pingSheetHint':
        'Einmal pro Begegnung möglich. Die Person entscheidet still, '
        'ob sie antwortet - du erfährst nur von einem Ja.',
    'transit.pingSheetTitle': 'Einen Gruß senden',
    'transit.place.bar': 'Bar / Café',
    'transit.place.messe': 'Messe',
    'transit.place.sonstiges': 'Sonstiges',
    'transit.place.veranstaltung': 'Veranstaltung',
    'transit.place.zug': 'Zug',
    'transit.placeHint': 'z. B. Wagen 3, Halle 2 bei den Toiletten',
    'transit.placeLabel': 'Wo bist du gerade?',
    'transit.placePrivacy':
        'Du nennst den Ort selbst - die App ermittelt nichts. Wer in der '
        'Nähe ist, sieht ihn nur, wenn er ihn selbst auch nennt.',
    'transit.preset.again': 'Vielleicht kreuzen sich unsere Wege ja nochmal?',
    'transit.preset.coffee': 'Falls du magst: ein Kaffee in der Nähe?',
    'transit.preset.wave': 'Hallo! Ich war gerade eben in deiner Nähe.',
    'transit.privacyNote':
        'Tokens sind zufällig, rotieren regelmäßig und verfallen nach '
        '45 Minuten. Gespeichert wird nur, was du aktiv sendest - nichts '
        'verlässt dein Gerät, solange du nicht selbst funkt. Ein Gruß an eine Person braucht deren aktuelles Token - dafür wird bei aktivem Radar dein zufälliges Token (nur dieses) 45 Minuten serverseitig hinterlegt.',
    'transit.remaining': 'Noch {time} aktiv',
    // "Signale" und nicht "Geräte": ein Gerät liefert mehrere Signale,
    // weil sein Token alle 6-14 Minuten wechselt (Datenschutz).
    'transit.seenCount': '{count} Thestia-Signale in Reichweite empfangen.',
    'transit.retainedHint': 'Die Liste bleibt noch 2 Stunden erhalten.',
    'transit.retainedTitle': 'Gesehene Geräte',
    'transit.retainedUntil': 'Die Liste bleibt bis {time} Uhr erhalten.',
    'transit.rssiValue': 'Signal ab {value} dBm',
    'transit.searchEmpty': 'Kein Merkmal passt zu „{query}“.',
    'transit.searchHint': 'Merkmal suchen',
    'transit.selectedCount': '{count} gewählt',
    'transit.self.hint':
        'Wähle 2-5 Merkmale zu dir selbst - nur so können dich andere '
        'über Transit Spark finden. Jeden Tag neu angeben.',
    'transit.self.noteHint':
        'Eigene Ergänzung (optional, z. B. "Rote Mütze, grüner Rucksack") …',
    'transit.self.title': 'Wie siehst du gerade aus?',
    'transit.sendFailed':
        'Das Signal konnte gerade nicht gesendet werden. Prüfe deine Verbindung und versuche es gleich noch einmal.',
    'transit.sheetHint':
        'Wähle 2-5 Merkmale, die dir an der Person aufgefallen sind - '
        'die Auswahl schärft das Matching.',
    'transit.sheetSend': 'Funken',
    'transit.sheetTitle': 'Wer war das?',
    'transit.showNameBoundary':
        'Wichtig: Das schützt nur deinen Namen. Wer neben dir steht, '
        'erkennt dich trotzdem.',
    'transit.showNameSub':
        'Wenn du jemandem bei Transit Spark zuwinkst, sieht die Person '
        'deinen Namen. Aus: Es steht nur "Jemand winkt dir zu".',
    'transit.showNameSubOff':
        'Dein Name wird nicht angezeigt - die Person sieht nur "Jemand '
        'winkt dir zu".',
    'transit.showNameTitle': 'Namen beim Zuwinken zeigen',
    'transit.start': 'Radar aktivieren',
    'transit.startFailed':
        'Radar konnte nicht gestartet werden. Bluetooth an und Berechtigung '
        'erteilen.',
    // Radar-Verlassen (Radar läuft): Stoppen? + Merk-Checkbox
    'transit.exitTitle': 'Radar laufen lassen?',
    'transit.stop': 'Radar stoppen',
    'transit.stored':
        'Dein Signal ist gespeichert. Spürt die andere Person denselben Moment und funkt ebenfalls, entsteht euer Funke.',
    'transit.tag.ausweis': 'Ausweis',
    'transit.tag.backpack': 'Rucksack',
    'transit.tag.black_hoodie': 'Hoodie (schwarz)',
    'transit.tag.bluse': 'Bluse',
    'transit.tag.brille': 'Brille',
    'transit.tag.cap': 'Cap',
    'transit.tag.colorful_top': 'Auffälliges Oberteil',
    'transit.tag.eyes_color': 'Augenfarbe',
    'transit.tag.glasses': 'Brille',
    'transit.tag.hair_color': 'Haarfarbe',
    'transit.tag.hair_length': 'Haarlänge',
    'transit.tag.hair_style': 'Frisur',
    'transit.tag.halbschuhe': 'Halbschuhe',
    'transit.tag.headphones': 'Kopfhörer',
    'transit.tag.helm': 'Helm',
    'transit.tag.hemd': 'Hemd',
    'transit.tag.hoodie': 'Hoodie',
    'transit.tag.hose': 'Hose',
    'transit.tag.jacke': 'Jacke',
    'transit.tag.jacket': 'Jacke',
    'transit.tag.jeans': 'Jeans',
    'transit.tag.kopfhoerer': 'Kopfhörer',
    'transit.tag.lanyard': 'Lanyard / Badge',
    'transit.tag.leggings': 'Leggings',
    'transit.tag.muetze': 'Mütze',
    'transit.tag.pants': 'Lange Hose',
    'transit.tag.pullover': 'Pullover',
    'transit.tag.rock': 'Rock',
    'transit.tag.rucksack': 'Rucksack',
    'transit.tag.sandalen': 'Sandalen',
    'transit.tag.scarf': 'Schal',
    'transit.tag.schal': 'Schal',
    'transit.tag.shorts': 'Kurze Hose',
    'transit.tag.sneaker': 'Sneaker',
    'transit.tag.sportlich': 'Sportliche Kleidung',
    'transit.tag.sporty': 'Sportliche Kleidung',
    'transit.tag.stiefel': 'Stiefel',
    'transit.tag.sweater': 'Pullover',
    'transit.tag.tasche': 'Tasche',
    'transit.tag.top': 'Oberteil',
    'transit.tag.tote_bag': 'Tote Bag',
    'transit.tag.tshirt': 'T-Shirt',
    'transit.tag.weste': 'Weste',
    'transit.title': 'Transit Spark',
    'transit.toChat': 'Zum Chat',
    'transit.value.flechtig': 'Geflechtet',
    'transit.value.gewellt': 'Gewellt',
    'transit.value.glatt': 'Glatt',
    'transit.value.kraus': 'Kraus',
    'transit.value.kurz_geschnitten': 'Kurz geschnitten',
    'transit.value.lang': 'Lang',
    'transit.value.lockig': 'Lockig',
    'transit.value.mittel': 'Mittellang',
    'transit.value.ponytail': 'Pferdeschwanz',
    'transit.value.schulter': 'Bis zur Schulter',
    'transit.value.schulterlang': 'Schulterlang',
    'transit.value.sehrlang': 'Sehr lang',
    'transit.value.stoppeln': 'Stoppeln',
    'transit.value.zopf': 'Zopf',
    'transit.waveFrom': '{name} winkt dir zu',
    'transit.waveFromAnonymous': 'Jemand winkt dir zu',
  },
  'en': {
    'transit.accept': 'Accept spark',
    'transit.acceptDone': 'Spark accepted - the chat is ready.',
    'transit.active': 'Radar active - visible to nearby Thestia devices.',
    'transit.adultOnly.body':
        'Transit Spark shows you in real time who is near you right now. '
        'This feature is only available to adults - blocked in the app '
        'and enforced on the server.',
    'transit.adultOnly.missingAge':
        'Transit Spark needs your date of birth. Add it to your profile '
        'so we can check your age - until that is confirmed, the feature '
        'stays locked.',
    'transit.adultOnly.title': 'Transit Spark is 18+ only',
    'transit.advertiseBody':
        'To broadcast your presence, the app needs the Bluetooth '
        'advertising permission (Android 12+). Please grant it and '
        'restart the radar.',
    'transit.alreadySparkBody':
        'You have met this person before. '
        'The spark is still there - check your chats.',
    'transit.alreadySparkTitle': 'You already have a spark',
    'transit.batteryHint':
        'Active radar uses Bluetooth and scans continuously. This uses '
        'noticeably more battery. Stop the radar when you no longer need it.',
    'transit.btBody':
        'Transit Spark needs Bluetooth turned on. Turn it on now?',
    'transit.btEnable': 'Turn on now',
    'transit.btTitle': 'Turn on Bluetooth',
    'transit.candidateAnonymous': 'Someone nearby',
    'transit.candidateWave': 'Wave',
    'transit.candidateWaveFailed': 'That did not work',
    'transit.candidateWaved': 'Waved',
    'transit.candidatesHint':
        'They are nearby and have similar features. You can wave at '
        'several of them.',
    'transit.candidatesTitle': 'People with your description',
    'transit.cat.accessory': 'Accessories',
    'transit.cat.bottom': 'Bottoms',
    'transit.cat.eyes': 'Eyes',
    'transit.cat.hair': 'Hair',
    // Own categories (migration 188): hair length and hairstyle are not
    // alternatives, but two separate statements.
    'transit.cat.hair_length': 'Hair length',
    'transit.cat.hair_style': 'Hairstyle',
    'transit.cat.head': 'Headwear',
    'transit.cat.shoes': 'Shoes',
    'transit.cat.top': 'Top',
    'transit.categoryAll': 'All',
    'transit.cleanupBody':
        'Radar is off. Bluetooth and location stay on - turn them off '
        'yourself in settings, the app is not allowed to.',
    'transit.cleanupLater': 'Later',
    'transit.cleanupOpenBluetooth': 'Bluetooth',
    'transit.cleanupOpenLocation': 'Location',
    'transit.cleanupTitle': 'Turn off after radar?',
    'transit.cleanupToggle': 'Remind after radar',
    'transit.cleanupToggleSub':
        'Off. Asks after radar sessions whether to turn off '
        'Bluetooth/location.',
    'transit.color.amber': 'Amber',
    'transit.color.auburn': 'Auburn',
    'transit.color.bald': 'Bald',
    'transit.color.black': 'Black',
    'transit.color.blonde': 'Blonde',
    'transit.color.blue': 'Blue',
    'transit.color.bluegrey': 'Blue-grey',
    'transit.color.brown': 'Brown',
    'transit.color.copper': 'Copper',
    'transit.color.darkbrown': 'Dark brown',
    'transit.color.green': 'Green',
    'transit.color.grey': 'Grey',
    'transit.color.hazel': 'Hazel',
    'transit.color.lightbrown': 'Light brown',
    'transit.color.orange': 'Orange',
    'transit.color.pink': 'Pink',
    'transit.color.platinum': 'Platinum blonde',
    'transit.color.purple': 'Purple',
    'transit.color.red': 'Red',
    'transit.color.saltpepper': 'Salt and pepper',
    'transit.color.silver': 'Silver',
    'transit.color.teal': 'Teal',
    // The values of the features with a value list (migration 187).
    'transit.value.kurz': 'Short',
    'transit.color.white': 'White',
    'transit.color.yellow': 'Yellow',
    'transit.colorOptional': 'Color (optional)',
    'transit.exchanged': 'Exchanged glances',
    'transit.exitBody':
        'The radar is still active. You can stop it when leaving this page '
        'or let it keep running in the background (the window keeps '
        'running, a spark is possible hours later).',
    'transit.exitKeep': 'Keep running',
    'transit.exitRemember': 'Apply automatically in the future',
    // 2-hour retention of seen people
    'transit.retainedBtn': 'View seen devices (2 hours)',
    'transit.exitStop': 'Stop radar',
    'transit.featureDisabled':
        'Transit Spark is currently unavailable. Please try again later.',
    'transit.greet': 'Greet',
    'transit.greetSection': 'Devices seen in this session',
    'transit.hoursAgo': '{count} h ago',
    'transit.howBody':
        'Activate the radar while you are on the go (train, café, '
        'convention). Your device exchanges anonymous, random tokens with '
        'other Thestia devices nearby - no names, no location, no photos. '
        'Later, tap "Exchanged glances": if the other person feels the '
        'same moment and signals too, a spark is created.',
    'transit.howTitle': 'How does it work?',
    'transit.ignore': 'Hide',
    'transit.ignoreConfirmBody':
        'It disappears from your list. The sender does not see anything - '
        'you can also simply accept it.',
    'transit.ignoreConfirmOk': 'Hide',
    'transit.ignoreConfirmTitle': 'Hide this spark?',
    'transit.inactive': 'Radar off. Activate it when you are on the go.',
    'transit.inboxTitle': 'Greetings for you',
    'transit.justNow': 'just now',
    'transit.later': 'Later',
    'transit.limitHint': 'One feature per category.',
    'transit.locationActiveBody':
        'Your location is now turned on. Tap "Start radar" to begin '
        'directly with your previously selected traits - no need to '
        're-enter anything.',
    'transit.locationActiveBtn': 'Start radar',
    'transit.locationActiveTitle': 'Location enabled',
    'transit.locationBody':
        'The radar needs the location SERVICE (GPS) turned on (Android '
        'requires this for BLE scans, especially Android 11). The app '
        'cannot turn it on itself - please enable it in system settings '
        'and restart the radar afterwards.',
    'transit.locationOpen': 'Open settings',
    'transit.locationTitle': 'Turn on location',
    'transit.matchBody':
        'The other person felt the same moment. Check your sparks - you '
        'can chat now.',
    'transit.matchTitle': 'Spark jumped over!',
    'transit.minutesAgo': '{count} min ago',
    'transit.mode.convention': 'Only right next to me',
    'transit.mode.transit': 'Normal',
    'transit.modeDesc.convention':
        'Tightly limited: only people right next to you count. Ideal '
        'for packed conventions, concerts and events.',
    'transit.modeDesc.transit':
        'Typical range: passing encounters, e. g. on the street as a '
        'pedestrian, on the train or in a café.',
    'transit.modeLabel': 'How far should detection reach?',
    'transit.nameDecisionBody':
        'When you wave to someone via Transit Spark, that person can '
        'see your name. You can decide here and change it later.',
    'transit.nameDecisionBoundary':
        'Important: this only protects your name. Someone standing next '
        'to you can still recognise you.',
    'transit.nameDecisionHide': 'No, I want to stay anonymous',
    'transit.nameDecisionShow': 'Yes, my name may be visible',
    'transit.nameDecisionTitle': 'Should your name be visible?',
    'transit.nearbyCount':
        '{count} people nearby - you are seeing {shown} of them.',
    'transit.noDevices':
        'No device in range. Wait until someone is nearby and '
        'try again.',
    // The radar is not sending a signal yet. Without its own token the
    // server cannot find a match - it says so instead of failing
    // quietly.
    'transit.ownTokenMissing':
        'The radar is not sending a signal yet. Wait a moment and '
        'try again.',
    // The server does not know the new version of the transit spark
    // function yet (migration 185). The app cannot find a match then -
    // it says so instead of failing quietly.
    'transit.serverTooOld':
        'The app is too old for the server. Please update it.',
    'transit.noEncounters': 'No devices in range yet.',
    'transit.openSparks': 'To the sparks',
    'transit.permissionBody':
        'The radar cannot start without this permission. Please grant it '
        'in app settings and try again.',
    'transit.permissionOpen': 'Open app settings',
    'transit.permissionTitle': 'Permission required',
    'transit.pingCustomHint': 'Optional: one short line of your own …',
    'transit.pingSend': 'Send greeting',
    'transit.pingSent': 'Greeting sent. 48-hour window - that is all.',
    'transit.pingSheetHint':
        'Possible once per encounter. The person decides quietly '
        'whether to respond - you will only hear about a yes.',
    'transit.pingSheetTitle': 'Send a greeting',
    'transit.place.bar': 'Bar / cafe',
    'transit.place.messe': 'Trade fair',
    'transit.place.sonstiges': 'Elsewhere',
    'transit.place.veranstaltung': 'Event',
    'transit.place.zug': 'Train',
    'transit.placeHint': 'e.g. coach 3, hall 2 by the toilets',
    'transit.placeLabel': 'Where are you right now?',
    'transit.placePrivacy':
        'You name the place yourself - the app does not detect anything. '
        'People nearby only see it if they name their own place too.',
    'transit.preset.again': 'Maybe our paths will cross again?',
    'transit.preset.coffee': 'If you like: a coffee nearby?',
    'transit.preset.wave': 'Hi! I was just near you.',
    'transit.privacyNote':
        'Tokens are random, rotate regularly and expire after 45 minutes. '
        'Only what you actively send is stored - nothing leaves your '
        'device unless you choose to signal. A greeting to a person '
        'needs their current token - therefore while the radar is '
        'active your random token (only this one) is stored server-'
        'side for 45 minutes.',
    'transit.remaining': 'Active for another {time}',
    // "Signals" and not "devices": one device delivers several signals,
    // because its token changes every 6-14 minutes (privacy).
    'transit.seenCount': 'Received {count} Thestia signals in range.',
    'transit.retainedHint': 'The list stays for 2 more hours.',
    'transit.retainedTitle': 'Seen devices',
    'transit.retainedUntil': 'The list stays until {time}.',
    'transit.rssiValue': 'Signal from {value} dBm',
    'transit.searchEmpty': 'No feature matches “{query}”.',
    'transit.searchHint': 'Search feature',
    'transit.selectedCount': '{count} selected',
    'transit.self.hint':
        'Pick 2-5 traits describing yourself - only this way others '
        'can find you via Transit Spark. Re-enter daily.',
    'transit.self.noteHint':
        'Your own note (optional, e.g. "Red cap, green backpack") …',
    'transit.self.title': 'How do you look right now?',
    'transit.sendFailed':
        'The signal could not be sent right now. Check your connection and try again in a moment.',
    'transit.sheetHint':
        'Pick 2-5 traits you noticed about the person - your selection '
        'sharpens the matching.',
    'transit.sheetSend': 'Spark',
    'transit.sheetTitle': 'Who was it?',
    'transit.showNameBoundary':
        'Important: this only protects your name. Someone standing next to '
        'you can still recognise you.',
    'transit.showNameSub':
        'When you wave to someone via Transit Spark, they see your name. '
        'Off: it only says "someone is waving at you".',
    'transit.showNameSubOff':
        'Your name is not shown - the person only sees "someone is waving '
        'at you".',
    'transit.showNameTitle': 'Show my name when I wave',
    'transit.start': 'Activate radar',
    'transit.startFailed':
        'Radar could not start. Turn on Bluetooth and grant permission.',
    'transit.stop': 'Stop radar',
    'transit.stored':
        'Your signal is saved. If the other person feels the same moment and signals too, your spark is created.',
    // Leaving the radar screen (radar active): stop? + remember checkbox
    'transit.exitTitle': 'Keep the radar running?',
    'transit.tag.ausweis': 'Badge',
    'transit.tag.backpack': 'Backpack',
    'transit.tag.black_hoodie': 'Hoodie (black)',
    'transit.tag.bluse': 'Blouse',
    'transit.tag.brille': 'Glasses',
    'transit.tag.cap': 'Cap',
    'transit.tag.colorful_top': 'Colorful top',
    'transit.tag.eyes_color': 'Eye colour',
    'transit.tag.glasses': 'Glasses',
    'transit.tag.hair_color': 'Hair colour',
    'transit.tag.hair_length': 'Hair length',
    'transit.tag.hair_style': 'Hairstyle',
    'transit.tag.halbschuhe': 'Loafers',
    'transit.tag.headphones': 'Headphones',
    'transit.tag.helm': 'Helmet',
    'transit.tag.hemd': 'Shirt',
    'transit.tag.hoodie': 'Hoodie',
    'transit.tag.hose': 'Trousers',
    'transit.tag.jacke': 'Jacket',
    'transit.tag.jacket': 'Jacket',
    'transit.tag.jeans': 'Jeans',
    'transit.tag.kopfhoerer': 'Headphones',
    'transit.tag.lanyard': 'Lanyard / badge',
    'transit.tag.leggings': 'Leggings',
    'transit.tag.muetze': 'Beanie',
    'transit.tag.pants': 'Long pants',
    'transit.tag.pullover': 'Sweater',
    'transit.tag.rock': 'Skirt',
    'transit.tag.rucksack': 'Backpack',
    'transit.tag.sandalen': 'Sandals',
    'transit.tag.scarf': 'Scarf',
    'transit.tag.schal': 'Scarf',
    'transit.tag.shorts': 'Shorts',
    'transit.tag.sneaker': 'Sneakers',
    'transit.tag.sportlich': 'Sporty clothes',
    'transit.tag.sporty': 'Sporty clothes',
    'transit.tag.stiefel': 'Boots',
    'transit.tag.sweater': 'Sweater',
    'transit.tag.tasche': 'Bag',
    'transit.tag.top': 'Top',
    'transit.tag.tote_bag': 'Tote bag',
    'transit.tag.tshirt': 'T-shirt',
    'transit.tag.weste': 'Waistcoat',
    'transit.title': 'Transit Spark',
    'transit.toChat': 'To chat',
    'transit.value.flechtig': 'Braided',
    'transit.value.gewellt': 'Wavy',
    'transit.value.glatt': 'Straight',
    'transit.value.kraus': 'Crimped',
    'transit.value.kurz_geschnitten': 'Cropped',
    'transit.value.lang': 'Long',
    'transit.value.lockig': 'Curly',
    'transit.value.mittel': 'Medium-length',
    'transit.value.ponytail': 'Ponytail',
    'transit.value.schulter': 'To the shoulder',
    'transit.value.schulterlang': 'Shoulder-length',
    'transit.value.sehrlang': 'Very long',
    'transit.value.stoppeln': 'Stubble',
    'transit.value.zopf': 'Ponytail braid',
    'transit.waveFrom': '{name} is waving at you',
    'transit.waveFromAnonymous': 'Someone is waving at you',
  },
};
