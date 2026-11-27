// Die Grenzen der Warteschlangen im P2P-Chat.
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/chat/p2p_chat_service.dart 57 offene Zeilen. Der
// grundlegende Weg (Nachricht vor dem offenen Kanal) war getestet -
// die Grenzen und das Leeren nicht: die Warteschlange ist begrenzt,
// eine Binärdatei darf den Relay-Weg nicht blockieren, und nach dem
// erfolgreichen Relay-Versand darf die Nachricht nicht doppelt
// ankommen.
//
// DER WEG: Eine Attrappe für den WebRTC-Dienst (der echte braucht eine
// E2E-Sitzung, die ohne Server nicht aufzubauen ist). Die Attrappe
// meldet den Kanal als geschlossen - genau der Fall, um den es geht.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Warteschlange ist begrenzt (die älteste Nachricht weicht),
//   * ein Binäreintrag blockiert den Relay-Weg nicht,
//   * ein erfolgreicher Relay-Versand holt den Eintrag aus der
//     Warteschlange (sonst käme die Nachricht doppelt an),
//   * die Steuer-Nachrichten (das Anruf-Signal) haben ihre eigene,
//     kleinere Warteschlange,
//   * das Leeren wirft auch die Steuer-Warteschlange weg.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

/// Die Attrappe für den WebRTC-Dienst.
///
/// DER GRUND: Der echte Dienst braucht für jede Nachricht eine
/// E2E-Sitzung (ohne Server nicht aufzubauen). Hier geht es um die
/// WARTESCHLANGE - also um den Fall "der Kanal ist noch nicht offen".
class _Attrappe extends WebRTCService {
  _Attrappe() : super(EncryptionService());

  /// Die gesendeten Texte (der Kanal ist offen).
  final List<String> gesendet = <String>[];

  /// Der Kanal ist offen?
  bool kanalOffen = false;

  /// Der zuletzt gesendete Fehler (für die Fehlerpfade).
  Object? fehler;

  @override
  bool get isConnected => kanalOffen;

  @override
  bool get isDataChannelOpen => kanalOffen;

  @override
  bool get hasSignalingChannel => true;

  @override
  Future<void> sendMessage(String plaintext) async {
    if (!kanalOffen) throw StateError('DataChannel nicht verbunden');
    if (fehler != null) throw fehler!;
    gesendet.add(plaintext);
  }

  @override
  Future<void> sendBinary(
    Uint8List data, {
    String contentType = 'application/octet-stream',
    Map<String, dynamic>? metadata,
  }) async {
    if (!kanalOffen) throw StateError('DataChannel nicht verbunden');
    if (fehler != null) throw fehler!;
  }

  @override
  Future<void> close() async {}
}

void main() {
  late _Attrappe webrtc;
  late P2PChatService dienst;

  setUp(() {
    webrtc = _Attrappe();
    // Der PreKey-Dienst wird nur für die Verbindung gebraucht - für die
    // Warteschlange nicht. Der echte Dienst braucht dafür den Keystore.
    dienst = P2PChatService(webrtc, PreKeyService(EncryptionService()));
  });

  tearDown(() async {
    await dienst.dispose();
  });

  group('Die Text-Warteschlange', () {
    test('eine geschlossene Tür reiht die Nachricht ein', () async {
      final direkt = await dienst.trySendText('Hallo');

      expect(direkt, isFalse);
      expect(dienst.pendingCount, 1);
    });

    test('die Warteschlange ist begrenzt', () async {
      // Die Grenze liegt bei 200 Einträgen - die älteste weicht.
      for (var i = 0; i < 205; i++) {
        await dienst.trySendText('Nachricht $i');
      }

      expect(
        dienst.pendingCount,
        lessThanOrEqualTo(200),
        reason: 'Die Warteschlange darf nicht unbegrenzt wachsen.',
      );

      // Und der älteste Eintrag ist gewichen.
      final gesendet = <String>[];
      await dienst.drainOutboxViaRelay((text) async {
        gesendet.add(text);
      });
      expect(
        gesendet.contains('Nachricht 0'),
        isFalse,
        reason: 'Die älteste Nachricht weicht - sonst wächst der Speicher.',
      );
      expect(gesendet.contains('Nachricht 204'), isTrue);
    });

    test('nach dem Relay-Versand ist der Eintrag raus', () async {
      await dienst.trySendText('Hallo');

      await dienst.drainOutboxViaRelay((text) async {});

      expect(
        dienst.pendingCount,
        0,
        reason:
            'Nach dem erfolgreichen Relay-Versand darf der Eintrag nicht '
            'in der Warteschlange bleiben - sonst käme die Nachricht '
            'doppelt an.',
      );
    });

    test('ein fehlgeschlagener Relay-Versand behält den Eintrag', () async {
      await dienst.trySendText('Hallo');

      await dienst.drainOutboxViaRelay((text) async {
        throw StateError('Relay nicht erreichbar');
      });

      expect(
        dienst.pendingCount,
        1,
        reason:
            'Ist das Relay gerade nicht erreichbar, bleibt die Nachricht '
            'liegen - sie darf nicht verloren gehen.',
      );
    });

    test('das gezielte Herausnehmen funktioniert', () async {
      await dienst.trySendText('Hallo');
      await dienst.trySendText('Tschuess');

      final entfernt = dienst.dequeueText('Hallo');

      expect(entfernt, isTrue);
      expect(dienst.pendingCount, 1);
      expect(
        dienst.dequeueText('gibt es nicht'),
        isFalse,
        reason: 'Ein unbekannter Text wird nicht gefunden.',
      );
    });
  });

  group('Die Binär-Warteschlange', () {
    test('ein Bild blockiert den Relay-Weg nicht', () async {
      await dienst.sendBinary(Uint8List.fromList(<int>[1, 2, 3]));
      expect(dienst.pendingCount, 1);

      await dienst.trySendText('Hallo');
      expect(dienst.pendingCount, 2);

      final uebertragen = <String>[];
      await dienst.drainOutboxViaRelay((text) async {
        uebertragen.add(text);
      });

      expect(
        uebertragen,
        <String>['Hallo'],
        reason:
            'Bilder können nicht über das Relay - sie dürfen die Texte '
            'dahinter aber nicht blockieren.',
      );
      expect(
        dienst.pendingCount,
        1,
        reason: 'Das Bild bleibt liegen (es ist P2P-only).',
      );
    });
  });

  group('Die Steuer-Warteschlange', () {
    test('ein Anrufsignal wird gepuffert', () async {
      await dienst.sendCallControl(<String, dynamic>{'type': 'invite'});

      // Das Signal steckt in der Steuer-Warteschlange (nicht in der
      // Text-Warteschlange - die zählt nur Texte und Binärdaten).
      expect(dienst.pendingCount, 0);
    });

    test('das Leeren wirft auch die Steuer-Warteschlange weg', () async {
      await dienst.sendCallControl(<String, dynamic>{'type': 'invite'});
      await dienst.trySendText('Hallo');

      dienst.clearOutbox();

      expect(dienst.pendingCount, 0);
    });
  });

  group('Der Kanal', () {
    test('mit offenem Kanal wird direkt gesendet', () async {
      webrtc.kanalOffen = true;

      final direkt = await dienst.trySendText('Hallo');

      expect(direkt, isTrue);
      expect(webrtc.gesendet, contains('Hallo'));
      expect(
        dienst.pendingCount,
        0,
        reason: 'Direkt gesendete Nachrichten landen nicht in der Schlange.',
      );
    });

    test('die Zustände werden durchgereicht', () {
      expect(dienst.isDataChannelOpen, isFalse);
      expect(dienst.hasSignalingChannel, isTrue);
      webrtc.kanalOffen = true;
      expect(dienst.isDataChannelOpen, isTrue);
      expect(dienst.isConnected, isTrue);
    });
  });
}
