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
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/screens/privacy/delete_account_action.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/mood_provider.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/widgets/captcha_challenge.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;
import 'package:thestia/services/supabase_service.dart';
import 'package:thestia/utils/constants.dart';
import 'package:thestia/utils/best_effort.dart';

/// DSGVO-relevanter Datenschutz- und Account-Screen.
///
/// - Zeigt die verarbeiteten Daten an (knappe Übersicht).
/// - Ermöglicht den Export der eigenen Daten (E-01: lokale Daten als JSON
///   inkl. Auftragsverarbeiter-Liste; Chat-Verläufe sind E2E-verschlüsselt
///   und bleiben auf dem Gerät).
/// - Ermöglicht das vollständige Löschen des Accounts inkl. aller Daten.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  Future<void> _requestDataExport(BuildContext context, WidgetRef ref) async {
    // Lokale Daten bündeln (Profile, Einstellungen, Präferenzen, Mood).
    // Chat-Verläufe sind E2E-verschlüsselt und werden bewusst NICHT
    // exportiert — sie verbleiben auf dem Gerät.
    final profile = ref.read(profileProvider);
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(userPreferencesProvider);
    // Chat-Verläufe (v0.8.0): nur im Export, wenn der verschlüsselte
    // lokale Verlauf aktiv ist (Opt-in) - sonst existieren keine
    // gespeicherten Nachrichten.
    final historyEnabled = await ref.read(
      chatHistoryLocalEnabledProvider.future,
    );
    final chatExport = historyEnabled
        ? await ref.read(chatServiceProvider).exportHistory()
        : <String, dynamic>{};
    final qrContacts = historyEnabled
        ? ref.read(chatProvider.notifier).exportQrContacts()
        : <Map<String, String>>[];

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
      'note':
          'Chat-Verläufe sind Ende-zu-Ende verschlüsselt und verbleiben '
          'auf deinen Geräten. Sie werden von keinem Server verarbeitet '
          'und können daher nicht exportiert werden.',
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
        // Temporäre Export-Datei (enthält alle Profildaten) wieder
        // löschen, damit nichts im Temp-Verzeichnis liegen bleibt
        // (Audit N2).
        // Best effort.
        await bestEffort('delete', () async {
          if (await file.exists()) await file.delete();
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${L10n.t(context, 'privacy.exportFailed')}: $e'),
          ),
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
              enableIMEPersonalizedLearning: false,
              autocorrect: false,
              enableSuggestions: false,
              controller: ctrl,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: L10n.t(context, 'privacy.importHint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
        jsonDecode(ctrl.text) as Map<String, dynamic>,
      );
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
          Map<String, dynamic>.from(map['profile'] as Map),
        );
        await ref.read(profileProvider.notifier).setProfile(profile);
      }
      // Einstellungen (blind mode, Sichtbarkeit, Dark Mode, ...).
      if (map['settings'] is Map) {
        await ref
            .read(settingsProvider.notifier)
            .applyServerUiPrefs(
              Map<String, dynamic>.from(map['settings'] as Map),
            );
      }
      // Präferenzen (Entfernung, Altersspanne, Geschlechter-Filter, ...).
      if (map['preferences'] is Map) {
        final prefs = UserPreferences.fromJson(
          Map<String, dynamic>.from(map['preferences'] as Map),
        );
        final notifier = ref.read(userPreferencesProvider.notifier);
        await notifier.setGenderPreferences(prefs.genderPreferences);
        await notifier.setDistanceFilterMode(prefs.distanceFilterMode);
        await notifier.setMaxDistanceKm(prefs.maxDistanceKm);
        await notifier.setPreferredState(prefs.preferredState);
        // v0.10.0: prefs.location entfaellt - der Import darf keinen
        // Ortsnamen aus einer alten Datensicherung zurueckbringen.
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

  /// Re-Authentifizierung für die sensiblen Konto-Änderungen
  /// (E-Mail-Adresse, Passwort).
  ///
  /// WARUM HIER EIN CAPTCHA-TOKEN NOTWENDIG IST (04.11.2026):
  ///
  /// GoTrue prüft das CAPTCHA bei **jedem** Passwort-Grant - also auch
  /// bei diesem. Der normale Login übergibt den Token (siehe
  /// `SupabaseAuthService.login`), diese beiden Aufrufe taten es
  /// nicht. Der Server antwortete darauf mit "Invalid login
  /// credentials" - dieselbe Meldung wie bei einem falschen Passwort.
  ///
  /// Die Folge war: **"E-Mail-Adresse ändern" und "Passwort ändern"
  /// waren im Release-Build komplett kaputt.** Der Nutzer gab sein
  /// richtiges Passwort ein und bekam eine Fehlermeldung, die wie ein
  /// Tippfehler aussah. Es ist kein Fehlerbericht aufgefallen, weil
  /// die Meldung "falsche Zugangsdaten" lautet und nicht "CAPTCHA
  /// fehlt".
  ///
  /// Der Token kommt aus derselben Challenge, die auch Registrierung
  /// und Login nutzen ([showCaptchaChallenge]).
  ///
  /// Gibt `true` zurück, wenn die Re-Auth geklappt hat, `false`, wenn
  /// der Nutzer die Challenge abgebrochen hat (dann wird gar nichts
  /// versucht).
  Future<bool> _reauthenticate(
    BuildContext context, {
    required String email,
    required String password,
  }) async {
    String? captchaToken;
    if (AppConstants.captchaEnabled && !kIsWeb) {
      captchaToken = await showCaptchaChallenge(context);
      if (captchaToken == null) {
        // Der Nutzer hat die Challenge abgebrochen - keine Re-Auth.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.t(context, 'privacy.changeFailed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
    }
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
    return true;
  }

  /// E-Mail-Adresse ändern (v0.8.0): Re-Auth per aktuellem Passwort,
  /// danach updateUser - Supabase sendet Bestätigungs-Links an beide
  /// Adressen; die Änderung wird erst nach Bestätigung aktiv.
  Future<void> _changeEmail(BuildContext context, WidgetRef ref) async {
    final currentEmail = SupabaseService.currentUser?.email ?? '';
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
                enableIMEPersonalizedLearning: false,
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: L10n.t(context, 'auth.email'),
                  hintText: currentEmail,
                ),
                validator: (v) => v != null && v.contains('@')
                    ? null
                    : L10n.t(ctx, 'privacy.validator.invalidEmail'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                enableIMEPersonalizedLearning: false,
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.password'),
                ),
                validator: (v) => v != null && v.length >= 8
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
      // Re-Auth: aktuelles Passwort verifizieren (mit CAPTCHA-Token -
      // siehe [_reauthenticate]).
      final okAuth = await _reauthenticate(
        context,
        email: currentEmail,
        password: passwordCtrl.text,
      );
      if (!okAuth) return;
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
    final currentEmail = SupabaseService.currentUser?.email ?? '';
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
                enableIMEPersonalizedLearning: false,
                controller: currentCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordCurrent'),
                ),
                validator: (v) => v != null && v.length >= 8
                    ? null
                    : L10n.t(ctx, 'privacy.validator.tooShort'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                enableIMEPersonalizedLearning: false,
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordNew'),
                ),
                validator: (v) => v != null && v.length >= 8
                    ? null
                    : L10n.t(ctx, 'privacy.validator.tooShort'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                enableIMEPersonalizedLearning: false,
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.t(ctx, 'auth.passwordConfirm'),
                ),
                validator: (v) => v == newCtrl.text
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
      // Re-Auth: aktuelles Passwort verifizieren (mit CAPTCHA-Token -
      // siehe [_reauthenticate]).
      final okAuth = await _reauthenticate(
        context,
        email: currentEmail,
        password: currentCtrl.text,
      );
      if (!okAuth) return;
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newCtrl.text),
      );
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

  /// Der Konto-Loesch-Ablauf - jetzt als gemeinsame Funktion, damit ihn
  /// auch die Einstellungen nutzen (06.11.2026).
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) =>
      deleteAccountWithConfirmation(context, ref);

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
          // Google Play verlangt die Datenschutzerklaerung als Text
          // INNERHALB der App, nicht nur als Link im Store. Deshalb
          // steht hier ein eigener Eintrag und nicht nur ein Hinweis
          // auf das Impressum.
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(L10n.t(context, 'privacy.policyTitle')),
            subtitle: Text(L10n.t(context, 'privacy.policySub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacyPolicy),
          ),
          // Das Impressum ist Pflicht, nicht Kuer: die App ist selbst
          // ein digitaler Dienst im Sinne des Par. 5 DDG. Ohne diesen
          // Eintrag kann die App die Anbieterkennzeichnung nicht
          // liefern (Recherche 05.11.2026).
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(L10n.t(context, 'privacy.imprintTitle')),
            subtitle: Text(L10n.t(context, 'privacy.imprintSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openImprint(context),
          ),
          // Die Nutzungsbedingungen gehoeren ebenfalls in die App:
          // Google Play verlangt fuer jede App eine erreichbare Adresse
          // der Nutzungsbedingungen, und in der App selbst gehoeren die
          // Bedingungen neben der Datenschutzerklaerung und dem
          // Impressum zu finden.
          //
          // BEFUND (14.11.2026, Betreiber): "Die Nutzungsbedingungen
          // funktionieren in der App nicht." Sie waren nur ein Link auf
          // die Webseite - das braucht einen installierten Browser und
          // eine erreichbare Seite. Der Text steht jetzt IN der App
          // (wie die Datenschutzerklaerung).
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(L10n.t(context, 'privacy.termsTitle')),
            subtitle: Text(L10n.t(context, 'privacy.termsSub')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacyTerms),
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
          // BEFUND (14.11.2026, Betreiber): "apple bei auftragsverarbeiter
          // ist aktuell falsch, da ich es dort nicht anbiete aktuell."
          // Es gibt keine App-Store-Verteilung - also steht Apple hier
          // nicht mehr. Wer die App im Play Store laedt, hat mit Google
          // (Firebase) den Push-Dienst genannt; die F-Droid-Fassung
          // nutzt UnifiedPush.
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
          // Push: Öffnet die App-Einstellungen des Betriebssystems
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
          // BEIDE Loesch-Wege stehen hier zusammen (06.11.2026,
          // Betreiber): "Daten löschen" (ohne das Konto aufzugeben) und
          // "Konto löschen" (mit).
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
            onTap: () => context.push(AppRoutes.deleteData),
          ),
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

/// Oeffnet das Impressum auf thestia.de.
///
/// Das Impressum liegt auf der Website, nicht in der App: es ist ein
/// fester Text, und ihn an zwei Stellen zu pflegen (App und Web) waere
/// eine Fehlerquelle. Ausserdem ist die Website die vollstaendige
/// Fassung - dort stehen Anschrift, Kontakt sowie die Hinweise zu
/// Moderation und Streitfaellen.
Future<void> _openImprint(BuildContext context) async {
  const url = 'https://thestia.de/impressum';
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[Privacy] Impressum konnte nicht geoeffnet werden: $e');
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.t(context, 'privacy.imprintFailed')),
        behavior: SnackBarBehavior.floating,
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }
}
