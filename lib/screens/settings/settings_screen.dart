// Passkeys sind ein Supabase-Beta-Feature (@experimental) - die Nutzung
// ist bewusst; die Hinweise werden auf Dateiebene ignoriert.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Passkey;

import 'package:wisp/models/profile_visibility.dart';
import 'package:wisp/providers/auth_provider.dart';
import 'package:wisp/providers/chat_provider.dart';
import 'package:wisp/providers/profile_provider.dart';
import 'package:wisp/providers/settings_provider.dart';
import 'package:wisp/routing/app_router.dart';
import 'package:wisp/screens/privacy/privacy_screen.dart' show promptTotpCode;
import 'package:wisp/services/auth_exception.dart';
import 'package:wisp/services/encryption_service.dart';
import 'package:wisp/services/local_storage.dart';
import 'package:wisp/services/mfa_service.dart';
import 'package:wisp/services/passkey_auth.dart';
import 'package:wisp/services/prekey_service.dart';
import 'package:wisp/services/supabase_database_service.dart';
import 'package:wisp/services/supabase_service.dart';
import 'package:wisp/services/unified_push_service.dart';
import 'package:wisp/utils/age_safety_rules.dart';
import 'package:wisp/widgets/buttons.dart';
import 'package:wisp/widgets/selectable_tile.dart';
import 'package:wisp/l10n/app_strings.dart';
import 'package:wisp/widgets/language_switch.dart';
import 'package:wisp/widgets/theme_picker.dart';

/// Spiegelt den Rest der UI-Einstellungen nach profiles.ui_prefs (v0.8.0,
/// Migration 074) - damit überstehen Blind Mode, Sichtbarkeit, Dark Mode
/// und alle Benachrichtigungs-Schalter eine Neuinstallation. Entprellt,
/// best effort.
void _persistUiPrefs(WidgetRef ref) {
  scheduleUiPrefsServerSync(ref.read(settingsProvider));
}

/// Einstellungen: Blind Mode, Foto-Freigabe, Sichtbarkeit, Theme, Logout.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final profile = ref.watch(profileProvider);

    // Altersbasierte Sicherheits-Regeln anwenden
    final userAge = profile.age;
    if (kDebugMode) {
      // Geburtsdatum ist PII – nur im Debug-Modus loggen (Audit H4).
      debugPrint('[SETTINGS] profile.age=${profile.age}, birthDate=${profile.birthDate}, userAge=$userAge');
    }
    // Falls kein Alter bekannt (kein birthDate), Mindestalter 16 als Fallback für UI
    final effectiveAge = userAge ?? 16;
    final ageGroup = AgeSafetyRules.ageGroup(effectiveAge);
    final (allowedAgeMin, allowedAgeMax) = AgeSafetyRules.clampFilterAge(
      viewerAge: effectiveAge,
      filterMin: settings.ageRangeMin,
      filterMax: settings.ageRangeMax,
    );
    if (kDebugMode) {
      debugPrint('[SETTINGS] ageGroup=$ageGroup, allowedAgeMin=$allowedAgeMin, allowedAgeMax=$allowedAgeMax');
    }

    // Falls die aktuellen Werte außerhalb des erlaubten Bereichs liegen, korrigieren
    if (settings.ageRangeMin != allowedAgeMin || settings.ageRangeMax != allowedAgeMax) {
      // Async-Korrektur (nicht im build)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setAgeRange(allowedAgeMin, allowedAgeMax);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'settings.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: L10n.t(context, 'common.back'),
          // P: Zurück zum aufrufenden Screen (Profil/Aktuelles). Falls die
          // Einstellungen direkt (z. B. Deep-Link) geöffnet wurden, fallback
          // auf "Aktuelles".
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.privacySection')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'settings.whoCanSee'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final v in ProfileVisibility.values)
                    SelectableTile<ProfileVisibility>(
                      value: v,
                      groupValue: settings.profileVisibility,
                      title: L10n.t(context, v.labelKey),
                      subtitle: switch (v) {
                        ProfileVisibility.everyone =>
                          L10n.t(context, 'settings.visEveryoneSub'),
                        ProfileVisibility.matchesOnly =>
                          L10n.t(context, 'settings.visMatchesSub'),
                        ProfileVisibility.hidden =>
                          L10n.t(context, 'settings.visHiddenSub'),
                      },
                      onChanged: (val) async {
                        if (val == null || val == settings.profileVisibility) {
                          return;
                        }
                        // 'Unsichtbar (Pausiert)' bestätigen lassen, damit
                        // kein versehentlicher Tap das Profil versteckt.
                        if (val == ProfileVisibility.hidden) {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: Icon(
                                Icons.pause_circle,
                                color: Theme.of(ctx).colorScheme.primary,
                                size: 40,
                              ),
                              title: Text(
                                  L10n.t(ctx, 'settings.pauseConfirmTitle')),
                              content:
                                  Text(L10n.t(ctx, 'settings.pauseConfirmBody')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child:
                                      Text(L10n.t(ctx, 'common.cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(
                                      L10n.t(ctx, 'settings.pauseConfirmBtn')),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                        }
                        await notifier.setProfileVisibility(val);
                        if (context.mounted) {
                          // Meldung nur bei echten Pause-UEBERGAENGEn -
                          // der Wechsel Jeder <-> Nur Funken hat mit der
                          // Pause nichts zu tun.
                          final wasPause = settings.profileVisibility ==
                              ProfileVisibility.hidden;
                          final isPause = val == ProfileVisibility.hidden;
                          if (isPause != wasPause) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isPause
                                      ? L10n.t(context, 'settings.pauseOn')
                                      : L10n.t(context, 'settings.pauseOff'),
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    L10n.t(context, 'settings.localDataNote'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.communitySafety')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.gavel),
                    title: Text(L10n.t(context, 'settings.communityRules')),
                    subtitle:
                        Text(L10n.t(context, 'settings.communityRulesSub')),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.communityGuidelines),
                  ),
                  if (SupabaseService.isInitialized) ...[
                    const Divider(),
                    // Eigene Stateful-Kachel: Doppel-Tap-Schutz. Zwei
                    // parallel laufende Passkey-Registrierungen brechen
                    // sich gegenseitig ab ("Anfrage abgebrochen von Wisp"
                    // / "credential verification failed").
                    const _PasskeyTile(),
                    const _PasskeyManagerCard(),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(L10n.t(context, 'settings.twoFactor')),
                      subtitle: Text(
                        ref.watch(mfaStatusProvider).hasVerifiedFactors
                            ? L10n.t(context, 'settings.twoFactorActive')
                            : L10n.t(context, 'settings.twoFactorSetup'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      contentPadding: EdgeInsets.zero,
                      onTap: () async {
                        // MFA-Status FRISCH laden (nicht den gecachten
                        // Provider vertrauen): Sonst zeigt die Kachel nach
                        // dem Einrichten fälschlich "nicht aktiv" und der
                        // Passkey-Precheck unten greift nicht.
                        if (SupabaseService.isInitialized) {
                          try {
                            final fresh = await MfaService(SupabaseService.client)
                                .loadStatus();
                            ref.read(mfaStatusProvider.notifier).state = fresh;
                          } catch (_) {
                            // Best-Effort: alter Stand bleibt.
                          }
                        }
                        if (context.mounted) {
                          context.push(AppRoutes.mfaSetup);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.notifications')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'settings.push'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L10n.t(context, 'settings.pushEnable')),
                    subtitle:
                        Text(L10n.t(context, 'settings.pushEnableSub')),
                    value: settings.notificationsEnabled,
                    onChanged: (v) {
                      notifier.setNotificationsEnabled(v);
                      _persistUiPrefs(ref);
                    },
                  ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L10n.t(context, 'settings.notifyFunken')),
                    subtitle:
                        Text(L10n.t(context, 'settings.notifyFunkenSub')),
                    value: settings.notifyMatches,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyMatches(v);
                            _persistUiPrefs(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L10n.t(context, 'settings.notifyLikes')),
                    subtitle:
                        Text(L10n.t(context, 'settings.notifyLikesSub')),
                    value: settings.notifyLikes,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyLikes(v);
                            _persistUiPrefs(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L10n.t(context, 'settings.notifyMessages')),
                    subtitle:
                        Text(L10n.t(context, 'settings.notifyMessagesSub')),
                    value: settings.notifyMessages,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyMessages(v);
                            _persistUiPrefs(ref);
                          }
                        : null,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text(L10n.t(context, 'settings.notifyDatingHour')),
                    subtitle: Text(
                        L10n.t(context, 'settings.notifyDatingHourSub')),
                    value: settings.notifyDatingHour,
                    onChanged: settings.notificationsEnabled
                        ? (v) {
                            notifier.setNotifyDatingHour(v);
                            _persistUiPrefs(ref);
                          }
                        : null,
                  ),
                  const Divider(),
                  const _UnifiedPushTile(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.appearance')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L10n.t(context, 'settings.appearance'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // String-Keys statt bool? (siehe Einrichtung):
                  // Radio mit null-Value verschluckt Taps.
                  SelectableTile<String>(
                    value: 'system',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: L10n.t(context, 'settings.system'),
                    onChanged: (_) { notifier.setDarkMode(null); _persistUiPrefs(ref); },
                  ),
                  SelectableTile<String>(
                    value: 'light',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: L10n.t(context, 'settings.light'),
                    onChanged: (_) { notifier.setDarkMode(false); _persistUiPrefs(ref); },
                  ),
                  SelectableTile<String>(
                    value: 'dark',
                    groupValue: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    title: L10n.t(context, 'settings.dark'),
                    onChanged: (_) { notifier.setDarkMode(true); _persistUiPrefs(ref); },
                  ),
                  const SizedBox(height: 12),
                  Text(L10n.t(context, 'settings.colors'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ThemePicker(
                    selectedName: settings.themeName,
                    onChanged: (t) {
                      ref.read(settingsProvider.notifier).setThemeName(t.name);
                      // Themefarbe serverseitig spiegeln (Migration 071),
                      // damit sie nach Neuinstallation/Login direkt wieder
                      // angewendet wird. Best effort.
                      if (SupabaseService.isInitialized) {
                        unawaited(() async {
                          try {
                            await SupabaseDatabaseService(
                              SupabaseService.client,
                            ).updateOwnProfile({'theme_name': t.name});
                          } catch (e) {
                            debugPrint(
                                '[Settings] Theme-Server-Sync fehlgeschlagen: '
                                '$e');
                          }
                        }());
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const LanguageSwitch(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.chatSafety')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ChatHistoryTile(),
                  SwitchListTile.adaptive(
                    title: Text(L10n.t(context, 'settings.blur')),
                    subtitle: Text(L10n.t(context, 'settings.blurSub')),
                    value: settings.blurChatImages,
                    onChanged: (v) {
                      ref.read(settingsProvider.notifier).setBlurChatImages(v);
                      _persistUiPrefs(ref);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.e2e')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t(context, 'settings.keyBackup'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    L10n.t(context, 'settings.keyBackupSub'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: Text(L10n.t(context, 'settings.backupCreate')),
                    subtitle:
                        Text(L10n.t(context, 'settings.backupCreateSub')),
                    contentPadding: EdgeInsets.zero,
                    onTap: SupabaseService.isInitialized
                        ? () => _createIdentityBackup(context, ref)
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: Text(L10n.t(context, 'settings.backupRestore')),
                    subtitle:
                        Text(L10n.t(context, 'settings.backupRestoreSub')),
                    contentPadding: EdgeInsets.zero,
                    onTap: SupabaseService.isInitialized
                        ? () => _restoreIdentityBackup(context, ref)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(L10n.t(context, 'settings.privacyAccount')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: Text(L10n.t(context, 'settings.safetyCenter')),
                    subtitle:
                        Text(L10n.t(context, 'settings.safetyCenterSub')),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.safetyCenter),
                  ),
                  ListTile(
                    leading: const Icon(Icons.devices),
                    title: Text(L10n.t(context, 'settings.devices')),
                    subtitle: Text(L10n.t(context, 'settings.devicesSub')),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.devices),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: Text(L10n.t(context, 'settings.privacyAccount')),
                    subtitle: Text(
                        L10n.t(context, 'settings.privacyAccountSub')),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.privacy),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SecondaryButton(
            label: L10n.t(context, 'settings.logout'),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: 24),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data;
              if (version == null) return const SizedBox.shrink();
              return Text(
                'Version ${version.version} (Build ${version.buildNumber})',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}



// ===========================================================================
// E2E-Identität: verschlüsseltes Key-Backup (Migration Roadmap 0.6)
// ===========================================================================

/// Erstellt ein passwortverschlüsseltes Backup der Signal-Identität und
/// zeigt es zum Kopieren an. Der Nutzer bewahrt den Code selbst auf
/// (Passwortmanager/Papier) - kein Cloud-Zwang.
Future<void> _createIdentityBackup(
  BuildContext context,
  WidgetRef ref,
) async {
  final pwCtrl = TextEditingController();
  final pw2Ctrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(context, 'settings.backupChoosePw')),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: pwCtrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: L10n.t(ctx, 'settings.backupPw'),
              ),
              validator: (v) => v != null && v.length >= 8
                  ? null
                  : L10n.t(ctx, 'settings.backupPwShort'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: pw2Ctrl,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'settings.backupPwRepeat')),
              validator: (v) => v == pwCtrl.text
                  ? null
                  : L10n.t(ctx, 'settings.backupPwMismatch'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(formKey.currentState!.validate()),
          child: Text(L10n.t(ctx, 'settings.backupCreateBtn')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final blob = await ref
      .read(encryptionServiceProvider)
      .createEncryptedBackup(pwCtrl.text);
  if (!context.mounted) return;
  if (blob == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.t(context, 'settings.backupCreateFailed'))),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(ctx, 'settings.backupCodeTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(blob,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              const SizedBox(height: 12),
              Text(
                L10n.t(context, 'settings.backupKeepSafe'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: blob));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(L10n.t(context, 'settings.backupCopied'))),
            );
          },
          icon: const Icon(Icons.copy),
          label: Text(L10n.t(ctx, 'common.copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.done')),
        ),
      ],
    ),
  );
}

/// Stellt die E2E-Identität aus einem Backup-Code wieder her und
/// veröffentlicht anschließend frische PreKeys auf dem Server, damit
/// Partner wieder verschlüsselte Sessions aufbauen können.
Future<void> _restoreIdentityBackup(
  BuildContext context,
  WidgetRef ref,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(context, 'settings.restoreConfirmTitle')),
      content: Text(
        L10n.t(context, 'settings.restoreOverwrite'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L10n.t(ctx, 'common.continue')),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  final blobCtrl = TextEditingController();
  final pwCtrl = TextEditingController();
  final restored = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(ctx, 'settings.restoreEnterTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: blobCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: L10n.t(context, 'settings.backupPasteCode'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pwCtrl,
            obscureText: true,
            decoration:
                InputDecoration(labelText: L10n.t(ctx, 'settings.restorePw')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L10n.t(ctx, 'settings.restoreBtn')),
        ),
      ],
    ),
  );
  if (restored != true || !context.mounted) return;

  try {
    await ref
        .read(encryptionServiceProvider)
        .restoreFromBackup(blobCtrl.text.trim(), pwCtrl.text);
    // Frische PreKeys veröffentlichen, damit Partner wieder Sessions
    // aufbauen können (das Backup enthält keine One-Time-PreKeys).
    await ref.read(preKeyServiceProvider).publishOwnPreKeysFromStore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.t(context, 'settings.restored'))),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'settings.restoreFailed')),
      ),
    );
  }
}

/// Stellt sicher, dass die Session AAL2 erfüllt, wenn 2FA aktiv ist
/// (GoTrue verlangt das für Passkey-Verwaltung). Status wird FRISCH
/// geladen - der gecachte Provider kann veraltet bzw. nie geladen sein.
///
/// Rückgabe: false = Step-up fehlgeschlagen/abgebrochen (Aufrufer abbrechen).
Future<bool> _ensurePasskeyAal2(BuildContext context, WidgetRef ref) async {
  var mfa = ref.read(mfaStatusProvider);
  if (!SupabaseService.isInitialized) return true;
  try {
    mfa = await MfaService(SupabaseService.client).loadStatus();
    ref.read(mfaStatusProvider.notifier).state = mfa;
  } catch (_) {
    // Fail-closed: Mit dem alten Stand weiter.
  }
  if (!mfa.hasVerifiedFactors || mfa.currentAal == 'aal2') return true;
  if (!context.mounted) return false;
  final code = await promptTotpCode(context);
  if (code == null || !context.mounted) return false;
  try {
    await MfaService(SupabaseService.client).verifyChallenge(code: code);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'settings.codeInvalid')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }
}

/// "Passkey erstellen"-Kachel mit Doppel-Tap-Schutz: Solange die
/// Registrierung läuft (inkl. 2FA-Step-up), ist die Kachel gesperrt.
/// Zwei parallele Zeremonien brechen sich sonst gegenseitig ab
/// ("Anfrage abgebrochen von Wisp" / "credential verification failed").
class _PasskeyTile extends ConsumerStatefulWidget {
  const _PasskeyTile();

  @override
  ConsumerState<_PasskeyTile> createState() => _PasskeyTileState();
}

class _PasskeyTileState extends ConsumerState<_PasskeyTile> {
  bool _busy = false;

  Future<void> _startRegistration() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _ensurePasskeyAal2(context, ref)) return;

      // Bestands-Check: Hängt auf dem Konto bereits ein (alter) Passkey,
      // kann dessen excludeCredentials-Eintrag die NEUE Registrierung
      // serverseitig scheitern lassen ("Der Server konnte den Passkey
      // nicht bestätigen"). Der Nutzer wird transparent darauf hingewiesen
      // und kann alt Einträge vorher unter "Passkeys verwalten" löschen.
      final existing = await PasskeyAuth.countRegistered();
      if (existing != null && existing > 0 && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.fingerprint,
                color: Theme.of(ctx).colorScheme.primary, size: 36),
            title: Text(L10n.t(ctx, 'settings.passkeyExistsTitle')),
            content: Text(L10n.tf(
              ctx,
              'settings.passkeyExistsBody',
              {'count': '$existing'},
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(L10n.t(ctx, 'settings.passkeyExistsAbort')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(L10n.t(ctx, 'settings.passkeyExistsContinue')),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }

      await PasskeyAuth.register();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'settings.passkeyCreated')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is AppException
            ? L10n.exc(context, e)
            : L10n.t(context, 'settings.passkeyFailed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.fingerprint),
      title: Text(L10n.t(context, 'settings.passkeyCreate')),
      subtitle: Text(
        _busy
            ? L10n.t(context, 'settings.passkeyWaitConfirm')
            : L10n.t(context, 'settings.passkeyCreateSub'),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      contentPadding: EdgeInsets.zero,
      onTap: _busy ? null : _startRegistration,
    );
  }
}

/// "Passkeys verwalten": Listet alle am Konto registrierten Passkeys
/// (WebAuthn-Credentials) und erlaubt Umbenennen/Löschen. Wichtig für
/// die Fehlersuche, wenn der Server eine NEUE Registrierung nicht
/// bestätigt: Ein alter/defekter Eintrag kann blockieren - löschen und
/// neu anlegen behebt das.
class _PasskeyManagerCard extends ConsumerStatefulWidget {
  const _PasskeyManagerCard();

  @override
  ConsumerState<_PasskeyManagerCard> createState() =>
      _PasskeyManagerCardState();
}

class _PasskeyManagerCardState extends ConsumerState<_PasskeyManagerCard> {
  List<Passkey>? _passkeys;
  String? _error;
  bool _needsStepUp = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool stepUpFirst = false}) async {
    setState(() {
      _error = null;
      _needsStepUp = false;
    });
    try {
      if (stepUpFirst) {
        if (!await _ensurePasskeyAal2(context, ref)) return;
      }
      final list = await PasskeyAuth.listRegistered();
      if (!mounted) return;
      setState(() => _passkeys = list);
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      final aal2Needed = text.contains('aal2') ||
          text.contains('mfa') ||
          text.contains('403');
      setState(() {
        _passkeys = null;
        _needsStepUp = aal2Needed;
        _error = aal2Needed
            ? L10n.t(context, 'passkey.stepUpHint')
            : L10n.t(context, 'passkey.loadError');
      });
    }
  }

  Future<void> _rename(Passkey passkey) async {
    final ctrl = TextEditingController(text: passkey.friendlyName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'passkey.renameTitle')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: L10n.t(ctx, 'passkey.renameLabel'),
            hintText: L10n.t(ctx, 'passkey.renameHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(L10n.t(ctx, 'common.save')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await PasskeyAuth.rename(passkeyId: passkey.id, friendlyName: name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AppException
          ? L10n.exc(context, e)
          : L10n.t(context, 'passkey.renameFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _delete(Passkey passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline,
            color: Theme.of(ctx).colorScheme.error, size: 36),
        title: Text(L10n.t(context, 'settings.passkeyDeleteTitle')),
        content: Text(L10n.tf(
          context,
          'passkey.deleteBody',
          {'name': passkey.friendlyName ?? L10n.t(context, 'passkey.name')},
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'settings.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (!await _ensurePasskeyAal2(context, ref)) return;
      await PasskeyAuth.delete(passkeyId: passkey.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'settings.passkeyDeleted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AppException
          ? L10n.exc(context, e)
          : L10n.t(context, 'settings.deleteFailed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  String _formatDate(DateTime? utc) {
    if (utc == null) return '';
    try {
      return DateFormat('dd.MM.yyyy').format(utc.toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _passkeys == null
        ? (_error ?? L10n.t(context, 'passkey.managerSub'))
        : L10n.tf(context, 'passkey.managerHint',
            {'count': '${_passkeys!.length}'});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: Text(L10n.t(context, 'settings.passkeysManage')),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: L10n.t(context, 'common.refresh'),
            onPressed: _error != null && _needsStepUp
                ? () => _load(stepUpFirst: true)
                : _load,
            icon: const Icon(Icons.refresh),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        for (final passkey in _passkeys ?? const <Passkey>[])
          ListTile(
            leading: const Icon(Icons.fingerprint, size: 20),
                    title: Text(passkey.friendlyName ??
                        L10n.t(context, 'passkey.name')),
            subtitle: Text(
              [
                L10n.tf(context, 'settings.passkeyCreatedAt',
                    {'date': _formatDate(passkey.createdAt)}),
                if (passkey.lastUsedAt != null)
                  L10n.tf(context, 'settings.passkeyLastUsed',
                      {'date': _formatDate(passkey.lastUsedAt)}),
              ].join(' · '),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: L10n.t(context, 'settings.passkeyRename'),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _rename(passkey),
                ),
                IconButton(
                  tooltip: L10n.t(context, 'settings.delete'),
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: () => _delete(passkey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Schalter fuer Google-freien Push via UnifiedPush (F-Droid-Variante).
///
/// Benoetigt eine Distributor-App (z. B. ntfy). Der Endpunkt wird
/// serverseitig im Profil gespeichert; eingehende Pushes zeigt der
/// [UnifiedPushService] lokal an.
class _UnifiedPushTile extends ConsumerStatefulWidget {
  const _UnifiedPushTile();

  @override
  ConsumerState<_UnifiedPushTile> createState() => _UnifiedPushTileState();
}

class _UnifiedPushTileState extends ConsumerState<_UnifiedPushTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    UnifiedPushService.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool want) async {
    setState(() => _busy = true);
    try {
      if (want) {
        await UnifiedPushService.enable();
      } else {
        await UnifiedPushService.disable();
      }
      final active = await UnifiedPushService.isEnabled();
      if (mounted) setState(() => _enabled = active);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L10n.tf(
                  context, 'common.errorWith', {'error': '$e'}))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled ?? false;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(L10n.t(context, 'settings.unifiedPush')),
      subtitle: Text(
        enabled
            ? L10n.t(context, 'settings.unifiedPushOn')
            : L10n.t(context, 'settings.unifiedPushOff'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: enabled,
      onChanged: _busy ? null : (v) => _toggle(v),
    );
  }
}

/// Opt-in-Tile für den verschlüsselten lokalen Chat-Verlauf (v0.8.0):
/// Standard AUS. Aktiviert die AES-256-verschlüsselte SecureHive-Ablage
/// der letzten 200 Nachrichten pro Chat (Key bleibt im Keystore).
enum _HistoryMode { off, cap200, all }

class _ChatHistoryTile extends ConsumerStatefulWidget {
  const _ChatHistoryTile();

  @override
  ConsumerState<_ChatHistoryTile> createState() => _ChatHistoryTileState();
}

class _ChatHistoryTileState extends ConsumerState<_ChatHistoryTile> {
  _HistoryMode _mode = _HistoryMode.all;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final storage = ref.read(localStorageProvider);
        final enabled = await storage.getBool('chat_history_local') ?? true;
        final all = await storage.getBool('chat_history_all') ?? true;
        if (!mounted) return;
        setState(() {
          _mode = enabled
              ? (all ? _HistoryMode.all : _HistoryMode.cap200)
              : _HistoryMode.off;
        });
      } catch (_) {
        if (mounted) setState(() => _mode = _HistoryMode.all);
      }
    }());
  }

  Future<void> _apply(_HistoryMode mode) async {
    setState(() => _busy = true);
    try {
      final storage = ref.read(localStorageProvider);
      await storage.saveBool('chat_history_local', mode != _HistoryMode.off);
      await storage.saveBool('chat_history_all', mode == _HistoryMode.all);
      ref.read(chatProvider.notifier).setHistoryPersistence(
            mode != _HistoryMode.off,
            limit: mode == _HistoryMode.cap200 ? 200 : null,
          );
      if (mounted) setState(() => _mode = mode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMode() async {
    final picked = await showDialog<_HistoryMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'chathist.dialogTitle')),
        content: RadioGroup<_HistoryMode>(
          groupValue: _mode,
          onChanged: (v) => Navigator.of(ctx).pop(v),
          child: Column(            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in _HistoryMode.values)
                RadioListTile<_HistoryMode>(
                  value: mode,
                  title: Text(switch (mode) {
                    _HistoryMode.off => L10n.t(ctx, 'chathist.off.title'),
                    _HistoryMode.cap200 => L10n.t(ctx, 'chathist.cap200.title'),
                    _HistoryMode.all => L10n.t(ctx, 'chathist.all.title'),
                  }),
                  subtitle: Text(switch (mode) {
                    _HistoryMode.off => L10n.t(ctx, 'chathist.off.sub'),
                    _HistoryMode.cap200 => L10n.t(ctx, 'chathist.cap200.sub'),
                    _HistoryMode.all => L10n.t(ctx, 'chathist.all.sub'),
                  }),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != _mode) {
      await _apply(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_mode) {
      _HistoryMode.off => L10n.t(context, 'chathist.mode.off'),
      _HistoryMode.cap200 => L10n.t(context, 'chathist.mode.cap200'),
      _HistoryMode.all => L10n.t(context, 'chathist.mode.all'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.history,
        color: _mode == _HistoryMode.off
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(L10n.t(context, 'chathist.tileTitle')),
      subtitle: Text(
        '${L10n.t(context, 'chathist.tileSubPrefix')} '
        '${L10n.t(context, 'chathist.modeWord')} $label. '
        '${L10n.t(context, 'chathist.deleteHint')}',
      ),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: _busy ? null : _pickMode,
    );
  }
}
