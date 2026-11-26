// Der Teil '_ActiveSessionButtonState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist über `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unverändert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_event_screen.dart';

class _ActiveSessionButtonState extends ConsumerState<_ActiveSessionButton> {
  /// Die zuletzt gesehene Session. Damit wird erkannt, WENN eine neue
  /// Session entsteht (nicht nur, dass eine da ist).
  String? _letzteSessionId;

  /// Die Rückfrage wurde für diese Session schon gestellt.
  bool _gefragt = false;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(
      myActiveDatingHourSessionProvider(widget.eventId),
    );

    return sessionAsync.when(
      loading: () => _PrimaryActionButton(
        icon: Icons.hourglass_top,
        label: L10n.t(context, 'dh.searching'),
        onPressed: null,
        // Die Theme-Farbe (siehe _PrimaryActionButton): im Wartezustand
        // kein festes Grau, sondern die Farbe des gewählten Themes.
        color: Theme.of(context).colorScheme.primary,
      ),
      error: (err, _) => _PrimaryActionButton(
        icon: Icons.error_outline,
        label: L10n.t(context, 'dh.event.loadError'),
        onPressed: null,
        color: Theme.of(context).colorScheme.error,
      ),
      data: (session) {
        // BEFUND (07.11.2026, Betreiber): "kein Chat-Erzwang (mit
        // Abfrage)". Wenn die Paarung stand, wurde der Nutzer in den
        // Chat gedrückt - ohne zu fragen. Jetzt kommt eine Rückfrage:
        // reinschauen oder später?
        if (session != null) {
          final neu = session.id != _letzteSessionId;
          _letzteSessionId = session.id;
          if (neu && !_gefragt) {
            _gefragt = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fragePartner(context, session.id);
            });
          }
        }
        if (session == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PrimaryActionButton(
                icon: Icons.search,
                label: L10n.t(context, 'dh.event.searchingPartner'),
                onPressed: null,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              // BEFUND (14.11.2026, Betreiber): "Bei Dating Hour
              // irgendwie umsetzen, dass von beiden Geschlechtern
              // welche in dem Event sind, wenn alle Hetero."
              //
              // Der Server paart jetzt nur noch über die Geschlechter
              // hinweg (Migration 216 + 217). Wer nicht gepaart wird,
              // wartet auf Menschen des anderen Geschlechts - das steht
              // hier, damit das Warten einen Grund hat und nicht wie
              // ein Fehler wirkt.
              Text(
                L10n.t(context, 'dh.event.genderMixHint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        return _PrimaryActionButton(
          icon: Icons.chat_bubble,
          label: L10n.t(context, 'dh.event.toChat'),
          onPressed: () => context.go(AppRoutes.datingHourChatPath(session.id)),
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }

  /// Die Rückfrage nach der Paarung.
  ///
  /// Sie erscheint EINMAL pro Session. Wer "Später" wählt, bleibt auf
  /// dem Bildschirm - der "Zum Chat"-Button bleibt ohnehin da.
  Future<void> _fragePartner(BuildContext context, String sessionId) async {
    final jetzt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.auto_awesome,
          color: Theme.of(ctx).colorScheme.primary,
        ),
        title: Text(L10n.t(ctx, 'dh.event.pairedTitle')),
        content: Text(L10n.t(ctx, 'dh.event.pairedBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'dh.event.chatLater')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'dh.event.chatNow')),
          ),
        ],
      ),
    );
    if (jetzt != true) return;
    if (!context.mounted) return;
    context.go(AppRoutes.datingHourChatPath(sessionId));
  }
}
