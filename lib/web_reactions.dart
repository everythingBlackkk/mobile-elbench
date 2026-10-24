import 'package:flutter/material.dart';

import 'app_menus.dart';

/// A shared reaction control. Its anchored palette never relays out the feed.
class WebReactionButton extends StatefulWidget {
  const WebReactionButton({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final String? selected;
  final Future<void> Function(String reaction) onSelected;

  @override
  State<WebReactionButton> createState() => _WebReactionButtonState();
}

class _WebReactionButtonState extends State<WebReactionButton> {
  bool _open = false, _busy = false;

  Future<void> _show() async {
    if (_open || _busy) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final anchor = origin & box.size;
    final safeTop = MediaQuery.paddingOf(navigator.context).top;
    final above = anchor.top - safeTop >= 88;
    final ar = Directionality.of(context) == TextDirection.rtl;
    setState(() => _open = true);
    try {
      final reaction = await showAppMenu<String>(
        context: context,
        anchorRect: above
            ? Rect.fromLTWH(anchor.left, anchor.top - 82, anchor.width, 0)
            : anchor,
        menuWidth: 180,
        menuMaxHeight: 76,
        semanticLabel: ar ? 'اختر تفاعل' : 'Choose a reaction',
        items: [_ReactionPaletteEntry(selected: widget.selected, arabic: ar)],
      );
      if (!mounted || reaction == null) return;
      setState(() => _busy = true);
      await widget.onSelected(reaction);
    } finally {
      if (mounted) {
        setState(() {
          _open = false;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ar = Directionality.of(context) == TextDirection.rtl;
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    return Semantics(
      button: true,
      selected: widget.selected != null,
      label: ar ? 'تفاعل' : 'React',
      child: Opacity(
        opacity: _busy ? .55 : 1,
        child: Material(
          color: widget.selected != null || _open
              ? theme.colorScheme.primary.withValues(alpha: .12)
              : theme.brightness == Brightness.dark
              ? const Color(0xff202020)
              : const Color(0xfff3f4f6),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: _busy ? null : _show,
            onLongPress: _busy ? null : _show,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: widget.selected == null
                      ? Icon(
                          Icons.thumb_up_outlined,
                          key: const ValueKey('none'),
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Text(
                          _emoji(widget.selected!),
                          key: ValueKey(widget.selected),
                          textScaler: MediaQuery.textScalerOf(
                            context,
                          ).clamp(maxScaleFactor: 1.25),
                          style: const TextStyle(fontSize: 21),
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

String _emoji(String reaction) => switch (reaction) {
  'love' => '❤️',
  'funny' => '😂',
  _ => '👍',
};

class _ReactionPaletteEntry extends PopupMenuEntry<String> {
  const _ReactionPaletteEntry({required this.selected, required this.arabic});
  final String? selected;
  final bool arabic;
  @override
  double get height => 60;
  @override
  bool represents(String? value) => false;
  @override
  State<_ReactionPaletteEntry> createState() => _ReactionPaletteEntryState();
}

class _ReactionPaletteEntryState extends State<_ReactionPaletteEntry>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    if (reduce) {
      _entrance.stop();
      _entrance.value = 1;
    } else if (!_started) {
      _entrance.forward();
    }
    _started = true;
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('reaction.palette'),
    height: 60,
    child: Row(
      children: [
        for (final (i, type) in ['like', 'love', 'funny'].indexed)
          Expanded(
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = Interval(
                  i * .12,
                  .76 + i * .12,
                ).transform(_entrance.value);
                final eased = Curves.easeOutCubic.transform(t);
                return IgnorePointer(
                  ignoring: eased < .2,
                  child: Opacity(
                    opacity: eased,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - eased)),
                      child: Transform.scale(
                        scale: .68 + .32 * Curves.easeOutBack.transform(t),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
              child: _ReactionChoice(
                type: type,
                selected: widget.selected == type,
                label: switch (type) {
                  'love' => widget.arabic ? 'أحببته' : 'Love',
                  'funny' => widget.arabic ? 'مضحك' : 'Funny',
                  _ => widget.arabic ? 'إعجاب' : 'Like',
                },
              ),
            ),
          ),
      ],
    ),
  );
}

class _ReactionChoice extends StatefulWidget {
  const _ReactionChoice({
    required this.type,
    required this.label,
    required this.selected,
  });
  final String type, label;
  final bool selected;
  @override
  State<_ReactionChoice> createState() => _ReactionChoiceState();
}

class _ReactionChoiceState extends State<_ReactionChoice> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      child: Tooltip(
        message: widget.label,
        child: AnimatedScale(
          scale: _pressed ? .88 : 1,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Material(
            color: widget.selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey('reaction.choice.${widget.type}'),
              borderRadius: BorderRadius.circular(16),
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).pop(widget.type),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    _emoji(widget.type),
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.25),
                    style: const TextStyle(fontSize: 28),
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
