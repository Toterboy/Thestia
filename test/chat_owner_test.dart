import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/chat_service.dart';

/// Tests für die Kontowechsel-Trennung (Audit: Setup/Verifizierung des
/// Vorgängers leckten in neue Konten): Persistente Boxen sind pro
/// Konto namespaced, In-Memory-State wird beim Wechsel geleert.
void main() {
  group('ChatService Box-Namensräume', () {
    test('ohne Besitzer gelten die Legacy-Namen', () {
      expect(ChatService.historyBoxNameFor(null), 'chat_history');
      expect(ChatService.qrBoxNameFor(null), 'qr_contacts');
    });

    test('gleicher Besitzer, gleiche Box (Stabilität)', () {
      expect(
        ChatService.historyBoxNameFor('userA'),
        ChatService.historyBoxNameFor('userA'),
      );
      expect(
        ChatService.qrBoxNameFor('userA'),
        ChatService.qrBoxNameFor('userA'),
      );
    });

    test('verschiedene Besitzer, verschiedene Boxen (Trennung)', () {
      expect(
        ChatService.historyBoxNameFor('userA') !=
            ChatService.historyBoxNameFor('userB'),
        isTrue,
        reason: 'Verlauf von A darf für B unsichtbar sein',
      );
      expect(
        ChatService.qrBoxNameFor('userA') !=
            ChatService.qrBoxNameFor('userB'),
        isTrue,
        reason: 'QR-Kontakte von A dürfen für B unsichtbar sein',
      );
    });

    test('Namensraum enthält die User-ID (keine Kollision)', () {
      expect(ChatService.historyBoxNameFor('userA'), contains('userA'));
      expect(ChatService.qrBoxNameFor('userA'), contains('userA'));
    });
  });
}
