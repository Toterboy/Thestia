import 'package:flutter/material.dart';

/// Verfügbare Farbschemata ("Erscheinungsbilder").
///
/// Classic ist das ursprüngliche Thestia-Rosa; die anderen sind
/// gleichwertige Alternativen (Light + Dark aus demselben Seed).
enum ThestiaTheme {
  classic('Classic Thestia', 'theme.classic', Color(0xFFE9457B)),
  ocean('Ozean', 'theme.ocean', Color(0xFF1E88E5)),
  forest('Wald', 'theme.forest', Color(0xFF2E7D32)),
  sunset('Sonnenuntergang', 'theme.sunset', Color(0xFFF57C00)),
  lila('Lavendel', 'theme.lavender', Color(0xFF8E6BD0)),
  mono('Schiefer', 'theme.slate', Color(0xFF546E7A));

  const ThestiaTheme(this.label, this.labelKey, this.primaryColor);

  final String label;

  /// L10n-Schlüssel (v0.8.1: EN-Übersetzung der Farbschemata).
  final String labelKey;

  final Color primaryColor;

  /// Kompakter Anzeigename für den Picker (feste Kachelbreite).
  String get shortLabel => switch (this) {
        ThestiaTheme.classic => 'Classic',
        ThestiaTheme.ocean => 'Ozean',
        ThestiaTheme.forest => 'Wald',
        ThestiaTheme.sunset => 'Sonnenuntergang',
        ThestiaTheme.lila => 'Lavendel',
        ThestiaTheme.mono => 'Schiefer',
      };

  /// Aufhellung für Dark-Mode-Akzente.
  Color get lightPrimary => Color.lerp(primaryColor, Colors.white, 0.25)!;

  static ThestiaTheme fromName(String? name) => ThestiaTheme.values
      .where((t) => t.name == name)
      .firstOrNull ?? ThestiaTheme.classic;
}

/// Zentrale Design-Farben der App (warm, einladend, modern).
class AppColors {
  AppColors._();

  /// Primärfarbe (romantisches Korallen/Rosa).
  static const Color primary = Color(0xFFE9457B);
  static const Color primaryLight = Color(0xFFF4799E);
  static const Color primaryDark = Color(0xFFB72E5C);

  /// Akzentfarbe für Sekundäres (Like = grün).
  static const Color like = Color(0xFF4CAF82);
  static const Color nope = Color(0xFFEF5350);
  static const Color superLike = Color(0xFF42A5F5);

  /// Neutrale Hintergründe.
  static const Color backgroundLight = Color(0xFFF7F7FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  /// Verlauf für Hero-Bereiche.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Wiederverwendbare Theme-Definitionen (Material 3).
///
/// Runde Buttons, abgerundete Karten und weiche Schatten werden hier
/// zentral definiert, damit alle Screens konsistent aussehen.
class AppTheme {
  AppTheme._();

  /// Light Theme (Material 3) für das gewählte Farbschema.
  static ThemeData light({ThestiaTheme theme = ThestiaTheme.classic}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primaryColor,
          brightness: Brightness.light,
          surface: AppColors.surfaceLight,
        ),
        scaffoldBackgroundColor: AppColors.backgroundLight,
        cardTheme: _cardTheme(AppColors.surfaceLight),
        popupMenuTheme: _popupMenuTheme(AppColors.surfaceLight),
        // Klick-Animation (Ripple) folgt der 24-px-Rundung der Karten -
        // überall derselbe abgerundete Effekt, auch beim Antippen (v0.8.1).
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
        elevatedButtonTheme: _elevatedButtonTheme,
        filledButtonTheme: _filledButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        inputDecorationTheme: _inputDecorationTheme(
            AppColors.surfaceLight, theme.primaryColor),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          elevation: 8,
          selectedItemColor: theme.primaryColor,
        ),
        // Snackbars als schwebende Bubbles am unteren Rand – konsistent
        // für Light- und Dark-Mode.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        extensions: const <ThemeExtension<dynamic>>[
          BlindModeTheme(placeholderColor: Color(0xFFE1E1EC)),
        ],
      );

  /// Dark Theme (Material 3) für das gewählte Farbschema.
  static ThemeData dark({ThestiaTheme theme = ThestiaTheme.classic}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.primaryColor,
          brightness: Brightness.dark,
          surface: AppColors.surfaceDark,
        ),
        scaffoldBackgroundColor: AppColors.backgroundDark,
        cardTheme: _cardTheme(AppColors.surfaceDark),
        popupMenuTheme: _popupMenuTheme(AppColors.surfaceDark),
        // Klick-Animation (Ripple) folgt der 24-px-Rundung der Karten -
        // überall derselbe abgerundete Effekt, auch beim Antippen (v0.8.1).
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
        elevatedButtonTheme: _elevatedButtonTheme,
        filledButtonTheme: _filledButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        inputDecorationTheme: _inputDecorationTheme(
            AppColors.surfaceDark, theme.primaryColor),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          elevation: 8,
          selectedItemColor: theme.lightPrimary,
        ),
        // Snackbars als schwebende Bubbles am unteren Rand – konsistent
        // für Light- und Dark-Mode.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        extensions: const <ThemeExtension<dynamic>>[
          BlindModeTheme(placeholderColor: Color(0xFF2C2C2C)),
        ],
      );

  /// Popup-Menüs (z. B. Sprachumschalter) mit demselben 16-px-Radius wie
  /// Cards/Snackbars/Inputs - konsistent abgerundet in der ganzen App.
  static PopupMenuThemeData _popupMenuTheme(Color surface) => PopupMenuThemeData(
        color: surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      );

  static CardThemeData _cardTheme(Color surface) => CardThemeData(        color: surface,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.12),
      );

  static ElevatedButtonThemeData get _elevatedButtonTheme =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static FilledButtonThemeData get _filledButtonTheme => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static OutlinedButtonThemeData get _outlinedButtonTheme =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      );

  static InputDecorationTheme _inputDecorationTheme(
      Color surface, Color primary) =>
      InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        // FIX Farbthemes: Bisher waren die Rahmen auf die Classic-Pink
        // (AppColors.primary/primaryLight) hartcodiert - Ozean, Wald,
        // Sonnenuntergang, Lavendel und Schiefer wurden an den Rahmen
        // nicht uebernommen. Jetzt leiten sich beide aus der aktiven
        // Primärfarbe ab (aktiv halbtransparent, fokussiert voll).
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primary.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

/// Theme-Extension für Blind-Mode-spezifische Farben.
class BlindModeTheme extends ThemeExtension<BlindModeTheme> {
  const BlindModeTheme({required this.placeholderColor});

  /// Farbe des Platzhalters, wenn Fotos ausgeblendet sind.
  final Color placeholderColor;

  @override
  BlindModeTheme copyWith({Color? placeholderColor}) {
    return BlindModeTheme(
      placeholderColor: placeholderColor ?? this.placeholderColor,
    );
  }

  @override
  BlindModeTheme lerp(ThemeExtension<BlindModeTheme>? other, double t) {
    if (other is! BlindModeTheme) return this;
    return BlindModeTheme(
      placeholderColor:
          Color.lerp(placeholderColor, other.placeholderColor, t) ??
              placeholderColor,
    );
  }
}
