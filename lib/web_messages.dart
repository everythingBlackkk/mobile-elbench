import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'api.dart';
import 'app_toast.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';
import 'floating_add.dart';

// Native equivalents of ask.css and notifications' shared timeline markup.
class _Colors {
  _Colors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get main => dark ? const Color(0xff0a0a0a) : Colors.white;
  Color get secondary =>
      dark ? const Color(0xff141414) : const Color(0xfff9fafb);
  Color get text => dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
  Color get muted => dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get border => dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
  Color get accent => dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
  Color get danger => dark ? const Color(0xffe7767d) : const Color(0xffc53d46);
  Color get fill => const Color(0xff2e855d);
}

String _ago(NativePageState page, dynamic input) {
  final parsed = DateTime.tryParse(value(input));
  if (parsed == null) return value(input);
  final difference = DateTime.now().difference(parsed);
  final seconds = difference.inSeconds.abs();
  final ar = page.c.settings.language == 'ar';
  if (seconds < 60) {
    return ar ? 'منذ ثوانٍ' : '${seconds.clamp(1, 59)} seconds ago';
  }
  final (int count, String unit, String arabic) = seconds < 3600
      ? (seconds ~/ 60, 'minute', 'دقيقة')
      : seconds < 86400
      ? (seconds ~/ 3600, 'hour', 'ساعة')
      : seconds < 604800
      ? (seconds ~/ 86400, 'day', 'يوم')
      : seconds < 2592000
      ? (seconds ~/ 604800, 'week', 'أسبوع')
      : seconds < 31536000
      ? (seconds ~/ 2592000, 'month', 'شهر')
      : (seconds ~/ 31536000, 'year', 'سنة');
  if (!ar) return '$count $unit${count == 1 ? '' : 's'} ago';
  if (count == 1) return 'منذ $arabic';
  if (count == 2) {
    return 'منذ ${switch (unit) {
      'minute' => 'دقيقتين',
      'hour' => 'ساعتين',
      'day' => 'يومين',
      'week' => 'أسبوعين',
      'month' => 'شهرين',
      _ => 'سنتين',
    }}';
  }
  final plural = count <= 10
      ? switch (unit) {
          'minute' => 'دقائق',
          'hour' => 'ساعات',
          'day' => 'أيام',
          'week' => 'أسابيع',
          'month' => 'أشهر',
          _ => 'سنوات',
        }
      : arabic;
  return 'منذ $count $plural';
}

bool _containsId(dynamic collection, dynamic id) {
  if (collection is Map) {
    return collection.containsKey('$id') || collection.containsKey(id);
  }
  if (collection is List) return collection.any((item) => '$item' == '$id');
  return false;
}

String _name(NativePageState page, Json person) =>
    value(person['name'], page.c.t('Deleted user', 'مستخدم محذوف'));

Widget _avatar(NativePageState page, Json person, double diameter, {Key? key}) {
  if (person.isEmpty) {
    final cacheExtent = (diameter * MediaQuery.devicePixelRatioOf(page.context))
        .ceil();
    return page.profileAvatar(
      person,
      key: key,
      radius: diameter / 2,
      child: ClipOval(
        child: networkImage(
          page.c.api.media('/avatars/jko.webp'),
          width: diameter,
          height: diameter,
          cacheWidth: cacheExtent,
          cacheHeight: cacheExtent,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: diameter,
            height: diameter,
            color: _Colors(page.context).secondary,
            alignment: Alignment.center,
            child: WebIcon('user', size: diameter / 2),
          ),
        ),
      ),
    );
  }
  return page.profileAvatar(person, key: key, radius: diameter / 2);
}

Widget _personName(NativePageState page, Json person, {double size = 14}) =>
    InkWell(
      onTap: page.profilePath(person) == null
          ? null
          : () => page.c.open(page.profilePath(person)!),
      child: Text(
        _name(page, person),
        textDirection: TextDirection.ltr,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    );

Widget _button(
  BuildContext context,
  String label,
  VoidCallback? onTap, {
  String? icon,
  bool filled = false,
  bool pill = false,
  double height = 38,
}) {
  final colors = _Colors(context);
  final foreground = onTap == null
      ? colors.muted
      : filled
      ? Colors.white
      : colors.text;
  return Material(
    color: onTap == null && filled
        ? colors.secondary
        : filled
        ? colors.fill
        : pill
        ? colors.secondary
        : colors.main,
    borderRadius: BorderRadius.circular(pill ? 99 : 12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(pill ? 99 : 12),
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          border: pill && !filled ? Border.all(color: colors.border) : null,
          borderRadius: BorderRadius.circular(pill ? 99 : 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              WebIcon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: pill ? 14 : 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _status(NativePageState page) {
  final text = value(page.envelope['status']);
  if (text.isEmpty) return const SizedBox.shrink();
  final colors = _Colors(page.context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    margin: const EdgeInsets.only(bottom: 15),
    decoration: BoxDecoration(
      color: colors.accent.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Text(text, style: TextStyle(color: colors.accent, fontSize: 14)),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.page,
    required this.icon,
    required this.title,
    required this.description,
  });
  final NativePageState page;
  final String icon, title, description;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 35),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent.withValues(alpha: colors.dark ? .12 : .1),
            ),
            alignment: Alignment.center,
            child: WebIcon(icon, size: 34, color: colors.accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: colors.text,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.6, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuAction {
  const _MenuAction(this.label, this.icon, this.action, {this.danger = false});
  final String label, icon;
  final VoidCallback action;
  final bool danger;
}

Widget _options(
  BuildContext context,
  List<_MenuAction> actions, {
  bool background = false,
}) {
  final colors = _Colors(context);
  return AppPopupMenuButton<int>(
    tooltip: '',
    padding: EdgeInsets.zero,
    color: colors.secondary,
    elevation: 9,
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: colors.border),
    ),
    onSelected: (index) => actions[index].action(),
    itemBuilder: (_) => [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebIcon(
                actions[i].icon,
                size: 17,
                color: actions[i].danger ? colors.danger : colors.text,
              ),
              const SizedBox(width: 9),
              Text(
                actions[i].label,
                style: TextStyle(
                  fontSize: 13,
                  color: actions[i].danger ? colors.danger : colors.text,
                ),
              ),
            ],
          ),
        ),
    ],
    child: Container(
      width: background ? 30 : 34,
      height: background ? 30 : 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ? colors.main : null,
      ),
      child: Text(
        '⋯',
        style: TextStyle(
          color: colors.muted,
          fontSize: background ? 21 : 24,
          height: 1,
        ),
      ),
    ),
  );
}

class _ActivitySnapshot {
  _ActivitySnapshot(this.envelope, this.path, this.scope)
    : saved = DateTime.now();
  final Json envelope;
  final String path, scope;
  final DateTime saved;
}

Json _copyActivity(Json source) => cloneJsonMap(source);

/// Tab visits retain the shell and scroll position, as navigation.js does for
/// [data-activity-list-content]. Only the incoming list moves during a visit.
class _ActivityTabs extends StatefulWidget {
  const _ActivityTabs({
    required this.page,
    required this.order,
    required this.builder,
  });
  final NativePageState page;
  final List<String> order;
  final Widget Function(BuildContext, _ActivityTabsState) builder;
  @override
  State<_ActivityTabs> createState() => _ActivityTabsState();
}

class _ActivityTabsState extends State<_ActivityTabs>
    with SingleTickerProviderStateMixin, RouteAware {
  late final scroll = ScrollController(
    initialScrollOffset: page.scrollOffset.value,
  );
  final panelKey = GlobalKey();
  final snapshots = <String, _ActivitySnapshot>{};
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late String selected, scope, counts;
  late String authorizedScope;
  Json inboxCounts = {};
  Timer? skeletonTimer;
  int generation = 0;
  late int revision;
  late Json lastEnvelope;
  bool pending = false, skeleton = false;
  bool _refreshOnResume = false;
  PageRoute<dynamic>? _route;
  double direction = 0, floor = 0;
  double? panelStart;
  String? error, failedTab;
  NativePageState get page => widget.page;
  bool get valid => authorizedScope == scope && page.c.user != null;

  String get currentScope {
    final c = page.c;
    final permissions =
        (c.user?['permissions'] is List
                ? c.user!['permissions'] as List
                : const [])
            .map((v) => '$v')
            .toList()
          ..sort();
    return jsonEncode([
      c.api.baseUri.origin,
      c.user?['id'],
      c.user?['role'],
      permissions,
      c.user?['can_post_announcements'],
      c.settings.language,
      c.features,
    ]);
  }

  @override
  void initState() {
    super.initState();
    selected = value(page.data['tab'], widget.order.first);
    scope = currentScope;
    authorizedScope = scope;
    counts = jsonEncode(page.c.counts);
    revision = page.c.cacheGeneration;
    lastEnvelope = page.envelope;
    inboxCounts = object(page.data['unreadInboxCounts']);
    remember();
    page.c.addListener(observeSession);
    page.c.settings.addListener(observeSession);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = page.pageRoute;
    if (route is PageRoute && route != _route) {
      if (_route != null) page.c.routeObserver.unsubscribe(this);
      _route = route;
      page.c.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (!_refreshOnResume) return;
    _refreshOnResume = false;
    scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant _ActivityTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A mutation, pagination or route-return refresh may replace this same
    // NativePage's envelope. Its current server result supersedes local visits.
    if (!identical(lastEnvelope, page.envelope) && page.c.user != null) {
      lastEnvelope = page.envelope;
      if (currentScope != scope) {
        observeSession();
        return;
      }
      generation++;
      skeletonTimer?.cancel();
      selected = value(page.data['tab'], widget.order.first);
      authorizedScope = scope;
      inboxCounts = object(page.data['unreadInboxCounts']);
      pending = skeleton = false;
      _refreshOnResume = false;
      error = failedTab = null;
      remember();
    }
  }

  void scheduleRefresh() {
    if (!(_route?.isCurrent ?? true)) {
      // Read-count updates must not make every retained inbox/notifications
      // route queue another request in front of the user's current action.
      _refreshOnResume = true;
      return;
    }
    final owner = generation;
    scheduleMicrotask(() {
      if (mounted && owner == generation && !page.loading) refresh();
    });
  }

  void remember() {
    if (!valid || Uri.parse(page.path).queryParameters.containsKey('page')) {
      return;
    }
    snapshots[value(page.data['tab'], widget.order.first)] = _ActivitySnapshot(
      _copyActivity(page.envelope),
      page.path,
      scope,
    );
  }

  void observeSession() {
    if (!mounted) return;
    final next = currentScope, nextCounts = jsonEncode(page.c.counts);
    final changed = revision != page.c.cacheGeneration;
    revision = page.c.cacheGeneration;
    if (next != scope) {
      generation++;
      skeletonTimer?.cancel();
      snapshots.clear();
      scope = next;
      authorizedScope = '';
      inboxCounts = {};
      counts = nextCounts;
      pending = false;
      setState(() {
        skeleton = true;
        error = null;
      });
      if (page.c.user != null) scheduleRefresh();
    } else if (counts != nextCounts || changed) {
      counts = nextCounts;
      // A tab's own GET can update badges. Preserve sibling snapshots and merge
      // those live counts on apply; external changes invalidate retained rows.
      if (changed || !pending) snapshots.clear();
      // A detail visit can mark an item read while this page is retained below
      // its route. Fetch its new unread state without replacing the shell.
      if (!pending && page.c.user != null) scheduleRefresh();
    }
  }

  @override
  void dispose() {
    generation++;
    skeletonTimer?.cancel();
    page.c.removeListener(observeSession);
    page.c.settings.removeListener(observeSession);
    page.c.routeObserver.unsubscribe(this);
    animation.dispose();
    scroll.dispose();
    super.dispose();
  }

  String tabPath(String tab) {
    final uri = Uri.parse(page.path);
    final parameters = {...uri.queryParameters, 'tab': tab}..remove('page');
    return uri.replace(queryParameters: parameters, fragment: '').toString();
  }

  void measurePanel() {
    final box = panelKey.currentContext?.findRenderObject();
    final viewport = scroll.hasClients
        ? scroll.position.context.notificationContext?.findRenderObject()
        : null;
    if (box is RenderBox && box.hasSize && viewport is RenderBox) {
      panelStart =
          box.localToGlobal(Offset.zero, ancestor: viewport).dy + scroll.offset;
    }
  }

  void holdScrollFloor() {
    if (scroll.hasClients && panelStart != null) {
      // Use the logical list start measured after layout. A scroll jump can
      // update pixels before RenderViewport has applied its paint transform.
      floor = math.max(
        0,
        scroll.position.viewportDimension + scroll.offset - panelStart!,
      );
    }
  }

  void apply(_ActivitySnapshot snapshot) {
    final envelope = _copyActivity(snapshot.envelope);
    // Snapshots never overwrite the current viewer, permissions or live badges.
    envelope['user'] = page.c.user;
    envelope['features'] = page.c.features;
    envelope['counts'] = page.c.counts;
    final data = object(envelope['data']);
    if (inboxCounts.isNotEmpty) data['unreadInboxCounts'] = {...inboxCounts};
    envelope['data'] = data;
    page.envelope = lastEnvelope = envelope;
    page.data = data;
    page.path = page.c.api.safePath(snapshot.path);
    authorizedScope = scope;
    page.c.rememberPage(
      page.path,
      envelope,
      offset: scroll.hasClients ? scroll.offset : page.scrollOffset.value,
    );
    if (ModalRoute.of(context)?.isCurrent ?? false) page.c.activatePage(page);
  }

  void slide(double sign) {
    direction = sign;
    if (sign == 0 || MediaQuery.disableAnimationsOf(context)) {
      animation.value = 1;
    } else {
      animation.forward(from: 0);
    }
  }

  Future<void> select(String tab) async {
    if (!widget.order.contains(tab)) return;
    if (tab == selected && !pending) {
      if (scroll.hasClients) {
        if (MediaQuery.disableAnimationsOf(context)) {
          scroll.jumpTo(0);
        } else {
          await scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(.22, 1, .36, 1),
          );
        }
      }
      return;
    }
    await visit(tab);
  }

  Future<void> refresh() async {
    if (!mounted || page.c.user == null) return;
    page.c.markAllStale();
    snapshots.clear();
    await visit(selected, force: true);
  }

  Future<void> visit(String tab, {bool force = false}) async {
    if (!mounted || page.c.user == null) return;
    final owner = ++generation, visitScope = scope;
    skeletonTimer?.cancel();
    final previous = valid
        ? _ActivitySnapshot(_copyActivity(page.envelope), page.path, scope)
        : null;
    final previousTab = value(page.data['tab'], widget.order.first);
    final sign = force
        ? 0.0
        : (widget.order.indexOf(tab) - widget.order.indexOf(previousTab)).sign
                  .toDouble() *
              (page.c.settings.language == 'ar' ? -1 : 1);
    final destination = tabPath(tab);
    holdScrollFloor();
    final cached = force ? null : snapshots[tab];
    final usable =
        cached != null &&
        cached.scope == scope &&
        DateTime.now().difference(cached.saved) < const Duration(minutes: 10);
    setState(() {
      selected = tab;
      error = failedTab = null;
      pending = true;
      skeleton = !valid;
    });
    if (usable) {
      setState(() {
        apply(cached);
        skeleton = false;
      });
      slide(sign);
      // Inbox GET marks questions read, so even a cached tab is revalidated on
      // every actual visit. Notifications can trust its recent authorized copy.
      if (page.screen == 'notifications.index' &&
          DateTime.now().difference(cached.saved) <
              const Duration(seconds: 30)) {
        setState(() => pending = false);
        return;
      }
    } else {
      skeletonTimer = Timer(const Duration(milliseconds: 90), () {
        if (mounted && owner == generation) {
          setState(() => skeleton = true);
        }
      });
    }
    try {
      final response = await page.c.get(destination);
      if (!mounted || owner != generation || visitScope != scope) return;
      final expected = page.screen;
      if (value(response['screen']) != expected) {
        await page.load(value(response['canonical_url'], destination));
        return;
      }
      final incoming = object(response['data']);
      if (incoming['unreadInboxCounts'] is Map) {
        inboxCounts = object(incoming['unreadInboxCounts']);
      }
      final snapshot = _ActivitySnapshot(
        _copyActivity(response),
        value(response['canonical_url'], destination),
        scope,
      );
      skeletonTimer?.cancel();
      setState(() {
        apply(snapshot);
        snapshots[tab] = snapshot;
        pending = false;
        skeleton = false;
      });
      if (!usable) slide(sign);
    } catch (e) {
      if (!mounted || owner != generation || visitScope != scope) return;
      skeletonTimer?.cancel();
      setState(() {
        if (!usable && previous != null && previous.scope == scope) {
          apply(previous);
          selected = previousTab;
        }
        pending = false;
        skeleton = !valid;
        error = '$e';
        failedTab = tab;
      });
    }
  }

  Widget panel(List<Widget> children, {bool clip = false}) {
    Widget content = AnimatedBuilder(
      animation: animation,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: floor),
        child: skeleton
            ? const _ActivitySkeleton()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
      ),
      builder: (_, child) => Transform.translate(
        key: const ValueKey('activity.list.motion'),
        offset: Offset(
          direction *
              48 *
              (1 - const Cubic(.22, 1, .36, 1).transform(animation.value)),
          0,
        ),
        child: child,
      ),
    );
    if (clip) content = ClipRect(child: content);
    return Column(
      key: panelKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _Colors(context).danger,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => visit(failedTab ?? selected),
                child: Text(page.c.t('Retry', 'إعادة المحاولة')),
              ),
            ],
          ),
        content,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // A retained short tab needs room for its saved scroll before first layout.
    if (panelStart == null && scroll.initialScrollOffset > 0) {
      floor = math.max(
        floor,
        MediaQuery.sizeOf(context).height + scroll.initialScrollOffset,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) measurePanel();
    });
    return widget.builder(context, this);
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    return Column(
      key: const ValueKey('activity.list.skeleton'),
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.border,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 13),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 180,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class WebInbox extends StatelessWidget {
  const WebInbox({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) => _ActivityTabs(
    page: page,
    order: const ['inbox', 'sent'],
    builder: (context, activity) {
      final colors = _Colors(context), c = page.c;
      final sent = page.data['tab'] == 'sent';
      final questions = rows(page.data['questions']);
      final counts = object(
        activity.valid ? page.data['unreadInboxCounts'] : null,
      );
      final inboxTabs = ['inbox', 'sent'];
      final selectedInboxIndex = inboxTabs
          .indexOf(activity.selected)
          .clamp(0, inboxTabs.length - 1);
      final reduceMotion =
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.of(context).accessibleNavigation;
      return RefreshIndicator.adaptive(
        onRefresh: () => page.refreshFromPull(activity.refresh),
        child: ListView(
          controller: activity.scroll,
          key: const ValueKey('activity.inbox.scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 27, 10, 110),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedAlign(
                        key: const ValueKey('activity.inbox.indicator'),
                        alignment: AlignmentDirectional(
                          selectedInboxIndex == 0 ? -1.0 : 1.0,
                          0.0,
                        ),
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                        child: FractionallySizedBox(
                          widthFactor: 0.5,
                          heightFactor: 1.0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: colors.main,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final tab in inboxTabs)
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            key: ValueKey('activity.inbox.tab.$tab'),
                            onTap: () => activity.select(tab),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 22,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedDefaultTextStyle(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 220),
                                      style: TextStyle(
                                        fontFamily: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.fontFamily,
                                        fontFamilyFallback: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.fontFamilyFallback,
                                        fontSize: 14,
                                        height: 1.5,
                                        fontWeight: FontWeight.w600,
                                        color: activity.selected == tab
                                            ? colors.text
                                            : colors.muted,
                                      ),
                                      child: Text(
                                        tab == 'sent'
                                            ? c.t('Sent', 'المرسلة')
                                            : c.t('Inbox', 'صندوق الوارد'),
                                      ),
                                    ),
                                    if ((int.tryParse(value(counts[tab])) ??
                                            0) >
                                        0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colors.fill,
                                        ),
                                        child: Text(
                                          (int.tryParse(value(counts[tab])) ??
                                                      0) >
                                                  99
                                              ? '99+'
                                              : value(counts[tab]),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (activity.valid) _status(page),
            activity.panel([
              if (questions.isEmpty)
                _Empty(
                  page: page,
                  icon: sent ? 'send' : 'inbox',
                  title: sent
                      ? c.t('No sent questions yet', 'لسه مبعتش أسئلة')
                      : c.t('No questions yet', 'لسه مفيش أسئلة'),
                  description: sent
                      ? c.t(
                          'Ask someone a question from their profile. You’ll find it here.',
                          'اسأل حد من ملفه الشخصي، وهتلاقي سؤالك هنا.',
                        )
                      : c.t(
                          'Questions people send you will appear here.',
                          'الأسئلة اللي الناس تبعتهالك هتظهر هنا.',
                        ),
                ),
              for (final question in questions)
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InboxCard(page: page, item: question, sent: sent),
                  ),
                ),
              page.pagination(page.data['questions']),
            ]),
          ],
        ),
      );
    },
  );
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.page,
    required this.item,
    required this.sent,
  });
  final NativePageState page;
  final Json item;
  final bool sent;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    final participant = object(item[sent ? 'recipient' : 'sender']);
    final answered = item['answered_at'] != null;
    final unread = _containsId(page.data['unreadQuestionIds'], item['id']);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: unread ? colors.accent.withValues(alpha: .09) : colors.secondary,
        border: Border.all(
          color: unread ? colors.accent.withValues(alpha: .32) : colors.border,
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(
                page,
                participant,
                44,
                key: ValueKey('inbox.avatar.${item['id']}'),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (sent)
                          Text(
                            '${c.t('To', 'إلى')} ',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Flexible(child: _personName(page, participant)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _ago(page, item['created_at']),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!sent)
                _options(context, [
                  _MenuAction(
                    c.t('Report', 'إبلاغ'),
                    'flag',
                    () => _reportQuestion(page, item),
                    danger: true,
                  ),
                ]),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 17),
            child: Text(
              value(item['question']),
              textDirection: contentDirection(value(item['question'])),
              style: TextStyle(fontSize: 16, height: 1.55, color: colors.text),
            ),
          ),
          Row(
            children: [
              _button(
                context,
                !sent && !answered
                    ? c.t('Reply', 'رد')
                    : answered
                    ? c.t('View question', 'عرض السؤال')
                    : c.t('Waiting for an answer', 'في انتظار الإجابة'),
                !sent && !answered
                    ? () => _reply(page, item)
                    : () => c.open(value(item['url'], '/ask/${item['id']}')),
                icon: !sent && !answered ? 'reply' : 'message',
              ),
              if (answered) ...[
                const Spacer(),
                Text(
                  c.t('Answered', 'تم الرد'),
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class WebAskDetail extends StatelessWidget {
  const WebAskDetail({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final item = object(page.data['question']);
    final owner = yes(page.data['isRecipient']);
    final answered = item['answered_at'] != null;
    final colors = _Colors(context), c = page.c;
    return RefreshIndicator.adaptive(
      onRefresh: page.pullRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 110),
        children: [
          _status(page),
          _QuestionThread(page: page, item: item, owner: owner),
          if (owner && !answered)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _button(
                  context,
                  c.t('Reply', 'رد'),
                  () => _reply(page, item),
                  icon: 'reply',
                ),
              ),
            ),
          if (!owner && value(item['answer']).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                c.t('Waiting for an answer', 'في انتظار الإجابة'),
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
            ),
          if (owner && !answered)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _reportQuestion(page, item),
                child: Text(
                  c.t('Report', 'إبلاغ'),
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestionThread extends StatelessWidget {
  const _QuestionThread({
    required this.page,
    required this.item,
    required this.owner,
  });
  final NativePageState page;
  final Json item;
  final bool owner;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    final answer = value(item['answer']);
    final published = item['published_at'] != null;
    final private = yes(item['is_private']);
    Widget entry(
      Json person,
      String text,
      dynamic timestamp, {
      bool menuSpace = false,
    }) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(page, person, 40),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: menuSpace ? 38 : 0),
                  child: Wrap(
                    spacing: 9,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _personName(page, person),
                      Text(
                        _ago(page, timestamp),
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  textDirection: contentDirection(text),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.secondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 15, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    if (answer.isNotEmpty)
                      PositionedDirectional(
                        start: 19,
                        top: 43,
                        bottom: 0,
                        child: Container(width: 2, color: colors.border),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: entry(
                        object(item['sender']),
                        value(item['question']),
                        item['created_at'],
                        menuSpace: owner && item['answered_at'] != null,
                      ),
                    ),
                  ],
                ),
                if (answer.isNotEmpty)
                  entry(object(item['recipient']), answer, item['answered_at']),
                if (published)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 50,
                      top: 18,
                    ),
                    child: Row(
                      children: [
                        WebIcon(
                          private ? 'lock' : 'globe',
                          size: 14,
                          color: colors.muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          private
                              ? c.t('Private', 'خاص')
                              : c.t('Public', 'عام'),
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (owner && item['answered_at'] != null)
            PositionedDirectional(
              top: 12,
              end: 12,
              child: _options(context, [
                if (!published)
                  _MenuAction(
                    c.t('Publish on my profile', 'انشر على ملفي الشخصي'),
                    'post',
                    () => page.run('PATCH', '/ask/${item['id']}/publication', {
                      'published': true,
                      'is_private': false,
                    }),
                  ),
                if (published)
                  _MenuAction(
                    private
                        ? c.t('Make public', 'خليه عام')
                        : c.t('Make private', 'خليه خاص'),
                    private ? 'globe' : 'lock',
                    () => page.run('PATCH', '/ask/${item['id']}/visibility', {
                      'is_private': !private,
                    }),
                  ),
                if (published)
                  _MenuAction(
                    c.t('Remove from profile', 'إزالة من الملف الشخصي'),
                    'delete',
                    () => _removePublication(page, item),
                    danger: true,
                  ),
                _MenuAction(
                  c.t('Report', 'إبلاغ'),
                  'flag',
                  () => _reportQuestion(page, item),
                  danger: true,
                ),
              ], background: true),
            ),
        ],
      ),
    );
  }
}

Future<void> _removePublication(NativePageState page, Json item) async {
  final confirmed = await _confirm(
    page,
    page.c.t(
      'Remove this question and answer from your profile?',
      'تحذف السؤال وإجابته من ملفك الشخصي؟',
    ),
    page.c.t('Remove from profile', 'إزالة من الملف الشخصي'),
  );
  if (confirmed && page.mounted) {
    await page.run('DELETE', '/ask/${item['id']}/publication');
  }
}

class WebNotifications extends StatefulWidget {
  const WebNotifications({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebNotifications> createState() => _WebNotificationsState();
}

class _WebNotificationsState extends State<WebNotifications> {
  bool dismissPush = false;
  NativePageState get page => widget.page;
  @override
  Widget build(BuildContext context) => _ActivityTabs(
    page: page,
    order: const ['all', 'replies', 'likes'],
    builder: (context, activity) {
      final colors = _Colors(context), c = page.c;
      final tab = value(page.data['tab'], 'all');
      final notifications = rows(page.data['notifications']);
      final notifOptions = [
        ('all', c.t('All', 'الكل')),
        ('replies', c.t('Replies', 'الردود')),
        ('likes', c.t('Likes', 'الإعجابات')),
      ];
      final selectedNotifIndex = notifOptions
          .indexWhere((o) => o.$1 == activity.selected)
          .clamp(0, notifOptions.length - 1);
      final reduceMotion =
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.of(context).accessibleNavigation;
      return Stack(
        children: [
          RefreshIndicator.adaptive(
            onRefresh: () => page.refreshFromPull(activity.refresh),
            child: ListView(
              controller: activity.scroll,
              key: const ValueKey('activity.notifications.scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 27, 10, 110),
              children: [
                if (activity.valid) _status(page),
                ListenableBuilder(
                  listenable: c.push,
                  builder: (_, _) =>
                      c.push.available && !c.push.enabled && !dismissPush
                      ? _PushCard(
                          page: page,
                          dismiss: () => setState(() => dismissPush = true),
                        )
                      : const SizedBox.shrink(),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.border)),
                  ),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Row(
                        children: [
                          for (final option in notifOptions)
                            Expanded(
                              child: InkWell(
                                key: ValueKey(
                                  'activity.notifications.tab.${option.$1}',
                                ),
                                onTap: () => activity.select(option.$1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 15,
                                  ),
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 220),
                                      style: TextStyle(
                                        fontFamily: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.fontFamily,
                                        fontFamilyFallback: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.fontFamilyFallback,
                                        fontSize: 14,
                                        height: 1.5,
                                        fontWeight: FontWeight.w600,
                                        color: activity.selected == option.$1
                                            ? colors.text
                                            : colors.muted,
                                      ),
                                      child: Text(option.$2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedAlign(
                            key: const ValueKey(
                              'activity.notifications.indicator',
                            ),
                            alignment: AlignmentDirectional(
                              -1.0 +
                                  2.0 *
                                      selectedNotifIndex /
                                      (notifOptions.length - 1),
                              1.0,
                            ),
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                            child: FractionallySizedBox(
                              widthFactor: 1 / notifOptions.length,
                              child: Center(
                                child: Container(
                                  width: 44,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: colors.accent,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                activity.panel([
                  for (final item in notifications)
                    RepaintBoundary(
                      child: _NotificationRow(page: page, item: item),
                    ),
                  if (notifications.isEmpty)
                    _Empty(
                      page: page,
                      icon: tab == 'likes'
                          ? 'heart'
                          : tab == 'replies'
                          ? 'reply'
                          : 'bell',
                      title: tab == 'likes'
                          ? c.t('No reactions yet', 'لسه مفيش تفاعلات')
                          : tab == 'replies'
                          ? c.t('No replies yet', 'لسه مفيش ردود')
                          : c.t('No notifications yet', 'لسه مفيش إشعارات'),
                      description: tab == 'likes'
                          ? c.t(
                              'Reactions to your posts and comments will appear here.',
                              'تفاعلات الناس مع منشوراتك وتعليقاتك هتظهر هنا.',
                            )
                          : tab == 'replies'
                          ? c.t(
                              'When someone replies to your posts, you’ll see it here.',
                              'لما حد يرد على منشوراتك، هتشوف الرد هنا.',
                            )
                          : c.t(
                              'Replies, reactions and updates will appear here.',
                              'الردود والتفاعلات والتحديثات هتظهر هنا.',
                            ),
                    ),
                  if (object(page.data['notifications'])['next_page_url'] !=
                          null ||
                      object(page.data['notifications'])['prev_page_url'] !=
                          null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: page.pagination(page.data['notifications']),
                    ),
                ], clip: true),
              ],
            ),
          ),
          if (activity.valid && yes(page.data['canAddAnnouncement']))
            WebFloatingAdd(
              key: const ValueKey('notifications.add'),
              dockHidden: c.dockHidden,
              label: c.t('Add announce', 'إضافة إعلان'),
              onTap: () => _composeAnnouncement(page),
            ),
        ],
      );
    },
  );
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.page, required this.item});
  final NativePageState page;
  final Json item;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    final announcement = item['kind'] == 'announcement';
    final scheduled = [
      'schedule_lecture',
      'schedule_section',
    ].contains(item['type']);
    final scheduleMeta = object(item['schedule_meta']);
    final actor = object(item[announcement ? 'author' : 'actor']);
    final unread = announcement
        ? !_containsId(page.data['readAnnouncementIds'], item['id'])
        : item['read_at'] == null;
    final canDelete = announcement && _canDeleteAnnouncement(page, item);
    final reaction = ['post_like', 'comment_like'].contains(item['type']);
    final preview = scheduled
        ? [
            value(scheduleMeta['subject']),
            value(scheduleMeta['location']),
            value(scheduleMeta['instructor']),
          ].where((v) => v.isNotEmpty).join(' · ')
        : announcement
        ? value(item['details'])
        : item['type'] == 'community_notice'
        ? [
            value(
              object(object(item['community_notice'])['community'])['name'],
            ),
            value(object(item['community_notice'])['title']),
          ].where((v) => v.isNotEmpty).join(' · ')
        : value(
            object(item['comment'])['content'] ??
                object(item['post'])['content'] ??
                object(item['community_question'])['content'],
          );
    return Stack(
      children: [
        Material(
          color: unread
              ? colors.accent.withValues(alpha: .09)
              : Colors.transparent,
          child: InkWell(
            onTap: () => c.open(
              value(
                item['url'],
                announcement
                    ? '/notifications/announcements/${item['id']}'
                    : '/notifications/${item['id']}',
              ),
            ),
            child: Container(
              padding: EdgeInsetsDirectional.fromSTEB(
                10,
                18,
                canDelete ? 45 : 10,
                18,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: unread
                        ? colors.accent.withValues(alpha: .32)
                        : colors.border,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    height: 36,
                    child: Center(
                      child: _TypeIcon(
                        kind: scheduled
                            ? 'schedule'
                            : announcement
                            ? 'update'
                            : reaction
                            ? 'reaction'
                            : 'reply',
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!scheduled) ...[
                          _avatar(
                            page,
                            actor,
                            36,
                            key: ValueKey('notification.avatar.${item['id']}'),
                          ),
                          const SizedBox(height: 11),
                        ],
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: scheduled
                                    ? item['type'] == 'schedule_lecture'
                                          ? c.t(
                                              'Lecture reminder',
                                              'تذكير بالمحاضرة',
                                            )
                                          : c.t(
                                              'Section reminder',
                                              'تذكير بالسكشن',
                                            )
                                    : _name(page, actor),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!announcement)
                                TextSpan(
                                  text: scheduled
                                      ? scheduleMeta['phase'] == 'start'
                                            ? c.t(
                                                ' · Starting now',
                                                ' · تبدأ الآن',
                                              )
                                            : c.t(
                                                ' · Starts in 10 minutes',
                                                ' · تبدأ بعد ١٠ دقائق',
                                              )
                                      : ' ${_notificationLabel(page, value(item['type']))}',
                                ),
                              TextSpan(
                                text: ' · ',
                                style: TextStyle(color: colors.muted),
                              ),
                              TextSpan(
                                text: _ago(page, item['created_at']),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 15,
                            height: 1.55,
                          ),
                        ),
                        if (announcement)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              value(item['title']),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                              ),
                            ),
                          ),
                        if (preview.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 15,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (unread)
          PositionedDirectional(
            top: 22,
            end: 6,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent,
              ),
            ),
          ),
        if (canDelete)
          PositionedDirectional(
            top: 16,
            end: 12,
            child: _options(context, [
              _MenuAction(
                c.t('Delete', 'حذف'),
                'delete',
                () => _deleteAnnouncement(page, item),
                danger: true,
              ),
            ]),
          ),
      ],
    );
  }
}

String _notificationLabel(NativePageState page, String type) => switch (type) {
  'post_reply' => page.c.t('replied to your post', 'رد على منشورك'),
  'post_like' => page.c.t('reacted to your post', 'تفاعل مع منشورك'),
  'comment_like' => page.c.t('reacted to your comment', 'تفاعل مع تعليقك'),
  'question_answer' => page.c.t(
    'answered your community question',
    'جاوب على سؤالك في المجتمع',
  ),
  'answer_received' => page.c.t('answered your question', 'جاوب على سؤالك'),
  'community_notice' => page.c.t('posted an update', 'نزّل تحديث'),
  _ => '',
};

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.kind});
  final String kind;
  static const _reactionSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="#f91880"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/></svg>';
  static const _replySvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="#1d9bf0"><path d="M20.8 11.6a8.6 8.6 0 0 1-8.7 8.4H9.3l-5.8 3v-6.1A8.1 8.1 0 0 1 3 5.4a9.2 9.2 0 0 1 6.4-2.5h2.7a8.6 8.6 0 0 1 8.7 8.7Z" fill="none" stroke="#1d9bf0" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 -1) scale(.96)"/></svg>';
  static const _defaultSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="#a56cf5"><path d="m12 2.5 2.9 5.9 6.5.9-4.7 4.6 1.1 6.5-5.8-3.1-5.8 3.1 1.1-6.5-4.7-4.6 6.5-.9L12 2.5Z" fill="none" stroke="#a56cf5" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';

  @override
  Widget build(BuildContext context) {
    if (kind == 'schedule') {
      return const Icon(
        Icons.calendar_month_outlined,
        color: Color(0xff2e855d),
        size: 28,
      );
    }
    final svg = kind == 'reaction'
        ? _reactionSvg
        : kind == 'reply'
        ? _replySvg
        : _defaultSvg;
    return SvgPicture.string(svg, width: 28, height: 28);
  }
}

class WebAnnouncement extends StatelessWidget {
  const WebAnnouncement({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    final item = object(page.data['announcement']);
    final author = object(item['author']);
    final canDelete = _canDeleteAnnouncement(page, item);
    return RefreshIndicator.adaptive(
      onRefresh: page.pullRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 30, 10, 110),
        children: [
          _status(page),
          Container(
            decoration: BoxDecoration(
              color: colors.secondary,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: canDelete ? 38 : 0,
                        ),
                        child: Text(
                          value(item['title']),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                            height: 1.5,
                          ),
                        ),
                      ),
                      Text(
                        '${c.t('Official update by', 'تحديث رسمي من')} ${_name(page, author)} · ${_ago(page, item['created_at'])}',
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SelectableText(
                        value(item['details']),
                        textDirection: contentDirection(value(item['details'])),
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.65,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canDelete)
                  PositionedDirectional(
                    top: 12,
                    end: 12,
                    child: _options(context, [
                      _MenuAction(
                        c.t('Delete', 'حذف'),
                        'delete',
                        () => _deleteAnnouncement(page, item, detail: true),
                        danger: true,
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _canDeleteAnnouncement(NativePageState page, Json item) =>
    page.c.permission('announcements.manage') ||
    (item['user_id'] != null &&
        '${item['user_id']}' == '${page.c.user?['id']}');

Future<bool> _confirm(
  NativePageState page,
  String message,
  String action,
) async {
  final colors = _Colors(page.context);
  return await showDialog<bool>(
        context: page.context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.main,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: colors.border),
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                page.c.t('Cancel', 'إلغاء'),
                style: TextStyle(color: colors.muted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action, style: TextStyle(color: colors.danger)),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _deleteAnnouncement(
  NativePageState page,
  Json item, {
  bool detail = false,
}) async {
  final confirmed = await _confirm(
    page,
    page.c.t(
      'Are you sure you want to delete this announcement?',
      'متأكد إنك عايز تمسح الإعلان ده؟',
    ),
    page.c.t('Delete', 'حذف'),
  );
  if (!confirmed || !page.mounted) return;
  try {
    await page.c.action('DELETE', '/notifications/announcements/${item['id']}');
    if (page.mounted) await page.load(detail ? '/notifications' : null);
  } catch (error) {
    if (page.mounted) {
      showAppToast(page.context, '$error');
    }
  }
}

Future<void> _reply(NativePageState page, Json item) async {
  final sent = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: page.context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _Colors(page.context).main,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _Composer(page: page, question: item),
  );
  if (sent == true && page.mounted) {
    if (page.screen == 'ask.inbox') {
      await page.load();
      page.c.open(value(item['url'], '/ask/${item['id']}'));
    } else {
      await page.load();
    }
  }
}

Future<void> _composeAnnouncement(NativePageState page) async {
  final sent = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: page.context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _Colors(page.context).main,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _Composer(page: page),
  );
  if (sent == true && page.mounted) await page.load('/notifications');
}

class _Composer extends StatefulWidget {
  const _Composer({required this.page, this.question});
  final NativePageState page;
  final Json? question;
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final title = TextEditingController(), body = TextEditingController();
  bool busy = false, publish = false;
  String? error;
  bool get reply => widget.question != null;
  NativePageState get page => widget.page;
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy ||
        body.text.trim().isEmpty ||
        (!reply && title.text.trim().isEmpty)) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await page.c.action(
        'POST',
        reply
            ? '/ask/${widget.question!['id']}/answer'
            : '/notifications/announcements',
        reply
            ? {'answer': body.text.trim(), 'publish': publish}
            : {'title': title.text.trim(), 'details': body.text.trim()},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).top -
        30;
    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.muted.withValues(alpha: .64)),
      filled: true,
      fillColor: colors.secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.accent),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      counterText: '',
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: available - keyboard,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            20,
            22,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    _button(
                      context,
                      c.t('Cancel', 'إلغاء'),
                      busy ? null : () => Navigator.pop(context),
                      pill: true,
                      height: 44,
                    ),
                    Expanded(
                      child: Text(
                        reply
                            ? c.t('Reply', 'رد')
                            : c.t('Add announce', 'إضافة إعلان'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _button(
                      context,
                      busy
                          ? '…'
                          : reply && !publish
                          ? c.t('Send reply', 'إرسال الرد')
                          : c.t('Publish', 'نشر'),
                      busy ? null : submit,
                      filled: true,
                      pill: true,
                      height: 44,
                    ),
                  ],
                ),
              ),
              if (reply) ...[
                Container(
                  constraints: BoxConstraints(maxHeight: available * .35),
                  margin: const EdgeInsets.only(top: 25, bottom: 14),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _avatar(page, object(widget.question!['sender']), 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _name(page, object(widget.question!['sender'])),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                value(widget.question!['question']),
                                textDirection: contentDirection(
                                  value(widget.question!['question']),
                                ),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colors.muted,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 22),
                Text(
                  c.t('Title', 'العنوان'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                AdaptiveTextField(
                  controller: title,
                  field: (direction) => TextField(
                    controller: title,
                    textDirection: direction,
                    maxLength: 255,
                    style: const TextStyle(fontSize: 16),
                    decoration: decoration(
                      c.t(
                        'Enter announcement title...',
                        'اكتب عنوان الإعلان...',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  c.t('Description', 'الوصف'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
              ],
              Expanded(
                child: AdaptiveTextField(
                  controller: body,
                  field: (direction) => TextField(
                    controller: body,
                    textDirection: direction,
                    maxLength: reply ? 3000 : 65535,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: colors.text,
                    ),
                    decoration: reply
                        ? InputDecoration(
                            hintText: c.t('Write a reply…', 'اكتب ردك…'),
                            hintStyle: TextStyle(
                              color: colors.muted.withValues(alpha: .64),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 5,
                            ),
                            counterText: '',
                          )
                        : decoration(
                            c.t(
                              'Enter announcement details...',
                              'اكتب تفاصيل الإعلان...',
                            ),
                          ),
                  ),
                ),
              ),
              if (reply)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InkWell(
                    onTap: () => setState(() => publish = !publish),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: publish,
                            onChanged: (on) =>
                                setState(() => publish = on ?? false),
                            activeColor: colors.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.t(
                              'Publish this question and answer on my profile',
                              'انشر السؤال وإجابتي على ملفي الشخصي',
                            ),
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(color: colors.danger, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _reportQuestion(NativePageState page, Json question) =>
    showDialog<void>(
      context: page.context,
      builder: (_) => _ReportDialog(page: page, question: question),
    );

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.page, required this.question});
  final NativePageState page;
  final Json question;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.page.c.action(
        'POST',
        '/ask/${widget.question['id']}/reports',
        {'reason': reason.text.trim()},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = widget.page.c;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: colors.main,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.t('Report this question', 'الإبلاغ عن السؤال'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 20),
                        child: Text(
                          c.t(
                            'Your report will be sent to the moderation team for review.',
                            'بلاغك هيوصل لفريق الإشراف للمراجعة.',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.muted,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.secondary,
                    ),
                    child: const Text('×', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ],
            ),
            Text(
              c.t('Reason (optional)', 'السبب (اختياري)'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            AdaptiveTextField(
              controller: reason,
              field: (direction) => TextField(
                controller: reason,
                textDirection: direction,
                minLines: 4,
                maxLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.secondary,
                  contentPadding: const EdgeInsets.all(12),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ),
            SizedBox(height: error == null ? 36 : 8),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: TextStyle(fontSize: 13, color: colors.danger),
                ),
              ),
            _button(
              context,
              busy
                  ? c.t('Sending…', 'جاري الإرسال…')
                  : c.t('Submit report', 'إرسال البلاغ'),
              busy ? null : submit,
              filled: true,
              height: 44,
            ),
          ],
        ),
      ),
    );
  }
}

class _PushCard extends StatelessWidget {
  const _PushCard({required this.page, required this.dismiss});
  final NativePageState page;
  final VoidCallback dismiss;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context), c = page.c;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: .07),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.fill,
            ),
            child: const WebIcon('bell', size: 21, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.t('Turn on notifications', 'فعّل الإشعارات'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.t(
                    'Get notified when someone comments, reacts, answers or asks you something, even when the app is closed.',
                    'هيوصلك إشعار لما حد يعلّق أو يتفاعل أو يجاوب أو يسألك، حتى لو التطبيق مقفول.',
                  ),
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    c.push.state,
                    style: TextStyle(color: colors.accent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _button(
                      context,
                      c.t('Turn on', 'تفعيل'),
                      c.push.enable,
                      filled: true,
                      pill: true,
                      height: 40,
                    ),
                    _button(
                      context,
                      c.t('Not now', 'مش دلوقتي'),
                      dismiss,
                      pill: true,
                      height: 40,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
