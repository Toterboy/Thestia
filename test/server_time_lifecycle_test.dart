// Tests für den ServerTimeService-Lebenszyklus (Offset-Verwaltung,
// isVerified-Flag, Lifecycle-Behandlung ohne Flutter-Binding).
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/server_time_service.dart';

void main() {
  final service = ServerTimeService.instance;

  setUp(service.resetForTesting);
  tearDown(service.resetForTesting);

  test('Initial: kein verifizierter Offset', () {
    expect(service.isVerified, isFalse);
  });

  test('getVerifiedNow() entspricht anfangs der lokalen Zeit', () {
    final before = DateTime.now();
    final now = service.getVerifiedNow();
    final after = DateTime.now();
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
  });

  test('setOffsetForTesting aktiviert isVerified', () {
    service.setOffsetForTesting(0);
    expect(service.isVerified, isTrue);
  });

  test('now() rechnet den Offset ein (Serverzeit = lokal + Offset)', () {
    service.setOffsetForTesting(const Duration(minutes: 30).inMilliseconds);
    final expected = DateTime.now().add(const Duration(minutes: 30));
    final actual = service.now;
    expect(actual.difference(expected).inSeconds.abs(), lessThan(2));
  });

  test('corrected() verschiebt einen lokalen Zeitstempel um den Offset', () {
    service.setOffsetForTesting(const Duration(hours: 2).inMilliseconds);
    final local = DateTime.now();
    expect(service.corrected(local).difference(local).inMinutes, 120);
  });

  test('isToday() bewertet den Tag in SERVER-Zeit, nicht Gerätezeit', () {
    // Geräte-Uhr ist 30 Stunden voraus -> Serverzeit ist "gestern".
    service.setOffsetForTesting(const Duration(hours: -30).inMilliseconds);
    expect(service.isToday(DateTime.now()), isTrue);
    expect(
      service.isToday(DateTime.now().add(const Duration(hours: 30))),
      isFalse,
    );
  });

  test('syncNow() ohne Supabase wirft nicht und bleibt unverifiziert', () async {
    await service.syncNow();
    expect(service.isVerified, isFalse);
  });

  test('syncNowWithResult() ohne Supabase liefert false', () async {
    expect(await service.syncNowWithResult(), isFalse);
  });

  test('dispose() ist ohne WidgetsBinding aufrufbar', () {
    // Muss auch in reinen Unit-Tests (ohne WidgetsBinding) sauber laufen.
    service.dispose();
    expect(service.isVerified, isFalse);
  });
}