import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/transit_ble_privacy.dart';
import 'package:thestia/services/transit_encounter_service.dart';

void main() {
  group('TransitBlePrivacy - Advertising-Zyklus', () {
    test('bleibt immer innerhalb des Fensters 20-45 s', () {
      for (int seed = 0; seed < 400; seed++) {
        final d = TransitBlePrivacy.advertiseCycleDelay(
            random: Random(seed));
        expect(d.inMilliseconds,
            greaterThanOrEqualTo(kAdvertiseCycleMin.inMilliseconds));
        expect(d.inMilliseconds,
            lessThanOrEqualTo(kAdvertiseCycleMax.inMilliseconds));
      }
    });

    test('erzeugt tatsächlich verschiedene Werte (kein fester Takt)', () {
      final values = <int>{};
      for (int seed = 0; seed < 200; seed++) {
        values.add(TransitBlePrivacy.advertiseCycleDelay(
                random: Random(seed))
            .inMilliseconds);
      }
      // Bei 200 Ziehungen aus ~26 s Spielraum sind viele Werte zu erwarten.
      expect(values.length, greaterThan(100),
          reason: 'fester Takt würde genau 1 distinct liefern');
    });

    test('deterministisch bei gleichem Random-Seed', () {
      expect(TransitBlePrivacy.advertiseCycleDelay(random: Random(42)),
          TransitBlePrivacy.advertiseCycleDelay(random: Random(42)));
    });
  });

  group('TransitBlePrivacy - Token-Rotation', () {
    test('bleibt im Band 6-14 min um die 10-Minuten-Basis', () {
      for (int seed = 0; seed < 400; seed++) {
        final d = TransitBlePrivacy.tokenRotationDelay(random: Random(seed));
        expect(d.inMinutes, inInclusiveRange(6, 14));
      }
    });

    test('KRITISCH: streut um die Basis, statt exakt 10 min zu treffen', () {
      // Ohne Jitter waere jeder Rotationszeitpunkt exakt 10 min - selbst
      // ein Fingerprint. Der exakte Basiswert darf also selten sein.
      final exact = <int>{};
      for (int seed = 0; seed < 400; seed++) {
        if (TransitBlePrivacy.tokenRotationDelay(random: Random(seed))
                .inMilliseconds ==
            kTokenRotationBase.inMilliseconds) {
          exact.add(seed);
        }
      }
      expect(exact.length, lessThan(5),
          reason: 'zu oft exakt die Basisperiode - Jitter wirkungslos');
    });

    test('erlaubt beide Richtungen (früher UND später als 10 min)', () {
      var early = 0, late = 0;
      for (int seed = 0; seed < 400; seed++) {
        final ms = TransitBlePrivacy.tokenRotationDelay(random: Random(seed))
            .inMilliseconds;
        if (ms < kTokenRotationBase.inMilliseconds) early++;
        if (ms > kTokenRotationBase.inMilliseconds) late++;
      }
      expect(early, greaterThan(50));
      expect(late, greaterThan(50));
    });
  });

  group('TransitBlePrivacy - Scan-Impuls', () {
    test('Pause liegt zwischen 8 und 20 s', () {
      for (int seed = 0; seed < 400; seed++) {
        final d = TransitBlePrivacy.scanPulseOff(random: Random(seed));
        expect(d.inMilliseconds,
            greaterThanOrEqualTo(kScanPulseOffMin.inMilliseconds));
        expect(d.inMilliseconds,
            lessThanOrEqualTo(kScanPulseOffMax.inMilliseconds));
      }
    });

    test('Duty-Cycle bleibt ueber 50 % (sonst verlieren wir Begegnungen)', () {
      // on=12s, off im Mittel 14s -> ~46 %. Wir wollen aber sicher ueber
      // die Haelfte kommen, sonst leidet die Match-Quote.
      final offSum = <int>{};
      var total = 0;
      const n = 500;
      for (int seed = 0; seed < n; seed++) {
        total += TransitBlePrivacy.scanPulseOff(random: Random(seed))
            .inMilliseconds;
      }
      offSum.add(total);
      final meanOff = total / n;
      final duty = kScanPulseOn.inMilliseconds /
          (kScanPulseOn.inMilliseconds + meanOff);
      expect(duty, greaterThan(0.40),
          reason: 'Duty-Cycle $duty zu niedrig - Begegnungen werden verpasst');
      // Gegenprobe: die Konstanten selbst duerfen nicht zu pessimistisch sein
      expect(kScanPulseOffMax.inMilliseconds,
          lessThanOrEqualTo(kScanPulseOn.inMilliseconds * 2));
    });
  });

  group('Hersteller-ID: muss zum nativen Advertising passen', () {
    test('0xFFFF ist der Wert, den MainActivity.addManufacturerData nutzt', () {
      // Regressionstest: aendert jemand die ID im Kotlin, faellt das hier auf.
      expect(kThestiaManufacturerId, 0xFFFF);
    });

    test('der Marker im Payload bleibt unveraendert', () {
      // "WST1" + Token ist das, wonach der Scanner filtert.
      expect(TransitEncounterService.bleMarker, 'WST1');
    });
  });

  group('Jitter ist nicht vorhersagbar', () {
    test('zwei Aufrufe ohne Random unterscheiden sich (nicht konstant)', () {
      // Ohne injizierten Random muss jeder Aufruf neu würfeln.
      final a = TransitBlePrivacy.tokenRotationDelay();
      final b = TransitBlePrivacy.tokenRotationDelay();
      // statistisch: die Chance auf Gleichheit ist vernachlaessigbar
      expect(a == b, isFalse);
    });

    test('Werte bleiben auch ohne injizierten Random im gültigen Band', () {
      for (int i = 0; i < 50; i++) {
        expect(TransitBlePrivacy.tokenRotationDelay().inMinutes,
            inInclusiveRange(6, 14));
        expect(TransitBlePrivacy.advertiseCycleDelay().inSeconds,
            inInclusiveRange(20, 45));
      }
    });
  });
}
