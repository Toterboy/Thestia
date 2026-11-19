/// Die Huelle einer Chat-Nachricht auf dem Draht.
///
/// WARUM ES SIE GIBT (11.11.2026): "Nachricht fuer alle loeschen" - wie
/// bei WhatsApp. Damit das ueberhaupt geht, muss BEIDEN Seiten dieselbe
/// Nachrichten-ID kennen: die loeschende Seite markiert eine ID, die
/// empfangende Seite muss genau diese Nachricht ersetzen.
///
/// Bisher hatte jede Nachricht eine lokale ID:
///   - im Relay: `relay_<serverzeile>` (die ID der Relay-Zeile)
///   - im P2P-Kanal: `p2p_<millisekunde>_<zaehler>` (lokal erzeugt)
///
/// Zwei Geraete hatten damit zwei verschiedene IDs fuer dieselbe Nachricht
/// - ein Loeschen haette beim Empfaenger nichts gefunden. Und dieselbe
/// Nachricht, die ueber BEIDE Wege kam (P2P und Relay), sahen die
/// Geraete auch als zwei verschiedene an.
///
/// DIE HULLE: `__T2__|<id>|<art>|<text>`
///   - `id`   die Nachrichten-ID des SENDERS (auf beiden Seiten gleich)
///   - `art`  `t` = Text, `i` = Eisbrecher
///   - `text` der Text (darf `|` enthalten - es wird nur an den ersten
///     drei Trennern getrennt)
///
/// RUECKWAERTSKOMPATIBILITAET: Eine Nachricht ohne `__T2__|` ist von
/// einer aelteren App. Sie wird wie bisher behandelt (lokale ID, der
/// Eisbreker-Praefix wird erkannt). Da die App noch nicht im Store ist,
/// gibt es solche alten Clients nur auf den Geraeten des Betreibers -
/// beide Handys brauchen den neuen Build.
library;

/// Der Anfang jeder neuen Huelle.
const String envelopePrefix = '__T2__|';

/// Die Art einer Nachricht auf dem Draht.
enum WireKind {
  /// Ein normaler Text.
  text('t'),

  /// Ein Eisbrecher (die gemeinsame Frage in der Mitte).
  icebreaker('i');

  const WireKind(this.code);

  /// Das Kuerzel im Drahtformat.
  final String code;

  /// Aus dem Kuerzel die Art machen (null bei unbekannt).
  static WireKind? fromCode(String code) {
    for (final k in WireKind.values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Eine auseinandergepackte Nachricht.
class WireMessage {
  const WireMessage({
    required this.id,
    required this.kind,
    required this.text,
    this.fromNewFormat = false,
  });

  /// Die Nachrichten-ID des Senders (bei der alten Form: leer).
  final String id;

  /// Die Art.
  final WireKind kind;

  /// Der Text.
  final String text;

  /// Kommt die Nachricht aus der neuen Huelle?
  ///
  /// Bei `false` muss die aufrufende Seite selbst eine ID vergeben (so wie
  /// es vor der Huelle war).
  final bool fromNewFormat;
}

/// Baut die Huelle fuer eine Nachricht.
///
/// [id] muss die ID des Senders sein - sie wird auf beiden Seiten
/// benutzt.
String buildEnvelope({
  required String id,
  required WireKind kind,
  required String text,
}) {
  return '$envelopePrefix$id|${kind.code}|$text';
}

/// Zerlegt eine Nachricht aus dem Draht.
///
/// Ist die Nachricht nicht in der neuen Form, kommt
/// [WireMessage.fromNewFormat] zurueck - der Aufrufer vergibt dann wie
/// bisher eine lokale ID.
WireMessage parseEnvelope(String wire) {
  if (!wire.startsWith(envelopePrefix)) {
    return WireMessage(
      id: '',
      kind: WireKind.text,
      text: wire,
      fromNewFormat: false,
    );
  }
  final rest = wire.substring(envelopePrefix.length);
  // Nur die ersten drei Trenner trennen - der Text darf '|' enthalten.
  final teile = rest.split('|');
  if (teile.length < 3) {
    // Unvollstaendige Huelle: als Text behandeln (lieber anzeigen als
    // verlieren).
    return WireMessage(
      id: '',
      kind: WireKind.text,
      text: wire,
      fromNewFormat: false,
    );
  }
  final id = teile[0];
  final art = WireKind.fromCode(teile[1]);
  final text = teile.sublist(2).join('|');
  if (art == null || id.isEmpty) {
    return WireMessage(
      id: '',
      kind: WireKind.text,
      text: wire,
      fromNewFormat: false,
    );
  }
  return WireMessage(id: id, kind: art, text: text, fromNewFormat: true);
}
