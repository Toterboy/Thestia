import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:thestia/models/signal_key_models.dart';

/// Ein [InMemorySignalProtocolStore], der Session-Records automatisch in
/// einer Hive-Box persistiert.
///
/// Nach einem App-Neustart werden alle Sessions aus der Hive-Box geladen
/// und der Double-Ratchet-Zustand (Chain Keys, Message Keys, Ratchet-State)
/// bleibt erhalten. Ohne diese Persistenz wären Sessions nach jedem Neustart
/// unbrauchbar — eine zentrale Anforderung für E2E-Verschlüsselung.
///
/// Audit H-7 (E-2/E-4-Fixes):
/// - Identity-Trust wird PERSISTIERT (Box 'signal_identity_trust'): Die
///   Trust-Map des InMemory-Stores war bisher flüchtig - nach jedem
///   Neustart wurde JEDE Identität akzeptiert (TOFU-Reset), was einem
///   serverseitigen Bundle-Swap (MITM) das Tor öffnete. Jetzt übersteht
///   der Vertrauensstatus Neustarts und ein Key-Wechsel wirft eine
///   [UntrustedIdentityException] statt still akzeptiert zu werden.
/// - PreKeys/SignedPreKey liegen in eigenen verschlüsselten Boxen
///   ([EncryptionService]) und überleben Neustarts ebenfalls.
class HiveSignalProtocolStore extends InMemorySignalProtocolStore {
  HiveSignalProtocolStore(
    super.identityKeyPair,
    super.localRegistrationId,
    this._sessionBox, [
    Box<SignalIdentityKeyStoreAdapter>? identityTrustBox,
  ]) : _identityTrustBox = identityTrustBox;

  final Box<SignalSessionRecordAdapter> _sessionBox;

  /// Persistenter Identity-Trust (Audit H-7/E-4). NULL = Legacy-Verhalten
  /// (In-Memory), z. B. wenn die Box nicht geöffnet werden konnte.
  final Box<SignalIdentityKeyStoreAdapter>? _identityTrustBox;

  /// Lädt alle aus Hive persistierten Sessions in den Store.
  static Future<HiveSignalProtocolStore> open({
    required IdentityKeyPair identityKeyPair,
    required int localRegistrationId,
    required Box<SignalSessionRecordAdapter> sessionBox,
    Box<SignalIdentityKeyStoreAdapter>? identityTrustBox,
  }) async {
    final store = HiveSignalProtocolStore(
      identityKeyPair,
      localRegistrationId,
      sessionBox,
      identityTrustBox,
    );

    // Bestehende Sessions aus Hive laden.
    for (final adapter in sessionBox.values) {
      try {
        final record =
            SessionRecord.fromSerialized(base64Decode(adapter.recordJson));
        final address = _addressFromId(adapter.sessionId);
        await store.storeSession(address, record);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[HiveSignalStore] Session ${adapter.sessionId} konnte nicht '
            'geladen werden: $e',
          );
        }
        // Beschädigte Session löschen.
        await adapter.delete();
      }
    }

    return store;
  }

  // ==========================================================================
  // Persistenter Identity-Trust (Audit H-7 / E-4)
  // ==========================================================================

  static String _trustId(SignalProtocolAddress address) =>
      '${address.getName()}:${address.getDeviceId()}';

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    if (identityKey == null) return false;
    final box = _identityTrustBox;
    if (box == null) {
      // Fallback ohne Persistenz (sollte nicht vorkommen): TOFU im RAM.
      return true;
    }
    final stored = box.get(_trustId(address));
    if (stored == null) return true; // Erster Kontakt (TOFU)
    try {
      final trusted = IdentityKey.fromBytes(base64Decode(stored.trustedKeyJson), 0);
      return _bytesEqual(trusted.serialize(), identityKey.serialize());
    } catch (_) {
      return false; // Beschädigter Eintrag -> fail-closed
    }
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    final box = _identityTrustBox;
    if (identityKey == null || box == null) {
      return await super.saveIdentity(address, identityKey);
    }
    final id = _trustId(address);
    final serialized = base64Encode(identityKey.serialize());
    final existing = box.get(id);
    if (existing != null && existing.trustedKeyJson == serialized) {
      return false; // Unverändert
    }
    await box.put(
      id,
      SignalIdentityKeyStoreAdapter(
        trustedKeyJson: serialized,
        recipientId: address.getName(),
      ),
    );
    return existing != null; // true = Key hat sich geändert
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final box = _identityTrustBox;
    if (box == null) return super.getIdentity(address);
    final stored = box.get(_trustId(address));
    if (stored == null) return null;
    try {
      return IdentityKey.fromBytes(base64Decode(stored.trustedKeyJson), 0);
    } catch (_) {
      return null;
    }
  }

  /// Entfernt den persistenten Trust für einen Peer (nur nach expliziter
  /// Nutzer-Bestätigung "Sicherheitsnummer hat sich geändert" verwenden).
  Future<void> forgetIdentity(String peerName) async {
    final box = _identityTrustBox;
    if (box == null) return;
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry != null && entry.recipientId == peerName) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    await super.storeSession(address, record);
    await _persist(address, record);
  }

  @override
  Future<void> deleteSession(SignalProtocolAddress address) async {
    await super.deleteSession(address);
    final key = await _sessionBox.keys.firstWhere(
      (k) => _sessionBox.get(k)?.sessionId == _sessionId(address),
      orElse: () => null,
    );
    if (key != null) {
      await _sessionBox.delete(key);
    }
  }

  @override
  Future<void> deleteAllSessions(String name) async {
    await super.deleteAllSessions(name);
    // Alle Sessions mit diesem Namen-Präfix löschen.
    final toRemove = <dynamic>[];
    for (final key in _sessionBox.keys) {
      final adapter = _sessionBox.get(key);
      if (adapter != null && adapter.sessionId.startsWith('$name:')) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      await _sessionBox.delete(key);
    }
  }

  /// Persistiert eine einzelne Session in Hive.
  Future<void> _persist(
    SignalProtocolAddress address,
    SessionRecord record,
  ) async {
    final id = _sessionId(address);
    final adapter = SignalSessionRecordAdapter(
      sessionId: id,
      recordJson: base64Encode(record.serialize()),
    );
    // Bestehenden Eintrag überschreiben oder neuen anlegen.
    final existingKey = await _sessionBox.keys.firstWhere(
      (k) => _sessionBox.get(k)?.sessionId == id,
      orElse: () => null,
    );
    if (existingKey != null) {
      await _sessionBox.put(existingKey, adapter);
    } else {
      await _sessionBox.add(adapter);
    }
  }

  /// Bildet eine Session-ID für Hive aus der Signal-Adresse.
  static String _sessionId(SignalProtocolAddress address) =>
      '${address.getName()}:${address.getDeviceId()}';

  /// Rekonstruiert eine Signal-Adresse aus der Session-ID.
  static SignalProtocolAddress _addressFromId(String id) {
    final parts = id.split(':');
    return SignalProtocolAddress(parts[0], int.parse(parts[1]));
  }

  /// Schließt die Hive-Box.
  Future<void> close() async {
    await _sessionBox.close();
  }
}
