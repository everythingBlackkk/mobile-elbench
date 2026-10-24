import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Exact geometry from elbench_bilingual_intertwined_lottie_studio.html.
/// The English logo consists of SVG paths, not a substitute font. Preserve
/// the contours (including the B/e holes) and the original drawing order.
abstract final class IntertwinedLogoGeometry {
  static const sourceViewBox = ui.Size(1000, 440);
  static const englishViewBox = ui.Rect.fromLTRB(144, 140, 832, 238);
  static const arabicGreen = ui.Color(0xff169b1e);

  static final List<ui.Path> english = [
    for (final path in [
      _english0,
      _english1,
      _english2,
      _english3,
      _english4,
      _english5,
      _english6,
    ])
      path..fillType = ui.PathFillType.evenOdd,
  ];
  static final List<LogoStroke> englishStrokes = [
    for (final path in english) LogoStroke(path),
  ];

  static final ui.Path _english1 = ui.Path()
    ..moveTo(258, 140)
    ..lineTo(282, 140)
    ..lineTo(282, 238)
    ..lineTo(258, 238)
    ..close();

  static final ui.Path _english3 = ui.Path()
    ..moveTo(424, 168)
    ..lineTo(496, 168)
    ..lineTo(496, 182)
    ..lineTo(508, 182)
    ..lineTo(508, 210)
    ..lineTo(436, 210)
    ..lineTo(436, 224)
    ..lineTo(496, 224)
    ..lineTo(496, 238)
    ..lineTo(424, 238)
    ..lineTo(424, 224)
    ..lineTo(412, 224)
    ..lineTo(412, 182)
    ..lineTo(424, 182)
    ..close()
    ..moveTo(436, 182)
    ..lineTo(436, 196)
    ..lineTo(484, 196)
    ..lineTo(484, 182)
    ..close();

  static final ui.Path _english5 = ui.Path()
    ..moveTo(648, 168)
    ..lineTo(720, 168)
    ..lineTo(720, 182)
    ..lineTo(660, 182)
    ..lineTo(660, 224)
    ..lineTo(720, 224)
    ..lineTo(720, 238)
    ..lineTo(648, 238)
    ..lineTo(648, 224)
    ..lineTo(636, 224)
    ..lineTo(636, 182)
    ..lineTo(648, 182)
    ..close();

  static final ui.Path _arMainStroke = ui.Path()
    ..moveTo(792, 108)
    ..cubicTo(796, 158, 800, 212, 796, 238)
    ..cubicTo(793, 254, 780, 260, 756, 260)
    ..lineTo(724, 260)
    ..cubicTo(704, 260, 694, 242, 688, 198)
    ..cubicTo(682, 242, 670, 258, 646, 258)
    ..lineTo(614, 258)
    ..cubicTo(592, 258, 580, 240, 574, 196)
    ..cubicTo(568, 240, 558, 258, 542, 258)
    ..cubicTo(526, 258, 520, 236, 516, 186)
    ..cubicTo(512, 232, 502, 250, 490, 250)
    ..cubicTo(476, 250, 468, 234, 462, 198)
    ..cubicTo(456, 234, 446, 250, 432, 250)
    ..cubicTo(416, 250, 408, 232, 402, 186)
    ..cubicTo(396, 244, 374, 282, 316, 288)
    ..cubicTo(254, 292, 188, 292, 150, 284)
    ..cubicTo(116, 276, 108, 232, 124, 190);

  static final ui.Path _english0 = ui.Path()
    ..moveTo(144, 140)
    ..lineTo(240, 140)
    ..lineTo(240, 154)
    ..lineTo(168, 154)
    ..lineTo(168, 182)
    ..lineTo(228, 182)
    ..lineTo(228, 196)
    ..lineTo(168, 196)
    ..lineTo(168, 224)
    ..lineTo(240, 224)
    ..lineTo(240, 238)
    ..lineTo(144, 238)
    ..close();

  static final ui.Path _english2 = ui.Path()
    ..moveTo(300, 140)
    ..lineTo(384, 140)
    ..lineTo(384, 154)
    ..lineTo(396, 154)
    ..lineTo(396, 182)
    ..lineTo(384, 182)
    ..lineTo(384, 196)
    ..lineTo(396, 196)
    ..lineTo(396, 224)
    ..lineTo(384, 224)
    ..lineTo(384, 238)
    ..lineTo(300, 238)
    ..close()
    ..moveTo(324, 154)
    ..lineTo(324, 182)
    ..lineTo(372, 182)
    ..lineTo(372, 154)
    ..close()
    ..moveTo(324, 196)
    ..lineTo(324, 224)
    ..lineTo(372, 224)
    ..lineTo(372, 196)
    ..close();

  static final ui.Path _english4 = ui.Path()
    ..moveTo(524, 168)
    ..lineTo(608, 168)
    ..lineTo(608, 182)
    ..lineTo(620, 182)
    ..lineTo(620, 238)
    ..lineTo(596, 238)
    ..lineTo(596, 182)
    ..lineTo(548, 182)
    ..lineTo(548, 238)
    ..lineTo(524, 238)
    ..close();

  static final ui.Path _english6 = ui.Path()
    ..moveTo(736, 140)
    ..lineTo(760, 140)
    ..lineTo(760, 168)
    ..lineTo(820, 168)
    ..lineTo(820, 182)
    ..lineTo(832, 182)
    ..lineTo(832, 238)
    ..lineTo(808, 238)
    ..lineTo(808, 182)
    ..lineTo(760, 182)
    ..lineTo(760, 238)
    ..lineTo(736, 238)
    ..close();

  static final ui.Path _arAlifStroke = ui.Path()
    ..moveTo(854, 108)
    ..cubicTo(857, 156, 858, 212, 855, 262);

  static final ui.Path _arSlashCutout = ui.Path()
    ..moveTo(140, 176)
    ..cubicTo(166, 172, 188, 194, 206, 218)
    ..cubicTo(242, 266, 280, 328, 314, 386);

  static final ui.Path _arSlashStroke = ui.Path()
    ..moveTo(124, 190)
    ..cubicTo(138, 166, 174, 176, 206, 218)
    ..cubicTo(242, 266, 280, 328, 314, 386);

  static final ui.Path _arCaretStroke = ui.Path()
    ..moveTo(508, 144)
    ..cubicTo(494, 156, 476, 156, 462, 136)
    ..cubicTo(446, 146, 430, 150, 414, 142);

  static final main = LogoStroke(_arMainStroke);
  static final alif = LogoStroke(_arAlifStroke);
  static final slash = LogoStroke(_arSlashStroke);
  static final slashCutout = LogoStroke(_arSlashCutout);
  static final caret = LogoStroke(_arCaretStroke);
}

/// Cached native path metrics, measured once rather than on every frame.
class LogoStroke {
  LogoStroke(this.path) : contours = path.computeMetrics().toList() {
    length = contours.fold(0, (sum, contour) => sum + contour.length);
  }

  final ui.Path path;
  final List<ui.PathMetric> contours;
  late final double length;

  /// SVG restarts the dash pattern at *each* subpath. Its single dash length is
  /// the total length of the compound path, so holes trace concurrently with
  /// the outside contour. Sequentially extracting contours changes the logo.
  ui.Path trace(double progress) {
    if (progress >= 1) return path;
    final visible = length * progress.clamp(0.0, 1.0);
    final result = ui.Path();
    for (final contour in contours) {
      if (visible >= contour.length) {
        // Preserve closed joins when a contour has been completely traced.
        final complete = contour.extractPath(0, contour.length);
        if (contour.isClosed) complete.close();
        result.addPath(complete, ui.Offset.zero);
      } else if (visible > 0) {
        result.addPath(contour.extractPath(0, visible), ui.Offset.zero);
      }
    }
    return result;
  }
}

/// Native rendition of the supplied HTML's 2250 ms SVG/JavaScript timeline.
/// The original contours and timing are retained, with the two names spaced
/// vertically so the launch wordmarks remain readable independently.
class IntertwinedLogoPainter extends CustomPainter {
  IntertwinedLogoPainter({
    required this.progress,
    required this.foreground,
    required this.background,
  }) : super(repaint: progress);

  static const duration = Duration(milliseconds: 2250);
  static const viewBox = ui.Size(1000, 520);
  static const englishOffset = ui.Offset(0, -94);
  static const arabicOffset = ui.Offset(0, 80);
  final Animation<double> progress;
  final ui.Color foreground;
  final ui.Color background;

  static double _clamp(double t) => t.clamp(0.0, 1.0);

  static double _easeInOutCubic(double t) {
    t = _clamp(t);
    return t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  static double _easeOutCubic(double t) {
    t = _clamp(t);
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  static double _easeOutBack(double t) {
    t = _clamp(t);
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final elapsed = _clamp(progress.value) * duration.inMilliseconds;
    final scale = math.min(
      size.width / viewBox.width,
      size.height / viewBox.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - viewBox.width * scale) / 2,
      (size.height - viewBox.height * scale) / 2,
    );
    canvas.scale(scale);

    final fill = ui.Paint()..style = ui.PaintingStyle.fill;
    final stroke = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;

    void drawStroke(
      LogoStroke path,
      double p,
      ui.Color color,
      double width, [
      double opacity = 1,
      ui.Offset offset = arabicOffset,
    ]) {
      if (p <= 0 || opacity <= 0) return;
      stroke
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = width;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawPath(path.trace(p), stroke);
      canvas.restore();
    }

    double englishFill(int index) =>
        _easeOutCubic((elapsed - (index * 110 + 260)) / 520);

    void drawEnglish(int index) {
      final shape = IntertwinedLogoGeometry.englishStrokes[index];
      final traceStart = index * 110;
      final trace = _easeInOutCubic((elapsed - traceStart) / 680);
      final opacity = englishFill(index);
      if (opacity > 0) {
        fill.color = foreground.withValues(alpha: opacity);
        canvas.save();
        canvas.translate(englishOffset.dx, englishOffset.dy);
        canvas.drawPath(shape.path, fill);
        canvas.restore();
      }
      final strokeOpacity =
          1 - _clamp((elapsed - (traceStart + 260 + 360)) / 300);
      drawStroke(shape, trace, foreground, 2.2, strokeOpacity, englishOffset);
    }

    // Layer 1: l, e and c pass behind the green body.
    for (final index in const [1, 3, 5]) {
      drawEnglish(index);
    }

    // Layer 2: separator backing and main Arabic body (right to left).
    final mainProgress = _easeInOutCubic((elapsed - 220) / 1300);
    drawStroke(IntertwinedLogoGeometry.main, mainProgress, background, 30);
    drawStroke(
      IntertwinedLogoGeometry.main,
      mainProgress,
      IntertwinedLogoGeometry.arabicGreen,
      23,
    );

    // Layer 3: all separator paths first, then E/B/n/h over the green body.
    // SVG cutouts have the default butt cap, unlike the English outlines.
    stroke.strokeCap = ui.StrokeCap.butt;
    for (final index in const [0, 2, 4, 6]) {
      drawStroke(
        IntertwinedLogoGeometry.englishStrokes[index],
        1,
        background,
        6,
        englishFill(index),
        englishOffset,
      );
    }
    stroke.strokeCap = ui.StrokeCap.round;
    for (final index in const [0, 2, 4, 6]) {
      drawEnglish(index);
    }

    // Layer 4: alif, loop over-weave, caret, and calligraphic dots.
    drawStroke(
      IntertwinedLogoGeometry.alif,
      _easeInOutCubic((elapsed - 80) / 440),
      IntertwinedLogoGeometry.arabicGreen,
      23,
    );
    drawStroke(
      IntertwinedLogoGeometry.slashCutout,
      _easeOutCubic((elapsed - 1530) / 500),
      background,
      21,
    );
    drawStroke(
      IntertwinedLogoGeometry.slash,
      _easeOutCubic((elapsed - 1490) / 540),
      IntertwinedLogoGeometry.arabicGreen,
      15,
    );
    drawStroke(
      IntertwinedLogoGeometry.caret,
      _easeInOutCubic((elapsed - 1140) / 440),
      IntertwinedLogoGeometry.arabicGreen,
      14,
    );

    void dot(
      double start,
      double duration,
      double cx,
      double cy,
      double rx,
      double ry, [
      double rotation = 0,
    ]) {
      final raw = (elapsed - start) / duration;
      if (raw <= 0) return;
      final scale = _easeOutBack(raw);
      fill.color = IntertwinedLogoGeometry.arabicGreen.withValues(
        alpha: _clamp(raw * 2.5),
      );
      canvas.save();
      canvas.translate(cx + arabicOffset.dx, cy + arabicOffset.dy);
      canvas.rotate(rotation * math.pi / 180);
      canvas.scale(scale);
      canvas.drawOval(ui.Rect.fromLTRB(-rx, -ry, rx, ry), fill);
      canvas.restore();
    }

    dot(680, 320, 688, 296, 15, 11.5);
    dot(940, 320, 574, 140, 13.5, 13.5);
    dot(1420, 340, 460, 100, 10.5, 15.5, -28);
    canvas.restore();
  }

  @override
  bool shouldRepaint(IntertwinedLogoPainter oldDelegate) =>
      oldDelegate.foreground != foreground ||
      oldDelegate.background != background ||
      oldDelegate.progress != progress;
}
