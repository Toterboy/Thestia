import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/utils/peer_id.dart';

/// Vermittelt den Aufbau einer Ende-zu-Ende-Session zum Kommunikationspartner.
///
/// Der Ablauf (Signal Protocol "PreKey"-Modell):
///   1. Wir laden das öffentliche PreKey-Bundle des Partners vom Server
///      (Supabase Edge Function `prekeys`). Der Server speichert NUR
///      öffentliche Schlüssel - kein Geheimnis verlässt je das Gerät.
///   2. Daraus bauen wir lokal eine Signal-Session (PreKeyBundle-Verarbeitung).
///   3. Danach können wir Nachrichten mit [EncryptionService.encryptMessage]
///      verschlüsseln; der Partner entschlüsselt sie mit seinem privaten
///      Schlüssel. Der Server sieht davon nichts (auch nicht bei TURN-Relay).
///
/// Wir cachen etablierte Sessions pro Peer, um wiederholte Bundles-Calls
/// (und PreKey-Verbrauch) zu vermeiden.
class PreKeyService {
  PreKeyService(this._encryption);

  final EncryptionService _encryption;

  final Map<String, Future<void>> _pending = {};
  final Set<String> _established = {};

  /// Stellt sicher, dass eine E2E-Session zu [peerId] existiert.
  /// Idempotent und thread-sicher (parallele Calls teilen den Aufbau).
  ///
  /// KRITISCHER FIX (Nachrichten waren inkompatibel verschlüsselt):
  /// Wenn bereits eine Session existiert — z. B. automatisch aus der
  /// Verarbeitung einer empfangenen PreKey-Nachricht — wird diese
  /// VERWENDET statt eine neue aus dem Bundle zu bauen. Sonst über-
  /// schreibt der Bundle-Fetch die bestehende Session, und die beiden
  /// Geräte verschlüsseln mit UNTERSCHIEDLICHEN Sessions, die der
  /// Empfänger nicht entschlüsseln kann ("Nachrichten kommen nicht an").
  ///
  /// Nur wenn KEINE Session existiert (erster Kontakt), wird das
  /// PreKey-Bundle geholt und die Session aufgebaut.
  Future<void> ensureSession(String peerId) async {
    if (_established.contains(peerId)) return;
    // Initialisierung abwarten, BEVOR der Store angefasst wird: hasSession
    // dereferenziert den Store, der erst nach initialize() existiert
    // (Fix: Null-Crash bei Kaltstart mit sofortigem Chat-Öffnen).
    await _encryption.initialized;
    // Bereits vorhandene Session (z. B. aus empfangener PreKey-Nachricht)
    // direkt verwenden statt sie zu überschreiben.
    if (await _encryption.hasSession(peerId)) {
      _established.add(peerId);
      return;
    }
    final future = _pending[peerId] ??= _build(peerId);
    try {
      await future;
      _established.add(peerId);
    } finally {
      _pending.remove(peerId);
    }
  }

  Future<void> _build(String peerId) async {
    await _encryption.initialized;

    // Peer-ID validieren, bevor sie in den Function-Pfad eingebaut wird
    // (Audit M1: Pfad-Manipulation über manipulierte QR-Payloads).
    if (!isValidPeerId(peerId)) {
      throw StateError('Ungültige Peer-ID (keine UUID): Verbindung abgelehnt.');
    }

    // PreKey-Bundle des Partners via Supabase Edge Function abrufen.
    // Bei 404/503 kurz warten und wiederholen (z. B. Bundle noch nicht hochgeladen).
    //
    // WICHTIG (Zufallschat-Fix): functions.invoke WIRFT bei non-2xx eine
    // FunctionsHttpException (statt eine Response zu liefern) - ohne
    // try/catch waren Retry- und 404-Logik toter Code und der Roh-Fehler
    // landete im UI ("Connection to partner failed.
    // FunctionsHttpException...").
    const maxAttempts = 3;
    const backoff = Duration(seconds: 1);
    dynamic lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future.delayed(backoff * attempt);
      }

      int status;
      Map<String, dynamic>? bundle;
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'prekeys/${Uri.encodeComponent(peerId)}',
          method: HttpMethod.get,
        );
        status = response.status;
        if (status == 200) {
          bundle = (response.data as Map).cast<String, dynamic>();
        }
      } on FunctionException catch (e) {
        status = e.status;
        // Server-Detail (z. B. "Datenbankfehler beim Abruf") nur im
        // Debug-Log - im UI steht die generische Meldung unten.
        if (kDebugMode) {
          debugPrint('[PreKey] Bundle-Abruf Status $status: ${e.details}');
        }
        if (status == 0) {
          // Kein Transport (offline/DNS) - wie transient behandeln.
          lastError = 'keine Verbindung';
          continue;
        }
      }

      if (status == 200 && bundle != null) {
        await _encryption.buildSession(
          peerId,
          bundle['identityKeyPublic'] as String,
          bundle['preKeyPublic'] as String,
          bundle['preKeyId'] as int,
          bundle['signedPreKeyPublic'] as String,
          bundle['signedPreKeyId'] as int,
          bundle['signedPreKeySignature'] as String,
          bundle['registrationId'] as int,
        );
        return;
      }

      // Explizite 404-Behandlung (C-04): Der Partner hat (noch) kein
      // PreKey-Bundle hochgeladen — ein Retry mit Backoff ändert daran
      // nichts und verzögert nur die Fehlermeldung. Sofort abbrechen.
      if (status == 404) {
        throw StateError(
          'Der Partner hat noch kein verschlüsseltes Schlüssel-Bundle '
          'veröffentlicht (404). Dessen Gerät benötigt die aktuelle '
          'App-Version und einen Neustart der App - danach verbindet sich '
          'der Chat automatisch.',
        );
      }

      // Transiente Fehler (503 "loading", 500er, Netzprobleme etc.):
      // wiederholen. Fehler-Details nicht ins UI/Log übernehmen, da sie
      // PII enthalten können (z. B. user_id). Stattdessen generische
      // Meldung.
      lastError = status;
    }

    // Serverfehler: meist veraltete deployte prekeys-Function (".single()"
    // wirft bei fehlendem Bundle 500 statt 404) oder fehlende prekeys-
    // Tabelle. Handlungsorientierte Meldung statt nacktem Status.
    if (lastError == 500) {
      throw StateError(
        'Serverfehler beim Laden des PreKey-Bundles (500). Vermutlich ist '
        'die deployte prekeys-Edge-Function veraltet oder die '
        'prekeys-Tabelle fehlt. Bitte die Function neu deployen '
        '(supabase functions deploy prekeys) und erneut versuchen.',
      );
    }
    throw StateError(
        'PreKey Bundle für $peerId konnte nicht geladen werden (Status: $lastError).',
    );
  }

  /// Lädt das EIGENE PreKey-Bundle hoch (einmalig nach Registrierung/Login).
  /// Damit andere Nutzer Sessions zu UNS aufbauen können.
  Future<void> publishOwnPreKeys(Map<String, dynamic> bundle) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'prekeys',
        body: bundle,
      );
      return;
    } on FunctionException catch (e) {
      // invoke wirft bei non-2xx (kein Response-Check möglich).
      final detail = e.details is Map
          ? (e.details as Map)['error'] ?? 'Unbekannter Fehler'
          : e.details ?? e.status;
      throw StateError(
          'PreKey Bundle konnte nicht hochgeladen werden: $detail');
    }
  }

  /// Komfort-Variante: exportiert das Bundle direkt aus dem
  /// [EncryptionService] und lädt es hoch.
  Future<void> publishOwnPreKeysFromStore() async {
    final bundle = await _encryption.exportPreKeyBundle();
    await publishOwnPreKeys(bundle);
    // PreKey-Rotation prüfen: falls Vorrat knapp, nachgenerieren.
    await _encryption.maybeRotatePreKeys();
  }

  /// Audit H-7/E-3: Stellt sicher, dass ein eigenes Bundle auf dem Server
  /// liegt - der fehlende Aufruf nach Registrierung/Login war der Grund,
  /// warum E2E-Aufbau für Normalnutzer fehlschlug (404 beim Bundle-Fetch).
  ///
  /// Wird nach Login/Session-Restore ([AuthNotifier._syncFromServer])
  /// aufgerufen. Fail-open: Eine fehlgeschlagene Prüfung blockiert den
  /// Login nicht - der Grund wird aber JETZT geloggt (vorher stummes
  /// Catch-All: Ein fehlgeschlagener Upload war von außen unsichtbar).
  ///
  /// KRITISCHER FIX (Nachrichten kommen nicht an): Das Bundle wurde nur
  /// HOCHGELADEN, wenn es fehlte - aber der One-Time-PreKey im Bundle wird
  /// vom ERSTEN eingehenden PreKey-Verbrauch konsumiert und danach aus
  /// dem Store entfernt. Ein Peer, der später (z. B. nach App-Neustart)
  /// eine NEUE Session aufbaut, bekommt das STALE Bundle mit dem
  /// konsumierten PreKey -> eingehende erste Nachrichten sind unlesbar
  /// ("No such prekey"). Deshalb: Bei JEDEM Aufruf ein FRISCHES Bundle
  /// veröffentlichen (neuer unbenutzter One-Time-Key). Drosselung auf
  /// einen Upload pro Minute (connect() ruft hier unawaited auf).
  DateTime? _lastPublishAt;

  /// Setzt Session-Cache und Publish-Drossel zurück (Logout/
  /// Kontowechsel, Audit): Sessions des Vorgängers dürfen unter dem
  /// neuen Konto nie wiederverwendet werden (Identitätstrennung).
  void reset() {
    _established.clear();
    _pending.clear();
    _lastPublishAt = null;
  }

  Future<void> ensureOwnBundlePublished() async {
    try {
      await _encryption.initialized;
      final myId = Supabase.instance.client.auth.currentUser?.id;
      if (myId == null || !isValidPeerId(myId)) return;

      // Drosselung: max. ein frisches Bundle pro Minute je App-Session.
      final last = _lastPublishAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(minutes: 1)) {
        return;
      }
      _lastPublishAt = DateTime.now();

      await publishOwnPreKeysFromStore();
      if (kDebugMode) {
        debugPrint('[PreKey] Eigenes Bundle frisch veröffentlicht ($myId).');
      }
    } catch (e) {
      // Fail-open wie dokumentiert: Der Login wird nicht blockiert; beim
      // nächsten Start wird erneut geprüft. Grund loggen (404-Diagnose).
      debugPrint('[PreKey] Eigenes Bundle veröffentlichen FEHLGESCHLAGEN: $e');
    }
  }

  /// Entfernt eine (z. B. beendete) Session aus dem Cache.
  void forget(String peerId) => _established.remove(peerId);
}

/// Provider für den [PreKeyService].
final preKeyServiceProvider = Provider<PreKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return PreKeyService(encryption);
});
