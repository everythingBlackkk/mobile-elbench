import 'package:flutter/material.dart';

/// Scrolling for the whole app: each platform keeps its native feel (iOS
/// bounce, Android clamping/stretch), but a fling carries further, so long
/// feeds are faster to move through.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final native = super.getScrollPhysics(context);
    // Clamping (Android) deceleration grows faster than linearly with
    // velocity, so it needs a smaller boost for a similar extra distance.
    return FastFlingScrollPhysics(
      parent: native,
      boost: native is ClampingScrollPhysics ? 1.15 : 1.3,
    );
  }
}

class FastFlingScrollPhysics extends ScrollPhysics {
  const FastFlingScrollPhysics({super.parent, this.boost = 1.3});

  /// Fling velocity multiplier: the same swipe carries further.
  final double boost;

  @override
  FastFlingScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      FastFlingScrollPhysics(parent: buildParent(ancestor), boost: boost);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(
    position,
    // Overscroll settling (pull-to-refresh, bounce back) keeps its own speed.
    position.outOfRange ? velocity : velocity * boost,
  );
}
