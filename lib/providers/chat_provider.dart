import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/models/match.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/notification_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';

/// Match-ID des aktuell im VORDERGRUND geöffneten Chats (sonst null).
///
/// Die Chat-Screens setzen den Wert beim Einstieg und löschen ihn im
/// dispose. [ChatNotifier] nutzt ihn, um die Lokal-Benachrichtigung für
/// eingehende Nachrichten zu UNTERDRÜCKEN, wenn die Nachricht gerade
/// sichtbar ist (Nutzerwunsch: "keine Benachrichtigung, wenn ich die
/// Nachricht schon sehe").
final activeChatIdProvider = StateProvider<String?>((ref) => null);

/// Partner-ID des aktuell geöffneten Chats (paralleler Zustand zu
/// [activeChatIdProvider]): Der FCM-Foreground-Handler kennt nur die
/// Absender-UUID aus den Push-Metadaten, nicht die lokale Match-ID -
/// die Unterdrückung für Server-Pushes läuft deshalb über diese ID.
final activeChatPeerIdProvider = StateProvider<String?>((ref) => null);

/// True, wenn die App gerade im Vordergrund ist.
bool appInForeground() =>
    WidgetsBinding.instance.lifecycleState == null ||
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

/// True, wenn für einen Push von [peerId] gerade die Benachrichtigung
/// unterdrückt werden soll (Chat mit dem Absender offen + Vordergrund).
bool shouldSuppressNotificationForPeer(WidgetRef? ref, String peerId) {
  if (ref == null || peerId.isEmpty) return false;
  final openPeer = ref.read(activeChatPeerIdProvider);
  return openPeer != null && openPeer == peerId && appInForeground();
}

/// Verwaltet Matches und Chats. Reagiert auf Likes aus dem Swipe.
class ChatNotifier extends StateNotifier<List<Match>> {
  ChatNotifier(this._chat) : super(_chat.getMatches());

  final ChatService _chat;

  /// Opt-in (v0.8.0): verschlüsselter lokaler Chat-Verlauf.
  /// [limit]: null = kompletter Verlauf, sonst max. N Nachrichten.
  void setHistoryPersistence(bool enabled, {int? limit}) =>
      _chat.setHistoryPersistence(enabled, limit: limit);

  /// Besitzerwechsel (Login/Logout, Audit Kontowechsel): Trennt Verlauf,
  /// Kontakte und State pro Konto. Bei Login werden die eigenen
  /// QR-Kontakte wiederhergestellt, bei Logout (null) wird nur geleert.
  Future<void> setOwner(String? userId) async {
    await _chat.setOwner(userId);
    if (userId == null) {
      state = [];
    } else {
      await _chat.restoreQrContacts();
      state = _chat.getMatches();
    }
  }

  /// Löscht alle eigenen Chat-Boxen vom Gerät (Account-Löschung).
  Future<void> deleteOwnedData(String userId) async {
    await _chat.deleteOwnedData(userId);
    state = [];
  }

  /// Lädt den gespeicherten Verlauf eines Matches (Opt-in aktiv).
  /// Aktualisiert nach dem Hydrate den State, damit die UI SOFORT neu
  /// zeichnet (Fix "Verlauf lädt nicht direkt": Das Hydrate füllte nur
  /// die interne Map, ohne den Provider-State zu berühren - der Chat
  /// blieb leer, bis ein anderes Event ein Rebuild auslöste).
  Future<void> hydrateHistory(String matchId) async {
    await _chat.hydrateHistory(matchId);
    state = _chat.getMatches();
  }

  /// Erzeugt ein Match aus einem gelikten Profil.
  void addMatch(UserProfile partner, {WidgetRef? ref}) {
    _chat.createMatch(partner);
    state = _chat.getMatches();
    if (ref != null) {
      _notifyMatch(partner, ref);
    }
  }

  /// Findet oder erstellt einen Chat mit einem Nutzer (via QR-Scan).
  ///
  /// QR-Kontakte sind PERSISTENT ("gespeicherte Profile", max.
  /// [ChatService.maxQrContacts]) - sie überleben den App-Neustart, damit
  /// man offline gescannte Personen später anschreiben kann.
  ///
  /// Prüft zuerst, ob bereits ein Match/Chat mit diesem Nutzer existiert
  /// (per Partner-ID - die Match-ID ist lokal generiert und beim Scan noch
  /// unbekannt). Gibt das MATCH zurück (nicht das Partner-Profil): Die
  /// Chat-Route braucht die Match-ID. Vorher wurde die Partner-ID
  /// navigiert, wodurch der Chat-Detail-Screen "Dieser Chat existiert
  /// nicht mehr" zeigte.
  ///
  /// Liefert `null`, wenn das Maximum erreicht ist - der Aufrufer bietet
  /// dann an, zuerst einen gespeicherten Kontakt zu löschen.
  Match? findOrCreateMatch(String peerId) {
    // Prüfe, ob bereits ein Chat existiert.
    final existing = _chat.getMatchByPartnerId(peerId);
    if (existing != null) return existing;

    // Neuen QR-Kontakt anlegen (Name/Profil lädt der Screen asynchron
    // vom Server nach; offline bleibt der Platzhalter "Unbekannt").
    final profile = UserProfile(id: peerId, name: 'Unbekannt', bio: '');
    final match = _chat.createQrContact(profile);
    if (match != null) {
      state = _chat.getMatches();
    }
    return match;
  }

  /// Aktualisiert das Partner-Profil eines Matches (z. B. QR-Kontakt, der
  /// nachträglich vom Server mit echtem Namen/Vorstellung befüllt wird).
  void updatePartner(String matchId, UserProfile partner) {
    _chat.updatePartner(matchId, partner);
    state = _chat.getMatches();
  }

  /// Entfernt einen persistenten QR-Kontakt ("Gespeichertes Profil
  /// löschen"): Match, Verlauf und lokale Speicherung.
  void deleteQrContact(String matchId) {
    _chat.deleteQrContact(matchId);
    state = _chat.getMatches();
  }

  /// Legt ein lokales Match mit der SERVER-Match-ID an (für Chats aus dem
  /// Funken-Tab, die nur serverseitig existieren). Existiert bereits eines,
  /// wird es zurückgegeben.
  Match? restoreServerMatch(
      String matchId, UserProfile partner, DateTime matchedAt) {
    final match = _chat.restoreServerMatch(matchId, partner, matchedAt);
    if (match != null) {
      state = _chat.getMatches();
    }
    return match;
  }

  /// Stellt persistierte QR-Kontakte nach dem App-Start wieder her
  /// ("gespeicherte Profile" überleben den Neustart).
  Future<void> restorePersistedQrContacts() async {
    await _chat.restoreQrContacts();
    state = _chat.getMatches();
  }

  /// QR-Kontakte aus dem Speicher (für den Datenexport): enthält die
  /// ORIGINAL-Match-IDs, damit importierte Verläufe wieder zuordnenbar
  /// sind.
  List<Map<String, String>> exportQrContacts() =>
      _chat.exportQrContacts();

  /// Liefert Nachrichten eines Matches.
  List<Message> messagesFor(String matchId) => _chat.getMessages(matchId);

  /// Hängt eine (echte P2P-)Nachricht an, ohne Mock-Auto-Reply auszulösen.
  /// Wird für gesendete UND empfangene Nachrichten des E2E-Chats genutzt.
  void addMessage(String matchId, Message msg, {WidgetRef? ref}) {
    _chat.addMessage(matchId, msg);
    state = _chat.getMatches();
    if (ref != null) {
      _maybeNotifyMessage(matchId, msg, ref);
    }
  }

  /// Liefert ein einzelnes Match anhand seiner ID.
  Match? getMatchById(String matchId) => _chat.getMatchById(matchId);

  /// Markiert Nachrichten eines Matches als gelesen.
  void markRead(String matchId) {
    _chat.markRead(matchId);
    state = _chat.getMatches();
  }

  /// Löst ein Match auf (entfernt Match und zugehörige Nachrichten).
  ///
  /// Gibt `true` zurück, wenn das Match erfolgreich gelöst wurde.
  bool dissolveMatch(String matchId) {
    final success = _chat.dissolveMatch(matchId);
    if (success) {
      state = _chat.getMatches();
    }
    return success;
  }

  /// Setzt ein Match vollständig zurück (L): verwirft alten Chat-State und
  /// legt ggf. ein neues, leeres Match an.
  void resetMatch(String matchId, {UserProfile? partner}) {
    _chat.resetMatch(matchId, partner: partner);
    state = _chat.getMatches();
  }

  void _maybeNotifyMessage(String matchId, Message msg, WidgetRef ref) {
    // Nur für eingehende Nachrichten (NICHT von mir selbst). Die ID kommt
    // aus der Supabase-Session; Demo-Fallback nur für den lokalen Modus
    // (Fix: AppConstants-Demo-ID kippte die Erkennung bei Session-Lücken).
    final myId = SupabaseService.currentUser?.id ?? AppConstants.currentUserId;
    if (msg.isFrom(myId)) return;
    final match = _chat.getMatchById(matchId);
    if (match == null) return;
    // NUTZERWUNSCH: Kein Notification-Ping, wenn der Chat GEÖFFNET ist und
    // die Nachricht gerade auf dem Bildschirm erscheint. Im Hintergrund
    // (App pausiert) zeigt die System-Benachrichtigung die Nachricht an.
    final open = ref.read(activeChatIdProvider);
    if (open != null && open == matchId && appInForeground()) return;
    ref.read(notificationServiceProvider).showMessageNotification(
      id: matchId.hashCode ^ (DateTime.now().millisecondsSinceEpoch & 0xFFFFFF),
      title: match.partner.name,
      body: msg.text,
      ref: ref,
    );
  }

  void _notifyMatch(UserProfile partner, WidgetRef ref) {
    ref.read(notificationServiceProvider).showMatchNotification(
      id: partner.id.hashCode,
      title: 'Neuer Funke!',
      body: 'Du und ${partner.name} haben sich gegenseitig geliked 🎉',
      ref: ref,
    );
  }
}

/// Provider für den Chat-Service.
///
/// WICHTIG: Chat-Nachrichten werden standardmäßig NICHT persistiert
/// (Chats sind E2E + P2P). Der Nutzer kann im Settings-Screen den
/// VERSCHLÜSSELTEN lokalen Verlauf aktivieren (Opt-in, SecureHive) -
/// dann sichert [ChatService] die letzten 200 Nachrichten AES-256
/// verschlüsselt auf dem Gerät.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

/// Provider für Matches & Nachrichten.
final chatProvider = StateNotifierProvider<ChatNotifier, List<Match>>((ref) {
  final service = ref.watch(chatServiceProvider);
  final notifier = ChatNotifier(service);
  // Opt-in-Einstellung (Geräte-lokal) beim Start anwenden - fail-safe
  // gekapselt, damit Tests/Container ohne localStorage nicht brechen.
  unawaited(() async {
    try {
      final storage = ref.read(localStorageProvider);
      final enabled = await storage.getBool('chat_history_local') ?? true;
      final limitRaw = await storage.getBool('chat_history_all');
      final limit = (limitRaw ?? true) ? null : 200;
      service.setHistoryPersistence(enabled, limit: limit);
    } catch (_) {
      // Ohne Storage läuft der Chat einfach ohne Verlauf.
    }
    // Persistente QR-Kontakte ("gespeicherte Profile") nach dem Start
    // wiederherstellen - Maximal 5, einzeln löschbar.
    try {
      await notifier.restorePersistedQrContacts();
    } catch (_) {
      // Best-effort: Ohne Restore funktioniert der Chat trotzdem.
    }
  }());
  return notifier;
});

  /// Hilfsprovider, um den Notification-Service in Provider-Buildern
  /// verfügbar zu machen, ohne direkte Singleton-Nutzung.
  final notificationServiceProvider = Provider<NotificationService>((ref) {
    return NotificationService.instance;
  });

/// Ob der verschlüsselte lokale Chat-Verlauf aktiv ist (v0.8.0) - für
/// den Datenexport: Chats landen nur im Export, wenn der Nutzer den
/// Verlauf eingeschaltet hat.
final chatHistoryLocalEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final v = await ref.watch(localStorageProvider).getBool(
        'chat_history_local');
    return v ?? false;
  } catch (_) {
    return false;
  }
});
