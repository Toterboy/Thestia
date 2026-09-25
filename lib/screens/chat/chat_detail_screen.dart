import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'package:thestia/models/match.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/gender.dart' show RelationshipType;
import 'package:thestia/models/message.dart';
import 'package:thestia/utils/chat_backgrounds.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/services/find_your_match_service.dart'
    show findYourMatchServiceProvider;
import 'package:thestia/widgets/heart_moments.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:thestia/services/image_report_service.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/p2p_chat_service.dart';
import 'package:thestia/services/prekey_service.dart';
import 'package:thestia/screens/chat/bucket_list_sheet.dart'
    show BucketListSheet;
import 'package:thestia/services/quiz_service.dart';
import 'package:thestia/services/relay_service.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/data/icebreaker_catalog.dart';
import 'package:thestia/utils/age_safety_rules.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/utils/exif_stripper.dart';
import 'package:thestia/widgets/audio_review_sheet.dart';
import 'package:thestia/widgets/chat_bubbles.dart';
import 'package:thestia/widgets/end_spark_dialog.dart';
import 'package:thestia/widgets/intro_audio_player.dart';
import 'package:thestia/widgets/meet_intent_card.dart';
import 'package:thestia/widgets/profile_widgets.dart';

/// Präfix für geteilte Eisbrecher-Fragen im Textkanal (v0.9.1): Beide Seiten
/// stellen solche Nachrichten als gemeinsame mittige Bubble dar.
const String icebreakerPrefix = '__ICEBREAKER__:';

/// 1:1-Chat-Detailansicht mit Nachrichtenverlauf und Eingabefeld.
///
/// Erweitert um:
/// - Bild- und Sprachnachrichten (mit Ladeindikator/Fehler-Wiederholen)
/// - Audio-Anruf (WebRTC + Signaling)
/// - Tippen auf Name/Avatar führt zum Profil des Gegenübers (Punkt G)
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  bool _recording = false;
  bool _paused = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _levels = [];
  static const int _maxVoiceSeconds = 300;
  static const int _ampBarCount = 24;
  // E: Ladezustand für Bild-Upload.
  bool _uploadingImage = false;

  /// Bilder im Chat standardmäßig verpixeln (Einstellung, Default an)?
  bool get _blurChatImages =>
      ref.watch(settingsProvider).blurChatImages;

  // Echte E2E-P2P-Verbindung (Signaling + WebRTC + PreKey).
  P2PChatService? _p2p;
  String? _myUserId;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>? _binarySub;
  StreamSubscription<Map<String, dynamic>>? _callControlSub;
  StreamSubscription<dynamic>? _connSub;
  StreamSubscription<void>? _relayPingSub;
  bool _p2pConnected = false;
  // Deduplication: bereits verarbeitete Message-IDs.
  final Set<String> _seenMessageIds = {};

  // Audio-Aufnahme und -Wiedergabe (echte Mikrofon/Playback-Pakete).
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;

  // Audit M-17: Lokal entschlüsselte Voice-Dateien (werden nach Wiedergabe
  // bzw. spätestens beim Verlassen des Chats gelöscht).
  final List<String> _voiceTempFiles = [];

  // Quiz-Sperre: Find-your-Match-Matches sind bis zum bestandenen
  // Kennenlern-Quiz für Chat, Bilder und Anrufe gesperrt (serverseitig
  // erzwungen, hier clientseitig gespiegelt).
  bool _quizGated = false;

  // Relay-Fallback (v0.9.1): zwischengespeicherte Nachrichten abholen.
  Timer? _relayTimer;
  bool _relayHintDismissed = false;
  bool _relayExpanded = false;
  // Handshake-Retry (v0.9.1-Fix "keine direkte Verbindung"): letzter
  // Re-Offer-Versuch (Drosselung, max. alle 25 s, nur im Vordergrund).
  DateTime? _lastHandshakeRetry;
  // Kurz-Fehler des letzten Handshake-Versuchs (für die Diagnose-Zeile
  // in der aufgeklappten Relay-Karte).
  String? _lastP2pError;

  /// Partner-ID des geöffneten Chats (für die Notification-Unterdrückung).
  String? _activePeerId;

  /// Kürzt Fehlermeldungen für die UI (keine Stacks, max. 160 Zeichen).
  static String _shortError(Object e) {
    var t = e
        .toString()
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '');
    if (t.length > 160) t = t.substring(0, 160);
    return t;
  }

  /// Date-Rad pro Chat ausgeblendet (v0.9.1, persistent in den Prefs).
  static const _ideaWheelHiddenKey = 'idea_wheel_hidden_chats';
  bool _ideaWheelHidden = false;

  /// 5-Minuten-Stille-Vorschlag (Nutzerwunsch): In einem frischen Funken-
  /// Chat ohne eigene Nachricht schlägt die App nach 5 Minuten eine
  /// Eisbrecher-Frage vor (Dialog mit Senden/Später). Einmalig je Match
  /// (Prefs-Key), läuft nur im geöffneten Chat im Vordergrund - beide
  /// Seiten bekommen den Vorschlag jeweils lokal.
  Timer? _icebreakerSuggestTimer;
  static const _icebreakerSuggestedKey = 'icebreaker_suggested_chats';

  /// Herzensstärken (v0.9.2): Server-Match-Daten (Funken-Typ 'friends',
  /// createdAt/passedAt für Erinnerungs-Momente) - im _bootstrap geladen.
  MatchWithState? _serverMatch;
  Set<String> _milestoneDismissed = const {};
  static const _milestoneDismissedKey = 'milestone_dismissed';

  /// Lädt Server-Match + dismissed-Momente für die Herzensstärken.
  Future<void> _loadHeartState() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null || !SupabaseService.isInitialized) return;
    try {
      final all =
          await ref.read(findYourMatchServiceProvider).listMatchesWithState();
      _serverMatch = all.where((m) => m.matchId == serverId).firstOrNull;
    } catch (_) {}
    try {
      final storage = ref.read(localStorageProvider);
      final raw = await storage.getString(_milestoneDismissedKey);
      _milestoneDismissed =
          (jsonDecode(raw ?? '[]') as List).map((e) => '$e').toSet();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // NUTZERWUNSCH: Unterdrückt die Lokal-Benachrichtigung für eingehende
    // Nachrichten, solange dieser Chat geöffnet ist (Nachricht sichtbar).
    ref.read(activeChatIdProvider.notifier).state = widget.matchId;
    unawaited(_bootstrap());
    unawaited(_loadQuizGate());
    unawaited(_loadIdeaWheelHidden());
    // Relay-Polling (5 s, Fix "Nachrichten kommen nicht an"): Der Partner
    // pingt nach relay_store sofort, aber falls der Ping verloren geht,
    // holt der Timer spätestens nach 5 s nach. Pausiert im Hintergrund.
    _startRelayTimer();
  }

  void _startRelayTimer() {
    _relayTimer?.cancel();
    // LATENZ: 3 s statt 5 s - der Wake-up-Ping liefert sofort, der Timer
    // fängt nur verlorene Pings ab (Akku-Kompromiss).
    _relayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        unawaited(_fetchRelay());
        unawaited(_retryHandshakeThrottled());
      }
    });
  }

  /// Versucht den P2P-Handshake erneut, solange keine direkte Verbindung
  /// besteht (Initiator sendet Re-Offer, sonst voller Neuaufbau).
  /// Läuft nur im geöffneten Chat im Vordergrund und ist auf max. einen
  /// Versuch alle 25 Sekunden gedrosselt (Akku).
  Future<void> _retryHandshakeThrottled() async {
    if (_p2pConnected || _p2p == null || !mounted) return;
    if (!SupabaseService.isInitialized) return;
    final match = _match;
    final myId = _myUserId;
    if (match == null || myId == null) return;
    final now = DateTime.now();
    if (_lastHandshakeRetry != null &&
        now.difference(_lastHandshakeRetry!) <
            const Duration(seconds: 25)) {
      return;
    }
    _lastHandshakeRetry = now;
    try {
      await _p2p!.ensureConnected(myUserId: myId, peerId: match.partner.id);
    } catch (e) {
      // Still - nächster Timer-Takt versucht es erneut. Fehler für die
      // Diagnose-Zeile merken.
      if (mounted) setState(() => _lastP2pError = _shortError(e));
      return;
    }
    if (!mounted) return;
    final open = _p2p?.isConnected ?? false;
    if (open != _p2pConnected || (open && _lastP2pError != null)) {
      setState(() {
        _p2pConnected = open;
        if (open) _lastP2pError = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hintergrund: kein Polling/Netz (Akku). Vordergrund: Timer neu +
    // sofort abholen (Nachrichten aus der Abwesenheit).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _relayTimer?.cancel();
      _relayTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      _startRelayTimer();
      unawaited(_fetchRelay());
      // Rückkehr in den Chat: ggf. sofort neu verbinden statt bis zum
      // nächsten Timer-Takt zu warten (Drossel greift trotzdem).
      unawaited(_retryHandshakeThrottled());
    }
  }

  /// Bootstrapping in richtiger Reihenfolge:
  ///   1. Lokales Match sicherstellen (Server-Matches aus dem Funken-Tab
  ///      existieren sonst NUR serverseitig -> "Dieser Chat existiert
  ///      nicht mehr", v0.9.0-Fix).
  ///   2. P2P-Verbindung aufbauen (braucht das lokale Match).
  ///   3. Partner-Profil nachladen (QR-Kontakte: Name "Unbekannt").
  ///   4. Offline gescannter Kontakt: Like nachholen (der QR-Scan erzeugt
  ///      nur bei Online den Like - beim späteren Öffnen nachholen).
  Future<void> _bootstrap() async {
    // Opt-in-Verlauf ZUERST laden (Fix "Verlauf wird nicht direkt
    // geladen"): lokal & sofort. Vorher lief die Hydration ganz am ENDE -
    // hinter dem (ggf. Sekunden dauernden oder scheiternden) P2P-Connect
    // und dem Relay-Fetch, der Chat blieb entsprechend lange leer.
    await ref.read(chatProvider.notifier).hydrateHistory(widget.matchId);
    await _ensureLocalMatch();
    await _initP2P();
    await _loadPartnerProfileIfNeeded();
    await _ensureLikeForSavedContact();
    // Relay-Nachrichten sofort abholen (Partner hat ggf. bei fehlendem
    // P2P-Kanal zwischengespeichert).
    await _fetchRelay();
    // Herzensstärken: Server-Match-Daten (Freundschafts-Badge,
    // Erinnerungs-Momente) im Hintergrund laden.
    unawaited(_loadHeartState());
    // 5-Minuten-Stille-Vorschlag starten (nur frischer Chat ohne eigene
    // Nachricht, siehe _maybeSuggestIcebreaker).
    unawaited(_maybeSuggestIcebreaker());
  }

  /// Eisbrecher-Sammlung im Chat (vom "mehr"-Menü, NUTZERWUNSCH): Frage
  /// auswählen -> direkt als gemeinsame mittige Bubble senden. Für
  /// QR-Kontakte (keine Server-ID) mit Hinweis statt tot aufhören.
  Future<void> _openIcebreakerCollection() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.spiceUnavailable')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final picked = await context.push<String>(
      AppRoutes.spiceQuestionsPath(serverId),
    );
    if (picked != null && picked.trim().isNotEmpty && mounted) {
      _sendIcebreakerQuestion(picked);
    }
  }

  /// Herzensstärken (Idee 5): Gemeinsame Erinnerungsliste (Bucket List)
  /// als Bottom Sheet - beide Seiten können Einträge hinzufügen, abhaken
  /// und eigene löschen. Bei Stillstand (14 Tage) erscheint ein sanfter
  /// Hinweis oben im Sheet.
  Future<void> _showBucketListSheet() async {
    final serverId = int.tryParse(widget.matchId);
    if (serverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.spiceUnavailable')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final partnerName = _match?.partner.name ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => BucketListSheet(
        matchId: serverId,
        partnerName: partnerName,
        myId: _myUserId ?? AppConstants.currentUserId,
      ),
    );
  }

  /// 5-Minuten-Stille-Vorschlag (Nutzerwunsch "Icebreaker-Vorschlag an
  /// beide nach 5 Minuten ohne Nachricht"): Hat der Nutzer in diesem
  /// frischen Funken-Chat nach 5 Minuten noch nichts geschrieben, wird
  /// EINMALIG eine zufällige Eisbrecher-Frage zum Senden angeboten.
  /// Die Gegenseite bekommt denselben Vorschlag lokal, sobald sie den
  /// Chat mit ebenfalls leerem Verlauf öffnet (beide Geräte werten
  /// dieselbe Regel aus - kein Server nötig).
  Future<void> _maybeSuggestIcebreaker() async {
    final match = _match;
    final myId = _myUserId;
    if (match == null || myId == null || !mounted) return;
    // Nur wenn ICH noch nichts geschrieben habe (empfangene zählen
    // nicht - dann läuft das Gespräch bereits).
    final sent = ref
        .read(chatProvider.notifier)
        .messagesFor(match.id)
        .any((m) => m.isFrom(myId));
    if (sent) return;
    // Einmalig je Match (Prefs).
    try {
      final storage = ref.read(localStorageProvider);
      final raw = await storage.getString(_icebreakerSuggestedKey);
      final done =
          (jsonDecode(raw ?? '[]') as List).map((e) => '$e').toSet();
      if (done.contains(match.id)) return;
    } catch (_) {}
    _icebreakerSuggestTimer?.cancel();
    _icebreakerSuggestTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted) return;
      final current = _match;
      final myIdNow = _myUserId;
      if (current == null || myIdNow == null) return;
      if (ref
          .read(chatProvider.notifier)
          .messagesFor(current.id)
          .any((m) => m.isFrom(myIdNow))) {
        return; // Inzwischen geschrieben - kein Vorschlag nötig.
      }
      // Als gezeigt vermerken (auch bei "Später" - kein Nerven).
      try {
        final storage = ref.read(localStorageProvider);
        final raw = await storage.getString(_icebreakerSuggestedKey);
        final done =
            (jsonDecode(raw ?? '[]') as List).map((e) => '$e').toSet();
        done.add(current.id);
        await storage.saveString(
            _icebreakerSuggestedKey, jsonEncode(done.toList()));
      } catch (_) {}
      if (!mounted) return;
      // Zufällige Frage aus dem Katalog (Sprache des Geräts).
      final lang = Localizations.localeOf(context).languageCode;
      final all = [
        for (final c in icebreakerCatalog) ...c.questions,
      ];
      if (all.isEmpty) return;
      all.shuffle();
      final question = all.first.textFor(lang);
      final send = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lightbulb_outline, size: 40),
          title: Text(L10n.t(ctx, 'chat.icebreakerSuggestTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.t(ctx, 'chat.icebreakerSuggestBody')),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '„$question"',
                  style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(L10n.t(ctx, 'chat.icebreakerSuggestLater')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(L10n.t(ctx, 'chat.icebreakerSuggestSend')),
            ),
          ],
        ),
      );
      if (send == true && mounted) {
        await _sendIcebreakerQuestion(question);
      }
    });
  }

  /// Holt E2E-verschlüsselte Relay-Nachrichten des Partners ab (Fallback,
  /// wenn P2P nicht zustande kam) und hängt sie in den Verlauf.
  Future<void> _fetchRelay() async {
    final match =
        _match ?? ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null || !mounted) return;
    if (!SupabaseService.isInitialized) return;
    try {
      // Nur Zeilen DIESES Partners abholen/bestätigen - fremde warten
      // unangetastet auf ihren eigenen Chat (RelayService.fetchPending).
      final pending = await ref
          .read(relayServiceProvider)
          .fetchPending(from: match.partner.id);
      if (!mounted) return;
      var added = false;
      for (final r in pending) {
        if (r.senderId != match.partner.id) continue;
        final msgId = 'relay_${r.id}';
        if (_seenMessageIds.contains(msgId)) continue;
        _seenMessageIds.add(msgId);
        final msg = Message(
          id: msgId,
          senderId: r.senderId,
          receiverId: _myUserId ?? AppConstants.currentUserId,
          text: r.text,
          timestamp: r.createdAt,
          type: r.kind == 'icebreaker'
              ? MessageType.icebreaker
              : MessageType.text,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
        added = true;
      }
      if (added && mounted) setState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Relay-Abruf fehlgeschlagen: $e');
    }
  }

  /// Sendet Text über drei Stufen (v0.9.1):
  ///   1. Direkt per P2P-DataChannel (wenn offen).
  ///   2. E2E-verschlüsselt über das Server-Relay (Partner holt beim
  ///      Öffnen des Chats ab - kein gleichzeitiges Online nötig).
  ///   3. Lokale Outbox (letzte Reserve, braucht später beide online).
  /// Inkl. Push-Metadaten und ehrlichem Zustands-Hinweis.
  Future<void> _transmitText(Match match, String text,
      {String kind = 'text'}) async {
    final wireText =
        kind == 'icebreaker' ? '$icebreakerPrefix$text' : text;
    final p2p = _p2p;
    if (p2p != null) {
      try {
        if (await p2p.trySendText(wireText)) {
          unawaited(_notifyPeerAboutMessage(match));
          return;
        }
      } catch (_) {}
    }
    // Kanal zu: Relay-Fallback (nur Ciphertext zum Server, E2E bleibt).
    try {
      await ref.read(relayServiceProvider).storeText(
            peerId: match.partner.id,
            text: text,
            kind: kind,
          );
      // Dual-Delivery-Schutz: trySendText oben hat bei geschlossenem Kanal
      // bereits in die Outbox eingereiht (mit icebreaker-Präfix!) - nach
      // erfolgreichem Relay-Store muss der Eintrag raus, sonst kommt die
      // Nachricht bei Kanalöffnung doppelt.
      p2p?.dequeueText(wireText);
      // Wake-up-Ping: Der Partner holt sofort ab statt aufs 5-s-Polling
      // zu warten (gleicher Mechanismus wie im Zufallschat).
      unawaited(p2p?.sendRelayPing());
      unawaited(_notifyPeerAboutMessage(match));
      // KEINE "zwischengespeichert"-SnackBar mehr (Fix: war bei jeder
      // Nachricht störend - die Nachricht kommt zuverlässig an, der
      // Nutzer braucht keinen Hinweis auf den Transportweg).
      return;
    } catch (_) {}
    // Letzte Reserve: Outbox (wird bei späterer Direktverbindung geflusht).
    try {
      await p2p?.sendText(wireText);
    } catch (_) {}
    unawaited(_notifyPeerAboutMessage(match));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.queuedHint')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Auflösung von Matches, die es lokal noch nicht gibt: Bei einer
  /// numerischen Match-ID (Server-Match) wird list_my_matches_with_state
  /// geladen und das Match lokal mit derselben ID wiederhergestellt.
  Future<void> _ensureLocalMatch() async {
    final notifier = ref.read(chatProvider.notifier);
    if (notifier.getMatchById(widget.matchId) != null) return;
    final id = int.tryParse(widget.matchId);
    if (id == null || !SupabaseService.isInitialized) return;
    try {
      final service = ref.read(findYourMatchServiceProvider);
      final matches = await service.listMatchesWithState();
      final server = matches.where((x) => x.matchId == id).firstOrNull;
      if (server == null || !mounted) return;
      notifier.restoreServerMatch(
        widget.matchId,
        server.partner,
        server.createdAt ?? DateTime.now(),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Server-Match laden fehlgeschlagen: $e');
    }
  }

  /// Offline gescannter Kontakt (gespeichertes Profil): Beim späteren
  /// Öffnen des Chats holen wir das versäumte Like nach - der Funke
  /// entsteht, sobald die Person annimmt. Best-Effort, mehrfach-fähig
  /// (like_user ist idempotent).
  Future<void> _ensureLikeForSavedContact() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null || !match.isQrContact) return;
    if (!SupabaseService.isInitialized) return;
    try {
      await ref
          .read(findYourMatchServiceProvider)
          .likeUser(match.partner.id);
      await SupabaseService.client.functions.invoke(
        'notify-user',
        body: {'kind': 'likes', 'target_user_id': match.partner.id},
      );
    } catch (e) {
      debugPrint('[ChatDetail] Nachträgliches Like fehlgeschlagen: $e');
    }
  }

  /// Das Partner-Profil wird IMMER vom Server nachgeladen (v0.9.1-Fix:
  /// vorher nur bei "Unbekannt" - dadurch fehlten bei bestehenden Kontakten
  /// Vorstellungstext und Audio-Pfad und die Vorstellung war weder sichtbar
  /// noch anhörbar). Lokale Daten bleiben Fallback bei Fehlschlag.
  Future<void> _loadPartnerProfileIfNeeded() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null) return;
    if (!SupabaseService.isInitialized) return;
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final row = await db.fetchPublicProfile(match.partner.id);
      if (row == null || !mounted) return;
      final real = UserProfile.fromPublicView(
        Map<String, dynamic>.from(row as Map),
      );
      ref
          .read(chatProvider.notifier)
          .updatePartner(widget.matchId, real);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[ChatDetail] Partner-Profil-Refresh fehlgeschlagen: $e');
    }
  }

  /// Lädt, ob das Date-Rad für diesen Chat ausgeblendet wurde.
  Future<void> _loadIdeaWheelHidden() async {
    try {
      final raw =
          await ref.read(localStorageProvider).getString(_ideaWheelHiddenKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final hidden =
          (jsonDecode(raw) as List).map((e) => '$e').toSet();
      if (mounted && hidden.contains(widget.matchId)) {
        setState(() => _ideaWheelHidden = true);
      }
    } catch (_) {}
  }

  /// Blendet das Date-Rad für diesen Chat dauerhaft aus.
  Future<void> _hideIdeaWheel() async {
    setState(() => _ideaWheelHidden = true);
    try {
      final storage = ref.read(localStorageProvider);
      final raw = await storage.getString(_ideaWheelHiddenKey);
      final hidden = <String>{
        if (raw != null && raw.isNotEmpty)
          ...(jsonDecode(raw) as List).map((e) => '$e'),
        widget.matchId,
      };
      await storage.saveString(
          _ideaWheelHiddenKey, jsonEncode(hidden.toList()));
    } catch (_) {}
  }

  /// Prüft serverseitig, ob dieses Match noch quiz-gesperrt ist.
  Future<void> _loadQuizGate() async {
    final matchId = int.tryParse(widget.matchId);
    if (matchId == null) return; // Lokaler Kontakt (QR etc.): keine Sperre.
    try {
      final state =
          await ref.read(quizServiceProvider).getState(matchId);
      if (!mounted || state == null) return;
      if (state.quizGated != _quizGated) {
        setState(() => _quizGated = state.quizGated);
      }
    } catch (e) {
      // Kein DB-Match (lokaler Kontakt) -> keine Sperre.
      debugPrint('[ChatDetail] Quiz-Gate prüfen fehlgeschlagen: $e');
    }
  }

  /// Baut die echte P2P-Verbindung zum Partner auf und leitet eingehende
  /// (bereits entschlüsselte) Nachrichten in den lokalen Chat-Verlauf.
  Future<void> _initP2P() async {
    final match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    if (match == null) return;
    _p2p = ref.read(p2pChatServiceProvider);
    // NUTZERWUNSCH: Notification-Unterdrückung braucht die Partner-ID
    // (Server-Push-Metadaten enthalten den Absender, nicht die Match-ID).
    _activePeerId = match.partner.id;
    ref.read(activeChatPeerIdProvider.notifier).state = _activePeerId;
    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // Werte (alter Account, Demo-'me') erzeugen ein Signaling-Topic, das
    // die echte auth.uid() nicht enthält -> Realtime-RLS verweigert den
    // Join und das Peer-Pinning verwirft jede Nachricht.
    _myUserId = SupabaseService.isInitialized
        ? SupabaseService.currentUser?.id
        : null;
    if (_myUserId == null || _myUserId!.isEmpty) {
      debugPrint('[ChatDetail] Keine Supabase-Session - P2P übersprungen.');
      return;
    }

    // Verbindungsstatus LIVE spiegeln (v0.9.1-Fix): Bisher wurde
    // _p2pConnected nur EINMAL direkt nach connect() gelesen - zu dem
    // Zeitpunkt ist ICE praktisch nie fertig, sodass Badge und
    // Relay-Karte dauerhaft "keine direkte Verbindung" zeigten, obwohl
    // der Kanal Sekunden später aufging.
    _connSub?.cancel();
    _connSub = _p2p!.connectionState.listen((_) {
      if (!mounted) return;
      final open = _p2p?.isConnected ?? false;
      if (open != _p2pConnected) {
        setState(() => _p2pConnected = open);
      }
    });

    // Relay-Wake-up: Der Partner hat eine Relay-Nachricht hinterlegt -
    // sofort abholen statt auf den 5-s-Poll-Takt zu warten.
    _relayPingSub?.cancel();
    _relayPingSub = _p2p!.relayPing.listen((_) {
      if (mounted) unawaited(_fetchRelay());
    });

    // Textnachrichten abonnieren. Nachrichten mit Eisbrecher-Präfix werden
    // als gemeinsame mittige Bubble dargestellt (v0.9.1, beide Seiten).
    _msgSub = _p2p!.incomingMessages.listen((text) {
      if (!mounted) return;
      final msgId = Message.newId('p2p');
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);
      final isIcebreaker = text.startsWith(icebreakerPrefix);
      final msg = Message(
        id: msgId,
        senderId: match.partner.id,
        receiverId: _myUserId ?? AppConstants.currentUserId,
        text: isIcebreaker
            ? text.substring(icebreakerPrefix.length)
            : text,
        timestamp: DateTime.now(),
        type: isIcebreaker ? MessageType.icebreaker : MessageType.text,
      );
      ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
    });

    // Binärdaten (Bilder, Audio) abonnieren.
    _binarySub = _p2p!.incomingBinary.listen((record) {
      final data = record.data;
      final contentType = record.contentType;
      final metadata = record.metadata;
      if (!mounted) return;
      final msgId = Message.newId('p2p_bin');
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);

      final isVoice = contentType.startsWith('audio/');
      if (isVoice) {
        final duration = (metadata?['durationSeconds'] as int?) ?? 0;
        _writeVoiceFile(msgId, data).then((path) {
          if (!mounted || path == null) return;
          final msg = Message(
            id: msgId,
            senderId: match.partner.id,
            receiverId: _myUserId!,
            text: '',
            timestamp: DateTime.now(),
            mediaUrl: path,
            durationSeconds: duration,
            type: MessageType.voice,
          );
          ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
        });
      } else {
        // Image: base64-data-URI.
        final mediaUrl = 'data:image/jpeg;base64,${base64Encode(data)}';
        final msg = Message(
          id: msgId,
          senderId: match.partner.id,
          receiverId: _myUserId!,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: mediaUrl,
          type: MessageType.image,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, msg, ref: ref);
      }
    });

    try {
      await _p2p!.connect(myUserId: _myUserId!, peerId: match.partner.id);
      if (mounted) setState(() => _p2pConnected = _p2p!.isConnected);
    } catch (e) {
      // Audit H-7/E-4: Der Peer hat einen ANDEREN Identity-Key als beim
      // ersten Kontakt -> Session wird blockiert statt still aufgebaut.
      if (e.toString().contains('peer_identity_changed')) {
        await _showIdentityChangedDialog(match.partner.id);
        return;
      }
      // v0.9.0-Feedback ("es gab einen P2P Fehler"): Wenn die andere Seite
      // (noch) nicht im Chat ist, scheitert das Signal-Setup - das ist
      // NORMAL und kein Fehler. Der orange E2E-Badge zeigt den Zustand;
      // die Verbindung kommt zustande, sobald beide gleichzeitig online
      // sind. Nur ein ruhiger Hinweis, keine Fehlermeldung.
      // Der Kurz-Fehler landet zusätzlich in der aufgeklappten
      // Relay-Karte (Diagnose statt Logcat-Suche).
      debugPrint('[ChatDetail] P2P-Verbindung noch nicht offen: $e');
      if (mounted) {
        setState(() {
          _p2pConnected = false;
          _lastP2pError = _shortError(e);
        });
      }
    }

    // Eingehende Anrufe (invite) abonnieren. Der Anruf-Screen wird nur
    // geöffnet, wenn gerade kein anderer Anruf aktiv ist.
    _callControlSub = _p2p!.callControl.listen((payload) {
      if (!mounted) return;
      final type = payload['type'] as String?;
      if (type != 'invite') return;
      // Leere/fremde callIds verwerfen (keine Ghost-Calls).
      final callId = payload['callId'] as String?;
      if (callId == null || callId.isEmpty) return;
      if (ref.read(activeCallIdProvider) != null) {
        // Bereits im Anruf: ablehnen statt zweiten Screen zu öffnen.
        _p2p?.sendCallControl({'type': 'decline', 'callId': callId});
        return;
      }
      // Synchron reservieren, damit keine zweite Einladung dazwischenfunkt.
      ref.read(activeCallIdProvider.notifier).state = callId;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            partnerName: match.partner.name,
            peerId: match.partner.id,
            isIncoming: true,
            incomingCallId: callId,
          ),
        ),
      );
    });
  }

  /// Audit H-7/E-4: Dialog bei Peer-Identity-Wechsel. Der Nutzer muss dem
  /// neuen Schlüssel explizit zustimmen (Safety-Number-Vergleich), bevor
  /// die Session neu aufgebaut wird - kein stiller MITM-Accept mehr.
  Future<void> _showIdentityChangedDialog(String partnerId) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.safetyChangedTitle')),
        content: Text(
          L10n.t(context, 'chat.safetyChangedBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'chat.safetyChangedCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'chat.safetyChangedAccept')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      // Alten Trust + Session-Cache verwerfen, dann erneut verbinden.
      await ref.read(encryptionServiceProvider).resetPeerTrust(partnerId);
      ref.read(preKeyServiceProvider).forget(partnerId);
      await _p2p?.connect(myUserId: _myUserId!, peerId: partnerId);
      if (mounted) setState(() => _p2pConnected = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(L10n.t(context, 'chat.reconnectStillFailing'))),
        );
      }
    }
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (sonst bliebe die Notification-Unterdrückung
    // für diese Chat-ID aktiv, obwohl der Screen weg ist).
    if (ref.read(activeChatIdProvider) == widget.matchId) {
      ref.read(activeChatIdProvider.notifier).state = null;
    }
    if (ref.read(activeChatPeerIdProvider) == _activePeerId) {
      ref.read(activeChatPeerIdProvider.notifier).state = null;
    }
    _icebreakerSuggestTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _binarySub?.cancel();
    _callControlSub?.cancel();
    _connSub?.cancel();
    _relayPingSub?.cancel();
    _relayTimer?.cancel();
    _p2p?.disconnect();
    _ctrl.dispose();
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _audioRecorder.dispose();
    // Audit M-17: Entschlüsselte Voice-Reste entfernen.
    for (final path in List<String>.from(_voiceTempFiles)) {
      _deleteVoiceFile(path);
    }
    super.dispose();
  }

  Match? _match;

  Future<void> _send() async {
    final match = _match;
    if (match == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    _ctrl.clear();

    // Lokal für die Anzeige ablegen (ohne Mock-Auto-Reply) …
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);

    // … und ECHT E2E-verschlüsselt zustellen: direkt per P2P, sonst über
    // das Server-Relay (Partner holt beim Öffnen ab), sonst Outbox.
    await _transmitText(match, text);
    if (mounted) setState(() {});
  }

  /// Ruft die notify-user-Edge-Function für den Chat-Partner auf
  /// (nur Metadaten – kein Nachrichteninhalt). Best effort.
  ///
  /// Seit Audit H2 generiert der SERVER Titel/Text (Client kann keine
  /// Push-Inhalte mehr einschleusen – kein Push-Phishing möglich).
  Future<void> _notifyPeerAboutMessage(Match match) async {
    if (!SupabaseService.isInitialized) return;
    try {
      await SupabaseService.client.functions.invoke(
        'notify-user',
        body: {
          'kind': 'messages',
          'target_user_id': match.partner.id,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Push-Benachrichtigung fehlgeschlagen: $e');
      }
    }
  }

  /// E: Bild aus Galerie/Kamera auswählen und E2E-verschlüsselt
  /// über den P2P-DataChannel senden.
  Future<void> _pickImage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.imageSend')),
        content: Text(L10n.t(context, 'chat.imageSourcePrompt')),
        // v0.9.0-Feedback: Buttons volle Breite, untereinander,
        // Abbrechen ganz unten (vorher quetschten sie sich in eine Reihe).
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('camera'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(L10n.t(ctx, 'chat.camera')),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('gallery'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(L10n.t(ctx, 'chat.gallery')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final match = _match;
    if (match == null) return;

    setState(() => _uploadingImage = true);
    try {
      final picker = ImagePicker();
      final source = choice == 'camera'
          ? ImageSource.camera
          : ImageSource.gallery;
      final picked = await picker.pickImage(
        source: source,
        // Bounds wie Avatare (2048 px): Vollauflösung vom Gallery-Pick
        // würde Speicher sprengen und den DataChannel verstopfen.
        // Angezeigt wird max. 0.8 Bildschirmbreite - mehr braucht niemand.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 70, // Kompression für DataChannel
      );
      if (picked == null) {
        if (mounted) setState(() => _uploadingImage = false);
        return;
      }

      final rawBytes = await File(picked.path).readAsBytes();

      // Audit M-21: EXIF (GPS, Geräteinfos) VOR Versand entfernen -
      // fail-closed, wenn das Bild nicht re-encodierbar ist.
      //
      // KEIN automatischer NSFW-Scan beim Senden (Betreiber-Entscheidung):
      // Chat-Bilder bleiben unangetastet E2E. Prüfung ausschließlich
      // melde-basiert (showImageReportDialog -> Edge Function report-image).
      final bytes = await stripImageMetadata(
        Uint8List.fromList(rawBytes),
        jpegQuality: 70,
      );
      if (bytes == null) {
        if (mounted) setState(() => _uploadingImage = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  L10n.t(context, 'chat.imagePrepareFailed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Bild-Hash serverseitig registrieren (Migration 068): Nur der
      // SHA-256-Hash - niemals das Bild. Damit kann eine spätere Meldung
      // dieses Bildes NACHGEWIESEN werden (Edge Function `report-image`
      // lehnt Bilder ohne Registrierung ab).
      try {
        final imageHash = sha256.convert(bytes).toString();
        unawaited(
          SupabaseService.client.rpc(
            'register_chat_image_hash',
            params: {
              'p_receiver_id': match.partner.id,
              'p_photo_hash': imageHash,
            },
          ),
        );
      } catch (_) {
        // Best effort - Senden darf daran nicht scheitern.
      }

      // E2E-verschlüsselt über den DataChannel senden.
      await _p2p?.sendBinary(Uint8List.fromList(bytes), contentType: 'image/jpeg');

      // Lokale Vorschau anzeigen.
      final localMsg = Message(
          id: Message.newId('local_img'),
        senderId: _myUserId ?? AppConstants.currentUserId,
        receiverId: match.partner.id,
        text: '',
        timestamp: DateTime.now(),
        mediaUrl: 'data:image/jpeg;base64,${base64Encode(bytes)}',
        type: MessageType.image,
      );
      ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
      if (mounted) setState(() => _uploadingImage = false);
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Text(L10n.t(ctx, 'chat.imageSendFailed')),
              ],
            ),
            content: Text(L10n.tf(ctx, 'chat.imageSendFailedBody', {'error': '$e'})),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(L10n.t(ctx, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
                child: Text(L10n.t(ctx, 'chat.retry')),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Lautstärke für die Live-Visualisierung (neues Design, wie IntroEditor):
  /// dBFS (-60..0) auf 0..1 normieren.
  void _onChatAmplitude(Amplitude amp) {
    if (!mounted || !_recording || _paused) return;
    final db = amp.current.clamp(-60.0, 0.0);
    final level = ((db + 60) / 60).clamp(0.0, 1.0);
    setState(() {
      _levels.add(level);
      while (_levels.length > _ampBarCount) {
        _levels.removeAt(0);
      }
    });
  }

  void _startChatTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      setState(() => _recordSeconds++);
      if (_recordSeconds >= _maxVoiceSeconds) {
        _toggleRecord();
      }
    });
  }

  /// Pause/Fortsetzen während der Sprachaufnahme (neues Design).
  Future<void> _pauseResumeRecording() async {
    if (!_recording) return;
    try {
      if (_paused) {
        await _audioRecorder.resume();
        if (mounted) setState(() => _paused = false);
      } else {
        await _audioRecorder.pause();
        if (mounted) setState(() => _paused = true);
      }
    } catch (e) {
      debugPrint('[ChatDetail] Pause/Resume fehlgeschlagen: $e');
    }
  }

  String _fmtRecordSeconds(int s) {
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  /// D: Sprachaufnahme starten/beenden mit [AudioRecorder].
  ///
  /// Aufnahme als .m4a (AAC), dann Bytes E2E-verschlüsselt via
  /// `_p2p!.sendBinary()` senden. Löscht die temporäre Datei nach
  /// erfolgreichem Senden.
  ///
  /// Mindestlänge: 1 Sekunde (versehentliche Ultra-Kurz-Aufnahmen
  /// werden verworfen). Neues Design (v0.9.1): Live-Dauer +
  /// Lautstärke-Balken + Pause/Fortsetzen, wie im IntroEditor.
  Future<void> _toggleRecord() async {
    if (_recording) {
      _recordTimer?.cancel();
      await _ampSub?.cancel();
      _ampSub = null;

      // WICHTIG: Sekunden VOR dem Reset sichern – vorher stand der Reset
      // vor der Prüfung, sodass jede Aufnahme als "unter 1 Sekunde"
      // verworfen wurde (Sprachnachrichten kamen nie durch).
      final seconds = _recordSeconds;

      // Aufnahme beenden.
      final path = _recordingPath;
      setState(() {
        _recording = false;
        _paused = false;
        _recordSeconds = 0;
        _recordingPath = null;
        _levels.clear();
      });

      if (path == null) return;

      try {
        // Aufnahme stoppen (schreibt die Datei final) und Bytes lesen.
        final recordedPath = await _audioRecorder.stop();
        final effectivePath = recordedPath ?? path;
        final file = File(effectivePath);
        final exists = await file.exists();
        if (!exists) return;

        // Mindestlänge prüfen (mit der gesicherten, echten Dauer).
        if (seconds < 1) {
          await file.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.t(context, 'chat.voiceTooShort')),
              ),
            );
          }
          return;
        }

        // Anhören vor dem Senden: Review-Sheet mit Player. Erst nach
        // Bestätigung wird die Nachricht (E2E-verschlüsselt) gesendet.
        if (!mounted) {
          await file.delete();
          return;
        }
        final send = await showAudioReviewSheet(
          context: context,
          path: effectivePath,
          durationSeconds: seconds,
          minimumSeconds: 1,
          confirmLabel: L10n.t(context, 'intro.review.send'),
        );
        if (send != true) {
          await file.delete();
          return;
        }

        final bytes = await file.readAsBytes();

        final match = _match;
        if (match == null) {
          await file.delete();
          return;
        }

        // E2E-verschlüsselt via P2P-DataChannel senden (inkl. Duration).
        await _p2p?.sendBinary(
          Uint8List.fromList(bytes),
          contentType: 'audio/m4a',
          metadata: {'durationSeconds': seconds},
        );

        // Lokale Vorschau anzeigen.
        final localMsg = Message(
          id: Message.newId('local_voice'),
          senderId: _myUserId ?? AppConstants.currentUserId,
          receiverId: match.partner.id,
          text: '',
          timestamp: DateTime.now(),
          mediaUrl: effectivePath,
          durationSeconds: seconds,
          type: MessageType.voice,
        );
        ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
        if (mounted && !_p2pConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'chat.queuedHint')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Temporäre Datei NICHT löschen: die Nachricht referenziert den
        // Pfad, damit sie lokal angehört werden kann.
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.tf(context, 'chat.voiceRecordFailed', {'error': '$e'}))),
          );
        }
      }
    } else {
      // Aufnahme starten.
      try {
        final hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(L10n.t(context, 'intro.micDenied'))),
            );
          }
          return;
        }

        final dir = Directory.systemTemp;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/thestia_voice_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 48000,
          ),
          path: path,
        );

        setState(() {
          _recording = true;
          _paused = false;
          _recordSeconds = 0;
          _recordingPath = path;
          _levels.clear();
        });
        _ampSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen(_onChatAmplitude);
        _startChatTimer();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.tf(context, 'chat.voiceStartFailed', {'error': '$e'}))),
          );
        }
      }
    }
  }

  /// D: Bricht eine laufende Sprachaufnahme ab - es wird NICHTS gesendet
  /// und die temporäre Datei gelöscht.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final path = _recordingPath;
    setState(() {
      _recording = false;
      _paused = false;
      _recordSeconds = 0;
      _recordingPath = null;
      _levels.clear();
    });
    try {
      await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.t(context, 'chat.voiceCancelled'))),
      );
    }
  }

  /// Neues Aufnahme-Panel (v0.9.1): Karte mit Live-Dauer, Pegel-Balken,
  /// Pause/Fortsetzen, Verwerfen und Stoppen - analog zum IntroEditor,
  /// statt des alten Mic/X-Hint-Designs.
  Widget _buildVoiceRecordingPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liveColor = _paused ? scheme.onSurfaceVariant : scheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Card(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    _paused
                        ? Icons.pause_circle
                        : Icons.radio_button_checked,
                    size: 18,
                    color: liveColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _paused
                        ? L10n.t(context, 'intro.pausedState')
                        : L10n.t(context, 'intro.recordingState'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: liveColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    _fmtRecordSeconds(_recordSeconds),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _ampBarCount; i++)
                      Container(
                        width: 3.5,
                        height: 4.0 +
                            26.0 *
                                (_levels.length > i
                                    ? _levels[_levels.length - 1 - i]
                                    : 0.0),
                        decoration: BoxDecoration(
                          color: (_levels.length > i
                                      ? _levels[_levels.length - 1 - i]
                                      : 0.0) <=
                                  0.01
                              ? liveColor.withValues(alpha: 0.25)
                              : liveColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _cancelRecording,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: L10n.t(context, 'chat.voiceCancel'),
                    color: scheme.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pauseResumeRecording,
                      icon: Icon(
                          _paused ? Icons.play_arrow : Icons.pause),
                      label: Text(_paused
                          ? L10n.t(context, 'intro.resume')
                          : L10n.t(context, 'intro.pause')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggleRecord,
                      icon: const Icon(Icons.stop),
                      label: Text(
                          L10n.t(context, 'intro.stopListen')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// F: Startet einen Audio-Anruf. Öffnet den Anruf-Screen (Signaling + Audio
  /// laufen E2E-verschlüsselt über den bestehenden P2P-DataChannel).
  Future<void> _call() async {
    final match = _match;
    if (match == null) return;
    if (!mounted) return;
    if (ref.read(activeCallIdProvider) != null) return;
    // callId synchron reservieren (v0.9.1-Fix: sonst öffnet ein exakt
    // gleichzeitig eingehendes Invite einen zweiten Screen darüber).
    final callId =
        'call_${DateTime.now().millisecondsSinceEpoch}';
    ref.read(activeCallIdProvider.notifier).state = callId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          partnerName: match.partner.name,
          peerId: match.partner.id,
          isIncoming: false,
          incomingCallId: callId,
        ),
      ),
    );
  }

  /// Zeigt den Safety-Number-Dialog (E2E-Identitätsverifikation, Audit B2).
  ///
  /// Beide Chat-Partner sehen für ihre Session dieselbe Nummer. Sie wird
  /// out-of-band (persönlich/telefonisch) verglichen; stimmt sie überein,
  /// kann die Identität hier bestätigt werden. Ein unterschobenes PreKey-
  /// Bundle (kompromittierter Server) führt zu abweichenden Nummern.
  Future<void> _showSafetyNumberDialog(String peerId, String peerName) async {
    final encryption = ref.read(encryptionServiceProvider);
    await encryption.initialized;

    var verified = encryption.isPeerIdentityVerified(peerId);
    final safetyNumber = encryption.safetyNumberFor(peerId);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(L10n.t(context, 'chat.safetyNumber'))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                safetyNumber == null
                    ? L10n.tf(context, 'chat.safetyNotConnected',
                        {'name': peerName})
                    : L10n.tf(context, 'chat.safetyCompare',
                        {'name': peerName}),
              ),
              if (safetyNumber != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    safetyNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L10n.t(context, 'chat.identityVerifiedTitle')),
                  subtitle: Text(
                    L10n.t(context, 'chat.identityVerifiedHint'),
                  ),
                  value: verified,
                  onChanged: (value) async {
                    await encryption.setPeerIdentityVerified(peerId, value);
                    setDialogState(() => verified = value);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(context, 'chat.close')),
            ),
          ],
        ),
      ),
    );
  }

  /// Meldet ein einzelnes Bild als unangemessenen Inhalt.
  ///
  /// Chat-Bilder werden bewusst NICHT beim Senden gescannt (E2E). Erst
  /// die Meldung durch den Empfänger löst die Prüfung aus: Die KI prüft
  /// das Bild automatisch, der Meldende sieht das Ergebnis sofort und
  /// kann bei Widerspruch der KI eine manuelle Team-Prüfung veranlassen
  /// (Bild + Report + KI-Ergebnis gehen ans Team, siehe
  /// [showImageReportDialog] und Edge Function `report-image`).
  void _reportImage(Message msg) {
    final match = _match;
    if (match == null) return;
    // Letzte 3 Textnachrichten als Kontext für das Moderations-Team
    // (v0.8.0). Das gemeldete Bild selbst wird separat übertragen.
    final contextMessages = ref
        .read(chatProvider.notifier)
        .messagesFor(match.id)
        .where((m) =>
            m.id != msg.id &&
            m.text.trim().isNotEmpty &&
            m.type == MessageType.text)
        .map((m) => m.text.trim())
        .toList()
        .reversed
        .take(3)
        .toList()
        .reversed
        .toList();
    showImageReportDialog(
      context: context,
      ref: ref,
      message: msg,
      reportedUserId: match.partner.id,
      reportedUserName: match.partner.name,
      contextMessages: contextMessages,
    );
  }

  /// Zeigt den Bestätigungsdialog zum Blockieren eines Nutzers
  /// (Bot-/Spam-Schutz, Migration 043).
  ///
  /// Serverseitig werden Likes in beide Richtungen und der Match gelöscht;
  /// künftige Interaktionen werden dauerhaft verhindert (bis zum Unblock).
  Future<void> _showBlockUserDialog(String peerId, String peerName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.block, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(L10n.t(ctx, 'chat.blockTitle'))),
          ],
        ),
        content: Text(L10n.tf(
          context,
          'chat.blockBody',
          {'name': peerName},
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(ctx, 'chat.blockAction')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await SupabaseDatabaseService(SupabaseService.client).blockUser(peerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tf(context, 'chat.blockedDone', {'name': peerName})),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Match wurde serverseitig gelöscht -> zurück zur Match-Liste
        // (Funken-Tab, v0.9.1).
        ref.read(interessenInitialTabProvider.notifier).state = 2;
        context.go(AppRoutes.interessen);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ChatDetail] Blockieren fehlgeschlagen: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.blockFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Gemeinsame Interessen mit dem Chat-Partner (für den
  /// Kontext-Icebreaker-Chip, v0.8.0).
  List<String> _commonInterests() {
    final match = _match;
    if (match == null) return const [];
    final mine = ref.read(profileProvider).interests.toSet();
    return match.partner.interests.where(mine.contains).toList();
  }

  /// Sendet eine E2E-Nachricht auf Basis der gemeinsamen Interessen.
  ///
  /// v0.9.1-Fix ("Icebreaker Button geht nicht"): Vorher stilles return,
  /// wenn [_myUserId] noch null war (P2P-Init läuft asynchron) oder [_p2p]
  /// null - ohne Feedback wirkte der Button funktionslos. Jetzt Fallback-ID,
  /// fehlender P2P-Hinweis und Queue-Hinweis bei offline Partner.
  Future<void> _sendContextIcebreaker(String interest) async {
    final match = _match;
    if (match == null) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    final text = L10n.tf(
        context, 'chat.icebreakerText', {'interest': interest});
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text);
    if (mounted) setState(() {});
  }

  /// Sendet eine Eisbrecher-Frage als GEMEINSAME mittige Bubble (v0.9.1):
  /// Beide Seiten sehen dieselbe Frage in der Chat-Mitte; sie wandert wie
  /// jede Nachricht mit.
  Future<void> _sendIcebreakerQuestion(String question) async {
    final match = _match;
    final text = question.trim();
    if (match == null || text.isEmpty) return;
    final myId = _myUserId ?? AppConstants.currentUserId;
    final localMsg = Message(
          id: Message.newId('local_ice'),
      senderId: myId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
      type: MessageType.icebreaker,
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text, kind: 'icebreaker');
    if (mounted) setState(() {});
  }

  // Ideen-Rad (v0.8.0): die bestehenden Date-Kategorien des Meet-Intents,
  // lokalisiert (l10n-Keys 'chat.idea.*').
  static const _meetIdeaCategories = <String>[
    'chat.idea.coffeeCake',
    'chat.idea.walk',
    'chat.idea.iceCream',
    'chat.idea.museum',
    'chat.idea.minigolf',
    'chat.idea.movieNight',
    'chat.idea.market',
    'chat.idea.bowling',
    'chat.idea.liveMusic',
    'chat.idea.stargazing',
  ];

  List<String> _localizedMeetIdeas(BuildContext context) => [
        for (final key in _meetIdeaCategories) L10n.t(context, key),
      ];

  /// Ideen-Rad: dreht (animiert über abnehmende Zyklen), landet auf einer
  /// Kategorie und bietet an, den Vorschlag als E2E-Nachricht zu senden.
  Future<void> _showMeetIdeaWheel() async {
    final match = _match;
    if (match == null) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _MeetIdeaWheelDialog(
          categories: _localizedMeetIdeas(ctx)),
    );
    if (picked == null || !mounted) return;

    // Vorschlag als E2E-Nachricht senden (gleicher Weg wie _send()).
    final text = L10n.tf(context, 'chat.dateIdea', {'idea': picked});
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: _myUserId ?? AppConstants.currentUserId,
      receiverId: match.partner.id,
      text: text,
      timestamp: DateTime.now(),
    );
    ref.read(chatProvider.notifier).addMessage(match.id, localMsg, ref: ref);
    await _transmitText(match, text);
  }

  /// "Ehrliches Beenden" (v0.8.0) statt hartem Auflösen: Entweder den
  /// Funken RUHIG enden lassen (status -> cooled, landet bei beiden unter
  /// "Erschlossene Funken", Re-Funke jederzeit) oder vorher einen der
  /// vorbereiteten, freundlichen Absage-Texte senden (Dialog geteilt mit
  /// der Interessen-Liste, siehe [showEndSparkDialog]).
  Future<void> _showEndSparkDialog() async {
    final choice = await showEndSparkDialog(context);

    if (choice == null || !mounted) return;

    // Optional: gewählten Absage-Text zuerst senden (P2P, sonst Relay).
    final goodbye = goodbyeTextForChoice(context, choice);
    if (goodbye != null) {
      final match = _match;
      if (match != null) {
        final localMsg = Message(
          id: Message.newId('local'),
          senderId: _myUserId ?? AppConstants.currentUserId,
          receiverId: match.partner.id,
          text: goodbye,
          timestamp: DateTime.now(),
        );
        ref.read(chatProvider.notifier).addMessage(match.id, localMsg,
            ref: ref);
        try {
          await _transmitText(match, goodbye);
        } catch (_) {
          // Best-Effort: Die Verbindung kühlt trotzdem.
        }
      }
    }

    // Serverseitig kühlen (Migration 090, BIGINT): status -> cooled.
    // Die Match-ID kommt aus der Route als String.
    final matchId = int.tryParse(_match?.id ?? '');
    if (matchId == null) {
      // Lokaler Kontakt (QR): kein Server-Funke - nur lokal entfernen.
      ref.read(chatProvider.notifier).dissolveMatch(_match!.id);
      if (mounted) {
        ref.read(interessenInitialTabProvider.notifier).state = 2;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.coolSparkDone')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go(AppRoutes.interessen);
      }
      return;
    }
    try {
      await ref
          .read(findYourMatchServiceProvider)
          .coolMatch(matchId);
    } catch (e) {
      // Bereits gekühlt (z. B. aus der Liste): kein Fehler, weiter zum
      // Funken-Tab statt Fehlermeldung.
      final alreadyCooled =
          e.toString().toLowerCase().contains('bereits gekuehlt');
      if (!alreadyCooled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.tf(context, 'chat.coolSparkError', {'error': e.toString()})),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
    }

    if (mounted) {
      // Direkt auf den Funken-Tab (v0.9.1): sonst landet man auf
      // "Gesendet" und der gekühlte Funke wirkt "komplett weg".
      ref.read(interessenInitialTabProvider.notifier).state = 2;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.coolSparkDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go(AppRoutes.interessen);
    }
  }

  /// Schreibt empfangene Voice-Bytes in eine temporäre Datei.
  ///
  /// Audit M-17: Der Pfad wird zusätzlich in [_voiceTempFiles] registriert;
  /// die Datei wird nach der Wiedergabe bzw. beim Verlassen des Chats
  /// gelöscht (entschlüsselte Sprache darf nicht akkumulierend im Temp-
  /// Verzeichnis liegen).
  Future<String?> _writeVoiceFile(String msgId, Uint8List data) async {
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/thestia_incoming_$msgId.m4a';
      await File(path).writeAsBytes(data);
      _voiceTempFiles.add(path);
      return path;
    } catch (e) {
      debugPrint('[ChatDetail] Voice-Datei konnte nicht geschrieben werden: $e');
      return null;
    }
  }

  /// Entfernt eine wiedergegebene Voice-Datei sofort (Audit M-17).
  Future<void> _deleteVoiceFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      _voiceTempFiles.remove(path);
    } catch (_) {
      // Best-effort: Der globale Sweep (temp_cleanup) entfernt Reste.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kontext-Icebreaker ein-/ausschaltbar (v0.8.0).
    final icebreakerEnabled =
        ref.watch(settingsProvider).contextIcebreakerEnabled;
    // v0.9.0-Nutzerwunsch: Wer NACH FREUNDEN sucht, bekommt keine
    // Date-Vorschläge (Meet-Intent + Ideen-Rad ausgeblendet). Der
    // Friends-Filter (Migration 088) stellt sicher, dass der Partner
    // ebenfalls "Freunde" sucht - die eigene Einstellung genügt als
    // Umschalter.
    final noDates =
        ref.watch(userPreferencesProvider).relationshipType ==
            RelationshipType.friends;
    _match = ref.watch(chatProvider.notifier).getMatchById(widget.matchId);
    final settings = ref.watch(settingsProvider);

    void goToSparks() {
      // Zurück IMMER auf die Seite davor (v0.9.1): per Push geöffnet ->
      // pop zum exakten Vorzustand (z. B. Funken-Tab). Nur ohne Stack
      // (Deep-Link) auf den Funken-Tab navigieren - Chats hängen dort,
      // sonst wirkt der Funke "plötzlich weg".
      if (Navigator.of(context).canPop()) {
        context.pop();
        return;
      }
      ref.read(interessenInitialTabProvider.notifier).state = 2;
      context.go(AppRoutes.interessen);
    }

    if (_match == null) {
      // Match existiert nicht mehr (z. B. aufgelöst) - zurück zur übersicht.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'chat.backToSparks'),
            onPressed: goToSparks,
          ),
          title: Text(L10n.t(context, 'chat.title')),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(L10n.t(context, 'chat.gone')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: goToSparks,
                child: Text(L10n.t(context, 'chat.backToSparks')),
              ),
            ],
          ),
        ),
      );
    }

    final partner = _match!.partner;
    final myProfile = ref.watch(profileProvider);
    final messages = ref.watch(chatProvider.notifier).messagesFor(_match!.id);
    final myId = _myUserId ?? AppConstants.currentUserId;
    // Nutzerwunsch Gruppierung: Namens-Header an Gruppenstarts (max. 3
    // Nachrichten / 3 Minuten pro Gruppe), Zeit an jeder Bubble.
    final bubbleGroups = computeBubbleGroups(messages);

    // Vorstellung ausblenden, sobald die erste eigene Nachricht raus ist.
    final hasSentMessage = messages.any((m) => m.isFrom(myId));

    // Kennenlern-Quiz erst nach 50-70 Nachrichten vorschlagen. Die Schwelle
    // ist pro Chat deterministisch (Hash der Match-ID) - jeder Chat hat
    // seine eigene, sie gilt nicht global für alle.
    final quizThreshold = 50 + (widget.matchId.hashCode.abs() % 21);
    final showQuizBanner = _quizGated && messages.length >= quizThreshold;

    // Date-Rad erst nach 50-70 Nachrichten (v0.9.1): Eigene Schwelle je
    // Chat (bitversetzt, damit sie nicht mit der Quiz-Schwelle
    // zusammenfällt), pro Chat ausblendbar.
    final ideaThreshold =
        50 + ((widget.matchId.hashCode >> 8).abs() % 21);
    final showIdeaWheel = !noDates &&
        messages.length >= ideaThreshold &&
        !_ideaWheelHidden;

    // Altersbasierte Sichtbarkeits-Regeln anwenden
    final myAge = myProfile.age ?? 0;
    final partnerAge = partner.age ?? 0;
    final isPhotosVisible = AgeSafetyRules.arePhotosVisible(
      targetAge: partnerAge,
      viewerAge: myAge,
      blindModeEnabled: settings.blindModeEnabled,
      revealPhotosAfterMatch: settings.revealPhotosAfterMatch,
      isMatched: _match!.photosUnlocked,
    );

    // Herzensstärken (v0.9.2): Funken-Typ + Server-Match-Daten (wenn der
    // Server-Match bekannt ist; QR-/Lokal-Chats bleiben 'spark') werden
    // NICHT im Build geladen (Sync-Build!), sondern in _bootstrap
    // vorgeladen und im State gehalten (Dismissed-Set ebenfalls).
    final serverMatch = _serverMatch;
    final serverId = serverMatch?.matchId;
    // Erinnerungs-Moment (Idee 1): EIN Moment pro Chat-Öffnung.
    final milestone = Milestones.currentFor(
      matchId: serverId ?? widget.matchId.hashCode,
      matchedAt: serverMatch?.createdAt,
      quizPassedAt: serverMatch?.passedAt,
      dismissed: _milestoneDismissed,
    );

    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: L10n.t(context, 'chat.backToSparks'),
            onPressed: goToSparks,
          ),
        // G/H: Tap auf Name/Avatar -> Profil des Gegenübers.
        // Bewusst push() statt go(), damit der "Zurück"-Pfeil im
        // Profil-Screen wieder exakt zu DIESEM Chat zurückkehrt (und nicht
        // zu Matches/Profil). Der aktive Tab bleibt "Matches" (siehe
        // _subRoutePrefixes in main_navigation.dart).
        title: GestureDetector(
          onTap: () => context.push(AppRoutes.profileDetailPath(partner.id)),
          child: Row(
            children: [
              CircleAvatar(
                child: !isPhotosVisible
                    ? const Icon(Icons.visibility_off)
                    : const Icon(Icons.person),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(
                          partner.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // KEINE Streaks/Flammen-Zählung (v0.9.0-Feedback:
                      // "Es soll keine Streaks geben") - nur der Name.
                    ]),
                    // Bewusst KEIN Online-Status / „schreibt…“ /
                    // Lesebestätigung - siehe ADR-0007 (Präsenz-frei).
                    // E2E + P2P-Status-Badge (v0.9.1: zentriert im
                    // verfügbaren Titel-Raum statt rechtsbündig am Rand -
                    // nutzt den Leerraum zwischen Avatar und Actions sauber
                    // aus und wird bei langen Namen nicht abgeschnitten).
                    const SizedBox(height: 2),
                    Center(
                      child: Tooltip(
                        message: _p2pConnected
                            ? L10n.t(context, 'chat.e2eReady')
                            : L10n.t(context, 'chat.e2eWaiting'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _p2pConnected
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.orange.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(
                                _p2pConnected
                                    ? Icons.lock
                                    : Icons.lock_open,
                                size: 13,
                                color: _p2pConnected
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'E2E',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _p2pConnected
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // NUTZERWUNSCH "zu viele Symbole, Name abgeschnitten": Die
          // AppBar-Buttons sind auf ZWEI kompakte reduziert (Anruf +
          // Menü). Alles andere (Eisbrecher, Erinnerungsliste,
          // Sicherheit, Melden, Blockieren, Funke beenden) lebt im
          // "mehr"-Menü bzw. im Chat-Verlauf - der Platz bleibt dem
          // Chat erhalten.
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: L10n.t(context, 'chat.call'),
            onPressed: _call,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: L10n.t(context, 'chat.more'),
            onSelected: (value) {
              switch (value) {
                case 'icebreaker':
                  _openIcebreakerCollection();
                case 'bucket':
                  _showBucketListSheet();
                case 'safety':
                  _showSafetyNumberDialog(partner.id, partner.name);
                case 'report':
                  // Letzte 3 Nachrichten (inkl. Medien) werden automatisch
                  // mit der Meldung an den Support übermittelt – nur so
                  // kann der Support E2E-Chats einsehen. Chronologisch
                  // (älteste zuerst), daher die letzten Elemente nehmen.
                  final lastMessages = messages.length > 3
                      ? messages.sublist(messages.length - 3)
                      : messages;
                  showReportUserDialog(
                    context: context,
                    ref: ref,
                    reportedUserId: partner.id,
                    reportedUserName: partner.name,
                    messages: lastMessages,
                  );
                case 'toggleIcebreaker':
                  final current =
                      ref.read(settingsProvider).contextIcebreakerEnabled;
                  ref
                      .read(settingsProvider.notifier)
                      .setContextIcebreaker(!current);
                case 'block':
                  _showBlockUserDialog(partner.id, partner.name);
                case 'dissolve':
                  _showEndSparkDialog();
              }
            },
            itemBuilder: (ctx) => [
              // NUTZERWUNSCH "Menü besser geordnet": Die Punkte laufen in
              // sinngemäßen Gruppen - ZUSAMMEN (Eisbrecher, Erinnerungs-
              // liste) -> SICHERHEIT (Sicherheitsnummer, Melden,
              // Blockieren, Funke beenden) -> EINSTELLUNGEN (Kontext-
              // Eisbrecher an/aus). Optisch getrennt durch Divider.
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'icebreaker',
                child: ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(L10n.t(context, 'chat.spiceTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'bucket',
                child: ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(L10n.t(context, 'bucket.title')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Padding(
                  padding: EdgeInsets.only(left: 16, top: 4, bottom: 4),
                  child: Text('Sicherheit',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              PopupMenuItem(
                value: 'safety',
                child: ListTile(
                  leading:
                      const Icon(Icons.verified_user_outlined),
                  title: Text(L10n.t(
                      context, 'chat.safetyNumberTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(
                      L10n.t(context, 'chat.reportTooltip')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(L10n.t(context, 'chat.block')),
                  subtitle: Text(L10n.t(context, 'chat.blockSub')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'toggleIcebreaker',
                child: ListTile(
                  leading: Icon(ref.watch(settingsProvider)
                          .contextIcebreakerEnabled
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  title: Text(ref.watch(settingsProvider)
                          .contextIcebreakerEnabled
                      ? L10n.t(context, 'chat.icebreakerOff')
                      : L10n.t(context, 'chat.icebreakerOn')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'dissolve',
                child: ListTile(
                  leading: const Icon(Icons.link_off),
                  title: Text(L10n.t(context, 'chat.end')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Chat-Hintergrund (v0.9.1): Muster oder eigenes Bild.
          Positioned.fill(
            child: ChatBackgroundView(
              backgroundId: settings.chatBackground,
              customPath: settings.chatBackgroundPath,
            ),
          ),
          Column(
        children: [
          // Verbindungs-Hinweis (v0.9.1): Abgerundete Karte, eingeklappt
          // nur "Keine direkte Verbindung", aufklappbar für Details.
          // Wegtippbar pro Öffnen.
          if (!_p2pConnected && !_relayHintDismissed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Card(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(
                      () => _relayExpanded = !_relayExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _relayExpanded
                                  ? Icons.expand_less
                                  : Icons.cloud_sync_outlined,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _relayExpanded
                                    ? L10n.t(
                                        context, 'chat.relayBanner')
                                    : L10n.t(context,
                                        'chat.relayBannerShort'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 16),
                              tooltip:
                                  L10n.t(context, 'common.close'),
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              onPressed: () => setState(
                                  () => _relayHintDismissed = true),
                            ),
                          ],
                        ),
                        // Technische Diagnose (nur aufgeklappt): hilft zu
                        // erkennen, wo der Aufbau hängt (Signaling vs.
                        // ICE/NAT). Automatischer Neuversuch läuft.
                        if (_relayExpanded)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 24, top: 2),
                            child: StreamBuilder(
                              stream:
                                  _p2p?.iceConnectionState,
                              builder: (context, snap) {
                                final ice = snap.data
                                        ?.toString()
                                        .split('.')
                                        .last ??
                                    '-';
                                final err = _lastP2pError;
                                return Text(
                                  err == null
                                      ? L10n.tf(context,
                                          'chat.connDiag', {'ice': ice})
                                      : '${L10n.tf(context, 'chat.connDiag', {'ice': ice})}\n${L10n.tf(context, 'chat.connError', {'error': err})}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Altersdifferenz-Hinweis (v0.9.1, Jugendschutz): Ab 10 Jahren
          // Unterschied warnen, Profile können falsche Angaben enthalten.
          // Tap führt ins Safety Center.
          if (myAge > 0 &&
              partnerAge > 0 &&
              (myAge - partnerAge).abs() >= 10)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Card(
                color: Colors.orange.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () =>
                      context.push(AppRoutes.safetyCenter),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: Colors.orange.shade900,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            L10n.tf(context, 'chat.ageGapHint', {
                              'my': '$myAge',
                              'other': '$partnerAge',
                            }),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Herzensstärken (Idee 1): Erinnerungs-Karte (ein Moment pro
          // Chat-Öffnung, wegwischbar).
          if (milestone != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.favorite,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${L10n.t(context, 'milestone.title')} · '
                              '${L10n.t(context, milestone.titleKey)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              L10n.tf(
                                  context,
                                  milestone.bodyKey,
                                  {
                                    'date': milestone.formattedDate(
                                        Localizations.localeOf(context)
                                            .languageCode),
                                  }),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: L10n.t(context, 'milestone.dismiss'),
                        onPressed: () async {
                          // Dismiss je Match+Moment (Prefs).
                          final key =
                              '${serverId ?? widget.matchId.hashCode}:${milestone.type}';
                          try {
                            final storage = ref.read(localStorageProvider);
                            final raw = await storage
                                .getString(_milestoneDismissedKey);
                            final dismissed = (jsonDecode(raw ?? '[]')
                                    as List)
                                .map((e) => '$e')
                                .toSet()
                              ..add(key);
                            await storage.saveString(
                                _milestoneDismissedKey,
                                jsonEncode(dismissed.toList()));
                            _milestoneDismissed = dismissed;
                          } catch (_) {}
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!isPhotosVisible)
            BlindPhotoPlaceholder(label: L10n.t(context, 'chat.photosAfterSpark')),
          // Freundschafts-Badge + Typ-Umschalter (Idee 3): Dezent als Chip
          // unter dem Verbindungs-Hinweis; Popup zum Umschalten.
          if (serverMatch?.isFriends == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: Icon(Icons.group_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  label: Text(
                    L10n.t(context, 'friends.badge'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  onPressed: () async {
                    final serverId = int.tryParse(widget.matchId);
                    if (serverId == null) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final l10nHint = L10n.t(context, 'friends.toggleHint');
                    try {
                      await ref
                          .read(findYourMatchServiceProvider)
                          .setMatchKind(serverId, friends: false);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(l10nHint),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      setState(() {});
                    } catch (_) {}
                  },
                ),
              ),
            ),
          // Kein Meet-Intent für Freunde-Sucher (v0.9.0: "keine Dates").
          if (!noDates)
            MeetIntentCard(
              matchId: widget.matchId,
              partnerName: partner.name,
            ),
          // Vorstellung des Partners (Text + Audio): Beide Seiten können
          // die Vorstellung im Chat anhören (v0.9.0-Feedback - die Person,
          // die den Funke erhalten hat, hörte sie bisher nur im
          // "Erhalten"-Tab). Blendet sich nach der ersten eigenen
          // Nachricht aus (v0.9.1).
          if (!hasSentMessage &&
              (partner.introText.isNotEmpty ||
                  partner.introAudioPath != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  // Volle Vorstellung im Profil-Screen (Text + Audio).
                  // Die Karten-Vorschau bleibt kompakt (2 Zeilen), ein Tap
                  // öffnet die ausführliche Ansicht.
                  onTap: () => context.push(
                    AppRoutes.profileDetailPath(partner.id),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                            Icons.record_voice_over_outlined,
                            size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            partner.introText.isNotEmpty
                                ? partner.introText
                                : L10n.t(context, 'chat.introTitle'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                        ),
                        if (partner.introAudioPath != null)
                          IntroAudioPlayer(
                              targetUserId: partner.id),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Ideen-Rad (v0.8.0, Test): wählt aus den bestehenden Date-
          // Kategorien einen Vorschlag, der als Nachricht gesendet wird -
          // beide bestätigen im Chat. Für Freunde-Sucher ausgeblendet
          // (v0.9.0: "keine Dates vorschlagen"). Erst nach 50-70
          // Nachrichten pro Chat sichtbar und ausblendbar (v0.9.1).
          if (showIdeaWheel)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showMeetIdeaWheel,
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: Text(L10n.t(context, 'chat.ideaWheelBtn')),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: L10n.t(context, 'chat.ideaHide'),
                    onPressed: _hideIdeaWheel,
                  ),
                ],
              ),
            ),
          // Kontext-Icebreaker (v0.8.0): gemeinsame Interessen als
          // Gesprächseinstieg. Im Menü deaktivierbar.
          if (icebreakerEnabled &&
              _commonInterests().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(
                    'Gemeinsam: ${_commonInterests().first}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _sendContextIcebreaker(
                      _commonInterests().first),
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                     child: Text(L10n.t(context, 'chat.empty')),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    reverse: true,
                    itemBuilder: (context, i) {
                      final idx = messages.length - 1 - i;
                      final msg = messages[idx];
                      final mine = msg.isFrom(_myUserId ?? AppConstants.currentUserId);
                      final group = idx >= 0 && idx < bubbleGroups.length
                          ? bubbleGroups[idx]
                          : (showName: true, showTime: true);
                      // Geteilte Eisbrecher-Frage: mittige Bubble für BEIDE
                      // Seiten (v0.9.1), wandert wie jede Nachricht mit.
                      if (msg.type == MessageType.icebreaker) {
                        final senderName =
                            mine ? L10n.t(context, 'chat.you') : partner.name;
                        return Center(
                          child: _IcebreakerBubble(
                            text: msg.text,
                            senderName: senderName,
                          ),
                        );
                      }
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: _MessageBubble(
                          msg: msg,
                          mine: mine,
                          blurEnabled: _blurChatImages,
                          onReportImage: _reportImage,
                          showName: group.showName,
                          senderName: mine
                              ? L10n.t(context, 'chat.you')
                              : partner.name,
                        ),
                      );
                    },
                  ),
          ),
          // Kennenlern-Quiz: schaltet NUR das Foto frei - chatten ist
          // unabhängig möglich. Vorschlag erst nach 50-70 Nachrichten
          // pro Chat (v0.9.1, Schwelle je Match deterministisch).
          if (showQuizBanner)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.photo_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.t(context, 'chat.quizBanner'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      final serverId =
                          int.tryParse(widget.matchId);
                      if (serverId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(L10n.t(
                                context, 'chat.quizUnavailable')),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      // Push: Zurück landet wieder in DIESEM Chat.
                      context.push(AppRoutes.quizPath(serverId));
                    },
                    child: Text(L10n.t(context, 'chat.quizOpen')),
                  ),
                ],
              ),
            ),
          // Neues Aufnahme-Design (v0.9.1, wie IntroEditor): Live-Dauer,
          // Lautstärke-Balken, Pause/Fortsetzen, Verwerfen, Stoppen/Senden
          // in einer Karte OBERHALB der Eingabezeile - statt nur Mic/X und
          // Sekunden im Hint-Text (altes Design).
          if (_recording) _buildVoiceRecordingPanel(context),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image),
                    tooltip: L10n.t(context, 'chat.imageSend'),
                    // E: Während eines Uploads deaktivieren.
                    onPressed: _uploadingImage ? null : _pickImage,
                  ),
                  IconButton(
                    icon: Icon(
                        _recording ? Icons.stop : Icons.mic),
                    tooltip: _recording
                        ? L10n.t(context, 'chat.voiceStopSend')
                        : L10n.t(context, 'chat.voiceTooltip'),
                    color: _recording ? Colors.red : null,
                    onPressed: _toggleRecord,
                  ),
                  // D: Separater "X"-Abbrechen-Button während der Aufnahme.
                  if (_recording)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: L10n.t(context, 'chat.voiceCancel'),
                      color: Colors.red,
                      onPressed: _cancelRecording,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      // A/B: Mehrzeilig wachsend (wie WhatsApp/Telegram), Text
                      // bricht um statt horizontal zu scrollen. Umlaute (ö, ä,
                       // ü) werden durch Dart/Flutter standardmäßig als UTF-16
                      // verarbeitet und korrekt angezeigt - ein horizontaler
                      // Scrolleffekt (alte Einzeilen-Darstellung) hätte sie am
                      // rechten Rand "unsichtbar" gemacht.
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _recording
                            ? L10n.tf(context, 'chat.recordingHint',
                                {'s': '$_recordSeconds'})
                            : L10n.t(context, 'chat.hint'),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // E: Während des Bild-Uploads Ladeindikator statt Senden.
                  if (_uploadingImage)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                ],
              ),
            ),
          ),
        ],
          ),
        ],
      ),
    );
  }
}

/// Sprechende Blase für Text-, Bild- und Sprachnachrichten mit
/// Playback-Unterstützung für Voice.
///
/// Nutzerwunsch Gruppierung: [showName] blendet den Absendernamen über
/// der Bubble ein (neue Gruppe nach Senderwechsel, > 3 Minuten Abstand
/// oder max. 3 Nachrichten am Stück). Jede Nachricht bleibt in ihrer
/// eigenen Bubble und trägt eine kleine Zeitanzeige.
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.msg,
    required this.mine,
    required this.blurEnabled,
    required this.onReportImage,
    this.showName = false,
    this.senderName = '',
  });

  final Message msg;
  final bool mine;

  /// Bilder (fremder Seite) standardmäßig verpixelt anzeigen?
  final bool blurEnabled;

  /// Meldet dieses Bild als unangemessenen Inhalt.
  final void Function(Message msg) onReportImage;

  /// Namens-Header über der Bubble anzeigen (Gruppenstart)?
  final bool showName;

  /// Anzuzeigender Absendername (z. B. "Du" oder Partnername).
  final String senderName;

  /// Uhrzeit (HH:mm) der Nachricht, lokal formatiert.
  String get _timeLabel {
    try {
      return DateFormat.Hm().format(msg.timestamp.toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  /// Vom Nutzer nach Warnung freigegebene Bilder (Session-lokal).
  bool _revealed = false;

  /// Bereits angesehene View-Once-Bilder (Session-lokal).
  /// Wird beim App-Neustart zurückgesetzt – das ist beabsichtigt,
  /// da der Sender die Kontrolle über die Einmaligkeit hat.
  static final Set<String> _viewedOnceIds = {};

  bool get _isViewOnceViewed =>
      _viewedOnceIds.contains(widget.msg.id) || widget.msg.viewed;

  void _markViewed() {
    _viewedOnceIds.add(widget.msg.id);
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final msg = widget.msg;
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    // Blur-Zustand einmal pro Build berechnen (siehe Bild-Zweig).
    final blurred = widget.blurEnabled && !widget.mine && !_revealed;

    return Column(
      crossAxisAlignment:
          widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Absendername über der Bubble (nur Gruppenstart, Nutzerwunsch).
        if (widget.showName && widget.senderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
            child: Text(
              widget.senderName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
        Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: switch (msg.type) {
        MessageType.image => _isViewOnceViewed && !widget.mine
            ? _buildViewedOncePlaceholder(textColor)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schutz vor unangemessenen Inhalten: Bilder der
                  // Gegenseite sind standardmäßig verpixelt (Einstellung
                  // "blurChatImages", Default an). Freigabe nur nach
                  // ausdrücklicher Bestätigung.
                  GestureDetector(
                    onTap: () {
                      if (blurred) {
                        _confirmRevealImage();
                        return;
                      }
                      if (widget.mine) {
                        _showFullscreenImage(context, msg);
                      } else if (msg.viewOnce) {
                        _showViewOnceImage(context, msg);
                      } else {
                        _showFullscreenImage(context, msg);
                      }
                    },
                    onLongPress: () => _showImageActions(context, blurred),
                    child: Semantics(
                      label: blurred
                          ? L10n.t(context, 'chat.imageBlurredHint')
                          : L10n.t(context, 'chat.imageHint'),
                      button: true,
                      child: Stack(
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: blurred ? 16 : 0,
                            sigmaY: blurred ? 16 : 0,
                          ),
                          child: Container(
                            width: 180,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Colors.purple, Colors.blue],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.image,
                                  color: Colors.white, size: 40),
                            ),
                          ),
                        ),
                        if (blurred)
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.visibility_off,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(L10n.t(context, 'chat.blurred'),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        if (msg.viewOnce)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.all(Radius.circular(6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock, size: 12, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(L10n.t(context, 'chat.viewOnce'),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                      ],
                      ),
                    ),
                  ),
                  if (msg.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child:
                          Text(msg.text, style: TextStyle(color: textColor)),
                    ),
                ],
              ),
        MessageType.voice => _VoiceMessage(
            msgId: msg.id,
            path: msg.mediaUrl ?? '',
            durationSeconds: msg.durationSeconds,
            textColor: textColor,
            mine: mine,
          ),
        _ => Text(
            msg.text,
            style: TextStyle(color: textColor),
          ),
      },
        ),
        // Zeitanzeige unter der Bubble (Nutzerwunsch, dezent).
        if (widget._timeLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
            child: Text(
              widget._timeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
            ),
          ),
      ],
    );
  }

  /// Bestätigt das Entzerren eines verpixelten Bildes mit Warnhinweis.
  void _confirmRevealImage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.revealTitle')),
        content: Text(L10n.t(context, 'chat.revealBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _revealed = true);
            },
            child: Text(L10n.t(context, 'chat.revealAction')),
          ),
        ],
      ),
    );
  }

  /// Aktionsmenü für Bilder: Melden und ggf. Freigeben.
  void _showImageActions(BuildContext context, bool blurred) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: Text(L10n.t(context, 'chat.reportImage')),
              subtitle: Text(L10n.t(context, 'chat.reportImageSub')),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onReportImage(widget.msg);
              },
            ),
            if (blurred)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(L10n.t(context, 'chat.revealAction')),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmRevealImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Platzhalter für bereits angesehene View-Once-Bilder.
  Widget _buildViewedOncePlaceholder(Color textColor) {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade300,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera, size: 28, color: Colors.grey),
            const SizedBox(height: 4),
            Text(L10n.t(context, 'chat.viewedOnce'),
                style: const TextStyle(
                    color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// Zeigt ein View-Once-Bild im Vollbild – NUR EINMAL.
  /// Danach wird die Nachricht als "angesehen" markiert.
  void _showViewOnceImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _markViewed();
          Navigator.of(ctx).pop();
        },
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: double.infinity,
                  height: 320,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.blue],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.image, color: Colors.white, size: 80),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(L10n.t(context, 'chat.viewOnce'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: L10n.t(context, 'chat.closeImageHint'),
                  onPressed: () {
                    _markViewed();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// E: Vollbild-Ansicht des Bildes (Mock-Platzhalter mit Hinweis).
  void _showFullscreenImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: double.infinity,
                height: 320,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple, Colors.blue],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.image, color: Colors.white, size: 80),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Sprachnachricht im NEUEN Design (v0.9.0): Play/Pause-Knopf,
/// Wellenform-Visualisierung (deterministische Balken aus der Message-ID)
/// mit Fortschritt und Dauer. Entschlüsselte Dateien werden nach der
/// Wiedergabe gelöscht (Audit M-17) - die Nachricht kann daher nur
/// EINMAL angehört werden; der Wiederholungs-Versuch zeigt einen
/// verständlichen Hinweis statt eines Roh-Fehlers.
class _VoiceMessage extends StatefulWidget {
  const _VoiceMessage({
    required this.msgId,
    required this.path,
    required this.durationSeconds,
    required this.textColor,
    required this.mine,
  });

  final String msgId;
  final String path;
  final int durationSeconds;
  final Color textColor;
  final bool mine;

  @override
  State<_VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<_VoiceMessage> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _sourceLoaded = false;
  Duration _position = Duration.zero;
  final Duration _length = Duration.zero;
  bool _consumed = false; // Datei nach Wiedergabe gelöscht (M-17).
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  /// Deterministische Balken-Form aus der Message-ID: gleiche Nachricht
  /// sieht bei beiden Seiten identisch aus, keine zwei gleichen Wellen.
  List<double> get _bars {
    final seed = widget.msgId.hashCode;
    final rand = Random(seed);
    return List.generate(24, (_) => 0.25 + rand.nextDouble() * 0.75);
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_consumed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'chat.voiceOnce')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final player = _player ??= AudioPlayer();
      if (_playing) {
        // Echte Pause (v0.9.1): Position bleibt, Fortsetzen per erneutem
        // Tap statt Neustart.
        await player.pause();
        if (mounted) setState(() => _playing = false);
        return;
      }
      if (!_sourceLoaded) {
        await player.setFilePath(widget.path);
        _sourceLoaded = true;
        await _posSub?.cancel();
        _posSub = player.positionStream.listen((p) {
          if (mounted) setState(() => _position = p);
        });
        await _stateSub?.cancel();
        _stateSub = player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed &&
              mounted) {
            setState(() {
              _playing = false;
              _position = Duration.zero;
              _sourceLoaded = false;
              _consumed = true;
            });
            // Audit M-17: Nach der Wiedergabe wird die entschlüsselte Datei
            // sofort entfernt.
            unawaited(_deletePlayedFile());
          }
        });
      }
      await player.play();
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      debugPrint('[VoiceMessage] Wiedergabe fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.voiceOnlyOnce')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Audit M-17: Löscht die lokal entschlüsselte Voice-Datei nach der
  /// Wiedergabe.
  Future<void> _deletePlayedFile() async {
    try {
      final file = File(widget.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort: der globale Sweep (temp_cleanup) entfernt Reste.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = _bars;
    final totalSeconds =
        _length.inSeconds > 0 ? _length.inSeconds : widget.durationSeconds;
    final progress = totalSeconds > 0
        ? _position.inMilliseconds / (totalSeconds * 1000)
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          visualDensity: VisualDensity.compact,
          tooltip: _playing
              ? L10n.t(context, 'intro.review.pause')
              : L10n.t(context, 'intro.review.listen'),
          onPressed: _toggle,
          // Weiß auf Primär-Button (v0.9.1-Fix: vorher Primär auf
          // Primär bei eigenen Nachrichten = unsichtbar).
          icon: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 132,
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < bars.length; i++)
                Container(
                  width: 3,
                  height: 6 + 22 * bars[i],
                  decoration: BoxDecoration(
                    color: _consumed
                        ? widget.textColor.withValues(alpha: 0.25)
                        : widget.textColor.withValues(
                            alpha: i / bars.length <= progress ? 1.0 : 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _consumed
              ? L10n.t(context, 'chat.voiceListened')
              : _fmt(totalSeconds),
          style: TextStyle(
            color: widget.textColor,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Geteilte Eisbrecher-Frage als mittige Bubble (v0.9.1): für BEIDE
/// Gesprächsseiten identisch in der Chat-Mitte, wandert wie jede andere
/// Nachricht mit nach oben.
class _IcebreakerBubble extends StatelessWidget {
  const _IcebreakerBubble({required this.text, required this.senderName});

  final String text;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.tertiary.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      senderName,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Das Ideen-Rad (v0.8.0): dreht mit abnehmender Geschwindigkeit und
/// landet auf einer zufälligen Date-Kategorie. Rückgabe via Navigator.pop
/// (gewählter Vorschlag) oder null (Abbruch).
class _MeetIdeaWheelDialog extends StatefulWidget {
  const _MeetIdeaWheelDialog({required this.categories});

  final List<String> categories;

  @override
  State<_MeetIdeaWheelDialog> createState() => _MeetIdeaWheelDialogState();
}

class _MeetIdeaWheelDialogState extends State<_MeetIdeaWheelDialog> {
  bool _spinning = false;
  String? _result;
  int _index = 0;

  Future<void> _spin() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    final rng = Random();
    final target = rng.nextInt(widget.categories.length);
    // Abnehmende Zyklen: wirkt wie ein echtes Rad, das ausläuft.
    var delay = 60;
    var rounds = 24 + rng.nextInt(8);
    var i = 0;
    while (rounds > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
      rounds--;
      i++;
      if (i % 6 == 0) delay += 25; // auslaufen
    }
    // Landen auf dem Ziel.
    while (_index != target) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.categories.length;
      });
    }
    if (!mounted) return;
    setState(() {
      _result = widget.categories[target];
      _spinning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.casino_outlined,
          color: Theme.of(context).colorScheme.primary, size: 36),
      title: Text(L10n.t(context, 'chat.wheelTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _result ??
                    widget.categories[_index % widget.categories.length],
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (_result == null)
              FilledButton.icon(
                onPressed: _spin,
                icon: const Icon(Icons.refresh),
                label: Text(L10n.t(context, 'chat.wheelSpin')),
              )
            else ...[
              Text(
                L10n.t(context, 'chat.wheelHint'),
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_result != null)
          TextButton(
            onPressed: _spin,
            child: Text(L10n.t(context, 'chat.wheelAgain')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.t(context, 'common.cancel')),
        ),
        if (_result != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_result),
            child: Text(L10n.t(context, 'chat.wheelSend')),
          ),
      ],
    );
  }
}
