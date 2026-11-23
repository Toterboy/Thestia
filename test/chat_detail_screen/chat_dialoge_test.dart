// Die Dialoge und Aktionen im Chat: der Anruf, das Date-Rad, der
// Hintergrund-Hinweis, die Sicherheitsnummer und die Mikrofon-Offenlegung.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/parts/chatdialoge.dart 86 offene Zeilen (54 %) -
// das ist der Dialog-Teil des Chats. Der Sicherheitsnummern-Dialog war
// dabei nie getestet: er wartet auf den Verschluesselungs-Dienst, und
// dessen Schluesselaufbau haengt im Test (echte Datei-Arbeit). Deshalb
// bekommt er hier einen Ersatz - genau so, wie der Anruf-Screen einen
// Ersatz fuer die Direktverbindung hat.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Anruf-Knopf oeffnet den Anruf-Screen (und nur einen),
//   * das Date-Rad laesst sich ausblenden - und bleibt ausgeblendet,
//   * der Quiz-Hinweis erscheint, wenn der Server den Chat sperrt,
//   * der Hinweis auf den Chat-Hintergrund laesst sich bestaetigen,
//   * die Sicherheitsnummer: der Hinweis erscheint, der Dialog zeigt die
//     Nummer, und die beiden Schalter merken sich ihr Ergebnis,
//   * die Mikrofon-Offenlegung kommt VOR der Aufnahme (Google Play).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// webrtc_interface kommt als Transitivum ueber flutter_webrtc - der Test
// braucht nur den DataChannel-Zustand.
// ignore_for_file: depend_on_referenced_packages
import 'package:webrtc_interface/webrtc_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/match.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/mood_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/services/server/mood_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

/// Der Verschluesselungs-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt seine Schluessel aus Hive und
/// rechnet daraus die Sicherheitsnummer - das ist echte Datei-Arbeit
/// und haengt im Test. Fuer den Dialog reichen die Zahlen: die
/// Sicherheitsnummer, der Bestaetigungsstand und die Schalter.
///
/// Der Test kann die Nummer setzen (null = "noch keine Sitzung") und
/// am Ende nachsehen, was der Nutzer angeklickt hat.
class _FakeVerschluesselung extends EncryptionService {
  _FakeVerschluesselung({this.nummer, this.zeigeHinweis = false});

  /// Die Sicherheitsnummer (null = keine Sitzung).
  final String? nummer;

  /// Soll der Hinweis auf die Sicherheitsnummer erscheinen?
  ///
  /// DER GRUND: Der Hinweis ist eine Snackbar mit einem langen Knopf
  /// ("Sicherheitsnummer (E2E-Verifikation)"). Im Test ist jeder Buchstabe
  /// breiter als in der echten Schrift - der Knopf passt dann nicht mehr
  /// neben dem Text und laeuft ueber. Deshalb ist der Hinweis hier
  /// ausgeschaltet (der Test schaltet ihn an, wenn es darum geht) - der
  /// Dialog selbst ist davon nicht betroffen.
  final bool zeigeHinweis;

  /// Wurde der Hinweis zu dieser Nummer schon gezeigt?
  final Set<String> hinweiseGezeigt = <String>{};

  /// Die als bestaetigt markierten Partner.
  final Set<String> bestaetigt = <String>{};

  /// Die Partner, bei denen die Bestaetigung verlangt wird.
  final Set<String> verlangt = <String>{};

  @override
  Future<void> get initialized => Future<void>.value();

  @override
  bool get bereit => true;

  @override
  String? safetyNumberFor(String peerId) => nummer;

  @override
  bool isPeerIdentityVerified(String peerId) => bestaetigt.contains(peerId);

  @override
  bool safetyHintShown(String peerId) =>
      !zeigeHinweis || hinweiseGezeigt.contains(peerId);

  @override
  Future<void> markSafetyHintShown(String peerId) async {
    hinweiseGezeigt.add(peerId);
  }

  @override
  bool requiresPeerVerification(String peerId) => verlangt.contains(peerId);

  @override
  Future<void> setRequiresPeerVerification(String peerId, bool value) async {
    if (value) {
      verlangt.add(peerId);
    } else {
      verlangt.remove(peerId);
    }
  }

  @override
  Future<void> setPeerIdentityVerified(String peerId, bool verified) async {
    if (verified) {
      bestaetigt.add(peerId);
    } else {
      bestaetigt.remove(peerId);
    }
  }
}

/// Der P2P-Dienst als Ersatz (der Anruf-Screen braucht ihn).
class _FakeP2P extends P2PChatService {
  _FakeP2P(super.webrtc, super.prekey);

  @override
  bool get isConnected => false;

  @override
  bool get isDataChannelOpen => false;

  @override
  Stream<Map<String, dynamic>> get callControl =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
  get callAudio =>
      const Stream<
        ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
      >.empty();

  /// DER KANAL-STATUS: Ohne diese Angabe wartet der Anruf-Screen bis
  /// zum Ablauf von zehn Sekunden auf einen offenen Kanal - dieser Timer
  /// stuende am Ende des Tests noch herum.
  @override
  Stream<RTCDataChannelState> get connectionState =>
      const Stream<RTCDataChannelState>.empty();

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {}
}

void main() {
  late FakeSupabaseServer server;
  late FakeLocalStorage speicher;
  late _FakeVerschluesselung verschluesselung;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    mockAufnahme();
    server = FakeSupabaseServer(userId: 'ich');
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

  setUp(() {
    server.rpcAntworten.clear();
    server.zeilen.clear();
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
    // DER SPEICHER: Er bleibt ueber die Tests hinweg derselbe - so
    // sieht der Test, was der Bildschirm wirklich gespeichert hat.
    speicher = FakeLocalStorage();
    verschluesselung = _FakeVerschluesselung(nummer: '1234 5678 9012 3456');
  });

  tearDown(() async {
    await moodClient.dispose();
  });

  /// Ein Chat mit [anzahl] Nachrichten.
  ({ChatNotifier notifier, Match match}) chatMitNachrichten({
    int anzahl = 2,
    bool alsServerFunke = false,
  }) {
    final service = ChatService();
    final partner = chatDetailScreenPartner();
    final match = alsServerFunke
        ? service.restoreServerMatch('7', partner, DateTime.now())!
        : service.createMatch(partner);
    for (var i = 0; i < anzahl; i++) {
      service.addMessage(
        match.id,
        Message(
          id: 'm_$i',
          senderId: i.isEven ? 'partner-1' : 'ich',
          receiverId: i.isEven ? 'ich' : 'partner-1',
          text: 'Nachricht $i',
          timestamp: DateTime.now(),
        ),
      );
    }
    return (notifier: ChatNotifier(service), match: match);
  }

  /// Baut den Chat-Bildschirm (mit Router - der Bildschirm navigiert).
  Future<void> baue(
    WidgetTester tester, {
    required Match match,
    required ChatNotifier notifier,
    bool hinweisGesehen = true,
    bool breit = false,
    List<Override> overrides = const <Override>[],
  }) async {
    // DER BILDSCHIRM: Gross genug, damit das komplette "mehr"-Menue
    // (viele Eintraege) auf einmal passt.
    //
    // DER BREITE SCHIRM: fuer die Snackbar mit dem langen Knopf (siehe
    // [_FakeVerschluesselung]) - im Test ist jeder Buchstabe breiter
    // als in der echten Schrift.
    await tester.binding.setSurfaceSize(
      breit ? const Size(1000, 1400) : const Size(430, 1400),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    if (hinweisGesehen) {
      speicher.saveString(
        AppConstants.prefsSettingsKey,
        jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
      );
    }

    final router = GoRouter(
      initialLocation: '/chat/${match.id}',
      routes: [
        GoRoute(
          path: '/chat/:matchId',
          builder: (ctx, state) =>
              ChatDetailScreen(matchId: state.pathParameters['matchId']!),
        ),
        GoRoute(
          path: '/interessen',
          builder: (ctx, state) => const Scaffold(body: Text('Interessen')),
        ),
        GoRoute(
          path: '/spice/:matchId',
          builder: (ctx, state) => const Scaffold(body: Text('Fragensammlung')),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (ctx, state) => const Scaffold(body: Text('Profil')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(speicher),
          secureProfileStoreProvider.overrideWithValue(
            FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              speicher,
              FakeSecureProfileStore(),
            );
            notifier.setProfile(eigenesProfil());
            return notifier;
          }),
          moodServiceProvider.overrideWithValue(MoodService(moodClient)),
          chatProvider.overrideWith((ref) => notifier),
          encryptionServiceProvider.overrideWithValue(verschluesselung),
          p2pChatServiceProvider.overrideWith(
            (ref) => _FakeP2P(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Das Zeitlimit der Edge-Function-Aufrufe (20 Sekunden) ablaufen
    // lassen: der Timer wuerde sonst als "pending timer" stehen bleiben.
    await tester.pump(const Duration(seconds: 21));
  }

  /// Oeffnet das "mehr"-Menue des Chats.
  Future<void> menueOeffnen(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt einen Menuepunkt an.
  Future<void> menuePunkt(WidgetTester tester, String key) async {
    final eintrag = find.text(L10n.tWithoutContext(key)).last;
    await tester.ensureVisible(eintrag);
    await tester.pump();
    await tester.tap(eintrag);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Der Anruf aus dem Chat', () {
    testWidgets('der Anruf-Knopf oeffnet den Anruf-Screen', (tester) async {
      final chat = chatMitNachrichten();

      await baue(tester, match: chat.match, notifier: chat.notifier);

      expect(find.byType(CallScreen), findsNothing);

      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(CallScreen),
        findsOneWidget,
        reason:
            'Der Anruf-Knopf muss den Anruf-Screen oeffnen - sonst passiert '
            'ueberhaupt nichts.',
      );
    });

    testWidgets('ein laufender Anruf blockiert den zweiten', (tester) async {
      final chat = chatMitNachrichten();

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        overrides: [
          activeCallIdProvider.overrideWith((ref) => 'laufender-anruf'),
        ],
      );

      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(CallScreen),
        findsNothing,
        reason:
            'Wer schon telefoniert, darf keinen zweiten Anruf starten - '
            'sonst stapeln sich die Bildschirme.',
      );
    });
  });

  group('Das Date-Rad', () {
    testWidgets('es laesst sich ausblenden und bleibt ausgeblendet', (
      tester,
    ) async {
      // DIE ANZAHL: Das Date-Rad erscheint erst nach 50-70 Nachrichten
      // (die Schwelle ist je Chat gestaffelt).
      final chat = chatMitNachrichten(anzahl: 70);

      await baue(tester, match: chat.match, notifier: chat.notifier);

      expect(
        find.text(L10n.tWithoutContext('chat.ideaWheelBtn')),
        findsOneWidget,
        reason: 'Nach vielen Nachrichten kommt der Vorschlag.',
      );

      // Der kleine Knopf neben dem Vorschlag blendet ihn aus.
      await tester.tap(find.byTooltip(L10n.tWithoutContext('chat.ideaHide')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('chat.ideaWheelBtn')),
        findsNothing,
        reason: 'Nach dem Ausblenden ist der Vorschlag weg.',
      );

      // UND ER BLEIBT WEG: Der Bildschirm merkt sich das im Speicher.
      await baue(tester, match: chat.match, notifier: chat.notifier);
      expect(
        find.text(L10n.tWithoutContext('chat.ideaWheelBtn')),
        findsNothing,
        reason:
            'Der Vorschlag darf nicht bei jedem Chat-Aufruf wiederkommen - '
            'der Nutzer hat ihn ja weggedrueckt.',
      );
    });
  });

  group('Das Quiz-Gate', () {
    testWidgets('der Server kann den Chat sperren', (tester) async {
      // DER SERVER: Ein Match aus "Find your Match", das das Quiz noch
      // nicht bestanden hat - genau das sperrt den Chat.
      server.rpcAntworten['get_match_quiz_state'] = <String, dynamic>{
        'matchId': 7,
        'partnerId': 'partner-1',
        'createdVia': 'find_match',
        'unlockLevel': 0,
      };
      final chat = chatMitNachrichten(anzahl: 70, alsServerFunke: true);

      await baue(tester, match: chat.match, notifier: chat.notifier);

      expect(
        find.text(L10n.tWithoutContext('chat.quizOpen')),
        findsOneWidget,
        reason:
            'Ist der Chat gesperrt, muss der Nutzer das Quiz sehen - '
            'sonst weiss er nicht, warum nichts geht.',
      );
    });
  });

  group('Der Hinweis auf den Chat-Hintergrund', () {
    testWidgets('"Fertig" bestaetigt den Hinweis', (tester) async {
      final chat = chatMitNachrichten();

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        hinweisGesehen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('chatbg.hintTitle')),
        findsOneWidget,
        reason: 'Der Hinweis kommt beim ersten Chat.',
      );

      await tester.tap(find.text(L10n.tWithoutContext('common.done')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('chatbg.hintDone')),
        findsOneWidget,
        reason:
            'Nach der Bestaetigung muss der Nutzer sehen, dass der '
            'Hintergrund gesetzt ist.',
      );
      expect(
        speicher.getString(AppConstants.prefsSettingsKey),
        isNotNull,
        reason: 'Der Hinweis wird gemerkt - er kommt sonst erneut.',
      );
    });
  });

  group('Die Sicherheitsnummer', () {
    testWidgets('der Hinweis erscheint beim ersten Kontakt', (tester) async {
      // DER HINWEIS AN: Die Snackbar mit dem Knopf braucht Platz (siehe
      // [_FakeVerschluesselung]).
      verschluesselung = _FakeVerschluesselung(
        nummer: '1234 5678 9012 3456',
        zeigeHinweis: true,
      );
      final chat = chatMitNachrichten();

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        breit: true,
      );

      expect(
        find.textContaining('Sicherheitsnummer'),
        findsWidgets,
        reason:
            'Der Hinweis muss erscheinen - er sagt dem Nutzer, dass er die '
            'Sicherheitsnummer pruefen soll.',
      );
      expect(
        verschluesselung.hinweiseGezeigt.contains('partner-1'),
        isTrue,
        reason:
            'Der Hinweis auf die Sicherheitsnummer wird gemerkt - er kommt '
            'sonst bei jedem Chat erneut.',
      );
    });

    testWidgets('der Knopf am Hinweis oeffnet den Dialog', (tester) async {
      verschluesselung = _FakeVerschluesselung(
        nummer: '1234 5678 9012 3456',
        zeigeHinweis: true,
      );
      final chat = chatMitNachrichten();

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        breit: true,
      );

      await tester.tap(
        find.text(L10n.tWithoutContext('chat.safetyNumberTooltip')).last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('1234 5678 9012 3456'),
        findsOneWidget,
        reason:
            'Der Knopf am Hinweis muss direkt zum Vergleich der Nummer '
            'führen.',
      );
    });

    testWidgets('der Dialog zeigt die Nummer und merkt die Schalter', (
      tester,
    ) async {
      final chat = chatMitNachrichten();

      await baue(tester, match: chat.match, notifier: chat.notifier);

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.safetyNumberTooltip');

      expect(
        find.text('1234 5678 9012 3456'),
        findsOneWidget,
        reason:
            'Die Nummer muss im Dialog stehen - sie wird am Telefon '
            'verglichen.',
      );

      // DER ERSTE SCHALTER: "Identität bestätigt".
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.identityVerifiedTitle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        verschluesselung.bestaetigt.contains('partner-1'),
        isTrue,
        reason:
            'Die Bestaetigung muss gespeichert werden - sonst waere der '
            'Schalter nur Dekoration.',
      );

      // DER ZWEITE SCHALTER: "Bestätigung verlangen".
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.requireVerifiedTitle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        verschluesselung.verlangt.contains('partner-1'),
        isTrue,
        reason:
            'Wer die Bestaetigung verlangt, muss sie auch durchsetzen - '
            'sonst ist der Schalter nutzlos.',
      );

      await tester.tap(find.text(L10n.tWithoutContext('chat.close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ohne Sitzung sagt der Dialog das', (tester) async {
      // KEINE SITZUNG: Dann gibt es keine Nummer - der Dialog muss das
      // sagen, statt eine leere Seite zu zeigen.
      verschluesselung = _FakeVerschluesselung();
      final chat = chatMitNachrichten();

      await baue(tester, match: chat.match, notifier: chat.notifier);

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.safetyNumberTooltip');

      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason: 'Der Dialog nennt den Partner.',
      );
      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason:
            'Ohne Nummer gibt es nichts zu vergleichen - die Schalter '
            'waeren dann irrefuehrend.',
      );
    });
  });

  group('Die Mikrofon-Offenlegung', () {
    testWidgets('sie kommt vor der Aufnahme', (tester) async {
      final chat = chatMitNachrichten();

      await baue(tester, match: chat.match, notifier: chat.notifier);

      // DER AUFNAHME-KNOPF: Das Mikrofon neben der Eingabeleiste.
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('chat.micDisclosureTitle')),
        findsOneWidget,
        reason:
            'Die App muss erklaeren, WARUM sie aufnimmt, BEVOR der '
            'Systemdialog kommt - das verlangt Google Play.',
      );
    });

    testWidgets('nach der Zustimmung wird aufgenommen', (tester) async {
      final chat = chatMitNachrichten();

      await baue(tester, match: chat.match, notifier: chat.notifier);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(
        find.text(L10n.tWithoutContext('chat.micDisclosureAccept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byTooltip(L10n.tWithoutContext('chat.voiceStopSend')),
        findsOneWidget,
        reason:
            'Nach der Zustimmung muss die Aufnahme laufen - der Knopf wird '
            'zum Stopp-Knopf.',
      );
    });
  });
}
