import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'api.dart';
import 'screens.dart';
import 'web_home.dart';
import 'web_style.dart';

Future<void> showWebEvent(
  BuildContext context,
  NativePageState p,
  Json event,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: p.c.t('Close modal', 'إغلاق'),
  barrierColor: Colors.black.withValues(alpha: .4),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 500),
  pageBuilder: (ctx, _, _) {
    final date = DateTime.tryParse(value(event['event_date']));
    Widget fact(String icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebIcon(icon, size: 16, color: webMuted(ctx)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: webMuted(ctx),
            ),
          ),
        ),
      ],
    );
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: SafeArea(
        child: Center(
          child: Material(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
              side: BorderSide(color: webBorder(ctx)),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 12,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(
                  500,
                  (MediaQuery.sizeOf(ctx).width - 40) * .92,
                ),
                maxHeight:
                    MediaQuery.sizeOf(ctx).height -
                    MediaQuery.paddingOf(ctx).vertical -
                    40,
              ),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Stagger(
                          delay: 100,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.c.t('Event Details', 'تفاصيل الايفنت'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xff3b82f6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  value(event['title']),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    fact(
                                      'calendar',
                                      date == null
                                          ? ''
                                          : DateFormat(
                                              'MMM dd, yyyy',
                                            ).format(date),
                                    ),
                                    fact(
                                      'clock',
                                      p.c.t('Event Time', 'ميعاد الايفنت'),
                                    ),
                                    fact('location', value(event['arenas'])),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        _Stagger(
                          delay: 200,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: webSecondary(ctx).withValues(alpha: .5),
                              border: Border.all(color: webBorder(ctx)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              value(event['details']),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.625,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  ctx,
                                ).colorScheme.onSurface.withValues(alpha: .9),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _Stagger(
                          delay: 300,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(ctx).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                              foregroundColor: Theme.of(
                                ctx,
                              ).scaffoldBackgroundColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              p.c.t('Coool!!', 'اشطة!!'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: p.c.t('Close modal', 'إغلاق'),
                      icon: Icon(Icons.close, size: 24, color: webMuted(ctx)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  },
  transitionBuilder: (ctx, animation, _, child) {
    if (MediaQuery.disableAnimationsOf(ctx)) return child;
    final progress = const Cubic(.34, 1.56, .64, 1).transform(animation.value);
    return Opacity(
      opacity: animation.value,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - progress)),
        child: Transform.scale(scale: .9 + .1 * progress, child: child),
      ),
    );
  },
);

class _Stagger extends StatefulWidget {
  const _Stagger({required this.delay, required this.child});
  final int delay;
  final Widget child;
  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Timer? timer;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      timer?.cancel();
      animation.value = 1;
    } else {
      timer ??= Timer(Duration(milliseconds: widget.delay), () {
        if (mounted) animation.forward();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: widget.child,
    builder: (_, child) {
      final v = const Cubic(.2, .8, .2, 1).transform(animation.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - v)),
          child: child,
        ),
      );
    },
  );
}
