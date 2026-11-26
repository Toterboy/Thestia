// Der Teil '_VerificationTabState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../admin_screen.dart';

class _VerificationTabState extends ConsumerState<_VerificationTab> {
  List<Map<String, dynamic>> _items = [];
  // Stichproben: Auto-Freigaben für die nachträgliche Kontrolle
  // (v0.9.0, Manipulationsschutz).
  List<Map<String, dynamic>> _auditItems = [];
  bool _loading = true;
  String? _error;
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(supabaseDatabaseServiceProvider);
      final rows = await db.fetchPendingVerifications();
      _items = rows.map((r) {
        final copy = Map<String, dynamic>.from(r);
        copy['submittedAt'] = DateTime.tryParse(
          '${copy['submittedAt']}',
        )?.toLocal();
        return copy;
      }).toList();
      // Größte Altersabweichung zuerst (v0.9.1, 80-als-22-Fälle oben).
      _items.sort((a, b) => _deviation(b).compareTo(_deviation(a)));
      // Stichproben laden - EIGENER try/catch: Fehlt die RPC (Migration
      // 120 noch nicht deployed), darf die Pending-Queue NICHT brechen.
      try {
        final auditRows = await db.fetchAutoVerifications();
        _auditItems = auditRows.map((r) {
          final copy = Map<String, dynamic>.from(r);
          copy['submittedAt'] = DateTime.tryParse(
            '${copy['submittedAt']}',
          )?.toLocal();
          return copy;
        }).toList();
      } catch (e) {
        debugPrint('[Admin] Auto-Stichproben n/a (Migration 120?): $e');
        _auditItems = [];
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Betrag |KI-Schätzung - angegebenes Alter| (-1 = unbekannt).
  static double _deviation(Map<String, dynamic> data) {
    final est = (data['estimatedAge'] as num?)?.toDouble();
    final stated = (data['statedAge'] as num?)?.toDouble();
    if (est == null || stated == null) return -1;
    return (est - stated).abs();
  }

  Future<void> _review(String targetUserId, {required bool approve}) async {
    setState(() => _busyUserId = targetUserId);
    try {
      // MIT ZEITLIMIT (15.11.2026): Ein Aufruf ohne Grenze blieb
      // stehen, wenn die Function keine Antwort bekam - der
      // Admin-Screen blieb dann mit dem Ladeindikator stehen.
      await SupabaseService.rufeEdgeFunktion(
        'verify-account',
        body: {
          'action': 'review',
          'targetUserId': targetUserId,
          'isVerified': approve,
        },
      );
      await _load();
      refreshAdminCounts(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.reviewFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  /// Kurzlebige signierte URL vom Server holen und Video ansehen.
  Future<void> _watch(String targetUserId) async {
    // Vor den Awaits einlesen (kein BuildContext über async-Gaps).
    final noUrl = L10n.t(context, 'admin.noVideoUrl');
    final browserFailed = L10n.t(context, 'admin.browserOpenFailed');
    try {
      final response = await SupabaseService.rufeEdgeFunktion(
        'verification-media',
        body: {'targetUserId': targetUserId},
      );
      final url = (response.data as Map?)?['url'] as String?;
      if (url == null) {
        throw StateError(noUrl);
      }
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(browserFailed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'admin.videoFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    }
  }

  /// Karte für einen Verifizierungsfall (Pending-Queue und Auto-
  /// Stichproben teilen sich Darstellung + Aktionen).
  Widget _verificationCard(BuildContext context, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '?';
    final userId = data['userId'] as String? ?? '?';
    final busy = _busyUserId == userId;
    // KI-Schätzung vs. angegebenes Alter (v0.9.1, Migration 095).
    final est = (data['estimatedAge'] as num?)?.toDouble();
    final stated = (data['statedAge'] as num?)?.toDouble();
    final dev = _VerificationTabState._deviation(data);
    // Minderjährigkeitsfall (v0.10.0, Migration 144).
    //
    // 'pending_minor' heißt: die Person ist 21 oder jünger und wird
    // IMMER von Hand geprüft. Ohne eigene Anzeige steht sie in der
    // Warteschlange wie jeder andere Fall - und genau die Person, um
    // die es am meisten geht, ist damit am leichtesten zu übersehen.
    final isMinorCase = data['status'] == 'pending_minor';
    final ageLine = (est == null || stated == null)
        ? L10n.tf(context, 'admin.ageNoAi', {
            'stated': stated?.toStringAsFixed(0) ?? '?',
          })
        : L10n.tf(context, 'admin.ageAi', {
            'stated': stated.toStringAsFixed(0),
            'est': est.toStringAsFixed(0),
            'dev': dev.toStringAsFixed(0),
          });
    // Abweichung > 2 Jahre färbt die Karte rot. Das ist die einzige
    // Stelle im Screen, die eine semantische Farbe benutzt - sie markiert
    // den Fall, der vor allen anderen zu prüfen ist.
    final flagged = dev > 2;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: (flagged || isMinorCase)
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        title: Row(
          children: [
            if (isMinorCase) ...[
              Icon(
                Icons.child_care,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(child: Text(name)),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(userId),
            Text(
              ageLine,
              style: TextStyle(fontWeight: flagged ? FontWeight.bold : null),
            ),
            if (isMinorCase)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  L10n.t(context, 'admin.minorCase'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: L10n.t(context, 'admin.watchVideo'),
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => _watch(userId),
                  ),
                  IconButton(
                    tooltip: L10n.t(context, 'admin.approve'),
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _review(userId, approve: true),
                  ),
                  IconButton(
                    tooltip: L10n.t(context, 'admin.rejectWithVideo'),
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _review(userId, approve: false),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(
        message: L10n.tf(context, 'admin.error', {'error': '$_error'}),
        onRetry: _load,
      );
    }
    // Beide Queues leer: EIN Leerzustand statt zweierhalber. Vorher stand
    // "Keine offenen Verifizierungen" oben und "Keine Auto-Freigaben" darunter
    // - zwei Sätze für den Zustand "nichts zu tun".
    if (_items.isEmpty && _auditItems.isEmpty) {
      return EmptyState(
        icon: Icons.verified_outlined,
        title: L10n.t(context, 'admin.emptyVerificationsTitle'),
        message: L10n.t(context, 'admin.noVerifications'),
      );
    }
    // Pending-Queue UND Auto-Stichproben in EINER scrollbaren Liste
    // (v0.9.0, Manipulationsschutz): Auto-Freigaben werden weiterhin
    // nachträglich prüfbar gehalten (Video ansehen, bei Missbrauch
    // entziehen).
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final data in _items) ...[
            _verificationCard(context, data),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              L10n.t(context, 'admin.auditTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (_auditItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  L10n.t(context, 'admin.auditEmpty'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (final data in _auditItems) ...[
              _verificationCard(context, data),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}
