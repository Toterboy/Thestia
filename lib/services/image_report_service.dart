import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wisp/models/message.dart';
import 'package:wisp/models/report_models.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/services/image_safety_service.dart';
import 'package:wisp/services/report_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/utils/constants.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/widgets/ai_badge.dart';

/// Ergebnis der Bild-Meldung mit KI-Vorprüfung.
class ImageReportOutcome {
  const ImageReportOutcome({
    required this.aiAvailable,
    required this.aiAgrees,
    required this.score,
    required this.operatorNotified,
  });

  /// War der KI-Scan verfügbar (Token konfiguriert, kein Fehler)?
  final bool aiAvailable;

  /// Sieht die KI das Bild als unangemessen (NSFW)?
  final bool aiAgrees;

  /// NSFW-Score 0..1 (nur sinnvoll, wenn [aiAvailable]).
  final double score;

  /// Hat die Betreiber-Mail das Team erreicht?
  final bool operatorNotified;
}

/// Bild-Meldung mit automatischer KI-Vorprüfung (Chat-Bilder).
///
/// Grundsatz: Chat-Bilder werden NIE automatisch beim Senden gescannt
/// (E2E). Nur wenn der Empfänger ein Bild meldet, wird exakt dieses eine
/// Bild an die Edge Function `report-image` übermittelt, dort von einem
/// NSFW-Klassifikator geprüft und das Ergebnis (Bild, Report, KI-Score)
/// per E-Mail an das Moderations-Team gesendet.
///
/// Der Meldende erhält das KI-Ergebnis DIREKT zurück:
///  - KI bestätigt -> Team ist informiert, fertig.
///  - KI widerspricht -> der Meldende kann eskalieren (manuelle Prüfung),
///    falls die KI falsch liegt. Auch dann gehen Bild, Report und
///    KI-Ergebnis an das Team.
class ImageReportService {
  /// Maximal übertragene Bildgröße (Base64) - identisch zum Server-Limit.
  static const int _maxBase64 = 3 * 1024 * 1024;

  Future<ImageReportOutcome> reportChatImage({
    required String imageBase64,
    required String reportedUserId,
    required String reason,
    String details = '',
    bool escalate = false,
    List<String> contextMessages = const [],
    double? localScore,
  }) async {
    if (!SupabaseService.isInitialized) {
      throw StateError('Melden derzeit nicht verfügbar (keine Verbindung).');
    }
    if (imageBase64.length > _maxBase64) {
      throw StateError('Bild ist zu groß für die Meldung.');
    }

    // Pseudonymisierte Reporter-ID (SHA-256): Der Klartext-UUID geht nicht
    // über die Kabel, das Moderations-Team kann Meldungen desselben
    // Meldenden trotzdem als zusammengehörig erkennen.
    final reporterIdSha256 =
        sha256.convert(utf8.encode(AppConstants.currentUserId)).toString();

    final response = await SupabaseService.client.functions.invoke(
      'report-image',
      body: {
        'imageBase64': imageBase64,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'details': details,
        'escalate': escalate,
        'contextMessages': contextMessages,
        'reporterIdSha256': reporterIdSha256,
        // Lokales On-Device-Ergebnis (v0.8.0): nur Hinweis für das
        // manuelle Team-Review - KEINE automatischen Kontosperren.
        if (localScore != null)
          'localAi': {'score': localScore},
      },
    );

    if (response.status != 200) {
      throw StateError(
        'Meldung fehlgeschlagen (Status ${response.status}). '
        'Bitte später erneut versuchen.',
      );
    }
    final data = (response.data as Map).cast<String, dynamic>();
    return ImageReportOutcome(
      aiAvailable: data['available'] == true,
      aiAgrees: data['nsfw'] == true,
      score: (data['score'] as num?)?.toDouble() ?? 0,
      operatorNotified: data['notified'] == true,
    );
  }
}

/// Provider für den [ImageReportService].
final imageReportServiceProvider = Provider<ImageReportService>((ref) {
  return ImageReportService();
});

/// Zeigt den Bild-Melde-Dialog mit KI-Vorprüfung und Direkt-Feedback.
///
/// Flow: Grund wählen -> Absenden (Bild + Grund gehen an die KI-Prüfung
/// und das Team) -> Ergebnis-Dialog:
///  - „KI bestätigt": fertig, Team informiert.
///  - „KI widerspricht": optional [Zur manuellen Prüfung] (Eskalation).
/// Parallel wird ein klassischer Report-Eintrag (user_reports) erzeugt,
/// damit die Meldung auch im Admin-Screen „Meldungen" auftaucht.
Future<void> showImageReportDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Message message,
  required String reportedUserId,
  required String reportedUserName,
  List<String> contextMessages = const [],
}) async {
  // Bild-Bytes aus der Data-URL extrahieren (mediaUrl = data:image/...;base64,<bytes>).
  final mediaUrl = message.mediaUrl ?? '';
  final commaIdx = mediaUrl.indexOf(',');
  if (!mediaUrl.startsWith('data:') || commaIdx < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'report.imageUnavailable')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  final imageBase64 = mediaUrl.substring(commaIdx + 1);
  if (imageBase64.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'report.imageUnavailable')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  Uint8List localBytes = Uint8List(0);
  try {
    localBytes = Uint8List.fromList(base64Decode(imageBase64));
  } catch (_) {
    // Dekodierung fehlgeschlagen: lokale Prüfung überspringen, die
    // Meldung selbst bleibt weiterhin möglich.
  }

  ReportType? selectedType;
  final descriptionController = TextEditingController();
  ImageSafetyResult? localResult;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.flag_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(L10n.tf(ctx, 'report.imageTitle',
                    {'name': reportedUserName}))),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LOKALE PRÜFUNG (v0.8.0): läuft auf dem Gerät, das Bild
                // verlässt dafür NICHT das Gerät. Startet automatisch mit
                // dem Öffnen dieses Meldedialogs (manueller Meldungs-Tap).
                _LocalSafetyCheckSection(
                  imageBytes: localBytes,
                  onDone: (r) => localResult = r,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Erst wenn du unten auf "Meldung absenden" tippst, '
                          'wird dieses Bild zur manuellen Prüfung an unser '
                          'Team übertragen. Bricht du ab, wird das Bild '
                          'sofort verworfen und nichts gesendet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Wähle den Grund für die Meldung:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 12),
                RadioGroup<ReportType>(
                  groupValue: selectedType,
                  onChanged: (v) => setState(() => selectedType = v),
                  child: Column(
                    children: [
                      ...ReportType.values.map(
                        (type) => RadioListTile<ReportType>(
                          title: Text(L10n.t(ctx, type.labelKey)),
                          value: type,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: L10n.t(context, 'report.detailsOptional'),
                    hintText: L10n.t(ctx, 'common.whatHappened'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: selectedType == null
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    await _runAiCheck(
                      context: context,
                      ref: ref,
                      imageBase64: imageBase64,
                      reportedUserId: reportedUserId,
                      reportedUserName: reportedUserName,
                      reason: selectedType!.label,
                      details: descriptionController.text.trim(),
                      contextMessages: contextMessages,
                      localScore: localResult?.criticalScore,
                    );
                  },
            child: Text(L10n.t(ctx, 'report.sendReport')),
          ),
        ],
      ),
    ),
  );
  // Dialog geschlossen: Bild-Bytes aus dem Speicher verwerfen (Abbruch
  // oder Versand - in beiden Fällen hält nichts mehr eine Referenz).
  localBytes.fillByZero();
  descriptionController.dispose();
}

extension _ZeroFill on Uint8List {
  void fillByZero() {
    for (var i = 0; i < length; i++) {
      this[i] = 0;
    }
  }
}

/// Lokale Prüf-Sektion im Meldedialog (v0.8.0): Klassifiziert das Bild
/// ON-DEVICE (das Bild verlässt dafür nicht das Gerät) und zeigt das
/// Ergebnis transparent an. Startet automatisch mit dem Öffnen des
/// Dialogs (der Meldungs-Tap ist die manuelle Auslösung).
class _LocalSafetyCheckSection extends StatefulWidget {
  const _LocalSafetyCheckSection({
    required this.imageBytes,
    required this.onDone,
  });

  final Uint8List imageBytes;
  final ValueChanged<ImageSafetyResult?> onDone;

  @override
  State<_LocalSafetyCheckSection> createState() =>
      _LocalSafetyCheckSectionState();
}

class _LocalSafetyCheckSectionState extends State<_LocalSafetyCheckSection> {
  bool _checking = true;
  ImageSafetyResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final result =
        await ImageSafetyService.instance.classifyImage(widget.imageBytes);
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
    });
    widget.onDone(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_iphone,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lokale Prüfung (auf diesem Gerät)',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              AiBadge(
                languageCode:
                    L10n.localeOf(context).languageCode,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_checking)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(L10n.t(context, 'report.analyzing')),
                ),
              ],
            )
          else if (_result == null)
            Text(
              L10n.t(context, 'report.noLocalModel'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (_result!.isFlagged)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 20, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dieses Bild wurde lokal als potenziell anstößig '
                    'eingestuft (Score ${(_result!.criticalScore * 100).toStringAsFixed(0)} %).',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keine eindeutigen Verstöße lokal erkannt '
                    '(Score ${(_result!.criticalScore * 100).toStringAsFixed(0)} %).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Führt den KI-Check durch und zeigt das Ergebnis/Eskalations-Dialoge.
/// [contextMessages]: letzte 3 Textnachrichten als Kontext für das Team.
/// [localScore]: lokales On-Device-Ergebnis (falls verfügbar).
Future<void> _runAiCheck({
  required BuildContext context,
  required WidgetRef ref,
  required String imageBase64,
  required String reportedUserId,
  required String reportedUserName,
  required String reason,
  required String details,
  List<String> contextMessages = const [],
  double? localScore,
}) async {
  // Parallel: Klassischen Report-Eintrag erzeugen (Admin-Sicht
  // „Meldungen"), damit die Bild-Meldung dort ebenfalls auftaucht.
  final reporterName = ref.read(profileProvider).name.isNotEmpty
      ? ref.read(profileProvider).name
      : AppConstants.currentUserId;
  unawaited(
    ref.read(reportServiceProvider).createReport(
          reporterId: AppConstants.currentUserId,
          reporterUserName: reporterName,
          reportedUserId: reportedUserId,
          reportedUserName: reportedUserName,
          type: ReportType.inappropriateContent,
          description: 'Bild-Meldung: $reason${details.isEmpty ? '' : ' - $details'}',
        ),
  );

  // Lade-Dialog (nicht abbrechbar - der Scan dauert wenige Sekunden).
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(L10n.t(context, 'report.checkingTitle')),
            ),
            AiBadge(
              languageCode: L10n.localeOf(context).languageCode,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(L10n.t(context, 'report.checkingSub')),
          ],
        ),
      ),
    ),
  ));

  ImageReportOutcome outcome;
  try {
    outcome = await ref.read(imageReportServiceProvider).reportChatImage(
          imageBase64: imageBase64,
          reportedUserId: reportedUserId,
          reason: reason,
          details: details,
          contextMessages: contextMessages,
          localScore: localScore,
        );
  } catch (e) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // Lade-Dialog schließen
    }
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(ctx, 'report.failedTitle')),
          content: Text(
            e is StateError ? e.message : L10n.t(context, 'report.retryLater'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(ctx, 'common.ok')),
            ),
          ],
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  if (Navigator.of(context).canPop()) Navigator.of(context).pop();

  // Fall 1: KI bestätigt die Meldung.
  if (outcome.aiAvailable && outcome.aiAgrees) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.verified_user_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(L10n.t(context, 'report.confirmed'))),
            AiBadge(
              languageCode: L10n.localeOf(context).languageCode,
            ),
          ],
        ),
        content: Text(
          '${L10n.tf(ctx, 'report.aiConfirm', {
                'score': (outcome.score * 100).toStringAsFixed(0)
              })}\n\n${outcome.operatorNotified ? L10n.t(ctx, 'report.aiEscalated') : L10n.t(ctx, 'report.aiNotNotified')}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.ok')),
          ),
        ],
      ),
    );
    return;
  }

  // Fall 2: KI widerspricht ODER nicht verfügbar -> Eskalations-Option.
  final aiText = outcome.aiAvailable
      ? 'Die KI stuft das Bild NICHT als unangemessen ein '
          '(Score ${(outcome.score * 100).toStringAsFixed(0)}%). '
          'Falls sie damit falsch liegt, kannst du das Bild zur manuellen '
          'Prüfung durch unser Team weiterleiten.'
      : 'Die automatische KI-Prüfung ist gerade nicht verfügbar. '
          'Du kannst das Bild direkt zur manuellen Prüfung durch unser '
          'Team weiterleiten.';

  final escalate = await showDialog<bool>(
    context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.psychology_alt_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(L10n.t(ctx, 'report.aiResult'))),
            AiBadge(
              languageCode: L10n.localeOf(ctx).languageCode,
            ),
          ],
        ),
      content: Text(aiText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.done')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L10n.t(context, 'report.forwardBtn')),
        ),
      ],
    ),
  );

  if (escalate != true || !context.mounted) return;

  // Eskalation: erneut senden (escalate=true) - Bild, Report und frisches
  // KI-Ergebnis gehen an das Team.
  try {
    await ref.read(imageReportServiceProvider).reportChatImage(
          imageBase64: imageBase64,
          reportedUserId: reportedUserId,
          reason: reason,
          details: details,
          escalate: true,
          contextMessages: contextMessages,
          localScore: localScore,
        );
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(ctx, 'report.forwardedTitle')),
          content: Text(
            L10n.t(ctx, 'report.forwardedBody'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(ctx, 'common.ok')),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[ImageReport] Eskalation fehlgeschlagen: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(L10n.t(context, 'report.forwardFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
