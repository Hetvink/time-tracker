import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'macos_theme.dart';

/// Design tokens for the Time Trak UI. Read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHover;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color glass;
  final Color glassBorder;

  /// Translucent card fill that lets the backdrop glow through.
  final Color glassFill;

  /// Light edge along the top of glass surfaces (the iOS "sheen").
  final Color glassHighlight;
  final Color shadow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHover,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.glass,
    required this.glassBorder,
    required this.glassFill,
    required this.glassHighlight,
    required this.shadow,
  });

  // Brand + semantic colours are the same in both modes.
  static const primary = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
  static const pink = Color(0xFFEC4899);
  static const idle = Color(0xFF94A3B8);

  static const brandGradient = LinearGradient(
    colors: [primary, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const auroraGradient = LinearGradient(
    colors: [primary, violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Categorical colours for charts, in a fixed order.
  static const chart = [
    Color(0xFF6366F1),
    Color(0xFF22D3EE),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
    Color(0xFF84CC16),
  ];

  static Color chartAt(int i) => chart[i % chart.length];

  static const dark = AppColors(
    background: Color(0xFF0A0C16),
    surface: Color(0xFF121527),
    surfaceAlt: Color(0xFF191D33),
    surfaceHover: Color(0xFF20253F),
    border: Color(0x1FFFFFFF),
    text: Color(0xFFF1F3FB),
    textMuted: Color(0xFFA3A9C2),
    textSubtle: Color(0xFF6B7290),
    glass: Color(0xB3141830),
    glassBorder: Color(0x26FFFFFF),
    glassFill: Color(0xA6121527),
    glassHighlight: Color(0x1FFFFFFF),
    shadow: Color(0x66000000),
  );

  static const light = AppColors(
    background: Color(0xFFF5F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F2F9),
    surfaceHover: Color(0xFFE8EBF6),
    border: Color(0xFFE2E5F0),
    text: Color(0xFF12152A),
    textMuted: Color(0xFF5A6180),
    textSubtle: Color(0xFF8D93AE),
    glass: Color(0xC7FFFFFF),
    glassBorder: Color(0x99FFFFFF),
    glassFill: Color(0xC2FFFFFF),
    glassHighlight: Color(0xE6FFFFFF),
    shadow: Color(0x1A1E2550),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textSubtle: l(textSubtle, other.textSubtle),
      glass: l(glass, other.glass),
      glassBorder: l(glassBorder, other.glassBorder),
      glassFill: l(glassFill, other.glassFill),
      glassHighlight: l(glassHighlight, other.glassHighlight),
      shadow: l(shadow, other.shadow),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const xl = 24.0;
}

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);
  static ThemeData get light => _build(Brightness.light, AppColors.light);

  static TextTheme _text(Color body, Color muted) {
    final base = GoogleFonts.interTextTheme();
    TextStyle? display(TextStyle? s) => GoogleFonts.plusJakartaSans(
      textStyle: s,
    ).copyWith(color: body, fontWeight: FontWeight.w700, letterSpacing: -0.6);
    return base
        .copyWith(
          displayLarge: display(
            base.displayLarge?.copyWith(fontSize: 44, height: 1.1),
          ),
          displayMedium: display(
            base.displayMedium?.copyWith(fontSize: 30, height: 1.15),
          ),
          displaySmall: display(
            base.displaySmall?.copyWith(fontSize: 24, height: 1.2),
          ),
          headlineLarge: display(base.headlineLarge?.copyWith(fontSize: 28)),
          headlineMedium: display(base.headlineMedium?.copyWith(fontSize: 22)),
          headlineSmall: display(base.headlineSmall?.copyWith(fontSize: 19)),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 13.5, height: 1.45),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12, color: muted),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        )
        .apply(bodyColor: body, displayColor: body);
  }

  static ThemeData _build(Brightness brightness, AppColors c) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primary.withValues(alpha: 0.18),
      onPrimaryContainer: isDark ? const Color(0xFFC7C9FF) : AppColors.primary,
      secondary: AppColors.violet,
      onSecondary: Colors.white,
      tertiary: AppColors.cyan,
      onTertiary: Colors.black,
      error: AppColors.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainerHighest: c.surfaceHover,
      outline: c.border,
      outlineVariant: c.border,
      shadow: c.shadow,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    final text = _text(c.text, c.textMuted);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: c.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textMuted, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        foregroundColor: c.text,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: c.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? const Color(0xFFA5A8FF) : AppColors.primary,
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.textMuted, shape: shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceAlt,
        hintStyle: text.bodyMedium?.copyWith(color: c.textSubtle),
        labelStyle: text.bodyMedium?.copyWith(color: c.textMuted),
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceAlt,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        side: BorderSide(color: c.border),
        labelStyle: text.labelMedium?.copyWith(color: c.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.text,
        unselectedLabelColor: c.textMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: c.border),
        ),
        titleTextStyle: text.headlineSmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: c.border),
        ),
        textStyle: text.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceAlt),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: c.border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2F4D) : const Color(0xFF1E2238),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF262B47)
            : const Color(0xFF1E2238),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : c.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : c.surfaceHover,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: c.surfaceHover,
        thumbColor: Colors.white,
        overlayColor: AppColors.primary.withValues(alpha: 0.15),
        trackHeight: 5,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: c.surfaceHover,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textMuted,
        textColor: c.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? AppColors.primary
                : c.textMuted,
          ),
        ),
        height: 68,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(c.textSubtle.withValues(alpha: 0.4)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      extensions: [
        c,
        // Older widgets still read these.
        MacOSThemeColors(sidebarColor: c.surface, separatorColor: c.border),
      ],
    );
  }
}

/// Appearance preferences, persisted across launches: light / dark /
/// system theme, and whether decorative motion (3D tilt, spinning and
/// drifting effects) is reduced.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  static const _motionKey = 'reduced_motion';
  ThemeMode _mode = ThemeMode.dark;
  bool _reducedMotion = false;

  ThemeMode get mode => _mode;
  bool get reducedMotion => _reducedMotion;

  ThemeController() {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      final reduced = prefs.getBool(_motionKey) ?? false;
      if ((mode != null && mode != _mode) || reduced != _reducedMotion) {
        _mode = mode ?? _mode;
        _reducedMotion = reduced;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  Future<void> setReducedMotion(bool value) async {
    if (value == _reducedMotion) return;
    _reducedMotion = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_motionKey, value);
    } catch (_) {}
  }

  /// Flips between light and dark, resolving "system" first.
  void toggle(Brightness current) =>
      setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  /// `MaterialApp.builder`: applies the reduced-motion choice app-wide by
  /// setting the same flag the OS "reduce motion" setting sets.
  Widget applyMotion(BuildContext context, Widget? child) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || _reducedMotion,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}
