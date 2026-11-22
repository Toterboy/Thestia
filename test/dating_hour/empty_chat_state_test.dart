// Der Leer-Chat-Zustand darf nie ueberlaufen.
//
// BEFUND (22.11.2026, Fuzzing): Der Leer-Zustand ist 228 Pixel hoch.
// Ist der Chatbereich kleiner - im Entscheidungsfenster des Dating
// Hours stehen unten die Frage-Chips, das Eingabefeld UND die
// Entscheidungs-Knoepfe -, lief der Inhalt aus dem Bild:
// "A RenderFlex overflowed by 48 pixels".
//
// DER TEST: Ein kleiner Bildschirm muss scrollen, nicht ueberlaufen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/screens/dating_hour/dating_hour_chat_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockHive();
    mockZeitzone();
    mockAufnahme();
    mockPackageInfo();
    final server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  /// Baut den Bildschirm auf einer kleinen Flaeche.
  Future<void> zeige(WidgetTester tester, Size flaeche) async {
    await tester.binding.setSurfaceSize(flaeche);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(TestSpeicher()),
        secureProfileStoreProvider.overrideWithValue(TestKeystore()),
        settingsProvider.overrideWith((ref) => TestEinstellungen(ref)),
        profileProvider.overrideWith((ref) => TestProfil()),
        chatProvider.overrideWith((ref) => ChatNotifier(ChatService())),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DatingHourChatScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('der Leer-Chat laeuft bei kleinem Bildschirm nicht ueber', (
    tester,
  ) async {
    // So klein, dass der Leer-Zustand (228 px) NICHT passt.
    await zeige(tester, const Size(390, 300));

    expect(
      tester.takeException(),
      isNull,
      reason:
          'Der Leer-Chat darf auf einem kleinen Bildschirm nicht '
          'ueberlaufen - er muss scrollen.',
    );
  });

  testWidgets('der Leer-Chat laeuft bei normaler Groesse nicht ueber', (
    tester,
  ) async {
    await zeige(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);
  });
}
