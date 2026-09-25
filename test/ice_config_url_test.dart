import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/webrtc_service.dart';

/// Regressionstest für den ice-config-401-Bug (Server-Log-Beweis):
/// Die URL wurde aus `client.rest.url` (= Basis plus Rest-Pfad) durch
/// reines Anhängen gebaut und landete bei einem PostgREST-Pfad ->
/// 401 vom Gateway, ohne je die Function zu erreichen. Dieser Test ruft
/// die ECHTE Ableitungsmethode auf (keine Kopie der Logik): Bricht der
/// Produktcode, wird der Test rot.
void main() {
  group('ice-config Basis-URL-Ableitung (echte Methode)', () {
    test('strippt das /rest/v1-Suffix', () {
      expect(
        WebRTCService.deriveFunctionBaseUrl(
            'https://jftuigjbmmuvrckbchqo.supabase.co/rest/v1'),
        'https://jftuigjbmmuvrckbchqo.supabase.co',
      );
    });

    test('verkettete URL trifft den Function-Pfad', () {
      final base = WebRTCService.deriveFunctionBaseUrl(
          'https://abc.supabase.co/rest/v1');
      expect('$base/functions/v1/ice-config',
          'https://abc.supabase.co/functions/v1/ice-config');
      expect(
        '$base/functions/v1/ice-config',
        isNot(contains('/rest/v1/functions')),
      );
    });

    test('lässt Fremd-URLs unangetastet', () {
      expect(WebRTCService.deriveFunctionBaseUrl('https://example.com/api'),
          'https://example.com/api');
    });
  });
}
