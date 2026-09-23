import 'dart:io';

import 'package:wisp/utils/cert_pinning.dart';

/// Globale HTTP-Overrides (v0.9.0): Zieht das Zertifikat-Pinning über
/// ALLE Dart-seitigen TLS-Verbindungen – insbesondere den gesamten
/// Supabase-Traffic (Auth, DB, Storage, Functions, Realtime), der über
/// supabase_flutter läuft und keinen eigenen HttpClient erlaubt.
///
/// Verhalten:
/// - Gepinnter Host (z. B. Supabase): exakter Pin ODER eng begrenzter
///   Rotation-Fallback ([CertPinning.verifyCertificate]), sonst
///   Ablehnung (fail-closed).
/// - Alle anderen Hosts: unverändert (System-Trust; der Callback läuft
///   dort nur, wenn die System-Validierung BEREITS fehlgeschlagen ist,
///   und gibt `false` zurück = Ablehnung wie bisher).
///
/// Ehrliche Grenze: Mit System-Roots läuft der Callback nur bei
/// fehlgeschlagener System-Validierung. Eine auf dem Gerät
/// nachinstallierte Fremd-CA (MDM, Stalkerware) wird systemseitig
/// akzeptiert und umgeht diesen Check – dagegen hilft nur der
/// strikte [CertPinning.pinnedHttpClient] (leerer Root-Store, bereits
/// für WebRTC-Signaling im Einsatz). Firebase/FCM laufen nativ
/// (OkHttp) und sind von Dart-Overrides unberührt.
class WispHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Hinweis: badCertificateCallback hat nur einen Setter (kein
    // Getter) - ein vorheriger Callback kann nicht verkettet werden.
    // Für nicht-gepinnte Hosts gibt der Callback `false` zurück: Er
    // läuft nur, wenn die System-Validierung BEREITS fehlgeschlagen
    // ist - Ablehnung wie ohne Overrides (fail-closed).
    client.badCertificateCallback = (cert, host, port) {
      if (CertPinning.isPinnedHost(host)) {
        return CertPinning.verifyCertificate(
          expectedHost: host.toLowerCase(),
          cert: cert,
          certHost: host,
        );
      }
      return false;
    };
    return client;
  }
}
