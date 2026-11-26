// Der Teil '_SoftPingInboxState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../transit_radar_screen.dart';

class _SoftPingInboxState extends ConsumerState<_SoftPingInbox>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _pings;
  Timer? _refreshTimer;
  int _idleTicks = 0;

  /// 15 s im aktiven Fall, im Leerlauf gestreckt. Soft-Pings entstehen
  /// selten; vorher feuerte der Timer alle 15 s einen RPC, auch wenn die
  /// Liste stundenlang leer blieb.
  static const List<Duration> _intervals = [
    Duration(seconds: 15),
    Duration(seconds: 40),
    Duration(minutes: 2),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleRefresh();
  }

  /// Eine Benachrichtigung über einen neuen Funke holt den Nutzer aus der
  /// App heraus. Ohne diesen Haken wartete die Liste im ungünstigsten Fall
  /// bis zu zwei Minuten - der Timer streckt im Leerlauf bewusst ab, und
  /// im Hintergrund liefert er ohnehin nichts Verlässliches. Beim
  /// Zurückkommen in die App sofort nachladen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // AKKU (03.11.2026): Im Hintergrund wird nicht gepollt. Vorher lief
      // der Timer weiter und feuerte alle 15 Sekunden einen echten
      // Server-Request - auch wenn der Screen gar nicht sichtbar war.
      // Der Screen bleibt im Backstack gemountet, also lief der Timer
      // unbegrenzt weiter.
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _idleTicks = 0;
    _load().then((_) {
      if (mounted) _scheduleRefresh();
    });
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!mounted) return;
    final step = _idleTicks.clamp(0, _intervals.length - 1);
    _refreshTimer = Timer(_intervals[step], () async {
      if (!mounted) return;
      final before = _idleTicks;
      await _load();
      if (!mounted) return;
      if (_idleTicks == before && _idleTicks < _intervals.length - 1) {
        _idleTicks++;
      }
      _scheduleRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      final pings = await db.listMySoftPings();
      if (pings.isEmpty) {
        _idleTicks = _idleTicks < _intervals.length - 1
            ? _idleTicks + 1
            : _idleTicks;
      } else {
        _idleTicks = 0;
      }
      if (mounted) setState(() => _pings = pings);
    } catch (_) {
      if (mounted) setState(() => _pings = []);
    }
  }

  Future<void> _accept(Map<String, dynamic> ping) async {
    try {
      final db = SupabaseDatabaseService(SupabaseService.client);
      final res = await db.acceptSoftPing(ping['id'] as String);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (res['matched'] == true) {
        // BEFUND (07.11.2026, Betreiber): "Funke wurde angezeigt, ist
        // dann aber wieder verschwunden." Nach dem Annehmen verschwand
        // der Funke ersatzlos aus der Liste - der Nutzer wusste nicht,
        // was daraus wurde.
        //
        // Deshalb sagt die App jetzt, was passiert ist, und bietet den
        // Weg zum Chat an - als Knopf, nicht als Zwang (der Betreiber
        // wollte ausdrücklich kein Chat-Erzwang).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'transit.acceptDone')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: L10n.t(context, 'transit.toChat'),
              onPressed: () async {
                if (!mounted) return;
                // Die Annahme liefert die match_id (Migration 194) - damit
                // geht es direkt in den Chat des neuen Funkens. Ohne sie
                // (älterer Server) geht es zu den Funken, wo er steht.
                final matchId = res['match_id'];
                if (matchId is num && matchId > 0) {
                  // BEFUND (07.11.2026, Betreiber): "Wenn man von
                  // Transit Spark in einen Chat geht, soll auch wenn
                  // Transit Spark noch an ist gefragt werden, ob es
                  // an bleiben soll."
                  //
                  // Dieselbe Frage wie beim Verlassen des Radar-
                  // Bildschirms: läuft der Radar weiter, oder soll
                  // er gestoppt werden? Ohne diese Frage bleibt der
                  // Radar im Hintergrund senden - der Nutzer hat das
                  // aber nicht entschieden.
                  final darfWeiter = await confirmTransitExit(context, ref);
                  if (!darfWeiter || !mounted) return;
                  context.push(AppRoutes.chatDetailPath(matchId.toString()));
                } else {
                  context.push(AppRoutes.interessen);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      // Vorher wurde der Fehler KOMPLETT verschluckt: kein Log, keine
      // Meldung. Der Nutzer tippte auf "annehmen" und es passierte
      // sichtbar nichts - genau der Befund. Ohne eine Ausgabe ist das
      // nicht von einem wirkungslosen Aufruf zu unterscheiden.
      debugPrint('[TransitRadar] Funke annehmen fehlgeschlagen: $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final message =
          '${L10n.t(context, 'transit.inboxTitle')}: '
          '${L10n.tf(context, 'common.errorWith', {'error': '$e'})}';
      await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Der Kopf der Ping-Karte: der Name des Absenders - oder die anonyme
  /// Meldung.
  ///
  /// BEFUND (10.11.2026, Betreiber): "Ich finde aber, dass man bei Transit
  /// Spark einstellen können soll, ob der Name für andere sichtbar sein
  /// soll oder nicht."
  ///
  /// DER GRUND: Der Server liefert den Namen nur, wenn der Absender ihn
  /// mit `transit_show_name` freigegeben hat (Migration 208). Fehlt der
  /// Name, bleibt die Meldung anonym - die Anonymität ist der
  /// Normalzustand, nicht die Ausnahme.
  Widget _pingHeadline(BuildContext context, Map<String, dynamic> ping) {
    final absender = (ping['senderName'] as String?)?.trim();
    final text = (absender != null && absender.isNotEmpty)
        ? L10n.tf(context, 'transit.waveFrom', {'name': absender})
        : L10n.t(context, 'transit.waveFromAnonymous');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _dismiss(Map<String, dynamic> ping) async {
    // BEFUND (07.11.2026, Betreiber): "Funke wurde angezeigt, ist dann
    // aber wieder verschwunden."
    //
    // Das Ausblenden LÖSCHT die Zeile - unwiderruflich. Und der Knopf
    // sitzt genau dort, wo der Finger schon liegt, wenn die Liste
    // gerade gewachsen ist: ein unbedachter Tippen vernichtet den
    // Funken. Deshalb fragt die App jetzt vorher nach.
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'transit.ignoreConfirmTitle')),
        content: Text(L10n.t(ctx, 'transit.ignoreConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'transit.ignoreConfirmOk')),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    // Still ausblenden: Zeile löschen (Absender sieht nichts).
    await bestEffort('from.delete', () async {
      await SupabaseService.client
          .from('transit_soft_pings')
          .delete()
          .eq('id', ping['id'] as String);
    });
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pings = _pings;
    if (pings == null || pings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.t(context, 'transit.inboxTitle'),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final ping in pings)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BEFUND (10.11.2026): Der Name des Absenders steht
                  // hier - aber NUR, wenn er ihn freigegeben hat. Der
                  // Server entscheidet das (transit_show_name); fehlt der
                  // Name, bleibt die Meldung anonym.
                  _pingHeadline(context, ping),
                  // BEFUND (11.11.2026): Der Ort des Absenders steht bei
                  // der Meldung - er weiß sonst nicht, wo er suchen
                  // soll ("Wagen 3").
                  if ((ping['placeText'] as String?)?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        (ping['placeText'] as String).trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Text(
                    L10n.t(
                      context,
                      'transit.preset.${ping['messageKey'] ?? 'wave'}',
                    ),
                  ),
                  if ((ping['customLine'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        ping['customLine'] as String,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  // DER UMBRUCH (18.11.2026, gefunden von einem Test): Die
                  // beiden Knopfe standen in einer festen Reihe - bei
                  // großer Schrift (oder einer System-Schriftgrösse
                  // über 100 %) lief die Reihe über den Rand
                  // ("RenderFlex overflowed").
                  //
                  // DER WEG: Ein "Wrap" bricht die Reihe um, statt zu
                  // überlaufen. Bei normaler Schrift steht alles
                  // weiterhin nebeneinander.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => _dismiss(ping),
                        child: Text(L10n.t(context, 'transit.ignore')),
                      ),
                      FilledButton(
                        onPressed: () => _accept(ping),
                        child: Text(L10n.t(context, 'transit.accept')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
