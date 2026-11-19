/// Geschlecht des eigenen Nutzers.
enum Gender {
  male('male', 'Männlich', 'gender.male'),
  female('female', 'Weiblich', 'gender.female'),
  maleTrans('male_trans', 'Männlich (F to M)', 'gender.maleTrans'),
  femaleTrans('female_trans', 'Weiblich (M to F)', 'gender.femaleTrans'),
  diverse('diverse', 'Divers', 'gender.diverse'),
  other('other', 'Eigenes / Anderes', 'gender.other');

  const Gender(this.value, this.label, this.labelKey);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Fallback-Anzeige (deutsch) - Anzeige bevorzugt über [labelKey] via L10n.
  final String label;

  /// L10n-Schlüssel (v0.8.1: EN-Übersetzung).
  final String labelKey;

  /// Findet das Geschlecht anhand des gespeicherten Schlüssels.
  static Gender? fromValue(String? value) {
    if (value == null) return null;
    return Gender.values.firstWhere(
      (e) => e.value == value,
      orElse: () => Gender.other,
    );
  }
}

/// Sexuelle Präferenz: Auf welches Geschlecht steht man?
///
/// Die Optionen entsprechen der Geschlechtsauswahl, damit die Präferenz
/// konsistent mit der eigenen Identität gewählt werden kann.
enum GenderPreference {
  male('male', 'Männlich', 'gender.male'),
  female('female', 'Weiblich', 'gender.female'),
  maleTrans('male_trans', 'Männlich (F to M)', 'gender.maleTrans'),
  femaleTrans('female_trans', 'Weiblich (M to F)', 'gender.femaleTrans'),
  diverse('diverse', 'Divers', 'gender.diverse'),
  other('other', 'Eigenes / Anderes', 'gender.other'),
  all('all', 'Alle', 'genderpref.all');

  const GenderPreference(this.value, this.label, this.labelKey);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Fallback-Anzeige (deutsch) - Anzeige bevorzugt über [labelKey].
  final String label;

  /// L10n-Schlüssel (v0.8.1: EN-Übersetzung).
  final String labelKey;

  /// Findet die Präferenz anhand des gespeicherten Schlüssels.
  static GenderPreference fromValue(String? value) {
    return GenderPreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => GenderPreference.all,
    );
  }
}

/// Beziehungsart: Was sucht der Nutzer?
enum RelationshipType {
  casual('casual', 'Lockere Bekanntschaft'),
  dating('dating', 'Ernsthaftes Dating'),
  relationship('relationship', 'Feste Beziehung'),
  friends('friends', 'Freundschaft'),
  open('open', 'Offen für alles');

  const RelationshipType(this.value, this.label);

  final String value;
  final String label;

  static RelationshipType fromValue(String? value) {
    return RelationshipType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RelationshipType.open,
    );
  }
}

/// Alle Geschlechter-Werte als Liste.
///
/// Entspricht der Mehrfachauswahl "Alle" (funktional identisch zu jedem
/// einzeln ausgewählten Geschlecht). Wird für die Präferenz-Liste
/// (UserPreferences), die "Alle"-Kurzform in der UI und als Default
/// für die Datenbank-Spalte profiles.gender_preferences verwendet.
final List<String> kAllGenderValues = Gender.values
    .map((g) => g.value)
    .toList(growable: false);
