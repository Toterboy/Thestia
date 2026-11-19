/// Die Zertifikat-Pins - die EINE Quelle der Wahrheit.
///
/// WARUM EIGENE DATEI (Audit 16.11.2026): Das Rotations-Werkzeug
/// (`tool/scripts/rotate_cert_pins.dart`) hatte eine eigene Kopie der
/// Pin-Tabelle. Die beiden Tabellen liefen auseinander - das Werkzeug
/// meldete dauerhaft "Rotation nötig", obwohl der echte Zustand im
/// Betrieb ganz woanders lag. Und niemand sah, dass der in der App
/// gepinnte Leaf-Pin seit dem 24.10.2026 veraltet war.
///
/// Diese Datei enthaelt KEINE Flutter-Abhaengigkeit - so kann sie
/// sowohl von der App (`cert_pinning.dart`) als auch vom reinen
/// Dart-Werkzeug gelesen werden. Es gibt damit nur noch EINE Tabelle.
///
/// Der Import in der App:
///
/// ```dart
/// import 'package:thestia/utils/security/cert_pins.dart';
/// ```
library;

/// Der gepinnte Host mit seinen Pins und dem Rotationsfenster.
class PinnedHost {
  const PinnedHost({
    required this.pins,
    required this.leafNotBeforeEpoch,
    required this.leafNotAfterEpoch,
    required this.issuer,
  });

  /// Die DER-Hashes (SHA-256 ueber das X.509-Zertifikat, base64).
  ///
  /// Mindestens EIN Pin muss passen. Der erste Eintrag ist der Leaf
  /// (das Server-Zertifikat), danach Intermediate und Root als
  /// Reserve (Dart liefert im Callback nur das Leaf - die beiden
  /// anderen sind damit praktisch nicht pruefbar, sie stehen aber als
  /// Dokumentation der Kette im Code).
  final List<String> pins;

  /// Beginn der Gueltigkeit des gepinnten Leaf-Zertifikats
  /// (Sekunden seit 1970, UTC).
  final int leafNotBeforeEpoch;

  /// Ende der Gueltigkeit des gepinnten Leaf-Zertifikats
  /// (Sekunden seit 1970, UTC).
  final int leafNotAfterEpoch;

  /// Erwartete Bestandteile des Leaf-Ausstellers (CN + Organisation).
  final List<String> issuer;

  /// Beginn der Gueltigkeit als [DateTime] (UTC).
  DateTime get leafNotBefore => DateTime.fromMillisecondsSinceEpoch(
    leafNotBeforeEpoch * 1000,
    isUtc: true,
  );

  /// Ende der Gueltigkeit als [DateTime] (UTC).
  DateTime get leafNotAfter => DateTime.fromMillisecondsSinceEpoch(
    leafNotAfterEpoch * 1000,
    isUtc: true,
  );

  /// Ist das Rotationsfenster geoeffnet?
  ///
  /// DER GRUND (Audit 16.11.2026): Der Aussteller-Fallback war
  /// dauerhaft offen und hat den Leaf-Pin damit entwertet - ein
  /// Kompromitt der CA waere sofort MITM-faehig gewesen. Jetzt ist er
  /// nur um das Ablaufdatum des gepinnten Leafs geoeffnet: dort
  /// rotieren die Zertifikate (Let's Encrypt stellt das neue rund einen
  /// Monat vor dem Ablauf des alten aus).
  bool rotationWindowOpen(
    DateTime now, {
    int leadDays = kRotationLeadDays,
    int graceDays = kRotationGraceDays,
  }) {
    final from = leafNotAfter.subtract(Duration(days: leadDays));
    final to = leafNotAfter.add(Duration(days: graceDays));
    return !now.isBefore(from) && !now.isAfter(to);
  }
}

/// Vorlauf des Rotationsfensters vor dem Ablaufdatum (Tage).
const int kRotationLeadDays = 45;

/// Nachlauf des Rotationsfensters nach dem Ablaufdatum (Tage).
const int kRotationGraceDays = 14;

/// Die gepinnten Hosts.
///
/// ANLEITUNG FUER DIE ROTATION (Audit 16.11.2026):
///   1. `dart run tool/scripts/rotate_cert_pins.dart` - das Werkzeug vergleicht
///      die Live-Zertifikate mit dieser Tabelle.
///   2. Den neuen Leaf-Hash hier eintragen (den alten zunaechst
///      behalten) und die Gueltigkeit (`leafNotBeforeEpoch`,
///      `leafNotAfterEpoch`) anpassen.
///   3. `flutter test test/cert_pinning_test.dart` laufen lassen.
///   4. Release bauen. Der CI-Schritt "Zertifikat-Pins pruefen"
///      schlaegt fehl, sobald der Pin veraltet ist - das ist gewollt.
///
/// Die Zeitpunkte stehen als Sekunden seit 1970 (UTC), damit die
/// Tabelle `const` bleiben kann.
const Map<String, PinnedHost> kPinnedHosts = {
  // Supabase (jftuigjbmmuvrckbchqo.supabase.co).
  // 1) Leaf (Let's Encrypt, CN=supabase.co / *.supabase.co) -
  //    ausgelesen am 16.11.2026, gueltig 24.10.2026 bis 22.01.2027.
  // 2) Intermediate (Google Trust Services, CN=WE1) - Jahre stabil.
  // 3) Root (Google Trust Services, CN=GTS Root R4) - Jahrzehnte stabil.
  //
  // WICHTIG: Der Leaf wurde am 24.10.2026 erneuert. Der bis dahin
  // gepinnte Hash war ab dem 24.10.2026 veraltet - die App lief dadurch
  // ausschliesslich ueber den Aussteller-Fallback.
  'jftuigjbmmuvrckbchqo.supabase.co': PinnedHost(
    pins: <String>[
      '6v9Fmtu620ZUy7m7Ps+XC68FFGxXMqy8cLMqf009Yq4=', // Leaf (Let's Encrypt)
      'HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=', // Intermediate (WE1)
      'drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac=', // Root (GTS Root R4)
    ],
    leafNotBeforeEpoch: 1792848156, // 24.10.2026 13:22:36 UTC
    leafNotAfterEpoch: 1800627752, // 22.01.2027 14:22:32 UTC
    // Leaf-Issuer: CN=WE1 / O=Google Trust Services (beides muss passen).
    issuer: <String>['cn=we1', 'o=google trust services'],
  ),
  // Hugging Face Inference Router (router.huggingface.co), H-09.
  // 1) Leaf (CN=huggingface.co, AWS/CloudFront) - ausgelesen am
  //    16.11.2026, gueltig 14.08.2026 bis 27.02.2027.
  // 2) Intermediate (Amazon RSA 2048 M01) - stabil.
  // 3) Root (Amazon Root CA 1) - Jahrzehnte stabil.
  'router.huggingface.co': PinnedHost(
    pins: <String>[
      'DspFS0ajYXzS6MI03Lnp4hXHHD4WFCTK5QXIdiUMOPE=', // Leaf (huggingface.co)
      'Uzjr7I+yrGCZYSbT52qjT9DzMYrHjrt6yPbxNh9ISzM=', // Intermediate (Amazon RSA 2048 M01)
      'h9zU3HRkCjIs0gVVJQbRvmTxJZYlgJZUSYa0hQvHJwY=', // Root (Amazon Root CA 1)
    ],
    leafNotBeforeEpoch: 1786672800, // 14.08.2026 02:00:00 UTC
    leafNotAfterEpoch: 1803776399, // 28.02.2027 00:59:59 UTC
    // Leaf-Issuer: CN=Amazon RSA 2048 M01 / O=Amazon.
    issuer: <String>['cn=amazon rsa 2048 m01', 'o=amazon'],
  ),
};

/// Der Standard-Host (Supabase), wenn kein Host explizit uebergeben wird.
const String kDefaultPinnedHost = 'jftuigjbmmuvrckbchqo.supabase.co';
