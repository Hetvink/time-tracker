import 'package:flutter/material.dart';

class IOSTheme {
  // iOS Default Color Palette
  static const Color iosSystemBlue = Color(0xFF007AFF);
  static const Color iosSystemGreen = Color(0xFF34C759);
  static const Color iosSystemIndigo = Color(0xFF5856D6);
  static const Color iosSystemOrange = Color(0xFFFF9500);
  static const Color iosSystemPink = Color(0xFFFF2D55);
  static const Color iosSystemPurple = Color(0xFFAF52DE);
  static const Color iosSystemRed = Color(0xFFFF3B30);
  static const Color iosSystemTeal = Color(0xFF5AC8FA);
  static const Color iosSystemYellow = Color(0xFFFFCC00);

  // iOS Gray Scale
  static const Color iosGray = Color(0xFF8E8E93);
  static const Color iosGray2 = Color(0xFFAEAEB2);
  static const Color iosGray3 = Color(0xFFC7C7CC);
  static const Color iosGray4 = Color(0xFFD1D1D6);
  static const Color iosGray5 = Color(0xFFE5E5EA);
  static const Color iosGray6 = Color(0xFFF2F2F7);

  // Light Mode Colors
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightCardBackground = Color(0xFFFFFFFF);
  static const Color lightSecondaryBackground = Color(0xFFF2F2F7);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF8E8E93);

  // Dark Mode Colors
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkCardBackground = Color(0xFF1C1C1E);
  static const Color darkSecondaryBackground = Color(0xFF2C2C2E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8E8E93);

  // Glass Morphism Settings
  static const double glassBlur = 20.0;
  static const double glassOpacity = 0.7;
  static const double glassBorderOpacity = 0.2;

  // Border Radius
  static const double smallRadius = 12.0;
  static const double mediumRadius = 16.0;
  static const double largeRadius = 24.0;

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // Light Theme
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: iosSystemBlue,
      secondary: iosSystemTeal,
      tertiary: iosSystemPurple,
      error: iosSystemRed,
      onSecondary: Colors.white,
    ),
    scaffoldBackgroundColor: lightBackground,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mediumRadius),
      ),
      color: lightCardBackground.withValues(alpha: 0.9),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: lightTextPrimary,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: lightTextPrimary,
        letterSpacing: -0.41,
      ),
    ),
    textTheme: _buildTextTheme(lightTextPrimary, lightTextSecondary),
    iconTheme: const IconThemeData(color: iosSystemBlue),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: lightCardBackground.withValues(alpha: 0.8),
      indicatorColor: iosSystemBlue.withValues(alpha: 0.1),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: iosGray5,
      thickness: 0.5,
      space: 1,
    ),
  );

  // Dark Theme
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: iosSystemBlue,
      secondary: iosSystemTeal,
      tertiary: iosSystemPurple,
      surface: darkCardBackground,
      error: iosSystemRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
    ),
    scaffoldBackgroundColor: darkBackground,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mediumRadius),
      ),
      color: darkCardBackground.withValues(alpha: 0.9),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: darkTextPrimary,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        letterSpacing: -0.41,
      ),
    ),
    textTheme: _buildTextTheme(darkTextPrimary, darkTextSecondary),
    iconTheme: const IconThemeData(color: iosSystemBlue),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: darkCardBackground.withValues(alpha: 0.8),
      indicatorColor: iosSystemBlue.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: darkSecondaryBackground,
      thickness: 0.5,
      space: 1,
    ),
  );

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      // Large Title - iOS Style
      displayLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: 0.37,
      ),
      // Title 1
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: 0.36,
      ),
      // Title 2
      displaySmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: 0.35,
      ),
      // Title 3
      headlineLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primary,
        letterSpacing: 0.38,
      ),
      // Headline
      headlineMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: primary,
        letterSpacing: -0.41,
      ),
      // Body
      bodyLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: primary,
        letterSpacing: -0.41,
      ),
      // Callout
      bodyMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: primary,
        letterSpacing: -0.32,
      ),
      // Subheadline
      bodySmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: secondary,
        letterSpacing: -0.24,
      ),
      // Footnote
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: secondary,
        letterSpacing: -0.08,
      ),
      // Caption 1
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
        letterSpacing: 0,
      ),
      // Caption 2
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: secondary,
        letterSpacing: 0.07,
      ),
    );
  }
}
