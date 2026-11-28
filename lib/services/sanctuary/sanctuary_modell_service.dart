// Der Import der KI-Modelle (Plan 0.11.0, der Sanctuary).
//
// ENTSCHEIDUNG DES BETREIBERS (27.11.2026): "KI Modelle muss man
// einfach selbst herunterladen." Der Nutzer holt die GGUF-Datei selbst
// (Browser, Dateimanager, PC) und importiert sie hier.
//
// DER WEG: Die App prüft die Datei (echtes GGUF? passt die Größe?), kopiert
// sie in ihr eigenes Verzeichnis (eine Datei im Download-Ordner wäre beim
// Aufräumen weg) und merkt sie sich.
//
// DIE PRÜFUNGEN:
//   * die Datei muss existieren und lesbar sein,
//   * sie muss eine GGUF-Datei sein (die Signatur "GGUF" am Anfang),
//   * sie muss zwischen 50 MB und 20 GB groß sein (das sind echte
//     Modelle - alles Kleine wäre keine brauchbare Datei).
//
// DER SPEICHER: Dart kann den freien Speicher des Geräts nicht
// auslesen (das gibt es nur mit einem Zusatz-Werkzeug). Der Import
// meldet deshalb die Größe des Modells - die App kann dem Nutzer
// sagen, wie viel Platz es braucht.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:thestia/models/sanctuary/sanctuary_empfehlung.dart';
import 'package:thestia/utils/common/best_effort.dart';

/// Ein importiertes Modell (auf dem Gerät).
class SanctuaryModell {
  const SanctuaryModell({
    required this.pfad,
    required this.groesseBytes,
    required this.importiertAm,
    this.empfehlungId,
  });

  /// Der Pfad der Datei (im App-Verzeichnis).
  final String pfad;

  /// Die Größe in Bytes.
  final int groesseBytes;

  /// Wann es importiert wurde.
  final DateTime importiertAm;

  /// Die Empfehlung, zu der es gehört (null = ein fremdes Modell).
  final String? empfehlungId;

  /// Der Name (der Dateiname).
  ///
  /// DER WEG: Auf Windows trennt ein Backslash - deshalb wird auf
  /// beide Trenner geachtet.
  String get name {
    final datei = pfad.split(RegExp(r'[/\\]')).last;
    return datei.isEmpty ? pfad : datei;
  }

  /// Die Größe in MB (gerundet).
  int get groesseMb => (groesseBytes / (1024 * 1024)).round();

  /// Passt das Modell zu einer Empfehlung?
  ///
  /// DER WEG: Über den Dateinamen (die Modelle heißen nach dem
  /// Repository). Eine Prüfung des Inhalts wäre der bessere Weg - der
  /// Dateiname reicht für den Hinweis.
  bool passtZu(SanctuaryEmpfehlung empfehlung) {
    return SanctuaryKatalog.passendZu(name)?.id == empfehlung.id;
  }
}

/// Warum ein Import nicht geklappt hat.
class SanctuaryImportFehler {
  const SanctuaryImportFehler(this.code, this.text);

  /// Der Code (für die Oberfläche).
  final String code;

  /// Der Text (deutsch).
  final String text;

  static const SanctuaryImportFehler dateiFehlt = SanctuaryImportFehler(
    'datei_fehlt',
    'Die Datei wurde nicht gefunden.',
  );
  static const SanctuaryImportFehler keinGguf = SanctuaryImportFehler(
    'kein_gguf',
    'Das ist keine GGUF-Datei (die Signatur "GGUF" fehlt am Anfang).',
  );
  static const SanctuaryImportFehler zuKlein = SanctuaryImportFehler(
    'zu_klein',
    'Die Datei ist zu klein für ein Sprachmodell (mindestens 50 MB).',
  );
  static const SanctuaryImportFehler zuGross = SanctuaryImportFehler(
    'zu_gross',
    'Die Datei ist zu groß für das Modell (höchstens 20 GB).',
  );
}

/// Das Ergebnis eines Imports.
class SanctuaryImportErgebnis {
  const SanctuaryImportErgebnis.erfolg(this.modell) : fehler = null;

  const SanctuaryImportErgebnis.fehler(this.fehler) : modell = null;

  /// Das importierte Modell (null, wenn es nicht geklappt hat).
  final SanctuaryModell? modell;

  /// Der Grund (null, wenn es geklappt hat).
  final SanctuaryImportFehler? fehler;

  /// Hat es geklappt?
  bool get ok => modell != null;
}

/// Der Dienst: die importierten Modelle und der Import.
class SanctuaryModellService {
  SanctuaryModellService({
    this.basis,
    this.mindestGroesseMb = 50,
    this.maxGroesseMb = 20000,
  });

  /// Das Verzeichnis, in dem die Modelle liegen (im Test ein Temp-Ordner).
  final Directory? basis;

  /// Die kleinste Datei, die als Modell gilt (in MB).
  ///
  /// DER GRUND: Der Wert ist ein Parameter - im Test wird eine winzige
  /// Datei benutzt (ein 60-MB-Test wäre langsam).
  final double mindestGroesseMb;

  /// Die größte Datei, die noch sinnvoll ist (in MB).
  final double maxGroesseMb;

  /// Das Verzeichnis der Modelle (im App-Support-Ordner).
  Future<Directory> _verzeichnis() async {
    final ordner = basis;
    final ziel =
        ordner ??
        Directory('${(await getApplicationSupportDirectory()).path}/sanctuary');
    if (!await ziel.exists()) {
      await ziel.create(recursive: true);
    }
    return ziel;
  }

  /// Die importierten Modelle (das neueste zuerst).
  Future<List<SanctuaryModell>> importierteModelle() async {
    final ordner = await _verzeichnis();
    if (!await ordner.exists()) return const <SanctuaryModell>[];
    final liste = <SanctuaryModell>[];
    await for (final eintrag in ordner.list()) {
      if (eintrag is! File) continue;
      if (!eintrag.path.toLowerCase().endsWith('.gguf')) continue;
      final stat = await eintrag.stat();
      liste.add(
        SanctuaryModell(
          pfad: eintrag.path,
          groesseBytes: stat.size,
          importiertAm: stat.modified,
        ),
      );
    }
    liste.sort((a, b) => b.importiertAm.compareTo(a.importiertAm));
    return liste;
  }

  /// Importiert eine GGUF-Datei.
  ///
  /// DER WEG: prüfen, kopieren, merken. Die Originaldatei bleibt, wo
  /// sie ist (der Nutzer hat sie heruntergeladen - die App stört ihn
  /// nicht damit).
  Future<SanctuaryImportErgebnis> importieren(String quelldatei) async {
    final quelle = File(quelldatei);
    if (!await quelle.exists()) {
      return const SanctuaryImportErgebnis.fehler(
        SanctuaryImportFehler.dateiFehlt,
      );
    }
    final fehler = await _pruefe(quelle);
    if (fehler != null) {
      return SanctuaryImportErgebnis.fehler(fehler);
    }

    final ordner = await _verzeichnis();
    final ziel = File('${ordner.path}/${_dateiname(quelle.path)}');
    final kopiert = await bestEffortOr<bool>(
      'sanctuary.import kopieren',
      () async {
        await quelle.copy(ziel.path);
        return true;
      },
      false,
    );
    if (!kopiert) {
      return const SanctuaryImportErgebnis.fehler(
        SanctuaryImportFehler.dateiFehlt,
      );
    }
    final stat = await ziel.stat();
    return SanctuaryImportErgebnis.erfolg(
      SanctuaryModell(
        pfad: ziel.path,
        groesseBytes: stat.size,
        importiertAm: stat.modified,
      ),
    );
  }

  /// Löscht ein importiertes Modell (die Datei im App-Verzeichnis).
  Future<void> loeschen(String pfad) async {
    await bestEffortOr<void>('sanctuary.loeschen', () async {
      final datei = File(pfad);
      if (await datei.exists()) await datei.delete();
    }, null);
  }

  /// Die Prüfungen vor dem Import (null = alles in Ordnung).
  Future<SanctuaryImportFehler?> _pruefe(File quelle) async {
    final stat = await quelle.stat();
    final mb = stat.size / (1024 * 1024);
    if (mb < mindestGroesseMb) return SanctuaryImportFehler.zuKlein;
    if (mb > maxGroesseMb) return SanctuaryImportFehler.zuGross;

    // DIE SIGNATUR: Eine GGUF-Datei beginnt mit "GGUF".
    final kopf = await bestEffortOr<List<int>>(
      'sanctuary.kopf lesen',
      () async {
        final bytes = await quelle
            .openRead(0, 4)
            .fold<List<int>>(<int>[], (vorher, bytes) => [...vorher, ...bytes]);
        return bytes;
      },
      const <int>[],
    );
    if (String.fromCharCodes(kopf) != 'GGUF') {
      return SanctuaryImportFehler.keinGguf;
    }
    return null;
  }

  /// Der Name, unter dem das Modell gespeichert wird.
  String _dateiname(String quelle) {
    final datei = quelle.split(RegExp(r'[/\\]')).last;
    return datei.toLowerCase().endsWith('.gguf') ? datei : '$datei.gguf';
  }
}
