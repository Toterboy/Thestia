import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/utils/cert_pinning.dart';

/// Service für WebRTC Peer-to-Peer Verbindungen.
///
/// Signaling läuft jetzt über Supabase Realtime (Broadcast-Kanal) —
/// kein eigener Signaling-WebSocket-Server mehr nötig.
///
/// ICE: Die ice-config Edge Function liefert STUN/TURN-Server dynamisch
/// (H-03). Bei Nichterreichbarkeit greift eine statische EU-STUN-Fallback-
/// Liste (kein Google). TURN wird nicht benötigt, weil STUN für
/// IP-Ermittlung in den meisten Fällen reicht.
class WebRTCService {
  static const String _dataChannelLabel = 'blind-date-chat';

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final EncryptionService _encryptionService;
  final http.Client _httpClient;

  /// ICE-Fallback (NUR EU, KEIN Google), falls die ice-config Edge
  /// Function nicht erreichbar ist.
  ///
  /// BETREIBER-ENTSCHEIDUNG: Kein TURN (keine laufenden Abos/Kosten).
  /// Konsequenz: Hinter symmetrischen NATs/strikten Firewalls (z. B.
  /// Unternehmensnetze) kommt ggf. keine direkte P2P-Verbindung zustande.
  /// Insbesondere MOBILFUNK (CGNAT) scheitert damit aktuell regelmäßig -
  /// Nutzer-Hinweis: random.errorConnectTimeout. Falls später TURN
  /// gewünscht ist: ice-config Edge Function um kurzlebige TURN-REST-
  /// Credentials erweitern (siehe Git-Historie).
  static final List<Map<String, dynamic>> _fallbackIceServers = [
    {'urls': 'stun:stun.nextcloud.com:443'},  // Hetzner, DE
    {'urls': 'stun:stun.miwifi.com:3478'},    // OVH, FR
    {'urls': 'stun:stun.voipgate.com:3478'},  // DE
    {'urls': 'stun:stun.voipstunt.com:3478'}, // NL
  ];

  /// Cache für die dynamisch geladene ICE-Konfiguration (H-03).
  List<Map<String, dynamic>>? _cachedIceServers;
  DateTime? _cacheExpiry;

  final StreamController<String> _incomingMessageController = StreamController<String>.broadcast();
  final StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _incomingBinaryController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();

  /// Kontroll-Kanal (Anruf-Signaling): entschlüsselte JSON-Payloads, die mit
  /// dem Präfix [controlPrefix] gesendet wurden. Landet NICHT im normalen
  /// Chat-Verlauf (kein Vermischen von Steuerung und Inhalt).
  final StreamController<Map<String, dynamic>> _controlController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Kontroll-Audio-Kanal: Sprachpakete eines Anrufs (contentType audio/call).
  /// Ebenfalls E2E-verschlüsselt und vom normalen Chat getrennt.
  final StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})> _controlAudioController =
      StreamController<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>.broadcast();

  /// Präfix für Steuerungsnachrichten im verschlüsselten Textkanal.
  static const String controlPrefix = 'CALL:';

  /// Wake-up-Signal für den Relay-Fallback: Nach relay_store pingt der
  /// Sender über den ohnehin bestehenden Signaling-Kanal, damit der
  /// Empfänger sofort abholt statt aufs Polling zu warten. Ein reiner
  /// void-Stream (kein Inhalt im Chat, keine Metadaten beim Server).
  final StreamController<void> _relayPingController =
      StreamController<void>.broadcast();

  /// Stream der Relay-Wake-up-Pings.
  Stream<void> get relayPing => _relayPingController.stream;

  /// ContentType für Sprachpakete eines Anrufs.
  static const String callAudioContentType = 'audio/call';

  final StreamController<RTCDataChannelState> _connectionStateController = StreamController<RTCDataChannelState>.broadcast();
  final StreamController<RTCIceConnectionState> _iceConnectionStateController = StreamController<RTCIceConnectionState>.broadcast();

  RealtimeChannel? _signalingChannel;
  String? _myUserId;
  String? _currentPeerId;
  String? _signalingTopic;
  bool _isConnected = false;

  /// True, wenn ein Signaling-Kanal referenziert ist (keine Aussage über
  /// dessen Realtime-Status - ein toter Kanal wird beim nächsten
  /// [connect] ersetzt).
  bool get hasSignalingChannel => _signalingChannel != null;

  /// Zuletzt gesehenes Offer-SDP (Duplikat-Schutz: Realtime liefert
  /// mindestens einmal aus; identische Wiederholungen starten den
  /// Handshake nicht neu).
  String? _lastOfferSdp;

  /// True, sobald eine Remote-Description gesetzt wurde. Nach dem ersten
  /// Offer/Answer-Austausch werden weitere ignoriert (Härtung gegen
  /// Signaling-Kaperung; keine Renegotiation in dieser Architektur).
  bool _remoteDescriptionSet = false;

  /// Serialisierte Signaling-Verarbeitung: Broadcast-Events werden in
  /// einer Queue abgelegt und STRENG NACHEINANDER verarbeitet. Vorher
  /// lief handleOffer (incl. ice-config-HTTP-Call und PC-Aufbau) parallel
  /// zum Eintreffen der ICE-Kandidaten - die Kandidaten trafen auf ein
  /// noch nicht existierendes/noch nicht konfiguriertes PeerConnection
  /// und gingen VERLOREN -> ICE blieb in "checking" -> keine Verbindung.
  final List<Map<String, dynamic>> _pendingSignals = [];
  bool _drainingSignals = false;

  /// Obergrenze für SDP in Signaling-Nachrichten (DoS-Schutz, Audit S4).
  static const int _maxSdpBytes = 64 * 1024;

  /// ICE-Backlog: Kandidaten, die VOR der Remote-Description eintreffen,
  /// werden gepuffert (statt sie zu verlieren) und nach
  /// setRemoteDescription nachgereicht.
  final List<RTCIceCandidate> _candidateBacklog = [];

  /// HTTP-Client MIT Zertifikat-Pinning für ice-config und das
  /// Signaling-Broadcast (Audit: beide Endpunkte laufen gegen denselben
  /// Supabase-Host wie der ApiClient - derselbe Pin-Schutz gilt).
  WebRTCService(this._encryptionService, {http.Client? httpClient})
      : _httpClient = httpClient ?? _buildPinnedClient();

  static http.Client _buildPinnedClient() {
    if (kIsWeb) {
      // Web kann kein dart:io-Pinning (siehe ApiClient).
      return http.Client();
    }
    return IOClient(CertPinning.pinnedHttpClient());
  }

  /// Lädt die ICE-Konfiguration von der ice-config Edge Function.
  ///
  /// Antwortformat: `{ "iceServers": [...], "ttlSeconds": 3600 }`.
  /// Die Antwort wird bis zum Ablauf von `ttlSeconds` gecacht; bei jedem
  /// Fehler (Netz, HTTP != 200, leere Liste) greift die statische
  /// EU-Fallback-Liste. Damit bleibt P2P auch ohne Edge Function nutzbar.
  Future<List<Map<String, dynamic>>> resolveIceServers() async {
    final now = DateTime.now();
    if (_cachedIceServers != null &&
        _cacheExpiry != null &&
        now.isBefore(_cacheExpiry!)) {
      return _cachedIceServers!;
    }

    try {
      // BUG-FIX (Server-Log: POST rest/v1/functions/v1/ice-config -> 401):
      // client.rest.url liefert "<Basis>/rest/v1" - mit suffixlosem
      // Zusammensetzen landeten ice-config-Calls im PostgREST-Pfad und
      // wurden vom Gateway mit 401 abgelehnt (Fallback STUN rettete die
      // Verbindung, aber die Config kam nie). Basis-URL sauber ableiten.
      final supabaseUrl = deriveFunctionBaseUrl(
          Supabase.instance.client.rest.url);
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw StateError('Keine aktive Session');
      // HARTES Timeout: Der Offer-Aufbau wartet hier drauf - ohne Limit
      // konnte eine langsame/nicht erreichbare Edge Function den kompletten
      // Verbindungsaufbau Minuten blockieren (ICE-Kandidaten laufen derweil
      // ins Leere).
      final res = await _httpClient
          .post(
            Uri.parse('$supabaseUrl/functions/v1/ice-config'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        throw StateError('ice-config Status ${res.statusCode}');
      }
      final servers = parseIceConfig(res.body);
      final ttl = _extractTtl(res.body);
      _cachedIceServers = servers;
      _cacheExpiry = now.add(Duration(seconds: ttl));
      if (kDebugMode) {
        debugPrint('[WebRTC] ICE-Server geladen: ${servers.length} Eintraege');
      }
      return servers;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebRTC] ice-config nicht verfuegbar, Fallback aktiv: $e');
      }
      return _fallbackIceServers;
    }
  }

  /// Parst die ice-config-Antwort (reine Funktion, testbar).
  @visibleForTesting
  static List<Map<String, dynamic>> parseIceConfig(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final servers = (json['iceServers'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (servers == null || servers.isEmpty) {
      throw StateError('ice-config ohne iceServers');
    }
    return servers;
  }

  /// Liest die TTL (Sekunden) aus der ice-config-Antwort (Default 3600).
  static int _extractTtl(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['ttlSeconds'] as num?)?.toInt() ?? 3600;
    } catch (_) {
      return 3600;
    }
  }

  /// Test-Hook: [resolveIceServers] ohne echte Edge Function prüfen.
  @visibleForTesting
  void setIceServerCache(List<Map<String, dynamic>> servers, Duration ttl) {
    _cachedIceServers = servers;
    _cacheExpiry = DateTime.now().add(ttl);
  }

  /// Leitet die Funktions-Basis-URL aus der REST-URL ab (reine Funktion,
  /// testbar): Der 401-Fix entfernt das `/rest/v1`-Suffix, damit der Call
  /// den Function-Pfad trifft statt des PostgREST-Pfads.
  @visibleForTesting
  static String deriveFunctionBaseUrl(String restUrl) =>
      restUrl.replaceFirst(RegExp(r'/rest/v1/?$'), '');

  /// Stream eingehender entschlüsselter Textnachrichten.
  Stream<String> get incomingMessages => _incomingMessageController.stream;

  /// Stream eingehender entschlüsselter Binärdaten (Bilder, Audio).
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get incomingBinary => _incomingBinaryController.stream;

  /// Stream entschlüsselter Kontroll-Nachrichten (Anruf-Signaling).
  Stream<Map<String, dynamic>> get callControl => _controlController.stream;

  /// Stream entschlüsselter Anruf-Sprachpakete.
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
      get callAudio => _controlAudioController.stream;

  /// Stream des DataChannel-Verbindungsstatus.
  Stream<RTCDataChannelState> get connectionState => _connectionStateController.stream;

  /// Stream des ICE-Verbindungsstatus.
  Stream<RTCIceConnectionState> get iceConnectionState => _iceConnectionStateController.stream;

  bool get isConnected => _isConnected;

  /// True, wenn der DataChannel offen und sendebereit ist (v0.9.1:
  /// Anruf-Invite wartet hierauf statt sofort zu scheitern).
  bool get isDataChannelOpen => _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Aktiviert die Signaling-Schicht via Supabase Realtime für [myUserId]
  /// und [peerId]. Wird von [P2PChatService.connect] aufgerufen.
  ///
  /// Sicherheits-Regeln (Audit H8):
  /// - [_currentPeerId] wird HIER fest verdrahtet und ändert sich danach
  ///   nicht mehr durch eingehende Nachrichten (kein TOCTOU/Hijacking).
  /// - Ausgehende Nachrichten tragen als `from` die EIGENE User-ID, nicht
  ///   die des Peers.
  ///
  /// Audit M-10/W-3: Der Kanal ist jetzt ein REALTIME PRIVATE CHANNEL
  /// (`private: true`). Realtime autorisiert Join UND Broadcast per RLS
  /// (Migration 062): nur die beiden im Topic genannten Nutzer dürfen den
  /// Kanal nutzen - Dritt-Injektion mit gefälschtem Absender ist
  /// serverseitig unmöglich.
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    // Vorherigen Versuch sauber abräumen (Retry-sicher): sonst sammeln
    // sich pro connect() ein toter Realtime-Kanal (Socket-Leak) und eine
    // alte PeerConnection (stale ICE) an - beides verhinderte zuvor, dass
    // ein späterer Handshake je durchkam.
    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _dataChannel = null;
    _isConnected = false;
    _remoteDescriptionSet = false;
    _lastOfferSdp = null;
    // Neue Verbindung: alte Signaling-Warteschlangen/Backlogs sind stale.
    _pendingSignals.clear();
    _candidateBacklog.clear();
    await _signalingChannel?.unsubscribe();
    _signalingChannel = null;

    _myUserId = myUserId;
    _currentPeerId = peerId;
    // Safety-Numbers benötigen die eigene User-ID (Signal-Fingerprint).
    _encryptionService.localUserId ??= myUserId;

    // Realtime-Authorization (Private Channels): Der Socket braucht das
    // AKTUELLE User-JWT im Join-Payload. supabase_flutter setzt es zwar
    // bei Auth-Events - bleibt dabei aber ein Zeitfenster/Fehlerpfad
    // (z. B. abgelaufenes Token beim App-Start: FormatException wird
    // verschluckt), in dem der Socket den ANON-Key behaelt. Der Join
    // wird dann mit der anon-Rolle gegen die 'to authenticated'-Policy
    // geprueft und verweigert -> "Signaling-Kanal nicht verfügbar".
    // Fix (Supabase-Doku): setAuth mit dem aktuellen Session-Token
    // unmittelbar vor dem Subscribe erzwingen.
    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken != null) {
      try {
        await Supabase.instance.client.realtime.setAuth(accessToken);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WebRTC] realtime.setAuth fehlgeschlagen: $e');
        }
      }
    }

    // Deterministischer Kanal-Name (lexikografisch sortiert).
    //
    // WICHTIG (Verbindungs-Fix): Der Client-Name darf KEIN 'realtime:'-
    // Präfix enthalten - Supabase präfixiert intern selbst mit 'realtime:'
    // (realtime_client: RealtimeChannel('realtime:$topic')). Mit dem alten
    // Wert 'realtime:signaling:...' lautete der Server-Topic
    // 'realtime:realtime:signaling:...', die RLS-Policy (Migration 062,
    // Regex '^realtime:signaling:...$') matchte nie und der Join des
    // Private Channels wurde verweigert -> "Verbindung fehlgeschlagen".
    final ids = [myUserId, peerId]..sort();
    _signalingTopic = 'signaling:${ids[0]}:${ids[1]}';
    final channelName = _signalingTopic!;

    _signalingChannel = Supabase.instance.client.channel(
      channelName,
      opts: const RealtimeChannelConfig(private: true),
    );

    final subscribed = Completer<void>();
    _signalingChannel!.onBroadcast(
      event: 'signal',
      callback: (payload) {
        try {
          final msg = Map<String, dynamic>.from(payload as Map);
          unawaited(_routeSignaling(msg));
        } catch (e) {
          if (kDebugMode) debugPrint('[WebRTC] Fehler beim Signaling-Routing: $e');
        }
      },
    );

    _signalingChannel!.subscribe((status, error) {
      if (subscribed.isCompleted) return;
      if (kDebugMode) {
        debugPrint('[WebRTC] Signaling-Subscribe-Status: ${status.name}'
            '${error != null ? ' ($error)' : ''}');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        subscribed.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        subscribed.completeError(
          StateError('Signaling-Kanal nicht verfügbar (${status.name}).'),
        );
      }
    });

    try {
      // 15 s statt 10 s: Der erste Join (Socket-Aufbau + Authorization)
      // kann auf Mobilfunk länger dauern, ohne dass er gescheitert ist.
      await subscribed.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      await _signalingChannel?.unsubscribe();
      _signalingChannel = null;
      rethrow;
    }
  }

  /// Sendet eine Signaling-Nachricht an den Peer über den autorisierten
  /// Broadcast des Private Channels (Audit M-10/W-3). Die REST-Broadcast-
  /// API wurde entfernt: Sie hätte Dritten mit gültigem JWT weiterhin
  /// erlaubt, beliebige Topics zu beschreiben.
  Future<void> _sendSignaling(Map<String, dynamic> message) async {
    final channel = _signalingChannel;
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(event: 'signal', payload: message);
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRTC] Broadcast-Fehler: $e');
    }
  }

  /// Leitet eingehende Signaling-Nachrichten SERIELL an die passenden
  /// WebRTC-Handler (Offer/Answer/ICE in fester Reihenfolge).
  ///
  /// Härtung gegen Signaling-Missbrauch:
  /// - Nur Nachrichten des erwarteten Peers werden akzeptiert ([_currentPeerId]).
  /// - Offers/Answers werden verworfen, sobald die Verbindung steht bzw. eine
  ///   Remote-Description vorhanden ist - so kann eine bereits etablierte
  ///   Session nicht durch injizierte Offers gekapert werden (keine
  ///   Renegotiation in dieser Architektur).
  /// - SDP wird größenbegrenzt (DoS-Schutz).
  /// - ICE-Kandidaten vor der Remote-Description werden gepuffert, nicht
  ///   verworfen ([_candidateBacklog]).
  Future<void> _routeSignaling(Map<String, dynamic> msg) async {
    try {
      final from = msg['from'] as String?;
      if (from == null || from != _currentPeerId) {
        if (kDebugMode) {
          debugPrint('[WebRTC] Signaling von unerwartetem Absender verworfen.');
        }
        return;
      }
      _pendingSignals.add(msg);
      if (_pendingSignals.length > 200) _pendingSignals.removeAt(0);
      if (_drainingSignals) return; // Ein Drain läuft bereits.
      _drainingSignals = true;
      try {
        while (_pendingSignals.isNotEmpty) {
          final next = _pendingSignals.removeAt(0);
          await _handleSignal(next);
        }
      } finally {
        _drainingSignals = false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRTC] Fehler bei Signaling-Routing: $e');
    }
  }

  /// Verarbeitet EINE Signaling-Nachricht (nur im seriellen Drain rufen).
  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    switch (type) {
      case 'offer':
        final sdp = msg['sdp'] as String?;
        if (sdp == null || _isConnected) break;
        if (utf8Length(sdp) > _maxSdpBytes) {
          if (kDebugMode) debugPrint('[WebRTC] Offer zu groß, verworfen.');
          break;
        }
        // Identische Offer-Wiederholung: kein Neustart.
        if (sdp == _lastOfferSdp && _peerConnection != null) break;
        _lastOfferSdp = sdp;
        await handleOffer(_currentPeerId!, sdp);
        break;
      case 'answer':
        final sdp = msg['sdp'] as String?;
        if (sdp == null || _isConnected || _remoteDescriptionSet) break;
        if (_peerConnection == null || utf8Length(sdp) > _maxSdpBytes) {
          if (kDebugMode) debugPrint('[WebRTC] Answer verworfen (kein PC/zu groß).');
          break;
        }
        await handleAnswer(_currentPeerId!, sdp);
        break;
      case 'ice':
        // Kein PC-Null-Check hier: Kandidaten vor der PeerConnection
        // werden in handleIceCandidate gepuffert (Reihenfolge-Sicherheit).
        if (_isConnected) break;
        final candidate = msg['candidate'] as String?;
        final sdpMid = msg['sdpMid'] as String?;
        final sdpMLineIndexRaw = msg['sdpMLineIndex'];
        if (candidate == null || sdpMid == null || sdpMLineIndexRaw == null) {
          break;
        }
        // num-Cast: Auf Web liefert jsonDecode ggf. double statt int.
        final sdpMLineIndex = (sdpMLineIndexRaw as num).toInt();
        await handleIceCandidate(
          _currentPeerId!,
          RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
        );
        break;
      case 'relay-ping':
        // Kein WebRTC-Material: Relay-Wake-up für den Fallback-Modus.
        _relayPingController.add(null);
        break;
      default:
        break; // Unbekannte Typen ignorieren.
    }
  }

  /// UTF-8-Länge eines Strings (für Größenlimits).
  static int utf8Length(String s) => utf8.encode(s).length;

  /// Test-Hook: Peer-Pinning-Logik ([_routeSignaling]) ohne echte
  /// Verbindung prüfen.
  @visibleForTesting
  Future<void> routeSignalingForTesting(Map<String, dynamic> msg) =>
      _routeSignaling(msg);

  /// Test-Hook: erwarteten Peer setzen, ohne einen Anruf aufzubauen.
  @visibleForTesting
  set currentPeerIdForTesting(String id) => _currentPeerId = id;

  /// Sendet das Offer erneut über den BESTEHENDEN Signaling-Kanal
  /// (Retry, ohne neuen Kanal und ohne neue E2E-Session). Nur der
  /// Initiator (kleinere User-ID, vgl. P2PChatService.connect) sendet;
  /// die Gegenseite antwortet per handleOffer. Harmlos, wenn bereits
  /// verbunden (dann No-op).
  Future<void> retryHandshake() async {
    if (_isConnected) return;
    final peerId = _currentPeerId;
    final myId = _myUserId;
    if (peerId == null || myId == null || _signalingChannel == null) return;
    if (myId.compareTo(peerId) >= 0) return; // Kein Initiator: warten.
    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
    _dataChannel = null;
    _remoteDescriptionSet = false;
    // Neues Offer = neue Session: alte Antworten/ICE sind stale.
    _pendingSignals.clear();
    _candidateBacklog.clear();
    await createOffer(peerId);
  }

  /// Initialisiert eine neue Peer-Verbindung als Initiator.
  Future<void> createOffer(String peerId) async {
    _currentPeerId ??= peerId;
    await _createPeerConnection();
    await _createDataChannel();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignaling({
      'type': 'offer',
      'from': _myUserId ?? _currentPeerId,
      'sdp': offer.sdp,
    });
  }

  /// Erstellt eine Peer-Verbindung als Empfänger.
  ///
  /// Der Peer ist seit [connect] fixiert (_currentPeerId) und wird hier
  /// NICHT mehr aus der Nachricht übernommen (Audit H8: ein Angreifer
  /// konnte sich per gefälschtem `from` als Peer etablieren).
  Future<void> handleOffer(String peerId, String offerSdp) async {
    _currentPeerId ??= peerId;
    // Stale Verbindungsversuche verwerfen, damit ein Re-Offer des
    // Initiators (Retry) übernommen wird statt zu verhallen.
    if (!_isConnected) {
      try {
        await _peerConnection?.close();
      } catch (_) {}
      _peerConnection = null;
      _dataChannel = null;
      _remoteDescriptionSet = false;
    }
    await _createPeerConnection();

    _peerConnection!.onDataChannel = (channel) {
      _setupDataChannel(channel);
    };

    await _peerConnection!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    _remoteDescriptionSet = true;
    // Pufferierte ICE-Kandidaten (vor der Remote-Description eingetroffen)
    // jetzt nachreichen - sie sind nicht verloren.
    await _flushCandidateBacklog();
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _sendSignaling({
      'type': 'answer',
      'from': _myUserId ?? _currentPeerId,
      'sdp': answer.sdp,
    });
  }

  /// Verarbeitet eine Answer vom Initiator (nur mit existierender
  /// PeerConnection - sonst wird die Answer verworfen statt zu crashen).
  Future<void> handleAnswer(String peerId, String answerSdp) async {
    final pc = _peerConnection;
    if (pc == null) {
      if (kDebugMode) debugPrint('[WebRTC] Answer ohne PeerConnection verworfen.');
      return;
    }
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    _remoteDescriptionSet = true;
    await _flushCandidateBacklog();
  }

  /// Verarbeitet einen ICE-Kandidaten. Kandidaten, die VOR der
  /// Remote-Description (oder gar vor der PeerConnection) eintreffen,
  /// werden gepuffert statt verworfen (Fix: Kandidatenverlust beim
  /// Offer-Handling). Die Flush-Punkte (handleOffer/handleAnswer)
  /// reichen sie nach setRemoteDescription nach.
  Future<void> handleIceCandidate(String peerId, RTCIceCandidate candidate) async {
    if (!_remoteDescriptionSet) {
      _candidateBacklog.add(candidate);
      if (_candidateBacklog.length > 100) _candidateBacklog.removeAt(0);
      return;
    }
    final pc = _peerConnection;
    if (pc == null) return;
    await pc.addCandidate(candidate);
  }

  /// Reicht gepufferte ICE-Kandidaten nach (nach setRemoteDescription).
  Future<void> _flushCandidateBacklog() async {
    final pc = _peerConnection;
    if (pc == null || _candidateBacklog.isEmpty) return;
    for (final candidate in _candidateBacklog) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        if (kDebugMode) debugPrint('[WebRTC] Backlog-Kandidat fehlgeschlagen: $e');
      }
    }
    _candidateBacklog.clear();
  }

  /// Sendet eine verschlüsselte Nachricht über den DataChannel.
  Future<void> sendMessage(String plaintext) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel nicht verbunden');
    }

    final encrypted = await _encryptionService.encryptMessage(_currentPeerId!, plaintext);
    final messageJson = jsonEncode({
      'type': 'signal_message',
      'ciphertext': base64Encode(encrypted.serialize()),
      'messageType': encrypted.getType(),
    });

    _dataChannel!.send(RTCDataChannelMessage(messageJson));
  }

  /// Sendet eine verschlüsselte Kontroll-Nachricht (Anruf-Signaling).
  /// Wird beim Empfänger in den Kontroll-Stream statt in den Chat geroutet.
  Future<void> sendControl(Map<String, dynamic> payload) {
    return sendMessage('$controlPrefix${jsonEncode(payload)}');
  }

  /// Sendet ein verschlüsseltes Sprachpaket eines Anrufs.
  Future<void> sendCallAudio(Uint8List data, {Map<String, dynamic>? metadata}) {
    return sendBinary(
      data,
      contentType: callAudioContentType,
      metadata: metadata,
    );
  }

  /// Sendet Binärdaten (Bild, Audio) verschlüsselt.
  Future<void> sendBinary(Uint8List data, {String contentType = 'application/octet-stream', Map<String, dynamic>? metadata}) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel nicht verbunden');
    }

    final encrypted = await _encryptionService.encryptBinary(_currentPeerId!, data);
    final envelope = <String, dynamic>{
      'type': 'signal_binary',
      'ciphertext': base64Encode(encrypted.serialize()),
      'messageType': encrypted.getType(),
      'contentType': contentType,
    };
    if (metadata != null) {
      envelope['metadata'] = metadata;
    }
    final messageJson = jsonEncode(envelope);

    _dataChannel!.send(RTCDataChannelMessage(messageJson));
  }

  /// Erstellt die PeerConnection mit dynamischer ICE-Konfiguration
  /// (ice-config Edge Function, Fallback: statische EU-STUN-Liste).
  Future<void> _createPeerConnection() async {
    final config = <String, dynamic>{
      'iceServers': await resolveIceServers(),
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentPeerId != null) {
        _sendSignaling({
          'type': 'ice',
          'from': _myUserId ?? _currentPeerId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _iceConnectionStateController.add(state);
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _isConnected = true;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                 state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _isConnected = false;
      }
    };
  }

  /// Erstellt den DataChannel (nur Initiator).
  Future<void> _createDataChannel() async {
    final channel = await _peerConnection!.createDataChannel(_dataChannelLabel, RTCDataChannelInit());
    _setupDataChannel(channel);
  }

  /// Konfiguriert den DataChannel-Handler.
  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (state) {
      _connectionStateController.add(state);
      if (kDebugMode) debugPrint('[WebRTC] DataChannel state: $state');
    };

    channel.onMessage = (message) {
      _handleIncomingMessage(message);
    };
  }

  /// Obergrenze für DataChannel-Envelopes (DoS-Schutz, Audit S3): Der
  /// Peer ist zwar authentifiziert, kann aber bösartig sein - beliebig
  /// große base64-Payloads/metadata-Maps dürfen den Speicher nicht
  /// sprengen können.
  static const int _maxEnvelopeBytes = 512 * 1024;

  /// Maximalzahl der metadata-Einträge im Binär-Envelope.
  static const int _maxMetadataEntries = 16;

  /// Verarbeitet eingehende verschlüsselte Nachrichten.
  Future<void> _handleIncomingMessage(RTCDataChannelMessage message) async {
    try {
      if (message.text.length > _maxEnvelopeBytes ||
          message.binary.lengthInBytes > _maxEnvelopeBytes) {
        if (kDebugMode) debugPrint('[WebRTC] Nachricht zu groß, verworfen.');
        return;
      }
      final data = jsonDecode(message.text) as Map<String, dynamic>;
      final type = data['type'] as String;

      if (type == 'signal_message' || type == 'signal_binary') {
        final ciphertextB64 = data['ciphertext'] as String;
        final ciphertext = base64Decode(ciphertextB64);
        final messageType = data['messageType'] as int;

        if (type == 'signal_message') {
          final CiphertextMessage signalMessage =
              messageType == CiphertextMessage.prekeyType
                  ? PreKeySignalMessage(ciphertext)
                  : SignalMessage.fromSerialized(ciphertext);

          final plaintext = await _encryptionService.decryptMessage(
            _currentPeerId!,
            signalMessage,
          );
          // Kontroll-Nachrichten (Anruf-Signaling) vom Chat-Verlauf trennen.
          // Fällt der JSON-Parse fehl (z. B. Nutzer-Text mit CALL:-Präfix),
          // landet die Nachricht als normaler Chat-Text statt zu
          // verschwinden (Fix: "Nachricht kommt nicht an").
          if (plaintext.startsWith(controlPrefix)) {
            try {
              final payload =
                  jsonDecode(plaintext.substring(controlPrefix.length));
              if (payload is Map<String, dynamic>) {
                _controlController.add(payload);
                return;
              }
            } catch (_) {}
          }
          _incomingMessageController.add(plaintext);
        } else {
          // Binärdaten müssen mit decryptBinary entschlüsselt werden,
          // da decryptMessage einen UTF-8-Text-Decoder anwendet.
          final CiphertextMessage signalMessage =
              messageType == CiphertextMessage.prekeyType
                  ? PreKeySignalMessage(ciphertext)
                  : SignalMessage.fromSerialized(ciphertext);

          final plaintext = await _encryptionService.decryptBinary(
            _currentPeerId!,
            signalMessage,
          );
          final contentType =
              (data['contentType'] as String?) ?? 'application/octet-stream';
          // metadata begrenzen: beliebig große/verschlachtelte Maps vom
          // Peer werden nicht ungeprüft übernommen (Audit S3).
          final metadataRaw = data['metadata'];
          final metadata =
              (metadataRaw is Map && metadataRaw.length <= _maxMetadataEntries)
                  ? Map<String, dynamic>.from(metadataRaw)
                  : null;
          final record =
              (data: plaintext, contentType: contentType, metadata: metadata);
          // Anruf-Sprachpakete in den Kontroll-Stream, sonst normaler
          // Binärkanal (Bilder, Sprachnachrichten).
          if (contentType == callAudioContentType) {
            _controlAudioController.add(record);
          } else {
            _incomingBinaryController.add(record);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRTC] Fehler beim Entschlüsseln: $e');
    }
  }

  /// Schließt die Verbindung.
  Future<void> close() async {
    _dataChannel?.close();
    await _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
    _currentPeerId = null;
    _myUserId = null;
    _isConnected = false;
    _remoteDescriptionSet = false;
    _lastOfferSdp = null;
    _pendingSignals.clear();
    _candidateBacklog.clear();
  }

  /// Sendet ein Relay-Wake-up-Signal an den Peer (nur wenn ein Signaling-
  /// Kanal referenziert ist). Bewusst ohne Payload - der Empfänger holt
  /// selbst via relay_fetch ab; der Server sieht nur das Ping-Signal.
  Future<void> sendRelayPing() async {
    final channel = _signalingChannel;
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(
        event: 'signal',
        payload: {'type': 'relay-ping', 'from': _myUserId ?? _currentPeerId},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[WebRTC] Relay-Ping fehlgeschlagen: $e');
    }
  }

  /// Trennt den Realtime-Kanal und gibt Ressourcen frei.
  Future<void> dispose() async {
    await close();
    await _signalingChannel?.unsubscribe();
    _signalingChannel = null;
    _incomingMessageController.close();
    _incomingBinaryController.close();
    _controlController.close();
    _controlAudioController.close();
    _connectionStateController.close();
    _iceConnectionStateController.close();
    _relayPingController.close();
  }
}

/// Provider für den WebRTC-Service.
final webRTCServiceProvider = Provider<WebRTCService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return WebRTCService(encryption);
});
