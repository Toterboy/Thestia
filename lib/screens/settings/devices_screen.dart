import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/auth_exception.dart';
import 'package:thestia/services/device_session_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/widgets/buttons.dart';

/// Ergebnis eines Ladevorgangs: Liste + optionaler Registrierungs-Hinweis
/// (das eigene Gerät konnte nicht aktualisiert werden - die Liste wird
/// trotzdem gezeigt).
class _DevicesLoadResult {
  const _DevicesLoadResult(this.devices, this.enrollError);
  final List<DeviceSession> devices;
  final String? enrollError;
}

/// "Wo bin ich eingeloggt?": Liste aller Geräte, auf denen das Konto
/// angemeldet ist (Migration 071), mit der Möglichkeit, sich ÜBERALL
/// außer auf diesem Gerät abzumelden (GoTrue signOut scope=others).
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  Future<_DevicesLoadResult>? _future;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DevicesLoadResult> _load() async {
    final service = ref.read(deviceSessionServiceProvider);
    // Eigene Registrierung/last_seen auffrischen - FEHLER werden nicht
    // verschluckt, sondern als Hinweis über der Liste gezeigt (damit
    // "Tabelle fehlt" vs. "kein Netz" unterscheidbar ist).
    String? enrollError;
    try {
      await service.enrollCurrentDevice().timeout(const Duration(seconds: 8));
    } on AppException catch (e) {
      enrollError = e.message;
    } catch (_) {
      enrollError = 'Das eigene Gerät konnte nicht registriert werden. '
          'Bitte Verbindung prüfen.';
    }
    final devices = await service.listDevices();
    return _DevicesLoadResult(devices, enrollError);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _confirmLogoutEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout,
            color: Theme.of(ctx).colorScheme.primary, size: 36),
        title: Text(L10n.t(ctx, 'devices.logoutTitle')),
        content: Text(L10n.t(ctx, 'devices.logoutBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'devices.logoutBtn')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOut = true);
    try {
      await ref
          .read(deviceSessionServiceProvider)
          .logoutEverywhereExceptCurrent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'devices.logoutDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _reload();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'devices.logoutFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  String _formatSeen(DateTime utc) {
    try {
      final local = utc.toLocal();
      final now = DateTime.now();
      final diff = now.difference(local);
      if (diff.inMinutes < 2) return L10n.t(context, 'devices.activeNow');
      if (diff.inMinutes < 60) {
        return '${L10n.t(context, 'devices.activeMinutesA')} ${diff.inMinutes} '
            '${L10n.t(context, 'devices.activeMinutesB')}';
      }
      if (diff.inHours < 24) {
        return '${L10n.t(context, 'devices.activeHoursA')} ${diff.inHours} '
            '${L10n.t(context, 'devices.activeHoursB')}';
      }
      return '${L10n.t(context, 'devices.activeLastSeen')} '
          '${DateFormat('dd.MM.yyyy').format(local)}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'devices.title')),
        actions: [
          IconButton(
            tooltip: L10n.t(context, 'common.refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_DevicesLoadResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final err = snapshot.error!;
            final message =
                err is AppException ? err.message : err.toString();
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.devices_other,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SecondaryButton(
                  label: L10n.t(context, 'devices.retry'),
                  onPressed: _reload,
                ),
              ],
            );
          }
          final result =
              snapshot.data ?? const _DevicesLoadResult([], null);
          final devices = result.devices;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (result.enrollError != null) ...[
                Card(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.enrollError!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                L10n.t(context, 'devices.hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              for (final device in devices)
                Card(
                  child: ListTile(
                    leading: Icon(
                      device.isCurrent
                          ? Icons.smartphone
                          : Icons.devices_other,
                      color: device.isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      device.label,
                      style: device.isCurrent
                          ? TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    subtitle: Text(
                      [
                        if (device.isCurrent)
                          L10n.t(context, 'devices.current'),
                        if (device.appVersion != null &&
                            device.appVersion!.isNotEmpty)
                          'App ${device.appVersion}',
                        _formatSeen(device.lastSeenAt),
                      ].where((s) => s.isNotEmpty).join(' · '),
                    ),
                  ),
                ),
              if (devices.isEmpty && result.enrollError == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    L10n.t(context, 'devices.empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),
              if (SupabaseService.isInitialized) ...[
                SecondaryButton(
                  label: _signingOut
                      ? L10n.t(context, 'devices.signingOut')
                      : L10n.t(context, 'devices.logoutBtnLong'),
                  onPressed: _signingOut ? null : _confirmLogoutEverywhere,
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.t(context, 'devices.logoutNote'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
