import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:thestia/services/prekey_service.dart';
import 'package:thestia/services/webrtc_service.dart';

/// Orchestriert eine echte Ende-zu-Ende-P2P-Chatverbindung:
///   1. E2E-Session zum Partner aufbauen (PreKey-Bundle via Supabase Edge)
///   2. Signaling via Supabase Realtime (WebRTCService.connect)
///   3. Offer senden (initiierende Seite)
///
/// Empfangene, bereits entschlüsselte Nachrichten stehen unter
/// [incomingMessages] (der [WebRTCService] entschlüsselt mit dem Signal
/// Protocol).
class P2PChatService {
  P2PChatService(
    this._webrtc,
    this._prekey,
  ) {
    _incomingSub = _webrtc.incomingMessages.listen(
      (text) => _messageController.add(text),
    );
    _incomingBinarySub = _webrtc.incomingBinary.listen((record) {
      _binaryController.add(record);
    });
    _callControlSub = _webrtc.callControl.listen(
      (payload) => _callControlController.add(payload),
    );
    _callAudioSub = _webrtc.callAudio.listen((record) {
      _callAudioController.add(record);
    });
    // Outbox: Solange der DataChannel noch nicht offen ist (Partner evtl.
    // noch nicht im Chat), landen Sendungen in der Warteschlange und
    // werden AUTOMATISCH verschickt, sobald der Kanal offen ist. Vorher
    // warf sendText "Bad state: DataChannel nicht verbunden"
    // (v0.9.0-Feedback: QR-Chat, Zufallschat, Ideen-Rad). Die Outbox gilt
    // nur pro Chat-Session (connect/disconnect leeren sie).
    _connSub = _webrtc.connectionState.listen((state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        unawaited(_flushOutbox());
        unawaited(_flushControlQueue());
      }
    });
  }

  final WebRTCService _webrtc;
  final PreKeyService _prekey;

  final _messageController = StreamController<String>.broadcast();
  final _binaryController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();
  final _callControlController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAudioController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();
  late final StreamSubscription<String> _incomingSub;
  late final StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _incomingBinarySub;
  late final StreamSubscription<Map<String, dynamic>> _callControlSub;
  late final StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _callAudioSub;
  Stream<String> get incomingMessages => _messageController.stream;
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get incomingBinary => _binaryController.stream;

  /// Eingehende Anruf-Signalisierung (invite/accept/decline/end).
  Stream<Map<String, dynamic>> get callControl => _callControlController.stream;

  /// Eingehende Sprachpakete eines Anrufs (entschlüsselt).
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get callAudio => _callAudioController.stream;

  bool get isConnected => _webrtc.isConnected;

  /// True, wenn der DataChannel offen und sendebereit ist.
  bool get isDataChannelOpen => _webrtc.isDataChannelOpen;

  /// Stream des DataChannel-Status (zum Warten auf "offen").
  Stream<RTCDataChannelState> get connectionState =>
      _webrtc.connectionState;

  /// Stream des ICE-Verbindungsstatus (Diagnose im Chat).
  Stream<RTCIceConnectionState> get iceConnectionState =>
      _webrtc.iceConnectionState;

  /// Wake-up-Pings für den Relay-Fallback.
  Stream<void> get relayPing => _webrtc.relayPing;

  /// Pingt das Partner-Gerät, dass eine neue Relay-Nachricht wartet.
  Future<void> sendRelayPing() => _webrtc.sendRelayPing();

  /// True, wenn ein Signaling-Kanal referenziert ist.
  bool get hasSignalingChannel => _webrtc.hasSignalingChannel;

  /// Zähler für ensureConnected-Versuche je Peer (für Eskalation).
  final Map<String, int> _ensureAttempts = {};

  /// Letzter ensureConnected-Versuch je Peer (für Zeitfenster-Reset).
  final Map<String, DateTime> _ensureAttemptAt = {};

  /// Absolute Obergrenze für ensureConnected-Versuche je Peer: Danach
  /// No-op bis zum nächsten disconnect() (Akku-/Netz-Schutz; der Aufrufer
  /// drosselt ohnehin, aber der Service selbst darf nie endlos feuern).
  /// Das Budget wird zurückgesetzt, wenn der letzte Versuch länger als
  /// 10 Minuten her ist (Fix: sonst kein Retry mehr im selben Chat, auch
  /// wenn sich die Netzlage längst gebessert hat).
  static const int _maxEnsureAttempts = 40;

  /// Stellt die Verbindung sicher: No-op, wenn verbunden; sonst Re-Offer
  /// über den bestehenden Kanal. Jeder 3. Versuch baut VOLL neu auf
  /// (frischer Signaling-Kanal) - falls der referenzierte Kanal tot ist
  /// (Subscribe-Fehlschlag), käme ein Re-Offer nie an.
  /// Gedrosselt vom Aufrufer verwenden (teurer Handshake).
  Future<void> ensureConnected({
    required String myUserId,
    required String peerId,
  }) async {
    if (_webrtc.isConnected) {
      _ensureAttempts.remove(peerId);
      _ensureAttemptAt.remove(peerId);
      return;
    }
    final now = DateTime.now();
    final last = _ensureAttemptAt[peerId];
    var n = (_ensureAttempts[peerId] ?? 0) + 1;
    if (last != null && now.difference(last) > const Duration(minutes: 10)) {
      n = 1; // Altes Budget verfallen: neu zählen.
    }
    _ensureAttempts[peerId] = n;
    _ensureAttemptAt[peerId] = now;
    if (n > _maxEnsureAttempts) return;
    if (_webrtc.hasSignalingChannel && n % 3 != 0) {
      await _webrtc.retryHandshake();
    } else {
      await connect(myUserId: myUserId, peerId: peerId);
    }
  }

  // ---------------------------------------------------------------------
  // Outbox (Senden vor verbundenem DataChannel)
  // ---------------------------------------------------------------------
  static const int _maxOutbox = 200;
  final List<({String? text, Uint8List? data, String contentType, Map<String, dynamic>? metadata})>
      _outbox = [];
  String? _outboxPeerId;
  late final StreamSubscription<RTCDataChannelState> _connSub;

  /// Anzahl wartender (noch nicht zugestellter) Nachrichten.
  int get pendingCount => _outbox.length;

  /// Verwirft die komplette Outbox inkl. Retry-Zähler (Logout/
  /// Kontowechsel, Audit): Ungesendete Chiffre des Vorgängers dürfen
  /// unter dem neuen Konto weder in einen falschen Chat laufen noch
  /// mit falscher Identität zugestellt werden.
  void clearOutbox() {
    _outbox.clear();
    _outboxPeerId = null;
    _controlQueue.clear();
    _flushFailures.clear();
    _ensureAttempts.clear();
    _ensureAttemptAt.clear();
  }

  /// Leert die TEXT-Outbox über einen alternativen Transport (Relay-
  /// Fallback): Nachrichten, die vor dem Relay-Modus geschrieben wurden,
  /// dürfen nicht auf einen womöglich nie kommenden DataChannel warten.
  /// Binärdaten (Bilder/Audio) bleiben P2P-only und werden ÜBERSPRUNGEN
  /// (continue statt break - Fix: sonst blockiert ein Bild alle
  /// dahinterliegenden Relay-fähigen Texte für immer).
  Future<void> drainOutboxViaRelay(
      Future<void> Function(String text) send) async {
    var i = 0;
    while (i < _outbox.length) {
      final item = _outbox[i];
      if (item.text == null) {
        i++;
        continue;
      }
      try {
        await send(item.text!);
        _outbox.removeAt(i);
      } catch (_) {
        break; // Relay gerade nicht erreichbar: später erneut.
      }
    }
  }

  /// Entfernt einen TEXT-Eintrag aus der Outbox (Dual-Delivery-Schutz):
  /// `trySendText` reiht bei geschlossenem Kanal EIN und meldet false;
  /// ruft der Aufrufer danach erfolgreich den Relay-Fallback, muss der
  /// eingereihte Eintrag raus - sonst käme die Nachricht bei späterer
  /// Kanalöffnung DOPPELT (einmal Relay, einmal Outbox-Flush).
  /// Gibt true zurück, wenn ein Eintrag entfernt wurde.
  bool dequeueText(String text) {
    final idx = _outbox.indexWhere((e) => e.text == text);
    if (idx < 0) return false;
    _outbox.removeAt(idx);
    return true;
  }

  void _enqueue({
    String? text,
    Uint8List? data,
    String contentType = 'application/octet-stream',
    Map<String, dynamic>? metadata,
  }) {
    if (_outbox.length >= _maxOutbox) {
      _outbox.removeAt(0); // Älteste Nachricht weicht (Begrenzung).
    }
    _outbox.add((
      text: text,
      data: data,
      contentType: contentType,
      metadata: metadata,
    ));
    debugPrint('[P2P] DataChannel nicht offen - Nachricht in die Outbox '
        '(${_outbox.length} wartend).');
  }

  /// Flush-Fehlversuche je Outbox-Eintrag (gegen Poison-Head-Blockade,
  /// siehe [_flushOutbox]).
  final Map<int, int> _flushFailures = {};
  static const int _maxFlushFailures = 5;

  Future<void> _flushOutbox() async {
    while (_outbox.isNotEmpty) {
      final item = _outbox.first;
      try {
        if (item.text != null) {
          await _webrtc.sendMessage(item.text!);
        } else {
          await _webrtc.sendBinary(item.data!,
              contentType: item.contentType, metadata: item.metadata);
        }
        _outbox.removeAt(0);
        _flushFailures.remove(identityHashCode(item));
      } on StateError {
        break; // Kanal wieder zu -> später erneut versuchen (behalten).
      } catch (e) {
        // Generischer Fehler (z. B. Verschlüsselung): Eintrag BEHALTEN
        // und abbrechen statt still zu verwerfen - sonst gehen Nachrichten
        // bei transienten Fehlern verloren. Nach 5 Fehlversuchen wird der
        // Eintrag verworfen, damit ein dauerhaft defekter Head die Queue
        // nicht für immer blockiert (Fix beider Richtungen).
        final key = identityHashCode(item);
        final fails = (_flushFailures[key] ?? 0) + 1;
        if (fails >= _maxFlushFailures) {
          debugPrint('[P2P] Outbox-Eintrag nach $fails Versuchen verworfen: $e');
          _outbox.removeAt(0);
          _flushFailures.remove(key);
        } else {
          _flushFailures[key] = fails;
          debugPrint('[P2P] Outbox-Eintrag vorerst behalten ($fails/$_maxFlushFailures): $e');
          break;
        }
      }
    }
  }

  Future<void> dispose() async {
    await _incomingSub.cancel();
    await _incomingBinarySub.cancel();
    await _callControlSub.cancel();
    await _callAudioSub.cancel();
    await _connSub.cancel();
    await _messageController.close();
    await _binaryController.close();
    await _callControlController.close();
    await _callAudioController.close();
    await disconnect();
  }

  /// Baut die Verbindung zum Partner auf.
  ///
  /// [myUserId] ist die eigene User-ID, [peerId] die des Partners.
  /// Glare-Vermeidung: Die Seite mit der lexikografisch kleineren userId
  /// initiiert das Offer.
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    // Outbox nur bei Peer-Wechsel leeren (Datenschutz: kein Transport in
    // den falschen Chat). Beim selben Peer bleibt die Outbox erhalten,
    // damit Nachrichten zugestellt werden, sobald beide gleichzeitig
    // online sind (v0.9.1-Fix: "Nachrichten kommen nicht an" - vorher
    // wurde die Outbox bei jedem connect/disconnect verworfen und beim
    // Verlassen des Chats ging alles verloren).
    if (_outboxPeerId != null && _outboxPeerId != peerId) {
      _outbox.clear();
      _controlQueue.clear();
      _flushFailures.clear();
    }
    _outboxPeerId = peerId;

    // Bundle-Self-Heal (Fix "Partner bekommt 404"): Das eigene Bundle wird
    // nicht nur beim Login geprüft, sondern bei JEDEM connect(). Hintergrund:
    // Der Server-Publish schlug projektweit fehl (42501, Migration 100) -
    // Geräte mit altem Stand haben evtl. noch kein Bundle. Ein GET ist
    // billig; nur bei 404/5xx folgt der POST.
    unawaited(_prekey.ensureOwnBundlePublished());

    // E2E-Session via PreKey-Bundle (Supabase Edge Function)
    await _prekey.ensureSession(peerId);

    // Signaling via Supabase Realtime
    await _webrtc.connect(myUserId: myUserId, peerId: peerId);

    final isInitiator = myUserId.compareTo(peerId) < 0;
    if (isInitiator) {
      await _webrtc.createOffer(peerId);
    }
    // Falls der Kanal schon offen ist (Empfängerseite), Queues sofort
    // leeren.
    unawaited(_flushOutbox());
    unawaited(_flushControlQueue());
  }

  /// Sendet Text E2E - oder puffert ihn, bis der DataChannel offen ist.
  Future<void> sendText(String text) async {
    await trySendText(text);
  }

  /// Wie [sendText], meldet aber zurück, ob DIREKT gesendet (true) oder
  /// nur eingereiht wurde (false, Kanal geschlossen). Ermöglicht dem
  /// Aufrufer den Relay-Fallback statt stillem Warten (v0.9.1).
  Future<bool> trySendText(String text) async {
    try {
      await _webrtc.sendMessage(text);
      return true;
    } on StateError {
      _enqueue(text: text);
      return false;
    }
  }

  /// Sendet Binärdaten E2E - oder puffert sie, bis der Kanal offen ist.
  Future<void> sendBinary(Uint8List data,
      {String contentType = 'application/octet-stream',
      Map<String, dynamic>? metadata}) async {
    try {
      await _webrtc.sendBinary(data, contentType: contentType, metadata: metadata);
    } on StateError {
      _enqueue(data: data, contentType: contentType, metadata: metadata);
    }
  }

  /// Sendet eine Anruf-Steuerungsnachricht (invite/accept/decline/end).
  /// E2E-verschlüsselt über den DataChannel - oder gepuffert, bis der Kanal
  /// offen ist (v0.9.1-Fix: vorher warf invite bei geschlossenem Kanal
  /// sofort StateError und der Anruf kam nie durch).
  Future<void> sendCallControl(Map<String, dynamic> payload) async {
    try {
      await _webrtc.sendControl(payload);
    } on StateError {
      _enqueueControl(payload);
    }
  }

  /// Sendet ein Sprachpaket eines Anrufs (E2E-verschlüsselt) - oder puffert.
  Future<void> sendCallAudio(Uint8List data, {Map<String, dynamic>? metadata}) async {
    try {
      await _webrtc.sendCallAudio(data, metadata: metadata);
    } on StateError {
      _enqueue(data: data, contentType: 'audio/call', metadata: metadata);
    }
  }

  // ---------------------------------------------------------------------
  // Control-Queue (Anruf-Signaling bei geschlossenem Kanal puffern)
  // ---------------------------------------------------------------------
  static const int _maxControlQueue = 10;
  final List<Map<String, dynamic>> _controlQueue = [];

  void _enqueueControl(Map<String, dynamic> payload) {
    if (_controlQueue.length >= _maxControlQueue) {
      _controlQueue.removeAt(0);
    }
    _controlQueue.add(Map<String, dynamic>.from(payload));
    debugPrint('[P2P] DataChannel nicht offen - Control in Queue '
        '(${_controlQueue.length} wartend).');
  }

  Future<void> _flushControlQueue() async {
    while (_controlQueue.isNotEmpty) {
      final item = _controlQueue.first;
      try {
        await _webrtc.sendControl(item);
        _controlQueue.removeAt(0);
      } on StateError {
        break;
      } catch (e) {
        debugPrint('[P2P] Control-Eintrag fehlgeschlagen, verworfen: $e');
        _controlQueue.removeAt(0);
      }
    }
  }

  Future<void> disconnect() {
    // Outbox bewusst NICHT leeren (v0.9.1-Fix): Nicht zugestellte
    // Nachrichten bleiben für denselben Peer erhalten und werden beim
    // nächsten connect geflusht, sobald der DataChannel offen ist.
    // Nur der Peer-Wechsel in connect() verwirft (Datenschutz).
    _ensureAttempts.clear();
    _ensureAttemptAt.clear();
    return _webrtc.close();
  }
}

/// Provider für den [P2PChatService].
final p2pChatServiceProvider = Provider<P2PChatService>((ref) {
  final service = P2PChatService(
    ref.watch(webRTCServiceProvider),
    ref.watch(preKeyServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
