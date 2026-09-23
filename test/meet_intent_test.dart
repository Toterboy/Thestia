import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/models/meet_intent.dart';

void main() {
  group('MeetIntent.bothWant', () {
    test('nur bei beidseitiger Zustimmung wahr', () {
      const base = MeetIntent(
        matchId: '1',
        eligible: true,
        myWants: false,
        partnerWants: false,
        metConfirmed: false,
      );
      expect(base.bothWant, isFalse);
      expect(
        const MeetIntent(
          matchId: '1',
          eligible: true,
          myWants: true,
          partnerWants: false,
          metConfirmed: false,
        ).bothWant,
        isFalse,
      );
      expect(
        const MeetIntent(
          matchId: '1',
          eligible: true,
          myWants: false,
          partnerWants: true,
          metConfirmed: false,
        ).bothWant,
        isFalse,
      );
      expect(
        const MeetIntent(
          matchId: '1',
          eligible: true,
          myWants: true,
          partnerWants: true,
          metConfirmed: false,
        ).bothWant,
        isTrue,
      );
    });
  });

  group('MeetIntent.fromJson', () {
    test('parst alle Felder, matchId als Zahl oder String', () {
      final intent = MeetIntent.fromJson({
        'matchId': 42,
        'eligible': true,
        'myWants': true,
        'partnerWants': false,
        'metConfirmed': false,
      });
      expect(intent.matchId, '42');
      expect(intent.eligible, isTrue);
      expect(intent.myWants, isTrue);
      expect(intent.partnerWants, isFalse);
      expect(intent.metConfirmed, isFalse);
      expect(intent.bothWant, isFalse);
    });

    test('fehlende Felder fallen auf sichere Defaults zurück', () {
      final intent = MeetIntent.fromJson({'matchId': 7});
      expect(intent.matchId, '7');
      expect(intent.eligible, isFalse);
      expect(intent.myWants, isFalse);
      expect(intent.partnerWants, isFalse);
      expect(intent.metConfirmed, isFalse);
      expect(intent.bothWant, isFalse);
    });
  });
}
