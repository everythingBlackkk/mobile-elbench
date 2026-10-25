import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'api.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';
import 'native_share.dart';
import 'web_event.dart';
import 'web_comments.dart';
import 'web_schedule.dart';
import 'web_reactions.dart';
import 'comment_thread_rails.dart';
import 'floating_add.dart';
import 'infinite_feed.dart';

Color webMuted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff9ca3af)
    : const Color(0xff6b7280);
Color webBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff303030)
    : const Color(0xffe5e7eb);
Color webSecondary(BuildContext context) =>
    Theme.of(context).colorScheme.surface;
String webAgo(dynamic source, bool ar) {
  final time = DateTime.tryParse(value(source));
  if (time == null) return value(source);
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return ar ? 'الآن' : 'just now';
  final n = delta.inDays > 0
      ? delta.inDays
      : delta.inHours > 0
      ? delta.inHours
      : delta.inMinutes;
  final unit = delta.inDays > 0
      ? (ar ? 'يوم' : 'day')
      : delta.inHours > 0
      ? (ar ? 'ساعة' : 'hour')
      : (ar ? 'دقيقة' : 'minute');
  return ar ? 'منذ $n $unit' : '$n $unit${n == 1 ? '' : 's'} ago';
}

class WebHome extends StatefulWidget {
  const WebHome({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebHome> createState() => _WebHomeState();
}

String _postSearchTerm(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

class _WebHomeState extends State<WebHome> {
  /// Home search matches post text only and runs on the server, across every
  /// post the viewer may see (not just the loaded ones).
  late String search = _postSearchTerm(
    Uri.parse(widget.page.path).queryParameters['q'] ?? '',
  );
  late final _searchField = TextEditingController(text: search);
  Timer? _searchTimer;

  void _searchChanged(String value) {
    final term = _postSearchTerm(value);
    if (term == search) return;
    setState(() => search = term);
    _searchTimer?.cancel();
    if (term.runes.length == 1) return;
    _searchTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || term != search) return;
      p.load(
        term.isEmpty
            ? '/community'
            : '/community?q=${Uri.encodeQueryComponent(term)}',
      );
    });
  }

  final _feedKey = GlobalKey();
  final _showAdd = ValueNotifier<bool>(false);
  bool _checkQueued = false;
  double _bottomClearance = 0;
  double? _cachedFeedOffset;
  double _clampedPullPixels = 0;
  RefreshIndicatorStatus? _refreshStatus;
  bool get _holdingRefresh =>
      _refreshStatus == RefreshIndicatorStatus.armed ||
      _refreshStatus == RefreshIndicatorStatus.snap ||
      _refreshStatus == RefreshIndicatorStatus.refresh;

  void _updateFeedVisibilityFromOffset(
    double feedOffset,
    double pixels,
    double viewportDimension,
  ) {
    final visible =
        pixels > 0 &&
        feedOffset - pixels < viewportDimension - _bottomClearance;
    if (_showAdd.value != visible) _showAdd.value = visible;
  }

  void _checkFeedVisibility() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (!mounted) return;
      final scroll = PrimaryScrollController.maybeOf(context);
      final marker = _feedKey.currentContext?.findRenderObject();
      if (scroll == null ||
          !scroll.hasClients ||
          marker is! RenderBox ||
          !marker.attached ||
          !marker.hasSize) {
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(marker);
      if (viewport == null) return;
      final feedOffset = viewport.getOffsetToReveal(marker, 0).offset;
      _cachedFeedOffset = feedOffset;
      final position = scroll.position;
      _updateFeedVisibilityFromOffset(
        feedOffset,
        position.pixels,
        position.viewportDimension,
      );
    });
  }

  @override
  void dispose() {
    _showAdd.dispose();
    _searchTimer?.cancel();
    _searchField.dispose();
    super.dispose();
  }

  NativePageState get p => widget.page;
  Future<void> compose() async {
    final changed = await pushPostComposerRoute(context, page: p);
    if (changed == true) await p.load();
  }

  Widget section(String title, String subtitle, {double size = 24}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: size,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(fontSize: 14, height: 1.5, color: webMuted(context)),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final c = p.c;
    final searching = search.isNotEmpty;
    final shortSearch = searching && search.runes.length < 2;
    // The path changes when a request starts; data.search identifies the
    // completed results, including when an older request finishes mid-debounce.
    final waitingForPosts =
        !shortSearch && _postSearchTerm(value(p.data['search'])) != search;
    final events = rows(p.data['featured_events']);
    final communities = rows(p.data['communities']);
    final posts = shortSearch || waitingForPosts
        ? <Json>[]
        : rows(p.data['posts']);
    _bottomClearance = MediaQuery.paddingOf(context).bottom + 12;
    _cachedFeedOffset = null;
    _checkFeedVisibility();
    final headerItems = <Widget>[
      Semantics(
        button: true,
        label: c.t('What’s on your mind?', 'إيه اللي في بالك؟'),
        child: GestureDetector(
          onTap: compose,
          child: Container(
            height: 70,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: webSecondary(context),
              border: Border.all(color: webBorder(context)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 16,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  p.avatar(c.user ?? {}, radius: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.t('What’s on your mind?', 'إيه اللي في بالك؟'),
                      style: TextStyle(fontSize: 14, color: webMuted(context)),
                      textDirection: c.settings.language == 'ar'
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(child: WebIcon('plus', size: 20)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      TextField(
        key: const ValueKey('home.search'),
        textDirection: contentDirection(search),
        controller: _searchField,
        onChanged: _searchChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: c.t('Search posts…', 'دوّر في المنشورات…'),
          hintStyle: TextStyle(color: webMuted(context), fontSize: 16),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(16),
            child: WebIcon('search', size: 20, color: webMuted(context)),
          ),
          suffixIcon: searching
              ? IconButton(
                  tooltip: c.t('Clear search', 'امسح البحث'),
                  onPressed: () {
                    _searchField.clear();
                    _searchChanged('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 20),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff1a1a1a)
              : const Color(0xfff3f4f6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 48),
      if (object(p.data['scheduleSummary']).isNotEmpty) ...[
        HomeScheduleCard(
          schedule: object(p.data['scheduleSummary']),
          controller: c,
        ),
      ],
      section(
        c.t('Upcoming Events', 'ايفنتات جاية'),
        c.t("Don't miss out on campus activities", 'ماتفوتش أنشطة الجامعة'),
      ),
      const SizedBox(height: 40),
      if (events.isEmpty)
        Text(
          c.t('No upcoming events.', 'لا توجد ايفنتات قادمة.'),
          style: TextStyle(color: webMuted(context)),
        )
      else
        SizedBox(
          height: 182,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 24),
            itemBuilder: (_, i) => event(events[i]),
          ),
        ),
      const SizedBox(height: 72),
      // The button sits beside the heading when it fits and drops below it on
      // narrow screens or with large text, instead of overflowing.
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 12,
        runSpacing: 14,
        children: [
          section(
            c.t('Featured Communities', 'مجتمعات مميزة'),
            c.t('Join and grow with like-minded peers', 'انضم واكبر مع زمايلك'),
          ),
          OutlinedButton.icon(
            onPressed: () => c.open('/community/subjects'),
            icon: WebIcon(
              'sliders',
              size: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(c.t('Edit subjects', 'تعديل المواد')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              backgroundColor: webSecondary(context),
              side: BorderSide(color: webBorder(context)),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      if (communities.isEmpty && yes(p.data['has_communities']))
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            c.t('You turned off all subjects.', 'انت قافل كل المواد.'),
            style: TextStyle(color: webMuted(context), fontSize: 14),
          ),
        ),
      const SizedBox(height: 40),
      if (communities.isNotEmpty)
        SizedBox(
          height: 312,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: communities.length,
            separatorBuilder: (_, _) => const SizedBox(width: 24),
            itemBuilder: (_, i) => community(communities[i]),
          ),
        ),
      const SizedBox(height: 92),
      _FeedHeading(
        key: _feedKey,
        child: section(
          searching
              ? c.t('Search results', 'نتائج البحث')
              : c.t('Community feed', 'منشورات المجتمع'),
          searching
              ? c.t('Community posts', 'منشورات المجتمع')
              : c.t(
                  'Share a thought. Start a conversation.',
                  'شارك فكرة وافتح كلام مع أصحابك.',
                ),
          size: 20,
        ),
      ),
      const SizedBox(height: 16),
    ];
    final feedHeadingIndex = headerItems.length - 2;
    if (searching) {
      // Keep the field at its existing child index so entering search does
      // not recreate it or dismiss the keyboard. Empty Home is unchanged.
      for (var i = 0; i < feedHeadingIndex; i++) {
        if (i != 2) headerItems[i] = const SizedBox.shrink();
      }
      headerItems[3] = const SizedBox(height: 24);
    }
    final postItemCount = posts.isEmpty ? 1 : posts.length;
    final totalCount = headerItems.length + postItemCount + 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical) {
              _cachedFeedOffset = null;
              _checkFeedVisibility();
            }
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical) {
                final pixels = notification.metrics.pixels;
                if (notification is ScrollEndNotification) {
                  _clampedPullPixels = 0;
                  if (!_holdingRefresh) p.homePullProgress.value = 0;
                } else if (pixels < 0) {
                  _clampedPullPixels = 0;
                  final progress = (-pixels / 76.0).clamp(0.0, 1.0);
                  if ((p.homePullProgress.value - progress).abs() > 0.005 ||
                      progress == 0) {
                    p.homePullProgress.value = progress;
                  }
                } else if (notification is OverscrollNotification &&
                    notification.overscroll < 0 &&
                    pixels <= 0) {
                  _clampedPullPixels =
                      (_clampedPullPixels - notification.overscroll).clamp(
                        0.0,
                        120.0,
                      );
                  final progress = (_clampedPullPixels / 76.0).clamp(0.0, 1.0);
                  if ((p.homePullProgress.value - progress).abs() > 0.005) {
                    p.homePullProgress.value = progress;
                  }
                } else {
                  _clampedPullPixels = 0;
                  if (!_holdingRefresh && p.homePullProgress.value != 0) {
                    p.homePullProgress.value = 0;
                  }
                }
                final cached = _cachedFeedOffset;
                if (cached != null) {
                  _updateFeedVisibilityFromOffset(
                    cached,
                    pixels,
                    notification.metrics.viewportDimension,
                  );
                } else {
                  _checkFeedVisibility();
                }
              }
              return false;
            },
            child: RefreshIndicator.noSpinner(
              onRefresh: p.refreshHome,
              onStatusChange: (status) {
                _refreshStatus = status;
                if (status == RefreshIndicatorStatus.armed) {
                  p.homePullProgress.value = 1;
                } else if ((status == null ||
                        status == RefreshIndicatorStatus.canceled ||
                        status == RefreshIndicatorStatus.done) &&
                    !p.homeRefreshing.value) {
                  p.homePullProgress.value = 0;
                }
              },
              child: ListView.custom(
                padding: const EdgeInsets.fromLTRB(10, 40, 10, 180),
                physics: const AlwaysScrollableScrollPhysics(),
                // Build (and start loading photos for) posts about a screen
                // ahead, so a fast fling doesn't reach unbuilt rows.
                scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                childrenDelegate: _HomeChildrenDelegate(
                  (context, index) {
                    if (index < headerItems.length) {
                      return headerItems[index];
                    }
                    final postIndex = index - headerItems.length;
                    if (posts.isEmpty && postIndex == 0) {
                      if (shortSearch) {
                        return p.empty(
                          c.t(
                            'Type at least 2 characters to search posts.',
                            'اكتب حرفين على الأقل للبحث في المنشورات.',
                          ),
                        );
                      }
                      if (waitingForPosts) {
                        return const PostSkeleton(
                          key: ValueKey('home.search.loading'),
                        );
                      }
                      return p.empty(
                        searching
                            ? c.t(
                                'No posts match your search.',
                                'مفيش منشورات بتطابق بحثك.',
                              )
                            : c.t(
                                'No posts yet. Be the first to share a thought.',
                                'لسه مفيش منشورات. شارك أول فكرة.',
                              ),
                      );
                    }
                    if (postIndex < posts.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: WebPostCard(page: p, post: posts[postIndex]),
                      );
                    }
                    // Search results are paginated by the server too.
                    return shortSearch || waitingForPosts
                        ? const SizedBox.shrink()
                        : p.more('posts');
                  },
                  childCount: totalCount,
                  feedHeadingIndex: feedHeadingIndex,
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showAdd,
          builder: (context, visible, _) => WebFloatingAdd(
            key: const ValueKey('home.feed.add'),
            dockHidden: c.dockHidden,
            label: c.t('Create post', 'إنشاء منشور'),
            onTap: compose,
            visible: visible && !searching,
            animate: true,
          ),
        ),
      ],
    );
  }

  Widget photo(String url, {BoxFit fit = BoxFit.cover}) {
    final cacheWidth = (280 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return networkImage(
      p.c.api.media(url),
      fit: fit,
      width: double.infinity,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => networkImage(
        p.c.api.media('/Picture/banner-1517694712202-14dd9538aa97.jpg'),
        fit: fit,
        width: double.infinity,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => ColoredBox(color: webSecondary(context)),
      ),
    );
  }

  Widget event(Json item) {
    final parsed = DateTime.tryParse(value(item['event_date']));
    return GestureDetector(
      onTap: () => showWebEvent(context, p, item),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          border: Border.all(color: webBorder(context)),
          borderRadius: BorderRadius.circular(32),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo(
              value(
                item['image_url'],
                '/Picture/banner-1517694712202-14dd9538aa97.jpg',
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xcc000000)],
                  stops: [.4, 1],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parsed == null
                        ? ''
                        : DateFormat(
                            'MMM dd, yyyy',
                          ).format(parsed).toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xccffffff),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value(item['title']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.25,
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

  Widget community(Json item) => GestureDetector(
    onTap: () => p.c.open('/forum?community_id=${item['id']}'),
    child: Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff121212)
            : Colors.white,
        border: Border.all(color: webBorder(context)),
        borderRadius: BorderRadius.circular(32),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            width: 280,
            child: photo(value(item['image_url'])),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value(item['name']),
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value(item['description']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: webMuted(context),
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

// Apply keep-alive before the first layout, including a cached visit restored
// below the heading. AutomaticKeepAlive defers its initial parent-data update
// until after layout, which is too late for a heading already off screen.
class _HomeChildrenDelegate extends SliverChildBuilderDelegate {
  _HomeChildrenDelegate(
    super.builder, {
    required int childCount,
    required this.feedHeadingIndex,
  }) : super(childCount: childCount);
  final int feedHeadingIndex;
  @override
  Widget? build(BuildContext context, int index) {
    if (index == feedHeadingIndex) {
      final child = builder(context, index);
      if (child == null) return null;
      return KeepAlive(
        keepAlive: true,
        child: RepaintBoundary(
          child: IndexedSemantics(index: index, child: child),
        ),
      );
    }
    return super.build(context, index);
  }
}

class _FeedHeading extends StatelessWidget {
  const _FeedHeading({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

Future<void> showWebPostOptions(
  BuildContext context,
  NativePageState p,
  Json post, {
  BuildContext? anchorContext,
  Rect? anchorRect,
}) async {
  final c = p.c;
  final own = '${post['user_id']}' == '${c.user?['id']}';
  final option = await showAppMenu<String>(
    useRootNavigator: true,
    context: context,
    anchorContext: anchorContext ?? context,
    anchorRect: anchorRect,
    color: webSecondary(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: webBorder(context)),
    ),
    items: [
      for (final item in [
        ('share', 'share', c.t('Share post', 'مشاركة المنشور')),
        ('report', 'flag', c.t('Report post', 'الإبلاغ عن المنشور')),
        if (own) ...[
          ('edit', 'edit', c.t('Edit post', 'تعديل المنشور')),
          (
            'privacy',
            yes(post['is_private']) ? 'globe' : 'lock',
            yes(post['is_private'])
                ? c.t('Make public', 'تغيير إلى عام')
                : c.t('Make private', 'تغيير إلى خاص'),
          ),
          ('delete', 'delete', c.t('Delete', 'حذف')),
        ],
        // Moderators can remove other members' public posts (after confirming).
        if (!own && c.permission('feed.moderate') && !yes(post['is_private']))
          ('delete', 'delete', c.t('Delete', 'حذف')),
      ])
        PopupMenuItem(
          value: item.$1,
          child: Row(
            children: [
              WebIcon(
                item.$2,
                color: ['report', 'delete'].contains(item.$1)
                    ? const Color(0xffc53d46)
                    : null,
              ),
              const SizedBox(width: 12),
              Text(item.$3, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
    ],
  );
  if (!context.mounted) return;
  if (option == 'edit') {
    final changed = await pushPostComposerRoute(context, page: p, post: post);
    if (changed == true) await p.load();
  } else if (option == 'privacy') {
    await p.run('PATCH', '/community/posts/${post['id']}/visibility', {
      'visibility': yes(post['is_private']) ? 'public' : 'private',
    });
  } else if (option == 'delete') {
    await deleteWebPost(context, p, post);
  } else if (option == 'report') {
    await p.report('/community/posts/${post['id']}/reports');
  } else if (option == 'share') {
    final link = c.api.media('/community/posts/${post['id']}');
    if (await shareNative(link, c.t('Post', 'منشور'))) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: webBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.t('Share post', 'مشاركة المنشور'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              SelectableText(link, style: TextStyle(color: webMuted(context))),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(c.t('Copy link', 'نسخ الرابط')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(c.t('Close', 'إغلاق')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebPostDetail extends StatefulWidget {
  const WebPostDetail({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebPostDetail> createState() => _WebPostDetailState();
}

class _WebPostDetailState extends State<WebPostDetail> {
  final content = TextEditingController();
  final focus = FocusNode();
  final focusedComment = GlobalKey();
  String? lastFocusedComment;
  bool focusScheduled = false;
  Json? sticker;
  bool sending = false;
  String? error;
  NativePageState get p => widget.page;
  String? get focusedCommentId {
    final uri = Uri.parse(p.path);
    return uri.queryParameters['focus_comment'] ??
        RegExp(r'^comment-(\d+)$').firstMatch(uri.fragment)?.group(1);
  }

  void revealFocusedComment() {
    final id = focusedCommentId;
    if (id == null || focusScheduled || lastFocusedComment == id) return;
    focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusScheduled = false;
      if (!mounted) return;
      final target = focusedComment.currentContext;
      if (target == null) return;
      lastFocusedComment = id;
      Scrollable.ensureVisible(
        target,
        alignment: .12,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (Uri.parse(p.path).queryParameters['comment'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    content.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending || content.text.trim().isEmpty && sticker == null) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await p.c.action(
        'POST',
        '/community/posts/${object(p.data['post'])['id']}/comments',
        {
          'comment_content': content.text.trim(),
          'comment_context': 'detail',
          if (sticker != null) 'sticker_id': sticker!['id'],
        },
      );
      content.clear();
      if (mounted) setState(() => sticker = null);
      await p.load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> chooseSticker() async {
    final selected = await showDialog<Json>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        backgroundColor: webSecondary(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: webBorder(context)),
        ),
        child: SizedBox(
          width: 360,
          height: 350,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.c.t('Stickers', 'الملصقات'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(p.c.t('Close', 'إغلاق')),
                    ),
                  ],
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      for (final s in rows(p.data['stickers']))
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx, s),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              border: Border.all(color: webBorder(context)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: networkImage(
                              // Picker cells are small; never decode full size.
                              cacheWidth: 200,
                              p.c.api.media(value(s['url'])),
                              errorBuilder: (_, _, _) => const SizedBox(),
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
    );
    if (selected != null && mounted) setState(() => sticker = selected);
  }

  @override
  Widget build(BuildContext context) {
    final comments = rows(p.data['comments']);
    final root = object(p.data['threadRoot']);
    revealFocusedComment();
    final loadedIds = comments.map((comment) => '${comment['id']}').toSet();
    final detached = root.isEmpty
        ? comments
        : comments
              .where(
                (comment) =>
                    '${comment['parent_id']}' != '${root['id']}' &&
                    !loadedIds.contains('${comment['parent_id']}'),
              )
              .toList();
    Widget commentNode(Json comment, {bool connectNext = false}) =>
        WebThreadComment(
          key: '${comment['id']}' == focusedCommentId ? focusedComment : null,
          page: p,
          comment: comment,
          focusedCommentId: focusedCommentId,
          focusedCommentKey: focusedComment,
          connectNext: connectNext,
        );
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: p.pullRefresh,
            child: () {
              final items = <Widget>[
                WebPostCard(
                  page: p,
                  post: object(p.data['post']),
                  detail: true,
                ),
                const SizedBox(height: 16),
                if (root.isNotEmpty) ...[
                  TextButton(
                    onPressed: () => p.load(
                      '/community/posts/${object(p.data['post'])['id']}',
                    ),
                    child: Text(p.c.t('All comments', 'كل التعليقات')),
                  ),
                  commentNode({
                    ...root,
                    'thread_replies': comments,
                  }, connectNext: detached.isNotEmpty),
                ],
                for (final (index, comment) in detached.indexed)
                  if (root.isEmpty)
                    commentNode(
                      comment,
                      connectNext: index < detached.length - 1,
                    )
                  else
                    CommentReplyBranch(
                      continues: index < detached.length - 1,
                      color: webBorder(context),
                      child: commentNode({
                        ...comment,
                        'thread_replies': comments,
                      }),
                    ),
                if (p.provisional && p.data['comments'] == null)
                  const CommentsSkeleton()
                else if (comments.isEmpty && root.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        WebIcon('message', size: 32, color: webMuted(context)),
                        const SizedBox(height: 16),
                        Text(
                          p.c.t('No comments yet', 'لا توجد تعليقات حتى الآن'),
                          style: TextStyle(
                            color: webMuted(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                p.more('comments', compact: true),
              ];
              const padding = EdgeInsets.fromLTRB(10, 12, 10, 24);
              const physics = AlwaysScrollableScrollPhysics();
              // A deep link to one comment needs it built to scroll to it;
              // otherwise only the visible comments are built and laid out.
              return focusedCommentId == null
                  ? ListView(
                      padding: padding,
                      physics: physics,
                      children: items,
                    )
                  : SingleChildScrollView(
                      padding: padding,
                      physics: physics,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: items,
                      ),
                    );
            }(),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (sticker != null)
                  Row(
                    children: [
                      networkImage(
                        p.c.api.media(value(sticker!['url'])),
                        width: 64,
                        height: 64,
                      ),
                      TextButton(
                        onPressed: () => setState(() => sticker = null),
                        child: Text(p.c.t('Remove sticker', 'إزالة الملصق')),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    p.avatar(p.c.user ?? {}, radius: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AdaptiveTextField(
                        controller: content,
                        field: (direction) => TextField(
                          controller: content,
                          textDirection: direction,
                          focusNode: focus,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          style: const TextStyle(fontSize: 16, height: 1.35),
                          decoration: InputDecoration(
                            hintText: p.c.t(
                              'Write a comment...',
                              'اكتب تعليقًا...',
                            ),
                            counterText: '',
                            filled: true,
                            fillColor: webSecondary(context),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 44,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: chooseSticker,
                        icon: Icon(
                          Icons.sticky_note_2_outlined,
                          size: 22,
                          color: webMuted(context),
                        ),
                        tooltip: p.c.t('Stickers', 'الملصقات'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: IconButton.filled(
                        onPressed: sending ? null : send,
                        style: IconButton.styleFrom(
                          backgroundColor: p.c.settings.accent,
                        ),
                        icon: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const WebIcon(
                                'send',
                                size: 23,
                                color: Colors.white,
                              ),
                        tooltip: p.c.t('Send comment', 'إرسال التعليق'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WebThreadComment extends StatelessWidget {
  const WebThreadComment({
    super.key,
    required this.page,
    required this.comment,
    this.depth = 0,
    this.connectNext = false,
    this.focusedCommentId,
    this.focusedCommentKey,
  });
  final NativePageState page;
  final Json comment;
  final int depth;
  final bool connectNext;
  final String? focusedCommentId;
  final GlobalKey? focusedCommentKey;
  @override
  Widget build(BuildContext context) {
    final p = page, c = page.c, person = object(comment['author']);
    final endpoint =
        '/community/posts/${object(p.data['post'])['id']}/comments/${comment['id']}';
    final own = '${comment['user_id']}' == '${c.user?['id']}';
    final replies = rows(comment['thread_replies']);
    final children = depth < 4
        ? replies
              .where((reply) => '${reply['parent_id']}' == '${comment['id']}')
              .toList()
        : <Json>[];
    Widget node(Json item, int nextDepth) => WebThreadComment(
      key: '${item['id']}' == focusedCommentId ? focusedCommentKey : null,
      page: p,
      comment: item,
      depth: nextDepth,
      focusedCommentId: focusedCommentId,
      focusedCommentKey: focusedCommentKey,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommentThreadRail(
          key: ValueKey('comment.rail.${comment['id']}'),
          visible: connectNext || children.isNotEmpty,
          color: webBorder(context),
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      key: ValueKey('comment.avatar.${comment['id']}'),
                      onTap: () => c.open('/users/${person['id']}'),
                      child: p.avatar(person, radius: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => c.open('/users/${person['id']}'),
                            child: Text(
                              value(
                                person['name'],
                                c.t('Deleted user', 'عضو محذوف'),
                              ),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${webAgo(comment['created_at'], c.settings.language == 'ar')}${comment['edited_at'] != null ? c.t(' · edited', ' · معدل') : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: webMuted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: AppPopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Text(
                          '⋯',
                          style: TextStyle(
                            fontSize: 25,
                            color: webMuted(context),
                          ),
                        ),
                        onSelected: (choice) async {
                          if (choice == 'edit') {
                            await editWebComment(context, p, comment, endpoint);
                          } else if (choice == 'delete') {
                            await deleteWebComment(
                              context,
                              p,
                              comment,
                              endpoint,
                            );
                          } else if (choice == 'report') {
                            await p.report('$endpoint/reports');
                          }
                        },
                        itemBuilder: (_) => [
                          if (own)
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(c.t('Edit comment', 'تعديل التعليق')),
                            ),
                          if (!own)
                            PopupMenuItem(
                              value: 'report',
                              child: Text(
                                c.t('Report comment', 'إبلاغ عن التعليق'),
                              ),
                            ),
                          if (own ||
                              c.permission('communities.manage') ||
                              c.permission('feed.moderate'))
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(c.t('Delete comment', 'حذف التعليق')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(54, 6, 0, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (value(comment['content']).isNotEmpty)
                        Text(
                          value(comment['content']),
                          textDirection: contentDirection(
                            value(comment['content']),
                          ),
                          style: const TextStyle(fontSize: 16, height: 1.6),
                        ),
                      if (value(comment['sticker_id']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: networkImage(
                            c.api.media(
                              '/comment-stickers/${comment['sticker_id']}.webp',
                            ),
                            width: 128,
                            height: 128,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        ),
                      WebCommentReactions(
                        page: p,
                        comment: comment,
                        endpoint: '$endpoint/reactions',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final (index, reply) in children.indexed)
          CommentReplyBranch(
            key: ValueKey('comment.branch.${reply['id']}'),
            continues: index < children.length - 1 || connectNext,
            color: webBorder(context),
            child: node({...reply, 'thread_replies': replies}, depth + 1),
          ),
        if ((int.tryParse(value(comment['thread_replies_count'])) ?? 0) >
            replies.length)
          CommentThreadRail(
            visible: connectNext,
            color: webBorder(context),
            top: 0,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 54),
              child: TextButton(
                onPressed: () => c.open(
                  '/community/posts/${object(p.data['post'])['id']}?thread=${comment['id']}',
                ),
                child: Text(c.t('View more replies', 'عرض المزيد من الردود')),
              ),
            ),
          ),
      ],
    );
  }
}

class WebCommentReactions extends StatelessWidget {
  const WebCommentReactions({
    super.key,
    required this.page,
    required this.comment,
    required this.endpoint,
  });
  final NativePageState page;
  final Json comment;
  final String endpoint;
  @override
  Widget build(BuildContext context) {
    final selected = rows(comment['reactions']).firstOrNull?['type'];
    final total = ['like', 'love', 'funny'].fold<int>(
      0,
      (n, k) => n + (int.tryParse(value(comment['${k}_count'])) ?? 0),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          WebReactionButton(
            key: ValueKey('reaction.comment.${comment['id']}'),
            selected: selected is String ? selected : null,
            onSelected: (reaction) => page.react(endpoint, comment, reaction),
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(
                '$total',
                style: TextStyle(color: webMuted(context), fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class WebPostCard extends StatefulWidget {
  const WebPostCard({
    super.key,
    required this.page,
    required this.post,
    this.detail = false,
  });
  final NativePageState page;
  final Json post;
  final bool detail;
  @override
  State<WebPostCard> createState() => _WebPostCardState();
}

class _WebPostCardState extends State<WebPostCard> {
  NativePageState get p => widget.page;
  Json get post => widget.post;
  Json get author => object(post['author']).isNotEmpty
      ? object(post['author'])
      : object(p.data['profile_user']).isNotEmpty
      ? object(p.data['profile_user'])
      : {'id': post['user_id'], 'name': post['name'], 'avatar': post['avatar']};
  static final _postSvgCache = <String, String>{};

  /// Open the post detail, rendering this row immediately while the full
  /// document (with comments) loads.
  void openPost([String query = '']) => p.c.open(
    '/community/posts/${post['id']}$query',
    seed: {
      'screen': 'community.post',
      'data': {
        'post': {...post, 'author': author},
        'comments': null,
        'threadRoot': null,
      },
    },
  );

  Widget svg(String path, {double size = 20, Color? color}) {
    final ink = color ?? webMuted(context);
    final raw = _postSvgCache.putIfAbsent(
      path,
      () =>
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="$path"/></svg>',
    );
    return SvgPicture.string(
      raw,
      width: size,
      height: size,
      colorFilter: svgColorFilter(ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c, detail = widget.detail;
    final selected = rows(post['reactions']).firstOrNull?['type'];
    final total = ['like', 'love', 'funny'].fold<int>(
      0,
      (n, k) => n + (int.tryParse(value(post['${k}_count'])) ?? 0),
    );
    final previews = rows(post['recent_comment_previews']);
    final muted = webMuted(context);
    final surface = webSecondary(context);
    return Container(
      decoration: BoxDecoration(
        color: detail ? Theme.of(context).scaffoldBackgroundColor : surface,
        border: detail ? null : Border.all(color: webBorder(context)),
        borderRadius: BorderRadius.circular(detail ? 0 : 12),
      ),
      padding: EdgeInsets.fromLTRB(
        detail ? 0 : 16,
        detail ? 0 : 16,
        detail ? 0 : 16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => c.open('/users/${author['id']}'),
                child: p.avatar(author, radius: detail ? 21 : 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => c.open('/users/${author['id']}'),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 3,
                        children: [
                          Text(
                            value(
                              author['name'],
                              c.t('Deleted user', 'عضو محذوف'),
                            ),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          UserBadge(api: c.api, badge: author['badge']),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          webAgo(
                            post['created_at'],
                            c.settings.language == 'ar',
                          ),
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xff202020)
                                : const Color(0xffe5f1e7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            yes(post['is_private'])
                                ? c.t('Private', 'خاص')
                                : c.t('Public', 'عام'),
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.6,
                              color:
                                  yes(post['is_private']) ||
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                  ? muted
                                  : const Color(0xff47734a),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!detail)
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Builder(
                    builder: (buttonContext) => GestureDetector(
                      onTap: () => showWebPostOptions(
                        context,
                        p,
                        post,
                        anchorContext: buttonContext,
                      ),
                      child: Center(
                        child: Text(
                          '⋯',
                          style: TextStyle(
                            fontSize: 25,
                            height: 1,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GestureDetector(
            // Start fetching on touch-down; the tap renders the post at once.
            onTapDown: detail
                ? null
                : (_) => c.prefetch('/community/posts/${post['id']}'),
            onTap: detail ? null : () => openPost(),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                0,
                detail ? 18 : 12,
                0,
                detail ? 24 : 16,
              ),
              child: Text(
                value(post['content']),
                textDirection: contentDirection(value(post['content'])),
                maxLines: detail ? null : 5,
                overflow: detail ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: detail ? 18 : 16,
                  height: detail ? 1.7 : 1.65,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: webBorder(context))),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                WebReactionButton(
                  key: ValueKey('reaction.post.${post['id']}'),
                  selected: selected is String ? selected : null,
                  onSelected: (reaction) => p.react(
                    '/community/posts/${post['id']}/reactions',
                    post,
                    reaction,
                  ),
                ),
                const SizedBox(width: 8),
                actionButton(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      svg(
                        'M21 11.5a8.5 8.5 0 0 1-8.5 8.5 9 9 0 0 1-4-.9L3 21l1.8-5.2a8.5 8.5 0 1 1 16.2-4.3ZM8 12h.01M12 12h.01M16 12h.01',
                      ),
                      if ((int.tryParse(value(post['comments_count'])) ?? 0) >
                          0) ...[
                        const SizedBox(width: 8),
                        Text(
                          value(post['comments_count']),
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ],
                  ),
                  label: c.t('Comments', 'التعليقات'),
                  onTap: detail ? null : () => openPost('?comment=1'),
                ),
                const Spacer(),
                if (total > 0) ...[
                  for (final pair in [
                    ('like', '👍'),
                    ('love', '❤️'),
                    ('funny', '😂'),
                  ])
                    if ((int.tryParse(value(post['${pair.$1}_count'])) ?? 0) >
                        0)
                      Text(pair.$2, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 7),
                  Text('$total', style: TextStyle(fontSize: 13, color: muted)),
                ],
              ],
            ),
          ),
          if (detail) Divider(height: 1, color: webBorder(context)),
          if (!detail && previews.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 20),
              child: Column(
                children: [for (final comment in previews) preview(comment)],
              ),
            ),
        ],
      ),
    );
  }

  Widget actionButton({
    required Widget child,
    required String label,
    required VoidCallback? onTap,
    bool selected = false,
  }) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xff2e855d).withValues(alpha: .1)
              : Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff202020)
              : const Color(0xfff3f4f6),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(child: child),
      ),
    ),
  );
  Widget preview(Json comment) {
    final person = object(comment['author']);
    void openComment() => p.c.open(
      '/community/posts/${post['id']}?focus_comment=${comment['id']}',
    );
    return Padding(
      key: ValueKey('feed.comment.${comment['id']}'),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openComment,
            child: p.avatar(person, radius: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  key: ValueKey('feed.comment.body.${comment['id']}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: openComment,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            value(person['name']),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          UserBadge(api: p.c.api, badge: person['badge']),
                          Text(
                            webAgo(
                              comment['created_at'],
                              p.c.settings.language == 'ar',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: webMuted(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (value(comment['sticker_id']).isNotEmpty)
                        networkImage(
                          p.c.api.media(
                            '/comment-stickers/${comment['sticker_id']}.webp',
                          ),
                          height: 90,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      if (value(comment['content']).isNotEmpty)
                        Text(
                          value(comment['content']),
                          textDirection: contentDirection(
                            value(comment['content']),
                          ),
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                    ],
                  ),
                ),
                WebCommentReactions(
                  page: p,
                  comment: comment,
                  endpoint:
                      '/community/posts/${post['id']}/comments/${comment['id']}/reactions',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> pushPostComposerRoute(
  BuildContext context, {
  required NativePageState page,
  Json? post,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      fullscreenDialog: true,
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) =>
          WebPostEditor(page: page, post: post),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.of(context).accessibleNavigation) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

class WebPostEditor extends StatefulWidget {
  const WebPostEditor({super.key, required this.page, this.post});
  final NativePageState page;
  final Json? post;
  @override
  State<WebPostEditor> createState() => _WebPostEditorState();
}

class _WebPostEditorState extends State<WebPostEditor> {
  late final TextEditingController text = TextEditingController(
    text: value(widget.post?['content']),
  );
  late String _lastText = text.text;
  late final ValueNotifier<bool> _hasText = ValueNotifier<bool>(
    text.text.trim().isNotEmpty,
  );
  late final ValueNotifier<int> _charCount = ValueNotifier<int>(
    text.text.characters.length,
  );
  late String visibility = yes(widget.post?['is_private'])
      ? 'private'
      : 'public';
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    text.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final current = text.text;
    if (identical(current, _lastText) || current == _lastText) return;
    _lastText = current;
    final hasText = current.trim().isNotEmpty;
    if (_hasText.value != hasText) _hasText.value = hasText;
    _charCount.value = current.characters.length;
  }

  @override
  void dispose() {
    text.removeListener(_onTextChanged);
    _hasText.dispose();
    _charCount.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (text.text.trim().isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.page.c.action(
        widget.post == null ? 'POST' : 'PUT',
        widget.post == null
            ? '/community/posts'
            : '/community/posts/${widget.post!['id']}',
        {
          'content': text.text.trim(),
          'visibility': visibility,
          if (widget.post != null) 'post_id': widget.post!['id'],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.page.c;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      c.t('Cancel', 'إلغاء'),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.post == null
                        ? c.t('Create post', 'إنشاء منشور')
                        : c.t('Edit post', 'تعديل المنشور'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: _hasText,
                    builder: (context, hasText, _) => FilledButton(
                      onPressed: busy || !hasText ? null : publish,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 21,
                          vertical: 8,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        busy
                            ? c.t('Posting…', 'جارٍ النشر…')
                            : c.t('Post', 'نشر'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    widget.page.avatar(c.user ?? {}, radius: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppDropdownButton<String>(
                            value: visibility,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'public',
                                child: Text(c.t('Public', 'عام')),
                              ),
                              DropdownMenuItem(
                                value: 'private',
                                child: Text(c.t('Only me', 'أنا فقط')),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) => setState(() => visibility = v!),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: RepaintBoundary(
                              child: AdaptiveTextField(
                                controller: text,
                                field: (direction) => TextField(
                                  controller: text,
                                  textDirection: direction,
                                  maxLength: 3000,
                                  maxLines: null,
                                  expands: true,
                                  autofocus: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    height: 1.6,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: c.t(
                                      'What’s on your mind?',
                                      'إيه اللي في بالك؟',
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    counterText: '',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (error != null)
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: webBorder(context))),
              ),
              alignment: AlignmentDirectional.centerEnd,
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _charCount,
                  builder: (context, count, _) => Text(
                    '$count / 3,000',
                    style: TextStyle(fontSize: 12, color: webMuted(context)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
