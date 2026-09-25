import 'package:flutter/material.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/utils/age_calculator.dart';
import 'package:thestia/utils/common_passwords.dart';

/// Mindestalter für die Nutzung der App.
const int minimumAge = 16;

/// Eingabe-Validierung für Formulare (Profil, Auth).
///
/// Alle meldungserzeugenden Methoden nehmen einen [BuildContext] und
/// lösen ihre Texte über L10n-Keys auf (volle DE/EN-Abdeckung).
class Validators {
  Validators._();

  /// Pflichtfeld - darf nicht leer sein.
  static String? required(BuildContext context, String? value,
      {String? field}) {
    if (value == null || value.trim().isEmpty) {
      return L10n.tf(context, 'validation.required',
          {'field': field ?? L10n.t(context, 'validation.field')});
    }
    return null;
  }

  /// Name: mindestens 2 Zeichen.
  static String? name(BuildContext context, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return L10n.t(context, 'validation.nameEmpty');
    if (v.length < 2) return L10n.t(context, 'validation.nameShort');
    return null;
  }

  /// Alter: zwischen [minimumAge] und 99.
  ///
  /// Nutzer unter [minimumAge] Jahren werden abgelehnt (altersbedingte
  /// Zugriffsbeschränkung der App).
  static String? age(BuildContext context, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return L10n.t(context, 'validation.ageEmpty');
    final parsed = int.tryParse(v);
    if (parsed == null) return L10n.t(context, 'validation.ageNumber');
    if (parsed < minimumAge) {
      return L10n.tf(context, 'validation.ageMin', {'age': '$minimumAge'});
    }
    if (parsed > 99) return L10n.t(context, 'validation.ageInvalid');
    return null;
  }

  /// Prüft, ob der Nutzer mindestens [minimumAge] Jahre alt ist.
  ///
  /// Liefert `true`, wenn das Alter zulässig ist. Wirft keine Exception,
  /// sondern gibt bei ungültiger Eingabe `false` zurück.
  static bool isOldEnough(int? age) =>
      age != null && age >= minimumAge && age <= 99;

  /// E-Mail-Validierung: Format + gültige Domain-Endung.
  ///
  /// Akzeptiert gängige TLDs wie .de, .com, .net, .org (sowie weitere
  /// zwei- bis mehrbuchstabige Endungen).
  static String? email(BuildContext context, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return L10n.t(context, 'validation.emailEmpty');
    if (!_emailRegExp.hasMatch(v)) {
      return L10n.t(context, 'validation.emailInvalid');
    }
    final domainPart = v.split('@').last;
    final tld = domainPart.contains('.')
        ? domainPart.split('.').last.toLowerCase()
        : '';
    if (tld.length < 2) {
      return L10n.t(context, 'validation.emailTld');
    }
    return null;
  }

  /// Prüft, ob eine E-Mail formal gültig ist (ohne Fehlermeldung).
  static bool isValidEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return false;
    if (!_emailRegExp.hasMatch(v)) return false;
    final domainPart = v.split('@').last;
    final tld = domainPart.contains('.')
        ? domainPart.split('.').last.toLowerCase()
        : '';
    return tld.length >= 2;
  }

  /// Passwort: mindestens 8 Zeichen, mindestens ein Buchstabe und eine Zahl.
  /// Häufige Passwörter aus einer Blockliste werden abgelehnt.
  static String? password(BuildContext context, String? value) {
    final v = value ?? '';
    if (v.isEmpty) return L10n.t(context, 'validation.passwordEmpty');
    if (v.length < 8) return L10n.t(context, 'validation.passwordLength');
    if (!v.contains(RegExp('[a-zA-ZäöüÄÖÜß]'))) {
      return L10n.t(context, 'validation.passwordLetter');
    }
    if (!v.contains(RegExp('[0-9]'))) {
      return L10n.t(context, 'validation.passwordDigit');
    }
    if (commonPasswords.contains(v.toLowerCase())) {
      return L10n.t(context, 'validation.passwordCommon');
    }
    return null;
  }

  /// Passwort bei der Registrierung: erfüllt die Server-Policy
  /// (Password Strength Policy im Supabase-Dashboard): mindestens 8
  /// Zeichen, Groß- und Kleinbuchstaben, mindestens eine Zahl und ein
  /// Sonderzeichen. Häufige Passwörter aus einer Blockliste werden
  /// abgelehnt.
  ///
  /// Sammelt ALLE fehlenden Anforderungen und nennt sie gemeinsam –
  /// sonst sieht der Nutzer nur die erste fehlende Regel und weiß nicht,
  /// was noch alles verlangt wird.
  static String? registrationPassword(BuildContext context, String? value) {
    final v = value ?? '';
    if (v.isEmpty) return L10n.t(context, 'validation.passwordEmpty');
    final missing = <String>[];
    if (v.length < 8) {
      missing.add(L10n.t(context, 'validation.pwChars'));
    }
    if (!v.contains(RegExp('[a-zäöüß]'))) {
      missing.add(L10n.t(context, 'validation.pwLower'));
    }
    if (!v.contains(RegExp('[A-ZÄÖÜ]'))) {
      missing.add(L10n.t(context, 'validation.pwUpper'));
    }
    if (!v.contains(RegExp('[0-9]'))) {
      missing.add(L10n.t(context, 'validation.pwDigit'));
    }
    if (!v.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/~`]'))) {
      missing.add(L10n.t(context, 'validation.pwSpecial'));
    }
    if (missing.isNotEmpty) {
      return L10n.tf(
          context, 'validation.pwMissing', {'list': missing.join(', ')});
    }
    // Normalisiert vergleichen (Kleinbuchstaben, ohne Sonderzeichen):
    // Sonst wäre die Liste wirkungslos, weil jedes Passwort mit allen
    // Zeichenklassen Sonderzeichen enthält, die Liste aber nicht.
    final normalized = v.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (commonPasswords.contains(normalized)) {
      return L10n.t(context, 'validation.passwordCommon');
    }
    return null;
  }

  /// Gibt eine textuelle Passwort-Stärke zurück (für UI-Feedback).
  static String passwordStrength(BuildContext context, String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (value.contains(RegExp('[a-z]'))) score++;
    if (value.contains(RegExp('[A-ZÄÖÜ]'))) score++;
    if (value.contains(RegExp('[0-9]'))) score++;
    if (value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/~`]'))) score++;
    if (score <= 2) return L10n.t(context, 'validation.pwWeak');
    if (score <= 4) return L10n.t(context, 'validation.pwMedium');
    return L10n.t(context, 'validation.pwStrong');
  }

  /// Berechnet das volle Alter in Jahren aus einem Geburtsdatum.
  ///
  /// Delegiert an die zentrale [calculateAge]-Funktion in age_calculator.dart.
  /// Liefert `null`, wenn das Datum in der Zukunft liegt oder `null` ist.
  static int? ageFromBirthDate(DateTime? birthDate) {
    return calculateAge(birthDate);
  }

  /// Validiert ein Geburtsdatum: Pflichtfeld, nicht in der Zukunft,
  /// und der Nutzer muss mindestens [minimumAge] Jahre alt sein.
  static String? birthDate(BuildContext context, DateTime? value) {
    if (value == null) return L10n.t(context, 'validation.birthEmpty');
    if (value.isAfter(DateTime.now())) {
      return L10n.t(context, 'validation.birthFuture');
    }
    final age = calculateAge(value);
    if (age == null || age < minimumAge) {
      return L10n.tf(
          context, 'validation.ageMin', {'age': '$minimumAge'});
    }
    if (age > 99) return L10n.t(context, 'validation.birthInvalid');
    return null;
  }
  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-äöüßÄÖÜ]+@[a-zA-Z0-9._%+-äöüßÄÖÜ]+\.[a-zA-Z]{2,}$',
  );

  /// Bio: optional, max. 300 Zeichen.
  static String? bio(BuildContext context, String? value) {
    final v = value?.trim() ?? '';
    if (v.length > 300) return L10n.t(context, 'validation.bioLong');
    return null;
  }
}
