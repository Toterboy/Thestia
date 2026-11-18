import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/auth_exception.dart';

import 'package:thestia/l10n/strings/grundlagen.dart';
import 'package:thestia/l10n/strings/laender.dart';
import 'package:thestia/l10n/strings/start.dart';
import 'package:thestia/l10n/strings/anmeldung.dart';
import 'package:thestia/l10n/strings/fehler.dart';
import 'package:thestia/l10n/strings/chat.dart';
import 'package:thestia/l10n/strings/meldung.dart';
import 'package:thestia/l10n/strings/begegnungen.dart';
import 'package:thestia/l10n/strings/profil.dart';
import 'package:thestia/l10n/strings/personentest.dart';
import 'package:thestia/l10n/strings/vorstellung.dart';
import 'package:thestia/l10n/strings/einstellungen.dart';
import 'package:thestia/l10n/strings/geraete.dart';
import 'package:thestia/l10n/strings/datenschutz.dart';
import 'package:thestia/l10n/strings/schutz.dart';
import 'package:thestia/l10n/strings/verwaltung.dart';
import 'package:thestia/l10n/strings/transit.dart';
import 'package:thestia/l10n/strings/dating.dart';
import 'package:thestia/l10n/strings/zufall.dart';

/// App-Sprache (Deutsch/Englisch). Default: Deutsch. Der Startwert wird
/// in main() aus SharedPreferences als Override gesetzt; [saveLocale]
/// aktualisiert State + Persistenz.
final localeProvider = StateProvider<Locale>((ref) {
  return const Locale('de');
});

Future<void> saveLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_locale', locale.languageCode);
}

/// Zentrale Übersetzungen für die aktuell vollständig zweisprachig
/// ausgelieferten Oberflächen (Login/Registrieren, Einstellungen,
/// Navigation, Home, zentrale Dialoge). Nicht abgedeckte Keys fallen
/// auf Deutsch zurück.
class L10n {
  L10n._();

  static Locale localeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_L10nScope>()?.locale ??
      const Locale('de');

  static String t(BuildContext context, String key) {
    final locale = localeOf(context).languageCode;
    return _strings[locale]?[key] ?? _strings['de']![key] ?? key;
  }

  /// Wie [t], aber ohne [BuildContext].
  ///
  /// fuer Stellen, die keinen Kontext haben: ein StateNotifier kann
  /// keinen Widget-Kontext bauen, ein Hintergrund-Task gar nicht. Ohne
  /// diese Variante muesste dort entweder ein deutscher Klartext
  /// stehen (und damit die englische Fassung vergessen werden) oder
  /// der Aufrufer auf den naechsten Bildschirm warten.
  ///
  /// Es wird immer DEUZSCH gewaehlt - die Sprache des Geraets ist hier
  /// nicht ermittelbar, und Deutsch ist die Quellsprache der Datei.
  static String tWithoutContext(String key) =>
      _strings['de']?[key] ?? _strings['en']?[key] ?? key;

  /// Wie [t], ersetzt aber {platzhalter} im Text, z. B.
  /// tf(context, 'profile.edit.maxDistance', {'km': '42'}).
  static String tf(
    BuildContext context,
    String key,
    Map<String, String> params,
  ) {
    var s = t(context, key);
    params.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    return s;
  }

  /// Zeigt eine Service-Exception zweisprachig an: Services haben keinen
  /// BuildContext, liefern aber optional einen L10n-Key
  /// ([AppException.messageKey]) mit {platzhalter}-Params mit.
  /// Fallback: die deutsche Klartext-Message.
  static String exc(BuildContext context, Object e) {
    if (e is AppException) {
      final key = e.messageKey;
      if (key != null && key.isNotEmpty) {
        var s = t(context, key);
        if (s != key) {
          e.params.forEach((k, v) {
            s = s.replaceAll('{$k}', v);
          });
          return s;
        }
      }
      return e.message;
    }
    return e.toString();
  }
}

/// InheritedWidget, das die aktive Locale an [L10n.t] verteilt.
class _L10nScope extends InheritedWidget {
  const _L10nScope({required this.locale, required super.child});

  final Locale locale;

  @override
  bool updateShouldNotify(_L10nScope oldWidget) => oldWidget.locale != locale;
}

/// Wrappt [child] und stellt die aktive Locale für [L10n.t] bereit.
class L10nScope extends ConsumerWidget {
  const L10nScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return _L10nScope(locale: locale, child: child);
  }
}

/// Die Texte nach Themen (je Datei in `strings/`).
///
/// DER GRUND FUER DIE AUFTEILUNG: Eine Datei mit ueber 1000
/// Zeilen kann niemand mehr ueberblicken - jede Aenderung darin
/// wird riskant. Nach Themen geteilt sind die Dateien klein genug
/// zum Lesen (und der Test `code_datei_groessen_test` verhindert,
/// dass es wieder eins wird).
const List<Map<String, Map<String, String>>> _gruppen = [
  stringsGrundlagen,
  stringsLaender,
  stringsStart,
  stringsAnmeldung,
  stringsFehler,
  stringsChat,
  stringsMeldung,
  stringsBegegnungen,
  stringsProfil,
  stringsPersonentest,
  stringsVorstellung,
  stringsEinstellungen,
  stringsGeraete,
  stringsDatenschutz,
  stringsSchutz,
  stringsVerwaltung,
  stringsTransit,
  stringsDating,
  stringsZufall,
];

/// Alle Texte: zuerst die deutsche, dann die englische Fassung.
final Map<String, Map<String, String>> _strings = {
  'de': {for (final gruppe in _gruppen) ...gruppe['de']!},
  'en': {for (final gruppe in _gruppen) ...gruppe['en']!},
};
