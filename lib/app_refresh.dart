import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_spinner.dart';

/// Pull-to-refresh with the app's own spinner, the same on every page and
/// platform. Flutter's [RefreshIndicator] still decides when a pull counts;
/// this only draws it: a round chip slides down with the finger while its arc
/// fills, spins while refreshing, then shrinks away.
class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final RefreshCallback onRefresh;
  final Widget child;

  /// Chip diameter and its resting distance below the top of the list.
  static const chipSize = 40.0, restOffset = 18.0;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with SingleTickerProviderStateMixin {
  /// 0 hidden → 1 at the pull threshold; a little more while over-pulling.
  final _pull = ValueNotifier<double>(0);
  final _refreshing = ValueNotifier<bool>(false);
  late final AnimationController _settle;
  double _settleFrom = 0, _drag = 0;
  RefreshIndicatorStatus? _status;

  @override
  void initState() {
    super.initState();
    // Created here, not lazily: a first touch in dispose() would be too late.
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => _pull.value = _settleFrom * (1 - _settle.value));
  }

  @override
  void dispose() {
    _settle.dispose();
    _pull.dispose();
    _refreshing.dispose();
    super.dispose();
  }

  bool get _engaged =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _refreshing.value) {
      return false;
    }
    // RefreshIndicator arms at a sixth of the viewport; follow the same pull.
    final threshold = n.metrics.viewportDimension / 6;
    final dragging =
        (n is ScrollUpdateNotification && n.dragDetails != null) ||
        (n is OverscrollNotification && n.dragDetails != null);
    if (n is ScrollStartNotification) {
      _drag = 0;
    } else if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.dragDetails != null) {
      _drag -= n.overscroll;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final before = n.metrics.pixels - n.metrics.minScrollExtent;
      _drag = before < 0
          ? -before
          : math.max(0, _drag - (n.scrollDelta ?? 0).clamp(0, double.infinity));
    }
    if (dragging && _engaged) {
      _settle.stop();
      final next = _drag / threshold;
      if ((next - _pull.value).abs() > .004) _pull.value = next;
    }
    return false;
  }

  void _hide() {
    if (_pull.value == 0) return;
    _settleFrom = _pull.value;
    _settle.forward(from: 0);
  }

  void _onStatus(RefreshIndicatorStatus? status) {
    _status = status;
    switch (status) {
      case RefreshIndicatorStatus.drag:
        _settle.stop();
      case RefreshIndicatorStatus.armed:
        break;
      case RefreshIndicatorStatus.snap || RefreshIndicatorStatus.refresh:
        _settle.stop();
        _pull.value = 1;
      case RefreshIndicatorStatus.done ||
          RefreshIndicatorStatus.canceled ||
          null:
        if (!_refreshing.value) _hide();
    }
  }

  Future<void> _refresh() async {
    _refreshing.value = true;
    _pull.value = 1;
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _refreshing.value = false;
        _hide();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        theme.progressIndicatorTheme.refreshBackgroundColor ??
        theme.colorScheme.surface;
    // Pages whose list runs under the top bar report that inset here.
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: _onStatus,
            child: widget.child,
          ),
        ),
        Positioned(
          top: top,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_pull, _refreshing]),
              builder: (context, _) {
                final pull = _pull.value;
                if (pull <= 0 && !_refreshing.value) {
                  return const SizedBox.shrink();
                }
                final shown = Curves.easeOutCubic.transform(
                  pull.clamp(0.0, 1.0),
                );
                // A little extra travel when pulled past the threshold.
                final extra = 14 * (1 - 1 / (1 + math.max(0, pull - 1)));
                final dy =
                    -AppRefreshIndicator.chipSize +
                    (AppRefreshIndicator.chipSize +
                            AppRefreshIndicator.restOffset) *
                        shown +
                    extra;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Opacity(
                    opacity: shown,
                    child: Transform.scale(
                      scale: .7 + .3 * shown,
                      child: Center(
                        child: Container(
                          key: const ValueKey('app.refresh.chip'),
                          width: AppRefreshIndicator.chipSize,
                          height: AppRefreshIndicator.chipSize,
                          decoration: BoxDecoration(
                            color: background,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .16),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(9),
                          child: _refreshing.value
                              ? const AppSpinner(strokeWidth: 2.6)
                              : AppSpinner(strokeWidth: 2.6, value: shown),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
