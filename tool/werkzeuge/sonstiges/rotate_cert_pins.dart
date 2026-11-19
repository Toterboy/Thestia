// Pin-Rotations-Werkzeug für CertPinning (Audit B7).
//
// Ermittelt die aktuellen DER-SHA256-Hashes (Leaf) der gepinnten Hosts und
// vergleicht sie mit den in lib/utils/cert_pins.dart konfigurierten Pins.
//
// DIE EINE QUELLE (Audit 16.11.2026): Frueher hatte dieses Werkzeug eine
// eigene Kopie der Pin-Tabelle. Die beiden Tabellen liefen auseinander -
// das Werkzeug meldete dauerhaft "Rotation noetig", obwohl der Pin in
// der App voellig in Ordnung war. Und umgekehrt: der in der App
// gepinnte Leaf-Pin war am 16.11.2026 seit dem 24.10.2026 veraltet,
// ohne dass jemand es bemerkt hat. Jetzt liest das Werkzeug DIESELBE
// Tabelle wie die App (lib/utils/cert_pins.dart).
//
// Aufruf:
//   dart run tool/werkzeuge/sonstiges/rotate_cert_pins.dart
//
// Vorgehen bei Rotation (z. B. nach Let's-Encrypt-/GTS-Erneuerung ~90 Tage):
//   1. Script ausfuehren - es zeigt fehlende/abweichende Pins.
//   2. Neuen Hash in lib/utils/cert_pins.dart eintragen (kPinnedHosts),
//      die Gueltigkeit (leafNotBeforeEpoch/leafNotAfterEpoch) anpassen.
//      Alten PIN zunaechst BEHALTEN (Backup-Pin), App releasen,
//      ~7 Tage warten, dann den alten entfernen.
//   3. flutter test test/cert_pinning_test.dart zur Kontrolle ausfuehren.
//
// Bewusst reines Dart (keine Flutter-Abhaengigkeit): laeuft ueberall.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:thestia/utils/cert_pins.dart';

Future<X509Certificate?> _fetchLeafCertificate(String host) async {
  try {
    final socket = await SecureSocket.connect(
      host,
      443,
      timeout: const Duration(seconds: 10),
      onBadCertificate: (cert) => true, // Cert nur abgreifen, nicht validieren
    );
    final cert = socket.peerCertificate;
    await socket.close();
    return cert;
  } catch (e) {
    stderr.writeln('FEHLER bei $host: $e');
    return null;
  }
}

String _sha256Base64(Uint8List der) {
  final digest = _sha256(der);
  return base64Encode(digest);
}

// Minimaler SHA-256 (keine externen Abhaengigkeiten im Tool).
const _k = [
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

List<int> _sha256(List<int> data) {
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final h = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final msg = List<int>.from(data)..addAll([0x80]);
  while (msg.length % 64 != 56) {
    msg.add(0);
  }
  final bitLen = data.length * 8;
  msg.addAll([
    (bitLen >>> 56) & 0xff,
    (bitLen >>> 48) & 0xff,
    (bitLen >>> 40) & 0xff,
    (bitLen >>> 32) & 0xff,
    (bitLen >>> 24) & 0xff,
    (bitLen >>> 16) & 0xff,
    (bitLen >>> 8) & 0xff,
    bitLen & 0xff,
  ]);

  for (var block = 0; block < msg.length; block += 64) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      final o = block + i * 4;
      w[i] =
          (msg[o] << 24) | (msg[o + 1] << 16) | (msg[o + 2] << 8) | msg[o + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      // BUGFIX (16.11.2026): Es fehlte das w[i - 7]! Der Standard ist
      //   W[i] = W[i-16] + s0 + W[i-7] + s1
      // Mit der Lücke lieferte diese eigene SHA-256 FALSCHE Hashes - und
      // damit passte der in der App gepinnte Leaf nie. Die App lief
      // dadurch nur noch ueber den Aussteller-Fallback. Gefangen durch
      // den Selbsttest (--selftest, Testvektor "abc").
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];

    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }

  return h
      .expand(
        (v) => [
          (v >>> 24) & 0xff,
          (v >>> 16) & 0xff,
          (v >>> 8) & 0xff,
          v & 0xff,
        ],
      )
      .toList();
}

Future<void> main(List<String> args) async {
  // DER SELBSTTEST (Audit 16.11.2026): Das Werkzeug hat seinen eigenen
  // SHA-256 (ohne Paket-Abhaengigkeit). Genau der lieferte am
  // 16.11.2026 einen ANDEREN Hash als Python und OpenSSL - der Pin
  // in der App passte also NIE, und die App lief nur noch ueber den
  // Aussteller-Fallback. Der Selftest faengt genau das ab.
  if (args.contains('--selftest')) {
    // Testvektor "abc" (SHA-256), base64-kodiert.
    final erwartet = 'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=';
    final ist = _sha256Base64(Uint8List.fromList(utf8.encode('abc')));
    if (ist != erwartet) {
      stdout.writeln('FEHLER: Die eigene SHA-256 ist falsch!');
      stdout.writeln('  erwartet: $erwartet');
      stdout.writeln('  bekommen: $ist');
      exit(1);
    }
    stdout.writeln('OK: Die eigene SHA-256 ist korrekt (Testvektor "abc").');
    exit(0);
  }

  var mismatch = false;
  final jetzt = DateTime.now();

  stdout.writeln(
    'Pin-Pruefung (Quelle: lib/utils/cert_pins.dart, Stand ${jetzt.toIso8601String().substring(0, 10)})',
  );

  for (final entry in kPinnedHosts.entries) {
    final host = entry.key;
    final gepinnt = entry.value;
    stdout.writeln('Pruefe $host ...');
    final cert = await _fetchLeafCertificate(host);
    if (cert == null) {
      stdout.writeln('  !! Host nicht erreichbar - uebersprungen.');
      mismatch = true;
      continue;
    }

    final leafHash = _sha256Base64(cert.der);
    final matches = gepinnt.pins.contains(leafHash);
    final issuerOk = _issuerKnown(gepinnt, cert.issuer);

    // Das Rotationsfenster: nur dort darf der Aussteller-Fallback den
    // Leaf-Pin-Mismatch auffangen (Audit 16.11.2026).
    final fensterOffen = gepinnt.rotationWindowOpen(jetzt);
    final tageBisAblauf = gepinnt.leafNotAfter.difference(jetzt).inDays;

    if (matches) {
      stdout.writeln(
        '  OK: Leaf-Pin stimmt '
        '($leafHash, gueltig bis ${cert.endValidity.toLocal()}).',
      );
    } else {
      mismatch = true;
      stdout.writeln('  !! Leaf-Pin STIMMT NICHT (Rotation noetig).');
      stdout.writeln('     Aktueller Leaf-Hash : $leafHash');
      stdout.writeln('     Issuer              : ${cert.issuer}');
      stdout.writeln(
        '     Gueltigkeit          : '
        '${cert.startValidity.toLocal()} - ${cert.endValidity.toLocal()}',
      );
      stdout.writeln(
        '     => Neuen Hash in lib/utils/cert_pins.dart '
        '(kPinnedHosts["$host"]) aufnehmen (alten zunaechst behalten, '
        'siehe Pin-Rotation-Doku).',
      );
      if (issuerOk) {
        stdout.writeln(
          '     Hinweis: Issuer ist die erwartete CA - vermutlich '
          'regulaere Rotation, kein Angriff.',
        );
      } else {
        stdout.writeln(
          '     WARNUNG: Issuer ist NICHT die erwartete CA - '
          'manuelle Pruefung empfohlen!',
        );
      }
      if (!fensterOffen) {
        stdout.writeln(
          '     ACHTUNG: Das Rotationsfenster ist ZU - der Fallback greift '
          'nicht. Die App verliert in diesem Zustand die Verbindung.',
        );
      }
    }

    // Der Pin darf nicht bald ablaufen: sonst steht die App beim
    // Rotieren ohne Kontakt da.
    if (tageBisAblauf < 30) {
      mismatch = true;
      stdout.writeln(
        '  !! Der gepinnte Leaf laeuft in nur $tageBisAblauf Tagen ab - '
        'jetzt erneuern (sonst bricht die App beim Rotieren ab).',
      );
    }
    stdout.writeln(
      '     Rotationsfenster: '
      '${gepinnt.rotationWindowOpen(jetzt) ? "offen" : "zu"} '
      '(Leaf laeuft am ${gepinnt.leafNotAfter.toIso8601String().substring(0, 10)} ab)',
    );
  }

  stdout.writeln(
    mismatch
        ? '\nErgebnis: MINDESTENS EIN PIN AKTUALISIEREN (siehe oben).'
        : '\nErgebnis: Alle Pins aktuell.',
  );
  exit(mismatch ? 1 : 0);
}

bool _issuerKnown(PinnedHost gepinnt, String issuer) {
  final i = issuer.toLowerCase();
  return gepinnt.issuer.every(i.contains);
}
