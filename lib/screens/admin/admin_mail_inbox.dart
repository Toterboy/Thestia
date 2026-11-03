import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/supabase_database_service.dart';
import 'package:thestia/services/supabase_service.dart';

/// Der Posteingang im Admin-Bereich.
///
/// NUR LESEN. Es gibt absichtlich keine Antwortfunktion: ein Antwortpfad
/// aus der App heraus braeuchte SMTP-Zugang und eine zweite
/// Absenderidentitaet - im Kinderschutz waere die Gefahr real, aus dem
/// falschen Konto zu schreiben (Migration 168).
///
/// Die Mails kommen aus `public.mail_messages`. Zwei Wege speisen sie:
/// der IMAP-Abfrage (`tool/mail_imap_poll.py`) und dem Cloudflare
/// Email Worker (`deploy/cloudflare/email-worker.js`).
class AdminMailInboxTab extends ConsumerStatefulWidget {
  const AdminMailInboxTab({super.key});

  @override
  ConsumerState<AdminMailInboxTab> createState() => _AdminMailInboxTabState();
}

class _AdminMailInboxTabState extends ConsumerState<AdminMailInboxTab> {
  static const _kategorien = <String?>[
    null,
    'kinderschutz',
    'support',
    'datenschutz',
    'presse',
    'sonstiges',
  ];

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _kategorie;

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
      final db = SupabaseDatabaseService(SupabaseService.client);
      final rows = await db.fetchAdminMailMessages(category: _kategorie);
      _items = rows;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  String _rubrikText(String kategorie) {
    switch (kategorie) {
      case 'kinderschutz':
        return L10n.t(context, 'admin.mailKinderschutz');
      case 'support':
        return L10n.t(context, 'admin.mailSupport');
      case 'datenschutz':
        return L10n.t(context, 'admin.mailDatenschutz');
      case 'presse':
        return L10n.t(context, 'admin.mailPresse');
      default:
        return L10n.t(context, 'admin.mailSonstiges');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            L10n.tf(context, 'admin.error', {'error': '$_error'}),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Die Rubriken: die Anforderung war "aufgeteilt nach Adresse".
          // Der Filter hier ist genau das - eine Kachel je Anschrift.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in _kategorien)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        k == null
                            ? L10n.t(context, 'admin.mailAll')
                            : _rubrikText(k),
                      ),
                      selected: _kategorie == k,
                      onSelected: (_) {
                        setState(() => _kategorie = k);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.t(context, 'admin.mailEmptyTitle'),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    L10n.t(context, 'admin.mailEmptyText'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final mail in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MailKarte(
                  mail: mail,
                  rubrik: _rubrikText(
                    '${mail['category'] ?? 'sonstiges'}',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Eine Mail in der Liste.
class _MailKarte extends StatelessWidget {
  const _MailKarte({required this.mail, required this.rubrik});

  final Map<String, dynamic> mail;
  final String rubrik;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final von = (mail['from_name'] as String?)?.trim().isNotEmpty == true
        ? '${mail['from_name']} <${mail['from_email'] ?? ''}>'
        : '${mail['from_email'] ?? '?'}';
    final betreff = (mail['subject'] as String?)?.trim();
    final empfaenger = '${mail['recipient'] ?? ''}';
    final zeit = _fmtTs(mail['received_at']);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ExpansionTile(
        // Der Kinderschutz-Bereich faellt auf: dort ist eine Mail das
        // Wichtigste, was im Admin-Bereich liegen kann.
        backgroundColor:
            mail['category'] == 'kinderschutz'
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
            : null,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          children: [
            Chip(
              label: Text(rubrik),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                betreff == null || betreff.isEmpty
                    ? L10n.t(context, 'admin.mailWithoutSubject')
                    : betreff,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$von\n$empfaenger · $zeit',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              (mail['body_text'] as String?) ??
                  L10n.t(context, 'admin.mailEmptyBody'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              L10n.t(context, 'admin.mailReadOnly'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTs(dynamic ts) {
    final dt = ts is DateTime ? ts : DateTime.tryParse('${ts ?? ''}');
    if (dt == null) return '';
    final lokal = dt.toLocal();
    String zwei(int v) => v.toString().padLeft(2, '0');
    return '${zwei(lokal.day)}.${zwei(lokal.month)}.${lokal.year} '
        '${zwei(lokal.hour)}:${zwei(lokal.minute)}';
  }
}
