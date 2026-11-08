import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's loading spinner: eight rounded spokes in a neutral gray, the
/// brightest stepping around the circle with the others fading behind it,
/// like the system activity indicator. Used by every loader, including
/// pull-to-refresh, so they all look the same.
/// Sized by [size], else by a parent that sets an exact size, else 36.
class AppSpinner extends StatefulWidget {
  const AppSpinner({
    super.key,
    this.size,
    this.strokeWidth,
    this.color,
    this.track = true,
    this.semanticsLabel,
    this.value,
  });

  /// Progress from 0 to 1 (an upload, a pull); null spins.
  final double? value;

  final double? size;
  final double? strokeWidth;

  /// Arc color; defaults to the theme's progress indicator color.
  final Color? color;

  /// Draws a faint full circle behind the arc.
  final bool track;
  final String? semanticsLabel;

  static const defaultSize = 36.0;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns;

  @override
  void initState() {
    super.initState();
    _turns = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.value == null) _turns.repeat();
  }

  @override
  void didUpdateWidget(covariant AppSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_turns.isAnimating) {
      _turns.repeat();
    } else if (widget.value != null && _turns.isAnimating) {
      _turns.stop();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A neutral gray, like the system activity indicator.
    final color =
        widget.color ??
        (theme.brightness == Brightness.dark
            ? const Color(0xff98989d)
            : const Color(0xff8e8e93));
    Widget spinner(double size) {
      final stroke = widget.strokeWidth ?? (size * .09).clamp(1.8, 3.6);
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _SpinnerPainter(
            turns: _turns,
            value: widget.value,
            color: color,
            stroke: stroke,
            track: widget.track,
          ),
        ),
      );
    }

    return Semantics(
      label: widget.semanticsLabel ?? 'Loading',
      liveRegion: true,
      child: RepaintBoundary(
        child: widget.size != null
            ? spinner(widget.size!)
            : LayoutBuilder(
                // Follow a parent that sets an exact size (an 18×18 box in a
                // button); anything looser gets the standard size.
                builder: (context, constraints) {
                  final side = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final exact =
                      constraints.hasTightWidth || constraints.hasTightHeight;
                  return Center(
                    child: spinner(
                      exact && side.isFinite && side > 0
                          ? side
                          : AppSpinner.defaultSize,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.turns,
    required this.value,
    required this.color,
    required this.stroke,
    required this.track,
  }) : super(repaint: turns);

  final Animation<double> turns;
  final double? value;
  final Color color;
  final double stroke;
  final bool track;

  static const spokes = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final inner = radius * .46, outer = radius - stroke / 2;
    final progress = value?.clamp(0.0, 1.0);
    // The bright spoke steps around once per turn, the rest trailing off.
    final head = (turns.value * spokes).floor() % spokes;
    for (var i = 0; i < spokes; i++) {
      final double alpha;
      if (progress != null) {
        // A pull or upload reveals the spokes one by one, clockwise.
        if (i >= (progress * spokes).ceil()) continue;
        alpha = .9;
      } else {
        final behind = (head - i) % spokes;
        alpha = 1 - behind * (.72 / (spokes - 1));
      }
      final angle = -math.pi / 2 + i * 2 * math.pi / spokes;
      final direction = Offset(math.cos(angle), math.sin(angle));
      paint.color = color.withValues(alpha: color.a * alpha);
      canvas.drawLine(
        center + direction * inner,
        center + direction * outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.value != value ||
      old.color != color ||
      old.stroke != stroke ||
      old.track != track;
}
