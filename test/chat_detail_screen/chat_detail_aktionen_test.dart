// Die Aktionen im Chat: Kontext-Eisbrecher, Ideen-Rad, Funke beenden.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/parts/chateisbrecher.dart 93 offene Zeilen (43 %) und
// für die Teile meetideawheeldialog.dart und chatdetailaufbau.dart noch
// mehr. Das sind genau die drei Wege, mit denen man in einem leeren Chat
// ins Gespräch kommt - sie gehören getestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Kontext-Eisbrecher erscheint nur bei gemeinsamen Interessen und
//     schickt dann auch wirklich eine Nachricht,
//   * das Ideen-Rad erscheint erst nach vielen Nachrichten, dreht und
//     lässt sich als Vorschlag senden,
//   * die Eisbrecher-Sammlung und die Erinnerungsliste melden klar, wenn
//     sie im lokalen Kontakt (QR) nicht zur Verfügung stehen,
//   * das Beenden des Funkens fragt nach und sendet den Absage-Text.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/signal/signal_key_models.dart';
import 'package:thestia/models/chat/match.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/mood_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/server/mood_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    // DIE ADAPTER: Der Verschlüsselungs-Dienst (Sicherheitsnummer) liest
    // seine Boxen aus Hive - ohne die angemeldeten Adapter kann er sie
    // nicht öffnen.
    Hive.registerAdapter(SignalIdentityKeyPairAdapterAdapter());
    Hive.registerAdapter(SignalPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSignedPreKeyRecordAdapterAdapter());
    Hive.registerAdapter(SignalSessionRecordAdapterAdapter());
    Hive.registerAdapter(SignalSenderKeyRecordAdapterAdapter());
    Hive.registerAdapter(EncryptedMessageAdapterAdapter());
    Hive.registerAdapter(SignalIdentityKeyStoreAdapterAdapter());
    mockAufnahme();
    mockZeitzone();
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
    // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
    // Client schlägt der Aufbau fehl.
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
  });

  tearDown(() async {
    await moodClient.dispose();
  });

  /// Ein Chat mit [anzahl] Nachrichten.
  ///
  /// DER GRUND FÜR DIE ANZAHL: Das Ideen-Rad erscheint erst nach 50-70
  /// Nachrichten (die Schwelle ist je Chat gestaffelt) - ohne viele
  /// Nachrichten gibt es den Knopf gar nicht.
  ({ChatNotifier notifier, Match match}) chatMitNachrichten({
    int anzahl = 1,
    List<String> partnerInteressen = const <String>['Musik'],
    bool alsServerFunke = false,
    int? partnerAlter,
  }) {
    final service = ChatService();
    final partner = UserProfile(
      id: 'partner-1',
      name: 'Mira',
      bio: '',
      birthDate: partnerAlter == null
          ? DateTime.now().subtract(const Duration(days: 24 * 365))
          : DateTime.now().subtract(Duration(days: partnerAlter * 365)),
      interests: partnerInteressen,
    );
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

  /// Das eigene Profil (mit Interessen für den Kontext-Eisbrecher).
  ///
  /// [alter] setzt das eigene Alter - der Altersdifferenz-Hinweis
  /// braucht beide Alter.
  UserProfile ich(List<String> interessen, {int? alter}) => UserProfile(
    id: 'ich',
    name: 'Lena',
    bio: 'Hallo',
    birthDate: alter == null
        ? DateTime(1995, 6, 1)
        : DateTime.now().subtract(Duration(days: alter * 365)),
    interests: interessen,
  );

  /// Baut den Chat-Bildschirm (mit Router - der Bildschirm navigiert).
  Future<void> baue(
    WidgetTester tester, {
    required Match match,
    required ChatNotifier notifier,
    required UserProfile profil,
    bool hinweisGesehen = true,
  }) async {
    // DER BILDSCHIRM: Groß genug, damit das komplette "mehr"-Menü
    // (viele Einträge) auf einmal passt - sonst liegt der letzte
    // Eintrag außerhalb des Bildschirms.
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = FakeLocalStorage();
    // Der Hinweis auf den Chat-Hintergrund kommt beim ersten Chat - im
    // Test stört er nur, also ist er als "gesehen" markiert.
    if (hinweisGesehen) {
      storage.saveString(
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
        // DIE PLATZHALTER: Der Bildschirm navigiert nach "/interessen"
        // (beim Beenden oder Blockieren), zu den Fragensammlungen und
        // zum Profil. Der Test braucht nur, dass die Navigation klappt.
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
        GoRoute(
          path: '/safety-center',
          builder: (ctx, state) =>
              const Scaffold(body: Text('Sicherheitscenter')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(storage, FakeSecureProfileStore());
            notifier.setProfile(profil);
            return notifier;
          }),
          moodServiceProvider.overrideWithValue(MoodService(moodClient)),
          chatProvider.overrideWith((ref) => notifier),
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
    // lassen: im Test antwortet der Server auf einen Functions-Aufruf
    // nicht, der Timer des Zeitlimits bliebe sonst stehen und der Test
    // scheiterte an "a Timer is still pending".
    await tester.pump(const Duration(seconds: 21));
  }

  /// Öffnet das "mehr"-Menü des Chats.
  Future<void> menueOeffnen(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt einen Menüpunkt an.
  Future<void> menuePunkt(WidgetTester tester, String key) async {
    final eintrag = find.text(L10n.tWithoutContext(key)).last;
    // DER MENÜPUNKT IST LANG: Das Menü hat viele Einträge - bei
    // kleiner Bildschirmhöhe liegt der letzte Punkt außerhalb. Ohne
    // Heranschieben tappt der Test ins Leere.
    await tester.ensureVisible(eintrag);
    await tester.pump();
    await tester.tap(eintrag);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Der Kontext-Eisbrecher', () {
    testWidgets('das Chip erscheint bei gemeinsamen Interessen', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>['Musik', 'Klettern']),
      );

      expect(
        find.textContaining('Gemeinsam:'),
        findsOneWidget,
        reason:
            'Bei einem gemeinsamen Interesse soll der Nutzer einen '
            'Gesprächseinstieg bekommen - das Chip ist der Einstieg.',
      );
    });

    testWidgets('ohne gemeinsame Interessen erscheint kein Chip', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>['Fotografieren']),
      );

      expect(
        find.textContaining('Gemeinsam:'),
        findsNothing,
        reason:
            'Ohne gemeinsames Interesse waere der Vorschlag erfunden - der '
            'Nutzer wuerde sich auf etwas angesprochen fuehlen, das es '
            'nicht gibt.',
      );
    });

    testWidgets('das Chip schickt die Nachricht', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>['Musik']),
      );

      await tester.tap(find.textContaining('Gemeinsam:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.textContaining('Musik'),
        findsWidgets,
        reason:
            'Der Vorschlag soll nicht nur dastehen - er muss als Nachricht '
            'in den Chat gehen.',
      );
    });
  });

  group('Das Ideen-Rad', () {
    testWidgets('der Knopf erscheint erst nach vielen Nachrichten', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 3);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      expect(
        find.text(L10n.tWithoutContext('chat.ideaWheelBtn')),
        findsNothing,
        reason:
            'In einem frischen Chat wuerde das Date-Rad nur stoeren - es '
            'kommt erst, wenn es etwas zu planen gibt.',
      );
    });

    testWidgets('der Knopf erscheint bei vielen Nachrichten', (tester) async {
      final chat = chatMitNachrichten(anzahl: 80);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      expect(find.text(L10n.tWithoutContext('chat.ideaWheelBtn')), findsOne);
    });

    testWidgets('das Rad dreht und der Vorschlag laesst sich senden', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 80);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await tester.tap(find.text(L10n.tWithoutContext('chat.ideaWheelBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.wheelSpin')),
        findsOneWidget,
        reason: 'Der Dialog bietet an, das Rad zu drehen.',
      );

      // DAS DREHEN: Der Dialog wartet mit abnehmenden Zyklen - der Test
      // pumpt die Zeit in Schritten vor.
      await tester.tap(find.text(L10n.tWithoutContext('chat.wheelSpin')));
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.text(L10n.tWithoutContext('chat.wheelSend')),
        findsOneWidget,
        reason:
            'Nach dem Drehen muss der Vorschlag sich senden lassen - '
            'sonst dreht das Rad nur dekorativ.',
      );

      await tester.tap(find.text(L10n.tWithoutContext('chat.wheelSend')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Nach dem Senden ist der Dialog zu.',
      );
    });
  });

  group('Die Sammlungen im Menue', () {
    testWidgets('die Eisbrecher-Sammlung meldet, dass sie fehlt', (
      tester,
    ) async {
      // DER LOKALE KONTAKT (QR): Er hat keine Server-Nummer - da gibt es
      // keine Fragensammlung. Der Nutzer muss das erfahren, sonst passiert
      // beim Tippen einfach nichts.
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.spiceTooltip');

      expect(
        find.text(L10n.tWithoutContext('chat.spiceUnavailable')),
        findsOneWidget,
        reason:
            'Ein toter Menuepunkt ohne Rueckmeldung ist wie ein Fehler - '
            'der Nutzer muss den Grund sehen.',
      );
    });

    testWidgets('die Erinnerungsliste meldet, dass sie fehlt', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'bucket.title');

      expect(
        find.text(L10n.tWithoutContext('chat.spiceUnavailable')),
        findsOneWidget,
      );
    });

    testWidgets('die Eisbrecher-Sammlung oeffnet die Fragen', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2, alsServerFunke: true);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.spiceTooltip');

      expect(
        find.text('Fragensammlung'),
        findsOneWidget,
        reason:
            'Beim Server-Funke gibt es die Sammlung - der Nutzer muss zu '
            'den Fragen kommen.',
      );
    });
  });

  group('Das Beenden des Funkens', () {
    testWidgets('der Dialog fragt nach', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.end');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.endSparkTitle')),
        findsOneWidget,
        reason:
            'Ein Funke soll nicht einfach verschwinden - der Nutzer soll '
            'wissen, was passiert.',
      );
    });

    testWidgets('der Absage-Text wird gesendet', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.end');

      // EINE ABSAGE WÄHLEN: Der erste vorbereitete Text.
      await tester.tap(find.text(L10n.tWithoutContext('chat.goodbye.1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text(L10n.tWithoutContext('chat.coolSpark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // DER NACHWEIS IM VERLAUF: Nach dem Beenden springt der Bildschirm
      // zur Funken-Liste - der Verlauf ist also nicht mehr zu sehen. Der
      // Beweis ist die Nachricht selbst.
      final gesendet = chat.notifier
          .messagesFor(chat.match.id)
          .map((m) => m.text)
          .toList();
      expect(
        gesendet,
        contains(L10n.tWithoutContext('chat.goodbye.1')),
        reason:
            'Der Absage-Text geht an die Gegenseite - so muss niemand '
            'unerwartet ohne Antwort dastehen (kein Ghosting).',
      );
    });

    testWidgets('nach dem Beenden geht es zur Funken-Liste', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);
      await menuePunkt(tester, 'chat.end');

      await tester.tap(find.text(L10n.tWithoutContext('chat.coolSpark')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.text('Interessen'),
        findsOneWidget,
        reason:
            'Nach dem Beenden soll der Nutzer zur Funken-Liste kommen - '
            'nicht auf einer leeren Seite stehen bleiben.',
      );
    });
  });

  group('Die Sicherheitsnummer', () {
    // ANMERKUNG: Der Dialog selbst lässt sich im Widget-Test nicht
    // öffnen: Er wartet auf den Verschlüsselungs-Dienst, dessen
    // Schluesselaufbau in der Test-Zone hängt (echte Datei-Arbeit).
    // Der Weg dorthin (der Menüpunkt) ist getestet - siehe
    // test/chat_detail_screen/relay_hinweis_test.dart.
    testWidgets('der Menuepunkt steht da', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await menueOeffnen(tester);

      expect(
        find.text(L10n.tWithoutContext('chat.safetyNumberTooltip')),
        findsOneWidget,
        reason:
            'Die Sicherheitsnummer ist der Beweis, dass niemand dazwischen '
            'sitzt - ihr Weg muss erreichbar sein.',
      );
    });
  });

  group('Der Hinweis auf den Chat-Hintergrund', () {
    testWidgets('im ersten Chat kommt der Hinweis', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
        hinweisGesehen: false,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('chatbg.hintTitle')),
        findsOneWidget,
        reason:
            'Der Hinweis kommt beim ersten Chat - danach nicht mehr '
            '(sonst nervt er).',
      );
    });

    testWidgets('nach dem Wegklicken kommt er nicht wieder', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
        hinweisGesehen: false,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // "Später": Der Hinweis ist damit abgehakt.
      await tester.tap(find.text(L10n.tWithoutContext('common.later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Der Altersdifferenz-Hinweis (Jugendschutz)', () {
    testWidgets('bei zehn Jahren Unterschied steht der Hinweis da', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 2, partnerAlter: 20);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[], alter: 40),
      );

      expect(
        find.byIcon(Icons.warning_amber_rounded),
        findsOneWidget,
        reason:
            'Eine grosse Altersdifferenz kann eine falsche Altersangabe '
            'verbergen - der Nutzer muss darauf hingewiesen werden.',
      );
    });

    testWidgets('bei kleiner Differenz steht der Hinweis nicht da', (
      tester,
    ) async {
      final chat = chatMitNachrichten(anzahl: 2, partnerAlter: 30);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[], alter: 32),
      );

      expect(
        find.byIcon(Icons.warning_amber_rounded),
        findsNothing,
        reason:
            'Der Hinweis waere bei zwei Jahren Difference nur nervig - er '
            'kommt ab zehn Jahren.',
      );
    });

    testWidgets('der Hinweis fuehrt ins Sicherheitscenter', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2, partnerAlter: 20);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[], alter: 40),
      );

      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Sicherheitscenter'),
        findsOneWidget,
        reason:
            'Der Hinweis muss einen Weg zeigen - blockieren, melden, '
            'Sicherheitscenter.',
      );
    });
  });

  group('Die Wege aus der Kopfzeile', () {
    testWidgets('der Zurueck-Knopf bringt zur Funken-Liste', (tester) async {
      final chat = chatMitNachrichten(anzahl: 2);

      await baue(
        tester,
        match: chat.match,
        notifier: chat.notifier,
        profil: ich(<String>[]),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Interessen'),
        findsOneWidget,
        reason:
            'Nach dem Zurueck-Knopf kommt die Funken-Liste - der Nutzer '
            'soll zu seinen Chats zurueck.',
      );
    });
  });
}
