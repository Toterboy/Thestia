import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/webrtc_service.dart';

/// Tests fuer die P2P-Diagnose im Release-Build.
///
/// WARUM (06.11.2026): Die internen Meldungen des WebRTC-Service gingen
/// nur in den Debug-Log (debugPrint). Der Betreiber testet aber den
/// Store-Build - dort war nicht zu sehen, WORAN der P2P-Aufbau
/// scheiterte. Die Probleme gehen jetzt ueber einen Stream und stehen
/// in der Diagnosezeile des Chats.
///
/// ZWEI DINGE MUESSEN STIMMEN:
///   1) Ein internes Problem kommt beim Aufrufer an.
///   2) Der Text enthaelt KEINE personenbezogenen Daten - er landet
///      in der Oberflaeche.
void main() {
  group('Die P2P-Probleme', () {
    test('ein internes Problem kommt beim Aufrufer an', () async {
      final service = WebRTCService(EncryptionService());
      final probleme = <String>[];
      final abo = service.problems.listen(probleme.add);
      addTearDown(abo.cancel);

      // Eine Answer ohne PeerConnection - genau der Fall, der vorher
      // stillschweigend unterging.
      await service.handleAnswer('peer-1', 'v=0');
      await Future<void>.delayed(Duration.zero);

      expect(
        probleme,
        isNotEmpty,
        reason:
            'das Problem kam nicht an - im Release-Build waere die '
            'Ursache wieder unsichtbar',
      );
      expect(probleme.first, contains('Antwort'));
    });

    test('der Text enthaelt keine User-ID', () async {
      final service = WebRTCService(EncryptionService());
      final probleme = <String>[];
      final abo = service.problems.listen(probleme.add);
      addTearDown(abo.cancel);

      await service.handleAnswer('11111111-1111-4111-8111-111111111111', 'v=0');
      await Future<void>.delayed(Duration.zero);

      for (final problem in probleme) {
        expect(
          problem.contains('11111111-1111-4111-8111-111111111111'),
          isFalse,
          reason: 'der Text nennt die User-ID - er landet in der Oberflaeche',
        );
      }
    });

    test('die Meldung nennt den Fehlertyp, nicht den Fehlertext', () async {
      // Der Fehlertext koennte eine User-ID enthalten (z. B. "user
      // 11111111-... not found"). Deshalb wird er weggelassen.
      final service = WebRTCService(EncryptionService());
      final probleme = <String>[];
      final abo = service.problems.listen(probleme.add);
      addTearDown(abo.cancel);

      await service.handleAnswer('peer-1', 'v=0');
      await Future<void>.delayed(Duration.zero);

      expect(probleme.first, isNot(contains('v=0')));
    });
  });
}
