import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tests fuer die Anzeige des Standort-Verdachtsflags im Admin-Bereich.
///
/// BETREIBER-ENTSCHEIDUNG (06.11.2026): Das Flag
/// `is_location_suspicious` wird seit Migration 180 korrekt
/// geschrieben, aber von KEINER Abfrage ausgewertet - es war ein
/// Hinweis ohne Wirkung. Die Entscheidung des Betreibers: das Flag
/// soll im Admin-Bereich sichtbar werden, das Verhalten der App
/// bleibt unveraendert.
///
/// DIESER TEST HAELT GENAU DAS FEST:
///   1) Die Liste ist nur fuer Admins erreichbar.
///   2) Die Funktion liest nur - sie aendert kein Flag.
///   3) Das Flag wirkt weiterhin auf NIEMANDEN ausser dem Admin:
///      keine Abfrage filtert danach. Das ist der Kern der
///      Entscheidung - waere das anders, waere es eine
///      Verhaltensaenderung, die der Betreiber nicht wollte.
void main() {
  final migration = File(
    'supabase/migrations/183_admin_list_location_checks.sql',
  ).readAsStringSync();

  group('Die Admin-Liste ist nur fuer Admins', () {
    test('die RPC prueft den Admin-Status selbst', () {
      expect(
        migration.contains('is_current_user_admin'),
        isTrue,
        reason:
            'ohne Admin-Pruefung wuerde jeder angemeldete Nutzer die '
            'Liste der auffaelligen Profile sehen',
      );
    });

    test('die Funktion liest nur', () {
      // Ein Schreibzugriff waere eine Verhaltensaenderung: das Flag
      // zuruecksetzen oder ein Profil sperren.
      for (final verb in const [
        'UPDATE public.profiles',
        'DELETE FROM public.profiles',
        'INSERT INTO public.profiles',
      ]) {
        expect(
          migration.contains(verb),
          isFalse,
          reason: 'die Anzeige schreibt ($verb) - sie soll nur lesen',
        );
      }
    });

    test('die Berechtigungen sind eng', () {
      expect(
        migration.contains(
          'REVOKE ALL ON FUNCTION public.admin_list_location_checks() '
          'FROM PUBLIC, anon',
        ),
        isTrue,
        reason: 'ohne REVOKE darf auch die oeffentliche Rolle die Liste',
      );
      expect(
        migration.contains(
          'GRANT EXECUTE ON FUNCTION public.admin_list_location_checks() '
          'TO authenticated',
        ),
        isTrue,
      );
    });
  });

  group('Der Client ruft die richtige RPC', () {
    test('der Datenbank-Service holt die Liste ueber die RPC', () {
      final service = File(
        'lib/services/supabase_database_service.dart',
      ).readAsStringSync();
      expect(
        service.contains("_adminList('admin_list_location_checks')"),
        isTrue,
        reason: 'der Service holt die Liste nicht ueber die RPC',
      );
    });

    test('der Admin-Screen zeigt den Tab', () {
      final screen = File(
        'lib/screens/admin/admin_screen.dart',
      ).readAsStringSync();
      expect(screen.contains('_LocationChecksTab()'), isTrue);
      expect(screen.contains('admin.tabLocations'), isTrue);
    });
  });

  group('Das Flag wirkt auf niemanden ausser dem Admin', () {
    test('keine Abfrage filtert nach dem Flag', () {
      // Jede Stelle, an der das Flag in einer WHERE-Klausel auftaucht,
      // waere eine Verhaltensaenderung: der Nutzer wuerde aus der
      // Discovery verschwinden. Erlaubt ist nur die Admin-Liste.
      final verzeichnis = Directory('supabase/migrations');
      final treffer = <String>[];
      for (final datei in verzeichnis.listSync().whereType<File>()) {
        if (!datei.path.endsWith('.sql')) continue;
        final inhalt = datei.readAsStringSync();
        final zeilen = inhalt.split('\n');
        for (var i = 0; i < zeilen.length; i++) {
          final zeile = zeilen[i];
          if (!zeile.contains('is_location_suspicious')) continue;
          if (!zeile.toLowerCase().contains('where')) continue;
          // Die Zeile muss zur Admin-Funktion gehoeren.
          const fenster = 12;
          final umgebung = zeilen
              .sublist(
                i < fenster ? 0 : i - fenster,
                (i + fenster).clamp(0, zeilen.length),
              )
              .join('\n');
          if (umgebung.contains('admin_list_location_checks')) continue;
          treffer.add('${datei.path}: ${i + 1}');
        }
      }
      expect(
        treffer,
        isEmpty,
        reason:
            'das Flag filtert in einer Abfrage: ${treffer.join(', ')} - '
            'das waere eine Verhaltensaenderung, die der Betreiber nicht '
            'wollte',
      );
    });
  });
}
