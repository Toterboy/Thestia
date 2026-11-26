// Der Hinweis auf ein junges Konto.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/new_account_badge.dart 0 % Abdeckung. Die Plakette
// ist ein HINWEIS auf ein junges Konto - sie soll davor schützen, dass
// man dauerhaft von Accounts angeschrieben wird, die es gerade erst
// gibt. Ohne Test weiß niemand, ob sie zu oft oder zu selten erscheint.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Profil (oder ohne Erstellungsdatum) erscheint NICHTS -
//     eine falsche Entwarnung wäre schädlicher als ein fehlender
//     Hinweis,
//   * ein Konto älter als eine Woche wird nicht markiert,
//   * ein junges Konto wird markiert (Text für Screenreader und
//     Tooltip).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/widgets/profile/new_account_badge.dart';

void main() {
  /// Baut die Plakette allein (ohne ganze App).
  Widget baue(UserProfile? profil) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: NewAccountBadge(profile: profil)),
  );

  group('Der Hinweis auf ein junges Konto', () {
    testWidgets('ohne Profil erscheint nichts', (tester) async {
      await tester.pumpWidget(baue(null));

      expect(
        find.text(L10n.tWithoutContext('profile.newAccountBadge')),
        findsNothing,
        reason:
            'Ohne Profil gibt es nichts zu zeigen - eine Platzhalter-'
            'Anzeige waere eine erfundene Aussage.',
      );
    });

    testWidgets('ohne Erstellungsdatum erscheint nichts', (tester) async {
      // DER WICHTIGE FALL: Der Server liefert bei manchen Profilen kein
      // `created_at`. Dann darf der Hinweis nicht erscheinen - sonst
      // wäre es eine Behauptung ohne Grundlage.
      await tester.pumpWidget(
        baue(
          const UserProfile(id: 'p1', name: 'Mira', bio: '', birthDate: null),
        ),
      );

      expect(
        find.text(L10n.tWithoutContext('profile.newAccountBadge')),
        findsNothing,
      );
    });

    testWidgets('ein Konto aelter als eine Woche wird nicht markiert', (
      tester,
    ) async {
      final profil = UserProfile(
        id: 'p1',
        name: 'Mira',
        bio: '',
        birthDate: DateTime(1995, 1, 1),
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );

      await tester.pumpWidget(baue(profil));

      expect(
        find.text(L10n.tWithoutContext('profile.newAccountBadge')),
        findsNothing,
        reason:
            'Nach einer Woche ist das Konto nicht mehr neu - die Markierung '
            'wuerde dann nur noch stoeren.',
      );
    });

    testWidgets('ein frisches Konto wird markiert', (tester) async {
      final profil = UserProfile(
        id: 'p1',
        name: 'Mira',
        bio: '',
        birthDate: DateTime(1995, 1, 1),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(baue(profil));

      expect(
        find.text(L10n.tWithoutContext('profile.newAccountBadge')),
        findsOneWidget,
        reason:
            'Ein Konto, das es seit zwei Stunden gibt, ist neu - der Nutzer '
            'soll das wissen.',
      );
    });

    testWidgets('der Hinweis traegt den Text fuer Screenreader', (
      tester,
    ) async {
      final profil = UserProfile(
        id: 'p1',
        name: 'Mira',
        bio: '',
        birthDate: DateTime(1995, 1, 1),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      // DIE SEMANTIK: Im Test ist der Semantik-Baum erst auf Verlangen
      // aktiv - ohne das findet der Sucher die Beschriftung nicht.
      final semantik = tester.ensureSemantics();

      await tester.pumpWidget(baue(profil));

      final text = L10n.tWithoutContext('profile.newAccountBadge');
      expect(
        find.bySemanticsLabel(RegExp(text)),
        findsOneWidget,
        reason:
            'Der Hinweis darf nicht nur eine Grafik sein - ein Screenreader '
            'muss ihn vorlesen koennen.',
      );

      // DER GRIFF: Er muss VOR dem Ende des Tests wieder weg - sonst
      // meckert das Test-Framework ("A SemanticsHandle was active").
      semantik.dispose();
    });

    testWidgets('der Tooltip erklaert den Hinweis', (tester) async {
      final profil = UserProfile(
        id: 'p1',
        name: 'Mira',
        bio: '',
        birthDate: DateTime(1995, 1, 1),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

      await tester.pumpWidget(baue(profil));

      expect(
        find.byTooltip(L10n.tWithoutContext('profile.newAccountTooltip')),
        findsOneWidget,
        reason:
            'Der Tooltip sagt, was die Plakette bedeutet - ohne Erklaerung '
            'raten die Nutzer, was die Markierung soll.',
      );
    });
  });

  group('Die Altersgrenze', () {
    test('die Grenze liegt bei sieben Tagen', () {
      expect(UserProfile.recentAccountDays, 7);
    });
  });
}
