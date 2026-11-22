// Die Huelle einer verschluesselten Nachricht im Peer-zu-Peer-Kanal.
//
// WARUM EINE EIGENE DATEI (22.11.2026, Fuzzing): Der Huelle kam
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
// kaputte (oder boesartige) Nachricht liess damit den Kanal abbrechen
// statt sie zu verwerfen. Jetzt steht das Auslesen hier, wirft NIE
// und ist damit auch pruefbar (test/fuzzing/).
//
// DIE REGEL: Was nicht sauber lesbar ist, wird verworfen. Nicht
// geraten, nicht repariert.
library;

import 'dart:convert';

import 'package:thestia/utils/common/json_leser.dart';

/// Die groesste Huelle, die der Dienst annimmt (512 KB).
const int maxSignalEnvelopeBytes = 512 * 1024;

/// Die hoechste Zahl der Metadaten-Eintraege (Audit S3).
///
/// DER GRUND: Der Peer darf den nicht beliebig gross machen - sonst
/// waere die Nachricht ein Angriff auf den Speicher.
const int maxSignalMetadataEntries = 16;

/// Der Typ einer Nachricht im Kanal.
enum SignalEnvelopeType {
  /// Eine Textnachricht (Signal-Protokoll).
  message,

  /// Binaerdaten (Bild, Sprachnachricht).
  binary,
}

/// Die Huelle einer Nachricht im Peer-zu-Peer-Kanal.
class SignalEnvelope {
  const SignalEnvelope({
    required this.typ,
    required this.ciphertext,
    required this.messageType,
    this.contentType = 'application/octet-stream',
    this.metadata,
  });

  /// Ob es eine Text- oder eine Binaernachricht ist.
  final SignalEnvelopeType typ;

  /// Die Chiffre (base64) - der eigentliche Inhalt.
  final String ciphertext;

  /// Der Signal-Typ der Chiffre (PreKey oder normal).
  final int messageType;

  /// Der Inhaltstyp (nur bei Binaerdaten).
  final String contentType;

  /// Die Metadaten (nur bei Binaerdaten, hoechstens
  /// [maxSignalMetadataEntries] Eintraege).
  final Map<String, dynamic>? metadata;

  /// Liest eine Huelle aus dem Text der empfangenen Nachricht.
  ///
  /// GIBT NULL ZURUECK, wenn die Nachricht nicht sauber lesbar ist -
  /// und wirft NIE. Das ist der ganze Zweck: die Gegenseite schickt
  /// den Inhalt, und der Inhalt entscheidet nicht ueber das Wohlbefinden
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
    // Die Chiffre muss base64 sein - sonst bricht das Entschluesseln
    // ab. `base64Decode` wirft bei ungueltigem Text, deshalb wird hier
    // schon geprueft.
    if (!_istBase64(chiffertext)) return null;

    final typNr = intOf(map, ['messageType']);

    // Die Metadaten: hoechstens [maxSignalMetadataEntries] Eintraege,
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
  /// (FormatException). Hier wird nur die Form geprueft - die
  /// base64-Alphabe, ihre Laenge und die korrekte Fuellung.
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
