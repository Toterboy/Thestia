import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/utils/common/json_leser.dart';

/// Eine abgeholte Relay-Nachricht (entschlüsselt, versandbereit zur Anzeige).
class RelayMessage {
  const RelayMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.kind,
    required this.createdAt,
  });

  /// Zeilen-ID (für [RelayService.ack] + Deduplizierung als `relay_<id>`).
  final int id;
  final String senderId;
  final String text;

  /// 'text' | 'icebreaker'.
  final String kind;

  final DateTime createdAt;

  factory RelayMessage.fromJson(Map<String, dynamic> json) {
    return RelayMessage(
      // BEFUND (22.11.2026, Fuzzing): Die Zeile kommt ueber den Server -
      // ihr Inhalt stammt von der GEGENSEITE. Die Casts hier warfen bei
      // jedem falschen Typ.
      id: intOf(json, ['id']) ?? 0,
      senderId: textOf(json, ['sender']) ?? '',
      text: textOf(json, ['text']) ?? '',
      kind: textOf(json, ['kind']) ?? 'text',
      createdAt: dateOf(json, ['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Relay-Fallback für den P2P-Chat (v0.9.1, Migration 093).
///
/// Wenn der DataChannel nicht offen ist (Partner offline / NAT-Probleme),
/// werden Textnachrichten Signal-verschlüsselt serverseitig
/// zwischengespeichert. Der Empfänger holt sie beim Chat-Öffnen (plus
/// Polling) ab und entschlüsselt lokal. Der Server sieht nur Ciphertext -
/// E2E bleibt gewahrt. Bilder/Audio bleiben P2P-only (zu groß für Relay).
class RelayService {
  RelayService(this._ref);

  final Ref _ref;

  EncryptionService get _encryption => _ref.read(encryptionServiceProvider);
  PreKeyService get _prekey => _ref.read(preKeyServiceProvider);

  /// Verschlüsselt [text] für [peerId] und legt ihn im Relay ab.
  /// Wirft bei Fehler (Aufrufer fällt auf Outbox zurück).
  Future<void> storeText({
    required String peerId,
    required String text,
    String kind = 'text',
  }) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('Keine Verbindung');
    }
    await _prekey.ensureSession(peerId);
    final encrypted = await _encryption.encryptMessage(peerId, text);
    await SupabaseService.client.rpc(
      'relay_store',
      params: {
        'p_receiver': peerId,
        'p_ciphertext': base64Encode(encrypted.serialize()),
        'p_msg_type': encrypted.getType(),
        'p_kind': kind,
      },
    );
  }

  /// Holt eigene unzugestellte Nachrichten ab, entschlüsselt sie und
  /// bestätigt (löscht) die zugestellten Zeilen.
  ///
  /// [from]: Nur Zeilen dieses Absenders verwenden und bestätigen -
  /// Zeilen ANDERER Chats/Partner bleiben unangetastet liegen, bis ihr
  /// Chat sie abholt.
  ///
  /// KRITISCHER FIX (Nachrichten wurden "verschluckt"): Entschlüsselungs-
  /// fehler löschen die Nachricht NICHT mehr. Sie bleibt im Relay liegen
  /// und wird beim nächsten Poll erneut versucht (z. B. nachdem die
  /// Session wiederhergestellt wurde). Erst nach 5 Fehlversuchen wird
  /// aufgegeben (Endlosschleifen-Schutz).
  ///
  /// Die separate Signal-Session zum Absender wird beim EMPFANGEN nicht
  /// mehr aufgebaut (ensureSession) — sie ist für das Entschlüsseln nicht
  /// nötig (die Session entsteht automatisch beim Verarbeiten der
  /// PreKey-Nachricht) und konnte bei fehlendem Bundle die gesamte
  /// Zustellung blockieren.
  static const int _maxDecryptRetries = 5;
  final Map<int, int> _decryptFailures = {};

  Future<List<RelayMessage>> fetchPending({
    String? from,
    bool ack = true,
  }) async {
    if (!SupabaseService.isInitialized) return const [];
    final response = await SupabaseService.client.rpc('relay_fetch');
    final rows = response is List ? response : const <dynamic>[];
    final out = <RelayMessage>[];
    final ackIds = <int>[];
    for (final row in rows) {
      // BEFUND (22.11.2026, Fuzzing): Die Relay-Zeile kommt vom Server,
      // ihr Inhalt von der GEGENSEITE. Die Casts hier warfen bei jedem
      // falschen Typ - im catch-Block selbst (Zeile unten) hat sogar der
      // Fehlerpfad geworfen, wenn die ID keine Zahl war.
      final map = row is Map
          ? Map<String, dynamic>.from(row)
          : <String, dynamic>{};
      final rowId = intOf(map, ['id']) ?? -1;
      try {
        // Fremde Absender (anderer Chat) überspringen, OHNE sie zu
        // bestätigen - ihr Chat holt sie später selbst ab.
        final senderId = textOf(map, ['sender']) ?? '';
        if (from != null && senderId != from) continue;
        final cipherText = textOf(map, ['ciphertext']);
        if (cipherText == null || cipherText.isEmpty) {
          throw const FormatException('keine Chiffre');
        }
        final cipherBytes = base64Decode(cipherText);
        final msgType = intOf(map, ['msgType']) ?? CiphertextMessage.prekeyType;
        final CiphertextMessage signalMessage =
            msgType == CiphertextMessage.prekeyType
            ? PreKeySignalMessage(cipherBytes)
            : SignalMessage.fromSerialized(cipherBytes);
        // KEIN ensureSession hier: Für das Entschlüsseln wird die
        // Session automatisch aus der PreKey-Nachricht aufgebaut. Ein
        // fehlgeschlagener Bundle-Fetch würde sonst die Nachricht
        // blockieren.
        final text = await _encryption.decryptMessage(senderId, signalMessage);
        out.add(RelayMessage.fromJson({...map, 'text': text}));
        ackIds.add(rowId);
        _decryptFailures.remove(rowId);
      } catch (e) {
        // Entschlüsselung fehlgeschlagen: Nachricht bleibt im Relay!
        // Sie wird beim nächsten Poll erneut versucht. Erst nach
        // [_maxDecryptRetries] Fehlversuchen wird sie gelöscht
        // (sonst wächst das Relay endlos, wenn die Session dauerhaft
        // kaputt ist).
        if (rowId < 0) continue;
        final failures = (_decryptFailures[rowId] ?? 0) + 1;
        _decryptFailures[rowId] = failures;
        if (failures >= _maxDecryptRetries) {
          // Dauerhaft unlesbar: jetzt erst löschen.
          ackIds.add(rowId);
          _decryptFailures.remove(rowId);
          debugPrint(
            '[Relay] Nachricht $rowId nach $failures Versuchen '
            'endgültig verworfen: $e',
          );
        } else {
          debugPrint(
            '[Relay] Entschlüsselung fehlgeschlagen ($failures/'
            '$_maxDecryptRetries), Nachricht bleibt im Relay: $e',
          );
        }
      }
    }
    // Ack ist OPT-IN (GlobalRelayInbox ackt selektiv NUR routierte Zeilen,
    // damit nicht zustellbare Nachrichten z. B. aus der Dating-Hour im
    // Relay bleiben, bis ihr Screen sie abholt).
    if (ack && ackIds.isNotEmpty) {
      await ackRows(ackIds);
    }
    return out;
  }

  /// Löscht bestätigte Relay-Zeilen (relay_ack). Sichtbar für Aufrufer,
  /// die selbst selektiv acken (z. B. der globale Relay-Eingang).
  Future<void> ackRows(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await SupabaseService.client.rpc('relay_ack', params: {'p_ids': ids});
    } catch (e) {
      debugPrint('[Relay] Ack fehlgeschlagen: $e');
    }
  }
}

/// Provider für den [RelayService].
final relayServiceProvider = Provider<RelayService>((ref) {
  return RelayService(ref);
});
