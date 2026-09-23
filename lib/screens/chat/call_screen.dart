import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/data/icebreaker_catalog.dart';
import 'package:wisp/services/p2p_chat_service.dart';
import 'package:wisp/services/supabase_service.dart';

/// ID des aktuell aktiven Anrufs (oder null).
///
/// Verhindert doppelte Anruf-Screens und wird vom Chat-Screen genutzt, um
/// eingehende Anrufe nur anzunehmen, wenn gerade kein Anruf läuft.
final activeCallIdProvider = StateProvider<String?>((ref) => null);

/// Anruf-Status.
enum CallStatus { connecting, ringingOutgoing, ringingIncoming, connected, declined, ended, unreachable }

/// Anruf-Screen mit echter E2E-P2P-Sprachkommunikation.
///
/// Architektur:
/// - Signaling (invite/accept/decline/end) läuft E2E-verschlüsselt über den
///   bestehenden WebRTC-DataChannel ([P2PChatService.sendCallControl]) -
///   keine Metadaten an den Server außer dem WebRTC-Aufbau selbst.
/// - Sprache wird per Push-to-Talk aufgenommen (record), Signal-verschlüsselt
///   als Binärpaket über den DataChannel gesendet und beim Empfänger mit
///   just_audio abgespielt. Halbduplex, aber vollständig E2E + P2P.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.partnerName,
    required this.peerId,
    this.isIncoming = false,
    this.incomingCallId,
    super.key,
  });

  final String partnerName;
  final String peerId;
  final bool isIncoming;
  final String? incomingCallId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  static const Duration _ringTimeout = Duration(seconds: 30);
  static const int _maxRecordSeconds = 60;

  P2PChatService? _p2p;
  String? _myUserId;
  String? _callId;
  CallStatus _status = CallStatus.connecting;
  int _seconds = 0;
  Timer? _durationTimer;
  Timer? _ringTimer;
  Timer? _recordTimer;
  Timer? _endTimer;
  int _recordSeconds = 0;
  bool _disposed = false;
  // Stumm-Schaltung: deaktiviert Push-to-Talk, bis wieder entstummt.
  bool _muted = false;

  StreamSubscription<Map<String, dynamic>>? _controlSub;
  StreamSubscription<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>? _audioSub;

  // Sprachaufnahme (echtes Mikrofon via record).
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  bool _recording = false;
  bool _sendingAudio = false;

  // Wiedergabe eingehender Sprachpakete (just_audio, sequenziell).
  final AudioPlayer _player = AudioPlayer();
  final List<String> _playQueue = [];
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _callId = widget.incomingCallId ??
        'call_${DateTime.now().millisecondsSinceEpoch}';
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _durationTimer?.cancel();
    _ringTimer?.cancel();
    _recordTimer?.cancel();
    _endTimer?.cancel();
    _controlSub?.cancel();
    _audioSub?.cancel();
    if (_recording) {
      _recording = false;
      _recorder.stop().catchError((_) => '');
    }
    _playQueue.clear();
    try {
      _player.stop();
    } catch (_) {}
    _player.dispose();
    _recorder.dispose();
    if (ref.read(activeCallIdProvider) == _callId) {
      ref.read(activeCallIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _init() async {
    ref.read(activeCallIdProvider.notifier).state = _callId;

    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;
    // Eigene ID strikt aus der Supabase-Session (Fix: keine Stale- oder
    // Demo-Fallbacks - sie erzeugen ein Topic ohne die echte auth.uid(),
    // wodurch RLS den Join verweigert; dieselbe Auflösung wie im Chat).
    _myUserId = SupabaseService.isInitialized
        ? SupabaseService.currentUser?.id
        : null;

    // Kontroll-Kanal (Signaling) abonnieren.
    _controlSub = p2p.callControl.listen(_onControlMessage);

    // Sprachpakete abonnieren.
    _audioSub = p2p.callAudio.listen(_onCallAudio);

    // Verbindung sicherstellen (läuft nur, wenn noch kein DataChannel offen ist;
    // KEIN zweites connect bei bestehender Verbindung - das würde den
    // Chat-Kanal killen).
    try {
      if (!p2p.isConnected) {
        final myId = _myUserId;
        if (myId == null || myId.isEmpty) {
          throw StateError('Keine Nutzer-ID für Signaling');
        }
        await p2p.connect(myUserId: myId, peerId: widget.peerId);
      }
      // Auf offenen DataChannel warten (max. 10 s), bevor das Invite raus
      // geht - vorher scheiterte es sofort mit StateError.
      if (!widget.isIncoming && !p2p.isDataChannelOpen) {
        try {
          await p2p.connectionState
              .firstWhere(
                (s) => s == RTCDataChannelState.RTCDataChannelOpen,
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Timeout oder Stream-Ende: unten folgt die Prüfung.
        }
        if (!p2p.isDataChannelOpen) {
          throw StateError('DataChannel nicht offen');
        }
      }
    } catch (e) {
      debugPrint('[CallScreen] Verbindung fehlgeschlagen: $e');
      if (mounted) {
        setState(() => _status = CallStatus.unreachable);
        _endAfterDelay();
      }
      return;
    }

    if (!mounted) return;

    if (widget.isIncoming) {
      setState(() => _status = CallStatus.ringingIncoming);
      _startIncomingTimeout();
    } else {
      setState(() => _status = CallStatus.ringingOutgoing);
      _startRingTimer();
      try {
        await p2p.sendCallControl({
          'type': 'invite',
          'callId': _callId,
          'from': _myUserId,
        });
      } catch (e) {
        debugPrint('[CallScreen] Invite fehlgeschlagen: $e');
        if (mounted) {
          setState(() => _status = CallStatus.unreachable);
          _endAfterDelay();
        }
      }
    }
  }

  /// Eingehender Anruf ohne Annahme (45 s): auflegen statt ewig klingeln.
  void _startIncomingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 45), () async {
      if (!mounted) return;
      if (_status == CallStatus.ringingIncoming) {
        await _sendControlSafely({'type': 'end', 'callId': _callId});
        if (!mounted) return;
        _stopCallTimers();
        setState(() => _status = CallStatus.ended);
        _endAfterDelay();
      }
    });
  }

  /// Hält alle Anruf-Timer an (bei decline/end/hangup).
  void _stopCallTimers() {
    _durationTimer?.cancel();
    _ringTimer?.cancel();
    _recordTimer?.cancel();
  }

  void _startRingTimer() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () async {
      if (!mounted) return;
      if (_status == CallStatus.ringingOutgoing ||
          _status == CallStatus.connecting) {
        setState(() => _status = CallStatus.unreachable);
        await _sendControlSafely({'type': 'end', 'callId': _callId});
        _endAfterDelay();
      }
    });
  }

  void _onControlMessage(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final callId = payload['callId'] as String?;
    if (type == null) return;
    // callId ist Pflicht und muss zu DIESEM Anruf gehören (leere/fremde
    // IDs werden verworfen statt Ghost-Calls zu erzeugen).
    if (callId == null || callId.isEmpty || callId != _callId) {
      // Anklopfen während aktivem Anruf: sofort besetzt melden, damit der
      // Anrufer nicht 30 s ins Leere wartet.
      if (type == 'invite' &&
          (_status == CallStatus.connected ||
              _status == CallStatus.ringingIncoming ||
              _status == CallStatus.ringingOutgoing)) {
        _sendControlSafely({
          'type': 'decline',
          'callId': callId ?? '',
          'busy': true,
        });
      }
      return;
    }

    switch (type) {
      case 'accept':
        // Nur aus Klingel-Zuständen annehmen (kein Reanimieren toter Calls).
        if (!mounted ||
            (_status != CallStatus.ringingOutgoing &&
                _status != CallStatus.connecting)) {
          return;
        }
        _ringTimer?.cancel();
        setState(() {
          _status = CallStatus.connected;
          _seconds = 0;
        });
        _startDuration();
        break;
      case 'decline':
        if (!mounted) return;
        _stopCallTimers();
        _stopRecorderSilently();
        setState(() => _status = CallStatus.declined);
        _endAfterDelay();
        break;
      case 'end':
        if (!mounted) return;
        _stopCallTimers();
        _stopRecorderSilently();
        setState(() => _status = CallStatus.ended);
        _endAfterDelay();
        break;
      case 'invite':
        // Gleiche callId erneut (Retry): bereits behandelt, ignorieren.
        break;
    }
  }

  /// Stoppt eine laufende Aufnahme ohne UI-Nebenwirkungen (Remote-Ende).
  void _stopRecorderSilently() {
    _recordTimer?.cancel();
    if (_recording) {
      _recording = false;
      _recorder.stop().catchError((_) => '');
    }
  }

  static const int _maxPlayQueue = 5;

  void _onCallAudio(
      ({Uint8List data, String contentType, Map<String, dynamic>? metadata}) record) async {
    // Nur im verbundenen Anruf abspielen (kein Klingel-/End-Geplapper),
    // Queue begrenzen (kein /tmp-Vollaufen bei Spam).
    if (_disposed || _status != CallStatus.connected) return;
    if (_playQueue.length >= _maxPlayQueue) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/wisp_call_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await file.writeAsBytes(record.data);
      if (_disposed) {
        try {
          await file.delete();
        } catch (_) {}
        return;
      }
      _playQueue.add(file.path);
      _processQueue();
    } catch (e) {
      debugPrint('[CallScreen] Sprachpaket konnte nicht gespeichert werden: $e');
    }
  }

  Future<void> _processQueue() async {
    if (_playing || _playQueue.isEmpty || _disposed) return;
    _playing = true;
    while (_playQueue.isNotEmpty && !_disposed) {
      final path = _playQueue.removeAt(0);
      try {
        await _player.setFilePath(path);
        if (_disposed) break;
        await _player.play();
        await _player.playerStateStream
            .firstWhere((s) => s.processingState == ProcessingState.completed)
            .timeout(const Duration(minutes: 2), onTimeout: () => _player.playerState);
      } catch (e) {
        debugPrint('[CallScreen] Wiedergabe fehlgeschlagen: $e');
      } finally {
        try {
          await _player.stop();
        } catch (_) {}
        final f = File(path);
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _playing = false;
  }

  void _startDuration() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  // ---------------------------------------------------------------- PTT --

  Future<void> _startTalking() async {
    if (_status != CallStatus.connected) return;
    if (_recording || _sendingAudio || _muted) return;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'chat.callMicDenied')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/wisp_ptt_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 48000,
        ),
        path: path,
      );
      _recordingPath = path;
      _recordSeconds = 0;
      if (!mounted) return;
      setState(() => _recording = true);

      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= _maxRecordSeconds) {
          _stopTalking();
        }
      });
    } catch (e) {
      debugPrint('[CallScreen] Aufnahme fehlgeschlagen: $e');
    }
  }

  Future<void> _stopTalking() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final path = _recordingPath;
    _recordingPath = null;
    _recording = false;
    if (!mounted) {
      try {
        await _recorder.stop();
      } catch (_) {}
      return;
    }
    setState(() {
      _sendingAudio = true;
    });

    try {
      final recordedPath = await _recorder.stop();
      if (recordedPath == null || path == null) {
        if (mounted) setState(() => _sendingAudio = false);
        return;
      }
      final file = File(recordedPath);
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}

      if (bytes.isEmpty) {
        if (mounted) setState(() => _sendingAudio = false);
        return;
      }

      await _p2p?.sendCallAudio(
        bytes,
        metadata: {'durationSeconds': _recordSeconds},
      );
    } catch (e) {
      debugPrint('[CallScreen] Sprachpaket konnte nicht gesendet werden: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'chat.callVoiceFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingAudio = false);
      }
    }
  }

  // ------------------------------------------------------------ Steuerung --

  Future<void> _sendControlSafely(Map<String, dynamic> payload) async {
    try {
      await _p2p?.sendCallControl(payload);
    } catch (e) {
      debugPrint('[CallScreen] Kontroll-Nachricht fehlgeschlagen: $e');
    }
  }

  Future<void> _accept() async {
    if (_status != CallStatus.ringingIncoming) return;
    _ringTimer?.cancel();
    await _sendControlSafely({'type': 'accept', 'callId': _callId});
    if (!mounted) return;
    setState(() {
      _status = CallStatus.connected;
      _seconds = 0;
    });
    _startDuration();
  }

  Future<void> _decline() async {
    _ringTimer?.cancel();
    _stopRecorderSilently();
    await _sendControlSafely({'type': 'decline', 'callId': _callId});
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _hangUp() async {
    _stopCallTimers();
    _endTimer?.cancel();
    _stopRecorderSilently();
    await _sendControlSafely({'type': 'end', 'callId': _callId});
    // P2P-Verbindung bewusst NICHT schließen: der Chat-Datachannel bleibt
    // für Nachrichten offen.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Eisbrecher-Sammlung während des Anrufs (Nutzerwunsch): Kategorien
  /// als Chips, Fragen als Karten zum Laut-Vorlesen. Reine Anzeige -
  /// nichts wird gesendet oder gespeichert.
  Future<void> _showIcebreakerSheet() async {
    final lang = Localizations.localeOf(context).languageCode;
    String? selectedCategory;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cats = icebreakerCatalog;
          final active = selectedCategory == null
              ? cats
              : cats.where((c) => c.id == selectedCategory).toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      L10n.t(ctx, 'call.icebreakerTitle'),
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.t(ctx, 'call.icebreakerHint'),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: Text(L10n.t(ctx, 'genderpref.all')),
                            selected: selectedCategory == null,
                            onSelected: (_) => setSheetState(
                                () => selectedCategory = null),
                          ),
                          const SizedBox(width: 6),
                          for (final c in cats) ...[
                            ChoiceChip(
                              avatar: Icon(c.icon, size: 16),
                              label: Text(c.titleFor(lang)),
                              selected: selectedCategory == c.id,
                              onSelected: (_) => setSheetState(() =>
                                  selectedCategory = c.id),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final c in active) ...[
                            if (selectedCategory == null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 4),
                                child: Text(
                                  c.titleFor(lang),
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ),
                            for (final q in c.questions)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    q.textFor(lang),
                                    style:
                                        Theme.of(ctx).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _endAfterDelay() {
    _endTimer?.cancel();
    _endTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  String _formatDuration() {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _statusText(BuildContext context) => switch (_status) {
        CallStatus.connecting => L10n.t(context, 'chat.callStatusConnecting'),
        CallStatus.ringingOutgoing =>
          L10n.t(context, 'chat.callStatusRingingOut'),
        CallStatus.ringingIncoming =>
          L10n.t(context, 'chat.callStatusRingingIn'),
        CallStatus.connected => _recording
            ? L10n.tf(context, 'chat.callStatusRecording',
                {'s': '$_recordSeconds'})
            : L10n.t(context, 'chat.callStatusConnected'),
        CallStatus.declined => L10n.t(context, 'chat.callStatusDeclined'),
        CallStatus.ended => L10n.t(context, 'chat.callStatusEnded'),
        CallStatus.unreachable =>
          L10n.t(context, 'chat.callStatusUnreachable'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRingIncoming = _status == CallStatus.ringingIncoming;
    final isRingOutgoing = _status == CallStatus.ringingOutgoing;
    final isConnected = _status == CallStatus.connected;
    final isFinal = _status == CallStatus.declined ||
        _status == CallStatus.ended ||
        _status == CallStatus.unreachable;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            const CircleAvatar(
              radius: 56,
              child: Icon(Icons.person, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              widget.partnerName,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isConnected ? _formatDuration() : _statusText(context),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // Mobilfunk-Hinweis (Betreiber-Entscheidung: kein TURN -> keine
            // Relay-Sprache): dezent während des Aufbaus, prominent im
            // Fehlerzustand.
            if (_status == CallStatus.connecting ||
                _status == CallStatus.ringingOutgoing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  L10n.t(context, 'chat.callNetHint'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_status == CallStatus.unreachable)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off,
                          size: 18, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          L10n.t(context, 'chat.callNetHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isConnected && _recording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  L10n.t(context, 'chat.callPttHold'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const Spacer(),
            if (isRingIncoming)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'accept',
                    backgroundColor: Colors.green,
                    onPressed: _accept,
                    child: const Icon(Icons.call),
                  ),
                  const SizedBox(width: 48),
                  FloatingActionButton(
                    heroTag: 'decline',
                    backgroundColor: Colors.red,
                    onPressed: _decline,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              )
            else if (isRingOutgoing || _status == CallStatus.connecting)
              FloatingActionButton(
                heroTag: 'cancel',
                backgroundColor: Colors.red,
                onPressed: _hangUp,
                child: const Icon(Icons.call_end),
              )
            else if (isConnected)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Stumm-Schalter: deaktiviert Push-to-Talk.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'mute',
                        backgroundColor: _muted
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        onPressed: () =>
                            setState(() => _muted = !_muted),
                        child: Icon(
                          _muted ? Icons.mic_off : Icons.mic,
                          color: _muted
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _muted
                            ? L10n.t(context, 'chat.callMuted')
                            : L10n.t(context, 'chat.callUnmuted'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  // Push-to-Talk: Halten zum Sprechen.
                  GestureDetector(
                    onTapDown: (_) => _startTalking(),
                    onTapUp: (_) => _stopTalking(),
                    onTapCancel: _stopTalking,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _muted
                            ? theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5)
                            : _recording
                                ? Colors.red
                                : Colors.green,
                        boxShadow: _muted
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Icon(
                        _muted
                            ? Icons.mic_off_outlined
                            : _recording
                                ? Icons.stop
                                : Icons.mic,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Eisbrecher-Sammlung (Nutzerwunsch): Während des Anrufs
                  // in den Fragen stöbern und laut stellen, wenn es still
                  // wird. Reine Anzeige - nichts wird gesendet.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'icebreakers',
                        backgroundColor: theme
                            .colorScheme.surfaceContainerHighest,
                        onPressed: _showIcebreakerSheet,
                        child: Icon(
                          Icons.lightbulb_outline,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.t(context, 'call.icebreakerTitle'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  FloatingActionButton.large(
                    heroTag: 'hangup',
                    backgroundColor: Colors.red,
                    onPressed: _hangUp,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              )
            else if (isFinal)
              const SizedBox()
            else
              FloatingActionButton(
                heroTag: 'hangup_fallback',
                backgroundColor: Colors.red,
                onPressed: _hangUp,
                child: const Icon(Icons.call_end),
              ),
            const SizedBox(height: 16),
            if (isConnected)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      L10n.t(context, 'chat.callE2eInfo'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.battery_charging_full_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            L10n.t(context, 'chat.callBatteryHint'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
