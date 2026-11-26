/// Die Routen des Safety Centers.
///
/// WARUM EINE EIGENE DATEI (22.11.2026): Der Router ist nach 220
/// Migrationen und vielen Routen an der Grenze von 1000 Zeilen
/// (`code_datei_groessen_test`). Die drei Safety-Routen gehören
/// zusammen - sie sind der Weg in die beiden Listen (blockierte Nutzer,
/// eigene Meldungen), die je einen eigenen Screen haben.
///
/// NUTZERWUNSCH (22.11.2026): "Blockierte Nutzer und Meldungen sollen
/// beide als einzelne Screens, damit der Safety Center Screen nicht
/// überladen wird, wenn es viele blockierungen und oder Meldungen
/// gibt."
library;

import 'package:go_router/go_router.dart';

import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/safety/blocked_users_screen.dart';
import 'package:thestia/screens/safety/my_reports_screen.dart';
import 'package:thestia/screens/safety/safety_center_screen.dart';

/// Die drei Safety-Routen (alle außerhalb der Reiterleiste).
List<RouteBase> safetyRoutes() => <RouteBase>[
  // Safety Center: Hilfe bei Belästigung/Stalking + In-App-Maßnahmen
  GoRoute(
    path: AppRoutes.safetyCenter,
    builder: (context, state) => const SafetyCenterScreen(),
  ),
  // Die beiden Listen des Safety Centers haben je einen eigenen Screen
  // (NUTZERWUNSCH 22.11.2026: der Safety Center soll bei vielen
  // Blockierungen oder Meldungen nicht unbrauchbar werden).
  GoRoute(
    path: AppRoutes.blockedUsers,
    builder: (context, state) => const BlockedUsersScreen(),
  ),
  GoRoute(
    path: AppRoutes.myReports,
    builder: (context, state) => const MyReportsScreen(),
  ),
];
