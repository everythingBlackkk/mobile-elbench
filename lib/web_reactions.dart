import 'package:flutter/material.dart';

import 'api.dart';
import 'app_menus.dart';
import 'page_skeletons.dart';
import 'screens.dart';
import 'web_home.dart' show webMuted;
import 'app_spinner.dart';

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
    final above = anchor.top - safeTop >= 76;
    final ar = Directionality.of(context) == TextDirection.rtl;
    setState(() => _open = true);
    try {
      final reaction = await showAppMenu<String>(
        context: context,
        anchorRect: above
            ? Rect.fromLTWH(anchor.left, anchor.top - 70, anchor.width, 0)
            : anchor,
        menuWidth: 260,
        menuMaxHeight: 64,
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

String _emoji(String reaction) => reactionEmoji(reaction);

/// Every reaction, in picker order. The server accepts the same list.
const reactionTypes = ['like', 'love', 'funny', 'sad', 'care'];

String reactionEmoji(String reaction) => switch (reaction) {
  'love' => '❤️',
  'funny' => '😂',
  'sad' => '😭',
  'care' => '🥰',
  _ => '👍',
};

String reactionName(String reaction, bool arabic) => switch (reaction) {
  'love' => arabic ? 'أحببته' : 'Love',
  'funny' => arabic ? 'مضحك' : 'Funny',
  'sad' => arabic ? 'حزين' : 'Sad',
  'care' => arabic ? 'أدعمك' : 'Care',
  _ => arabic ? 'إعجاب' : 'Like',
};

class _ReactionPaletteEntry extends PopupMenuEntry<String> {
  const _ReactionPaletteEntry({required this.selected, required this.arabic});
  final String? selected;
  final bool arabic;
  @override
  double get height => 48;
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
    height: 48,
    child: Row(
      children: [
        for (final (i, type) in reactionTypes.indexed)
          Expanded(
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = Interval(
                  i * .06,
                  .76 + i * .06,
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
                label: reactionName(type, widget.arabic),
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
                height: 44,
                child: Center(
                  child: Text(
                    _emoji(widget.type),
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.25),
                    style: const TextStyle(fontSize: 25),
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

const _reactionTypes = reactionTypes;

/// Total reactions on a post, comment or answer row.
int reactionTotal(Json row) => _reactionTypes.fold<int>(
  0,
  (n, k) => n + (int.tryParse(value(row['${k}_count'])) ?? 0),
);

/// The emojis people used on a row, then the total, as shown under posts and comments.
class WebReactionSummary extends StatelessWidget {
  const WebReactionSummary({
    super.key,
    required this.row,
    this.emojiSize = 16,
    this.gap = 7,
  });
  final Json row;
  final double emojiSize, gap;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final type in _reactionTypes)
        if ((int.tryParse(value(row['${type}_count'])) ?? 0) > 0)
          Text(_emoji(type), style: TextStyle(fontSize: emojiSize)),
      SizedBox(width: gap),
      Text(
        '${reactionTotal(row)}',
        style: TextStyle(fontSize: 13, color: webMuted(context)),
      ),
    ],
  );
}

/// Makes a row's reaction summary open the list of people who reacted.
class WebReactionCount extends StatelessWidget {
  const WebReactionCount({
    super.key,
    required this.page,
    required this.endpoint,
    required this.row,
    required this.child,
  });
  final NativePageState page;
  final String endpoint;
  final Json row;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: page.c.t(
      'See who reacted (${reactionTotal(row)})',
      'شوف مين تفاعل (${reactionTotal(row)})',
    ),
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showReactionsSheet(page, endpoint, row),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      ),
    ),
  );
}

/// Lists everyone who reacted, newest first, with a tab per reaction type.
/// People load only when the sheet opens, 30 at a time.
Future<void> showReactionsSheet(
  NativePageState page,
  String endpoint,
  Json row,
) {
  final dark = Theme.of(page.context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: page.context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: dark ? const Color(0xff161616) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .62,
      minChildSize: .35,
      maxChildSize: .92,
      builder: (context, scroll) => _ReactionsSheet(
        page: page,
        endpoint: endpoint,
        counts: {
          for (final type in _reactionTypes)
            type: int.tryParse(value(row['${type}_count'])) ?? 0,
        },
        scroll: scroll,
      ),
    ),
  );
}

class _ReactorTab {
  final people = <Json>[];
  int? next = 1;
  bool loading = false;
  String? error;
}

class _ReactionsSheet extends StatefulWidget {
  const _ReactionsSheet({
    required this.page,
    required this.endpoint,
    required this.counts,
    required this.scroll,
  });
  final NativePageState page;
  final String endpoint;
  final Map<String, int> counts;
  final ScrollController scroll;
  @override
  State<_ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<_ReactionsSheet> {
  static const _extent = 68.0;
  late Map<String, int> counts = widget.counts;
  final tabs = <String, _ReactorTab>{};
  String tab = '';

  _ReactorTab get current => tabs.putIfAbsent(tab, _ReactorTab.new);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = tab, state = current, page = state.next;
    if (state.loading || page == null) return;
    setState(() {
      state.loading = true;
      state.error = null;
    });
    try {
      final response = await widget.page.c.get(
        '${widget.endpoint}?page=$page${key.isEmpty ? '' : '&type=$key'}',
      );
      if (!mounted) return;
      final fresh = object(response['counts']);
      setState(() {
        state.people.addAll(rows(response['data']));
        state.next = int.tryParse(value(response['next_page']));
        if (fresh.isNotEmpty) {
          counts = {
            for (final type in _reactionTypes)
              type: int.tryParse(value(fresh[type])) ?? 0,
          };
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => state.error = e is ApiFailure && e.message.isNotEmpty
            ? e.message
            : widget.page.c.t(
                'Could not load reactions.',
                'تعذر تحميل التفاعلات.',
              ),
      );
    } finally {
      if (mounted) setState(() => state.loading = false);
    }
  }

  void _select(String next) {
    if (next == tab) return;
    setState(() => tab = next);
    if (current.people.isEmpty && current.error == null) _load();
  }

  Widget _retry() => Center(
    child: TextButton(
      onPressed: _load,
      child: Text(widget.page.c.t('Try again', 'حاول تاني')),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.page.c;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final state = current;
    final Widget list;
    if (state.people.isEmpty &&
        (state.loading || state.next != null) &&
        state.error == null) {
      list = ListView(
        controller: widget.scroll,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SkeletonPulse(
            child: Column(
              children: [
                for (var i = 0; i < 6; i++)
                  const SizedBox(
                    height: _extent,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          SkeletonBlock(width: 46, height: 46, radius: 23),
                          SizedBox(width: 14),
                          Expanded(
                            child: SkeletonLine(fraction: .5, height: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    } else if (state.people.isEmpty) {
      list = ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            state.error ?? c.t('No reactions yet', 'لسه مفيش تفاعلات'),
            textAlign: TextAlign.center,
            style: TextStyle(color: webMuted(context)),
          ),
          if (state.error != null) _retry(),
        ],
      );
    } else {
      final more = state.next != null || state.error != null;
      list = ListView.builder(
        key: PageStorageKey('reactions.list.$tab'),
        controller: widget.scroll,
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemExtent: _extent,
        itemCount: state.people.length + (more ? 1 : 0),
        itemBuilder: (context, i) => i < state.people.length
            ? _ReactorRow(page: widget.page, row: state.people[i])
            : state.error != null
            ? _retry()
            : const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: AppSpinner(strokeWidth: 2),
                ),
              ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              c.t('Reactions ($total)', 'التفاعلات ($total)'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _ReactionTab(
                key: const ValueKey('reactions.tab.all'),
                label: c.t('All', 'الكل'),
                selected: tab.isEmpty,
                onTap: () => _select(''),
              ),
              for (final type in _reactionTypes)
                if ((counts[type] ?? 0) > 0)
                  _ReactionTab(
                    key: ValueKey('reactions.tab.$type'),
                    emoji: _emoji(type),
                    label: '${counts[type]}',
                    selected: tab == type,
                    onTap: () => _select(type),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300 &&
                  state.people.isNotEmpty &&
                  state.next != null &&
                  !state.loading &&
                  state.error == null) {
                _load();
              }
              return false;
            },
            child: list,
          ),
        ),
      ],
    );
  }
}

/// A pill filter: solid app green when selected, soft grey otherwise.
class _ReactionTab extends StatelessWidget {
  const _ReactionTab({
    super.key,
    this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String? emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The app's green, as on filled buttons (AppSettings.accent).
    const accent = Color(0xff2e855d);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? accent
              : dark
              ? const Color(0xff262626)
              : const Color(0xfff3f4f6),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: emoji == null ? 20 : 14,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (emoji != null) ...[
                    Text(
                      emoji!,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    textScaler: MediaQuery.textScalerOf(
                      context,
                    ).clamp(maxScaleFactor: 1.3),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactorRow extends StatelessWidget {
  const _ReactorRow({required this.page, required this.row});
  final NativePageState page;
  final Json row;
  @override
  Widget build(BuildContext context) {
    final c = page.c;
    final person = {
      'id': row['user_id'],
      'name': row['name'],
      'avatar': row['avatar'],
      'avatar_url': row['avatar_url'],
    };
    final name = value(row['name'], c.t('Deleted user', 'مستخدم محذوف'));
    final mine = value(row['user_id']) == value(c.user?['id'], '-');
    final destination = page.profilePath(person);
    final reaction = value(row['type']);
    final reactionLabel = reactionName(reaction, c.settings.language == 'ar');
    return Semantics(
      button: destination != null,
      label: '$name${mine ? c.t(' (You)', ' (أنت)') : ''}, $reactionLabel',
      excludeSemantics: true,
      child: InkWell(
        onTap: destination == null
            ? null
            : () {
                Navigator.of(context).pop();
                c.open(destination);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              page.avatar(person, radius: 23),
              const SizedBox(width: 14),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: name,
                    children: [
                      if (mine)
                        TextSpan(
                          text: c.t(' (You)', ' (أنت)'),
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: webMuted(context),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _emoji(reaction),
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.2),
                style: const TextStyle(fontSize: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
