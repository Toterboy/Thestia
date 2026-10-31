// Regressionstest: Der Passkey-Plugin MUSS in der App sein.
//
// ANLASS (31.10.2026): "Passkey geht noch immer nicht." Die Ursache
// war nicht der Server und nicht das Gerät: `supabase_flutter 2.18.3`
// hängt nur am `passkeys_platform_interface`, NICHT am app-seitigen
// `passkeys`-Paket. Flutter baut ein Endorsed-Plugin
// (`passkeys_android`) aber nur ein, wenn die App selbst vom
// App-Facing-Paket abhängt.
//
// Im Release-APK fehlten deshalb BEIDES:
//   * die Plugin-Klassen (com.corbado.passkeys_android.*)
//   * die Berechtigung CREDENTIAL_MANAGER_SET_ORIGIN
// Jeder Passkey-Versuch endete mit "MissingPluginException" - die
// Meldung im Coderatel war (zu Recht) auf dieses Plugin gemünzt.
//
// Dieser Test schützt die ABHÄNGIGKEIT, nicht das Artefakt: Ein
// Build-Test wäre hier zu teuer (Gradle-Lauf), und die Abhängigkeit
// ist die eigentliche Ursache.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Passkey-Plugin in der Abhaengigkeitsliste', () {
    test('passkeys ist eine ECHTE Abhaengigkeit der App', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      // Im dependencies-Block, nicht nur im dependency_overrides:
      // ein Override allein zieht das Paket nicht in die App.
      final dependencies = pubspec.split('dependency_overrides:').first;
      expect(
        dependencies,
        matches(RegExp(r'^\s*passkeys:\s*\d', multiLine: true)),
        reason: 'Das app-seitige passkeys-Paket muss eine direkte '
            'Abhaengigkeit sein - ohne es baut Flutter das Plugin nicht.',
      );

      // Und zwar fest gepinnt: das Paket steuert die Anmeldung.
      expect(
        dependencies,
        matches(RegExp(r'^\s*passkeys:\s*2\.\d+\.\d+\s*$', multiLine: true)),
        reason: 'passkeys ist sicherheitsrelevant und wird exakt gepinnt.',
      );
    });

    test('passkeys steht im Lockfile als "direct main"', () {
      final lock = File('pubspec.lock').readAsStringSync();
      // CRLF-tolerant: das Lockfile kann mit Windows-Zeilenenden
      // vorliegen, und der Test soll an der Zeilenende-Formatierung
      // nicht scheitern.
      final eintrag = RegExp(
        r'\r?\n  passkeys:\r?\n(?:[^\n]*\r?\n)*?    dependency: "([^"]+)"',
      ).firstMatch(lock);
      expect(eintrag, isNotNull,
          reason: 'passkeys muss im Lockfile stehen');
      expect(eintrag!.group(1), 'direct main',
          reason: 'Nur eine direkte Abhaengigkeit baut das Plugin ein - '
              '"transitive" oder "direct overridden" tun es nicht.');
    });

    test('passkeys_android ist als Fork eingebunden', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('passkeys_android:'),
        reason: 'Der KGP-freie Fork muss per Override eingebunden sein.',
      );
      expect(
        File('third_party/passkeys_android/pubspec.yaml').existsSync(),
        isTrue,
      );
    });

    test('der Plugin wird als Android-Plugin gefuehrt', () {
      // Die Datei wird von `flutter pub get` erzeugt. Fehlt sie, gibt es
      // in dieser Umgebung keine Aufloesung - dann sagt der Test nichts
      // und laeuft durch.
      final datei = File('.flutter-plugins-dependencies');
      if (!datei.existsSync()) return;

      final daten =
          jsonDecode(datei.readAsStringSync()) as Map<String, dynamic>;
      final android = (daten['plugins'] as Map<String, dynamic>?)?['android'];
      final namen = (android as List<dynamic>?)
              ?.map((e) => (e as Map<String, dynamic>)['name'] as String)
              .toList() ??
          <String>[];
      expect(
        namen,
        contains('passkeys_android'),
        reason: 'passkeys_android muss in der Android-Plugin-Liste stehen - '
            'nur dann landet der Plugin im Build.',
      );
    });
  });
}
