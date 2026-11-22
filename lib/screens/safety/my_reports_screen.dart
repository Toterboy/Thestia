import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/profile/report_service.dart';

/// Die eigenen Meldungen mit ihrem Bearbeitungsstand.
///
/// NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen sollen
/// beide als einzelne Screens, damit der Safety Center Screen nicht
/// überladen wird, wenn es viele blockierungen und oder Meldungen
/// gibt."
///
/// Vorher stand diese Liste direkt im Safety Center - eine Zeile je
/// Meldung. Jetzt hat sie ihren eigenen Screen.
///
/// Es stehen bewusst nur der Status und der Typ der Meldung hier -
/// keine Details über Dritte (das ist der Grund für diese Ansicht).
class MyReportsScreen extends ConsumerStatefulWidget {
  const MyReportsScreen({super.key});

  @override
  ConsumerState<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends ConsumerState<MyReportsScreen> {
  List<MyReportEntry>? _reports;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await SupabaseService.client.rpc('list_my_reports');
      final rows = (response as List<dynamic>? ?? <dynamic>[]);
      final reports = rows
          .map(
            (row) =>
                MyReportEntry.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      if (mounted) setState(() => _reports = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'safety.myReports'))),
      body: _reports == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _reports!.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  L10n.t(context, 'safety.noReports'),
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _reports!.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final report = _reports![index];
                return ListTile(
                  leading: Icon(
                    report.status == 'pending'
                        ? Icons.hourglass_top
                        : Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    report.reportType.isEmpty
                        ? L10n.t(context, 'report.type.default')
                        : report.reportType,
                  ),
                  subtitle: Text(report.statusLabel),
                );
              },
            ),
    );
  }
}
