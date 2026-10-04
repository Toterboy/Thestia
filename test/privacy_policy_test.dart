import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/generated/privacy_policy_de.dart';
import 'package:thestia/screens/privacy/privacy_policy_text_screen.dart';

/// Publish-Verzeichnis des Netlify-Projekts fuer thestia.de. Dieselbe
/// Datei wird live ausgeliefert, deshalb wird sie hier geprueft und
/// nicht nur der Dart-Text fuer die App.
final String publishPath =
    '${Directory.current.path}/passkey-assets/datenschutz.html';

/// Google Play verlangt die Datenschutzerklaerung an ZWEI Stellen:
///
/// 1. als oeffentlich erreichbare URL im Store-Eintrag und
/// 2. als **Link oder Text innerhalb der App selbst**.
///
/// Punkt 2 ist der hier abgesicherte. Ein Link allein genuegt nicht -
/// und ein Link ist genau die Form, die ausfallen kann: falsch
/// eingetragen, umgezogen, nicht erreichbar. Deshalb steht der Text im
/// Binary und wird gerendert.
void main() {
  test('Die Erklaerung ist als Text in der App vorhanden', () {
    expect(kPrivacyPolicyDe, isNotEmpty,
        reason: 'Ohne Bloecke gibt es keinen Text in der App.');

    // Mehr als eine Ueberschrift und ein Absatz: Play verlangt eine
    // Erklaerung, keinen Satz.
    expect(kPrivacyPolicyDe.where((b) => b.kind == 'h2').length,
        greaterThanOrEqualTo(5));
    expect(kPrivacyPolicyDe.where((b) => b.kind == 'p').length,
        greaterThanOrEqualTo(10));
  });

  test('Jeder Block ist gerendert - keine unbekannte Art', () {
    const erlaubt = <String>{
      'h1', 'h2', 'h3', 'p', 'li', 'table', 'table_head',
    };
    for (final block in kPrivacyPolicyDe) {
      expect(
        erlaubt.contains(block.kind),
        isTrue,
        reason: 'Blockart "${block.kind}" wird im Screen nicht behandelt '
            'und faellt auf den Absatz-Zweig zurueck. Das sieht dann '
            'aus wie Fliesstext statt wie eine Tabelle.',
      );
    }
  });

  test('Die veroeffentlichte HTML-Datei hat keine Doppelungen', () {
    // Ein echter Fehler: im Renderer fehlte nach dem Heading-Zweig ein
    // `continue`, wodurch jede Ueberschrift ZWEIMAL ausgegeben wurde -
    // einmal als h2 und einmal als Absatz mit demselben Text. Im
    // Play-Eintrag steht so eine Erklaerung, in der jeder Abschnitt
    // zweimal beginnt. Der Dart-Text fuer die App war nicht betroffen.
    final html = File(publishPath).readAsStringSync();

    final headings = RegExp(r'<h[123]>(.*?)</h[123]>', dotAll: true)
        .allMatches(html)
        .map((m) => m.group(1)!.trim())
        .toList();
    final paragraphs = RegExp(r'<p>(.*?)</p>', dotAll: true)
        .allMatches(html)
        .map((m) => m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim())
        .toSet();

    expect(headings, isNotEmpty);
    for (final h in headings) {
      expect(
        paragraphs.contains(h),
        isFalse,
        reason: 'Ueberschrift steht auch als Absatz da: "$h"',
      );
    }
  });

  test('Die HTML-Datei enthaelt die Entitaet aus dem Store-Eintrag', () {
    final html = File(publishPath).readAsStringSync();
    expect(html, contains('Verantwortliche Stelle im Sinne der DSGVO '
        'ist <strong>Thestia</strong>'),
        reason: 'Play verlangt, dass die im Store-Eintrag genannte '
            'Entitaet in der Erklaerung auftaucht. Store: "Thestia".');
  });

  test('Die HTML-Datei ist statisch - kein Skript, keine externen Requests',
      () {
    final html = File(publishPath).readAsStringSync();
    expect(html, isNot(contains('<script')));
    expect(RegExp(r'src\s*=\s*"http').hasMatch(html), isFalse);
    expect(RegExp(r'href\s*=\s*"https?://(?!thestia)').hasMatch(html), isFalse,
        reason: 'Externe Requests wuerden die Seite verlangsamen und '
            'einen Besuch bei Dritten registrieren.');
  });

  test('Tabellenzeilen haben Zellen, andere Bloecke keinen', () {
    for (final block in kPrivacyPolicyDe) {
      if (block.kind == 'table' || block.kind == 'table_head') {
        expect(block.cells, isNotNull);
        expect(block.cells, isNotEmpty);
      } else {
        expect(block.cells, isNull,
            reason: 'Absatz "${block.text}" traegt unnoetige Zell-Daten.');
        expect(block.text.trim(), isNotEmpty,
            reason: 'Leerer Textblock ohne Zellen: erzeugt einen '
                'unsichtbaren Absatz mit Abstand.');
      }
    }
  });

  test('Kein Block bricht mitten im Satz ab', () {
    // Umbrochene Listenzeilen nicht mitzunehmen war ein echter Fehler
    // im Generator: der Satz zerfiel mitten im Wort. Ein Text, der mit
    // einem Kleinbuchstaben endet und mit einem Grossbuchstaben oder
    // klein beginnt, sieht danach aus - hart zu pruefen ist das nicht,
    // aber ein Text darf nicht mit einem Komma-Fragment enden.
    for (final block in kPrivacyPolicyDe) {
      if (block.kind == 'table' || block.kind == 'table_head') continue;
      final t = block.text.trim();
      expect(t, isNot(endsWith(',')),
          reason: 'Text endet mit einem Komma - ein Satzbruch wurde '
              'als eigener Block abgetrennt: "${t.substring(t.length > 40 ? t.length - 40 : 0)}"');
      expect(t, isNot(endsWith('und')),
          reason: 'Text endet mit "und" - mitten im Satz abgeschnitten.');
    }
  });

  testWidgets('Der Bildschirm zeigt den Anfang der Erklaerung',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyTextScreen()));
    await tester.pump();

    final ersterH1 = kPrivacyPolicyDe.firstWhere((b) => b.kind == 'h1');
    expect(
      find.text(ersterH1.text.replaceAll('**', '').trim()),
      findsOneWidget,
      reason: 'Der Titel muss sichtbar sein - sonst ist nicht erkennbar, '
          'dass hier die Datenschutzerklaerung steht.',
    );
  });

  testWidgets('Kein Textblock wird als Markdown angezeigt',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyTextScreen()));
    await tester.pump();

    // Die Sterne duerfen nirgends im sichtbaren Text landen. Sie sind
    // Auszeichnung, kein Inhalt.
    expect(find.textContaining('**'), findsNothing);
  });
}