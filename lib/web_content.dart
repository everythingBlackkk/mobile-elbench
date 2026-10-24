import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';

class _ContentColors {
  _ContentColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get main => dark ? const Color(0xff0a0a0a) : Colors.white;
  Color get secondary =>
      dark ? const Color(0xff141414) : const Color(0xfff9fafb);
  Color get text => dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
  Color get muted => dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get border => dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
  Color get accent => dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
  Color get fill => const Color(0xff2e855d);
  Color get danger => dark ? const Color(0xffe7767d) : const Color(0xffc53d46);
}

class WebCampus extends StatefulWidget {
  const WebCampus({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebCampus> createState() => _WebCampusState();
}

class _WebCampusState extends State<WebCampus> {
  static Future<void>? _font;
  PictureInfo? artwork, environment;
  bool? dark;
  Object? error;
  int generation = 0;
  double x = 0, y = 0, scale = .35, minimum = .18;
  Size viewport = Size.zero;
  final pointers = <int, Offset>{};
  Offset dragStart = Offset.zero, doubleTap = Offset.zero;
  double? pinchDistance;
  bool get dragging => pointers.length == 1;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Theme.of(context).brightness == Brightness.dark;
    if (dark != next) {
      dark = next;
      loadArtwork();
    }
  }

  Future<void> loadArtwork() async {
    final current = ++generation;
    try {
      _font ??= () async {
        try {
          final loader = FontLoader('CampusGrotesk')
            ..addFont(rootBundle.load('assets/campus-space-grotesk-700.ttf'));
          await loader.load();
        } catch (_) {
          /* The map remains usable if a cached install lacks its new font. */
        }
      }();
      await _font;
      var source = await rootBundle.loadString('assets/campus.svg');
      // The old native export contains simplified pins, with four outside the
      // map rotation. Keep the authored map and paint the original pins below.
      final pins = source.indexOf('<g id="map-pins-layer">');
      if (pins >= 0) source = '${source.substring(0, pins)}</g></g></svg>';
      source = source.replaceAll(
        RegExp(r'''font-family="[^"]*"'''),
        'font-family="CampusGrotesk"',
      );
      var surroundings = _surroundings;
      final palette = dark == true
          ? [
              '#29251f',
              '#40392e',
              '#302a22',
              '#4d4435',
              '#65664c',
              '#4b4944',
              '#373d43',
              '#b7b6ad',
              '#b59a58',
            ]
          : [
              '#eee5d4',
              '#d5c6ac',
              '#e5d8bf',
              '#cabb9f',
              '#989879',
              '#cfc8ba',
              '#626970',
              '#e9e5da',
              '#e8cb82',
            ];
      const names = [
        'sand',
        'sand-detail',
        'dune',
        'rock',
        'shrub',
        'curb',
        'road',
        'road-mark',
        'road-center',
      ];
      for (var i = 0; i < names.length; i++) {
        surroundings = surroundings.replaceAll(
          'var(--campus-${names[i]})',
          palette[i],
        );
      }
      final pictures = await Future.wait([
        vg.loadPicture(SvgStringLoader(source), null, clipViewbox: false),
        vg.loadPicture(SvgStringLoader(surroundings), null, clipViewbox: false),
      ]);
      if (!mounted || current != generation) {
        for (final picture in pictures) {
          picture.picture.dispose();
        }
        return;
      }
      setState(() {
        artwork?.picture.dispose();
        environment?.picture.dispose();
        artwork = pictures[0];
        environment = pictures[1];
        error = null;
      });
    } catch (e) {
      if (mounted && current == generation) setState(() => error = e);
    }
  }

  @override
  void dispose() {
    generation++;
    artwork?.picture.dispose();
    environment?.picture.dispose();
    super.dispose();
  }

  void resize(Size next) {
    if (next == viewport || next.isEmpty) return;
    final fit = math.min(next.width * .94 / 1360, next.height * .94 / 2840);
    minimum = math.min(.18, fit);
    if (viewport.isEmpty) {
      scale = math.min(2.6, fit);
      x = next.width / 2 - 1100 * scale;
      y = next.height / 2 - 1310 * scale;
    } else {
      final centerX = (viewport.width / 2 - x) / scale;
      final centerY = (viewport.height / 2 - y) / scale;
      x = next.width / 2 - centerX * scale;
      y = next.height / 2 - centerY * scale;
    }
    viewport = next;
    constrain();
  }

  void constrain() {
    final padding = math.min(
      24.0,
      math.min(viewport.width * .025, viewport.height * .025),
    );
    double axis(double position, double start, double end, double size) {
      final first = padding - start * scale;
      final last = size - padding - end * scale;
      return position.clamp(math.min(first, last), math.max(first, last));
    }

    x = axis(x, 420, 1780, viewport.width);
    y = axis(y, -110, 2730, viewport.height);
  }

  void zoom(Offset center, double factor) {
    final next = (scale * factor).clamp(minimum, 2.6);
    x = center.dx - ((center.dx - x) / scale) * next;
    y = center.dy - ((center.dy - y) / scale) * next;
    scale = next;
    constrain();
  }

  void down(PointerDownEvent event) {
    setState(() {
      pointers[event.pointer] = event.localPosition;
      if (pointers.length == 1) {
        dragStart = event.localPosition - Offset(x, y);
      } else if (pointers.length == 2) {
        pinchDistance = (pointers.values.first - pointers.values.last).distance;
      }
    });
  }

  void move(PointerMoveEvent event) {
    if (!pointers.containsKey(event.pointer)) return;
    setState(() {
      pointers[event.pointer] = event.localPosition;
      if (pointers.length == 1) {
        x = event.localPosition.dx - dragStart.dx;
        y = event.localPosition.dy - dragStart.dy;
        constrain();
      } else if (pointers.length == 2) {
        final first = pointers.values.first, last = pointers.values.last;
        final distance = (first - last).distance;
        if (pinchDistance != null && pinchDistance! > 0) {
          zoom((first + last) / 2, distance / pinchDistance!);
        }
        pinchDistance = distance;
      }
    });
  }

  void up(PointerEvent event) {
    setState(() {
      pointers.remove(event.pointer);
      if (pointers.length < 2) pinchDistance = null;
      if (pointers.length == 1) {
        dragStart = pointers.values.first - Offset(x, y);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ContentColors(context);
    return ColoredBox(
      color: colors.dark ? Colors.black : Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          10,
          10,
          10,
          96 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                resize(constraints.biggest);
                if (error != null) {
                  return ErrorPanel(error: error!, retry: loadArtwork);
                }
                if (artwork == null || environment == null) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                return Semantics(
                  label: widget.page.c.t(
                    'Interactive Future Academy campus map',
                    'خريطة أكاديمية المستقبل التفاعلية',
                  ),
                  hint: widget.page.c.t(
                    'Drag to explore · Pinch or scroll to zoom',
                    'اسحب علشان تستكشف · قرّب أو بعّد بإصبعين',
                  ),
                  child: MouseRegion(
                    cursor: dragging
                        ? SystemMouseCursors.grabbing
                        : SystemMouseCursors.grab,
                    child: Listener(
                      onPointerDown: down,
                      onPointerMove: move,
                      onPointerUp: up,
                      onPointerCancel: up,
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          setState(
                            () => zoom(
                              event.localPosition,
                              event.scrollDelta.dy < 0 ? 1.14 : .88,
                            ),
                          );
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: (details) =>
                            doubleTap = details.localPosition,
                        onDoubleTap: () =>
                            setState(() => zoom(doubleTap, 1.35)),
                        child: CustomPaint(
                          painter: _CampusPainter(
                            artwork: artwork!,
                            environment: environment!,
                            x: x,
                            y: y,
                            scale: scale,
                            dark: colors.dark,
                          ),
                          size: constraints.biggest,
                        ),
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

class _CampusPainter extends CustomPainter {
  const _CampusPainter({
    required this.artwork,
    required this.environment,
    required this.x,
    required this.y,
    required this.scale,
    required this.dark,
  });
  final PictureInfo artwork, environment;
  final double x, y, scale;
  final bool dark;
  static const pins = [
    ('#01', Color(0xff9e5b53), Offset(1034, 256)),
    ('#02', Color(0xffd4744a), Offset(1205, 632)),
    ('#03', Color(0xff3d6078), Offset(1125, 962)),
    ('#04', Color(0xff6a994e), Offset(1234, 174)),
    ('#09', Color(0xff7e57c2), Offset(912, 36)),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final sand = dark ? const Color(0xff29251f) : const Color(0xffeee5d4);
    canvas.drawColor(sand, BlendMode.src);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(x, y);
    canvas.scale(scale);
    canvas.save();
    canvas.translate(-14000, -14000);
    canvas.drawPicture(environment.picture);
    canvas.restore();
    // Undo the exported SVG's viewBox origin, leaving the original world units.
    canvas.save();
    canvas.translate(350, -220);
    canvas.drawPicture(artwork.picture);
    canvas.restore();
    const angle = -13.5 * math.pi / 180;
    for (final pin in pins) {
      final offset = pin.$3 - const Offset(1100, 1300);
      final position = Offset(
        1100 + offset.dx * math.cos(angle) - offset.dy * math.sin(angle),
        1300 + offset.dx * math.sin(angle) + offset.dy * math.cos(angle),
      );
      canvas.save();
      canvas.translate(position.dx, position.dy);
      final path = Path()
        ..moveTo(0, 6)
        ..cubicTo(-16, -12, -30, -24, -30, -42)
        ..arcToPoint(
          const Offset(30, -42),
          radius: const Radius.circular(30),
          largeArc: true,
        )
        ..cubicTo(30, -24, 16, -12, 0, 6)
        ..close();
      canvas.drawPath(
        path.shift(const Offset(0, 4)),
        Paint()
          ..color = const Color(0x520f172a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
      canvas.drawPath(path, Paint()..color = Colors.white);
      canvas.drawPath(
        path,
        Paint()
          ..color = pin.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeJoin = StrokeJoin.round,
      );
      final label = TextPainter(
        text: TextSpan(
          text: pin.$1,
          style: const TextStyle(
            fontFamily: 'CampusGrotesk',
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff1e293b),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          -label.width / 2,
          -35 - label.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        ),
      );
      canvas.restore();
    }
    canvas.restore();
    void edge(Rect rect, Alignment begin, Alignment end) => canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: [sand, sand.withValues(alpha: 0)],
        ).createShader(rect),
    );
    edge(
      Rect.fromLTWH(0, 0, 22, size.height),
      Alignment.centerLeft,
      Alignment.centerRight,
    );
    edge(
      Rect.fromLTWH(size.width - 22, 0, 22, size.height),
      Alignment.centerRight,
      Alignment.centerLeft,
    );
    edge(
      Rect.fromLTWH(0, 0, size.width, 22),
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    edge(
      Rect.fromLTWH(0, size.height - 22, size.width, 22),
      Alignment.bottomCenter,
      Alignment.topCenter,
    );
  }

  @override
  bool shouldRepaint(_CampusPainter old) =>
      old.artwork != artwork ||
      old.environment != environment ||
      old.x != x ||
      old.y != y ||
      old.scale != scale ||
      old.dark != dark;
}

// The same authored environment as content/campus-surroundings.blade.php.
const _surroundings =
    '''<svg xmlns="http://www.w3.org/2000/svg" width="30000" height="30000" viewBox="-14000 -14000 30000 30000">
<defs>
<pattern id="campus-sand-grain" width="360" height="320" patternUnits="userSpaceOnUse"><path d="M32 64q28-10 55-3m164 99q26-9 48-3M98 268q25-9 45-3" fill="none" stroke="var(--campus-sand-detail)" stroke-width="2"/><g fill="var(--campus-sand-detail)"><ellipse cx="190" cy="45" rx="3" ry="1.5"/><ellipse cx="55" cy="204" rx="4" ry="2"/><ellipse cx="276" cy="282" rx="2.5" ry="1.5"/></g></pattern>
<g id="campus-desert-rock" fill="var(--campus-rock)" stroke="var(--campus-sand-detail)" stroke-width="2"><path d="m-18 5 7-13 19-3 15 14-6 10-28 2Z"/><path d="m-5-6 6 15 15-5" fill="none"/></g>
<g id="campus-desert-shrub" fill="none" stroke="var(--campus-shrub)" stroke-width="4" stroke-linecap="round"><path d="M0 8V-9M0 5q-4-15-14-17M0 5q6-17 16-20M-5 0q-13-5-19-2M6-2q12-5 20-1"/></g>
<g id="campus-road-arrow" fill="none" stroke="var(--campus-road-mark)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"><path d="M-28 0h56m-12-12L28 0 16 12"/></g>
</defs><g transform="rotate(-13.5, 1100, 1300)">
<rect x="-14000" y="-14000" width="30000" height="30000" fill="var(--campus-sand)"/><rect x="-14000" y="-14000" width="30000" height="30000" fill="url(#campus-sand-grain)"/>
<g fill="var(--campus-dune)"><path d="M-2200-900Q-350-1450 690-480 155-620-200-110T-2200 350Z"/><path d="M1600-700Q3200-250 4000 1550 2700 750 1920 1000 2300 100 1600-700Z"/><path d="M-1800 1300Q-650 900 490 1550-200 1430-750 2100T-1800 2400Z"/><path d="M1800 1870Q2700 1480 3900 2270 2950 2020 2500 2380T1800 2300Z"/></g>
<g opacity=".75"><use href="#campus-desert-rock" x="524" y="368"/><use href="#campus-desert-rock" x="1650" y="770"/><use href="#campus-desert-rock" x="460" y="1650"/><use href="#campus-desert-rock" x="1750" y="2130"/><use href="#campus-desert-shrub" x="582" y="650"/><use href="#campus-desert-shrub" x="1610" y="350"/><use href="#campus-desert-shrub" x="515" y="1200"/><use href="#campus-desert-shrub" x="1720" y="1470"/><use href="#campus-desert-shrub" x="580" y="2100"/><use href="#campus-desert-shrub" x="1550" y="2240"/></g>
<rect x="-14000" y="2424" width="30000" height="242" fill="var(--campus-curb)"/><rect x="-14000" y="2440" width="30000" height="210" fill="var(--campus-road)"/><path d="M-14000 2452H16000M-14000 2638H16000" stroke="var(--campus-road-mark)" stroke-width="3" fill="none"/><path d="M-14000 2542H16000M-14000 2548H16000" stroke="var(--campus-road-center)" stroke-width="2" fill="none"/><path d="M1068 2415h134v25h-134Z" fill="#7c838b"/>
<g stroke="var(--campus-road-mark)" stroke-width="10" opacity=".8"><path d="M1082 2467h106m-106 25h106m-106 25h106m-106 57h106m-106 25h106m-106 25h106"/></g>
<g opacity=".8"><use href="#campus-road-arrow" transform="translate(820 2496) rotate(180)"/><use href="#campus-road-arrow" transform="translate(1470 2496) rotate(180)"/><use href="#campus-road-arrow" transform="translate(820 2595)"/><use href="#campus-road-arrow" transform="translate(1470 2595)"/></g>
</g></svg>''';

class WebTerms extends StatelessWidget {
  const WebTerms({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final colors = _ContentColors(context);
    final terms = object(page.data['terms']);
    final sections = rows(terms['sections']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 40, 10, 40),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Material(
            color: colors.secondary,
            shape: CircleBorder(side: BorderSide(color: colors.border)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.maybePop(context),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: WebIcon('back')),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.only(bottom: 20),
          margin: const EdgeInsets.only(bottom: 40),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value(terms['title'], 'Usage Policy'),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value(
                  terms['subtitle'],
                  'Terms and conditions for using Sahabk platform.',
                ),
                style: TextStyle(
                  fontSize: 17.6,
                  color: colors.muted,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        if (sections.isEmpty)
          SelectableText(
            value(page.data['terms_text']),
            style: TextStyle(fontSize: 16, height: 1.6, color: colors.text),
          ),
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(section['title']),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 15),
                for (final paragraph
                    in (section['paragraphs'] is List
                        ? section['paragraphs'] as List
                        : const []))
                  Text(
                    value(paragraph),
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: colors.text,
                    ),
                  ),
                for (final item
                    in (section['items'] is List
                        ? section['items'] as List
                        : const []))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 5,
                      bottom: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            value(item),
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.6,
                              color: colors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (value(object(section['notice'])['title']).isNotEmpty ||
                    value(object(section['notice'])['body']).isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(top: 20),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value(
                            object(section['notice'])['title'],
                          ).toUpperCase(),
                          style: TextStyle(
                            fontSize: 12.8,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          value(object(section['notice'])['body']),
                          style: TextStyle(
                            fontSize: 15.2,
                            color: colors.text,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Text(
          value(terms['contact'], 'Contact administration at'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.6, color: colors.muted),
        ),
        Center(
          child: InkWell(
            onTap: () => launchUrl(
              Uri(
                scheme: 'mailto',
                path: value(terms['email'], 'team@sahbak.site'),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Text(
                value(terms['email'], 'team@sahbak.site'),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 19.2,
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                  color: colors.text,
                ),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 60),
          padding: const EdgeInsets.only(top: 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Text(
            value(
              terms['footer'],
              '© ${DateTime.now().year} Sahabk. All rights reserved.',
            ).toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.8,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.28,
              height: 1.6,
              color: colors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class WebPasswordReset extends StatefulWidget {
  const WebPasswordReset({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebPasswordReset> createState() => _WebPasswordResetState();
}

class _WebPasswordResetState extends State<WebPasswordReset> {
  final code = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool sending = false, resetting = false, sent = false;
  String? error;
  NativePageState get page => widget.page;
  @override
  void dispose() {
    code.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (sending) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await page.c.action('POST', '/profile/password/reset/code');
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> reset() async {
    if (resetting) return;
    final c = page.c;
    String? invalid;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code.text)) {
      invalid = c.t(
        'Enter the six-digit verification code.',
        'اكتب رمز التحقق المكوّن من ٦ أرقام.',
      );
    }
    if (password.text.length < 6 || password.text.length > 72) {
      invalid ??= c.t(
        'The password must contain between 6 and 72 characters.',
        'كلمة السر لازم تكون من ٦ إلى ٧٢ حرف.',
      );
    }
    if (confirmation.text != password.text) {
      invalid ??= c.t(
        'The password confirmation does not match.',
        'تأكيد كلمة السر مش مطابق.',
      );
    }
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      resetting = true;
      error = null;
    });
    try {
      final result = await c.action('POST', '/profile/password/reset', {
        'code': code.text,
        'password': password.text,
        'password_confirmation': confirmation.text,
      });
      if (page.mounted) {
        await page.load(value(result['redirect_url'], '/profile'));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  Widget field(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool secret = false,
    String? hint,
    bool numeric = false,
  }) {
    final colors = _ContentColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.6,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 47,
          child: AdaptiveTextField(
            controller: controller,
            field: (direction) => TextField(
              controller: controller,
              textDirection: numeric ? TextDirection.ltr : direction,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: !secret,
              autofillHints: numeric
                  ? const [AutofillHints.oneTimeCode]
                  : const [AutofillHints.newPassword],
              keyboardType: numeric
                  ? TextInputType.number
                  : TextInputType.visiblePassword,
              maxLength: numeric ? 6 : 72,
              inputFormatters: numeric
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              style: TextStyle(fontSize: 16, color: colors.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: colors.muted.withValues(alpha: .8)),
                counterText: '',
                filled: true,
                fillColor: colors.main,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget button(
    BuildContext context,
    String label,
    VoidCallback? tap, {
    bool primary = false,
  }) {
    final colors = _ContentColors(context);
    return Material(
      color: primary ? colors.fill : colors.secondary,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            border: primary ? null : Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.56,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: primary ? Colors.white : colors.text,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ContentColors(context), c = page.c;
    final title = c.t('Reset password', 'إعادة تعيين كلمة السر');
    final intro = c.t(
      'We’ll send a six-digit code to your account email. Enter it below with a new password.',
      'هنبعت رمز من ٦ أرقام لبريد حسابك. اكتبه مع كلمة السر الجديدة.',
    );
    final email = value(page.data['email']);
    final codeSent = sent || yes(page.data['reset_code_sent']);
    Widget alert(String text, {bool danger = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: danger
            ? const Color(0x1ac53d46)
            : colors.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: danger ? colors.danger : colors.accent,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 110),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 12, 5, 30),
          child: Text(
            intro,
            style: TextStyle(fontSize: 13.44, color: colors.muted, height: 1.5),
          ),
        ),
        if (error != null) alert(error!, danger: true),
        if (codeSent)
          alert(
            c.t(
              'A reset code was sent to your email.',
              'بعتنا رمز التحقق لبريدك الإلكتروني.',
            ),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
          decoration: BoxDecoration(
            color: colors.secondary,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18.56,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.37,
                  color: colors.text,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                intro,
                style: TextStyle(
                  fontSize: 14.72,
                  color: colors.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 25),
              if (email.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colors.main,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        email,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                        ),
                      ),
                      button(
                        context,
                        sending
                            ? '…'
                            : codeSent
                            ? c.t('Send another code', 'إرسال رمز جديد')
                            : c.t('Send reset code', 'إرسال رمز التحقق'),
                        sending ? null : sendCode,
                      ),
                    ],
                  ),
                ),
                field(
                  context,
                  c.t('Verification code', 'رمز التحقق'),
                  code,
                  numeric: true,
                ),
                const SizedBox(height: 16),
                field(
                  context,
                  c.t('New password', 'كلمة السر الجديدة'),
                  password,
                  secret: true,
                  hint: c.t('At least 6 characters', '٦ أحرف على الأقل'),
                ),
                const SizedBox(height: 16),
                field(
                  context,
                  c.t('Confirm new password', 'تأكيد كلمة السر الجديدة'),
                  confirmation,
                  secret: true,
                ),
                const SizedBox(height: 16),
                button(
                  context,
                  resetting ? '…' : title,
                  resetting ? null : reset,
                  primary: true,
                ),
              ] else
                alert(
                  c.t(
                    'This account has no email address. Change your password from Menu Settings with your current password, or contact support.',
                    'الحساب ده مفيهوش بريد إلكتروني. غيّر كلمة السر من إعدادات القائمة باستخدام كلمة السر الحالية، أو تواصل مع الدعم.',
                  ),
                  danger: true,
                ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InkWell(
                  onTap: () => c.open('/profile/edit'),
                  child: Text(
                    c.t('Back to edit profile', 'العودة لتعديل الملف'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
