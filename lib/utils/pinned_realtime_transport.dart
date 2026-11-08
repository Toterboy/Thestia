import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:thestia/utils/cert_pinning.dart';

/// Der WebSocket-Transport fuer Supabase Realtime - mit DEMSELBEN
/// strikten Pinning-Client wie der REST-Stack.
///
/// BEFUND (08.11.2026, Sicherheitspruefung): Der Standard-Transport von
/// `realtime_client` erzeugt den WebSocket ohne eigenen Client:
///
///     IOWebSocketChannel.connect(url, headers: headers, pingInterval: ...)
///
/// `IOWebSocketChannel` erzeugt damit einen HttpClient MIT System-Root-
/// Store. Dart ruft `badCertificateCallback` nur auf, wenn die
/// System-Validierung FEHLGESCHLAGEN ist - ein von einer fremden CA
/// ausgestelltes Zertifikat, das das System akzeptiert, umgeht das
/// Pinning also komplett.
///
/// WARUM DAS JETZT KRITISCH IST: Das Dart-SDK-Advisory GHSA-frr6-h895-5pxp
/// (High) besagt, dass `dart:io` auf Android die Zwischenzertifikate
/// der kompromittierten eMudhra-CA weiterhin akzeptiert - der
/// eingebaute BoringSSL-Store kennt die Sperrliste des Betriebssystems
/// nicht. Ein Angreifer im Netzpfad kann damit ein gefaelschtes
/// Zertifikat fuer `*.supabase.co` vortaeuschen. Mit diesem Transport
/// ist das ausgeschlossen: der Client hat einen LEEREN Root-Store, der
/// Pin-Callback laeuft IMMER, und ohne passenden Pin wird die
/// Verbindung abgelehnt (fail-closed).
///
/// Der Host wird aus der WebSocket-URL abgeleitet. Ist er nicht
/// gepinnt, wird die Verbindung ebenfalls abgelehnt - fail-closed ist
/// hier richtig: ein ungepinnter Realtime-Kanal waere genau die Luecke,
/// die dieser Transport schliesst.
///
/// DER PING-INTERVALL (25 Sekunden) entspricht dem des
/// Standard-Transports von realtime_client. Ohne ihn wuerde der
/// Server die Verbindung nach einer Weile schliessen.
///
/// Signatur: `WebSocketTransport` aus realtime_client ist
/// `WebSocketChannel Function(String url, Map<String, String> headers)`.
WebSocketChannel gepinnterRealtimeTransport(
  String url,
  Map<String, String> headers,
) {
  final host = Uri.tryParse(url)?.host ?? '';
  return IOWebSocketChannel.connect(
    url,
    headers: headers,
    pingInterval: const Duration(seconds: 25),
    customClient: CertPinning.pinnedHttpClient(host),
  );
}
