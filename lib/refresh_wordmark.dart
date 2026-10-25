import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The original wordmark dims with a pull, then refills from left to right.
/// Refresh animation stays inside the asset; the header's geometry never moves.
class ElBenchHeaderLogo extends StatefulWidget {
  const ElBenchHeaderLogo({
    super.key,
    required this.pullProgress,
    required this.refreshing,
  });

  final ValueListenable<double> pullProgress;
  final ValueListenable<bool> refreshing;

  @override
  State<ElBenchHeaderLogo> createState() => _ElBenchHeaderLogoState();
}

class _ElBenchHeaderLogoState extends State<ElBenchHeaderLogo>
    with TickerProviderStateMixin {
  late final _pull = AnimationController(vsync: this);
  late final _activity = AnimationController(vsync: this);
  late final _cycle = AnimationController(vsync: this);
  late final _paint = Listenable.merge([_pull, _activity, _cycle]);
  late final _imageListener = ImageStreamListener(_imageLoaded);
  ImageStream? _imageStream;
  ImageInfo? _logo;
  bool _reduceMotion = false;
  bool _wasRefreshing = false;
  bool _finishing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshing.addListener(_changed);
    widget.pullProgress.addListener(_changed);
  }

  void _imageLoaded(ImageInfo image, bool synchronousCall) {
    _logo?.dispose();
    _logo = image;
    if (!synchronousCall && mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = const AssetImage(
      'assets/logo.png',
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key != _imageStream?.key) {
      _imageStream?.removeListener(_imageListener);
      _imageStream = stream..addListener(_imageListener);
    }
    final media = MediaQuery.of(context);
    _reduceMotion = media.disableAnimations || media.accessibleNavigation;
    _sync();
  }

  @override
  void didUpdateWidget(ElBenchHeaderLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshing != widget.refreshing) {
      oldWidget.refreshing.removeListener(_changed);
      widget.refreshing.addListener(_changed);
    }
    if (oldWidget.pullProgress != widget.pullProgress) {
      oldWidget.pullProgress.removeListener(_changed);
      widget.pullProgress.addListener(_changed);
    }
    _sync();
  }

  void _changed() {
    if (mounted) _sync();
  }

  void _sync() {
    if (_reduceMotion) {
      _generation++;
      _pull.stop();
      _activity.stop();
      _cycle.stop();
      _pull.value = 0;
      _activity.value = 0;
      _wasRefreshing = false;
      _finishing = false;
      return;
    }
    if (widget.refreshing.value) {
      if (!_wasRefreshing) {
        if (!_finishing && _activity.value == 0) _cycle.value = 0;
        _generation++;
        _wasRefreshing = true;
        _finishing = false;
        _pull.stop();
        _activity.animateTo(
          1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
        _cycle.repeat(period: const Duration(milliseconds: 1600));
      }
      return;
    }
    if (_wasRefreshing) {
      _wasRefreshing = false;
      _finish();
      return;
    }
    if (!_finishing) {
      final progress = widget.pullProgress.value.clamp(0.0, 1.0);
      if (progress > 0) {
        _pull.stop();
        _pull.value = progress;
      } else if (_pull.value > 0 && !_pull.isAnimating) {
        _pull.animateBack(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _finish() {
    _finishing = true;
    final generation = ++_generation;
    _cycle.stop();
    final phase = _cycle.value;
    // Even an instant response completes one readable fill. If a long refresh
    // ends during the soft reset, return to the fully inked part of the cycle.
    final target = phase < .65 ? .65 : .82;
    final duration = phase < .65
        ? math.max(240, (1000 * (1 - phase / .65)).round())
        : 180;
    _cycle
        .animateTo(
          target,
          duration: Duration(milliseconds: duration),
          curve: Curves.linear,
        )
        .then((_) {
          if (!mounted || generation != _generation) return;
          _pull.value = 0;
          _activity
              .animateBack(
                0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              )
              .then((_) {
                if (!mounted || generation != _generation) return;
                _finishing = false;
                _sync();
              });
        });
  }

  @override
  void dispose() {
    widget.refreshing.removeListener(_changed);
    widget.pullProgress.removeListener(_changed);
    _imageStream?.removeListener(_imageListener);
    _logo?.dispose();
    _pull.dispose();
    _activity.dispose();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: const ValueKey('header.home.logo'),
      label: 'ElBench',
      header: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: 144,
          height: 40,
          child: CustomPaint(
            // Preserve the existing integration key while using the real logo.
            key: const ValueKey('header.home.cursive'),
            painter: _OriginalWordmarkPainter(
              repaint: _paint,
              image: _logo?.image,
              pull: _pull,
              activity: _activity,
              cycle: _cycle,
              ink: theme.brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _OriginalWordmarkPainter extends CustomPainter {
  _OriginalWordmarkPainter({
    required Listenable repaint,
    required this.image,
    required this.pull,
    required this.activity,
    required this.cycle,
    required this.ink,
  }) : super(repaint: repaint);

  final ui.Image? image;
  final Animation<double> pull, activity, cycle;
  final Color ink;

  static const _lightInvert = ColorFilter.matrix(<double>[
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final logo = image;
    if (logo == null) return;
    // Match ElBenchBrandLogo's fit and optical alignment exactly. The asset's
    // transparency, spacing, block lettering, and aspect ratio stay intact.
    final input = Size(logo.width.toDouble(), logo.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, input, size);
    final source = const Alignment(
      0,
      -.09,
    ).inscribe(fitted.source, Offset.zero & input);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    void drawInk(double opacity) => canvas.drawImageRect(
      logo,
      source,
      destination,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity)
        ..colorFilter = ink == Colors.black ? _lightInvert : null,
    );

    final amount = activity.value;
    final restingInk = 1 - .78 * Curves.easeInOutSine.transform(pull.value);
    if (amount == 0) {
      drawInk(restingInk);
      return;
    }
    final phase = cycle.value;
    final written = Curves.easeInOutCubic.transform(
      (phase / .65).clamp(0.0, 1.0),
    );
    final reset = Curves.easeInOut.transform(
      ((phase - .82) / .18).clamp(0.0, 1.0),
    );
    final filledInk = ui.lerpDouble(restingInk, 1 - .78 * reset, amount)!;
    final waitingInk = ui.lerpDouble(restingInk, .22, amount)!;
    if ((filledInk - waitingInk).abs() < .0001) {
      drawInk(filledInk);
      return;
    }
    final feather = size.width * .075;
    final edge = ui.lerpDouble(-feather, size.width + feather, written)!;
    // A soft alpha mask lets light travel through the original letterforms.
    // Moving the feather outside the bounds keeps both endpoints fully inked
    // or fully dimmed without changing the bitmap's silhouette or color.
    canvas.saveLayer(Offset.zero & size, Paint());
    drawInk(1);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          Offset(edge - feather, 0),
          Offset(edge + feather, 0),
          [
            Colors.white.withValues(alpha: filledInk),
            Colors.white.withValues(alpha: waitingInk),
          ],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OriginalWordmarkPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.ink != ink;
}
