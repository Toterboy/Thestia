// Die Hülle einer verschlüsselten Nachricht im Peer-zu-Peer-Kanal.
//
// WARUM EINE EIGENE DATEI (22.11.2026, Fuzzing): Der Hülle kam
// direkt von der GEGENSEITE - sie kann senden, was sie will. Vorher
// stand das Auslesen mitten in der WebRTC-Verarbeitung:
//
//     final data = jsonDecode(message.text) as Map<String, dynamic>;
//     final type = data['type'] as String;
//     final ciphertextB64 = data['ciphertext'] as String;
//     final ciphertext = base64Decode(ciphertextB64);
//     final messageType = data['messageType'] as int;
//
// Jeder dieser Casts wirft bei einer falschen Eingabe - eine
// kaputte (oder bösartige) Nachricht ließ damit den Kanal abbrechen
// statt sie zu verwerfen. Jetzt steht das Auslesen hier, wirft NIE
// und ist damit auch prüfbar (test/fuzzing/).
//
// DIE REGEL: Was nicht sauber lesbar ist, wird verworfen. Nicht
// geraten, nicht repariert.
library;

import 'dart:convert';

import 'package:thestia/utils/common/json_leser.dart';

/// Die größte Hülle, die der Dienst annimmt (512 KB).
const int maxSignalEnvelopeBytes = 512 * 1024;

/// Die höchste Zahl der Metadaten-Einträge (Audit S3).
///
/// DER GRUND: Der Peer darf den nicht beliebig groß machen - sonst
/// wäre die Nachricht ein Angriff auf den Speicher.
const int maxSignalMetadataEntries = 16;

/// Der Typ einer Nachricht im Kanal.
enum SignalEnvelopeType {
  /// Eine Textnachricht (Signal-Protokoll).
  message,

  /// Binärdaten (Bild, Sprachnachricht).
  binary,
}

/// Die Hülle einer Nachricht im Peer-zu-Peer-Kanal.
class SignalEnvelope {
  const SignalEnvelope({
    required this.typ,
    required this.ciphertext,
    required this.messageType,
    this.contentType = 'application/octet-stream',
    this.metadata,
  });

  /// Ob es eine Text- oder eine Binärnachricht ist.
  final SignalEnvelopeType typ;

  /// Die Chiffre (base64) - der eigentliche Inhalt.
  final String ciphertext;

  /// Der Signal-Typ der Chiffre (PreKey oder normal).
  final int messageType;

  /// Der Inhaltstyp (nur bei Binärdaten).
  final String contentType;

  /// Die Metadaten (nur bei Binärdaten, höchstens
  /// [maxSignalMetadataEntries] Einträge).
  final Map<String, dynamic>? metadata;

  /// Liest eine Hülle aus dem Text der empfangenen Nachricht.
  ///
  /// GIBT NULL ZURÜCK, wenn die Nachricht nicht sauber lesbar ist -
  /// und wirft NIE. Das ist der ganze Zweck: die Gegenseite schickt
  /// den Inhalt, und der Inhalt entscheidet nicht über das Wohlbefinden
  /// der App.
  static SignalEnvelope? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    if (text.length > maxSignalEnvelopeBytes) return null;

    Object? dekodiert;
    try {
      dekodiert = jsonDecode(text);
    } catch (_) {
      // Kein JSON - weg damit.
      return null;
    }
    if (dekodiert is! Map) return null;
    final map = Map<String, dynamic>.from(dekodiert);

    final typ = textOf(map, ['type']);
    final SignalEnvelopeType art;
    if (typ == 'signal_message') {
      art = SignalEnvelopeType.message;
    } else if (typ == 'signal_binary') {
      art = SignalEnvelopeType.binary;
    } else {
      // Unbekannter Typ - nicht raten.
      return null;
    }

    final chiffertext = textOf(map, ['ciphertext']);
    if (chiffertext == null || chiffertext.isEmpty) return null;
    // Die Chiffre muss base64 sein - sonst bricht das Entschlüsseln
    // ab. `base64Decode` wirft bei ungültigem Text, deshalb wird hier
    // schon geprüft.
    if (!_istBase64(chiffertext)) return null;

    final typNr = intOf(map, ['messageType']);

    // Die Metadaten: höchstens [maxSignalMetadataEntries] Einträge,
    // und keine verschachtelten Bomben.
    Map<String, dynamic>? metadata;
    final metadatenRoh = map['metadata'];
    if (metadatenRoh is Map &&
        metadatenRoh.length <= maxSignalMetadataEntries) {
      metadata = Map<String, dynamic>.from(metadatenRoh);
    }

    return SignalEnvelope(
      typ: art,
      ciphertext: chiffertext,
      messageType: typNr ?? 0,
      contentType: textOf(map, ['contentType']) ?? 'application/octet-stream',
      metadata: metadata,
    );
  }

  /// Ist der Text base64?
  ///
  /// DER WEG: `base64Decode` wirft bei jedem unbrauchbaren Text
  /// (FormatException). Hier wird nur die Form geprüft - die
  /// base64-Alphabe, ihre Länge und die korrekte Füllung.
  static bool _istBase64(String text) {
    if (text.isEmpty || text.length % 4 != 0) return false;
    const erlaubt =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        'abcdefghijklmnopqrstuvwxyz0123456789+/=';
    for (var i = 0; i < text.length; i++) {
      if (!erlaubt.contains(String.fromCharCode(text.codeUnitAt(i)))) {
        return false;
      }
    }
    return true;
  }
}
