import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/admin/admin_counts.dart';
import 'package:thestia/screens/admin/admin_mail_inbox.dart';
import 'package:thestia/services/profile/photo_moderation_service.dart';
import 'package:thestia/services/server/supabase_database_service.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/utils/common/constants.dart';
import 'package:thestia/widgets/common/admin_metric_row.dart';
import 'package:thestia/widgets/profile/ai_badge.dart';
import 'package:thestia/widgets/chat/pill_tab_bar.dart';
import 'package:thestia/widgets/common/pinned_network_image.dart';
import 'package:thestia/widgets/common/states.dart';

part 'parts/adminmetricsbar.dart';
part 'parts/asynclist.dart';
part 'parts/userreportstab.dart';
part 'parts/userreportstabstate.dart';
part 'parts/bugreportstab.dart';
part 'parts/bugreportstabstate.dart';
part 'parts/verificationtab.dart';
part 'parts/verificationtabstate.dart';
part 'parts/photomoderationlist.dart';
part 'parts/photomoderationliststate.dart';
part 'parts/banstab.dart';
part 'parts/banstabstate.dart';
part 'parts/photoappealstab.dart';
part 'parts/photoappealstabstate.dart';
part 'parts/appealcard.dart';
part 'parts/statuschip.dart';
part 'parts/signedappealimage.dart';
part 'parts/signedappealimagestate.dart';
part 'parts/locationcheckstab.dart';
part 'parts/locationcheckstabstate.dart';

/// Hilfsfunktion: Prüft, ob der aktuell eingeloggte Nutzer der Admin ist.
///
/// Die Admin-UUID wird via --dart-define=ADMIN_UUID=... beim Build gesetzt.
/// Ist sie nicht konfiguriert (leerer String), gibt die Funktion IMMER false
/// zurück — Admin-Funktionen sind dann deaktiviert (fail-safe).
bool isCurrentUserAdmin() {
  final adminId = AppConstants.adminUserId;
  // Fail-safe: Wenn die Admin-UUID nicht konfiguriert ist, kann NIEMAND
  // Admin sein - auch nicht versehentlich durch leere User-ID.
  if (adminId.isEmpty) return false;
  final userId = SupabaseService.currentUser?.id;
  if (userId == null) return false;
  return userId == adminId;
}

/// Ob der aktuell eingeloggte Nutzer Admin ist - als Provider.
///
/// DER WEG (14.11.2026): Über einen Provider ist der Admin-Bereich im
/// Test erreichbar, ohne die echte Admin-UUID im Test zu brären.
///
/// DIE REGEL BLEIBT: Ohne konfigurierte Admin-UUID (Build-Parameter) ist
/// NIE jemand Admin, und der Bildschirm prüft zusätzlich serverseitig
/// (fail-closed). Nur der TEST überschreibt diesen Provider - die
/// Produktion nicht.
final adminAccessProvider = Provider<bool>((ref) => isCurrentUserAdmin());

/// Geschützter Admin-Screen.
///
/// SCHUTZKONZEPT (warum normale Nutzer ihn nicht sehen können):
///  1. Route nur aus "Mein Profil" verlinkt; der Screen prüft beim Öffnen
///     clientseitig [isCurrentUserAdmin] UND serverseitig den RPC
///     `is_current_user_admin` (fail-closed - bei Fehler wird umgeleitet).
///  2. Alle Daten kommen ausschließlich aus SECURITY DEFINER-RPCs
///     (`admin_list_*`), die `is_current_user_admin()` serverseitig
///     prüfen. Ohne Admin-Flag liefern sie leere Ergebnisse bzw. Fehler -
///     selbst bei manipuliertem Client ist kein Datenzugriff möglich.
///  3. Schreibaktionen (Verifizierungs-Freigabe) laufen durch die Edge
///     Function `verify-account`, die den Admin-Status ebenfalls
///     serverseitig gegen die profiles-Tabelle prüft.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _serverAdminChecked = false;

  @override
  void initState() {
    super.initState();
    _enforceAdmin();
    _checkServerAdmin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enforceAdmin();
  }

  void _enforceAdmin() {
    if (!ref.read(adminAccessProvider) && mounted) {
      // Fail-closed bleibt (Audit H6), aber der Grund gehört ins Log.
      // Ohne das ist die häufigste Ursache - die FALSCHE APK - nur daran
      // zu erkennen, dass der Screen sofort wieder zugeht, und das sieht
      // wie ein Fehler der App aus statt wie ein Baufehler.
      if (kDebugMode) {
        final eingeloggt = SupabaseService.currentUser?.id;
        debugPrint(
          '[AdminScreen] Client-Check abgelehnt. '
          'adminUserId konfiguriert: '
          '${AppConstants.adminUserId.isNotEmpty}, '
          'eingeloggt: $eingeloggt. '
          'Haeufigste Ursache: oeffentliche APK statt ADMIN-APK '
          'installiert - die oeffentliche enthaelt die Admin-UUID '
          'absichtlich nicht.',
        );
      }
      // NACH dem Aufbau navigieren (BEFUND 14.11.2026, gefunden von einem
      // Test): Ein `context.go()` während des Aufbaus wirft "setState()
      // or markNeedsBuild() called during build" - der Aufruf kommt hier
      // aus dem initState/didChangeDependencies, also genau während des
      // Aufbaus. Der Bereich ist trotzdem zu: der Aufbau selbst zeigt
      // den Hinweis ("admin.denied"), erst danach geht es zur Startseite.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(AppRoutes.home);
      });
    }
  }

  Future<void> _checkServerAdmin() async {
    if (!mounted) return;
    try {
      final result = await SupabaseService.client.rpc('is_current_user_admin');
      if (mounted && result != true) {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      // Fail-closed (Audit H6): Schlägt die serverseitige Prüfung fehl,
      // wird der Admin-Bereich NICHT gerendert.
      if (kDebugMode) {
        debugPrint(
          '[AdminScreen] Server-Admin-Check fehlgeschlagen '
          '(fail-closed): $e',
        );
      }
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } finally {
      if (mounted) setState(() => _serverAdminChecked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(adminAccessProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t(context, 'admin.deniedTitle'))),
        body: Center(child: Text(L10n.t(context, 'admin.deniedBody'))),
      );
    }

    if (!_serverAdminChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      // ACHTUNG (14.11.2026, gefunden von einem Test): Hier stand 7 -
      // aber es gibt ACHT Tabs (Pillen) und ACHT Seiten (TabBarView).
      // Der letzte (Posteingang) war dadurch nicht erreichbar: ein
      // Klick darauf rief controller.animateTo(7) auf einem Controller
      // mit 7 Eintrügen auf - das ist ein Assertion-Fehler.
      // Die Zahl muss zur Zahl der Pillen passen.
      length: 8,
      child: Builder(
        builder: (context) {
          final counts = ref.watch(adminCountsProvider).valueOrNull;
          final controller = DefaultTabController.of(context);
          final openReports = counts?.openReports ?? 0;
          final newBugs = counts?.bugsLast24h ?? 0;

          return Scaffold(
            appBar: AppBar(
              title: Text(L10n.t(context, 'admin.title')),
              // Pillen-Indikator statt TabBar: der TabBar-Indikator ist
              // ein Unterstrich zwischen den Labels und damit bei sechs
              // Tabs mit Icon mehrdeutig. Die Pille sitzt HINTER dem
              // aktiven Tab und trägt dieselbe Zahl wie die Kennzahlen-
              // Zeile, sodass man von beiden Stellen sieht, wo Arbeit
              // wartet.
              //
              // PillTabBar baut seinen AnimatedBuilder selbst: die
              // Auswahl ist Teilzustand des Widgets, nicht des Aufrufers.
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: PillTabBar(
                  controller: controller,
                  tabs: [
                    PillTab(
                      label: L10n.t(context, 'admin.tabReports'),
                      icon: Icons.flag,
                      count: openReports > 0 ? openReports : null,
                    ),
                    PillTab(
                      label: L10n.t(context, 'admin.tabBugs'),
                      icon: Icons.bug_report,
                      count: newBugs > 0 ? newBugs : null,
                    ),
                    PillTab(
                      label: L10n.t(context, 'admin.tabVerification'),
                      icon: Icons.verified,
                      count: (counts?.pendingVerifications ?? 0) > 0
                          ? counts!.pendingVerifications
                          : null,
                    ),
                    PillTab(
                      label: L10n.t(context, 'admin.tabModeration'),
                      icon: Icons.photo_library,
                    ),
                    PillTab(
                      label: L10n.t(context, 'admin.tabAppeals'),
                      icon: Icons.image_search,
                      count: (counts?.pendingAppeals ?? 0) > 0
                          ? counts!.pendingAppeals
                          : null,
                    ),
                    PillTab(
                      label: L10n.t(context, 'admin.tabBans'),
                      icon: Icons.block,
                      count: (counts?.bans ?? 0) > 0 ? counts!.bans : null,
                    ),
                    // Die Standort-Prüfungen: Profile, bei denen der
                    // Standort-Check aufgefallen ist. Reiner Hinweis -
                    // die App verhält sich dadurch nicht anders.
                    PillTab(
                      label: L10n.t(context, 'admin.tabLocations'),
                      icon: Icons.location_on_outlined,
                    ),
                    // Der Posteingang: eingehende Mails an die Adresse
                    // des Betreibers, nach Rubrik gefiltert. Nur lesen -
                    // antworten geht weiterhin über das Mail-Programm.
                    PillTab(
                      label: L10n.t(context, 'admin.tabMail'),
                      icon: Icons.inbox_outlined,
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: L10n.t(context, 'admin.close'),
                  // WICHTIG: context.go statt Navigator.pop - der
                  // Admin-Screen wird per GoRouter-go erreicht (kein
                  // Stack-Eintrag), ein Navigator.pop ging hinter die
                  // Root-Route und erzeugte einen Blackscreen.
                  onPressed: () => context.go(AppRoutes.home),
                ),
              ],
            ),
            body: const Column(
              children: [
                // Kennzahlen-Zeile: beantwortet "wo liegt Arbeit" ohne
                // Durchklicken. Die Tabs melden dem Provider nach einer
                // Aktion über `refreshAdminCounts(ref)`, damit die Zeile
                // nicht bis zum nächsten Öffnen falsch bleibt.
                _AdminMetricsBar(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _UserReportsTab(),
                      _BugReportsTab(),
                      _VerificationTab(),
                      _PhotoModerationList(),
                      _PhotoAppealsTab(),
                      _BansTab(),
                      _LocationChecksTab(),
                      AdminMailInboxTab(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Gemeinsames Lade-Gerüst für Server-Listen.
// ===========================================================================

String _fmtTs(BuildContext context, dynamic ts) {
  final dt = ts is DateTime ? ts : DateTime.tryParse(ts?.toString() ?? '');
  if (dt == null) return L10n.t(context, 'admin.unknown');
  return DateFormat('dd.MM.yyyy HH:mm').format(dt);
}

// ===========================================================================
// Tab 1: Nutzer-Meldungen (user_reports-Tabelle via admin_list_user_reports)
// ===========================================================================

// ===========================================================================
// Tab 2: Bug Reports (bug_reports-Tabelle via admin_list_bug_reports)
// ===========================================================================

// ===========================================================================
// Tab 3: Verifizierungen (Videos im privaten Bucket freigeben/ablehnen)
// ===========================================================================

// ===========================================================================
// Tab 4: Foto-Moderation (unverändert übernommen, mit Hash-Guard)
// ===========================================================================

// ===========================================================================
// Tab 5: Sperren (banned_emails, Anzeige)
// ===========================================================================

// ===========================================================================
// Tab 5: Bild-Prüfung (v0.8.1 Einspruchs-Verfahren)
//
// Nutzer, deren Profilbild die LOKALE NSFW-Prüfung abgelehnt hat, können
// Einspruch einlegen. Das Bild liegt dann verschlüsselt-frei (nur
// Owner + Admin via Storage-Policy) unter {uid}/appeals/ im privaten
// avatars-Bucket und wird hier zur Entscheidung angezeigt.
//   - Freigeben: Nutzer erhält Push + kann das Bild in der App als
//     Profilbild übernehmen (Client verschlüsselt dabei selbst).
//   - Ablehnen: Nutzer erhält Push; die Appeals-Datei wird vom Client
//     beim Quittieren gelöscht.
// ===========================================================================

// ===========================================================================
// Tab: Standort-Prüfungen (Profile mit gesetztem Verdachtsflag)
// ===========================================================================
//
// WAS DAS ZEIGT: Profile, bei denen der Standort-Check aufgefallen ist -
// der Standort sprang um mehr als 15 km oder die Fortbewegungs-
// geschwindigkeit lag über 300 km/h.
//
// WAS ES NICHT TUT: Niemand wird aus der Discovery genommen, niemand
// gesperrt, kein Verhalten der App ändert sich. Das Flag
// `is_location_suspicious` wird seit Migration 180 geschrieben, aber
// von keiner Abfrage ausgewertet - es ist ein Hinweis für den Admin,
// kein Filter. Die Entscheidung des Nutzers (06.11.2026) war
// ausdrücklich "nur im Admin-Bereich anzeigen".
//
// DIE DATENLOESUNG: Die RPC admin_list_location_checks prüft selbst,
// ob der Aufrufer Admin ist - ohne Admin liefert sie eine leere
// Liste. Die Anzeige ist damit nicht nur im Admin-Bereich, sondern
// nur für Admins erreichbar.
