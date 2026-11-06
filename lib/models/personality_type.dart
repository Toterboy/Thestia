/// MBTI-Persönlichkeitstypen und Kompatibilitätsmatrix.
///
/// Vereinfachte Kompatibilitätsbewertung für den Matching-Algorithmus:
/// Jeder Typ erhält für jeden anderen Typ einen Wert von 0.0 bis 1.0.
/// Dies ist bewusst eine heuristische Demo-Matrix, keine psychologische
/// Aussage.
class PersonalityType {
  PersonalityType._(this.code);

  /// Vierbuchstabiger Typ-Code, z. B. "ENFP".
  final String code;

  /// Alle 16 MBTI-Typen.
  static const List<String> allTypes = [
    'INTJ',
    'INTP',
    'ENTJ',
    'ENTP',
    'INFJ',
    'INFP',
    'ENFJ',
    'ENFP',
    'ISTJ',
    'ISFJ',
    'ESTJ',
    'ESFJ',
    'ISTP',
    'ISFP',
    'ESTP',
    'ESFP',
  ];

  /// Liefert den [PersonalityType] für einen Code (null-safe).
  static PersonalityType? fromCode(String? code) {
    if (code == null) return null;
    final upper = code.toUpperCase();
    return allTypes.contains(upper) ? PersonalityType._(upper) : null;
  }
}

/// Statische Kompatibilitätsmatrix zwischen MBTI-Typen.
///
/// Schlüssel = eigener Typ, Wert = Map mit (anderer Typ -> Score 0..1).
/// Bekannte "klassische" Paare (z. B. NF/NT-Komplemente) werden höher
/// gewichtet, ansonsten ein neutraler Basiswert.
class MbtiCompatibility {
  MbtiCompatibility._();

  /// Liefert die Kompatibilität (0..1) zwischen zwei Typen.
  static double score(String a, String b) {
    if (a == b) return 0.9; // Gleichgesinnte passen oft gut.
    final ra = _dichotomy(a);
    final rb = _dichotomy(b);
    var s = 0.5;
    // Energie: Entgegengesetzt (E/I) gilt oft als ergänzend.
    if (ra[0] != rb[0]) s += 0.1;
    // Wahrnehmung: S/N-Mix wird oft als spannend empfunden.
    if (ra[1] != rb[1]) s += 0.1;
    // Entscheidung: T/F-Mix fördert Ausgleich.
    if (ra[2] != rb[2]) s += 0.1;
    // Lebensweise: Gleich (J/J oder P/P) gibt Struktur.
    if (ra[3] == rb[3]) s += 0.1;
    return s.clamp(0.0, 1.0);
  }

  /// Zerlegt einen Typ in seine 4 Buchstaben.
  static List<String> _dichotomy(String code) {
    if (code.length < 4) return ['', '', '', ''];
    return [code[0], code[1], code[2], code[3]];
  }
}
