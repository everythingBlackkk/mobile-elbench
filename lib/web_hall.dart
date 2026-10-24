import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'api.dart';
import 'image_cache.dart';
import 'screens.dart';

/// Mobile Hall of Fame presentation; ranking data and refresh stay unchanged.
class WebHall extends StatelessWidget {
  const WebHall({super.key, required this.page});
  final NativePageState page;

  @override
  Widget build(BuildContext context) {
    final users = rows(page.data['top_users']);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.black : Colors.white;
    return DecoratedBox(
      key: const ValueKey('hall.background'),
      decoration: BoxDecoration(
        color: background,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xff292313), Color(0xff0b0b0b), Colors.black]
              : const [Color(0xfffbf5e7), Color(0xfffafafa), Colors.white],
          stops: const [0, .42, .8],
        ),
      ),
      child: RefreshIndicator.adaptive(
        onRefresh: page.pullRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 128),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // The mobile top bar already displays the page heading.
            Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Column(
                children: [
                  Text(
                    page.c
                        .t(
                          'Top Contributors & Challenge Masters',
                          'أعلى المساهمين وأبطال التحديات',
                        )
                        .toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CurrentPoints(page: page),
                ],
              ),
            ),
            if (users.isNotEmpty) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  key: const ValueKey('hall.podium'),
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final place in [1, 0, 2])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: place < users.length
                              ? Directionality(
                                  textDirection:
                                      page.c.settings.language == 'ar'
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  child: _Podium(
                                    page: page,
                                    person: users[place],
                                    rank: place + 1,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
              if (users.length > 3) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('hall.participants'),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xff101010)
                        : Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: dark ? .08 : .025,
                        ),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (final (index, person) in users.skip(3).indexed)
                        _RankedMember(
                          page: page,
                          person: person,
                          rank: index + 4,
                        ),
                    ],
                  ),
                ),
              ],
            ] else
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 80,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    _HallGlyph(
                      'award',
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      page.c.t('No users ranked yet', 'مفيش حد في التصنيف لسه'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
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

final _avatarFilenamePattern = RegExp(r'^u[A-Za-z0-9]{14}\.webp$');
final _arabicNamePattern = RegExp(r'^\s*[\u0600-\u06ff]');

String _points(dynamic number) =>
    NumberFormat.decimalPattern('en').format(int.tryParse(value(number)) ?? 0);
String _avatarUrl(NativePageState page, Json person) {
  final supplied = value(person['avatar_url']);
  if (supplied.isNotEmpty) return page.c.api.media(supplied);
  final filename = value(person['avatar'], 'jko.webp');
  return page.c.api.media(
    _avatarFilenamePattern.hasMatch(filename)
        ? '/profile-media/$filename'
        : '/avatars/${filename.isEmpty ? 'jko.webp' : filename}',
  );
}

class _HallAvatar extends StatelessWidget {
  const _HallAvatar({
    required this.page,
    required this.person,
    required this.size,
    required this.border,
    this.borderWidth = 3,
    this.scalloped = false,
  });
  final NativePageState page;
  final Json person;
  final double size, borderWidth;
  final Color border;
  final bool scalloped;

  @override
  Widget build(BuildContext context) {
    final innerSize = size - borderWidth * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (innerSize * dpr).round().clamp(32, 256);
    final photo = networkImage(
      _avatarUrl(page, person),
      width: innerSize,
      height: innerSize,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Text(
            value(person['username'], '?').characters.first,
            style: TextStyle(fontSize: size / 3),
          ),
        ),
      ),
    );
    final body = ColoredBox(
      color: border,
      child: Padding(
        padding: EdgeInsets.all(borderWidth),
        child: scalloped
            ? ClipPath(clipper: const _ScallopedPortrait(), child: photo)
            : ClipOval(child: photo),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: scalloped
          ? ClipPath(clipper: const _ScallopedPortrait(), child: body)
          : ClipOval(child: body),
    );
  }
}

/// A soft, twelve-lobed portrait edge matching the reference's rosette border.
class _ScallopedPortrait extends CustomClipper<Path> {
  const _ScallopedPortrait();

  @override
  Path getClip(Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final path = Path();
    const samples = 240;
    for (var step = 0; step <= samples; step++) {
      final angle = step * 2 * math.pi / samples - math.pi / 2;
      final r = radius * (.957 + .043 * math.cos(12 * angle));
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (step == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(_ScallopedPortrait oldClipper) => false;
}

const _gold = [Color(0xfffbbf24), Color(0xffd97706)];
const _silver = [Color(0xff94a3b8), Color(0xff475569)];
const _bronze = [Color(0xffd97706), Color(0xff92400e)];
LinearGradient _metal(List<Color> colors) => LinearGradient(
  begin: const Alignment(-.574, -.819),
  end: const Alignment(.574, .819),
  colors: colors,
);

class _CurrentPoints extends StatelessWidget {
  const _CurrentPoints({required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xfff3d789) : const Color(0xff87651d);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xffe7c45c).withValues(alpha: dark ? .13 : .15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.string(
            _pointsTrophy,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
          ),
          const SizedBox(width: 6),
          Text(
            _points(page.data['current_user_points']),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              height: 20 / 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            page.c.t('points', 'نقطة'),
            style: TextStyle(color: ink, fontSize: 12, height: 20 / 12),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.page, required this.person, required this.rank});
  final NativePageState page;
  final Json person;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final first = rank == 1;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = rank == 1
        ? _gold
        : rank == 2
        ? _silver
        : _bronze;
    final border = rank == 1
        ? const Color(0xfff4c400)
        : rank == 2
        ? const Color(0xffb8b9b3)
        : const Color(0xffd6bb89);
    return LayoutBuilder(
      builder: (context, constraints) {
        final avatarSize = math.min(constraints.maxWidth, first ? 110.0 : 82.0);
        final avatar = _HallAvatar(
          page: page,
          person: person,
          size: avatarSize,
          border: border,
          borderWidth: first ? 3 : 2.5,
          scalloped: true,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first)
              _WinnerEmblem(size: avatarSize, avatar: avatar)
            else
              avatar,
            SizedBox(height: first ? 20 : 12),
            Text(
              value(person['username']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: first ? 17 : 15,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '@${person['university_id'] ?? ''}',
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                height: 1.25,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HallGlyph(
                  first
                      ? 'trophy'
                      : rank == 2
                      ? 'star'
                      : 'medal',
                  size: 11,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${_points(person['points'])} Pts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: first ? 13 : 12,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: first ? 158 : 144,
              width: double.infinity,
              child: CustomPaint(
                painter: _PodiumColumnPainter(first: first, dark: dark),
                child: Align(
                  alignment: const Alignment(0, -.18),
                  child: _RankMedal(rank: rank, colors: colors),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PodiumColumnPainter extends CustomPainter {
  const _PodiumColumnPainter({required this.first, required this.dark});
  final bool first, dark;

  @override
  void paint(Canvas canvas, Size size) {
    const lip = 17.0;
    final face = Rect.fromLTWH(0, lip, size.width, size.height - lip);
    final transparent = (dark ? Colors.black : Colors.white).withValues(
      alpha: 0,
    );
    final faceTop = first
        ? (dark ? const Color(0xff9c741e) : const Color(0xffffe58a))
        : (dark ? const Color(0xff242321) : Colors.white);
    final topColor = first
        ? (dark ? const Color(0xff59451c) : const Color(0xfffff4c5))
        : (dark ? const Color(0xff181818) : const Color(0xfffdfdfd));
    final top = Path()
      ..moveTo(size.width * .08, 0)
      ..lineTo(size.width * .92, 0)
      ..lineTo(size.width, lip)
      ..lineTo(0, lip)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor.withValues(alpha: 0), faceTop],
        ).createShader(Rect.fromLTWH(0, 0, size.width, lip)),
    );
    canvas.drawRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            faceTop,
            faceTop.withValues(alpha: first ? .42 : .5),
            transparent,
          ],
          stops: const [0, .52, 1],
        ).createShader(face),
    );
    canvas.drawLine(
      const Offset(0, lip),
      Offset(size.width, lip),
      Paint()
        ..color = (first ? const Color(0xfffff7d2) : Colors.white).withValues(
          alpha: dark ? .14 : .8,
        )
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PodiumColumnPainter oldDelegate) =>
      oldDelegate.first != first || oldDelegate.dark != dark;
}

class _RankMedal extends StatelessWidget {
  const _RankMedal({required this.rank, required this.colors});
  final int rank;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final first = rank == 1;
    return SizedBox(
      width: first ? 47 : 36,
      height: first ? 61 : 48,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 0,
            child: _HallGlyph(
              'medal',
              size: first ? 47 : 36,
              color: colors.first.withValues(alpha: .68),
            ),
          ),
          Container(
            width: first ? 40 : 31,
            height: first ? 40 : 31,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _metal(colors),
              border: Border.all(
                color: colors.first.withValues(alpha: .55),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.first.withValues(alpha: .16),
                  blurRadius: 12,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: first ? 23 : 18,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerEmblem extends StatefulWidget {
  const _WinnerEmblem({required this.avatar, required this.size});
  final Widget avatar;
  final double size;
  @override
  State<_WinnerEmblem> createState() => _WinnerEmblemState();
}

class _WinnerEmblemState extends State<_WinnerEmblem>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _animate = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final allowed =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (allowed != _animate) {
      _animate = allowed;
      if (allowed) {
        _animation.repeat();
      } else {
        _animation.stop();
        _animation.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _animation,
      child: widget.avatar,
      builder: (context, avatar) {
        final crownPhase = (_animation.value * 3) % 1;
        final triangle = crownPhase < .5 ? crownPhase * 2 : 2 - crownPhase * 2;
        final float = _animate ? Curves.easeInOut.transform(triangle) : 0.0;
        final sparkle = !_animate || crownPhase < .35 || crownPhase > .8
            ? 0.0
            : crownPhase < .55
            ? Curves.easeInOut.transform((crownPhase - .35) / .2)
            : 1 - Curves.easeInOut.transform((crownPhase - .55) / .25);
        final shinePhase = (_animation.value * 2) % 1;
        final shine = shinePhase <= .65
            ? -1.2
            : shinePhase >= .9
            ? 1.2
            : -1.2 + 2.4 * Curves.easeInOut.transform((shinePhase - .65) / .25);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar!,
              Positioned(
                top: -25,
                left: (widget.size - 34) / 2,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 34,
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Transform.translate(
                          offset: Offset(0, -4 * float),
                          child: Transform.rotate(
                            angle: _animate
                                ? (-3 + 6 * float) * math.pi / 180
                                : 0,
                            origin: const Offset(0, 14),
                            child: const _CrownArt(),
                          ),
                        ),
                        if (_animate)
                          Positioned(
                            top: 3,
                            right: -5,
                            child: Opacity(
                              opacity: sparkle,
                              child: Transform.scale(
                                scale: .5 + .65 * sparkle,
                                child: SvgPicture.string(
                                  _sparkleSvg,
                                  width: 6,
                                  height: 6,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -12,
                left: 0,
                right: 0,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, -3 * float),
                    child: _WinnerTag(animated: _animate, shine: shine),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _CrownArt extends StatelessWidget {
  const _CrownArt();
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: 34,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(0, 2),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: SvgPicture.string(
                  _crownSvg,
                  width: 34,
                  height: 28,
                  colorFilter: const ColorFilter.mode(
                    Color(0x4df59e0b),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
          SvgPicture.string(_crownSvg, width: 34, height: 28),
        ],
      ),
    ),
  );
}

class _WinnerTag extends StatelessWidget {
  const _WinnerTag({required this.animated, required this.shine});
  final bool animated;
  final double shine;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 48, minHeight: 30),
    decoration: BoxDecoration(
      gradient: _metal(_gold),
      border: Border.all(color: Colors.white.withValues(alpha: .35)),
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: const Color(0xff784104).withValues(alpha: .16),
          offset: const Offset(0, 3),
          blurRadius: 8,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.string(_tagTrophy, width: 14, height: 14),
                    const SizedBox(width: 5),
                    const Text(
                      '#1',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (animated)
            Positioned.fill(
              child: IgnorePointer(
                child: FractionalTranslation(
                  translation: Offset(shine, 0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-.94, -.342),
                        end: Alignment(.94, .342),
                        stops: [.25, .5, .75],
                        colors: [
                          Colors.transparent,
                          Color(0x59ffffff),
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
    ),
  );
}

class _RankedMember extends StatelessWidget {
  const _RankedMember({
    required this.page,
    required this.person,
    required this.rank,
  });
  final NativePageState page;
  final Json person;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final current =
        '${person['id']}' ==
        '${page.data['current_user_id'] ?? page.c.user?['id']}';
    final scheme = Theme.of(context).colorScheme;
    final username = value(person['username']);
    final nameDirection = _arabicNamePattern.hasMatch(username)
        ? TextDirection.rtl
        : TextDirection.ltr;
    return RepaintBoundary(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: current
                ? LinearGradient(
                    colors: [
                      const Color(0xffe2b84d).withValues(alpha: .14),
                      const Color(0xffe2b84d).withValues(alpha: .025),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _HallAvatar(
                page: page,
                person: person,
                size: 40,
                border: scheme.outlineVariant.withValues(alpha: .5),
                borderWidth: 1,
                scalloped: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: nameDirection == TextDirection.rtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      textDirection: nameDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${person['university_id'] ?? ''}',
                      textDirection: nameDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_points(person['points'])} pts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfffbbf24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          page.c.t('You', 'أنت'),
                          textDirection: page.c.settings.language == 'ar'
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: const TextStyle(
                            color: Color(0xff211500),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _crownSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 40" fill="none"><defs><linearGradient id="hall-crown-gold" x1="8" y1="5" x2="39" y2="36" gradientUnits="userSpaceOnUse"><stop stop-color="#fef3c7"/><stop offset=".4" stop-color="#fbbf24"/><stop offset="1" stop-color="#d97706"/></linearGradient></defs><path d="m5 13 10 7L24 5l9 15 10-7-5 21H10L5 13Z" fill="url(#hall-crown-gold)" stroke="#fcd34d" stroke-width="1.2" stroke-linejoin="round"/><path d="M11 30h26M12 34h24" stroke="#fff2bf" stroke-opacity=".65" stroke-width="1.5" stroke-linecap="round"/><circle cx="5" cy="12" r="2.5" fill="#fde68a"/><circle cx="24" cy="4" r="2.5" fill="#fde68a"/><circle cx="43" cy="12" r="2.5" fill="#fde68a"/></svg>';
const _sparkleSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 6"><path d="M3 0 3.72 2.28 6 3 3.72 3.72 3 6 2.28 3.72 0 3 2.28 2.28Z" fill="#fde68a"/></svg>';
const _pointsTrophy =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3h8v5a4 4 0 0 1-8 0V3Z"/><path d="M8 5H5v2a4 4 0 0 0 4 4m7-6h3v2a4 4 0 0 1-4 4m-3 1v6m-4 3h8m-6-3h4v3"/></svg>';
const _tagTrophy =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3h8v6a4 4 0 0 1-8 0V3ZM8 5H4v2a4 4 0 0 0 4 4m8-6h4v2a4 4 0 0 1-4 4m-4 2v5m-4 3h8m-6-3h4v3h-4v-3Z"/></svg>';

// Original solid icon outlines extracted from public/fonts/fa-solid-900.ttf.
const _glyphs = <String, String>{
  "trophy":
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 576 512\"><path d=\"M400.000 0.000L176.000 0.000Q156.000 1.000 142.000 14.000Q129.000 28.000 129.000 48.000Q129.000 56.000 130.000 64.000L24.000 64.000Q2.000 66.000 0.000 88.000Q1.000 157.000 22.000 207.000Q44.000 256.000 79.000 289.000Q112.000 321.000 149.000 339.000Q186.000 357.000 217.000 365.000Q234.000 370.000 245.000 382.000Q256.000 395.000 256.000 410.000Q256.000 426.000 245.000 437.000Q234.000 448.000 218.000 448.000L192.000 448.000Q178.000 448.000 169.000 457.000Q160.000 466.000 160.000 480.000Q160.000 494.000 169.000 503.000Q178.000 512.000 192.000 512.000L384.000 512.000Q398.000 512.000 407.000 503.000Q416.000 494.000 416.000 480.000Q416.000 466.000 407.000 457.000Q398.000 448.000 384.000 448.000L358.000 448.000Q342.000 448.000 331.000 437.000Q320.000 426.000 320.000 410.000Q320.000 395.000 331.000 382.000Q342.000 370.000 359.000 365.000Q390.000 357.000 427.000 339.000Q464.000 321.000 498.000 289.000Q532.000 256.000 554.000 207.000Q575.000 157.000 576.000 88.000Q574.000 66.000 552.000 64.000L446.000 64.000Q447.000 56.000 447.000 48.000Q447.000 28.000 434.000 14.000Q420.000 1.000 400.000 0.000ZM49.000 112.000L133.000 112.000Q140.000 179.000 154.000 226.000Q168.000 273.000 185.000 303.000Q147.000 287.000 112.000 254.000Q88.000 231.000 70.000 196.000Q53.000 161.000 49.000 112.000ZM464.000 254.000Q429.000 287.000 391.000 303.000Q408.000 273.000 422.000 226.000Q436.000 179.000 443.000 112.000L527.000 112.000Q523.000 161.000 506.000 196.000Q489.000 231.000 464.000 254.000Z\"/></svg>",
  "award":
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 384.625 511.6111111111111\"><path d=\"M174.125 5.500Q192.125 -5.500 210.125 5.500L228.125 16.500Q237.125 22.500 248.125 22.500L269.125 20.500Q291.125 20.500 301.125 39.500L311.125 58.500Q316.125 67.500 325.125 72.500L345.125 82.500Q363.125 92.500 363.125 114.500L361.125 135.500Q361.125 146.500 367.125 155.500L379.125 173.500Q390.125 191.500 379.125 209.500L367.125 227.500Q361.125 236.500 361.125 247.500L363.125 268.500Q363.125 290.500 344.125 300.500L325.125 310.500Q316.125 315.500 311.125 324.500L301.125 344.500Q291.125 362.500 270.125 362.500L248.125 360.500Q237.125 360.500 228.125 366.500L210.125 378.500Q192.125 389.500 174.125 378.500L156.125 366.500Q147.125 360.500 136.125 360.500L115.125 362.500Q93.125 362.500 83.125 343.500L73.125 324.500Q68.125 315.500 59.125 310.500L40.125 300.500Q21.125 290.500 21.125 269.500L23.125 247.500Q23.125 236.500 17.125 227.500L6.125 209.500Q-4.875 191.500 6.125 173.500L17.125 155.500Q23.125 146.500 23.125 135.500L21.125 114.500Q21.125 92.500 40.125 82.500L59.125 72.500Q68.125 67.500 73.125 58.500L83.125 39.500Q93.125 20.500 115.125 20.500L136.125 22.500Q147.125 22.500 156.125 16.500L174.125 5.500ZM272.125 191.500Q271.125 146.500 232.125 122.500Q192.125 100.500 152.125 122.500Q113.125 146.500 112.125 191.500Q113.125 236.500 152.125 260.500Q192.125 282.500 232.125 260.500Q271.125 236.500 272.125 191.500ZM1.125 441.500L44.125 338.500Q45.125 338.500 45.125 339.500L54.125 358.500Q75.125 394.500 116.125 394.500L138.125 392.500Q138.125 392.500 138.125 393.500L156.125 404.500Q164.125 409.500 172.125 412.500L135.125 501.500Q131.125 510.500 121.125 511.500Q112.125 512.500 107.125 504.500L74.125 455.500L18.125 463.500Q9.125 464.500 3.125 457.500Q-1.875 449.500 1.125 441.500ZM249.125 501.500L212.125 412.500Q220.125 409.500 228.125 404.500L246.125 393.500Q246.125 392.500 246.125 392.500L268.125 394.500Q309.125 394.500 330.125 358.500L339.125 339.500Q339.125 338.500 340.125 338.500L383.125 441.500Q386.125 449.500 381.125 457.500Q375.125 464.500 366.125 463.500L310.125 455.500L277.125 504.500Q272.125 511.500 263.125 511.500Q253.125 510.500 249.125 501.500Z\"/></svg>",
  "medal":
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 512 512\"><path d=\"M4.000 38.000Q0.000 32.000 0.000 25.000Q2.000 2.000 25.000 0.000L134.000 0.000Q152.000 1.000 161.000 16.000L230.000 130.000Q156.000 140.000 106.000 192.000L4.000 38.000ZM508.000 38.000L406.000 192.000Q356.000 140.000 282.000 130.000L351.000 16.000Q360.000 1.000 378.000 0.000L487.000 0.000Q510.000 2.000 512.000 25.000Q512.000 32.000 508.000 38.000ZM80.000 336.000Q80.000 288.000 104.000 248.000L104.000 248.000Q127.000 208.000 168.000 184.000Q210.000 160.000 256.000 160.000Q302.000 160.000 344.000 184.000Q385.000 208.000 408.000 248.000Q432.000 288.000 432.000 336.000Q432.000 384.000 408.000 424.000Q385.000 464.000 344.000 488.000Q302.000 512.000 256.000 512.000Q210.000 512.000 168.000 488.000Q127.000 464.000 104.000 424.000Q80.000 384.000 80.000 336.000ZM264.000 241.000Q256.000 231.000 248.000 241.000L225.000 287.000Q223.000 291.000 218.000 292.000L168.000 299.000Q156.000 304.000 163.000 315.000L199.000 350.000Q202.000 354.000 202.000 359.000L193.000 408.000Q193.000 414.000 197.000 418.000Q201.000 421.000 207.000 418.000L252.000 395.000Q256.000 393.000 260.000 395.000L305.000 418.000Q318.000 422.000 319.000 408.000L310.000 359.000Q309.000 354.000 313.000 350.000L349.000 315.000Q356.000 304.000 344.000 299.000L294.000 292.000Q289.000 291.000 287.000 287.000L264.000 241.000Z\"/></svg>",
  "star":
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 528.1888888888889 512.05\"><path d=\"M292.800 18.000Q283.800 1.000 263.800 -0.000Q244.800 1.000 234.800 18.000L170.800 150.000L26.800 172.000Q7.800 175.000 1.800 193.000Q-4.200 212.000 9.800 226.000L113.800 329.000L88.800 475.000Q86.800 494.000 101.800 506.000Q117.800 517.000 135.800 508.000L263.800 440.000L392.800 508.000Q409.800 517.000 425.800 506.000Q441.800 494.000 438.800 475.000L414.800 329.000L518.800 226.000Q531.800 212.000 526.800 193.000Q519.800 175.000 500.800 172.000L356.800 150.000L292.800 18.000Z\"/></svg>",
};

class _HallGlyph extends StatelessWidget {
  const _HallGlyph(this.name, {required this.size, required this.color});
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _glyphs[name]!,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}
