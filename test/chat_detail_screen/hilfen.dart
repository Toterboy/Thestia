// Die Helfer fuer die Tests des Bildschirms 'chat_detail_screen'.
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Helfer
// (Ersatz-Speicher, Aufbau, Bildschirm-Helfer) liegen hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.

// Der 1:1-Chat OHNE Server (v0.10.1).
//
// WARUM (13.11.2026): Der Chat-Screen ist die groesste Datei der App
// (rund 1.800 Zeilen) - und die Coverage-Messung zeigte: 0,1 %.
// Genau dort sitzt auch die eigene Tastatur (Build 54). Ein Screen, den
// niemand gerendert hat, ist geraten: der Absturz beim Wischen zwischen
// den Reitern (31.10.2026) war nur zufaellig im Screenshot-Render
// aufgefallen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Chat rendert mit seinen Nachrichten (kein Absturz, kein
//     Render-Overflow),
//   * ein Chat, den es nicht mehr gibt, zeigt den Hinweis statt eines
//     leeren Bildschirms,
//   * die EINGABE ist die eigene Tastatur: das Feld ist readOnly (die
//     Systemtastatur sieht nichts) und das Tippen oeffnet die
//     App-Tastatur,
//   * eine getippte Nachricht landet im Chat.
//
// OHNE SERVER: Die Supabase-Aufrufe des Bildschirms (P2P, Relay,
// Loeschen, Herz-Staerken) laufen ueber bestEffort/bestEffortOr und
// brechen ohne Client still ab. Genau das ist hier der Fall - es wird
// geprueft, was der Bildschirm ohne Server macht, nicht was er mit
// Server macht (das macht test/live_message_flow_test.dart).
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/models/chat/match.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/mood_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/services/chat/chat_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/server/mood_service.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';
import '../support/fake_supabase_server.dart';

class FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};
  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;
  @override
  Future<String?> getString(String key) async => _data[key];
  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();
  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';
  @override
  Future<void> remove(String key) async => _data.remove(key);
  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();
  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

class FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

UserProfile eigenesProfil() => UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo',
  birthDate: DateTime(1995, 6, 1),
);
UserProfile chatDetailScreenPartner() => UserProfile(
  id: 'partner-1',
  name: 'Mira',
  bio: '',
  birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
);
late supabase.SupabaseClient moodClient;
({ChatNotifier notifier, Match match}) chatMitNachricht({
  bool serverFunke = false,
}) {
  final service = ChatService();
  final match = serverFunke
      ? service.restoreServerMatch(
          '7',
          chatDetailScreenPartner(),
          DateTime.now(),
        )!
      : service.createMatch(chatDetailScreenPartner());
  service.addMessage(
    match.id,
    Message(
      id: 'm_1',
      senderId: 'partner-1',
      receiverId: 'ich',
      text: 'Hallo, magst du Kaffee?',
      timestamp: DateTime.now(),
    ),
  );
  return (notifier: ChatNotifier(service), match: match);
}

List<Override> chatDetailScreenOverrides(
  ChatNotifier notifier, {
  bool hinweisGesehen = true,
  bool unscharfeBilder = false,
}) {
  final storage = FakeLocalStorage();
  // Der Hinweis auf den Chat-Hintergrund (v0.10.0) kommt beim ersten
  // Chat - im Test stoert er nur, also ist er als "gesehen" markiert.
  if (hinweisGesehen) {
    storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{'chatBackgroundSeen': true}),
    );
  }
  // Die Bilder der Gegenseite zuerst unscharf (Schutz vor
  // unangemessenen Inhalten) - das kommt aus den Einstellungen.
  if (unscharfeBilder) {
    storage.saveString(
      AppConstants.prefsSettingsKey,
      jsonEncode(<String, dynamic>{
        'chatBackgroundSeen': true,
        'blurChatImages': true,
      }),
    );
  }
  return [
    localStorageProvider.overrideWithValue(storage),
    secureProfileStoreProvider.overrideWithValue(FakeSecureProfileStore()),
    profileProvider.overrideWith((ref) {
      final notifier = ProfileNotifier(storage, FakeSecureProfileStore());
      notifier.setProfile(eigenesProfil());
      return notifier;
    }),
    moodServiceProvider.overrideWithValue(MoodService(moodClient)),
    chatProvider.overrideWith((ref) => notifier),
  ];
}

Future<void> chatDetailScreenPump(
  WidgetTester tester,
  Widget kind,
  ChatNotifier notifier, {
  bool hinweisGesehen = true,
  bool unscharfeBilder = false,
  List<Override> overrides = const <Override>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...chatDetailScreenOverrides(
          notifier,
          hinweisGesehen: hinweisGesehen,
          unscharfeBilder: unscharfeBilder,
        ),
        ...overrides,
      ],
      child: MaterialApp(theme: ThemeData(useMaterial3: true), home: kind),
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

class FakeReportService extends ReportService {
  /// Die Nachrichten, die bei der Meldung mitgingen.
  final List<Message> gemeldeteNachrichten = [];

  /// Der Typ der Meldung.
  ReportType? gemeldeterTyp;
  @override
  Future<ReportSubmission> createReport({
    required String reporterId,
    required String reporterUserName,
    required String reportedUserId,
    required String reportedUserName,
    required ReportType type,
    String? description,
    List<Message>? messages,
  }) async {
    gemeldeterTyp = type;
    gemeldeteNachrichten.addAll(messages ?? const <Message>[]);
    return ReportSubmission(
      report: UserReport(
        id: 'report-1',
        reporterId: reporterId,
        reportedUserId: reportedUserId,
        type: type,
        description: description,
        createdAt: DateTime.now(),
      ),
      serverAccepted: true,
    );
  }
}

/// Legt eine kleine Aufnahmedatei an (der Pfad kommt vom Plugin).
///
/// DER GRUND: Das Aufnahme-Plugin meldet beim Stoppen einen Pfad. Ohne
/// Datei prueft der Bildschirm gar nicht weiter - die Datei muss also
/// wirklich da sein.
///
/// ACHTUNG: Das ist echte Datei-Arbeit - sie muss ueber
/// [WidgetTester.runAsync] laufen, sonst wartet der Test ewig.
Future<String> aufnahmeDatei() async {
  final ordner = await Directory.systemTemp.createTemp('thesia_voice_test');
  final pfad = '${ordner.path}/aufnahme.m4a';
  await File(pfad).writeAsBytes(<int>[1, 2, 3, 4]);
  return pfad;
}

/// Laesst die echten Datei-Zugriffe durch und baut danach neu.
///
/// DER GRUND: Das Lesen und Loeschen der Aufnahme-Datei ist echte
/// Arbeit - sie laeuft ausserhalb der Test-Uhr. Ohne dieses Warten
/// bleibt der Bildschirm bei "Aufnahme laeuft" stehen und die Meldung
/// kommt nicht.
///
/// Es sind mehrere Runden: jeder `await` in der Kette (Abo beenden,
/// Plugin stoppen, Datei loeschen) braucht seine eigene Runde durch
/// die echte Ereignisschleife.
Future<void> echteZeit(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

FakeSupabaseServer server = FakeSupabaseServer(userId: 'ich');
