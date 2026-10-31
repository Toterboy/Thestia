import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:thestia/models/contact_share_profile.dart';
import 'package:thestia/services/secure_storage_namespaces.dart';

/// Verschlüsselte, rein lokale Speicherung der freiwilligen Kontaktdaten
/// aus "Connect to others".
///
/// DATENSCHUTZ: Telefonnummer und Handles werden NIE an Supabase oder
/// andere Server gesendet. Sie liegen im Keystore (Android) bzw. in der
/// Keychain (iOS) und werden nur beim aktiven Teilen/Kopieren ausgelesen.
class SecureContactShareStore {
  static const _profileKey = 'contact_share_profile';

  static const _androidOptions = AndroidOptions(
    storageNamespace: SecureNamespaces.contacts,
  );
  static const _iOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    accountName: SecureNamespaces.contacts,
  );

  final FlutterSecureStorage _storage;

  SecureContactShareStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  Future<ContactShareProfile> load() async {
    try {
      final raw = await _storage.read(
        key: _profileKey,
        aOptions: _androidOptions,
        iOptions: _iOSOptions,
      );
      if (raw == null || raw.isEmpty) return const ContactShareProfile();
      return ContactShareProfile.fromJsonString(raw);
    } catch (e) {
      // Korrupte/unnatürlich unlesbare Daten dürfen die App nicht
      // blockieren. Es wird nichts gelöscht - der nächste Speichervorgang
      // ersetzt den Eintrag.
      debugPrint('[ContactShare] Laden fehlgeschlagen: $e');
      return const ContactShareProfile();
    }
  }

  Future<void> save(ContactShareProfile profile) => _storage.write(
    key: _profileKey,
    value: profile.toJsonString(),
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );

  Future<void> clear() => _storage.delete(
    key: _profileKey,
    aOptions: _androidOptions,
    iOptions: _iOSOptions,
  );
}
