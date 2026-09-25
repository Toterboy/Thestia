import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/auth_provider.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;
import 'package:thestia/services/mfa_service.dart';
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';

/// DSGVO-relevanter Datenschutz- und Account-Screen.
///
/// - Zeigt die verarbeiteten Daten an (knappe Ãœbersicht).
/// - ErmÃ¶glicht den Export der eigenen Daten (E-01: lokale Daten als JSON
///   inkl. Auftragsverarbeiter-Liste; Chat-VerlÃ¤ufe sind E2E-verschlÃ¼sselt
///   und bleiben auf dem GerÃ¤t).
/// - ErmÃ¶glicht das vollstÃ¤ndige LÃ¶schen des Accounts inkl. aller Daten.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _requestDataExport(BuildContext context, WidgetRef ref) async {
    // Lokale Daten bÃ¼ndeln (Profile, Einstellungen, PrÃ¤ferenzen, Mood).
    // Chat-VerlÃ¤ufe sind E2E-verschlÃ¼sselt und werden bewusst NICHT
    // exportiert â€” sie verbleiben auf dem GerÃ¤t.
    final profile = ref.read(profileProvider);
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(userPreferencesProvider);
    // Chat-Verläufe (v0.8.0): nur im Export, wenn der verschlüsselte
    // lokale Verlauf aktiv ist (Opt-in) - sonst existieren keine
    // gespeicherten Nachrichten.
    final historyEnabled =
        await ref.read(chatHistoryLocalEnabledProvider.future);
    final chatExport = historyEnabled
        ? await ref.read(chatServiceProvider).exportHistory()
        : <String, dynamic>{};
    final qrContacts =
        historyEnabled ? ref.read(chatProvider.notifier).exportQrContacts() : <Map<String, String>>[];

    final exportData = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'Thestia',
      'userId': AppConstants.currentUserId,
      'profile': profile.toJson(),
      'settings': settings.toJson(),
      'preferences': prefs.toJson(),
      'mood': ref.read(moodProvider)?.value,
      // Chat-Verläufe (v0.8.0): entschlüsselte Nachrichten AUS DEM lokalen
      // Speicher - NUR wenn der Nutzer den verschlüsselten Verlauf aktiv
      // hat. Beim Import werden sie wiederhergestellt (Gerätewechsel).
      if (chatExport.isNotEmpty) 'chats': chatExport,
      if (qrContacts.isNotEmpty) 'qrContacts': qrContacts,
      'note': 'Chat-VerlÃ¤ufe sind Ende-zu-Ende verschlÃ¼sselt und verbleiben '
          'auf deinen GerÃ¤ten. Sie werden von keinem Server verarbeitet '
          'und kÃ¶nnen daher nicht exportiert werden.',
      'processors': [
        {'name': 'Supabase Inc.', 'purpose': 'Hosting, Datenbank, Auth'},
        {'name': 'Google LLC (Firebase)', 'purpose': 'Push-Benachrichtigungen'},
        {'name': 'Brevo', 'purpose': 'Transaktions-E-Mails'},
        {'name': 'Cloudflare Inc.', 'purpose': 'CAPTCHA (Turnstile), TURN'},
        {'name': 'Netlify Inc.', 'purpose': 'Hosting Auth-/CAPTCHA-Seite'},
        {'name': 'Apple Inc.', 'purpose': 'App-Store-Verteilung'},
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(exportData);

    if (kIsWeb) {
      // Web kann keine Datei-Share-API nutzen: Inhalt im Dialog anzeigen.
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(L10n.t(context, 'privacy.yourData')),
          content: SingleChildScrollView(
            child: SelectableText(json, style: const TextStyle(fontSize: 11)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(L10n.t(context, 'common.ok')),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/thestia_data_export.json');
      await file.writeAsString(json);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            subject: 'Thestia Datenexport',
            text: 'Dein Thestia-Datenexport (JSON).',
          ),
        );
      } finally {
        // TemporÃ¤re Export-Datei (enthÃ¤lt alle Profildaten) wieder
        // lÃ¶schen, damit nichts im Temp-Verzeichnis liegen bleibt
        // (Audit N2).
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best effort.
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${L10n.t(context, 'privacy.exportFailed')}: $e')),
        );
      }
    }
  }

  /// Datenimport (v0.8.0):JSON aus dem Export einlesen und Profile,
  /// Einstellungen und Präferenzen wiederherstellen. Chat-Inhalte sind
  /// bewusst nicht Teil des Exports/Imports (E2E).
  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'privacy.importTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.t(context, 'privacy.importBody')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: L10n.t(context, 'privacy.importHint'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(context, 'privacy.importApply')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    Map<String, dynamic>? map;
    try {
      map = Map<String, dynamic>.from(
          jsonDecode(ctrl.text) as Map<String, dynamic>);
    } catch (_) {
      map = null;
    }
    if (map == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'privacy.importInvalid')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      // Profil.
      if (map['profile'] is Map) {
        final profile = UserProfile.fromJson(
            Map<String, dynamic>.from(map['profile'] as Map));
        await ref.read(profileProvider.notifier).setProfile(profile);
      }
      // Einstellungen (blind mode, Sichtbarkeit, Dark Mode, ...).
      if (map['settings'] is Map) {
        await ref.read(settingsProvider.notifier).applyServerUiPrefs(
            Map<String, dynamic>.from(map['settings'] as Map));
      }
      // Präferenzen (Entfernung, Altersspanne, Geschlechter-Filter, ...).
      if (map['preferences'] is Map) {
        final prefs = UserPreferences.fromJson(
            Map<String, dynamic>.from(map['preferences'] as Map));
        final notifier = ref.read(userPreferencesProvider.notifier);
        await notifier.setGenderPreferences(prefs.genderPreferences);
        await notifier.setDistanceFilterMode(prefs.distanceFilterMode);
        await notifier.setMaxDistanceKm(prefs.maxDistanceKm);
        await notifier.setPreferredState(prefs.preferredState);
        await notifier.setLocation(prefs.location);
        await notifier.setRelationshipType(prefs.relationshipType);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'privacy.importDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.t(context, 'privacy.importFailed')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// E-Mail-Adresse ändern (v0.8.0): Re-Auth per aktuellem Passwort,
  /// danach updateUser - Supabase sendet Bestätigungs-Links an beide
  /// Adressen; die Änderung wird erst nach Bestätigung aktiv.
  Future<void> _changeEmail(BuildContext context, WidgetRef ref) async {
    final currentEmail =
        SupabaseService.currentUser?.email ?? '';
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'privacy.changeEmail')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(L10n.t(context, 'privacy.changeEmailInfo')),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'auth.email'),
                  hintText: currentEmail,
                ),
                validator: (v) =>
                    v != null && v.contains('@')
                        ? null
                        : L10n.t(ctx, 'privacy.validator.invalidEmail'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.password'),
                ),
                validator: (v) =>
                    v != null && v.length >= 8
                        ? null
                        : L10n.t(ctx, 'privacy.validator.tooShort'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(formKey.currentState!.validate()),
            child: Text(L10n.t(context, 'common.save')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      // Re-Auth: aktuelles Passwort verifizieren.
      await SupabaseService.client.auth.signInWithPassword(
        email: currentEmail,
        password: passwordCtrl.text,
      );
      await SupabaseService.client.auth.updateUser(
        UserAttributes(email: emailCtrl.text.trim()),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'privacy.changeEmailSent')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.t(context, 'privacy.changeFailed')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Passwort ändern (v0.8.0): Re-Auth per aktuellem Passwort, danach
  /// updateUser - session bleibt bestehen.
  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final currentEmail =
        SupabaseService.currentUser?.email ?? '';
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'privacy.changePassword')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordCurrent'),
                ),
                validator: (v) =>
                    v != null && v.length >= 8
                        ? null
                        : L10n.t(ctx, 'privacy.validator.tooShort'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordNew'),
                ),
                validator: (v) =>
                    v != null && v.length >= 8
                        ? null
                        : L10n.t(ctx, 'privacy.validator.tooShort'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordConfirm'),
                ),
                validator: (v) =>
                    v == newCtrl.text
                        ? null
                        : L10n.t(ctx, 'privacy.validator.mismatch'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(formKey.currentState!.validate()),
            child: Text(L10n.t(context, 'common.save')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      // Re-Auth: aktuelles Passwort verifizieren.
      await SupabaseService.client.auth.signInWithPassword(
        email: currentEmail,
        password: currentCtrl.text,
      );
      await SupabaseService.client.auth
          .updateUser(UserAttributes(password: newCtrl.text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.t(context, 'privacy.changePasswordDone')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${L10n.t(context, 'privacy.changeFailed')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    // Step-up (ASVS 7.5.3): Bei aktivem MFA ist vor der Konto-LÃ¶schung
    // eine zusÃ¤tzliche TOTP-Verifikation nÃ¶tig â€“ eine reine Passwort-
    // Session (AAL1) reicht nicht (die Edge Function erzwingt AAL2
    // serverseitig; der Pre-Check hier liefert die verstÃ¤ndliche
    // Fehlermeldung statt eines kryptischen Server-Fehlers).
    final mfa = ref.read(mfaStatusProvider);
    if (mfa.hasVerifiedFactors && mfa.currentAal != 'aal2') {
      final code = await promptTotpCode(context);
      if (code == null || !context.mounted) return; // abgebrochen
      try {
        await MfaService(SupabaseService.client).verifyChallenge(code: code);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'UngÃ¼ltiger oder abgelaufener Code. '
                'Die LÃ¶schung wurde abgebrochen.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'privacy.deleteTitle')),
        content: Text(L10n.t(context, 'privacy.deleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(L10n.t(context, 'privacy.deleteConfirm')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (context.mounted) {
        context.go(AppRoutes.welcome);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${L10n.t(context, 'privacy.deleteFailed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t(context, 'privacy.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(L10n.t(context, 'privacy.yourData')),
          _InfoCard(text: L10n.t(context, 'privacy.dataInfo')),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(L10n.t(context, 'privacy.export')),
            subtitle: Text(L10n.t(context, 'privacy.exportSub')),
            onTap: () => _requestDataExport(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.upload),
            title: Text(L10n.t(context, 'privacy.import')),
            subtitle: Text(L10n.t(context, 'privacy.importSub')),
            onTap: () => _importData(context, ref),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.accountSection')),
          _InfoCard(text: L10n.t(context, 'privacy.accountInfo')),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(L10n.t(context, 'privacy.changeEmail')),
            onTap: () => _changeEmail(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: Text(L10n.t(context, 'privacy.changePassword')),
            onTap: () => _changePassword(context, ref),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.processors')),
          _InfoCard(text: L10n.t(context, 'privacy.processorsInfo')),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Supabase Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorSupabase')),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Google LLC (Firebase)'),
            subtitle: Text(L10n.t(context, 'privacy.processorGoogle')),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Brevo'),
            subtitle: Text(L10n.t(context, 'privacy.processorBrevo')),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Cloudflare Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorCloudflare')),
          ),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: const Text('Netlify Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorNetlify')),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Apple Inc.'),
            subtitle: Text(L10n.t(context, 'privacy.processorApple')),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.consent')),
          // Standortfreigabe: Direkter Sprung in die System-Standort-
          // Einstellungen (Einwilligung OS-seitig widerrufbar).
          ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(L10n.t(context, 'privacy.location')),
            subtitle: Text(L10n.t(context, 'privacy.locationSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Geolocator.openLocationSettings(),
          ),
          // Push: Ã–ffnet die App-Einstellungen des Betriebssystems
          // (Android: Benachrichtigungen sind dort ein Tap entfernt).
          ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(L10n.t(context, 'privacy.push')),
            subtitle: Text(L10n.t(context, 'privacy.pushSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAppSettings(),
          ),
          const Divider(height: 32),
          _SectionTitle(L10n.t(context, 'privacy.dangerZone')),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              L10n.t(context, 'privacy.deleteAccount'),
              style: const TextStyle(color: Colors.red),
            ),
            subtitle: Text(L10n.t(context, 'privacy.deleteAccountSub')),
            onTap: () => _deleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}

/// Fragt den 6-stelligen TOTP-Code fÃ¼r das Step-up vor einer sensiblen
/// Aktion (Konto-LÃ¶schung, Passkey-Erstellung) ab.
/// Liefert `null`, wenn der Nutzer abgebrochen hat.
Future<String?> promptTotpCode(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L10n.t(ctx, 'privacy.totpTitle')),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(
          labelText: L10n.t(ctx, 'privacy.totpLabel'),
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L10n.t(ctx, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(L10n.t(ctx, 'privacy.totpConfirm')),
        ),
      ],
    ),
  );
}
