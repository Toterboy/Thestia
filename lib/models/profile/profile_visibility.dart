/// Sichtbarkeit des eigenen Profils - zentrale Privatsphäre-Einstellung.
enum ProfileVisibility {
  /// Jeder (auch Nicht-Matches) kann das Profil sehen.
  everyone('everyone', 'Jeder', 'settings.visEveryone'),

  /// Nur Nutzer, mit denen man einen Funken hat, sehen das Profil.
  matchesOnly('matches_only', 'Nur Funken', 'settings.visMatchesOnly'),

  /// Profil ist unsichtbar (Pause-Modus).
  hidden('hidden', 'Unsichtbar (Pausiert)', 'settings.visHidden');

  const ProfileVisibility(this.value, this.label, this.labelKey);

  /// Technischer Schlüssel für die Speicherung.
  final String value;

  /// Fallback-Anzeige (deutsch) - Anzeige bevorzugt über [labelKey].
  final String label;

  /// L10n-Schlüssel (v0.8.1: EN-Übersetzung).
  final String labelKey;

  /// Findet die Sichtbarkeit anhand des gespeicherten Schlüssels.
  static ProfileVisibility fromValue(String? value) {
    return ProfileVisibility.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ProfileVisibility.everyone,
    );
  }
}
