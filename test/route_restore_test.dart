import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/routing/route_restore.dart';

void main() {
  group('isRestorableRoute', () {
    test('Haupt-Tabs sind wiederherstellbar', () {
      expect(isRestorableRoute('/'), isTrue);
      expect(isRestorableRoute('/interessen'), isTrue);
      expect(isRestorableRoute('/profile'), isTrue);
      expect(isRestorableRoute('/find-your-match'), isTrue);
      expect(isRestorableRoute('/swipe-mode-selection'), isTrue);
      expect(isRestorableRoute('/transit/radar'), isTrue);
      expect(isRestorableRoute('/random-chat'), isTrue);
    });

    test('Chat-Detailrouten sind wiederherstellbar', () {
      expect(isRestorableRoute('/chat/123'), isTrue);
      expect(isRestorableRoute('/chat/abc-def'), isTrue);
    });

    test('fremde Profilseiten sind wiederherstellbar, Edit nicht', () {
      expect(isRestorableRoute('/profile/abc-123'), isTrue);
      expect(isRestorableRoute('/profile/edit'), isFalse);
    });

    test('Setup/Auth/transiente Routen sind NICHT wiederherstellbar', () {
      expect(isRestorableRoute(''), isFalse);
      expect(isRestorableRoute('/login'), isFalse);
      expect(isRestorableRoute('/chat/'), isFalse);
      expect(isRestorableRoute('/quiz/1'), isFalse);
      expect(isRestorableRoute('/spice/1'), isFalse);
      expect(isRestorableRoute('/dating-hour/chat/1'), isFalse);
      expect(isRestorableRoute('/settings'), isFalse);
      expect(isRestorableRoute('/admin'), isFalse);
    });
  });

  group('Pending-Restore (einmalig verbrauchbar)', () {
    test('setzen, holen, danach leer', () {
      setPendingRouteRestore('/chat/42');
      expect(consumePendingRouteRestore(), '/chat/42');
      // Einmalig: zweiter Konsum liefert null.
      expect(consumePendingRouteRestore(), isNull);
    });

    test('null setzen bleibt null', () {
      setPendingRouteRestore(null);
      expect(consumePendingRouteRestore(), isNull);
    });

    test('neuer Wert überschreibt alten', () {
      setPendingRouteRestore('/chat/1');
      setPendingRouteRestore('/interessen');
      expect(consumePendingRouteRestore(), '/interessen');
      expect(consumePendingRouteRestore(), isNull);
    });
  });
}
