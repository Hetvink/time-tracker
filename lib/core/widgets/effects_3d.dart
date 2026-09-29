import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';

/// True when the OS asks for reduced motion; every effect here honours it.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Matrix4 _perspective([double depth = 0.0012]) =>
    Matrix4.identity()..setEntry(3, 2, depth);

// -----------------------------------------------------------------------------
// Hover tilt
// -----------------------------------------------------------------------------

/// Tilts its child in 3D toward the pointer and adds a moving glare.
/// On touch it gives a small press-down instead.
class TiltCard extends StatefulWidget {
  final Widget child;
  final double maxTilt;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final bool glare;

  const TiltCard({
    super.key,
    required this.child,
    this.maxTilt = 0.12,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.lg)),
    this.onTap,
    this.glare = true,
  });

  @override
  State<TiltCard> createState() => _TiltCardState();
}

/// Pointer state of a [TiltCard]; tilt is -1..1 on each axis.
@immutable
class _Tilt {
  final Offset tilt;
  final bool hover;
  final bool pressed;
  const _Tilt({
    this.tilt = Offset.zero,
    this.hover = false,
    this.pressed = false,
  });

  _Tilt copyWith({Offset? tilt, bool? hover, bool? pressed}) => _Tilt(
    tilt: tilt ?? this.tilt,
    hover: hover ?? this.hover,
    pressed: pressed ?? this.pressed,
  );
}

class _TiltCardState extends State<TiltCard> {
  // Pointer state lives in a notifier so only the transform rebuilds.
  final _state = ValueNotifier(const _Tilt());

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  void _update(Offset local, Size size) {
    _state.value = _state.value.copyWith(
      tilt: Offset(
        (local.dx / size.width) * 2 - 1,
        (local.dy / size.height) * 2 - 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          onEnter: (_) => _state.value = _state.value.copyWith(hover: true),
          onExit: (_) => _state.value = const _Tilt(),
          onHover: (e) => _update(e.localPosition, constraints.biggest),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) =>
                _state.value = _state.value.copyWith(pressed: true),
            onTapUp: (_) =>
                _state.value = _state.value.copyWith(pressed: false),
            onTapCancel: () =>
                _state.value = _state.value.copyWith(pressed: false),
            child: ValueListenableBuilder<_Tilt>(
              valueListenable: _state,
              child: widget.child,
              builder: (context, s, child) => TweenAnimationBuilder<Offset>(
                tween: Tween(end: s.hover ? s.tilt : Offset.zero),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: child,
                builder: (context, t, child) {
                  final scale = s.pressed ? 0.975 : (s.hover ? 1.012 : 1.0);
                  return Transform(
                    alignment: Alignment.center,
                    transform: _perspective()
                      ..rotateX(-t.dy * widget.maxTilt)
                      ..rotateY(t.dx * widget.maxTilt)
                      ..scaleByDouble(scale, scale, 1, 1),
                    child: Stack(
                      children: [
                        child!,
                        if (widget.glare && s.hover)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipRRect(
                                borderRadius: widget.borderRadius,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment(t.dx, t.dy),
                                      radius: 1.1,
                                      colors: [
                                        Colors.white.withValues(
                                          alpha: context.isDark ? 0.08 : 0.25,
                                        ),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Spinning cube
// -----------------------------------------------------------------------------

/// A real 3D cube (six transformed faces with back-face culling) that
/// slowly rotates. Each face shows one of [icons].
class SpinningCube extends StatefulWidget {
  final double size;
  final List<IconData> icons;
  final Duration period;

  const SpinningCube({
    super.key,
    this.size = 120,
    this.icons = const [
      Icons.timer_rounded,
      Icons.insights_rounded,
      Icons.groups_rounded,
      Icons.calendar_month_rounded,
      Icons.bolt_rounded,
      Icons.shield_rounded,
    ],
    this.period = const Duration(seconds: 14),
  });

  @override
  State<SpinningCube> createState() => _SpinningCubeState();
}

class _SpinningCubeState extends State<SpinningCube>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
      _c.value = 0.12;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Face orientation (outward normal) for front, right, back, left, top, bottom.
  static final _faces = <Matrix4>[
    Matrix4.identity(),
    Matrix4.rotationY(-math.pi / 2),
    Matrix4.rotationY(math.pi),
    Matrix4.rotationY(math.pi / 2),
    Matrix4.rotationX(-math.pi / 2),
    Matrix4.rotationX(math.pi / 2),
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.6,
      height: s * 1.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final a = _c.value * 2 * math.pi;
          final rotation = Matrix4.rotationX(-0.45 + math.sin(a) * 0.25)
            ..multiply(Matrix4.rotationY(a));
          final faces = <Widget>[];
          for (var i = 0; i < _faces.length; i++) {
            final m = rotation.multiplied(_faces[i]);
            // Outward normal is m·(0,0,-1); it faces the viewer when z < 0.
            if (m.entry(2, 2) <= 0.02) continue;
            faces.add(
              Transform(
                alignment: Alignment.center,
                transform: _perspective(0.0016)
                  ..multiply(m)
                  ..translateByDouble(0, 0, -s / 2, 1),
                child: _CubeFace(
                  size: s,
                  icon: widget.icons[i % widget.icons.length],
                  // Faces pointing up-front are lit more.
                  light: m.entry(2, 2),
                  color: AppColors.chartAt(i),
                ),
              ),
            );
          }
          return Center(
            child: SizedBox(
              width: s,
              height: s,
              child: Stack(children: faces),
            ),
          );
        },
      ),
    );
  }
}

class _CubeFace extends StatelessWidget {
  final double size;
  final IconData icon;
  final double light;
  final Color color;

  const _CubeFace({
    required this.size,
    required this.icon,
    required this.light,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final shade = (0.35 + light * 0.65).clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.black, color, shade)!,
            Color.lerp(Colors.black, AppColors.violet, shade * 0.85)!,
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25 * shade),
          width: 1.2,
        ),
      ),
      child: Icon(
        icon,
        size: size * 0.42,
        color: Colors.white.withValues(alpha: 0.35 + shade * 0.6),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Brand mark
// -----------------------------------------------------------------------------

/// The app mark — the same artwork as the app icon (see
/// assets/icon/make_icons.py): a clock disc with a tilted orbit ring on a
/// gradient tile. Static, so it never competes with the content.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _BrandMarkPainter()),
  );
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  static const _hands = Color(0xFF4338CA);
  static const _frontRing = Color(0xFF8B5CF6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final c = rect.center;

    // Tile
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(s * 0.26)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF06B6D4)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );

    final discR = s * 0.25;
    final ring = Rect.fromCenter(
      center: Offset.zero,
      width: s * 0.82,
      height: s * 0.28,
    );
    final ringW = s * 0.042;
    final white = Paint()..color = Colors.white;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringW
      ..color = Colors.white;

    // Whole ring, then the disc hides its back
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-20 * math.pi / 180);
    canvas.drawOval(ring, ringPaint);
    canvas.restore();
    canvas.drawCircle(c, discR, white);

    // Front of the ring across the disc, with a thin gap
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: discR)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-20 * math.pi / 180);
    canvas.clipRect(Rect.fromLTRB(-s, 0, s, s));
    canvas.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW * 1.9
        ..color = Colors.white,
    );
    canvas.drawOval(ring, ringPaint..color = _frontRing);
    canvas.restore();

    // Hands: 12 and 4 o'clock
    final hand = Paint()
      ..color = _hands
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, c + Offset(0, -s * 0.165), hand);
    final a = (120 - 90) * math.pi / 180;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * (s * 0.115),
      hand,
    );
    canvas.drawCircle(c, s * 0.038, Paint()..color = _hands);

    // Satellite
    const t = -35 * math.pi / 180;
    const rot = -20 * math.pi / 180;
    final x = s * 0.41 * math.cos(t), y = s * 0.14 * math.sin(t);
    final sat =
        c +
        Offset(
          x * math.cos(rot) - y * math.sin(rot),
          x * math.sin(rot) + y * math.cos(rot),
        );
    canvas.drawCircle(
      sat,
      s * 0.09,
      Paint()
        ..color = const Color(0xAAA5F3FC)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04),
    );
    canvas.drawCircle(sat, s * 0.05, Paint()..color = const Color(0xFFE0FCFF));
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => false;
}

// -----------------------------------------------------------------------------
// Backgrounds
// -----------------------------------------------------------------------------

/// Slowly drifting colour blobs behind the content. Optional 3D grid floor.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  final bool grid;
  final double intensity;

  /// Drift the colours slowly; false keeps a still backdrop.
  final bool animate;

  const AuroraBackground({
    super.key,
    required this.child,
    this.grid = false,
    this.intensity = 1,
    this.animate = true,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.background),
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuroraPainter(
              _c,
              dark: context.isDark,
              intensity: widget.intensity,
            ),
          ),
        ),
        if (widget.grid)
          RepaintBoundary(
            child: CustomPaint(
              painter: _GridFloorPainter(_c, color: colors.text),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final Animation<double> t;
  final bool dark;
  final double intensity;

  _AuroraPainter(this.t, {required this.dark, required this.intensity})
    : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    final alpha = (dark ? 0.32 : 0.22) * intensity;
    final blobs = [
      (AppColors.primary, 0.2 + 0.1 * math.sin(a), 0.2 + 0.08 * math.cos(a)),
      (
        AppColors.violet,
        0.85 + 0.08 * math.cos(a * 1.3),
        0.3 + 0.1 * math.sin(a),
      ),
      (
        AppColors.cyan,
        0.55 + 0.12 * math.sin(a * 0.7),
        0.9 + 0.06 * math.cos(a),
      ),
    ];
    final r = math.max(size.width, size.height) * 0.55;
    for (final (color, x, y) in blobs) {
      final center = Offset(size.width * x, size.height * y);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.dark != dark || old.intensity != intensity;
}

/// Perspective grid receding to a horizon, scrolling toward the viewer.
class _GridFloorPainter extends CustomPainter {
  final Animation<double> t;
  final Color color;

  _GridFloorPainter(this.t, {required this.color}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.58;
    final vanishing = Offset(size.width / 2, horizon);
    final paint = Paint()..strokeWidth = 1;
    final floor = size.height - horizon;

    // Lines toward the vanishing point
    const rays = 22;
    for (var i = -rays; i <= rays; i++) {
      final x = size.width / 2 + i * size.width / rays * 1.6;
      paint.color = color.withValues(alpha: 0.05);
      canvas.drawLine(vanishing, Offset(x, size.height), paint);
    }

    // Horizontal lines, spaced by depth
    final scroll = (t.value * 12) % 1;
    for (var i = 0; i < 16; i++) {
      final z = (i + scroll) / 16; // 0 far → 1 near
      final y = horizon + floor * z * z;
      paint.color = color.withValues(alpha: 0.02 + 0.07 * z);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Fade the horizon
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 40, size.width, 120),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0),
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, horizon - 40, size.width, 120)),
    );
  }

  @override
  bool shouldRepaint(_GridFloorPainter old) => old.color != color;
}

// -----------------------------------------------------------------------------
// Small motion helpers
// -----------------------------------------------------------------------------

/// Gently bobs its child up and down (for hero illustrations).
class Floating extends StatelessWidget {
  final Widget child;
  final double distance;
  final Duration period;

  const Floating({
    super.key,
    required this.child,
    this.distance = 10,
    this.period = const Duration(seconds: 4),
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return child
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(
          begin: -distance / 2,
          end: distance / 2,
          duration: period,
          curve: Curves.easeInOutSine,
        );
  }
}

/// Pulsing dot for "live" states.
class PulseDot extends StatelessWidget {
  final Color color;
  final double size;

  const PulseDot({super.key, required this.color, this.size = 9});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (reduceMotion(context)) return dot;
    return SizedBox(
      width: size * 2.4,
      height: size * 2.4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(end: 2.4, duration: 1400.ms, curve: Curves.easeOut)
              .fadeOut(duration: 1400.ms),
          dot,
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Flip clock
// -----------------------------------------------------------------------------

/// HH:MM:SS where each digit flips over in 3D when it changes.
class FlipClock extends StatelessWidget {
  final Duration duration;
  final double digitSize;
  final Color color;

  const FlipClock({
    super.key,
    required this.duration,
    this.digitSize = 56,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = [
      two(duration.inHours.clamp(0, 99)),
      two(duration.inMinutes.remainder(60)),
      two(duration.inSeconds.remainder(60)),
    ];
    const labels = ['HOURS', 'MIN', 'SEC'];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var p = 0; p < 3; p++) ...[
            Column(
              children: [
                Row(
                  children: [
                    for (var d = 0; d < 2; d++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _FlipDigit(
                          digit: parts[p][d],
                          size: digitSize,
                          color: color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  labels[p],
                  style: TextStyle(
                    color: color.withValues(alpha: 0.6),
                    fontSize: digitSize * 0.17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
            if (p < 2)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: digitSize * 0.12,
                  vertical: digitSize * 0.28,
                ),
                child: Text(
                  ':',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.5),
                    fontSize: digitSize * 0.8,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FlipDigit extends StatelessWidget {
  final String digit;
  final double size;
  final Color color;

  const _FlipDigit({
    required this.digit,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      key: ValueKey(digit),
      width: size * 0.78,
      height: size * 1.12,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            digit,
            style: TextStyle(
              color: color,
              fontSize: size * 0.82,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // The hinge line across the middle
          Container(height: 1.2, color: Colors.black.withValues(alpha: 0.18)),
        ],
      ),
    );
    if (reduceMotion(context)) return card;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(digit);
        return AnimatedBuilder(
          animation: anim,
          child: child,
          builder: (context, child) {
            // Incoming digit swings down from above; outgoing folds away.
            final angle =
                (1 - anim.value) * (incoming ? -math.pi / 2 : math.pi / 2);
            return Opacity(
              opacity: anim.value.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: _perspective(0.006)..rotateX(angle),
                child: child,
              ),
            );
          },
        );
      },
      child: card,
    );
  }
}
