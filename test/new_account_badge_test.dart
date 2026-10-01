import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/user_profile.dart';

/// Kontoalter fuer den Hinweis "neuer Account".
///
/// Der Hinweis ist die Reaktion auf das Problem, dass man dauerhaft von
/// Accounts angeschrieben wird, die es gerade erst gibt. Ein Hinweis,
/// kein Beweis - deshalb wird bewusst kein Datum angezeigt.
void main() {
  UserProfile withAge(Duration age) => UserProfile(
        id: 'u1',
        name: 'Test',
        bio: '',
        createdAt: DateTime.now().toUtc().subtract(age),
      );

  group('isRecentlyCreated', () {
    test('Konto unter 7 Tagen gilt als neu', () {
      expect(
        withAge(const Duration(hours: 1)).isRecentlyCreated, isTrue);
      expect(
        withAge(const Duration(days: 3)).isRecentlyCreated, isTrue);
      expect(
        withAge(const Duration(days: UserProfile.recentAccountDays - 1))
            .isRecentlyCreated,
        isTrue,
        reason: '6 von 7 Tagen ist noch neu',
      );
    });

    test('ab 7 Tagen gilt das Konto nicht mehr als neu', () {
      expect(
        withAge(const Duration(days: UserProfile.recentAccountDays))
            .isRecentlyCreated,
        isFalse,
        reason: 'die Grenze selbst zaehlt schon als nicht mehr neu',
      );
      expect(
        withAge(const Duration(days: 30)).isRecentlyCreated, isFalse);
      expect(
        withAge(const Duration(days: 400)).isRecentlyCreated, isFalse);
    });

    test('ohne Erstellungsdatum gibt es keinen Hinweis', () {
      // Eine falsche Entwarnung waere schaedlicher als ein fehlender
      // Hinweis: dann wuerde niemand mehr auf das Kontoalter achten.
      final p = const UserProfile(id: 'u1', name: 'Test', bio: '');
      expect(p.createdAt, isNull);
      expect(p.isRecentlyCreated, isFalse);
    });

    test('die Grenze liegt bei 7 Tagen', () {
      expect(UserProfile.recentAccountDays, 7);
    });
  });

  group('createdAt aus der public_profiles-View', () {
    test('ISO-String wird gelesen', () {
      final p = UserProfile.fromPublicView({
        'user_id': 'u2',
        'name': 'Neu',
        'bio': null,
        'created_at': DateTime.now().toUtc()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      });
      expect(p.createdAt, isNotNull);
      expect(p.isRecentlyCreated, isTrue);
    });

    test('fehlendes Feld fuehrt zu keinem Hinweis, nicht zu einem Fehler', () {
      final p = UserProfile.fromPublicView({
        'user_id': 'u2',
        'name': 'Ohne Datum',
        'bio': null,
      });
      expect(p.createdAt, isNull);
      expect(p.isRecentlyCreated, isFalse);
    });

    test('kaputter Wert sprengt den Profilaufbau nicht', () {
      final p = UserProfile.fromPublicView({
        'user_id': 'u2',
        'name': 'Kaputt',
        'bio': null,
        'created_at': 'kein datum',
      });
      expect(p.createdAt, isNull);
      expect(p.isRecentlyCreated, isFalse);
    });

    test('DateTime statt String wird akzeptiert', () {
      final p = UserProfile.fromPublicView({
        'user_id': 'u2',
        'name': 'Neu',
        'bio': null,
        'created_at': DateTime.now().toUtc().subtract(const Duration(days: 1)),
      });
      expect(p.isRecentlyCreated, isTrue);
    });
  });

  group('createdAt im eigenen Profil', () {
    test('aus fromJson uebernehmen und serialisieren', () {
      final at = DateTime.utc(2026, 1, 15, 12);
      final p = UserProfile.fromJson({
        'id': 'u3',
        'name': 'Eigen',
        'bio': '',
        'createdAt': at.toIso8601String(),
      });
      expect(p.createdAt, at);
      expect(p.toJson()['createdAt'], at.toIso8601String());
    });

    test('copyWith behaelt das Datum, wenn nichts uebergeben wird', () {
      final at = DateTime.utc(2026, 1, 15);
      final p = UserProfile(
        id: 'u3',
        name: 'Eigen',
        bio: '',
        createdAt: at,
      );
      expect(p.copyWith(name: 'Neu').createdAt, at);
      expect(p.copyWith(createdAt: null).createdAt, at,
          reason: 'null bedeutet "unveraendert", nicht "loeschen"');
    });
  });
}
