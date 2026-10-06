import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/global_relay_inbox.dart';
import 'package:thestia/services/relay_poll_backoff.dart';

void main() {
  group('RelayPollBackoff', () {
    test('startet im 6-Sekunden-Takt', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      expect(b.step, 0);
      expect(b.next, const Duration(seconds: 6));
    });

    test('Leerfall streckt bis zum Deckel', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      b.onEmpty();
      expect(b.next, const Duration(seconds: 12));
      b.onEmpty();
      expect(b.next, const Duration(seconds: 25));
      b.onEmpty();
      expect(b.next, const Duration(seconds: 45));
      // Deckel: weiterer Leerfall bewegt nichts mehr.
      b.onEmpty();
      expect(b.next, const Duration(seconds: 45));
    });

    test('Fehlerfall streckt genauso wie der Leerfall', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      b.onFailure();
      expect(b.next, const Duration(seconds: 12));
      b.onFailure();
      expect(b.next, const Duration(seconds: 25));
      b.onFailure();
      expect(b.next, const Duration(seconds: 45));
    });

    test('Zustellung geht sofort zurueck auf 6 s', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      b.onEmpty();
      b.onEmpty();
      b.onEmpty();
      expect(b.next, const Duration(seconds: 45));
      b.onDelivered();
      expect(b.step, 0);
      expect(b.next, const Duration(seconds: 6));
    });

    test('reset() verhaelt sich wie onDelivered', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      b.onFailure();
      b.onFailure();
      b.reset();
      expect(b.next, const Duration(seconds: 6));
    });

    test('Jitter haelt +/-20 Prozent ein und streut', () {
      final b = RelayPollBackoff(random: Random(42));
      final seen = <int>{};
      for (var i = 0; i < 200; i++) {
        final ms = b.next.inMilliseconds;
        expect(ms, inInclusiveRange(4800, 7200));
        seen.add(ms);
      }
      // Kein Stufen-Deckel: die Werte muessen sich wirklich unterscheiden,
      // sonst wachen alle Clients im Gleichtakt auf.
      expect(seen.length, greaterThan(50));
    });

    test('Jitter 0 liefert exakte Intervalle', () {
      final b = RelayPollBackoff(jitterFraction: 0);
      for (var i = 0; i < 10; i++) {
        expect(b.next, const Duration(seconds: 6));
      }
    });

    test('eigene Leiter wird respektiert', () {
      final b = RelayPollBackoff(
        ladder: const [Duration(seconds: 2), Duration(seconds: 3)],
        jitterFraction: 0,
      );
      expect(b.baseInterval, const Duration(seconds: 2));
      b.onEmpty();
      expect(b.next, const Duration(seconds: 3));
      b.onEmpty();
      expect(b.next, const Duration(seconds: 3));
    });

    test('Gegenprobe: Fehlerfall OHNE onFailure bleibt im 6-s-Takt', () {
      // Haelt fest, dass genau dieser Aufruf die Dauerlast behebt.
      // Fehlt er, bleibt der Step 0 und der Poll wieder 6 s.
      final b = RelayPollBackoff(jitterFraction: 0);
      for (var i = 0; i < 5; i++) {
        b.onFailure();
      }
      expect(b.step, greaterThan(0));
      expect(b.next, greaterThan(const Duration(seconds: 6)));
    });
  });

  // Ohne diese Gruppe waere die obige Klasse gruen, obwohl der Fehlerpfad
  // in GlobalRelayInbox._tick kaputt ist - die Klasse kannte den Aufruf
  // gar nicht. Genau dieser Test ist beim Weglassen von
  // `_backoff.onFailure()` fehlgeschlagen.
  group('GlobalRelayInbox Fehlerpfad', () {
    test('fehlgeschlagener Poll streckt das Intervall', () async {
      final inbox = GlobalRelayInbox(_FakeRef());
      expect(inbox.debugBackoffStep, 0);
      final step = await inbox.debugPollOnce(
        pending: const [],
        throwBeforeHandling: true,
      );
      expect(step, 1, reason: 'Fehler muss den Backoff genau so strecken '
          'wie ein leerer Poll');
    });

    test('fuenf Fehlversuche landen bei Stufe 3 (45 s)', () async {
      final inbox = GlobalRelayInbox(_FakeRef());
      var step = 0;
      for (var i = 0; i < 5; i++) {
        step = await inbox.debugPollOnce(
          pending: const [],
          throwBeforeHandling: true,
        );
      }
      expect(step, 3);
    });

    test('Leerfall und Fehlerfall sind gleichwertig', () async {
      final leer = GlobalRelayInbox(_FakeRef());
      final fehler = GlobalRelayInbox(_FakeRef());
      await leer.debugPollOnce(pending: const []);
      await fehler.debugPollOnce(
        pending: const [],
        throwBeforeHandling: true,
      );
      expect(leer.debugBackoffStep, fehler.debugBackoffStep);
      expect(fehler.debugBackoffStep, 1);
    });
  });
}

/// Minimales Ref-Attribut: der Fehler-/Leerfall braucht keinen Provider-
/// Zugriff, weil der Wurf VOR dem Routing passiert.
class _FakeRef {
  // ignore: unused_field
  final Object? _marker = null;
}
