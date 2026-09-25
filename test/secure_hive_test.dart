import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:thestia/services/secure_hive.dart';

/// In-Memory-Fake für den Keystore (flutter_secure_storage).
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage(this.store);

  final Map<String, String> store;

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    store[key] = value ?? '';
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    store.remove(key);
  }
}

/// Tests für [SecureHive] (Audit K6/M11): AES-verschlüsselte Hive-Boxen mit
/// Schlüssel aus dem (gefakten) Keystore.
void main() {
  late Directory tempDir;
  late Map<String, String> keystore;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('secure_hive_test');
    Hive.init(tempDir.path);
    keystore = {};
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  SecureHive newHive() => SecureHive.forTesting(_FakeSecureStorage(keystore));

  test('Schlüssel wird einmalig erzeugt und im Keystore persistiert', () async {
    final hive = newHive();
    await hive.openBox<String>('box_a');

    expect(keystore.containsKey('hive_encryption_key'), isTrue);
    final key1 = keystore['hive_encryption_key']!;
    final bytes = base64Decode(key1);
    expect(bytes.length, equals(32));

    // Zweite Box: derselbe Schlüssel wird wiederverwendet (kein neuer).
    await hive.openBox<String>('box_b');
    expect(keystore['hive_encryption_key'], equals(key1));
  });

  test('Daten überleben Reopen (gleicher Schlüssel) und sind at-rest '
      'verschlüsselt', () async {
    final hive1 = newHive();
    final box1 = await hive1.openBox<String>('persist');
    await box1.put('secret', 'private-identity-key-material');
    await box1.flush();
    final boxPath = box1.path;
    await box1.close();

    // At-rest-Check: Rohdaten dürfen den Klartext NICHT enthalten.
    final raw = File(boxPath!).readAsBytesSync();
    final rawString = latin1Decode(raw);
    expect(rawString.contains('private-identity-key-material'), isFalse,
        reason: 'Hive-Datei enthält Klartext – Box wurde nicht verschlüsselt.');

    // Reopen mit demselben (persistierten) Schlüssel liefert die Daten.
    final hive2 = newHive();
    final box2 = await hive2.openBox<String>('persist');
    expect(box2.get('secret'), equals('private-identity-key-material'));
  });

  test('Ohne Schlüssel (verloren/geänderter Keystore) wird die Box '
      'sicher zurückgesetzt', () async {
    final hive1 = newHive();
    final box1 = await hive1.openBox<String>('locked');
    await box1.put('secret', 'must-not-leak');
    await box1.close();

    // Keystore leeren = Schlüsselverlust simulieren.
    keystore.clear();

    final hive2 = newHive();
    final box2 = await hive2.openBox<String>('locked');
    expect(box2.isEmpty, isTrue,
        reason: 'Mit fremdem Schlüssel unlesbare Box muss zurückgesetzt '
            'werden (fail-closed, keine Klartext-Weiterverwendung).');
  });

  test('Klartext-Altbestand wird transparent in verschlüsselte Box '
      'migriert', () async {
    // Alt-Box OHNE Cipher anlegen (Stand vor dem Security-Fix).
    final plain = await Hive.openBox<String>('legacy');
    await plain.put('old', 'legacy-value');
    await plain.close();

    final hive = newHive();
    final box = await hive.openBox<String>('legacy');
    expect(box.get('old'), equals('legacy-value'));

    // Nach der Migration muss die Datei verschlüsselt sein.
    await box.flush();
    final raw = latin1Decode(File(box.path!).readAsBytesSync());
    expect(raw.contains('legacy-value'), isFalse);
  });

  test('Ungültiger gespeicherter Schlüssel (falsche Länge) wird ersetzt', () async {
    keystore['hive_encryption_key'] = base64Encode(List.filled(16, 1));
    final hive = newHive();
    final box = await hive.openBox<String>('recover');
    await box.put('k', 'v');
    expect(box.get('k'), equals('v'));
    final newKey = base64Decode(keystore['hive_encryption_key']!);
    expect(newKey.length, equals(32));
  });
}

String latin1Decode(List<int> bytes) => String.fromCharCodes(bytes);
