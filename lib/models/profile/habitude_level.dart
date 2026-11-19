/// Verhalten zu Rauchen, Alkohol und anderen Drogen.
///
/// Die Stufen sind bewusst geordnet (Nie < Gelegentlich < Täglich), damit der
/// Find-your-Match-Algorithmus kompatible Profile filtern kann: Es werden nur
/// Personen angezeigt, deren Konsum maximal so hoch ist wie der eigene.
enum HabitudeLevel {
  /// Nie.
  never,

  /// Gelegentlich.
  occasionally,

  /// Täglich.
  daily;

  /// Map aus dem serverseitigen Textwert (profiles.smoking u. a.).
  static HabitudeLevel? fromServer(String? value) {
    switch (value) {
      case 'never':
        return HabitudeLevel.never;
      case 'occasionally':
        return HabitudeLevel.occasionally;
      case 'daily':
        return HabitudeLevel.daily;
      default:
        return null;
    }
  }

  /// Serverseitiger Textwert (profiles.smoking u. a.).
  String toServer() => name;
}

/// Erweiterungen für [HabitudeLevel].
extension HabitudeLevelX on HabitudeLevel {
  /// Anzeige-Text (Button-Beschriftung).
  String get label {
    switch (this) {
      case HabitudeLevel.never:
        return 'Nie';
      case HabitudeLevel.occasionally:
        return 'Gelegentlich';
      case HabitudeLevel.daily:
        return 'Täglich';
    }
  }

  /// Ordnungswert für den Vergleich (je höher, desto stärkerer Konsum).
  int get rank {
    switch (this) {
      case HabitudeLevel.never:
        return 0;
      case HabitudeLevel.occasionally:
        return 1;
      case HabitudeLevel.daily:
        return 2;
    }
  }
}

/// Themen, für die eine Konsum-Präferenz erfasst wird.
enum HabitudeTopic {
  /// Rauchen.
  smoking,

  /// Alkohol.
  alcohol,

  /// Andere Drogen.
  drugs,
}

/// Erweiterungen für [HabitudeTopic].
extension HabitudeTopicX on HabitudeTopic {
  /// Anzeige-Text (Überschrift).
  String get label {
    switch (this) {
      case HabitudeTopic.smoking:
        return 'Rauchen';
      case HabitudeTopic.alcohol:
        return 'Alkohol';
      case HabitudeTopic.drugs:
        return 'Andere Drogen';
    }
  }
}
