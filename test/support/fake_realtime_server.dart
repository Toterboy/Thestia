// Ein winziger Ersatz fuer den Supabase-Realtime-Server - fuer die Tests.
//
// WOFUER (24.11.2026): Der WebRTC-Dienst holt seinen Signaling-Kanal
// ueber `Supabase.instance.client.channel(...)` und wartet dann auf die
// Bestaetigung des Servers ("subscribed"). Ohne Server bleibt der Kanal
// im Zustand "joining" - nach 15 Sekunden laeuft `connect()` in einen
// Timeout. Damit war der komplette Signaling-Aufbau (Kanal, Einladung,
// eingehende Nachricht) im Test nicht pruefbar.
//
// DER WEG: Der Ersatz spricht das Phoenix-Protokoll des Realtime-Clients
// (Version 2.0.0). Die Frames sind JSON-Listen:
//
//   `[joinRef, ref, topic, event, payload]`
//
//   * JOIN: Der Client schickt "phx_join" - der Server antwortet mit
//     "phx_reply" und `{"status":"ok","response":{}}`. OHNE diese
//     Antwort bleibt der Kanal im Zustand "joining" (und der Dienst
//     wartet 15 Sekunden auf sein Ende).
//   * BROADCAST: Der Server schickt
//     `[joinRef, ref, topic, "broadcast", payload]` - damit laeuft der
//     Broadcast-Haendler des Kanals auf und die App bekommt die
//     Nachricht.
//
// DER WERT: Der Test sieht damit genau das, was die App sendet (der
// Ersatz merkt sich die Frames) und kann selbst eine Nachricht in die
// App hineinschieben - ohne echten Server und ohne Netz.
//
// KEINE ZEIT: Der Ersatz antwortet sofort. Die Wartezeiten der App
// (15 Sekunden fuer den Kanal) kommen im Test also nicht vor.
import 'dart:convert';
import 'dart:io';

/// Der Ersatz fuer den Supabase-Realtime-Server.
///
/// DER AUFBAU: Ein echter WebSocket-Server auf dem Loopback. Der
/// Realtime-Client verbindet sich mit dem Pfad
/// "ws://127.0.0.1:PORT/realtime/v1/websocket" - deshalb genuegt ein
/// einfacher HTTP-Server, der die WebSocket-Verbindung annimmt.
class FakeRealtimeServer {
  FakeRealtimeServer._(this._server);

  /// Der HTTP-Server, der die WebSocket-Verbindung annimmt.
  final HttpServer _server;

  /// Die offenen WebSockets (der Test schickt an alle).
  final List<WebSocket> _sockets = <WebSocket>[];

  /// Die Frames, die der Client geschickt hat (in der Reihenfolge).
  ///
  /// Jeder Frame ist eine Mappe mit den Feldern 'join_ref', 'ref',
  /// 'topic', 'event' und 'payload' - so, wie der Client sie sendet.
  final List<Map<String, dynamic>> empfangeneFrames = <Map<String, dynamic>>[];

  /// Die Nutzlasten der Broadcasts, die der Client geschickt hat.
  ///
  /// DER WERT: Der Test sieht damit, WAS die App ueber den Kanal
  /// schickt - das Angebot, die Antwort, den Relay-Ping.
  final List<Map<String, dynamic>> gesendeteBroadcasts =
      <Map<String, dynamic>>[];

  /// Die Topics, denen der Client beigetreten ist (in der Reihenfolge).
  final List<String> beigetreteneTopics = <String>[];

  /// Wie oft hat sich ein Client angemeldet?
  int verbindungen = 0;

  /// Wenn true: der Server verweigert den Verbindungsaufbau.
  ///
  /// DER ZWECK: Der Fall "kein Server erreichbar". Der Client meldet
  /// dann sofort einen Fehler - ohne 15 Sekunden Warten.
  bool verbindungVerweigern = false;

  /// Wenn false: der Server beantwortet den Join nicht.
  ///
  /// DER ZWECK: Der Fall "der Server schweigt" - der Kanal bleibt im
  /// Zustand "joining".
  bool joinBeantworten = true;

  /// Der Port, auf dem der Server laeuft.
  int get port => _server.port;

  /// Die Adresse, die man als Supabase-URL an den Client geben kann.
  String get url => 'http://127.0.0.1:$port';

  /// Startet den Server auf einem freien Port (Loopback).
  static Future<FakeRealtimeServer> starten() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ersatz = FakeRealtimeServer._(server);
    server.listen(ersatz._handleAnfrage);
    return ersatz;
  }

  /// Beendet den Server (die Sockets werden geschlossen).
  Future<void> stoppen() async {
    for (final socket in List<WebSocket>.from(_sockets)) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
  }

  /// Vergisst alles, was bisher angekommen ist (zwischen zwei Tests).
  void vergessen() {
    empfangeneFrames.clear();
    gesendeteBroadcasts.clear();
    beigetreteneTopics.clear();
    verbindungen = 0;
  }

  /// Die Broadcast-Nutzlasten einer bestimmten Art (z. B. 'offer').
  ///
  /// DER WEG: Der Realtime-Client setzt in die Nutzlast zusaetzlich
  /// 'type' und 'event' - die eigene Art der Nachricht steht im Feld
  /// 'kind' (deshalb sucht der Test danach).
  List<Map<String, dynamic>> broadcastsMitArt(String art) =>
      gesendeteBroadcasts.where((nutzlast) => nutzlast['kind'] == art).toList();

  /// Schickt eine Broadcast-Nachricht an alle angemeldeten Clients.
  ///
  /// [topic] ist das volle Topic des Kanals (mit dem Praefix
  /// 'realtime:'), [event] der Ereignisname (in der App 'signal') und
  /// [nutzlast] die Nachricht selbst.
  void sendeBroadcast({
    required String topic,
    required String event,
    required Map<String, dynamic> nutzlast,
  }) {
    final frame = jsonEncode(<dynamic>['1', '1', topic, 'broadcast', nutzlast]);
    for (final socket in List<WebSocket>.from(_sockets)) {
      socket.add(frame);
    }
  }

  /// Nimmt eine HTTP-Anfrage an (WebSocket-Aufbau oder nichts).
  Future<void> _handleAnfrage(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      // Kein WebSocket-Aufbau (z. B. ein REST-Aufruf) - der Ersatz
      // kann das nicht - also 404.
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (verbindungVerweigern) {
      // DER SERVER VERWEIGERT: Es kommt kein "101 Switching Protocols"
      // - der Client meldet den Fehler und der Kanal geht auf Fehler.
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    verbindungen++;
    _sockets.add(socket);
    socket.listen(
      (nachricht) => _handleNachricht(socket, nachricht),
      onDone: () => _sockets.remove(socket),
      onError: (Object _) => _sockets.remove(socket),
    );
  }

  /// Nimmt einen Frame des Clients entgegen.
  void _handleNachricht(WebSocket socket, dynamic roh) {
    if (roh is! String) return;
    final Object? dekodiert;
    try {
      dekodiert = jsonDecode(roh);
    } on FormatException {
      // Kein JSON - der Ersatz versteht nur das Phoenix-Format.
      return;
    }
    if (dekodiert is! List || dekodiert.length < 5) return;
    final frame = <String, dynamic>{
      'join_ref': dekodiert[0],
      'ref': dekodiert[1],
      'topic': dekodiert[2],
      'event': dekodiert[3],
      'payload': dekodiert[4],
    };
    empfangeneFrames.add(frame);

    final event = frame['event'];
    final topic = frame['topic'];
    final nutzlast = frame['payload'];

    if (event == 'phx_join') {
      if (topic is String) beigetreteneTopics.add(topic);
      if (!joinBeantworten) return;
      _reply(socket, 'ok', <String, dynamic>{});
      return;
    }
    if (event == 'phx_leave' || event == 'phx_heartbeat') {
      _reply(socket, 'ok', <String, dynamic>{});
      return;
    }
    if (event == 'broadcast') {
      if (nutzlast is Map) {
        gesendeteBroadcasts.add(Map<String, dynamic>.from(nutzlast));
      }
    }
  }

  /// Antwortet auf den letzten Frame (Phoenix: "phx_reply").
  ///
  /// DER GRUND: Die Antwort geht nur an den Socket, der gefragt hat -
  /// sonst antwortet der Server allen Clients mit derselben Nummer.
  void _reply(WebSocket socket, String status, Map<String, dynamic> response) {
    if (empfangeneFrames.isEmpty) return;
    final frame = empfangeneFrames.last;
    final antwort = jsonEncode(<dynamic>[
      frame['join_ref'],
      frame['ref'],
      frame['topic'],
      'phx_reply',
      <String, dynamic>{'status': status, 'response': response},
    ]);
    socket.add(antwort);
  }
}
