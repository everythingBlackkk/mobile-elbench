import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'web_style.dart';

/// Positioned inside an extending Scaffold body. Its inherited bottom padding
/// already includes the dock and device inset, so it must be counted only once.
class WebFloatingAdd extends StatelessWidget {
  const WebFloatingAdd({
    super.key,
    required this.label,
    required this.onTap,
    this.visible = true,
    this.animate = false,
    this.dockHidden,
  });
  final String label;
  final VoidCallback onTap;
  final bool visible, animate;
  final ValueListenable<bool>? dockHidden;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    final duration = animate && !reduce
        ? const Duration(milliseconds: 180)
        : Duration.zero;
    return ValueListenableBuilder<bool>(
      valueListenable: dockHidden ?? const AlwaysStoppedAnimation(false),
      builder: (context, hidden, child) => AnimatedPositioned(
        right: 16 + padding.right,
        bottom:
            (hidden
                ? View.of(context).viewPadding.bottom /
                      View.of(context).devicePixelRatio
                : padding.bottom) +
            12,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: child!,
      ),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, .16),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: Curves.easeOut,
              child: RepaintBoundary(
                child: Semantics(
                  label: label,
                  button: true,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x2e000000),
                          blurRadius: 24,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Material(
                      color: const Color(0xff2e855d),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onTap,
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: WebIcon(
                              'plus',
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
