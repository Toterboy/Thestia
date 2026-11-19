// Passkeys sind ein Supabase-Beta-Feature (@experimental) - die Nutzung
// ist bewusst; die Hinweise werden auf Dateiebene ignoriert.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Passkey;

import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/privacy/delete_account_action.dart'
    show deleteAccountWithConfirmation, promptTotpCode;
import 'package:thestia/services/auth/auth_exception.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/auth/mfa_service.dart';
import 'package:thestia/services/auth/passkey_auth.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/widgets/settings/captcha_challenge.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/server/unified_push_service.dart';
import 'package:thestia/utils/location/age_safety_rules.dart';
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/providers/settings/guardian_provider.dart';
import 'package:thestia/widgets/settings/appearance_selector.dart';
import 'package:thestia/widgets/common/buttons.dart';
import 'package:thestia/widgets/chat/chat_background_picker.dart';
import 'package:thestia/widgets/settings/privacy_section.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/settings/language_switch.dart';
import 'package:thestia/widgets/settings/theme_picker.dart';
import 'package:thestia/utils/common/best_effort.dart';

part 'parts/guardiansettingsentry.dart';
part 'parts/sectiontitle.dart';
part 'parts/passkeytile.dart';
part 'parts/passkeytilestate.dart';
part 'parts/passkeymanagercard.dart';
part 'parts/passkeymanagercardstate.dart';
part 'parts/unifiedpushtile.dart';
part 'parts/unifiedpushtilestate.dart';
part 'parts/chathistorytile.dart';
part 'parts/chathistorytilestate.dart';

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
      debugPrint(
        '[SETTINGS] profile.age=${profile.age}, birthDate=${profile.birthDate}, userAge=$userAge',
      );
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
      debugPrint(
        '[SETTINGS] ageGroup=$ageGroup, allowedAgeMin=$allowedAgeMin, allowedAgeMax=$allowedAgeMax',
      );
    }

    // Falls die aktuellen Werte außerhalb des erlaubten Bereichs liegen, korrigieren
    if (settings.ageRangeMin != allowedAgeMin ||
        settings.ageRangeMax != allowedAgeMax) {
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
          // v0.10.0: Der Datenschutz-Abschnitt ist als eigenes Widget
          // ausgelagert, damit der Store-Screenshot dasselbe rendert
          // wie die App. Ein im Screenshot-Test nachgebautes Layout
          // zeigt sonst etwas, das es in der App nicht gibt.
          const PrivacySection(),
          const SizedBox(height: 16),
          // Kinderschutz & Elternzugriff (v0.10.0). Sichtbar fuer alle:
          // wer mit 18 geworden ist, hat die Freigabe aus der Zeit mit
          // 16/17 noch und entscheidet hier ueber ihr Ende.
          //
          // Die Einstellungen selbst liegen in einem EIGENEN Screen
          // (04.11.2026): hier stand der komplette Bereich mit
          // PIN-Dialog, Rhythmus und Nutzungszeit als grosse Karte
          // zwischen Datenschutz und Community-Regeln - der
          // Einstellungs-Screen war zugeballert und der Bereich schwer
          // auffindbar. Hier steht der Eintrag mit dem aktuellen
          // Status, der Weg fuehrt in den Elternbereich.
          const _GuardianSettingsEntry(),
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
                    subtitle: Text(
                      L10n.t(context, 'settings.communityRulesSub'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.communityGuidelines),
                  ),
                  if (SupabaseService.isInitialized) ...[
                    const Divider(),
                    // Eigene Stateful-Kachel: Doppel-Tap-Schutz. Zwei
                    // parallel laufende Passkey-Registrierungen brechen
                    // sich gegenseitig ab ("Anfrage abgebrochen von Thestia"
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
                          // Best-Effort: alter Stand bleibt.
                          await bestEffort('MfaService.loadStatus', () async {
                            final fresh = await MfaService(
                              SupabaseService.client,
                            ).loadStatus();
                            ref.read(mfaStatusProvider.notifier).state = fresh;
                          });
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
                    subtitle: Text(L10n.t(context, 'settings.pushEnableSub')),
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
                    subtitle: Text(L10n.t(context, 'settings.notifyFunkenSub')),
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
                    subtitle: Text(L10n.t(context, 'settings.notifyLikesSub')),
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
                    subtitle: Text(
                      L10n.t(context, 'settings.notifyMessagesSub'),
                    ),
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
                    title: Text(L10n.t(context, 'settings.notifyDatingHour')),
                    subtitle: Text(
                      L10n.t(context, 'settings.notifyDatingHourSub'),
                    ),
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
                  // v0.9.2: drei SelectableTile-Radiozeilen wurden zu
                  // einem AppearanceSelector. Siehe dort, warum.
                  // String-Keys statt bool? bleibt: Radio mit
                  // null-Value verschluckt Taps.
                  AppearanceSelector(
                    value: settings.useDarkMode == null
                        ? 'system'
                        : (settings.useDarkMode! ? 'dark' : 'light'),
                    onChanged: (mode) {
                      switch (mode) {
                        case 'light':
                          notifier.setDarkMode(false);
                        case 'dark':
                          notifier.setDarkMode(true);
                        default:
                          notifier.setDarkMode(null);
                      }
                      _persistUiPrefs(ref);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.t(context, 'settings.colors'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ThemePicker(
                    selectedName: settings.themeName,
                    // Der Server-Sync sitzt im Provider (setThemeName) -
                    // sonst wurde die Farbe nur im Einstellungs-Screen
                    // gespiegelt und nicht im Onboarding.
                    onChanged: (t) {
                      ref.read(settingsProvider.notifier).setThemeName(t.name);
                    },
                  ),
                  const SizedBox(height: 16),
                  const LanguageSwitch(),
                  const SizedBox(height: 12),
                  Text(
                    L10n.t(context, 'settings.chatBg'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L10n.t(context, 'settings.chatBgSub'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const ChatBackgroundPicker(),
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
                  Text(
                    L10n.t(context, 'settings.keyBackup'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
                    subtitle: Text(L10n.t(context, 'settings.backupCreateSub')),
                    contentPadding: EdgeInsets.zero,
                    onTap: SupabaseService.isInitialized
                        ? () => _createIdentityBackup(context, ref)
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: Text(L10n.t(context, 'settings.backupRestore')),
                    subtitle: Text(
                      L10n.t(context, 'settings.backupRestoreSub'),
                    ),
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
                    subtitle: Text(L10n.t(context, 'settings.safetyCenterSub')),
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
                      L10n.t(context, 'settings.privacyAccountSub'),
                    ),
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
          // DIE LOESCH-WEGE STEHEN GANZ UNTEN (06.11.2026, Betreiber:
          // "Konto loeschen und Daten loeschen sollen die untersten
          // Punkte sein"). Sie sind zerstoererisch - dafuer gehoeren sie
          // nicht zwischen "Geraete" und "Datenschutz & Konto".
          const SizedBox(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.dangerZone')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.cleaning_services_outlined,
                      color: Colors.red,
                    ),
                    title: Text(
                      L10n.t(context, 'settings.deleteData'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    subtitle: Text(L10n.t(context, 'settings.deleteDataSub')),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(AppRoutes.deleteData),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                    ),
                    title: Text(
                      L10n.t(context, 'privacy.deleteAccount'),
                      style: const TextStyle(color: Colors.red),
                    ),
                    subtitle: Text(L10n.t(context, 'privacy.deleteAccountSub')),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => deleteAccountWithConfirmation(context, ref),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FutureBuilder<PackageInfo>(
            // Einmalig fuer die App-Lebenszeit. Im build() erzeugt,
            // feuert jeder Schalter-Toggle einen neuen
            // Platform-Channel-Aufruf.
            future: _packageInfo,
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

  /// Einmalig: die Version aendert sich waehrend der Sitzung nicht.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
}

// ===========================================================================
// E2E-Identität: verschlüsseltes Key-Backup (Migration Roadmap 0.6)
// ===========================================================================

/// Erstellt ein passwortverschlüsseltes Backup der Signal-Identität und
/// zeigt es zum Kopieren an. Der Nutzer bewahrt den Code selbst auf
/// (Passwortmanager/Papier) - kein Cloud-Zwang.
Future<void> _createIdentityBackup(BuildContext context, WidgetRef ref) async {
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
              enableIMEPersonalizedLearning: false,
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
              enableIMEPersonalizedLearning: false,
              controller: pw2Ctrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: L10n.t(ctx, 'settings.backupPwRepeat'),
              ),
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
          // BEFUND (15.11.2026, gefunden von einem Test): Vorher
          // schloss der Dialog IMMER - auch bei einem zu kurzen oder
          // verschiedenen Passwort (`pop(validate())` schliesst, auch
          // wenn `validate()` false ergibt). Der Nutzer tippte auf
          // "Backup erstellen", der Dialog war weg, der Fehlerhinweis
          // (den die Pruefung zwar zeigt) verschwand mit ihm - und es
          // passierte gar nichts.
          //
          // JETZT: Der Dialog bleibt offen, solange die Angaben nicht
          // stimmen. Der Fehlerhinweis bleibt sichtbar.
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(true);
            }
          },
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
      SnackBar(content: Text(L10n.t(context, 'settings.backupCreateFailed'))),
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
              SelectableText(
                blob,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
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
              SnackBar(content: Text(L10n.t(context, 'settings.backupCopied'))),
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
Future<void> _restoreIdentityBackup(BuildContext context, WidgetRef ref) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(context, 'settings.restoreConfirmTitle')),
      content: Text(L10n.t(context, 'settings.restoreOverwrite')),
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
            enableIMEPersonalizedLearning: false,
            controller: blobCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: L10n.t(context, 'settings.backupPasteCode'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            enableIMEPersonalizedLearning: false,
            controller: pwCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: L10n.t(ctx, 'settings.restorePw'),
            ),
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
      SnackBar(content: Text(L10n.t(context, 'settings.restored'))),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.t(context, 'settings.restoreFailed'))),
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
  // Fail-closed: Mit dem alten Stand weiter.
  await bestEffort('MfaService.loadStatus', () async {
    mfa = await MfaService(SupabaseService.client).loadStatus();
    ref.read(mfaStatusProvider.notifier).state = mfa;
  });
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

/// Tile für den verschlüsselten lokalen Chat-Verlauf (v0.8.0):
/// Standard AN (kompletter Verlauf). Der Verlauf wird AES-256-verschlüsselt
/// in der SecureHive abgelegt (Key im Keystore) und verlässt das Gerät
/// nicht; ausgeschaltet wird nichts gespeichert.
///
/// BEFUND (13.11.2026): Dieser Kommentar behauptete "Standard AUS" - der
/// Code stellte aber auf "an" um (`?? true`). Der Kommentar wurde an den
/// Code angepasst, nicht umgekehrt: die Datenschutzerklärung sagt
/// ebenfalls "Kompletter Verlauf (Standard)".
enum _HistoryMode { off, cap200, all }
