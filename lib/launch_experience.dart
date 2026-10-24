import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_typography.dart';
import 'settings.dart';
import 'intertwined_logo.dart';

/// Offline launch artwork, using the studio contours and animation timeline.
class LaunchAnimation extends StatefulWidget {
  const LaunchAnimation({super.key, required this.onFinished});
  final VoidCallback onFinished;
  static const duration = IntertwinedLogoPainter.duration;

  @override
  State<LaunchAnimation> createState() => _LaunchAnimationState();
}

class _LaunchAnimationState extends State<LaunchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(vsync: this, duration: LaunchAnimation.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _finish();
            });
          }
        });
  bool _started = false, _finished = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Launch always follows the phone, even if the in-app preference differs.
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final background = dark ? Colors.black : Colors.white;
    final foreground = dark ? Colors.white : Colors.black;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: background,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
      child: ColoredBox(
        key: const ValueKey('launch.background'),
        color: background,
        child: Center(
          child: Semantics(
            label: 'ElBench البنش',
            image: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const viewBox = IntertwinedLogoPainter.viewBox;
                final width = math.min(
                  constraints.maxWidth * .96,
                  math.min(
                    920.0,
                    constraints.maxHeight * .72 * viewBox.aspectRatio,
                  ),
                );
                return SizedBox(
                  width: width,
                  height: width / viewBox.aspectRatio,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('launch.wordmark'),
                      painter: IntertwinedLogoPainter(
                        progress: _animation,
                        foreground: foreground,
                        background: background,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class IntroductionPage extends StatelessWidget {
  const IntroductionPage({
    super.key,
    required this.settings,
    required this.onLogin,
    required this.onCreateAccount,
  });
  final AppSettings settings;
  final VoidCallback onLogin, onCreateAccount;

  static const _whiteLogo = ColorFilter.matrix(<double>[
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    0,
    0,
    0,
    0,
    255,
    .2126,
    .7152,
    .0722,
    0,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lower = dark ? const Color(0xff080d0a) : const Color(0xfff8fbf7);
    final ink = dark ? const Color(0xfff4f8f1) : const Color(0xff142d23);
    final muted = dark ? const Color(0xff9ca99e) : const Color(0xff586c5f);
    final rtl = settings.language == 'ar';
    final buttonText = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700);
    String t(String en, String ar) => settings.tr(en, ar);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: lower,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        key: const ValueKey('intro.page'),
        backgroundColor: lower,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomCenter,
              stops: const [0, .28, .51, .71],
              colors: [
                const Color(0xff0a634a),
                const Color(0xff17845c),
                const Color(0xff1b714e),
                lower,
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final illustrationHeight = math.max(
                  245.0,
                  constraints.maxHeight - (rtl ? 470 : 450),
                );
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ColorFiltered(
                                  colorFilter: _whiteLogo,
                                  child: Image.asset(
                                    'assets/logo.png',
                                    width: 121,
                                    height: 29,
                                    fit: BoxFit.cover,
                                    alignment: const Alignment(0, -.09),
                                    semanticLabel: 'ElBench',
                                  ),
                                ),
                                Flexible(
                                  child: TextButton.icon(
                                    key: const ValueKey('intro.language'),
                                    onPressed: () =>
                                        settings.setLanguage(rtl ? 'en' : 'ar'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(44, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.language_rounded,
                                      size: 17,
                                    ),
                                    label: Text(
                                      rtl ? 'English' : 'العربية',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 26),
                          child: Text(
                            t('YOUR SPACE.\nYOUR PEOPLE.', 'مساحتك.\nناسك.'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: rtl ? 38 : 36,
                              fontWeight: FontWeight.w900,
                              height: rtl ? 1.2 : 1.03,
                              letterSpacing: rtl ? 0 : -1.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 27),
                          child: Text(
                            t(
                              'Share moments. Start conversations.\nMake every connection count.',
                              'شارك لحظاتك. ابدأ حكايات.\nوخلّي لكل تواصل معنى.',
                            ),
                            style: const TextStyle(
                              color: Color(0xffd1e6d2),
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: illustrationHeight,
                          child: ExcludeSemantics(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _IntroductionArtPainter(
                                  language: settings.language,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 5, 28, 13),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                t('Come on in.', 'مكانك هنا.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  height: 1.15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: rtl ? 0 : -1,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t(
                                  'Your next favorite corner of the internet.',
                                  'ركنك المفضّل الجديد على الإنترنت.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                key: const ValueKey('intro.login'),
                                onPressed: onLogin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: dark
                                      ? const Color(0xfff6faf3)
                                      : ink,
                                  foregroundColor: dark ? lower : Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                  shape: const StadiumBorder(),
                                  textStyle: buttonText,
                                ),
                                child: Text(t('Login', 'تسجيل الدخول')),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                key: const ValueKey('intro.signup'),
                                onPressed: onCreateAccount,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ink,
                                  backgroundColor: ink.withValues(alpha: .035),
                                  side: BorderSide(
                                    color: muted.withValues(alpha: .45),
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                  shape: const StadiumBorder(),
                                  textStyle: buttonText,
                                ),
                                child: Text(t('Create Account', 'إنشاء حساب')),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                t(
                                  'Be real. Be creative. Be connected.',
                                  'خليك على طبيعتك. أبدع. واتواصل.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.5,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Vector illustration matching the reference's tilted social phone/cards.
/// Drawn locally at any screen size, with no network or decode on first launch.
class _IntroductionArtPainter extends CustomPainter {
  const _IntroductionArtPainter({required this.language});
  final String language;
  static const forest = Color(0xff113e30);

  void _round(Canvas canvas, Rect rect, double radius, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void _line(Canvas canvas, Offset a, Offset b, Color color, double width) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _text(
    Canvas canvas,
    String label,
    Offset offset,
    double size,
    Color color, {
    FontWeight weight = FontWeight.w700,
  }) {
    (TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          fontFamily: AppTypography.fontFamily,
          fontFamilyFallback: AppTypography.fontFamilyFallback,
        ),
      ),
      textDirection: language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    )..layout()).paint(canvas, offset);
  }

  void _star(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * .24, center.dy - radius * .22)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx + radius * .23, center.dy + radius * .23)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * .23, center.dy + radius * .23)
      ..lineTo(center.dx - radius, center.dy)
      ..lineTo(center.dx - radius * .23, center.dy - radius * .23)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xffb5dfaa));
  }

  void _tile(
    Canvas canvas,
    Offset center,
    double angle,
    Color color,
    void Function(Canvas canvas) draw,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: 68, height: 68);
    canvas.drawShadow(
      Path()
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20))),
      const Color(0xff103927),
      8,
      false,
    );
    _round(canvas, rect, 20, color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(19)),
      Paint()
        ..color = const Color(0xffedffdb)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    draw(canvas);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.save();
    final scale = math.min(size.width / 390, size.height / 350);
    canvas.translate((size.width - 390 * scale) / 2, 0);
    canvas.scale(scale);
    final ambient = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xff45ba82), Color(0x003fa875)],
      ).createShader(const Rect.fromLTWH(10, -35, 370, 380));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 360), ambient);
    final orbit = Paint()
      ..color = const Color(0xffb6dba3).withValues(alpha: .14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(const Rect.fromLTWH(-100, 25, 350, 290), orbit);
    canvas.drawOval(const Rect.fromLTWH(178, 44, 300, 285), orbit);
    for (var x = 0; x < 6; x++) {
      for (var y = 0; y < 5; y++) {
        canvas.drawCircle(
          Offset(31 + x * 9, 56 + y * 9),
          1.2,
          Paint()..color = const Color(0xffb5dfaa).withValues(alpha: .3),
        );
        canvas.drawCircle(
          Offset(323 + x * 9, 242 + y * 9),
          1.2,
          Paint()..color = const Color(0xffb5dfaa).withValues(alpha: .3),
        );
      }
    }
    _star(canvas, const Offset(88, 57), 14);
    _star(canvas, const Offset(349, 183), 10);
    _line(
      canvas,
      const Offset(316, 18),
      const Offset(373, -5),
      const Color(0x558bd19c),
      2.4,
    );
    _line(
      canvas,
      const Offset(327, 32),
      const Offset(365, 16),
      const Color(0x558bd19c),
      2.4,
    );

    // Floating conversation card behind the phone.
    canvas.save();
    canvas.translate(85, 152);
    canvas.rotate(-.18);
    _round(
      canvas,
      const Rect.fromLTWH(-48, -29, 138, 67),
      16,
      const Color(0xffeff8e7),
    );
    canvas.drawCircle(
      const Offset(-23, -5),
      12,
      Paint()..color = const Color(0xffb2ddb0),
    );
    _line(
      canvas,
      const Offset(-6, -13),
      const Offset(47, -13),
      const Color(0xff547a63),
      6,
    );
    _line(
      canvas,
      const Offset(-6, -1),
      const Offset(30, -1),
      const Color(0xffa0b9a6),
      4,
    );
    _line(
      canvas,
      const Offset(-27, 17),
      const Offset(55, 17),
      const Color(0xffbdcfbd),
      4,
    );
    _line(
      canvas,
      const Offset(-27, 27),
      const Offset(48, 27),
      const Color(0xffd3dec9),
      3.5,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(200, 175);
    canvas.rotate(.17);
    final phone = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-77, -156, 154, 301),
      const Radius.circular(28),
    );
    canvas.drawShadow(
      Path()..addRRect(phone.shift(const Offset(9, 11))),
      const Color(0xff041d13),
      14,
      false,
    );
    canvas.drawRRect(phone, Paint()..color = const Color(0xffd8f3d8));
    canvas.drawRRect(
      phone.deflate(2.5),
      Paint()..color = const Color(0xff102a22),
    );
    final screen = phone.deflate(4);
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRRect(screen, Paint()..color = const Color(0xfff0f7e9));
    canvas.drawRect(
      const Rect.fromLTWH(-80, -156, 160, 71),
      Paint()..color = forest,
    );
    _round(
      canvas,
      const Rect.fromLTWH(-19, -148, 38, 7),
      4,
      const Color(0xff071c15),
    );
    _text(
      canvas,
      language == 'ar' ? 'اكتشف.' : 'explore.',
      const Offset(-59, -133),
      15,
      const Color(0xfff6faed),
    );
    canvas.drawCircle(
      const Offset(54, -117),
      8,
      Paint()..color = const Color(0xff2c7556),
    );
    _line(
      canvas,
      const Offset(50, -117),
      const Offset(58, -117),
      const Color(0xfff6faed),
      1.7,
    );
    _line(
      canvas,
      const Offset(54, -121),
      const Offset(54, -113),
      const Color(0xfff6faed),
      1.7,
    );
    _round(
      canvas,
      const Rect.fromLTWH(-60, -103, 119, 20),
      11,
      const Color(0xff347656),
    );
    canvas.drawCircle(
      const Offset(-48, -94),
      3.7,
      Paint()..color = const Color(0xffb8dbc4),
    );
    _text(
      canvas,
      language == 'ar' ? 'اكتشف حاجة جديدة' : 'Discover something new',
      const Offset(-37, -99),
      6.6,
      const Color(0xffdbedda),
      weight: FontWeight.w400,
    );
    _round(
      canvas,
      const Rect.fromLTWH(-61, -72, 122, 175),
      14,
      const Color(0xfffffff6),
    );
    canvas.drawCircle(
      const Offset(-48, -58),
      6,
      Paint()..color = const Color(0xffa7d899),
    );
    _line(
      canvas,
      const Offset(-36, -61),
      const Offset(3, -61),
      const Color(0xff476252),
      4,
    );
    _line(
      canvas,
      const Offset(-36, -54),
      const Offset(-13, -54),
      const Color(0xffbecdb9),
      3,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-59, -46, 118, 129),
        const Radius.circular(12),
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-59, -46, 118, 129),
      Paint()..color = const Color(0xffb4d29f),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-59, -46, 70, 129),
      Paint()..color = const Color(0xffd8dca0),
    );
    canvas.drawCircle(
      const Offset(26, -16),
      23,
      Paint()..color = const Color(0xffffecac),
    );
    final hills = Path()
      ..moveTo(-65, 39)
      ..cubicTo(-11, -7, 14, 70, 69, 39)
      ..lineTo(69, 91)
      ..lineTo(-65, 91)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xff6ba386));
    final frontHill = Path()
      ..moveTo(-65, 61)
      ..cubicTo(27, 6, 21, 102, 68, 70)
      ..lineTo(68, 91)
      ..lineTo(-65, 91)
      ..close();
    canvas.drawPath(frontHill, Paint()..color = const Color(0xff2c765d));
    _line(
      canvas,
      const Offset(-27, 56),
      const Offset(14, 18),
      const Color(0xffd5edb7),
      1.7,
    );
    for (var petal = 0; petal < 5; petal++) {
      final angle = petal * math.pi * 2 / 5;
      canvas.drawCircle(
        Offset(15 + math.cos(angle) * 10, 24 + math.sin(angle) * 10),
        10,
        Paint()..color = const Color(0xffe7f3c9),
      );
    }
    canvas.drawCircle(
      const Offset(15, 24),
      7,
      Paint()..color = const Color(0xffedbd68),
    );
    canvas.restore();
    final actionStroke = Paint()
      ..color = const Color(0xff2b6049)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    final heart = Path()
      ..moveTo(-47, 98)
      ..cubicTo(-66, 88, -54, 77, -47, 86)
      ..cubicTo(-38, 77, -30, 90, -47, 98);
    canvas.drawPath(heart, actionStroke);
    canvas.drawPath(
      Path()
        ..moveTo(-26, 83)
        ..lineTo(-12, 91)
        ..lineTo(-21, 92)
        ..lineTo(-26, 101)
        ..close(),
      actionStroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(3, 84)
        ..lineTo(17, 84)
        ..lineTo(17, 96)
        ..lineTo(8, 96)
        ..lineTo(3, 101)
        ..close(),
      actionStroke,
    );
    _line(
      canvas,
      const Offset(-52, 111),
      const Offset(26, 111),
      const Color(0xffa6bca2),
      3.7,
    );
    _line(
      canvas,
      const Offset(-52, 120),
      const Offset(6, 120),
      const Color(0xffc5d2ba),
      3.7,
    );
    canvas.drawCircle(
      const Offset(-47, 136),
      6,
      Paint()..color = const Color(0xffb2ccb1),
    );
    _line(
      canvas,
      const Offset(-34, 134),
      const Offset(17, 134),
      const Color(0xffa6bca2),
      3.5,
    );
    canvas.restore();
    canvas.restore();

    _tile(canvas, const Offset(323, 107), .24, const Color(0xffe5f5dc), (
      canvas,
    ) {
      final heart = Path()
        ..moveTo(0, 16)
        ..cubicTo(-34, -3, -18, -33, 0, -15)
        ..cubicTo(22, -34, 32, -4, 0, 16);
      canvas.drawPath(heart, Paint()..color = const Color(0xfffa6577));
    });
    _tile(canvas, const Offset(308, 269), .22, const Color(0xffd8f2a9), (
      canvas,
    ) {
      _round(
        canvas,
        const Rect.fromLTWH(-18, -18, 36, 36),
        10,
        const Color(0xff2b704d),
      );
      canvas.drawPath(
        Path()
          ..moveTo(-4, -10)
          ..lineTo(11, 0)
          ..lineTo(-4, 10)
          ..close(),
        Paint()..color = const Color(0xfff9ffec),
      );
    });
    canvas.save();
    canvas.translate(79, 292);
    canvas.scale(.7);
    _tile(canvas, Offset.zero, -.14, const Color(0xfff6f9e9), (canvas) {
      final p = Paint()
        ..color = const Color(0xff2e7852)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3;
      canvas.drawArc(const Rect.fromLTWH(-11, -9, 22, 18), .5, 2.2, false, p);
      canvas.drawArc(const Rect.fromLTWH(-11, -9, 22, 18), 3.6, 2.2, false, p);
    });
    canvas.restore();
    canvas.restore();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .065, .66, 1],
          colors: [
            Color(0x00ffffff),
            Colors.white,
            Colors.white,
            Color(0x00ffffff),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IntroductionArtPainter oldDelegate) =>
      oldDelegate.language != language;
}
