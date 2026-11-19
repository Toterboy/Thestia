// Der Ersatz fuer die Anbieter, die der Router braucht.
//
// ANLASS (19.11.2026): Der Rauchtest ueber alle Routen braucht einen
// Container, in dem der Router ein fertig eingerichtetes Konto sieht -
// und das an ZWEI Stellen (Redirect-Test und Rauchtest).
//
// DER WEG: Diese Datei ist der gemeinsame Ort fuer die Ersatz-
// Anbieter. Sie sind handgeschrieben (kein mocktail, kein mockito) -
// der Test soll zeigen, was die App wirklich tut.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/auth/app_auth_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

/// Der Speicher im RAM (nichts wird auf der Platte gespeichert).
class TestSpeicher implements LocalStorage {
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
class TestKeystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    // Der Test speichert kein Profil im Keystore.
  }

  @override
  Future<void> delete() async {
    // Der Test loescht kein Profil im Keystore.
  }
}

/// Der Auth-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt die Session vom Server. Fuer den
/// Test ist nur wichtig, OB jemand eingeloggt ist - und das entscheidet
/// der Test selbst, nicht der Server.
class TestAuth implements AppAuthService {
  /// Meldet der Dienst eine vorhandene Sitzung?
  ///
  /// DER GRUND: Der echte Dienst holt die Session vom Server. Fuer den
  /// Test ist nur wichtig, OB jemand eingeloggt ist - und das entscheidet
  /// der Test selbst, nicht der Server.
  final bool eingeloggt;

  /// Wirft der Dienst bei der Registrierung einen Fehler?
  final Object? registrierungsFehler;

  /// Wirft der Dienst bei der Anmeldung einen Fehler?
  final Object? anmeldeFehler;

  /// Das Profil, das die Registrierung liefert.
  final UserProfile? registriertesProfil;

  TestAuth({
    this.eingeloggt = true,
    this.registrierungsFehler,
    this.anmeldeFehler,
    this.registriertesProfil,
  });

  @override
  Future<bool> restoreSession() async {
    // DER WEG: Die Wiederherstellung antwortet erst nach einem kleinen
    // Augenblick. Sonst wuerde sie den Auth-Status UEBERSCHreiben, bevor
    // der Router ihn liest - und der Server-Sync, der nach der Anmeldung
    // laeuft, wuerde die Test-Werte zerstoeren.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return eingeloggt;
  }

  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final fehler = anmeldeFehler;
    if (fehler != null) throw fehler;
    // Der Test meldet sich nicht wirklich an - der Zustand wird gesetzt.
  }

  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {
    // Der Test meldet sich nicht an - der Zustand wird gesetzt.
  }

  @override
  Future<void> logout() async {
    // Der Test meldet sich nicht ab - der Zustand wird gesetzt.
  }

  @override
  Future<void> deleteAccount() async {
    // Der Test loescht kein Konto.
  }

  @override
  Future<UserProfile> register({
    required String email,
    required String password,
    required String name,
    String? gender,
    required DateTime birthDate,
    String? captchaToken,
    double? latitude,
    double? longitude,
  }) async {
    final fehler = registrierungsFehler;
    if (fehler != null) throw fehler;
    return registriertesProfil ??
        UserProfile(id: 'ich', name: name, bio: '', birthDate: birthDate);
  }
}

/// Die Einstellungen als Ersatz (der Test gibt sie direkt vor).
class TestEinstellungen extends SettingsNotifier {
  TestEinstellungen(Ref ref) : super(TestSpeicher(), ref);
}

/// Das Profil als Ersatz (der Test gibt den Verifikationsstand vor).
class TestProfil extends ProfileNotifier {
  TestProfil() : super(TestSpeicher(), TestKeystore());
}
