// Die empfohlenen KI-Modelle für den Sanctuary (Plan 0.11.0).
//
// ENTSCHEIDUNG DES BETREIBERS (27.11.2026): "KI Modelle muss man
// einfach selbst herunterladen. Ein paar könnte man aber vielleicht als
// Empfehlung nennen oder so."
//
// DER WEG: Die App lädt NICHTS selbst herunter - der Nutzer holt die
// GGUF-Datei selbst (Browser, Dateimanager, PC) und importiert sie.
// Die App nennt dazu ein paar Empfehlungen: Name, Herkunft, Größe,
// RAM-Bedarf und Lizenz.
//
// WARUM DAS GUT IST: Die App ruft keinen fremden Dienst ab - kein
// Metadatenabruf, keine IP-Adresse bei einem US-Anbieter. Wer das Modell
// herunterlädt, entscheidet das selbst (und kann einen eigenen Spiegel
// nehmen). Das Drittlandproblem stellt sich damit nicht.

/// Ein empfohlenes Modell.
///
/// DER HINWEIS: Die Angaben sind Empfehlungen, keine Garantie - die
/// Lizenz hängt vom jeweiligen Repository ab und muss vor dem Download
/// geprüft werden. Deshalb steht sie hier als Text und nicht als
/// durchgesetzte Bedingung.
class SanctuaryEmpfehlung {
  const SanctuaryEmpfehlung({
    required this.id,
    required this.name,
    required this.herkunft,
    required this.groesseMb,
    required this.ramMb,
    required this.lizenz,
    required this.beschreibung,
    required this.quantisierungen,
  });

  /// Der technische Name (der Schlüssel in der Liste).
  final String id;

  /// Der Name, den der Nutzer sieht.
  final String name;

  /// Woher das Modell kommt (die Firma und das Lager).
  final String herkunft;

  /// Die Größe der Datei in MB (die übliche Variante Q4_K_M).
  final int groesseMb;

  /// Wie viel RAM das Modell braucht (Faustregel: noch ein GB obendrauf).
  final int ramMb;

  /// Die Lizenz (ein Hinweis - vor dem Download prüfen).
  final String lizenz;

  /// Wofür das Modell gut ist.
  final String beschreibung;

  /// Die Quantisierungen, die es davon gibt.
  final List<String> quantisierungen;

  /// Der Text für die Oberfläche (der Schlüssel im l10n).
  String get textKey => 'sanctuary.model.$id';
}

/// Der Katalog: die Modelle, die die App empfiehlt.
///
/// DER KATALOG IST EINE INFORMATION, KEIN DOWNLOAD: Die App nennt die
/// Modelle - heruntergeladen wird selbst.
///
/// DIE GRÖSSEN: Sie stammen aus dem Plan (27.11.2026) und sind
/// Erfahrungswerte für die mobile Nutzung. Sie können je nach
/// Quantisierung abweichen - der Import prüft die tatsächliche Größe
/// und warnt, wenn der Speicher nicht reicht.
class SanctuaryKatalog {
  SanctuaryKatalog._();

  /// Die Stufe 1: kompakt und akkusparend (für die meisten Geräte).
  static const List<SanctuaryEmpfehlung> stufe1 = <SanctuaryEmpfehlung>[
    SanctuaryEmpfehlung(
      id: 'gemma4e2b',
      name: 'Gemma 4 E2B',
      herkunft: 'Google (Hugging Face)',
      groesseMb: 1100,
      ramMb: 1500,
      lizenz: 'Apache-2.0 (Prüfen vor dem Download)',
      beschreibung: 'Kompakt und schnell - das Modell für die meisten Geräte.',
      quantisierungen: <String>['Q4_K_M', 'Q5_K_M', 'Q3_K_S'],
    ),
    SanctuaryEmpfehlung(
      id: 'spark25',
      name: 'Spark-X2.5 1.7B',
      herkunft: 'iFlytek (Hugging Face)',
      groesseMb: 1200,
      ramMb: 1600,
      lizenz: 'Lizenz des Repositorys prüfen',
      beschreibung:
          'Gut im Deutschen, kompakt - eine gute Wahl für lange Texte.',
      quantisierungen: <String>['Q4_K_M', 'Q5_K_M', 'Q3_K_S'],
    ),
  ];

  /// Die Stufe 2: großer und gründlicher (braucht mehr RAM und Speicher).
  static const List<SanctuaryEmpfehlung> stufe2 = <SanctuaryEmpfehlung>[
    SanctuaryEmpfehlung(
      id: 'qwen35',
      name: 'Qwen 3.5 4B',
      herkunft: 'Alibaba (Hugging Face)',
      groesseMb: 2900,
      ramMb: 3200,
      lizenz: 'Apache-2.0 (Prüfen vor dem Download)',
      beschreibung:
          'Gründlicher und sprachstark - für lange, schwierige Texte.',
      quantisierungen: <String>['Q4_K_M', 'Q5_K_M', 'Q6_K', 'IQ3'],
    ),
    SanctuaryEmpfehlung(
      id: 'gemma4e4b',
      name: 'Gemma 4 E4B',
      herkunft: 'Google (Hugging Face)',
      groesseMb: 2500,
      ramMb: 3000,
      lizenz: 'Apache-2.0 (Prüfen vor dem Download)',
      beschreibung:
          'Ausgewogen und schnell - der beste Kompromiss aus Qualität und '
          'Größe.',
      quantisierungen: <String>['Q4_K_M', 'Q5_K_M', 'Q6_K', 'IQ3'],
    ),
    SanctuaryEmpfehlung(
      id: 'spark25gross',
      name: 'Spark-X2.5 4B',
      herkunft: 'iFlytek (Hugging Face)',
      groesseMb: 2900,
      ramMb: 3200,
      lizenz: 'Lizenz des Repositorys prüfen',
      beschreibung:
          'Gut im Deutschen, tiefer in der Reflexion - für lange Gespräche.',
      quantisierungen: <String>['Q4_K_M', 'Q5_K_M', 'Q6_K'],
    ),
  ];

  /// Alle Empfehlungen (die leichte Stufe zuerst).
  static List<SanctuaryEmpfehlung> get alle => <SanctuaryEmpfehlung>[
    ...stufe1,
    ...stufe2,
  ];

  /// Die Empfehlung mit diesem technischen Namen (null, wenn unbekannt).
  static SanctuaryEmpfehlung? nachId(String id) {
    for (final e in alle) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Die Empfehlung, die zum Dateinamen passt (null, wenn keine).
  ///
  /// DER WEG: Der Dateiname nennt das Modell (die Dateien heißen nach
  /// dem Repository). Bei zwei ähnlichen Namen ("spark25" und
  /// "spark25gross") gewinnt der LÄNGERE - sonst würde das kleine Modell
  /// immer zum großen passen.
  static SanctuaryEmpfehlung? passendZu(String dateiname) {
    final kurz = dateiname.toLowerCase();
    SanctuaryEmpfehlung? best;
    for (final e in alle) {
      if (!kurz.contains(e.id.toLowerCase())) continue;
      if (best == null || e.id.length > best.id.length) best = e;
    }
    return best;
  }
}
