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

import 'package:thestia/models/chat/match.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/gender.dart' show RelationshipType;
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/utils/chat/chat_backgrounds.dart';
import 'package:thestia/widgets/chat/chat_background_picker.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/services/dating_hour/find_your_match_service.dart'
    show findYourMatchServiceProvider;
import 'package:thestia/widgets/chat/heart_moments.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/screens/interests/interessen_screen.dart'
    show interessenInitialTabProvider;
import 'package:thestia/services/profile/image_report_service.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/chat/message_envelope.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/screens/chat/bucket_list_sheet.dart'
    show BucketListSheet;
import 'package:thestia/services/dating_hour/quiz_service.dart';
import 'package:thestia/services/chat/relay_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/data/icebreaker_catalog.dart';
import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/utils/chat/exif_stripper.dart';
import 'package:thestia/widgets/common/audio_review_sheet.dart';
import 'package:thestia/widgets/chat/chat_bubbles.dart';
import 'package:thestia/widgets/chat/end_spark_dialog.dart';
import 'package:thestia/widgets/profile/intro_audio_player.dart';
import 'package:thestia/widgets/profile/meet_intent_card.dart';
import 'package:thestia/widgets/profile/profile_widgets.dart';
import 'package:thestia/widgets/chat/secure_composer.dart';
import 'package:thestia/widgets/chat/stimmen_nudge.dart';
import 'package:thestia/widgets/chat/sync_date_antizipation.dart';
import 'package:thestia/widgets/chat/sync_date_card.dart';
import 'package:thestia/widgets/chat/sync_date_zeitwahl.dart';
import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/providers/dating_hour/sync_date_provider.dart';
import 'package:thestia/widgets/chat/nachricht_ueberdenken.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/chatdialoge.dart';

part 'parts/chateisbrecher.dart';

part 'parts/chatsprache.dart';

part 'parts/chatbilder.dart';

part 'parts/chatnachrichten.dart';
part 'parts/chatnachrichtpruefung.dart';

part 'parts/chatp2p.dart';

part 'parts/chatrelay.dart';

part 'parts/messagebubble.dart';
part 'parts/messagebubblestate.dart';
part 'parts/voicemessage.dart';
part 'parts/voicemessagestate.dart';
part 'parts/icebreakerbubble.dart';
part 'parts/meetideawheeldialog.dart';
part 'parts/meetideawheeldialogstate.dart';
part 'parts/swipetoclose.dart';
part 'parts/swipetoclosestate.dart';
part 'parts/chatimage.dart';
part 'parts/imagebubbleplaceholder.dart';
part 'parts/chatdetailaufbau.dart';
part 'parts/chatdetailsyncdate.dart';
part 'parts/chatdetailstimmen.dart';

/// Präfix für geteilte Eisbrecher-Fragen im Textkanal (v0.9.1): Beide Seiten
/// stellen solche Nachrichten als gemeinsame mittige Bubble dar.

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
  bool get _blurChatImages => ref.watch(settingsProvider).blurChatImages;

  // Echte E2E-P2P-Verbindung (Signaling + WebRTC + PreKey).
  P2PChatService? _p2p;
  String? _myUserId;
  StreamSubscription<String>? _msgSub;
  StreamSubscription<
    ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
  >?
  _binarySub;
  StreamSubscription<Map<String, dynamic>>? _callControlSub;
  StreamSubscription<dynamic>? _connSub;
  StreamSubscription<void>? _relayPingSub;
  StreamSubscription<String>? _problemSub;

  /// Das letzte Problem aus dem P2P-Aufbau (für die Diagnosezeile).
  ///
  /// 06.11.2026: Die internen Meldungen des WebRTC-Service gingen nur
  /// in den Debug-Log. Im Store-Build - dem, in dem der Betreiber
  /// testet - war deshalb nicht zu sehen, woran der Aufbau scheiterte.
  String? _lastP2pProblem;
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

  /// Die Notifier der beiden "aktiver Chat"-Markierungen.
  ///
  /// BEFUND (14.11.2026, gefunden von einem Test): Riverpod hat den
  /// Consumer-State im `dispose()` schon abgeräumt - ein `ref.read()`
  /// dort wirft ("Cannot use ref after the widget was disposed"). Damit
  /// blieb die Notification-Unterdrückung BIS ZUM APP-ENDE stehen: die
  /// Meldungen des Partners kamen nicht mehr an.
  ///
  /// DER WEG: Die Notifier werden im `initState` geholt. Der
  /// StateNotifier lebt länger als der Screen - so wird die
  /// Unterdrückung wirklich wieder aufgehoben.
  late final StateController<String?> _aktiveChatId;
  late final StateController<String?> _aktiveChatPeerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Die Notifier jetzt holen: im dispose() ist `ref` nicht mehr
    // benutzbar (siehe die Erklären beim Feld).
    _aktiveChatId = ref.read(activeChatIdProvider.notifier);
    _aktiveChatPeerId = ref.read(activeChatPeerIdProvider.notifier);

    // Alles, was Provider-State anfasst, wartet auf den ersten Frame.
    //
    // Riverpod verbietet das Ändern eines Providers in einer
    // Lebenszyklus-Phase ausdrücklich und nennt initState in der
    // Fehlermeldung: "Tried to modify a provider while the widget tree
    // was building". Zwei Stellen taten genau das hier:
    //
    //   * activeChatIdProvider wird unten synchron gesetzt - das ist ein
    //     Schreibzugriff Whährend des Aufbaus, und die Zuhörer des
    //     Providers hängen zu diesem Zeitpunkt noch nicht.
    //   * _bootstrap() beginnt mit hydrateHistory(), das den State des
    //     ChatNotifier setzt; die Microtask-Auflösung landete dadurch
    //     mitten im Aufbau.
    //
    // In der App fällt beides nicht auf, weil der Screen normalerweise
    // über eine Route geöffnet wird und ein Frame vergeht. Sichtbar
    // wird es, sobald der Screen als erstes gerendert wird - etwa im
    // Screenshot-Render. Der Fix ist unabhängig davon richtig: Provider
    // gehören nach dem Frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // NUTZERWUNSCH: Unterdrückt die Lokal-Benachrichtigung für
      // eingehende Nachrichten, solange dieser Chat geöffnet ist
      // (Nachricht sichtbar).
      _aktiveChatId.state = widget.matchId;
      unawaited(_bootstrap());
      unawaited(_loadQuizGate());
      unawaited(_loadIdeaWheelHidden());
      unawaited(_maybeShowBackgroundHint());
    });

    // Relay-Polling (5 s, Fix "Nachrichten kommen nicht an"): Der Partner
    // pingt nach relay_store sofort, aber falls der Ping verloren geht,
    // holt der Timer spätestens nach 5 s nach. Pausiert im Hintergrund.
    _startRelayTimer();
  }

  /// Relay-Ticker als Einmal-Timer mit variablem Intervall.
  ///
  /// Der Wake-up-Ping liefert Nachrichten sofort; dieser Timer fängt nur
  /// verlorene Pings ab. Ein aktiver Chat ohne Nachrichtenverkehr ist der
  /// Normalfall - deshalb wird das Intervall bei leerem Ergebnis gestreckt
  /// (3 s -> 10 s -> 20 s) statt stur alle 3 s einen RPC zu feuern. Kommt
  /// etwas an, geht es sofort zurück auf 3 s.
  static const List<Duration> _relayIntervals = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];
  int _relayBackoffStep = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hintergrund: kein Polling/Netz (Akku). Vordergrund: Timer neu +
    // sofort abholen (Nachrichten aus der Abwesenheit).
    //
    // `hidden` zählen mit: auf Android kommt es direkt nach `inactive`,
    // wenn der Nutzer den App-Switcher öffnet - der Poller soll da
    // ebenfalls sofort enden statt 3 s weiterzulaufen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _relayTimer?.cancel();
      _relayTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      _relayBackoffStep = 0;
      _startRelayTimer();
      unawaited(_fetchRelay());
      // Rückkehr in den Chat: ggf. sofort neu verbinden statt bis zum
      // nächsten Timer-Takt zu warten (Drossel greift trotzdem).
      unawaited(_retryHandshakeThrottled());
    }
  }

  @override
  void dispose() {
    // Aktiven Chat freigeben (sonst bliebe die Notification-Unterdrückung
    // für diese Chat-ID aktiv, obwohl der Screen weg ist).
    //
    // `ref` wird VOR super.dispose() ausgewertet, und nur, wenn der
    // Container noch lebt. Riverpod hat den Consumer-State zum Zeitpunkt
    // von dispose() bereits abgeräumt: ein ref.read() hier wirft
    // "Cannot use ref after the widget was disposed" - sichtbar wurde das
    // beim Wechsel aus dem Chat heraus (Route pop, Test-Teardown), nicht
    // im Normalbetrieb, weil dort der Screen seltener abgeräumt wird
    // während ein Chat aktiv ist.
    _clearActiveChatFlags();
    _icebreakerSuggestTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _binarySub?.cancel();
    _callControlSub?.cancel();
    _connSub?.cancel();
    _relayPingSub?.cancel();
    _problemSub?.cancel();
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

  @override
  Widget build(BuildContext context) => _baueChat(context);

  /// Setzt den Zustand - aufrufbar auch aus den Erweiterungen.
  ///
  /// DER GRUND: In einer Erweiterung darf `setState` nicht aufgerufen
  /// werden (der Analyser erlaubt es nur in Instanzmitgliedern einer
  /// State-Klasse). Diese Methode gehört zur Klasse - die Erweiterung
  /// ruft sie auf.
  void _setzeState(VoidCallback fn) => setState(fn);
}
