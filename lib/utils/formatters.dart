// Hilfsfunktionen zur Formatierung von Werten in der UI.

import 'package:thestia/utils/age_calculator.dart';

class Formatters {
  Formatters._();

  /// Formatiert eine Distanz in km (z. B. "3 km" oder "< 1 km").
  static String distance(double km) {
    if (km < 1) return '< 1 km';
    return '${km.round()} km';
  }

  /// Formatiert einen Zeitstempel als Uhrzeit (HH:MM).
  static String time(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Relative Zeitangabe (z. B. "vor 5 Min.", "gestern").
  static String relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    if (diff.inDays == 1) return 'gestern';
    return 'vor ${diff.inDays} Tagen';
  }

  /// Berechnet das Alter aus einem Geburtsdatum.
  ///
  /// Delegiert an die zentrale [calculateAge]-Funktion in age_calculator.dart.
  static int? ageFromBirthDate(DateTime? birthDate) => calculateAge(birthDate);

  /// Alter aus einem Geburtsjahr berechnen (veraltet - nutze ageFromBirthDate).
  @Deprecated('Nutze ageFromBirthDate mit DateTime statt Jahr')
  static int ageFromYear(int birthYear) =>
      DateTime.now().year - birthYear;
}
