import 'package:flutter/material.dart';

/// Width classes the whole UI adapts to.
enum ScreenSize { phone, tablet, desktop, wide }

abstract final class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1024.0;
  static const wide = 1440.0;

  static ScreenSize of(double width) {
    if (width >= wide) return ScreenSize.wide;
    if (width >= desktop) return ScreenSize.desktop;
    if (width >= tablet) return ScreenSize.tablet;
    return ScreenSize.phone;
  }
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  ScreenSize get screen => Breakpoints.of(screenWidth);
  bool get isPhone => screen == ScreenSize.phone;
  bool get isTablet => screen == ScreenSize.tablet;
  bool get isDesktopUp =>
      screen == ScreenSize.desktop || screen == ScreenSize.wide;

  /// Picks a value for the current width, falling back to the next smaller
  /// size that was given.
  T responsive<T>({required T phone, T? tablet, T? desktop, T? wide}) =>
      switch (screen) {
        ScreenSize.phone => phone,
        ScreenSize.tablet => tablet ?? phone,
        ScreenSize.desktop => desktop ?? tablet ?? phone,
        ScreenSize.wide => wide ?? desktop ?? tablet ?? phone,
      };

  /// Horizontal page gutter.
  double get gutter => responsive(phone: 16.0, tablet: 24.0, desktop: 32.0);
}

/// Equal-width grid that picks its column count from the available width.
/// Children keep their natural height.
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;

  /// Narrower minimum used on phones (e.g. two KPI tiles per row).
  final double? phoneMinItemWidth;
  final int maxColumns;
  final double spacing;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.phoneMinItemWidth,
    this.maxColumns = 4,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth;
        final n = children.length;
        final minWidth = context.isPhone && phoneMinItemWidth != null
            ? phoneMinItemWidth!
            : minItemWidth;
        var columns = ((max + spacing) / (minWidth + spacing)).floor().clamp(
          1,
          maxColumns.clamp(1, n == 0 ? 1 : n),
        );
        // Prefer balanced rows (4 → 2×2, 6 → 3×2) over a lone last tile.
        if (n % columns != 0) {
          for (var c = columns - 1; c >= 2 && c * 2 >= columns; c--) {
            if (n % c == 0) {
              columns = c;
              break;
            }
          }
        }
        final width = (max - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

/// Two panes side by side on wide screens, stacked on narrow ones.
class SplitPanes extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double breakpoint;
  final double spacing;

  const SplitPanes({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.breakpoint = 900,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: spacing),
              secondary,
            ],
          );
        }
        // No IntrinsicHeight: panes often contain LayoutBuilders (charts).
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: spacing),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

/// Centers content with a max width and responsive gutters.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = 1360});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // Fill the width so toolbars can spread to both edges.
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
