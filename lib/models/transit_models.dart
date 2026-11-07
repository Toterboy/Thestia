import 'package:flutter/material.dart';

/// Ergebnis des Signal-Versands ("Blicke getauscht").
class TransitSparkResult {
  const TransitSparkResult({
    required this.matched,
    this.partnerId,
    this.partnerNote,
  });

  /// true = die andere Person hatte ebenfalls signalisiert - der Funke
  /// wurde erzeugt (Match-Übernahme läuft über die Bestandspipeline).
  final bool matched;

  /// Partner-User-ID bei Match (sonst null).
  final String? partnerId;

  /// Freie Ergänzung der Gegenseite bei Match (sonst null, v0.9.1).
  final String? partnerNote;

  factory TransitSparkResult.fromJson(Map<String, dynamic> json) {
    final note = json['partnerNote'] as String?;
    return TransitSparkResult(
      matched: json['matched'] == true,
      partnerId: json['partner'] as String?,
      partnerNote: (note == null || note.trim().isEmpty) ? null : note,
    );
  }
}

/// Ein lokal gecachter Encounter (anderes Gerät in BLE-Nähe).
class TransitEncounter {
  const TransitEncounter({required this.token, required this.seenAt});

  /// Ephemeres Token des anderen Geräts (rotiert bei dessen Aktivierung).
  final String token;

  /// Zeitpunkt der letzten Sichtung.
  final DateTime seenAt;

  /// 45-Minuten-Vorhaltezeit (Phase 2 asynchron - auch später funken).
  static const Duration retention = Duration(minutes: 45);

  /// Erweiterte Vorhaltezeit (v0.9.0-Nutzerwunsch): Nach Ablauf der 45
  /// Minuten bleiben gesehene Personen noch 2 Stunden SICHTBAR in der
  /// Liste ("in Ruhe finden"), funkenfähig sind sie ab dem Server-TTL-
  /// Ablauf allerdings nicht mehr (isFresh = funkenfähig).
  static const Duration softRetention = Duration(hours: 2);

  /// 45-Minuten-Fenster: funkenfähig (Server-TTL der Tokens).
  bool get isFresh => DateTime.now().difference(seenAt) < retention;

  /// 2-Stunden-Fenster: noch sichtbar in der Liste.
  bool get isSoftFresh => DateTime.now().difference(seenAt) < softRetention;
}

/// Kategorie eines Transit-Merkmals (v0.10.0, Migration 148).
///
/// BISHER war die Merkmalsauswahl eine flache Liste: "T-Shirt",
/// "Hoodie" und "Oberteil" standen gleichrangig nebeneinander, ohne
/// erkennbar zu sein, dass drei davon Oberteile sind und eines gar
/// nichts mit Kleidung zu tun hat. Wer "Hemd" suchte, musste alle
/// Eintraege durchsehen.
///
/// JETZT: sieben Kategorien. Jede Kategorie hat eigene Werte, und
/// hoechstens EIN Wert je Kategorie ist waehlbar - "Hemd" und "Bluse"
/// gleichzeitig waere keine Angabe mehr, sondern Unsinn.
///
/// Die Kategorien kommen aus dem Server (public.transit_tag_catalog),
/// die Werte sind im Katalog hier hinterlegt. Der Server ist die
/// Quelle der Wahrheit fuer WAS erlaubt ist, der Client die fuer WIE
/// es aussieht.
class TransitTagCategory {
  const TransitTagCategory(this.slug, this.icon);

  /// Technischer Slug (serverseitig in transit_tag_catalog).
  final String slug;

  final IconData icon;

  /// L10n-Schluessel des Kategorienamens.
  String get labelKey => 'transit.cat.$slug';

  /// Reihenfolge der Anzeige.
  ///
  /// BEFUND (07.11.2026, Betreiber): "es so schon echt voll, braucht es
  /// schon fast ein Redesign vom wie siehst du aus screen."
  ///
  /// Die Reihenfolge ist deshalb nach der Bedeutung sortiert, nicht nach
  /// dem Alphabet: Was man im Gesicht sieht, steht oben. Die Haare sind
  /// das Erste, was andere wahrnehmen - und der Bildschirm heisst
  /// "Wie siehst du gerade aus?". Vorher standen die Haare ganz hinten
  /// (nach Ober- und Unterteil), also genau dort, wo niemand hinschaut.
  ///
  /// "Haarlaenge" und "Frisur" sind eigene Kategorien (Migration 188):
  /// je Kategorie ist nur EIN Merkmal erlaubt, und "lockig" UND "lang"
  /// ist keine Alternative, sondern eine vollstaendige Beschreibung. In
  /// derselben Kategorie haetten sie sich ausgeschlossen.
  static const List<TransitTagCategory> values = [
    TransitTagCategory('hair', Icons.face_retouching_natural),
    TransitTagCategory('hair_length', Icons.straighten),
    TransitTagCategory('hair_style', Icons.auto_awesome),
    TransitTagCategory('eyes', Icons.remove_red_eye_outlined),
    TransitTagCategory('head', Icons.face),
    TransitTagCategory('top', Icons.checkroom),
    TransitTagCategory('bottom', Icons.airline_seat_legroom_reduced),
    TransitTagCategory('shoes', Icons.ice_skating),
    TransitTagCategory('accessory', Icons.watch),
  ];

  static TransitTagCategory? bySlug(String slug) {
    for (final c in values) {
      if (c.slug == slug) return c;
    }
    return null;
  }
}

/// Merkmal-Tags (v0.9.0, Kategoriesystem v0.10.0).
///
/// Es gibt ZWEI getrennte Merkmals-Stroeme, die denselben Katalog
/// benutzen:
///
///  * [TransitTag] an der ANDEREN Person (was ich an ihr gesehen habe)
///    - gespeichert in transit_signals.tags
///  * [TransitTag] ueber sich selbst (wie ich aussehe)
///    - gespeichert in transit_signals.self_tags
///
/// Die Wire-Form bleibt FLACH: ein Slug je Array-Element, Farbe als
/// 'slug:farbe'. Grund: das Matching vergleicht Slugs. Ein
/// 'kategorie:wert'-Format wuerde alle Bestandswerte neu kodieren
/// muessen.
///
/// Haar- und Augenfarben haben eine EIGENE Palette. "schwarz" bei der
/// Kleidung und "schwarz" beim Haar sind verschiedene Angaben - mit
/// derselben Liste wuerde ein schwarzes Hemd mit schwarzem Haar
/// gleichgesetzt. Die Verwechslung wird dadurch verhindert, dass die
/// SLUGS verschieden sind ('hoodie:black' vs. 'hair_color:black').
class TransitTag {
  const TransitTag(
    this.slug,
    this.icon, {
    this.colorizable = false,
    this.category = 'top',
    this.allowedColors,
    this.allowedValues,
    this.searchAliases = const <String>[],
  });

  /// Technischer Slug (auch fuer das Matching, serverseitig whitelisted
  /// ueber public.transit_tag_catalog).
  final String slug;

  final IconData icon;

  /// Farbwahl moeglich (optional, ueberspringbar) - Tag wird dann als
  /// 'slug:color' gesendet.
  final bool colorizable;

  /// Kategorie-Slug (siehe [TransitTagCategory]).
  final String category;

  /// Eigene Farbpalette. Leer = die Standard-Kleidungspalette.
  ///
  /// Die Kleidung nutzt "black/white/grey/...", das Haar "blonde/
  /// braun/schwarz/..." und die Augen "braun/blau/gruen/...". Ohne
  /// getrennte Listen wuerde "schwarz" bei beiden dasselbe bedeuten.
  final List<String>? allowedColors;

  /// Eigene Werteliste (v0.10.0, Migration 187).
  ///
  /// BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen,
  /// also Hairstyle und so." Der Server kannte "hair_length" und
  /// "hair_style" schon - aber als blosse Merkmale sind sie wertlos:
  /// "hair_style" als Aussage sagt nichts aus ("hat eine Frisur"?).
  ///
  /// Deshalb hat der Katalog eine dritte Art von Wert bekommen:
  /// neben "slug" (Ja/Nein) und "slug:farbe" jetzt auch "slug:wert"
  /// ("hair_style:lockig").
  final List<String>? allowedValues;

  /// Zusaetzliche Schreibweisen fuer die Suche (z. B. 't-shirt' fuer
  /// 'tshirt'). Kleinbuchstaben, ohne Umlaute.
  final List<String> searchAliases;

  /// L10n-Schluessel des Labels.
  String get labelKey => 'transit.tag.$slug';

  /// Die Farben, die fuer DIESEN Wert wahlbar sind.
  ///
  /// Heisst "availableColors" und nicht "colors", weil es die statische
  /// Liste [TransitTag.colors] (die Kleidungspalette) bereits gibt.
  List<String> get availableColors =>
      allowedColors ?? (colorizable ? TransitTag.clothingColors : const []);

  /// Die Werte, die fuer DIESEN Merkmal wahlbar sind (leer = keine).
  List<String> get availableValues => allowedValues ?? const [];

  /// Hat dieses Merkmal eine Werteliste? Dann wird es als
  /// 'slug:wert' gesendet.
  bool get hasValues => availableValues.isNotEmpty;

  /// Kleidungsfarben - die Standardpalette.
  static const List<String> clothingColors = [
    'black',
    'white',
    'grey',
    'blue',
    'green',
    'red',
    'yellow',
    'orange',
    'pink',
    'brown',
    'purple',
    'teal',
  ];

  /// Haarfarben. EIGENE Palette, siehe [allowedColors].
  ///
  /// BEFUND (06.11.2026, Betreiber): "Es muss mehr Haarfarben zur
  /// Auswahl geben." Die acht Werte decken nur die grobsten
  /// Unterscheidungen ab - "dunkelbraun" und "hellbraun" sind fuer
  /// viele Menschen genau die Unterscheidung, die zaehlt, und "Kupferrot"
  /// sieht anders aus als "Rot".
  ///
  /// Die Reihenfolge hier ist die Reihenfolge in der Auswahl. Der
  /// Server kennt dieselben Werte (public.transit_tag_catalog,
  /// Migration 184 und 186) - ein Wert, den der Server nicht kennt,
  /// wird beim Senden abgelehnt.
  ///
  /// BEFUND (07.11.2026, Betreiber): "Zudem soll bei Haarfarben auch
  /// noch sowas wie lila usw. sein." Migration 186 hat die Palette um
  /// lila, rosa, blau und gruen erweitert - 18 Werte.
  static const List<String> hairColors = [
    'black',
    'brown',
    'darkbrown',
    'lightbrown',
    'blonde',
    'platinum',
    'red',
    'copper',
    'auburn',
    'grey',
    'silver',
    'saltpepper',
    'white',
    'bald',
    'purple',
    'pink',
    'blue',
    'green',
  ];

  /// Haarlaengen. EIGENE Werteliste, siehe [allowedValues].
  ///
  /// BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen,
  /// also Hairstyle und so." Der Server kannte "hair_length" schon -
  /// aber ohne Werte war das Merkmal wertlos ("hat Haarlaenge"?).
  /// Migration 187 hat die Werteliste eingefuehrt.
  ///
  /// Die Reihenfolge hier ist die Reihenfolge in der Auswahl. Der Server
  /// kennt dieselben Werte (public.transit_tag_catalog, Migration 187).
  static const List<String> hairLengthValues = [
    'kurz',
    'schulterlang',
    'mittel',
    'lang',
    'sehrlang',
    'schulter',
    'stoppeln',
  ];

  /// Frisuren. EIGENE Werteliste, siehe [allowedValues].
  ///
  /// BEFUND (07.11.2026, Betreiber): "also Hairstyle und so."
  /// Migration 187 hat die Werteliste eingefuehrt.
  static const List<String> hairStyleValues = [
    'glatt',
    'lockig',
    'gewellt',
    'kraus',
    'flechtig',
    'zopf',
    'ponytail',
    'kurz_geschnitten',
  ];

  /// Augenfarben. EIGENE Palette, siehe [allowedColors].
  static const List<String> eyeColors = [
    'brown',
    'blue',
    'green',
    'grey',
    'hazel',
    'bluegrey',
    'amber',
  ];

  /// Die in der alten Fassung (v0.9.0) benutzten 12 Farben. Der Name
  /// bleibt, weil die Farbslugs in der Datenbank und in den
  /// L10n-Texten so vergeben sind.
  static const List<String> colors = clothingColors;

  /// Material-Farbe je Farbslug (Fallback grau bei unbekanntem Slug).
  static Color swatchOf(String color) => colorSwatch[color] ?? Colors.grey;

  /// Hauptfarbe eines Kleckses (Fallback grau bei unbekanntem Slug).
  static const Map<String, Color> colorSwatch = {
    'black': Colors.black,
    'white': Colors.white,
    'grey': Color(0xFF9E9E9E),
    'blue': Color(0xFF2196F3),
    'green': Color(0xFF4CAF50),
    'red': Color(0xFFF44336),
    'yellow': Color(0xFFFFEB3B),
    'orange': Color(0xFFFF9800),
    'pink': Color(0xFFE91E63),
    'brown': Color(0xFF795548),
    'purple': Color(0xFF9C27B0),
    'teal': Color(0xFF009688),
    // Haarfarben
    'blonde': Color(0xFFD9B36C),
    'auburn': Color(0xFF8B3A2A),
    'bald': Color(0xFFE0C9A6),
    'darkbrown': Color(0xFF4E342E),
    'lightbrown': Color(0xFFA1887F),
    'copper': Color(0xFFB87333),
    'platinum': Color(0xFFE8D8A0),
    'silver': Color(0xFFC0C0C0),
    'saltpepper': Color(0xFF7A7A7A),
    // Augenfarben
    'hazel': Color(0xFF9C7B4E),
    'bluegrey': Color(0xFF7A8C99),
    'amber': Color(0xFFC58F35),
  };

  static String colorLabelKey(String color) => 'transit.color.$color';

  /// Der Katalog, in Kategorien gegliedert (v0.10.0, Migration 148).
  ///
  /// Reihenfolge = Anzeigereihenfolge. Jeder Wert gehoert zu genau
  /// einer Kategorie, und je Kategorie ist hoechstens ein Wert waehlbar.
  static const List<TransitTag> catalog = [
    // ---- Oberteil
    TransitTag(
      'hemd',
      Icons.checkroom,
      colorizable: true,
      category: 'top',
      searchAliases: ['shirt', 'hemden', 'oberhemd'],
    ),
    TransitTag(
      'bluse',
      Icons.checkroom_outlined,
      colorizable: true,
      category: 'top',
      searchAliases: ['blouse'],
    ),
    TransitTag(
      'tshirt',
      Icons.abc,
      colorizable: true,
      category: 'top',
      searchAliases: ['t-shirt', 'shirt', 'tee'],
    ),
    TransitTag(
      'hoodie',
      Icons.checkroom,
      colorizable: true,
      category: 'top',
      searchAliases: ['kapuzenpulli', 'kapuzenpullover'],
    ),
    TransitTag(
      'pullover',
      Icons.dry_cleaning,
      colorizable: true,
      category: 'top',
      searchAliases: ['pulli', 'strickpullover', 'sweater'],
    ),
    TransitTag(
      'jacke',
      Icons.dry_cleaning,
      colorizable: true,
      category: 'top',
      searchAliases: ['jacken', 'mantel'],
    ),
    TransitTag(
      'weste',
      Icons.dry_cleaning,
      colorizable: true,
      category: 'top',
      searchAliases: ['gilet', 'vest'],
    ),
    // ---- Unterteil
    TransitTag(
      'hose',
      Icons.checkroom_outlined,
      colorizable: true,
      category: 'bottom',
      searchAliases: ['hosen', 'pants'],
    ),
    TransitTag(
      'jeans',
      Icons.checkroom_outlined,
      colorizable: true,
      category: 'bottom',
      searchAliases: ['denim'],
    ),
    TransitTag(
      'rock',
      Icons.dry_cleaning,
      colorizable: true,
      category: 'bottom',
      searchAliases: ['rocke', 'kleid'],
    ),
    TransitTag(
      'shorts',
      Icons.airline_seat_legroom_reduced,
      colorizable: true,
      category: 'bottom',
      searchAliases: ['kurze hose', 'kurzhosen'],
    ),
    TransitTag(
      'leggings',
      Icons.checkroom_outlined,
      colorizable: true,
      category: 'bottom',
      searchAliases: ['leggins'],
    ),
    // ---- Kopf
    TransitTag(
      'cap',
      Icons.sports_baseball,
      colorizable: true,
      category: 'head',
      searchAliases: ['muetze', 'kappe'],
    ),
    TransitTag(
      'muetze',
      Icons.face,
      colorizable: true,
      category: 'head',
      searchAliases: ['beanie', 'stirnband'],
    ),
    TransitTag('helm', Icons.motorcycle, category: 'head'),
    // ---- Schuhe
    TransitTag(
      'sneaker',
      Icons.ice_skating,
      colorizable: true,
      category: 'shoes',
      searchAliases: ['schuhe', 'turnschuhe', 'sneakers'],
    ),
    TransitTag(
      'stiefel',
      Icons.ice_skating,
      colorizable: true,
      category: 'shoes',
      searchAliases: ['stiefel', 'boots'],
    ),
    TransitTag('sandalen', Icons.ice_skating, category: 'shoes'),
    TransitTag(
      'halbschuhe',
      Icons.ice_skating,
      colorizable: true,
      category: 'shoes',
      searchAliases: ['schuhe', 'loafer'],
    ),
    // ---- Accessoires
    TransitTag(
      'brille',
      Icons.visibility,
      category: 'accessory',
      searchAliases: ['glasses', 'sonnenbrille'],
    ),
    TransitTag(
      'kopfhoerer',
      Icons.headphones,
      category: 'accessory',
      searchAliases: ['headphones', 'ohrhoerer'],
    ),
    TransitTag(
      'schal',
      Icons.stay_current_landscape,
      colorizable: true,
      category: 'accessory',
      searchAliases: ['stola', 'tuch'],
    ),
    TransitTag(
      'rucksack',
      Icons.backpack,
      category: 'accessory',
      searchAliases: ['backpack'],
    ),
    TransitTag(
      'tasche',
      Icons.shopping_bag,
      colorizable: true,
      category: 'accessory',
      searchAliases: ['shoppingbag', 'tote bag', 'umhaengetasche'],
    ),
    TransitTag(
      'ausweis',
      Icons.badge,
      category: 'accessory',
      searchAliases: ['lanyard', 'badge'],
    ),
    TransitTag(
      'sportlich',
      Icons.fitness_center,
      category: 'accessory',
      searchAliases: ['sportkleidung', 'sporty'],
    ),
    // ---- Haar
    TransitTag(
      'hair_color',
      Icons.face_retouching_natural,
      colorizable: true,
      category: 'hair',
      allowedColors: hairColors,
      searchAliases: ['haarfarbe', 'hair colour'],
    ),
    TransitTag(
      'hair_length',
      Icons.straighten,
      // EIGENE Kategorie (Migration 188): je Kategorie ist nur EIN
      // Merkmal erlaubt. Haarlaenge und Frisur sind keine Alternative,
      // sondern zwei Angaben - in derselben Kategorie wuerden sie sich
      // ausschliessen.
      category: 'hair_length',
      // BEFUND (07.11.2026, Betreiber): "also Hairstyle und so". Als
      // blosse Merkmale waren Haarlaenge und Frisur wertlos ("hat
      // Haarlaenge?"). Migration 187 hat die Wertelisten eingefuehrt.
      allowedValues: hairLengthValues,
      searchAliases: ['haarlaenge', 'hair length'],
    ),
    TransitTag(
      'hair_style',
      Icons.auto_awesome,
      category: 'hair_style',
      allowedValues: hairStyleValues,
      searchAliases: ['frisur', 'haartyp'],
    ),
    // ---- Augen
    TransitTag(
      'eyes_color',
      Icons.remove_red_eye_outlined,
      colorizable: true,
      category: 'eyes',
      allowedColors: eyeColors,
      searchAliases: ['augenfarbe', 'eye colour'],
    ),
  ];

  /// Alle Werte einer Kategorie, in Katalog-Reihenfolge.
  static List<TransitTag> byCategory(String category) =>
      catalog.where((t) => t.category == category).toList();

  /// Sucht im Katalog.
  ///
  /// Verglichen wird gegen den Slug und die Schreibweisen aus
  /// [searchAliases]. Die SUCHE IM TEXT des Labels braucht die
  /// Uebersetzung und passiert deshalb in der Oberflaeche, nicht hier.
  static List<TransitTag> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return catalog;
    final normalisiert = q
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(' ', '-');
    return catalog.where((t) {
      if (t.slug.toLowerCase().contains(normalisiert)) return true;
      for (final alias in t.searchAliases) {
        if (alias.toLowerCase().contains(normalisiert)) return true;
      }
      return false;
    }).toList();
  }

  static TransitTag? bySlug(String slug) {
    final base = slug.split(':').first;
    for (final t in catalog) {
      if (t.slug == base) return t;
    }
    return null;
  }
}

/// Transit-Modi (v0.9.0): Bestimmt die Empfindlichkeit der Encounter-
/// Erkennung CLIENTSEITIG (Messe = nur starke Signale = echter
/// Sichtkontakt); serverseitig nur Metadatum.
enum TransitMode {
  transit('transit', Icons.directions_transit),
  convention('convention', Icons.festival);

  const TransitMode(this.value, this.icon);

  final String value;
  final IconData icon;

  String get labelKey => 'transit.mode.$value';

  /// RSSI-Schwellwert: In Messe-Umgebungen (dichte BLE-Umgebung) zählen
  /// nur starke Signale als echter Sichtkontakt (> -75 dBm).
  int get rssiThreshold => this == TransitMode.convention ? -75 : -100;
}
