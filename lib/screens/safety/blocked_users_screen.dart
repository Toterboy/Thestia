import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/profile/report_service.dart';

/// Die blockierten Nutzer - mit der Möglichkeit, sie zu entsperren.
///
/// NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen sollen
/// beide als einzelne Screens, damit der Safety Center Screen nicht
/// überladen wird, wenn es viele blockierungen und oder Meldungen
/// gibt."
///
/// Vorher stand diese Liste direkt im Safety Center - eine Zeile je
/// blockiertem Nutzer. Bei vielen Blockierungen wurde der Screen
/// unbrauchbar (alles Weiterscrollen). Jetzt hat die Liste ihren
/// eigenen Screen; das Safety Center zeigt nur noch den Einstieg.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<BlockedUserEntry>? _blocked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await SupabaseService.client.rpc('list_blocked_users');
      final rows = (response as List<dynamic>? ?? <dynamic>[]);
      final blocked = rows
          .map(
            (row) => BlockedUserEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      if (mounted) setState(() => _blocked = blocked);
    } catch (_) {
      if (mounted) setState(() => _blocked = []);
    }
  }

  Future<void> _unblock(BlockedUserEntry entry) async {
    try {
      await SupabaseService.client.rpc(
        'unblock_user',
        params: {'p_blocked': entry.blockedUserId},
      );
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'safety.unblockFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t(context, 'safety.blockedUsers'))),
      body: _blocked == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _blocked!.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  L10n.t(context, 'safety.noBlocked'),
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _blocked!.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _blocked![index];
                return ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: Text(entry.name),
                  trailing: TextButton(
                    onPressed: () => _unblock(entry),
                    child: Text(L10n.t(context, 'safety.unblock')),
                  ),
                );
              },
            ),
    );
  }
}
