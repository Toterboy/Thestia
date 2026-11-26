// Die Nutzungszeit-Sperre (Elternbereich).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/settings/usage_time_gate.dart nur 7,5 % Abdeckung. Die reine
// Rechnung (isWithinWindow) war getestet - der BILDSCHIRM nicht: also
// weiß niemand, ob die Sperre die App tatsächlich zuhält.
//
// WAS HIER GEPRÜFT WIRD:
//   * außerhalb der erlaubten Zeit steht die Sperre statt der App,
//   * innerhalb der erlaubten Zeit steht die App (die Sperre blockt
//     nicht versehentlich),
//   * ohne Begrenzung steht immer die App.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/guardian_provider.dart';
import 'package:thestia/services/auth/app_auth_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/services/verification/guardian_service.dart';
import 'package:thestia/widgets/settings/usage_time_gate.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Keystore ohne Plugin.
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Auth-Dienst als Ersatz - der Test meldet niemanden an.
class _Auth implements AppAuthService {
  @override
  Future<bool> restoreSession() async => false;

  @override
  Future<UserProfile> register({
    required String name,
    required String email,
    required String password,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async => UserProfile(id: 'neu', name: name, bio: '', birthDate: birthDate);

  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {}

  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount() async {}
}

/// Der Eltern-Dienst als Ersatz: Er meldet den Stand, den der Test will.
class _GuardianDienst extends GuardianService {
  _GuardianDienst(super.client, this.stand);

  /// Der Stand, den der Dienst meldet.
  final GuardianStatus stand;

  @override
  Future<GuardianStatus> fetchStatus() async => stand;
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
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
  });

  setUp(() {
    server.zeilen.clear();
    server.rpcAntworten.clear();
  });

  /// Baut die Sperre mit dem gewünschten Stand.
  Future<void> zeige(WidgetTester tester, GuardianStatus stand) async {
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
        guardianServiceProvider.overrideWithValue(
          _GuardianDienst(supabase.Supabase.instance.client, stand),
        ),
        authProvider.overrideWith(
          (ref) =>
              AuthNotifier(_Auth(), ref.read(profileProvider.notifier), ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: UsageTimeGate(child: Text('Die App'))),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('Die Nutzungszeit-Sperre', () {
    testWidgets('ausserhalb der erlaubten Zeit steht die Sperre', (
      tester,
    ) async {
      final jetzt = DateTime.now();
      // DAS FENSTER: Es beginnt erst in zwei Stunden - jetzt ist die App
      // also gesperrt.
      final stand = GuardianStatus(
        usageLimitEnabled: true,
        usageStartMin: (jetzt.hour + 2) * 60 + jetzt.minute,
        usageEndMin: (jetzt.hour + 3) * 60 + jetzt.minute,
        loaded: true,
      );

      await zeige(tester, stand);

      expect(
        find.text('Die App'),
        findsNothing,
        reason: 'Die gesperrte App darf nicht zu sehen sein.',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.usageLockTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, WARUM die App gesperrt ist - ein leerer '
            'Bildschirm sieht wie ein Absturz aus.',
      );
    });

    testWidgets('innerhalb der erlaubten Zeit steht die App', (tester) async {
      final jetzt = DateTime.now();
      // DAS FENSTER: Es läuft von vor einer bis nach einer Stunde.
      final stand = GuardianStatus(
        usageLimitEnabled: true,
        usageStartMin: (jetzt.hour - 1) * 60 + jetzt.minute,
        usageEndMin: (jetzt.hour + 1) * 60 + jetzt.minute,
        loaded: true,
      );

      await zeige(tester, stand);

      expect(
        find.text('Die App'),
        findsOneWidget,
        reason:
            'Innerhalb der erlaubten Zeit darf die Sperre nicht zuschlagen - '
            'sonst ist die App unbenutzbar.',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.usageLockTitle')),
        findsNothing,
      );
    });

    testWidgets('ohne Begrenzung steht immer die App', (tester) async {
      await zeige(tester, const GuardianStatus(loaded: true));

      expect(
        find.text('Die App'),
        findsOneWidget,
        reason:
            'Wer keine Nutzungszeit begrenzt hat, darf die App benutzen - '
            'auch um die Uhrzeit, zu der ein anderer gesperrt waere.',
      );
    });
  });
}
