// Pin-Rotations-Werkzeug für CertPinning (Audit B7).
//
// Ermittelt die aktuellen DER-SHA256-Hashes (Leaf) der gepinnten Hosts und
// vergleicht sie mit den in lib/utils/cert_pinning.dart konfigurierten Pins.
//
// Aufruf:
//   dart run tool/rotate_cert_pins.dart
//
// Vorgehen bei Rotation (z. B. nach Let's-Encrypt-/GTS-Erneuerung ~90 Tage):
//   1. Script ausführen – es zeigt fehlende/abweichende Pins.
//   2. Neuen Hash aus der Ausgabe in _pinnedByHost eintragen (alten PIN
//      zunächst KEEPEN, App releasen, ~7 Tage warten, dann alten entfernen –
//      siehe Doc-Comment in cert_pinning.dart).
//   3. flutter test test/cert_pinning_test.dart zur Kontrolle ausführen.
//
// Bewusst reines Dart (keine Flutter-Abhängigkeit): läuft überall.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Muss mit CertPinning._defaultHost / _pinnedByHost in
/// lib/utils/cert_pinning.dart synchron gehalten werden.
const Map<String, List<String>> pinnedHosts = {
  'jftuigjbmmuvrckbchqo.supabase.co': [
    '5IkHI2A4x/6wXNhi5BzX/Fco8o2mG5Xmdh2cKVxbMpg=', // Leaf
    'HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y=', // Intermediate (WE1)
    'drJ7gKWAJ9w88dpo2sFwEO2TmX0LYD4vrb6FASSTtac=', // Root (GTS Root R4)
  ],
  'router.huggingface.co': [
    'DspFS0ajYXzS6MI03Lnp4hXHHD4WFCTK5QXIdiUMOPE=', // Leaf
    'Uzjr7I+yrGCZYSbT52qjT9DzMYrHjrt6yPbxNh9ISzM=', // Intermediate (Amazon RSA 2048 M01)
    'h9zU3HRkCjIs0gVVJQbRvmTxJZYlgJZUSYa0hQvHJwY=', // Root (Amazon Root CA 1)
  ],
};

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

// Minimaler SHA-256 (keine externen Abhängigkeiten im Tool).
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
  var mismatch = false;

  for (final entry in pinnedHosts.entries) {
    final host = entry.key;
    stdout.writeln('Prüfe $host ...');
    final cert = await _fetchLeafCertificate(host);
    if (cert == null) {
      stdout.writeln('  !! Host nicht erreichbar – übersprungen.');
      mismatch = true;
      continue;
    }

    final leafHash = _sha256Base64(cert.der);
    final matches = entry.value.contains(leafHash);
    final issuerOk = _issuerKnown(host, cert.issuer);

    if (matches) {
      stdout.writeln(
        '  OK: Leaf-Pin stimmt '
        '($leafHash, gültig bis ${cert.endValidity.toLocal()}).',
      );
    } else {
      mismatch = true;
      stdout.writeln('  !! Leaf-Pin STIMMT NICHT (Rotation nötig).');
      stdout.writeln('     Aktueller Leaf-Hash : $leafHash');
      stdout.writeln('     Issuer              : ${cert.issuer}');
      stdout.writeln(
        '     Gültigkeit          : '
        '${cert.startValidity.toLocal()} – ${cert.endValidity.toLocal()}',
      );
      stdout.writeln(
        '     => Neuen Hash in lib/utils/cert_pinning.dart '
        '(_pinnedByHost["$host"]) aufnehmen (alten zunächst behalten, '
        'siehe Pin-Rotation-Doku).',
      );
      if (issuerOk) {
        stdout.writeln(
          '     Hinweis: Issuer ist die erwartete CA – vermutlich '
          'reguläre Rotation, kein Angriff.',
        );
      } else {
        stdout.writeln(
          '     WARNUNG: Issuer ist NICHT die erwartete CA – '
          'manuelle Prüfung empfohlen!',
        );
      }
    }
  }

  stdout.writeln(
    mismatch
        ? '\nErgebnis: MINDESTENS EIN PIN AKTUALISIEREN (siehe oben).'
        : '\nErgebnis: Alle Pins aktuell.',
  );
  exit(mismatch ? 1 : 0);
}

bool _issuerKnown(String host, String issuer) {
  final i = issuer.toLowerCase();
  switch (host) {
    case 'jftuigjbmmuvrckbchqo.supabase.co':
      return i.contains('google trust services');
    case 'router.huggingface.co':
      return i.contains('amazon');
    default:
      return false;
  }
}
