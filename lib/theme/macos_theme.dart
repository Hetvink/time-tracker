import 'package:flutter/material.dart';

class MacOSTheme {
  // macOS System Colors (SF Pro Colors)
  static const Color systemBlue = Color(0xFF007AFF);
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemIndigo = Color(0xFF5856D6);
  static const Color systemOrange = Color(0xFFFF9500);
  static const Color systemPink = Color(0xFFFF2D55);
  static const Color systemPurple = Color(0xFFAF52DE);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemTeal = Color(0xFF5AC8FA);
  static const Color systemYellow = Color(0xFFFFCC00);

  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);
  static const Color systemGray4 = Color(0xFFD1D1D6);
  static const Color systemGray5 = Color(0xFFE5E5EA);
  static const Color systemGray6 = Color(0xFFF2F2F7);

  // Dark Mode System Grays
  static const Color systemGrayDark = Color(0xFF8E8E93);
  static const Color systemGray2Dark = Color(0xFF636366);
  static const Color systemGray3Dark = Color(0xFF48484A);
  static const Color systemGray4Dark = Color(0xFF3A3A3C);
  static const Color systemGray5Dark = Color(0xFF2C2C2E);
  static const Color systemGray6Dark = Color(0xFF1C1C1E);

  // Semantic Colors
  static const Color lightSidebar = Color(
    0xFFF0F0F5,
  ); // Translucent-ish look base
  static const Color darkSidebar = Color(0xFF2D2D2D);

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF1E1E1E);

  static const Color lightDivider = Color(0xFFE5E5E5);
  static const Color darkDivider = Color(0xFF383838);

  // Typography
  static TextTheme get typography => const TextTheme(
    displayLarge: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
      fontFamily: '.SF Pro Display', // Use system font if possible
    ),
    displayMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.4,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.2,
    ),
    bodyMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.1,
    ),
  );

  // Animation durations
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration normalAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);

  // Spacing constants
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  // Activity colors
  static Color getActivityColor(String activityType, {bool isDark = false}) {
    switch (activityType.toLowerCase()) {
      case 'work':
        return systemGreen;
      case 'break':
        return systemOrange;
      case 'idle':
        return isDark ? systemGray2Dark : systemGray;
      default:
        return systemBlue;
    }
  }

  // Grid line colors
  static Color getGridLineColor(bool isHourBoundary, {bool isDark = false}) {
    if (isHourBoundary) {
      return isDark ? systemGray4Dark : systemGray4;
    } else {
      return isDark ? systemGray5Dark : systemGray5;
    }
  }

  // Activity background opacity
  static const double activityBackgroundOpacity = 0.15;
  static const double activityBackgroundOpacityDark = 0.2;
  static const double activityBorderOpacity = 0.4;
  static const double activityBorderOpacityDark = 0.5;

  // Light Theme Data
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: systemBlue,
        outline: lightDivider,
      ),
      dividerTheme: const DividerThemeData(color: lightDivider, thickness: 1),
      iconTheme: const IconThemeData(color: systemGray, size: 20),
      textTheme: typography.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      extensions: const [
        MacOSThemeColors(
          sidebarColor: lightSidebar,
          separatorColor: lightDivider,
        ),
      ],
    );
  }

  // Dark Theme Data
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: systemBlue,
        surface: darkBackground,
        outline: darkDivider,
      ),
      dividerTheme: const DividerThemeData(color: darkDivider, thickness: 1),
      iconTheme: const IconThemeData(color: systemGray, size: 20),
      textTheme: typography.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      extensions: const [
        MacOSThemeColors(
          sidebarColor: darkSidebar,
          separatorColor: darkDivider,
        ),
      ],
    );
  }
}

// Theme Extension to access custom semantic colors easily
class MacOSThemeColors extends ThemeExtension<MacOSThemeColors> {
  final Color sidebarColor;
  final Color separatorColor;

  const MacOSThemeColors({
    required this.sidebarColor,
    required this.separatorColor,
  });

  @override
  ThemeExtension<MacOSThemeColors> copyWith({
    Color? sidebarColor,
    Color? separatorColor,
  }) {
    return MacOSThemeColors(
      sidebarColor: sidebarColor ?? this.sidebarColor,
      separatorColor: separatorColor ?? this.separatorColor,
    );
  }

  @override
  ThemeExtension<MacOSThemeColors> lerp(
    ThemeExtension<MacOSThemeColors>? other,
    double t,
  ) {
    if (other is! MacOSThemeColors) {
      return this;
    }
    return MacOSThemeColors(
      sidebarColor: Color.lerp(sidebarColor, other.sidebarColor, t)!,
      separatorColor: Color.lerp(separatorColor, other.separatorColor, t)!,
    );
  }
}
