import 'dart:async';

import 'package:flutter/material.dart';

final _toasts = Expando<_ToastHandle>();

/// A brief, non-blocking message shared by every in-app action.
void showAppToast(BuildContext context, String message) {
  if (!context.mounted || message.trim().isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toasts[overlay]?.remove();
  late final _ToastHandle handle;
  final theme = Theme.of(context);
  final direction = Directionality.of(context);
  final entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: Directionality(
        textDirection: direction,
        child: _AppToast(message: message, onDismissed: () => handle.remove()),
      ),
    ),
  );
  handle = _ToastHandle(overlay, entry);
  _toasts[overlay] = handle;
  overlay.insert(entry);
}

class _ToastHandle {
  _ToastHandle(this.overlay, this.entry);
  final OverlayState overlay;
  final OverlayEntry entry;
  bool removed = false;

  void remove() {
    if (removed) return;
    removed = true;
    if (overlay.mounted) entry.remove();
    entry.dispose();
    if (identical(_toasts[overlay], this)) _toasts[overlay] = null;
  }
}

class _AppToast extends StatefulWidget {
  const _AppToast({required this.message, required this.onDismissed});
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final motion = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? timer;
  bool started = false, reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      animation.value = 1;
    } else {
      animation.forward();
    }
    timer = Timer(const Duration(seconds: 2), () async {
      if (!reducedMotion) await animation.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    motion.dispose();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Positioned(
      left: 20,
      right: 20,
      bottom:
          MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom +
          18,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: motion,
            child: SlideTransition(
              key: const ValueKey('app.toast.slide'),
              position: Tween<Offset>(
                begin: const Offset(0, 1.4),
                end: Offset.zero,
              ).animate(motion),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  key: const ValueKey('app.toast'),
                  color: dark ? const Color(0xff242424) : Colors.white,
                  elevation: 5,
                  shadowColor: Colors.black.withValues(alpha: .18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: dark
                          ? const Color(0xff3a3a3a)
                          : const Color(0xffe5e7eb),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: dark
                              ? const Color(0xfff3f4f6)
                              : const Color(0xff111827),
                          height: 1.4,
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
