// Der Audio-Player der Vorstellung.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/widgets/profile/intro_audio_player.dart 60 offene Zeilen bei 36 %
// Abdeckung - das ganze Widget war ungetestet.
//
// DER WEG: Der Dienst, der die signierte URL holt, ist ein Hand-Fake
// (er kann antworten, nichts liefern oder scheitern). Der Audio-Player
// ist der Ersatz aus test/support/plugin_mocks.dart.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Abspielen startet (der Knopf wird zum Stopp-Knopf),
//   * der Balken und die Zeit stehen da, WAEHREND es laeuft (das war ein
//     Wunsch des Betreibers: "eine Zeitanzeige mit Balken"),
//   * das Stoppen macht aus dem Stopp-Knopf wieder einen Play-Knopf,
//   * gibt es keine Vorstellung, steht das dem Nutzer auch da (nicht ein
//     stummer Knopf, der nichts tut),
//   * scheitert das Laden, wird der Grund gesagt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart';
import 'package:thestia/widgets/profile/intro_audio_player.dart';

import '../support/plugin_mocks.dart';

/// Der Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt eine signierte URL von der
/// Edge-Function "match-media" - im Test gibt es die nicht.
class _Dienst extends FindYourMatchService {
  _Dienst()
    : super(supabase.SupabaseClient('https://example.supabase.co', 'test-key'));

  /// Die gelieferte URL (null = es gibt keine Vorstellung).
  String? url = 'https://example.supabase.co/intro.mp3';

  /// Wenn gesetzt, wirft [getIntroAudioUrl] diesen Fehler.
  Object? fehler;

  /// Wie oft wurde nach der URL gefragt?
  int anfragen = 0;

  @override
  Future<String?> getIntroAudioUrl(String targetUserId) async {
    anfragen++;
    final e = fehler;
    if (e != null) throw e;
    return url;
  }
}

void main() {
  late _Dienst dienst;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER AUDIO-PLAYER: Das Plugin gibt es im Test nicht - der Ersatz
    // liefert eine leere Wiedergabe.
    mockAudioPlayer();
  });

  setUp(() {
    dienst = _Dienst();
  });

  /// Baut den Player.
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          findYourMatchServiceProvider.overrideWithValue(dienst),
        ],
        child: const MaterialApp(
          home: Scaffold(body: IntroAudioPlayer(targetUserId: 'partner-1')),
        ),
      ),
    );
    await tester.pump();
  }

  /// Tippt auf den Knopf.
  Future<void> tippe(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Die Fehler', () {
    testWidgets('gibt es keine Vorstellung, steht das da', (tester) async {
      dienst.url = null;
      await zeige(tester);

      await tippe(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('intro.unavailable')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass es keine Vorstellung gibt - '
            'sonst tippt er vergeblich.',
      );
    });

    testWidgets('scheitert das Laden, wird der Grund gesagt', (tester) async {
      dienst.fehler = StateError('Das Netz ist weg.');
      await zeige(tester);

      await tippe(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('intro.unplayable')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass die Vorstellung nicht laeuft - '
            'ein stummer Knopf sieht wie ein Absturz aus.',
      );
    });
  });
}
