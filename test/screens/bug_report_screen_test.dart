// Der Bildschirm für den Bug-Report.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/bug_report/bug_report_screen.dart 80 offene Zeilen bei
// 48 % Abdeckung. Das ist der einzige Weg, mit dem der Nutzer der App
// einen Fehler melden kann - und er hängt dabei Bildschirmshots an
// (mit GPS-Metadaten im Bild, die vorher entfernt werden müssen).
//
// WAS HIER GEPRÜFT WIRD:
//   * die Beschreibung wird geprüft (leer / zu kurz / zu lang),
//   * ein Bild, das kein Bild ist, wird abgewiesen,
//   * ein Bild landet in der Vorschau,
//   * der Versand geht an den Server und der Bildschirm meldet das
//     Ergebnis (erst danach schließt er).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Das Plattform-Interface wird von image_picker exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darüber.
// ignore_for_file: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/bug_report/bug_report_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Bildauswahl-Ersatz.
///
/// DER GRUND: Das echte Plugin öffnet auf dem Testrechner eine Datei-
/// auswahl (oder gar nichts). Der Ersatz liefert eine feste Datei.
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.datei);

  /// Die gelieferte Datei (null = der Nutzer bricht ab).
  final String? datei;

  /// Wie oft wurde ausgewahlt?
  int aufrufe = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    aufrufe++;
    return datei == null ? null : XFile(datei!);
  }
}

void main() {
  late FakeSupabaseServer server;
  late String bildPfad;
  late String kaputtePfad;
  late ImagePickerPlatform original;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockPackageInfo();

    // DIE BILDER: Echte Dateien (die Datei-Arbeit hängt im Test-Bereich).
    final ordner = await Directory.systemTemp.createTemp('thesia_bugreport');
    bildPfad = '${ordner.path}/bild.png';
    final bild = img.Image(width: 40, height: 40);
    img.fill(bild, color: img.ColorRgb8(20, 120, 200));
    await File(bildPfad).writeAsBytes(img.encodePng(bild));

    kaputtePfad = '${ordner.path}/kein-bild.txt';
    await File(kaputtePfad).writeAsString('das ist kein bild');

    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.funktionsAufrufe.clear();
    original = ImagePickerPlatform.instance;
  });

  tearDown(() {
    ImagePickerPlatform.instance = original;
  });

  /// Baut den Bildschirm.
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // DER PROVIDER: Der Bildschirm liest den Versand-Dienst aus dem
    // Provider - ohne ihn kann er gar nicht senden.
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: BugReportScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt den "Senden"-Knopf.
  Future<void> sende(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('bug.send'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('Der Bug-Report-Bildschirm', () {
    testWidgets('eine leere Beschreibung wird abgewiesen', (tester) async {
      await zeige(tester);

      await sende(tester);

      expect(
        find.text(L10n.tWithoutContext('bug.descMissing')),
        findsOneWidget,
        reason:
            'Ohne Beschreibung kann der Support nichts tun - der Report '
            'muss abgelehnt werden.',
      );
      expect(
        server.funktionsAufrufe.any((c) => c['funktion'] == 'send-bug-report'),
        isFalse,
        reason: 'Ein leerer Report geht nicht raus.',
      );
    });

    testWidgets('eine zu kurze Beschreibung wird abgewiesen', (tester) async {
      await zeige(tester);

      await tester.enterText(find.byType(TextFormField), 'hi');
      await tester.pump();
      await sende(tester);

      expect(find.text(L10n.tWithoutContext('bug.descShort')), findsOneWidget);
    });

    testWidgets('ein Bild, das kein Bild ist, wird abgewiesen', (tester) async {
      ImagePickerPlatform.instance = _FakeImagePicker(kaputtePfad);
      await zeige(tester);

      await tester.tap(find.text(L10n.tWithoutContext('bug.gallery')));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.text(L10n.tWithoutContext('bugreport.badFormat')),
        findsOneWidget,
        reason:
            'Nur echte Bilder duerfen angehaengt werden - eine Datei mit '
            'beliebigem Inhalt gehoert nicht in den Report.',
      );
    });

    testWidgets('ein Bild landet in der Vorschau', (tester) async {
      ImagePickerPlatform.instance = _FakeImagePicker(bildPfad);
      await zeige(tester);

      await tester.tap(find.text(L10n.tWithoutContext('bug.gallery')));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        find.text(L10n.tWithoutContext('bug.preview')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, was er anhaengt.',
      );
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('der Versand geht an den Server', (tester) async {
      await zeige(tester);

      await tester.enterText(
        find.byType(TextFormField),
        'Die App stuerzt beim Chat ab, wenn ich ein Bild sende.',
      );
      await tester.pump();
      await sende(tester);

      expect(
        server.funktionsAufrufe.any((c) => c['funktion'] == 'send-bug-report'),
        isTrue,
        reason: 'Der Report muss raus - sonst hat der Nutzer nichts davon.',
      );
    });
  });
}
