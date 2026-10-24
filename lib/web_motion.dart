import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Motion values from public/JS/navigation.js and public/CSS/ui.css.
class WebVisitMotion {
  const WebVisitMotion({
    this.pixels = 0,
    this.fraction = 0,
    this.opacity = 1,
    this.milliseconds = 0,
    this.menu = false,
  });
  final double pixels, fraction, opacity;
  final int milliseconds;
  final bool menu;
  static const curve = Cubic(.22, 1, .36, 1);
  static WebVisitMotion between(
    String from,
    String to, {
    int tabDirection = 0,
    bool rtl = false,
  }) {
    final a = Uri.parse(from).path, b = Uri.parse(to).path;
    final sign = rtl ? -1.0 : 1.0;
    // Post details open immediately from every entry point (feed, profile,
    // notifications and comment links), including their reverse navigation.
    if (RegExp(r'^/community/posts/\d+/?$').hasMatch(b)) {
      return const WebVisitMotion();
    }
    // The website fixes the dock's physical order in both languages.
    if (tabDirection != 0) {
      return WebVisitMotion(
        fraction: tabDirection.sign.toDouble(),
        milliseconds: 220,
      );
    }
    if (b == '/menu' && a != '/menu' && !a.startsWith('/menu/')) {
      return const WebVisitMotion(fraction: 1, milliseconds: 260, menu: true);
    }
    if (a == '/people' && b.startsWith('/users/')) {
      return WebVisitMotion(pixels: 22 * sign, opacity: .84, milliseconds: 230);
    }
    bool community(String p) => p == '/community' || p == '/forum';
    bool thread(String p) =>
        p.startsWith('/community/posts/') || p == '/question';
    if (community(a) && (community(b) || thread(b)) ||
        thread(a) && community(b)) {
      return WebVisitMotion(pixels: 20 * sign, milliseconds: 190);
    }
    bool activity(String p) =>
        p == '/profile' ||
        p.startsWith('/users/') ||
        p == '/inbox' ||
        p == '/notifications';
    bool detail(String p) =>
        p.startsWith('/ask/') || thread(p) || p.startsWith('/notifications/');
    if (activity(a) && detail(b) || detail(a) && activity(b)) {
      return WebVisitMotion(
        pixels: a == '/notifications' ? -64 : 64 * sign,
        milliseconds: 260,
      );
    }
    return const WebVisitMotion();
  }
}

class WebPageRoute<T> extends PageRouteBuilder<T> {
  WebPageRoute({
    required WidgetBuilder builder,
    required this.motion,
    required this.path,
  }) : _entranceComplete = motion.fraction == 0,
       super(
         settings: RouteSettings(name: path),
         pageBuilder: (context, _, _) => builder(context),
         transitionsBuilder: (_, _, _, child) => child,
         transitionDuration: Duration(milliseconds: motion.milliseconds),
         reverseTransitionDuration: Duration(milliseconds: motion.milliseconds),
       );
  final WebVisitMotion motion;
  final String path;
  bool _entranceComplete;
  bool _finishScheduled = false;
  bool get hasPreviousBody => motion.fraction != 0;
  @override
  bool get opaque => _entranceComplete;
  final progress = ValueNotifier<double>(0);
  void completeEntrance() {
    if (_entranceComplete || _finishScheduled) return;
    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator == null) return;
      _entranceComplete = true;
      // Keep exactly the previous route visible while its live body is used.
      // Once the slide finishes, Navigator can stop painting it altogether.
      if (animation?.status == AnimationStatus.completed &&
          overlayEntries.isNotEmpty) {
        overlayEntries.first.opaque = true;
      }
      changedInternalState();
    });
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }
}

/// Reuses the outgoing body's retained render layer instead of rasterizing a
/// screen-sized image on every tap. Header and dock are outside this transform.
class WebPageDeparture extends StatelessWidget {
  const WebPageDeparture({super.key, required this.visit, required this.child});
  static final _idleProgress = ValueNotifier<double>(0);
  final WebPageRoute<dynamic>? visit;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final route = visit;
    final moving =
        route != null &&
        !route.motion.menu &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.of(context).accessibleNavigation;
    final width = moving ? MediaQuery.sizeOf(context).width : 0.0;
    final fraction = route?.motion.fraction ?? 0;
    return ValueListenableBuilder<double>(
      valueListenable: route?.progress ?? _idleProgress,
      child: child,
      builder: (_, progress, child) => Transform.translate(
        offset: Offset(moving ? -fraction * width * .3 * progress : 0, 0),
        child: Opacity(opacity: moving ? 1 - .5 * progress : 1, child: child),
      ),
    );
  }
}

/// Moves the menu's own header while keeping the floating dock stationary.
class WebMenuHeaderMotion extends StatelessWidget {
  const WebMenuHeaderMotion({
    super.key,
    required this.route,
    required this.child,
  });
  final WebPageRoute<dynamic> route;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation ||
        !route.motion.menu) {
      return child;
    }
    return ValueListenableBuilder<double>(
      valueListenable: route.progress,
      child: child,
      builder: (context, progress, child) => Transform.translate(
        offset: Offset(MediaQuery.sizeOf(context).width * (1 - progress), 0),
        child: child,
      ),
    );
  }
}

class WebPageEntrance extends StatefulWidget {
  const WebPageEntrance({
    super.key,
    required this.motion,
    required this.ready,
    required this.child,
  });
  final WebVisitMotion motion;
  final bool ready;
  final Widget child;
  @override
  State<WebPageEntrance> createState() => _WebPageEntranceState();
}

class _WebPageEntranceState extends State<WebPageEntrance>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.motion.milliseconds),
  );
  WebPageRoute<dynamic>? route;
  Animation<double>? routeAnimation;
  bool played = false, reduceMotion = false, _updateScheduled = false;
  bool _startScheduled = false;
  double? _lastProgress;
  @override
  void initState() {
    super.initState();
    animation.addListener(_update);
    animation.addStatusListener(_completed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    final modal = ModalRoute.of(context);
    if (modal is WebPageRoute && modal != route) {
      routeAnimation?.removeListener(_update);
      route = modal;
      routeAnimation = modal.animation;
      routeAnimation?.addListener(_update);
    }
    _start();
  }

  @override
  void didUpdateWidget(WebPageEntrance old) {
    super.didUpdateWidget(old);
    _start();
  }

  double get _progress {
    if (reduceMotion || widget.motion.milliseconds == 0) return 1;
    final value = routeAnimation?.status == AnimationStatus.reverse
        ? routeAnimation!.value
        : animation.value;
    return WebVisitMotion.curve.transform(value.clamp(0.0, 1.0));
  }

  void _start() {
    if (played || !widget.ready || _startScheduled) return;
    if (!reduceMotion &&
        widget.motion.milliseconds > 0 &&
        route?.hasPreviousBody == true) {
      // Lay out the ready page before its entrance clock starts. On a cold
      // visit, creating SVGs and laying out rows in the first moving frame
      // otherwise produces a visible hitch. The previous route stays painted
      // while this retained subtree is offstage for one layout frame.
      _startScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startScheduled = false;
        if (!mounted || played || !widget.ready) return;
        setState(_play);
      });
      return;
    }
    _play();
  }

  void _play() {
    played = true;
    if (reduceMotion || widget.motion.milliseconds == 0) {
      animation.value = 1;
      route?.completeEntrance();
    } else {
      animation.forward();
    }
  }

  void _update() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_updateScheduled) {
        _updateScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateScheduled = false;
          if (mounted) _update();
        });
      }
      return;
    }
    if (routeAnimation?.status == AnimationStatus.reverse &&
        animation.isAnimating) {
      animation.stop();
    }
    final progress = _progress;
    // Navigator's clock and the body entrance clock can tick in the same frame.
    // Only one of them changes the visible position, so don't rebuild twice.
    if (_lastProgress == progress) return;
    _lastProgress = progress;
    // Header and body share the same entrance clock, including delayed network
    // responses. Pop motion uses Navigator's reverse clock instead of replaying.
    if (route != null && route!.progress.value != progress) {
      route!.progress.value = progress;
    }
    setState(() {});
  }

  void _completed(AnimationStatus status) {
    if (status == AnimationStatus.completed) route?.completeEntrance();
  }

  @override
  void dispose() {
    routeAnimation?.removeListener(_update);
    animation.removeListener(_update);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final hasPrevious = route?.hasPreviousBody == true && !reduceMotion;
    final width = MediaQuery.sizeOf(context).width;
    final offset = widget.motion.pixels + width * widget.motion.fraction;
    final moving = !reduceMotion && widget.motion.milliseconds > 0;
    final incoming = ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: widget.child,
    );
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: hasPrevious && !played,
            child: TickerMode(
              enabled: !hasPrevious || played,
              child: Transform.translate(
                key: const ValueKey('navigation.incomingBody'),
                offset: Offset(moving ? offset * (1 - progress) : 0, 0),
                child: Opacity(
                  opacity: moving
                      ? widget.motion.opacity +
                            (1 - widget.motion.opacity) * progress
                      : 1,
                  child: incoming,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
