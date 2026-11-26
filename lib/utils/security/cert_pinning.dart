import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:thestia/utils/security/cert_pins.dart';

/// Zertifikat-Pinning (DER-Hash, SHA-256) – fail-closed.
///
/// Schützt vor Man-in-the-Middle, selbst wenn ein Angreifer ein gültiges,
/// von einer vertrauenswürdigen CA ausgestelltes Zertifikat präsentieren
/// könnte. Wir vergleichen den SHA-256-Hash des gesamten X.509-Zertifikats
/// (DER-kodiert) des Servers mit unseren fest einkodierten, erwarteten Hashes.
///
/// Warum DER (nicht SPKI)?
///   - dart:io X509Certificate hat kein publicKey-Feld
///   - pointycastle X509Utils ist src/-only (kein öffentliches API)
///   - Manuelle DER-Parsing zur SPKI-Extraktion ist fragil und fehleranfällig
///     (siehe Commit-Historie: zwei Anläufe, beide mit Byte-Offset-Bugs)
///   - Let's Encrypt generiert bei jeder Erneuerung neue Keys → SPKI ändert
///     sich ebenso wie DER → kein praktischer Vorteil für Leaf-Zertifikate
///   - Intermediate + Root DER-Hashes sind für Jahre stabil
///
/// Die Pins selbst stehen in `cert_pins.dart` - das ist die EINE Quelle,
/// die auch das Rotations-Werkzeug liest (Audit 16.11.2026).
///
/// Pinning-Strategie (Audit 16.11.2026, überarbeitet):
///
/// DER BISHERIGE ZUSTAND (befund im Sicherheits-Audit vom 16.11.2026):
/// Der Rotations-Fallback war **dauerhaft** aktiv. Stimmt der Leaf-Pin
/// nicht, wurde auf CA-Ebene degradiert (Aussteller + Host + Gültigkeit).
/// Damit war der Leaf-Pin faktisch OPTIONAL: ein Kompromitt der CA
/// (Google Trust Services) wäre sofort MITM-fähig gewesen - genau das
/// Szenario, das die eMudhra-Lücke ausgelöst hat. Der Live-Test am
/// 16.11.2026 zeigte es deutlich: der gepinnte Leaf-Pin war seit dem
/// 24.10.2026 veraltet, die App lief deshalb nur noch über den
/// Fallback.
///
/// JETZT: Der Fallback gilt **nur im Rotationsfenster** um das Ablaufdatum
/// des gepinnten Leaf-Zertifikats (siehe `PinnedHost.rotationWindowOpen`).
/// Außerhalb dieses Fensters gilt: Leaf-Pin passt nicht → Verbindung
/// wird abgebrochen. Wer die App nicht aktualisiert, verliert nach dem
/// Ablauf den Zugang - das ist der gewollte Druck, die Pins zu pflegen.
///
/// Extraktion der DER-Hashes (unabhängig verifiziert via openssl + Node.js):
///
///   # 1. Zertifikatskette abrufen:
///   openssl s_client -connect jftuigjbmmuvrckbchqo.supabase.co:443 \
///     -showcerts 2>/dev/null > cert_chain.pem
///
///   # 2. Leaf (erstes Zertifikat):
///   awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' cert_chain.pem | head -22 | \
///     openssl x509 -outform der | openssl dgst -sha256 -binary | openssl base64
///
///   # 3. Intermediate (zweites Zertifikat): analog mit zweitem Block
///   # 4. Root (drittes Zertifikat): analog mit drittem Block
///
///   # Alternative (Node.js, falls openssl nicht verfügbar):
///   node -e "const tls=require('tls');const c=tls.connect({host:'...',port:443,
///   servername:'...',rejectUnauthorized:false},()=>{const r=c.getPeerCertificate(true);
///   const cr=require('crypto');[r,r.issuerCertificate,
///   r.issuerCertificate?.issuerCertificate].filter(Boolean).forEach(cert=>{
///   console.log(cr.createHash('sha256').update(Buffer.from(cert.raw,'base64'))
///   .digest('base64'));});c.end();});"
///
/// WICHTIG: `withTrustedRoots: false` + leerer Root-CA-Store erzwingt
/// den Callback für JEDE Verbindung — nicht nur bei CA-Fehlern.
class CertPinning {
  /// Standard-Host (Supabase), wenn kein Host explizit übergeben wird.
  static const String _defaultHost = kDefaultPinnedHost;

  /// Die gepinnten Hosts (die eine Quelle der Wahrheit).
  static const Map<String, PinnedHost> _pinnedByHost = kPinnedHosts;

  /// Ob [host] ein gepinnter Host ist (exakter Vergleich, v0.9.0).
  static bool isPinnedHost(String host) {
    final needle = host.toLowerCase();
    return _pinnedByHost.keys.any((h) => h.toLowerCase() == needle);
  }

  /// Prüft ein Zertifikat für [expectedHost] (reine Logik, v0.9.0):
  /// exakter Pin ODER – **nur im Rotationsfenster** – eng begrenzter
  /// Rotation-Fallback (Issuer + Host + Gültigkeit).
  static bool verifyCertificate({
    required String expectedHost,
    required X509Certificate cert,
    required String certHost,
    DateTime? now,
  }) {
    final pinned = _pinnedByHost[expectedHost];
    if (pinned == null) return false;
    final hash = base64Encode(sha256.convert(cert.der).bytes);
    if (pinned.pins.contains(hash)) return true;
    // DER FALLBACK NUR IM ROTATIONSFENSTER (Audit 16.11.2026).
    if (!pinMismatchAllowed(host: expectedHost, now: now)) return false;
    return pinned.issuerFallbackMatches(
      targetHost: expectedHost,
      cert: cert,
      certHost: certHost,
    );
  }

  /// Darf ein Leaf-Pin-Mismatch durch den Rotation-Fallback aufgefangen
  /// werden?
  ///
  /// DER GRUND (Audit 16.11.2026): Der Fallback war dauerhaft offen und
  /// hat den Leaf-Pin damit entwertet (ein Kompromitt der CA wäre sofort
  /// MITM-fähig). Jetzt gilt er nur im Rotationsfenster um das Ablaufdatum
  /// des gepinnten Leaf-Zertifikats.
  ///
  /// REINE LOGIK (ohne Zertifikat) - damit im Test prüfbar.
  @visibleForTesting
  static bool pinMismatchAllowed({required String host, DateTime? now}) {
    final pinned = _pinnedByHost[host];
    if (pinned == null) return false;
    return pinned.rotationWindowOpen(now ?? DateTime.now());
  }

  /// Für Tests: die aktuell konfigurierten DER-Hashes des Standard-Hosts.
  @visibleForTesting
  static List<String> get pinnedCertHashes =>
      _pinnedByHost[_defaultHost]?.pins ?? const <String>[];

  /// Für Tests: die DER-Hashes eines konkreten Hosts (leer = unbekannt).
  @visibleForTesting
  static List<String> pinnedCertHashesFor(String host) =>
      _pinnedByHost[host]?.pins ?? const <String>[];

  /// Für Tests/Werkzeuge: das Ablaufdatum des gepinnten Leaf-Zertifikats.
  @visibleForTesting
  static DateTime? pinnedLeafValidUntil(String host) =>
      _pinnedByHost[host]?.leafNotAfter;

  /// Für Tests/Werkzeuge: das Rotationsfenster des Hosts.
  @visibleForTesting
  static ({DateTime from, DateTime to})? rotationWindowFor(String host) {
    final pinned = _pinnedByHost[host];
    if (pinned == null) return null;
    final bis = pinned.leafNotAfter;
    return (
      from: bis.subtract(const Duration(days: kRotationLeadDays)),
      to: bis.add(const Duration(days: kRotationGraceDays)),
    );
  }

  /// Erzeugt einen [HttpClient] mit DER-Pinning für [host].
  ///
  /// - Gepinnte Hosts: exakter Leaf-Pin; bei Mismatch wird der
  ///   Rotation-Fallback **nur im Rotationsfenster** geprüft (Issuer +
  ///   Host + Gültigkeit).
  /// - Ungepinnte Hosts: **fail-closed** – leerer Root-Store, jeder
  ///   Zertifikatversuch wird abgelehnt. Vorher liefen diese Hosts über
  ///   den System-Trust-Store; damit hätte eine nachinstallierte
  ///   Fremd-CA (MDM, Stalkerware) das Pinning umgangen (Befund im
  ///   Audit vom 16.11.2026). Wer einen eigenen Supabase-Host
  ///   betreibt, MUSS dessen Pins eintragen (siehe
  ///   `tool/scripts/rotate_cert_pins.dart`).
  static HttpClient pinnedHttpClient([String? host]) {
    final targetHost = host ?? _defaultHost;
    final pinned = _pinnedByHost[targetHost];

    if (pinned == null) {
      // FAIL-CLOSED: kein Pin -> kein System-Trust.
      final client = HttpClient(
        context: SecurityContext(withTrustedRoots: false),
      );
      client.badCertificateCallback = (cert, certHost, port) {
        if (kDebugMode) {
          debugPrint(
            '[CERT_PINNING] Keine Pins für $certHost:$port konfiguriert - '
            'Verbindung abgelehnt (fail-closed).',
          );
        }
        return false;
      };
      return client;
    }

    final context = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: context);
    client.badCertificateCallback = (cert, certHost, port) {
      // Strikte Stufe: Callback läuft IMMER (leerer Root-Store) -
      // auch bei systemseitig gültigen Zertifikaten (Schutz vor
      // nachinstallierten Fremd-CAs auf dem Gerät).
      if (verifyCertificate(
        expectedHost: targetHost,
        cert: cert,
        certHost: certHost,
      )) {
        return true;
      }

      if (kDebugMode) {
        debugPrint(
          '[CERT_PINNING] ACHTUNG: Zertifikat-Pin-Mismatch für '
          '$certHost:$port, möglicher MITM-Angriff! Verbindung abgelehnt.',
        );
      }
      return false;
    };
    return client;
  }
}

/// Der Aussteller-Fallback (nur im Rotationsfenster).
extension _PinnedHostFallback on PinnedHost {
  /// Prüft den Rotation-Fallback: Zertifikat muss
  /// 1. vom erwarteten Intermediate (exakter CN + Organisation, Audit M-9),
  /// 2. für den Ziel-Host und
  /// 3. innerhalb seines Gültigkeitszeitraums ausgestellt sein.
  bool issuerFallbackMatches({
    required String targetHost,
    required X509Certificate cert,
    required String certHost,
  }) {
    final hostOk = certHost.toLowerCase() == targetHost.toLowerCase();
    // Whitespace normalisieren, Kleinbuchstaben; ALLE Komponenten müssen
    // enthalten sein (CN des konkreten Intermediates + Organisation).
    final issuerNormalized = cert.issuer.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final issuerOk = issuer.every(issuerNormalized.contains);
    final now = DateTime.now();
    final validityOk =
        cert.startValidity.isBefore(now) && cert.endValidity.isAfter(now);

    return hostOk && issuerOk && validityOk;
  }
}
