// Peer-Connection und Datenkanal für die WebRTC-Tests.
//
// ANLASS (20.11.2026): `createPeerConnection()` aus flutter_webrtc braucht
// die native Schicht - im Test gibt es sie nicht. Die Naht
// `WebRTCService.peerConnectionFactory` erlaubt es, stattdessen diese
// Attrappen einzusetzen. Der Produktionscode bleibt unverändert.
//
// Nicht benutzte Methoden der Schnittstellen werden bewusst NICHT
// nachgebaut - ein Aufruf wäre im Test ein Fehler (und kein stilles
// "geht schon"). So fällt sofort auf, wenn der Dienst etwas Neues
// braucht.
import 'package:webrtc_interface/webrtc_interface.dart';

// webrtc_interface kommt als Transitivum über flutter_webrtc - genau wie
// die anderen Plattform-Interfaces im Projekt wird es nur direkt
// importiert, damit der Test eine Attrappe bauen kann.
// ignore_for_file: depend_on_referenced_packages

/// Der Datenkanal im Test: merkt sich gesendete Nachrichten und lässt
/// den Test eingehende schieben.
class FakeDataChannel extends RTCDataChannel {
  FakeDataChannel();

  /// Alle gesendeten Nachrichten.
  final List<RTCDataChannelMessage> gesendet = <RTCDataChannelMessage>[];

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    gesendet.add(message);
  }

  @override
  Future<void> close() async {}

  @override
  RTCDataChannelState get state => RTCDataChannelState.RTCDataChannelOpen;

  @override
  int get id => 1;

  @override
  String get label => 'blind-date-chat';

  @override
  int get bufferedAmount => 0;

  /// Schiebt eine eingehende Textnachricht hinein.
  void empfange(String text) {
    onMessage?.call(RTCDataChannelMessage(text));
  }

  /// Der Kanal geht auf (der Dienst hört darauf).
  void oeffne() {
    onDataChannelState?.call(RTCDataChannelState.RTCDataChannelOpen);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Im Test nicht gebraucht: ${invocation.memberName}');
  }
}

/// Die Peer-Connection im Test: liefert einen Datenkanal und lässt den
/// Test den Verbindungszustand steuern.
class FakePeerConnection extends RTCPeerConnection {
  FakePeerConnection({RTCDataChannel? kanal})
    : datenkanal = kanal ?? FakeDataChannel();

  /// Der Datenkanal, den die Verbindung herstellt.
  final RTCDataChannel datenkanal;

  /// Wie oft wurde die Verbindung gebaut?
  int erstellt = 0;

  @override
  Future<RTCDataChannel> createDataChannel(
    String label, [
    RTCDataChannelInit? dataChannelInit,
  ]) async {
    erstellt++;
    return datenkanal;
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('test-offer', 'offer');

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('test-answer', 'answer');

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<void> addStream(MediaStream stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      RTCSessionDescription('test-offer', 'offer');

  @override
  Future<RTCSessionDescription?> getRemoteDescription() async =>
      RTCSessionDescription('test-answer', 'answer');

  /// Der ICE-Zustand meldet "verbunden" (der Dienst setzt isConnected).
  void verbinde() {
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateConnected,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Im Test nicht gebraucht: ${invocation.memberName}');
  }
}
