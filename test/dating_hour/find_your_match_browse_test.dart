// Regressionstest fuer den Kategorie-Browser in "Find your Spark"
// (09.11.2026).
//
// BEFUND (Betreiber): "dann entweder Zufallsvorstellung oder
// Vorstellungen anderer nach Kategorien ansehen. Also Kategorien sind die
// Interessens-Kategorien. Auf diesen neuen Teil mit den Kategorien soll
// ein Bereich mit 18+ sein, wo von 18 bis 99+ alle gesehen werden (Aber
// man kann nach Alter filtern mit Regler) und ein 16-17 Bereich ohne
// Vorstellung mit Alter darueber. Wichtig ist, dass diese Grenze
// wirklich klappt, wie auch ueberall anders auch, damit die
// Kinder/Jugend geschuetzt sind."
//
// DER TEST prueft die App-seitige Haelfte: die Altersgrenzen des
// Browsers. Die serverseitige Haelfte (Migration 203/204) ist durch
// die Sicht `public_profiles` erzwungen - dort ist die Grenze nicht
// verhandelbar, auch nicht mit einem manipulierten Client.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/providers/find_your_match_browse_provider.dart';
import 'package:thestia/services/find_your_match_service.dart';

/// Ein Client, der NICHT verbindet (die Abfragen laufen ohne Server
/// gar nicht erst - der Provider prueft `SupabaseService.isInitialized`).
FindYourMatchService _service() =>
    FindYourMatchService(SupabaseClient('https://example.invalid', 'anon'));

void main() {
  group('Der Kategorie-Browser', () {
    test('die Altersgrenzen folgen den Sicherheitsregeln', () {
      // 16 und 17: nur untereinander. Das Alter endet bei 17 - ein
      // 16-Jaehriger darf keinen Erwachsenen sehen.
      final minderjaehrig = FindYourMatchBrowseNotifier(_service(), 16);
      expect(minderjaehrig.state.alterMin, 16);
      expect(minderjaehrig.state.alterMax, 17);

      // 18: nur Erwachsene, von 18 bis 99.
      final erwachsen = FindYourMatchBrowseNotifier(_service(), 18);
      expect(erwachsen.state.alterMin, 18);
      expect(erwachsen.state.alterMax, 99);

      // 30: mindestens 20 (zehn Jahre unter dem eigenen Alter), sonst
      // nichts - und nach oben bleibt alles offen (bis 99).
      final erfahren = FindYourMatchBrowseNotifier(_service(), 30);
      expect(erfahren.state.alterMin, 20);
      expect(erfahren.state.alterMax, 99);
    });

    test('die Kategorien werden mit ihrer Zahl gelesen', () {
      final musik = CategoryCount.fromJson({'category': 'Musik', 'cnt': 3});
      expect(musik.category, 'Musik');
      expect(musik.count, 3);

      // Fehlende Werte fallen nicht um (kein Absturz, keine Exception).
      final leer = CategoryCount.fromJson({'category': ''});
      expect(leer.category, '');
      expect(leer.count, 0);
    });

    test('der Zustand laesst sich kopieren, ohne etwas zu verlieren', () {
      final n = FindYourMatchBrowseNotifier(_service(), 18);
      final neu = n.state.copyWith(kategorie: 'Musik');
      expect(neu.kategorie, 'Musik');
      expect(neu.alterMin, 18);
      expect(neu.alterMax, 99);
    });
  });
}
