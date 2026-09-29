import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import 'effects_3d.dart';
import 'responsive.dart';

export '../state/keep_alive.dart';
export '../state/submit_controller.dart';
export '../state/ticking.dart';
export 'effects_3d.dart';
export 'responsive.dart';
export '../../theme/app_theme.dart';

/// Shared building blocks for every screen, so pages follow the app theme
/// on every platform and width.

// =============================================================================
// Formatting
// =============================================================================

/// Width below which forms and dialogs switch to single-column layouts.
const double kCompactWidth = 720;

bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kCompactWidth;

String formatHm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String formatSeconds(int seconds) => formatHm(Duration(seconds: seconds));

/// Hours with one decimal, e.g. "7.5h" — compact for charts.
String formatHoursShort(Duration d) {
  final h = d.inMinutes / 60;
  return h >= 10 ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

/// Live clock style "02:14:09".
String formatClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

String formatTime(DateTime? t) =>
    t == null ? '—' : DateFormat('HH:mm').format(t.toLocal());

String formatRelative(DateTime? time) {
  if (time == null) return 'Never';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM yyyy').format(time);
}

String formatDate(DateTime? time) =>
    time == null ? '—' : DateFormat('d MMM yyyy').format(time);

String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return 'Working late';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

// =============================================================================
// Feedback
// =============================================================================

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? AppColors.danger : AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        width: isCompact(context) ? null : 480,
      ),
    );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
        color: destructive ? AppColors.danger : AppColors.primary,
        size: 32,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, textAlign: TextAlign.center),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// =============================================================================
// Surfaces
// =============================================================================

/// Rounded glass panel used for cards and list groups: a translucent fill
/// over the app backdrop, a hairline border and a soft light sheen on top.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Container(
      // Sheen: the top edge catches light, as on iOS glass.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35],
          colors: [
            colors.glassHighlight.withValues(
              alpha: colors.glassHighlight.a * (context.isDark ? 0.6 : 0.35),
            ),
            colors.glassHighlight.withValues(alpha: 0),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient == null ? (color ?? colors.glassFill) : null,
            gradient: gradient,
            borderRadius: radius,
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -14,
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Frosted bar (sidebar, top bar, bottom navigation): blurs whatever is
/// behind it, like iOS toolbars.
class GlassBar extends StatelessWidget {
  final Widget child;
  final Border? border;
  final BorderRadius? borderRadius;

  const GlassBar({
    super.key,
    required this.child,
    this.border,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = borderRadius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: radius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted-glass panel for use over [AuroraBackground].
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = AppRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Card with a title row, optional trailing actions and a body.
class AppCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? bodyPadding;

  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.bodyPadding,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || actions.isNotEmpty;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: SectionHeader(
                title: title ?? '',
                subtitle: subtitle,
                icon: icon,
                actions: actions,
              ),
            ),
          Padding(
            padding:
                bodyPadding ??
                (hasHeader
                    ? const EdgeInsets.fromLTRB(20, 14, 20, 20)
                    : padding),
            child: child,
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: context.text.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

// =============================================================================
// Page scaffolding
// =============================================================================

/// Page title row; actions wrap below the title on narrow screens.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: context.text.labelSmall?.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          title,
          style: context.responsive(
            phone: context.text.headlineLarge,
            desktop: context.text.displayMedium,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return titleBlock;
    if (isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    );
  }
}

/// Standard scrolling page: header, then [children] in a max-width column
/// with responsive gutters and pull-to-refresh.
class AppPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final double spacing;
  final bool animate;

  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const [],
    required this.children,
    this.onRefresh,
    this.maxWidth = 1360,
    this.spacing = 20,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    final items = <Widget>[
      PageHeader(
        title: title,
        subtitle: subtitle,
        eyebrow: eyebrow,
        actions: actions,
      ),
      ...children,
    ];

    Widget list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, gutter + 24),
      itemCount: items.length,
      separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 24 : spacing),
      itemBuilder: (context, i) {
        final child = ContentWidth(maxWidth: maxWidth, child: items[i]);
        return animate ? child : child;
      },
    );
    if (onRefresh != null) {
      list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    }
    return Scaffold(backgroundColor: Colors.transparent, body: list);
  }
}

/// Centered, width-limited scroll area used by form-like pages.
class CenteredScroll extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const CenteredScroll({super.key, required this.child, this.maxWidth = 640});

  @override
  Widget build(BuildContext context) {
    final pad = context.gutter;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

// =============================================================================
// Badges, avatars
// =============================================================================

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Bounded so the label can ellipsize even inside an unbounded Row.
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final Color? statusColor;

  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 18,
    this.statusColor,
  });

  static Color colorFor(String name) =>
      AppColors.chartAt(name.codeUnits.fold(0, (a, b) => a + b));

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final tint = colorFor(name);

    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [tint, Color.lerp(tint, AppColors.violet, 0.6)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                onError: (_, _) {},
              )
            : null,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.72,
              ),
            ),
    );
    if (statusColor == null) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.62,
            height: radius * 0.62,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.1)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

// =============================================================================
// Stats
// =============================================================================

/// Headline number with icon, optional delta and sparkline. Tilts in 3D.
class KpiCard extends StatelessWidget {
  final String label;
  final String? value;
  final double? numeric;
  final String Function(double)? format;
  final IconData icon;
  final Color color;
  final String? caption;
  final double? delta; // fraction, e.g. 0.12 = +12 %
  final List<double>? spark;
  final VoidCallback? onTap;
  final bool loading;

  const KpiCard({
    super.key,
    required this.label,
    this.value,
    this.numeric,
    this.format,
    required this.icon,
    required this.color,
    this.caption,
    this.delta,
    this.spark,
    this.onTap,
    this.loading = false,
  }) : assert(value != null || (numeric != null && format != null));

  /// Convenience for durations.
  factory KpiCard.duration({
    Key? key,
    required String label,
    required Duration duration,
    required IconData icon,
    required Color color,
    String? caption,
    double? delta,
    List<double>? spark,
    VoidCallback? onTap,
    bool loading = false,
  }) => KpiCard(
    key: key,
    label: label,
    numeric: duration.inSeconds.toDouble(),
    format: (v) => formatSeconds(v.round()),
    icon: icon,
    color: color,
    caption: caption,
    delta: delta,
    spark: spark,
    onTap: onTap,
    loading: loading,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueStyle = context.text.headlineLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TiltCard(
      onTap: onTap,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Soft corner glow in the card colour, clipped to the card shape
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Stack(
                  children: [
                    Positioned(
                      right: -40,
                      top: -40,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.isPhone ? 14 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(
                        icon: icon,
                        color: color,
                        size: context.isPhone ? 34 : 38,
                      ),
                      const Spacer(),
                      if (delta != null) _DeltaChip(delta: delta!),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (loading)
                    const Skeleton(width: 110, height: 30)
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        numeric != null ? format!(numeric!) : value!,
                        style: valueStyle,
                        maxLines: 1,
                      ),
                    ),
                  // Always reserve the caption line so cards in a row match.
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            caption ?? '',
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (spark != null && spark!.length > 1)
                          SizedBox(
                            width: 72,
                            height: 24,
                            child: CustomPaint(
                              painter: _SparkPainter(spark!, color),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double delta;
  const _DeltaChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final color = up ? AppColors.success : AppColors.danger;
    return StatusPill(
      label: '${up ? '+' : ''}${(delta * 100).round()}%',
      color: color,
      icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - minV) / range * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

/// Kept for older call sites; a compact [KpiCard].
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) =>
      KpiCard(label: label, value: value, icon: icon, color: color);
}

/// Lays out [children] in a responsive grid of equal-width tiles.
class ResponsiveTiles extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;

  const ResponsiveTiles({
    super.key,
    required this.children,
    this.minTileWidth = 200,
  });

  @override
  Widget build(BuildContext context) => AdaptiveGrid(
    minItemWidth: minTileWidth,
    phoneMinItemWidth: 150,
    spacing: 14,
    children: children,
  );
}

/// Circular progress with a gradient stroke and centered label.
class ProgressRing extends StatelessWidget {
  final double progress; // 0..1 (may exceed 1)
  final double size;
  final double stroke;
  final Widget? center;
  final List<Color> colors;

  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 120,
    this.stroke = 12,
    this.center,
    this.colors = const [AppColors.primary, AppColors.violet, AppColors.cyan],
  });

  @override
  Widget build(BuildContext context) {
    final track = context.colors.surfaceHover;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0, 1).toDouble()),
        duration: reduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(v, stroke, track, colors),
          child: Center(child: child),
        ),
        child: center,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final Color track;
  final List<Color> colors;
  _RingPainter(this.v, this.stroke, this.track, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.track != track;
}

/// Label / value pair used in detail panels.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: colors.textSubtle),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal bar showing a share of a total (app usage lists etc.).
class ShareBar extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction;
  final Color color;
  final String? sublabel;

  const ShareBar({
    super.key,
    required this.label,
    required this.trailing,
    required this.fraction,
    required this.color,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                trailing,
                style: context.text.bodyMedium?.copyWith(
                  color: colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (sublabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                sublabel!,
                style: context.text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction.clamp(0, 1).toDouble()),
              duration: reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: color,
                backgroundColor: colors.surfaceHover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Controls
// =============================================================================

/// Pill-style segmented control that scrolls horizontally on small screens.
class SegmentedTabs<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;

  const SegmentedTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buttons = [
      for (final (v, label) in items)
        _Segment(
          label: label,
          selected: v == value,
          onTap: () => onChanged(v),
          expand: expand,
        ),
    ];
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: buttons,
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: expand
          ? row
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.expand,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected ? AppColors.brandGradient : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelMedium?.copyWith(
          color: selected ? Colors.white : colors.textMuted,
        ),
      ),
    );
    final tappable = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: child,
    );
    return expand ? Expanded(child: tappable) : tappable;
  }
}

/// "‹  September 2026  ›" style stepper with an optional picker on tap.
class PeriodStepper extends StatelessWidget {
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTapLabel;
  final VoidCallback? onToday;

  const PeriodStepper({
    super.key,
    required this.label,
    this.onPrevious,
    this.onNext,
    this.onTapLabel,
    this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous',
            visualDensity: VisualDensity.compact,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Flexible(
            child: InkWell(
              onTap: onTapLabel,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onTapLabel != null) ...[
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: context.text.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next',
            visualDensity: VisualDensity.compact,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (onToday != null) ...[
            Container(width: 1, height: 22, color: colors.border),
            if (context.isPhone)
              IconButton(
                tooltip: 'Today',
                visualDensity: VisualDensity.compact,
                onPressed: onToday,
                icon: const Icon(Icons.today_rounded, size: 20),
              )
            else
              TextButton(onPressed: onToday, child: const Text('Today')),
          ],
        ],
      ),
    );
  }
}

/// Search box sized for toolbars.
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.width = 300,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isCompact(context) ? double.infinity : width,
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Primary call-to-action with the brand gradient and a glow.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    // Bounded so the label can ellipsize even inside an unbounded Row.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: expand ? double.infinity : 420),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.6,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: 18, color: Colors.white),
                    if (loading || icon != null) const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Loading / empty / error
// =============================================================================

/// Shimmering placeholder block.
class Skeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceHover,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (reduceMotion(context)) return box;
    return box
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1400.ms,
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.7),
        );
  }
}

/// Placeholder for a whole dashboard section while it loads.
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 220});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: SizedBox(
        height: height - 40,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(width: 140, height: 18),
            SizedBox(height: 12),
            Skeleton(width: 220, height: 12),
            SizedBox(height: 20),
            Expanded(child: Skeleton(radius: AppRadius.md)),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color color;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Inside short cards use a compact layout; if even that is too tall,
        // scale down rather than overflow.
        final bounded = constraints.maxHeight.isFinite;
        final compact = bounded && constraints.maxHeight < 280;
        final width = math.min(440.0, constraints.maxWidth);
        final content = Padding(
          padding: EdgeInsets.all(compact ? 12 : 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(0, width - (compact ? 24 : 64)),
            ),
            child: _content(context, compact),
          ),
        );
        return Center(
          child: bounded
              ? FittedBox(fit: BoxFit.scaleDown, child: content)
              : content,
        );
      },
    );
  }

  Widget _content(BuildContext context, bool compact) {
    final colors = context.colors;
    final badge = compact ? 44.0 : 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: badge,
          height: badge,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: badge * 0.46, color: color),
        ),
        SizedBox(height: compact ? 10 : 18),
        Text(
          title,
          style: compact ? context.text.titleSmall : context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(
            message!,
            style: (compact ? context.text.bodySmall : context.text.bodyMedium)
                ?.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[SizedBox(height: compact ? 12 : 20), action!],
      ],
    );
  }
}

class ErrorState extends StatelessWidget {
  final String title;
  final Object? error;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    var message = error?.toString();
    if (message != null && message.startsWith('Exception: ')) {
      message = message.substring(11);
    }
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      color: AppColors.danger,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
    );
  }
}

/// FutureBuilder with the app's loading and error states built in.
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final VoidCallback? onRetry;

  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.loading,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState(error: snap.error, onRetry: onRetry);
        }
        if (!snap.hasData) {
          return loading ?? const Center(child: CircularProgressIndicator());
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
            key: ValueKey(snap.data.hashCode),
            child: builder(context, snap.data as T),
          ),
        );
      },
    );
  }
}
