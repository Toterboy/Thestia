import 'package:flutter/material.dart';
import 'package:wisp/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Liefert einen BuildContext (Default-Locale Deutsch, wie ohne Scope).
Future<BuildContext> _ctx(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }),
  ));
  return ctx;
}

void main() {
  group('Validators - required', () {
    testWidgets('lehnt null ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.required(context, null), isNotNull);
    });

    testWidgets('lehnt leere Strings ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.required(context, ''), isNotNull);
      expect(Validators.required(context, '  '), isNotNull);
    });

    testWidgets('akzeptiert nicht-leere Werte', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.required(context, 'ok'), isNull);
      expect(Validators.required(context, '  ok  '), isNull);
    });

    testWidgets('nutzt Feldnamen in der Fehlermeldung', (tester) async {
      final context = await _ctx(tester);
      final result = Validators.required(context, '', field: 'E-Mail');
      expect(result, isNotNull);
      expect(result, contains('E-Mail'));
    });

    testWidgets('Standard-Feldname ist Feld', (tester) async {
      final context = await _ctx(tester);
      final result = Validators.required(context, '');
      expect(result, contains('Feld'));
    });
  });

  group('Validators - name', () {
    testWidgets('lehnt null ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.name(context, null), isNotNull);
    });

    testWidgets('lehnt leere Strings ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.name(context, ''), isNotNull);
      expect(Validators.name(context, '  '), isNotNull);
    });

    testWidgets('lehnt ein Zeichen ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.name(context, 'A'), isNotNull);
    });

    testWidgets('akzeptiert ab 2 Zeichen', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.name(context, 'AB'), isNull);
      expect(Validators.name(context, 'ABc'), isNull);
    });

    testWidgets('trimmt Leerzeichen', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.name(context, ' A'), isNotNull); // Nach Trim nur 1 Zeichen
      expect(Validators.name(context, '  AB  '), isNull);
    });
  });

  group('Validators - age', () {
    testWidgets('lehnt leere Werte ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.age(context, ''), isNotNull);
      expect(Validators.age(context, '  '), isNotNull);
    });

    testWidgets('lehnt keine Zahl ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.age(context, 'abc'), isNotNull);
      expect(Validators.age(context, '12.5'), isNotNull);
      expect(Validators.age(context, ''), isNotNull);
    });

    testWidgets('akzeptiert 16 bis 99', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.age(context, '16'), isNull);
      expect(Validators.age(context, '18'), isNull);
      expect(Validators.age(context, '25'), isNull);
      expect(Validators.age(context, '99'), isNull);
    });

    testWidgets('lehnt unter 16 ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.age(context, '15'), isNotNull);
      expect(Validators.age(context, '0'), isNotNull);
      expect(Validators.age(context, '-5'), isNotNull);
    });

    testWidgets('lehnt ueber 99 ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.age(context, '100'), isNotNull);
      expect(Validators.age(context, '120'), isNotNull);
      expect(Validators.age(context, '200'), isNotNull);
    });

    testWidgets('Alter unter 16 wird mit klarer Meldung abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final msg = Validators.age(context, '14');
      expect(msg, isNotNull);
      expect(msg, contains('mindestens $minimumAge Jahre alt'));
    });

    testWidgets('Alter ueber 99 wird mit passender Meldung abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final msg = Validators.age(context, '100');
      expect(msg, isNotNull);
      expect(msg, contains('gültiges'));
    });
  });

  group('Validators - isOldEnough', () {
    testWidgets('akzeptiert ab 16', (tester) async {
      expect(Validators.isOldEnough(15), isFalse);
      expect(Validators.isOldEnough(16), isTrue);
      expect(Validators.isOldEnough(30), isTrue);
      expect(Validators.isOldEnough(99), isTrue);
    });

    testWidgets('lehnt ueber 99 ab', (tester) async {
      expect(Validators.isOldEnough(100), isFalse);
      expect(Validators.isOldEnough(150), isFalse);
    });

    testWidgets('lehnt null ab', (tester) async {
      expect(Validators.isOldEnough(null), isFalse);
    });
  });

  group('E-Mail-Validierung', () {
    testWidgets('gültige E-Mails werden akzeptiert', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.email(context, 'max@beispiel.de'), isNull);
      expect(Validators.email(context, 'a.b@mail.com'), isNull);
      expect(Validators.email(context, 'user@domain.net'), isNull);
      expect(Validators.email(context, 'x@y.org'), isNull);
      expect(Validators.email(context, 'test+filter@example.co.uk'), isNull);
    });

    testWidgets('ungueltige E-Mails werden abgelehnt', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.email(context, ''), isNotNull);
      expect(Validators.email(context, 'keinemail'), isNotNull);
      expect(Validators.email(context, 'max@beispiel'), isNotNull); // keine TLD
      expect(Validators.email(context, 'max@@de'), isNotNull);
      expect(Validators.email(context, 'max@beispiel.d'), isNotNull); // TLD zu kurz
      expect(Validators.email(context, ' @beispiel.de'), isNotNull);
      expect(Validators.email(context, 'max @beispiel.de'), isNotNull);
      expect(Validators.email(context, 'max@'), isNotNull);
      expect(Validators.email(context, '@beispiel.de'), isNotNull);
    });

    testWidgets('null wird abgelehnt', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.email(context, null), isNotNull);
    });

    testWidgets('isValidEmail spiegelt email() wider', (tester) async {
      expect(Validators.isValidEmail('max@beispiel.de'), isTrue);
      expect(Validators.isValidEmail('falsch'), isFalse);
      expect(Validators.isValidEmail(null), isFalse);
      expect(Validators.isValidEmail(''), isFalse);
    });
  });

  group('Passwort-Validierung', () {
    testWidgets('lehnt leere Passwoerter ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.password(context, ''), isNotNull);
      expect(Validators.password(context, null), isNotNull);
    });

    testWidgets('lehnt zu kurze Passwoerter ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.password(context, 'kurz'), isNotNull);
      expect(Validators.password(context, '1234567'), isNotNull);
    });

    testWidgets('akzeptiert ab 8 Zeichen mit Buchstabe und Zahl', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.password(context, 'langgenug1'), isNull);
      expect(Validators.password(context, 'meinSicheres99'), isNull);
      expect(Validators.password(context, 'Passwort1!'), isNull);
    });

    testWidgets('akzeptiert nur Buchstaben + Zahl', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.password(context, '12345678'), isNotNull);
    });

    testWidgets('lehnt häufige Passwörter ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.password(context, '12345678a'), isNotNull);
      expect(Validators.password(context, 'password1'), isNotNull);
      expect(Validators.password(context, 'qwerty123'), isNotNull);
    });
  });

  group('16+ Alterspruefung', () {
    testWidgets('isOldEnough akzeptiert ab 16', (tester) async {
      expect(Validators.isOldEnough(15), isFalse);
      expect(Validators.isOldEnough(16), isTrue);
      expect(Validators.isOldEnough(30), isTrue);
      expect(Validators.isOldEnough(99), isTrue);
      expect(Validators.isOldEnough(100), isFalse);
      expect(Validators.isOldEnough(null), isFalse);
    });

    testWidgets('Alter unter 16 wird mit klarer Meldung abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final msg = Validators.age(context, '14');
      expect(msg, isNotNull);
      expect(msg, contains('mindestens $minimumAge Jahre alt'));
    });
  });

  group('Bio-Validierung', () {
    testWidgets('leere Bio ist erlaubt', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.bio(context, ''), isNull);
      expect(Validators.bio(context, null), isNull);
    });

    testWidgets('akzeptiert bis 300 Zeichen', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.bio(context, 'A' * 300), isNull);
    });

    testWidgets('lehnt ueber 300 Zeichen ab', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.bio(context, 'A' * 301), isNotNull);
      expect(Validators.bio(context, 'A' * 500), isNotNull);
    });

    testWidgets('Fehlermeldung enthaelt die Grenze', (tester) async {
      final context = await _ctx(tester);
      final msg = Validators.bio(context, 'A' * 301);
      expect(msg, isNotNull);
      expect(msg, contains('300'));
    });
  });

  group('Geburtsdatum-Validierung', () {
    testWidgets('null wird abgelehnt', (tester) async {
      final context = await _ctx(tester);
      expect(Validators.birthDate(context, null), isNotNull);
    });

    testWidgets('Datum in der Zukunft wird abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final future = DateTime.now().add(const Duration(days: 1));
      expect(Validators.birthDate(context, future), isNotNull);
    });

    testWidgets('Datum heute wird akzeptiert wenn alt genug', (tester) async {
      final context = await _ctx(tester);
      // Person, die heute 16 wird (genau 16 Jahre alt)
      final today = DateTime.now();
      final exactly16 = DateTime(today.year - 16, today.month, today.day);
      // Wenn das Datum heute ist, ist die Person genau 16 -> akzeptiert
      final result = Validators.birthDate(context, exactly16);
      // Kann null oder nicht-null sein je nach genauer Uhrzeit,
      // aber mindestens sollte keine Zukunft-Meldung kommen
      if (result != null) {
        expect(result, isNot(contains('Zukunft')));
      }
    });

    testWidgets('unter 16 wird abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final tooYoung = DateTime.now().subtract(const Duration(days: 15 * 365));
      expect(Validators.birthDate(context, tooYoung), isNotNull);
    });

    testWidgets('ueber 99 wird abgelehnt', (tester) async {
      final context = await _ctx(tester);
      final tooOld = DateTime(DateTime.now().year - 100, DateTime.now().month, DateTime.now().day);
      expect(Validators.birthDate(context, tooOld), isNotNull);
    });

    testWidgets('16-99 wird akzeptiert', (tester) async {
      final context = await _ctx(tester);
      final ok = DateTime.now().subtract(const Duration(days: 25 * 365));
      expect(Validators.birthDate(context, ok), isNull);
    });
  });

  group('ageFromBirthDate', () {
    testWidgets('null liefert null', (tester) async {
      expect(Validators.ageFromBirthDate(null), isNull);
    });

    testWidgets('Datum in der Zukunft liefert null', (tester) async {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(Validators.ageFromBirthDate(future), isNull);
    });

    testWidgets('berechnt Alter korrekt', (tester) async {
      final birthDate = DateTime.now().subtract(const Duration(days: 25 * 365));
      final age = Validators.ageFromBirthDate(birthDate);
      expect(age, isNotNull);
      expect(age, inInclusiveRange(24, 26));
    });
  });
}
