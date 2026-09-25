import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/screens/admin/admin_screen.dart';
import 'package:thestia/utils/constants.dart';

/// Tests für den Admin-Zugang (fail-safe: ohne dart-define kein Admin).
void main() {
  test('Bei leerem adminUserId gibt isCurrentUserAdmin() IMMER false', () {
    // Simuliere: ADMIN_UUID wurde beim Build NICHT gesetzt.
    // Der defaultValue von AppConstants.adminUserId ist ''.
    // In einer echten App müsste SupabaseService.currentUser gesetzt sein,
    // aber da isCurrentUserAdmin() ZUERST den isEmpty-Check macht, wird
    // der currentUser nie geprüft.
    // Wir können diesen Test nur indirekt validieren: Die Funktion greift
    // auf AppConstants.adminUserId zu, das via String.fromEnvironment
    // initialisiert wird. In der Test-Umgebung (ohne dart-define) ist
    // der Wert garantiert ''.

    // Direkter Test: Der defaultValue von String.fromEnvironment('ADMIN_UUID')
    // im Test ist immer '', weil flutter test keinen --dart-define übergibt.
    expect(AppConstants.adminUserId, isEmpty,
      reason: 'Ohne --dart-define=ADMIN_UUID muss adminUserId leer sein.');
  });

  test('isCurrentUserAdmin() gibt false, wenn adminUserId leer ist', () {
    // Da adminUserId im Test immer '' ist (kein dart-define), muss
    // die Funktion false zurückgeben — selbst wenn ein User eingeloggt wäre.
    // Der isEmpty-Check in Zeile 17 läuft VOR der User-Prüfung.
    final result = isCurrentUserAdmin();
    expect(result, isFalse,
      reason: 'Ohne ADMIN_UUID darf NIEMAND Admin sein.');
  });
}
