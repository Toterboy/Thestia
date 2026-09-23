import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha512;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:wisp/models/signal_key_models.dart';
import 'package:wisp/services/backup_crypto.dart';
import 'package:wisp/services/hive_signal_store.dart';
import 'package:wisp/services/secure_hive.dart';

/// Zentrale Service-Klasse für Ende-zu-Ende-Verschlüsselung mit dem Signal Protocol.
///
/// Kapselt alle kryptographischen Operationen:
/// - Identitätsschlüsselpaar (Identity Key Pair)
/// - PreKeys (einmalige Schlüssel für neue Sessions)
/// - Signed PreKeys (langfristige signierte Schlüssel, mit Zeitrotation)
/// - Session-Management (Verschlüsselung/Entschlüsselung)
/// - Persistente Speicherung der Identität via Hive
///
/// Audit H-7-Fixes (PreKey-Lifecycle):
/// - E-2: PreKeys und der Signed PreKey werden jetzt PERSISTIERT
///   (verschlüsselte Hive-Boxen). Bisher wurden sie bei jedem Start neu
///   generiert, während der Server das ALTE Bundle auslieferte -> alle
///   neuen eingehenden Sessions brachen nach einem Neustart.
/// - E-1: [exportPreKeyBundle] rückt den Cursor nach jeder Auslieferung
///   vor; aufeinanderfolgende Bundles enthalten unterschiedliche
///   One-Time-PreKeys statt denselben an alle Peers.
/// - E-3: Der Signed PreKey rotiert zeitbasiert (90 Tage); alte Keys
///   bleiben zur Entschlüsselung laufender Sessions erhalten.
/// - E-4: Identity-Trust wird persistent ([HiveSignalProtocolStore]);
///   ein bekannter Peer-Key-Change wirft jetzt eine Exception
///   ('peer_identity_changed') statt still akzeptiert zu werden.
class EncryptionService {
  static const String _boxNameIdentity = 'signal_identity';
  static const String _boxNameSessions = 'signal_sessions';
  static const String _boxNamePeerTrust = 'signal_peer_trust';
  static const String _boxNamePreKeys = 'signal_prekeys';
  static const String _boxNameSignedPreKeys = 'signal_signed_prekeys';
  static const String _boxNameIdentityTrust = 'signal_identity_trust';
  static const String _boxNameMeta = 'signal_meta';
  static const String _identityKey = 'identity';
  static const String _registrationIdKey = 'registration_id';
  static const String _preKeyCursorKey = 'prekey_cursor';
  static const String _signedPreKeyActiveKey = 'signed_prekey_active';

  late final Box<SignalIdentityKeyPairAdapter> _identityBox;
  late final Box<SignalSessionRecordAdapter> _sessionBox;

  /// Reine Skalar-Metadaten (Registrierungs-ID, PreKey-Cursor,
  /// aktiver SignedPreKey) als Klartext-Strings. Bewusst EIGENE Box, statt
  /// den [SignalIdentityKeyPairAdapter] (der eigentlich nur den Identity-
  /// Key hält) für fremde Strings zweckzuentfremden.
  late final Box<String> _metaBox;

  /// Peer-Trust-Store: peerId → JSON { identityKeyPublic, verified }.
  /// Grundlage der Safety-Number-Verifikation (Audit B2) – verschlüsselt
  /// über [SecureHive], da hier Identity-Keys und Vertrauensstatus liegen.
  /// (Als JSON-String, weil Hive für Map keinen eingebauten Adapter hat.)
  late final Box<String> _peerTrustBox;

  /// Persistente PreKey-/SignedPreKey-Store (Audit H-7/E-2).
  late final Box<SignalPreKeyRecordAdapter> _preKeysBox;
  late final Box<SignalSignedPreKeyRecordAdapter> _signedPreKeysBox;

  /// Persistenter libsignal-Identity-Trust (Audit H-7/E-4).
  late final Box<SignalIdentityKeyStoreAdapter> _identityTrustBox;

  HiveSignalProtocolStore? _store;
  IdentityKeyPair? _identityKeyPair;
  int _registrationId = 1;

  /// Eigene User-ID (für Safety-Numbers via NumericFingerprintGenerator).
  /// Wird vom Auth-Flow gesetzt (Login/Restore) und von WebRTC als Fallback.
  String? localUserId;

  /// Future, das abschließt, sobald [initialize] fertig ist. Ermöglicht
  /// anderen Services (z. B. [PreKeyService]), sicher auf initialisierte
  /// Schlüssel zu warten, statt eine Race-Condition zu riskieren.
  Future<void> get initialized => _initCompleter.future;
  final _initCompleter = Completer<void>();

  static const int _firstPreKeyId = 1;
  static const int _preKeyCount = 100;

  /// Cursor für PreKey-Auswahl, wandert vorwärts und wrappt.
  int _preKeyIndex = 0;

  /// Gültigkeit des aktiven Signed PreKeys (Signal-Empfehlung: Wochen bis
  /// Monate). Nach Ablauf wird ein neuer erzeugt, der alte bleibt für
  /// laufende Sessions erhalten.
  static const Duration _signedPreKeyLifetime = Duration(days: 90);

  /// Mindestanzahl unbenutzter PreKeys, bevor eine Neugeneration ausgelöst wird.
  static const int _preKeyLowWatermark = 10;

  /// Initialisiert den Service und öffnet die Hive-Boxen.
  ///
  /// Die Boxen werden AES-256-verschlüsselt geöffnet (Schlüssel liegt im
  /// Keystore/Keychain, siehe [SecureHive]) – der private Identity-Key,
  /// die PreKeys und die Session-Ratchet-States liegen damit nicht im
  /// Klartext auf der Platte.
  Future<void> initialize() async {
    // Fail-open statt Hang (Fix): Schlägt das Öffnen einer Box fehl
    // (z. B. Keystore gesperrt), bekommen Wartende eine Exception statt
    // ewig zu blockieren - Aufrufer zeigen dann Fehler statt Funkstille.
    try {
      await _initializeInner();
    } catch (e) {
      if (!_initCompleter.isCompleted) _initCompleter.completeError(e);
      rethrow;
    }
  }

  Future<void> _initializeInner() async {    _identityBox = await SecureHive.instance.openBox<SignalIdentityKeyPairAdapter>(
      _boxNameIdentity,
    );
    _sessionBox = await SecureHive.instance.openBox<SignalSessionRecordAdapter>(
      _boxNameSessions,
    );
    _peerTrustBox = await SecureHive.instance.openBox<String>(_boxNamePeerTrust);
    _preKeysBox =
        await SecureHive.instance.openBox<SignalPreKeyRecordAdapter>(_boxNamePreKeys);
    _signedPreKeysBox = await SecureHive.instance
        .openBox<SignalSignedPreKeyRecordAdapter>(_boxNameSignedPreKeys);
    _identityTrustBox = await SecureHive.instance
        .openBox<SignalIdentityKeyStoreAdapter>(_boxNameIdentityTrust);
    _metaBox = await SecureHive.instance.openBox<String>(_boxNameMeta);

    await _migrateLegacyMeta();
    await _loadOrCreateIdentity();
    _store = await HiveSignalProtocolStore.open(
      identityKeyPair: _identityKeyPair!,
      localRegistrationId: _registrationId,
      sessionBox: _sessionBox,
      identityTrustBox: _identityTrustBox,
    );

    // Persistierte Keys laden; fehlende generieren (Audit H-7/E-2).
    await _loadOrEnsurePreKeys();
    await _loadOrRotateSignedPreKey();
    // KRITISCHER FIX (Nachrichten kommen nicht an): Der libsignal-Store
    // ist In-Memory - nach einem Neustart enthielt er nur den AKTIVEN
    // SignedPreKey. Nachrichten von Peers, die ein AELTERES Bundle
    // geladen hatten (referenzieren SignedPreKey 1, aktiv inzwischen 2+),
    // waren unlesbar und blieben im Relay haengen. Jetzt werden ALLE
    // persistierten SignedPreKeys wieder in den Store geladen.
    await _reloadAllSignedPreKeys();
    // Initialisierung abgeschlossen - wartende Consumer (PreKeyService) können
    // nun Sessions aufbauen / Bundles exportieren.
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  /// Einmalige Migration: Skalar-Metadaten (Registrierungs-ID, PreKey-Cursor,
  /// aktiver Signed-PreKey) lagen früher zweckentfremdet in [_identityBox]
  /// als [SignalIdentityKeyPairAdapter]. Sie werden in die eigene [_metaBox]
  /// verschoben, damit bestehende Installationen ihren Stand nicht verlieren.
  Future<void> _migrateLegacyMeta() async {
    for (final key in [
      _registrationIdKey,
      _preKeyCursorKey,
      _signedPreKeyActiveKey,
    ]) {
      if (_metaBox.get(key) != null) continue;
      final legacy = _identityBox.get(key);
      if (legacy != null) {
        await _metaBox.put(key, legacy.identityKeyPairJson);
        await _identityBox.delete(key);
      }
    }
  }

  /// Lädt das existierende Identitätsschlüsselpaar oder generiert ein neues.
  Future<void> _loadOrCreateIdentity() async {
    final existing = _identityBox.get(_identityKey);
    final registration = _metaBox.get(_registrationIdKey);
    if (existing != null) {
      _identityKeyPair = IdentityKeyPair.fromSerialized(
        base64Decode(existing.identityKeyPairJson),
      );
      _registrationId = registration != null
          ? int.tryParse(registration) ?? 1
          : 1;
    } else {
      _identityKeyPair = generateIdentityKeyPair();
      _registrationId = generateRegistrationId(false);
      await _identityBox.put(
        _identityKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: base64Encode(_identityKeyPair!.serialize()),
        ),
      );
      await _metaBox.put(_registrationIdKey, _registrationId.toString());
    }
    _preKeyIndex =
        int.tryParse(_metaBox.get(_preKeyCursorKey) ?? '') ?? 0;
  }

  /// Gibt das eigene Identitätsschlüsselpaar zurück.
  IdentityKeyPair get identityKeyPair => _identityKeyPair!;

  /// Gibt den öffentlichen Identitätsschlüssel als Base64 zurück (für Austausch).
  String get identityKeyPublicBase64 =>
      base64Encode(_identityKeyPair!.getPublicKey().serialize());

  // ==========================================================================
  // PreKey-Verwaltung (persistiert, Audit H-7/E-2)
  // ==========================================================================

  Future<void> _storePreKeyPersistent(int keyId, PreKeyRecord record) async {
    await _store!.storePreKey(keyId, record);
    await _preKeysBox.put(
      keyId.toString(),
      SignalPreKeyRecordAdapter(
        keyId: keyId,
        keyPairJson: base64Encode(record.serialize()),
      ),
    );
  }

  /// Lädt persistierte PreKeys in den Store und füllt Lücken auf.
  Future<void> _loadOrEnsurePreKeys({int count = _preKeyCount}) async {
    var available = 0;
    for (var i = 0; i < count; i++) {
      final keyId = _firstPreKeyId + i;
      final persisted = _preKeysBox.get(keyId.toString());
      if (persisted != null) {
        try {
          final record = PreKeyRecord.fromBuffer(base64Decode(persisted.keyPairJson));
          await _store!.storePreKey(keyId, record);
          available++;
          continue;
        } catch (_) {
          // Beschädigter Eintrag -> neu generieren.
          await _preKeysBox.delete(keyId.toString());
        }
      }
      if (!(await _store!.containsPreKey(keyId))) {
        final preKey = generatePreKeys(keyId, 1).first;
        await _storePreKeyPersistent(keyId, preKey);
        available++;
      } else {
        available++;
      }
    }
    debugPrint('[EncryptionService] PreKeys verfügbar: $available');
  }

  /// Holt den nächsten unbenutzten PreKey via Cursor UND rückt den Cursor
  /// vor (Audit H-7/E-1): Aufeinanderfolgende Bundle-Exporte liefern
  /// verschiedene One-Time-Keys statt denselben an alle Peers.
  ///
  /// Durchläuft den Key-Raum `[1, 100]` zyklisch; konsumierte Keys werden
  /// von libsignal automatisch aus dem Store entfernt. Liefert `null`, wenn
  /// keine unbenutzten Keys mehr existieren (Löser: `_loadOrEnsurePreKeys`).
  Future<PreKeyRecord?> getUnusedPreKey() async {
    final store = _store!;
    for (var attempt = 0; attempt < _preKeyCount; attempt++) {
      final keyId = _firstPreKeyId + _preKeyIndex;
      // Cursor sofort weiterstellen (auch wenn dieser Key nicht passt),
      // damit parallele Exporte nicht denselben Key bekommen.
      _preKeyIndex = (_preKeyIndex + 1) % _preKeyCount;
      await _metaBox.put(_preKeyCursorKey, _preKeyIndex.toString());
      if (await store.containsPreKey(keyId)) {
        return store.loadPreKey(keyId);
      }
    }
    return null;
  }

  /// Gibt die Anzahl noch verfügbarer (nicht konsumierter) PreKeys zurück.
  Future<int> get availablePreKeyCount async {
    final store = _store!;
    var count = 0;
    for (var i = _firstPreKeyId; i < _firstPreKeyId + _preKeyCount; i++) {
      if (await store.containsPreKey(i)) count++;
    }
    return count;
  }

  /// Löst PreKey-Neugeneration aus, wenn der Vorrat unter die Schwelle fällt.
  Future<void> maybeRotatePreKeys() async {
    final available = await availablePreKeyCount;
    if (available < _preKeyLowWatermark) {
      await _loadOrEnsurePreKeys();
    }
  }

  /// Lädt den persistierten Signed PreKey bzw. rotiert ihn zeitbasiert
  /// (Audit H-7/E-2 + E-3). Alte Signed PreKeys bleiben zur Entschlüsselung
  /// bereits etablierter Sessions im Store.
  Future<void> _loadOrRotateSignedPreKey() async {
    final activeIdStr = _metaBox.get(_signedPreKeyActiveKey);
    final activeId = int.tryParse(activeIdStr ?? '');

    if (activeId != null) {
      final persisted = _signedPreKeysBox.get(activeId.toString());
      if (persisted != null) {
        try {
          final record = SignedPreKeyRecord.fromSerialized(
            base64Decode(persisted.keyPairJson),
          );
          final age = DateTime.now().millisecondsSinceEpoch - persisted.timestamp;
          // Noch gültig UND im Store vorhanden -> übernehmen.
          if (Duration(milliseconds: age) < _signedPreKeyLifetime &&
              await _store!.containsSignedPreKey(activeId)) {
            await _store!.storeSignedPreKey(activeId, record);
            debugPrint('[EncryptionService] SignedPreKey $activeId geladen.');
            return;
          }
          // Abgelaufen oder nicht mehr im Store: unten neu rotieren.
        } catch (_) {
          await _signedPreKeysBox.delete(activeId.toString());
        }
      }
    }

    // Neuen Signed PreKey erzeugen (Erstinstallation oder Rotation).
    final newId = (activeId ?? 0) + 1;
    final signedPreKey = generateSignedPreKey(_identityKeyPair!, newId);
    await _store!.storeSignedPreKey(newId, signedPreKey);
    await _signedPreKeysBox.put(
      newId.toString(),
      SignalSignedPreKeyRecordAdapter(
        keyId: newId,
        keyPairJson: base64Encode(signedPreKey.serialize()),
        signatureJson: base64Encode(signedPreKey.signature),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _metaBox.put(_signedPreKeyActiveKey, newId.toString());
    debugPrint('[EncryptionService] SignedPreKey $newId erzeugt (Rotation).');
  }

  /// Lädt ALLE persistierten SignedPreKeys aus der Box in den Store
  /// (Neustart-Fix, siehe [_initializeInner]): Alte SignedPreKeys bleiben
  /// zur Entschlüsselung von Sessions ged behalten, die Peers aus einem
  /// älteren Bundle aufgebaut haben. Beschädigte Einträge werden gelöscht.
  Future<void> _reloadAllSignedPreKeys() async {
    var loaded = 0;
    final deadKeys = <dynamic>[];
    for (final key in _signedPreKeysBox.keys) {
      final persisted = _signedPreKeysBox.get(key);
      if (persisted == null) continue;
      try {
        final record = SignedPreKeyRecord.fromSerialized(
          base64Decode(persisted.keyPairJson),
        );
        await _store!.storeSignedPreKey(persisted.keyId, record);
        loaded++;
      } catch (_) {
        deadKeys.add(key);
      }
    }
    for (final key in deadKeys) {
      await _signedPreKeysBox.delete(key);
    }
    debugPrint('[EncryptionService] SignedPreKeys geladen: $loaded');
  }

  /// Holt den AKTIVEN Signed PreKey (höchste/latest ID, siehe Box-Metadaten).
  Future<SignedPreKeyRecord?> getCurrentSignedPreKey() async {
    final activeIdStr = _metaBox.get(_signedPreKeyActiveKey);
    final activeId = int.tryParse(activeIdStr ?? '') ?? 1;
    if (await _store!.containsSignedPreKey(activeId)) {
      return _store!.loadSignedPreKey(activeId);
    }
    return null;
  }

  /// Exportiert das EIGENE öffentliche PreKey-Bundle zur Veröffentlichung am
  /// Server (GET/POST /api/prekeys). Enthält ausschließich öffentliche
  /// Schlüssel - der private Identity-Key verlässt das Gerät niemals.
  ///
  /// Nutzt den Cursor-basierten PreKey-Selektor (mit Vorwärts-Schritt,
  /// Audit H-7/E-1); löst automatisch Rotation aus, wenn der Vorrat knapp wird.
  Future<Map<String, dynamic>> exportPreKeyBundle() async {
    final store = _store!;
    final identityPub = _identityKeyPair!.getPublicKey().serialize();
    // Self-Heal (Fix Publish-Deadlock): Vorrat ggf. erst auffüllen, dann
    // exportieren - sonst wirft ein erschöpfter Pool dauerhaft und das
    // Gerät kann nie (wieder) ein Bundle veröffentlichen.
    await _loadOrEnsurePreKeys();
    final preKey = await getUnusedPreKey();
    if (preKey == null) {
      throw StateError(
        'Keine unbenutzten PreKeys verfügbar. '
        'Rufe _loadOrEnsurePreKeys() vor exportPreKeyBundle() auf.',
      );
    }
    // KRITISCHER FIX (Nachrichten kommen nicht an): Die aktive
    // SignedPreKey-ID liegt seit der Meta-Migration in [_metaBox] (nicht
    // mehr in [_identityBox]). Vorher wurde hier null gelesen und IMMER
    // id 1 exportiert - Bundles mit tatsaechlichem SignedPreKey 2+ waren
    // damit faelschlich als id 1 signiert/advertised, und eingehende
    // PreKey-Nachrichten verweigerten die Entschluesselung
    // ("No such signed prekey").
    final activeIdStr = _metaBox.get(_signedPreKeyActiveKey);
    final activeSignedPreKeyId = int.tryParse(activeIdStr ?? '') ?? 1;
    final signedPreKey = await store.loadSignedPreKey(activeSignedPreKeyId);
    return {
      'identityKeyPublic': base64Encode(identityPub),
      'registrationId': _registrationId,
      'preKeyId': preKey.id,
      'preKeyPublic': base64Encode(preKey.getKeyPair().publicKey.serialize()),
      'signedPreKeyId': activeSignedPreKeyId,
      'signedPreKeyPublic': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signedPreKeySignature': base64Encode(signedPreKey.signature),
    };
  }

  // ==========================================================================
  // Session-Aufbau & Peer-Trust (Audit H-7/E-4)
  // ==========================================================================

  /// Erstellt eine neue Session mit einem Empfänger (Signal Session Builder).
  ///
  /// Wirft [StateError] ('peer_identity_changed'), wenn der Peer bereits
  /// einen ANDEREN Identity-Key im Trust-Store hat - ein unterschobenes
  /// Bundle (kompromittierter Server) wird damit NICHT mehr still
  /// akzeptiert. Der Nutzer muss dem neuen Key explizit per
  /// [resetPeerTrust] zustimmen (Safety-Number-Vergleich im UI).
  Future<void> buildSession(
    String recipientId,
    String recipientIdentityKeyB64,
    String recipientPreKeyB64,
    int recipientPreKeyId,
    String recipientSignedPreKeyB64,
    int recipientSignedPreKeyId,
    String recipientSignedPreKeySignatureB64,
    int recipientRegistrationId,
  ) async {
    final existingEntry = _decodeTrustEntry(recipientId);
    final existingKey = existingEntry?['identityKeyPublic'] as String?;
    if (existingKey != null && existingKey != recipientIdentityKeyB64) {
      throw StateError(
        'peer_identity_changed: Der Identity-Key von $recipientId hat sich '
        'geändert. Safety-Number prüfen und Vertrauen ggf. zurücksetzen.',
      );
    }

    final recipientIdentityKey =
        IdentityKey.fromBytes(base64Decode(recipientIdentityKeyB64), 0);
    final recipientPreKey =
        Curve.decodePoint(base64Decode(recipientPreKeyB64), 0);
    final recipientSignedPreKey =
        Curve.decodePoint(base64Decode(recipientSignedPreKeyB64), 0);
    final recipientSignedPreKeySignature =
        base64Decode(recipientSignedPreKeySignatureB64);

    final address = SignalProtocolAddress(recipientId, 1);
    final sessionBuilder = SessionBuilder.fromSignalStore(_store!, address);
    await sessionBuilder.processPreKeyBundle(
      PreKeyBundle(
        recipientRegistrationId,
        1, // deviceId
        recipientPreKeyId,
        recipientPreKey,
        recipientSignedPreKeyId,
        recipientSignedPreKey,
        recipientSignedPreKeySignature,
        recipientIdentityKey,
      ),
    );

    // Peer-Identity für Safety-Number persistieren (TOFU; weitere
    // Änderungen werden durch den Check oben blockiert).
    await _peerTrustBox.put(recipientId, jsonEncode({
      'identityKeyPublic': recipientIdentityKeyB64,
      'verified': false,
    }));
  }

  /// Setzt den gespeicherten Trust für einen Peer zurück (NUR nach
  /// Nutzer-Bestätigung im "Sicherheitsnummer geändert"-Dialog).
  Future<void> resetPeerTrust(String peerId) async {
    await _peerTrustBox.delete(peerId);
    await _store?.forgetIdentity(peerId);
  }

  Map<String, dynamic>? _decodeTrustEntry(String peerId) {
    final raw = _peerTrustBox.get(peerId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // Safety-Numbers (Audit B2 / N-6)
  // ==========================================================================

  /// Berechnet die Safety-Number zwischen zwei öffentlichen Identity-Keys.
  ///
  /// DEPRECATED-Pfad ohne Stable-Identifiers (nur noch für Tests):
  /// 5200-fach iteriertes SHA-512 über die byte-lexikografisch sortierte
  /// Konkatenation beider öffentlicher Keys; die ersten 15 Bytes werden
  /// auf je 2 Dezimalziffern abgebildet → 30 Ziffern in 6 Blöcken à 5.
  @visibleForTesting
  static String computeSafetyNumber(Uint8List ourIdentityPub, Uint8List theirIdentityPub) {
    // Kanonische Reihenfolge: byte-lexikografisch kleinerer Key zuerst
    // (unabhängig davon, wer die Nummer berechnet).
    final first = Uint8List.fromList(ourIdentityPub);
    final second = Uint8List.fromList(theirIdentityPub);
    final Uint8List a;
    final Uint8List b;
    if (_compareBytes(first, second) <= 0) {
      a = first;
      b = second;
    } else {
      a = second;
      b = first;
    }

    var digest = sha512.convert(a + b).bytes;
    for (var i = 1; i < 5200; i++) {
      digest = sha512.convert(digest).bytes;
    }

    final buffer = StringBuffer();
    for (var i = 0; i < 15; i++) {
      buffer.write((digest[i] % 100).toString().padLeft(2, '0'));
    }
    final digits = buffer.toString();
    return RegExp(r'.{5}')
        .allMatches(digits)
        .map((m) => digits.substring(m.start, m.end))
        .join(' ');
  }

  static int _compareBytes(Uint8List x, Uint8List y) {
    final len = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < len; i++) {
      if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
    }
    return x.length.compareTo(y.length);
  }

  /// Berechnet die Safety-Number gemäß Signal-Standard
  /// ([NumericFingerprintGenerator], Audit N-6) mit den STABLE IDENTIFIERS
  /// beider User-IDs - das vetted Verfahren statt eines eigenen Schemas.
  String fingerprintSafetyNumber(String peerId, String peerIdentityKeyB64) {
    final generator = NumericFingerprintGenerator(5200);
    final fp = generator.createFor(
      0,
      Uint8List.fromList(utf8.encode(localUserId ?? '')),
      _identityKeyPair!.getPublicKey(),
      Uint8List.fromList(utf8.encode(peerId)),
      IdentityKey.fromBytes(base64Decode(peerIdentityKeyB64), 0),
    );
    return fp.displayableFingerprint.getDisplayText();
  }

  /// Safety-Number für [peerId] (oder `null`, wenn noch keine Session bzw.
  /// keine gespeicherte Peer-Identity existiert). Bevorzugt der
  /// Signal-Standard-Fingerprint (N-6); fällt ohne bekannte eigene User-ID
  /// auf das Legacy-Schema zurück.
  String? safetyNumberFor(String peerId) {
    final peerKeyB64 = _decodeTrustEntry(peerId)?['identityKeyPublic'] as String?;
    if (peerKeyB64 == null || _identityKeyPair == null) return null;
    if (localUserId != null) {
      try {
        return fingerprintSafetyNumber(peerId, peerKeyB64);
      } catch (_) {
        // Fall through zum Legacy-Schema.
      }
    }
    return computeSafetyNumber(
      _identityKeyPair!.getPublicKey().serialize(),
      base64Decode(peerKeyB64),
    );
  }

  /// True, wenn die Peer-Identity per Out-of-Band-Vergleich bestätigt wurde.
  bool isPeerIdentityVerified(String peerId) =>
      _decodeTrustEntry(peerId)?['verified'] == true;

  /// Markiert die Peer-Identity als verifiziert (nach gemeinsamem Vergleich
  /// der Safety-Number über einen zweiten Kanal) bzw. entfernt die
  /// Verifikation.
  Future<void> setPeerIdentityVerified(String peerId, bool verified) async {
    final entry = _decodeTrustEntry(peerId);
    if (entry == null) return;
    await _peerTrustBox.put(peerId, jsonEncode({
      'identityKeyPublic': entry['identityKeyPublic'],
      'verified': verified,
    }));
  }

  // ==========================================================================
  // Encrypt / Decrypt
  // ==========================================================================

  /// Verschlüsselt eine Nachricht für einen Empfänger.
  Future<CiphertextMessage> encryptMessage(
      String recipientId, String plaintext) async {
    final address = SignalProtocolAddress(recipientId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    return sessionCipher.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
  }

  /// Entschlüsselt eine empfangene Nachricht.
  Future<String> decryptMessage(
      String senderId, CiphertextMessage message) async {
    final address = SignalProtocolAddress(senderId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    late final Uint8List plaintext;
    if (message is PreKeySignalMessage) {
      plaintext = await sessionCipher.decrypt(message);
    } else if (message is SignalMessage) {
      plaintext = await sessionCipher.decryptFromSignal(message);
    } else {
      throw ArgumentError('Unbekannter Nachrichtentyp: ${message.getType()}');
    }
    return utf8.decode(plaintext);
  }

  /// Verschlüsselt Binärdaten (Bilder, Sprachnachrichten).
  Future<CiphertextMessage> encryptBinary(
      String recipientId, Uint8List data) async {
    final address = SignalProtocolAddress(recipientId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    return sessionCipher.encrypt(data);
  }

  /// Entschlüsselt Binärdaten.
  Future<Uint8List> decryptBinary(
      String senderId, CiphertextMessage message) async {
    final address = SignalProtocolAddress(senderId, 1);
    final sessionCipher = SessionCipher.fromStore(_store!, address);
    if (message is PreKeySignalMessage) {
      return sessionCipher.decrypt(message);
    } else if (message is SignalMessage) {
      return sessionCipher.decryptFromSignal(message);
    }
    throw ArgumentError('Unbekannter Nachrichtentyp: ${message.getType()}');
  }

  /// Prüft, ob eine Session mit einem Nutzer existiert.
  Future<bool> hasSession(String userId) {
    final address = SignalProtocolAddress(userId, 1);
    return _store!.containsSession(address);
  }

  /// Löscht alle Daten (z. B. bei Logout/Account-Löschung).
  Future<void> clearAllData() async {
    await _identityBox.clear();
    await _sessionBox.clear();
    await _peerTrustBox.clear();
    await _preKeysBox.clear();
    await _signedPreKeysBox.clear();
    await _identityTrustBox.clear();
    await _metaBox.clear();
    _identityKeyPair = null;
    _store = null;
    _preKeyIndex = 0;
  }

  /// Erstellt ein AES-256-GCM-verschlüsseltes Backup der Identität.
  ///
  /// Die kryptographische Logik (PBKDF2-Key-Derivation + AES-256-GCM) ist
  /// in [BackupCrypto] gekapselt; dieser Service liefert nur den zu
  /// sichernden Identitäts-Klartext.
  Future<String?> createEncryptedBackup(String password) async {
    try {
      final identityB64 = _identityBox.get(_identityKey)?.identityKeyPairJson;
      if (identityB64 == null) return null;

      final backup = jsonEncode({
        'identity': identityB64,
        'registrationId': _registrationId,
      });
      return BackupCrypto.encrypt(backup, password);
    } catch (e) {
      debugPrint('[EncryptionService] Backup-Verschlüsselung fehlgeschlagen: $e');
      return null;
    }
  }

  /// Entschlüsselt und stellt ein Backup wieder her.
  Future<void> restoreFromBackup(String backupBase64, String password) async {
    final backupJson = BackupCrypto.decrypt(backupBase64, password);
    final backup = jsonDecode(backupJson) as Map<String, dynamic>;

    if (backup['identity'] != null) {
      await _identityBox.put(
        _identityKey,
        SignalIdentityKeyPairAdapter(
          identityKeyPairJson: backup['identity'] as String,
        ),
      );
    }
    if (backup['registrationId'] != null) {
      _registrationId = backup['registrationId'] as int;
      await _metaBox.put(_registrationIdKey, _registrationId.toString());
    }
    await initialize(); // Neu laden
  }

  Future<void> dispose() async {
    await _identityBox.close();
    await _sessionBox.close();
    await _peerTrustBox.close();
    await _preKeysBox.close();
    await _signedPreKeysBox.close();
    await _identityTrustBox.close();
    await _metaBox.close();
  }
}

/// Provider für den [EncryptionService].
///
/// Startet die asynchrone Initialisierung im Hintergrund und schlieüt den
/// Service beim Dispose ordnungsgemäü.
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final service = EncryptionService();
  // Initialisierung asynchron starten; Fehler abfangen, damit keine
  // unhandled async exception entsteht (sonst Crash im Release).
  Future.microtask(() => service.initialize()).catchError((e) {
    debugPrint('[EncryptionService] Initialisierung fehlgeschlagen: $e');
  });
  ref.onDispose(service.dispose);
  return service;
});
