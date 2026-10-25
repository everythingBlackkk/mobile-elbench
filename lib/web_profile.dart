import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'api.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'infinite_feed.dart';
import 'text_direction.dart';
import 'web_style.dart';
import 'native_share.dart';

/// Native counterpart of profile/{show,user}.blade.php and profile.css.
/// The surrounding NativePage supplies the transparent mobile header and nav.
class WebProfile extends StatefulWidget {
  const WebProfile({super.key, required this.page});

  final NativePageState page;

  @override
  State<WebProfile> createState() => _WebProfileState();
}

class _ProfileScope {
  const _ProfileScope(
    this.origin,
    this.viewer,
    this.locale,
    this.profile,
    this.path,
  );
  final String origin, viewer, locale, profile, path;
  String get key => '$origin|$viewer|$locale|$profile';
}

class _ProfilePanel {
  _ProfilePanel(this.items, this.destination) : validated = DateTime.now();
  final dynamic items;
  final String destination;
  final DateTime validated;
}

class _WebProfileState extends State<WebProfile>
    with TickerProviderStateMixin, RouteAware {
  late final scroll = ScrollController(
    initialScrollOffset: page.scrollOffset.value,
  );
  final stageKey = GlobalKey();
  final panels = <String, _ProfilePanel>{};
  final errors = <String, String>{};
  final pending = <String, Future<void>>{};
  final requestUrls = <String, String>{};
  final latest = <String, int>{};
  final appendingPanels = <String>{};
  final failedAppends = <String>{};
  late final slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );
  late _ProfileScope scope;
  late Json profileData;
  late Json publishedData;
  late String tab;
  int epoch = 0, sequence = 0;
  late int cacheGeneration;
  PageRoute<dynamic>? observedRoute;
  bool _refreshOnResume = false;
  double direction = 1, stageFloor = 0;
  NativePageState get page => widget.page;
  static const tabs = ['posts', 'comments', 'ask'];

  String field(String name) => switch (name) {
    'comments' => 'profile_comments',
    'ask' => 'profile_asks',
    _ => 'profile_posts',
  };

  _ProfileScope captureScope() {
    final viewer = value(page.c.user?['id']);
    final route = Uri.parse(page.path).path;
    final match = RegExp(r'^/users/([0-9]+)/?$').firstMatch(route);
    final id = route == '/profile' ? viewer : match?.group(1) ?? '';
    return _ProfileScope(
      page.c.api.baseUri.origin,
      viewer,
      page.c.settings.language,
      id,
      route == '/profile' ? '/profile' : '/users/$id',
    );
  }

  bool get authorized => scope.viewer.isNotEmpty && scope.profile.isNotEmpty;
  bool get hasIdentity =>
      authorized &&
      value(object(profileData['profile_user'])['id']) == scope.profile &&
      value(object(profileData['profile_user'])['name']).isNotEmpty;

  @override
  void initState() {
    super.initState();
    scope = captureScope();
    cacheGeneration = page.c.cacheGeneration;
    profileData = {...page.data};
    publishedData = page.data;
    tab = tabs.contains(page.data['activityTab'])
        ? value(page.data['activityTab'])
        : 'posts';
    seedPanels();
    stripPanelData();
    page.c.addListener(scopeChanged);
    page.c.settings.addListener(scopeChanged);
    if (!panels.containsKey(tab)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fetchPanel(tab);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = page.pageRoute;
    if (route is PageRoute && route != observedRoute) {
      if (observedRoute != null) page.c.routeObserver.unsubscribe(this);
      observedRoute = route;
      page.c.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (!mounted || page.loading) return;
    if (_refreshOnResume) {
      _refreshOnResume = false;
      fetchPanel(tab, force: true);
      return;
    }
    final cached = panels[tab];
    if (cached != null &&
        DateTime.now().difference(cached.validated) >
            const Duration(seconds: 30)) {
      fetchPanel(tab, force: true);
    }
  }

  void seedPanels() {
    if (!hasIdentity ||
        (page.envelope['locale'] != null &&
            page.envelope['locale'] != scope.locale)) {
      return;
    }
    for (final name in tabs) {
      if (profileData[field(name)] != null) {
        panels[name] = _ProfilePanel(
          profileData[field(name)],
          name == tab ? destination(name, page.path) : destination(name),
        );
      }
    }
  }

  void stripPanelData() {
    for (final name in tabs) {
      profileData.remove(field(name));
    }
  }

  @override
  void didUpdateWidget(WebProfile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.c != page.c) {
      oldWidget.page.c.removeListener(scopeChanged);
      oldWidget.page.c.settings.removeListener(scopeChanged);
      page.c.addListener(scopeChanged);
      page.c.settings.addListener(scopeChanged);
    }
    if (captureScope().key != scope.key ||
        cacheGeneration != page.c.cacheGeneration) {
      resetScope();
    } else if (!identical(publishedData, page.data)) {
      // A retained NativePage may receive a fresh authorized response on resume.
      epoch++;
      _refreshOnResume = false;
      pending.clear();
      requestUrls.clear();
      latest.clear();
      errors.clear();
      panels.clear();
      profileData = {...page.data};
      publishedData = page.data;
      tab = tabs.contains(page.data['activityTab'])
          ? value(page.data['activityTab'])
          : tab;
      seedPanels();
      stripPanelData();
    }
  }

  void scopeChanged() {
    if (!mounted ||
        captureScope().key == scope.key &&
            cacheGeneration == page.c.cacheGeneration) {
      return;
    }
    setState(resetScope);
  }

  void resetScope() {
    final previous = scope;
    scope = captureScope();
    cacheGeneration = page.c.cacheGeneration;
    epoch++;
    pending.clear();
    requestUrls.clear();
    latest.clear();
    errors.clear();
    panels.clear();
    slide.value = arrival.value = 1;
    if (!authorized || previous.profile != scope.profile) {
      profileData = {
        'profile_user': {'id': scope.profile},
        'skills': [],
      };
    }
    stripPanelData();
    publish();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !authorized || page.loading) return;
      if (!(observedRoute?.isCurrent ?? true)) {
        _refreshOnResume = true;
        return;
      }
      fetchPanel(tab, force: true);
    });
  }

  void retainViewport() {
    final render = stageKey.currentContext?.findRenderObject();
    if (render != null && render.attached) {
      final top = MatrixUtils.transformPoint(
        render.getTransformTo(null),
        Offset.zero,
      ).dy;
      stageFloor =
          (MediaQuery.sizeOf(context).height -
                  top -
                  112 -
                  MediaQuery.paddingOf(context).bottom)
              .clamp(0.0, double.infinity);
    }
  }

  String destination(String name, [String? pagination]) {
    final params = pagination == null
        ? <String, String>{}
        : {...Uri.parse(pagination).queryParameters};
    final pageParameter = '${name == 'ask' ? 'ask' : name}_page';
    params.removeWhere((key, _) => key != pageParameter);
    params['tab'] = name;
    return Uri(path: scope.path, queryParameters: params).toString();
  }

  void publish() {
    final data = <String, dynamic>{
      ...profileData,
      'activityTab': tab,
      for (final name in tabs) field(name): panels[name]?.items,
    };
    publishedData = data;
    page.data = data;
    page.envelope = {
      ...page.envelope,
      'user': page.c.user,
      'locale': scope.locale,
      'data': data,
    };
    page.path = panels[tab]?.destination ?? destination(tab);
    if (ModalRoute.of(context)?.isCurrent != false) {
      page.c.currentPath = page.path;
    }
  }

  void selectTab(String next) {
    if (!authorized || !tabs.contains(next) || next == tab) return;
    retainViewport();
    direction =
        (tabs.indexOf(next) > tabs.indexOf(tab) ? 1 : -1) *
        (page.c.settings.language == 'ar' ? -1 : 1);
    setState(() {
      tab = next;
      publish();
    });
    arrival.value = 1;
    if (MediaQuery.disableAnimationsOf(context)) {
      slide.value = 1;
    } else {
      slide.forward(from: 0);
    }
    fetchPanel(next);
  }

  Future<void> fetchPanel(
    String name, {
    String? url,
    bool force = false,
    bool refresh = false,
  }) {
    if (!mounted || !authorized) return Future.value();
    final requestedScope = scope;
    final requestedEpoch = epoch;
    final cached = panels[name];
    final animate = !MediaQuery.disableAnimationsOf(context);
    String target;
    try {
      if (url != null) {
        final safe = Uri.parse(page.c.api.safePath(url));
        if (safe.path != '/users/${scope.profile}' &&
            !(scope.viewer == scope.profile && safe.path == '/profile')) {
          throw const ApiFailure('Activity unavailable');
        }
      }
      target = destination(name, url ?? cached?.destination);
    } catch (_) {
      setState(
        () => errors[name] = page.c.t(
          'Unable to load activity.',
          'تعذّر تحميل النشاط.',
        ),
      );
      return Future.value();
    }
    if (pending[name] != null && requestUrls[name] == target) {
      return pending[name]!;
    }
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.validated) <
            const Duration(seconds: 30)) {
      return Future.value();
    }
    final requestId = ++sequence;
    latest[name] = requestId;
    requestUrls[name] = target;
    setState(() => errors.remove(name));
    late final Future<void> work;
    bool current() =>
        mounted &&
        epoch == requestedEpoch &&
        scope.key == requestedScope.key &&
        captureScope().key == requestedScope.key &&
        latest[name] == requestId;
    work = () async {
      try {
        final response = await page.c.get(target);
        if (!current()) return;
        final updated = object(response['data']);
        final responseViewer = object(response['user']);
        if (!['profile.show', 'profile.user'].contains(response['screen']) ||
            value(object(updated['profile_user'])['id']) !=
                requestedScope.profile ||
            updated['activityTab'] != name ||
            updated[field(name)] == null ||
            response.containsKey('user') &&
                value(responseViewer['id']) != requestedScope.viewer ||
            response['locale'] != null &&
                response['locale'] != requestedScope.locale) {
          throw const ApiFailure('Activity unavailable');
        }
        if (name == tab) retainViewport();
        setState(() {
          final canonical = response['canonical_url'];
          if (canonical is String &&
              requestedScope.viewer == requestedScope.profile &&
              Uri.parse(page.c.api.safePath(canonical)).path == '/profile') {
            scope = _ProfileScope(
              scope.origin,
              scope.viewer,
              scope.locale,
              scope.profile,
              '/profile',
            );
          }
          if (refresh) panels.clear();
          panels[name] = _ProfilePanel(
            updated[field(name)],
            destination(name, target),
          );
          // Metadata/counts arrive from the same authorized profile controller.
          profileData = {...updated};
          stripPanelData();
          errors.remove(name);
          publish();
        });
        if (name == tab && animate && cached == null) {
          arrival.forward(from: 0);
        }
      } catch (_) {
        if (!current()) return;
        setState(() {
          // A failed background revalidation keeps already loaded activity.
          if (panels[name] == null) {
            errors[name] = page.c.t(
              'Unable to load activity.',
              'تعذّر تحميل النشاط.',
            );
          }
        });
      } finally {
        if (current()) {
          setState(() {
            pending.remove(name);
            requestUrls.remove(name);
          });
        }
      }
    }();
    pending[name] = work;
    return work;
  }

  /// Append the next page of an activity tab below the rows already shown.
  Future<void> appendPanel(String name) async {
    final cached = panels[name];
    final next = object(cached?.items)['next_page_url'];
    if (!mounted ||
        !authorized ||
        cached == null ||
        next is! String ||
        appendingPanels.contains(name) ||
        pending[name] != null) {
      return;
    }
    final requestedScope = scope, requestedEpoch = epoch;
    bool current() =>
        mounted &&
        epoch == requestedEpoch &&
        scope.key == requestedScope.key &&
        captureScope().key == requestedScope.key &&
        identical(panels[name], cached);
    String target;
    try {
      target = destination(name, page.c.api.safePath(next));
    } catch (_) {
      return;
    }
    setState(() {
      appendingPanels.add(name);
      failedAppends.remove(name);
    });
    try {
      final response = await page.c.get(target);
      if (!current()) return;
      final updated = object(response['data']);
      if (!['profile.show', 'profile.user'].contains(response['screen']) ||
          value(object(updated['profile_user'])['id']) !=
              requestedScope.profile ||
          updated['activityTab'] != name ||
          updated[field(name)] == null) {
        throw const ApiFailure('Activity unavailable');
      }
      final previous = object(cached.items),
          incoming = object(updated[field(name)]);
      setState(() {
        panels[name] = _ProfilePanel({
          ...incoming,
          'prev_page_url': previous['prev_page_url'],
          'data': mergeRows(rows(previous), rows(incoming)),
        }, cached.destination);
        publish();
      });
    } catch (_) {
      if (current()) setState(() => failedAppends.add(name));
    } finally {
      if (mounted) setState(() => appendingPanels.remove(name));
    }
  }

  @override
  void dispose() {
    page.c.removeListener(scopeChanged);
    page.c.settings.removeListener(scopeChanged);
    page.c.routeObserver.unsubscribe(this);
    scroll.dispose();
    slide.dispose();
    arrival.dispose();
    epoch++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final person = object(profileData['profile_user'] ?? profileData['user']);
    if (!hasIdentity) {
      return ListView(
        key: const ValueKey('profile.loading'),
        controller: scroll,
        padding: EdgeInsets.zero,
        children: [
          Container(height: 184, color: _Colors(context).soft),
          Padding(
            padding: const EdgeInsets.all(34),
            child: errors[tab] != null
                ? _ProfilePanelFailure(
                    page: page,
                    retry: () => fetchPanel(tab, force: true),
                  )
                : _ProfilePanelSkeleton(tab: tab),
          ),
        ],
      );
    }
    final own = '${person['id']}' == '${page.c.user?['id']}';
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= 375;
    final avatarSize = compact ? 94.0 : 116.0;
    final colors = _Colors(context);
    final banner = value(person['banner_url']);
    final skills = rows(profileData['skills']);
    final bio = [
      value(person['job']),
      value(person['major']),
    ].where((s) => s.isNotEmpty).join(' ▪ ');
    final joined = DateTime.tryParse(value(person['created_at']));

    Widget stat(dynamic count, String label) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value(count, '0'),
            style: TextStyle(
              fontSize: compact ? 18 : (width * .05).clamp(18.0, 25.0),
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -.035 * (compact ? 18 : width * .05),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.muted,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    return RefreshIndicator.adaptive(
      onRefresh: () {
        page.c.markAllStale();
        return fetchPanel(tab, force: true, refresh: true);
      },
      child: CustomScrollView(
        key: const ValueKey('profile.scroll'),
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                  child: SizedBox(
                    height: 184,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color:
                              _hex(person['banner_color']) ??
                              const Color(0xff2e855d),
                        ),
                        if (banner.isEmpty)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [colors.soft, colors.accent],
                              ),
                            ),
                          ),
                        if (banner.isNotEmpty)
                          networkImage(
                            page.c.api.media(banner),
                            fit: BoxFit.cover,
                            cacheWidth:
                                (MediaQuery.sizeOf(context).width *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .ceil(),
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [.55, 1],
                              colors: [Colors.transparent, Color(0x1f000000)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 162),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: colors.main,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 70,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PositionedDirectional(
                                start: 0,
                                top: compact ? -47 : -58,
                                child: Container(
                                  width: avatarSize,
                                  height: avatarSize,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: colors.main,
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x1f000000),
                                        offset: Offset(0, 8),
                                        blurRadius: 26,
                                      ),
                                    ],
                                  ),
                                  child: _Avatar(
                                    page: page,
                                    person: person,
                                    size: avatarSize - 8,
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                start: avatarSize + 8,
                                end: 0,
                                bottom: 9,
                                child: Row(
                                  children: [
                                    stat(
                                      page.data['posts_count'],
                                      page.c.t('Posts', 'المنشورات'),
                                    ),
                                    const SizedBox(width: 2),
                                    stat(
                                      page.data['comments_count'],
                                      page.c.t('Comments', 'التعليقات'),
                                    ),
                                    const SizedBox(width: 2),
                                    stat(
                                      page.data['reactions_count'],
                                      page.c.t('Reactions', 'التفاعلات'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                value(person['name']),
                                key: const ValueKey('profile.identity'),
                                style: const TextStyle(
                                  fontSize: 26,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.65,
                                ),
                              ),
                            ),
                            if (_hasBadge(person)) ...[
                              const SizedBox(width: 6),
                              _ProfileBadge(page: page, person: person),
                            ],
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '@${value(person['university_id'])}',
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        _StudyPlacement(page: page, person: person),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.soft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.string(
                                  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3h8v5a4 4 0 0 1-8 0V3Z"/><path d="M8 5H5v2a4 4 0 0 0 4 4m7-6h3v2a4 4 0 0 1-4 4m-3 1v6m-4 3h8m-6-3h4v3"/></svg>',
                                  width: 16,
                                  height: 16,
                                  colorFilter: svgColorFilter(colors.accent),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  NumberFormat.decimalPattern('en').format(
                                    num.tryParse(
                                          value(page.data['user_points'], '0'),
                                        ) ??
                                        0,
                                  ),
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    color: colors.accent,
                                    fontSize: 13,
                                    height: 20 / 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  page.c.t('Points', 'نقطة'),
                                  style: TextStyle(
                                    color: colors.accent,
                                    fontSize: 13,
                                    height: 20 / 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          bio.isEmpty
                              ? page.c.t(
                                  'No information provided',
                                  'مفيش معلومات',
                                )
                              : bio,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 22,
                          runSpacing: 10,
                          children: [
                            if (value(person['city']).isNotEmpty)
                              _ProfileMeta(
                                icon: Icons.location_on,
                                label: value(person['city']),
                              ),
                            if (joined != null)
                              _ProfileMeta(
                                icon: Icons.calendar_month,
                                label:
                                    '${page.c.t('Member since', 'عضو من')} '
                                    '${DateFormat(own ? 'MMMM yyyy' : 'MMM yyyy', 'en').format(joined)}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _PillAction(
                          text: own
                              ? page.c.t('Edit profile', 'تعديل الملف الشخصي')
                              : page.c.t('Ask', 'اسأل'),
                          onTap: own
                              ? () => page.c.open('/profile/edit')
                              : () => showWebAskComposer(context, page, person),
                          profile: true,
                        ),
                        if (skills.isNotEmpty) ...[
                          const SizedBox(height: 48),
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colors.text,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                page.c.t('Skills', 'المهارات'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final skill in skills)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.main,
                                    border: Border.all(color: colors.border),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    value(skill['skill_name']),
                                    style: const TextStyle(
                                      fontSize: 13.6,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              10,
              0,
              10,
              112 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: _ProfileActivity(
              page: page,
              person: person,
              own: own,
              tab: tab,
              source: panels[tab]?.items,
              loading: panels[tab] == null && errors[tab] == null,
              error: errors[tab],
              onSelect: selectTab,
              retry: () => fetchPanel(tab, force: true),
              onNavigate: (url) => fetchPanel(tab, url: url, force: true),
              appending: appendingPanels.contains(tab),
              appendFailed: failedAppends.contains(tab),
              onLoadMore: () => appendPanel(tab),
              stageKey: stageKey,
              stageFloor: stageFloor,
              slide: slide,
              arrival: arrival,
              direction: direction,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActivity extends StatelessWidget {
  const _ProfileActivity({
    required this.page,
    required this.person,
    required this.own,
    required this.tab,
    required this.source,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.retry,
    required this.onNavigate,
    required this.appending,
    required this.appendFailed,
    required this.onLoadMore,
    required this.stageKey,
    required this.stageFloor,
    required this.slide,
    required this.arrival,
    required this.direction,
  });

  final NativePageState page;
  final Json person;
  final bool own;
  final String tab;
  final dynamic source;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSelect;
  final VoidCallback retry;
  final Future<void> Function(String) onNavigate;
  final bool appending, appendFailed;
  final VoidCallback onLoadMore;
  final GlobalKey stageKey;
  final double stageFloor, direction;
  final Animation<double> slide, arrival;

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final items = rows(source);
    final titles = [
      ('posts', 'post', page.c.t('Posts', 'المنشورات')),
      ('comments', 'message', page.c.t('Comments', 'التعليقات')),
      ('ask', 'message', page.c.t('Ask', 'اسأل')),
    ];
    final selectedTabIndex = titles
        .indexWhere((item) => item.$1 == tab)
        .clamp(0, titles.length - 1);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Row(
                  children: [
                    for (final item in titles)
                      Expanded(
                        child: Semantics(
                          selected: item.$1 == tab,
                          button: true,
                          child: InkWell(
                            key: ValueKey('profile.tab.${item.$1}'),
                            onTap: () => onSelect(item.$1),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 15,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (item.$1 != tab) ...[
                                    WebIcon(
                                      item.$2,
                                      size: 17,
                                      color: colors.muted,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
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
                                        fontWeight: FontWeight.w700,
                                        color: item.$1 == tab
                                            ? colors.text
                                            : colors.muted,
                                      ),
                                      child: Text(
                                        item.$3,
                                        maxLines: 1,
                                        overflow: TextOverflow.visible,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                ],
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
                      key: const ValueKey('profile.tab.indicator'),
                      alignment: AlignmentDirectional(
                        -1.0 + 2.0 * selectedTabIndex / (titles.length - 1),
                        1.0,
                      ),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                      child: FractionallySizedBox(
                        widthFactor: 1 / titles.length,
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: .64,
                            child: Container(
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
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        ProfileActivityMotion(
          key: stageKey,
          slide: slide,
          arrival: arrival,
          direction: direction,
          minimumExtent: stageFloor,
          child: SliverMainAxisGroup(
            key: ValueKey('profile.panel.$tab'),
            slivers: [
              if (loading)
                SliverToBoxAdapter(child: _ProfilePanelSkeleton(tab: tab))
              else if (error != null)
                SliverToBoxAdapter(
                  child: _ProfilePanelFailure(page: page, retry: retry),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    padding: const EdgeInsets.all(34),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      switch (tab) {
                        'comments' => page.c.t(
                          'No comments yet.',
                          'لا توجد تعليقات بعد.',
                        ),
                        'ask' => page.c.t(
                          'No published answers yet.',
                          'لسه مفيش إجابات منشورة.',
                        ),
                        _ => page.c.t('No posts yet.', 'لا توجد منشورات بعد.'),
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: colors.muted),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => tab == 'ask'
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AskThread(
                            page: page,
                            item: items[i],
                            person: person,
                            own: own,
                          ),
                        )
                      : Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            border: Border(
                              left: BorderSide(color: colors.border),
                              right: BorderSide(color: colors.border),
                              top: i == 0
                                  ? BorderSide(color: colors.border)
                                  : BorderSide.none,
                              bottom: i == items.length - 1
                                  ? BorderSide(color: colors.border)
                                  : BorderSide.none,
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: i == 0
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                              bottom: i == items.length - 1
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                            ),
                          ),
                          child: _ActivityItem(
                            page: page,
                            item: items[i],
                            person: person,
                            comment: tab == 'comments',
                            first: i == 0,
                            last: i == items.length - 1,
                          ),
                        ),
                ),
              if (!loading && error == null && items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InfiniteScrollFooter(
                      hasMore: object(source)['next_page_url'] is String,
                      loading: appending,
                      failed: appendFailed,
                      onLoadMore: onLoadMore,
                      translate: page.c.t,
                      compact: tab != 'posts',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A paint-only slide over a lazy activity sliver. Offscreen rows are neither
/// built nor laid out, and tab animation does not relayout the list per frame.
class ProfileActivityMotion extends SingleChildRenderObjectWidget {
  const ProfileActivityMotion({
    super.key,
    required this.slide,
    required this.arrival,
    required this.direction,
    required this.minimumExtent,
    required super.child,
  });
  final Animation<double> slide, arrival;
  final double direction, minimumExtent;
  double get horizontalShift =>
      direction * 48 * (1 - const Cubic(.22, 1, .36, 1).transform(slide.value));
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderActivityMotion(this);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderActivityMotion).update(this);
  }
}

class _RenderActivityMotion extends RenderProxySliver {
  _RenderActivityMotion(this.options);
  ProfileActivityMotion options;
  @override
  bool get alwaysNeedsCompositing => true;
  void update(ProfileActivityMotion next) {
    if (attached) _listen(false);
    final needsLayout = options.minimumExtent != next.minimumExtent;
    options = next;
    if (attached) _listen(true);
    if (needsLayout) markNeedsLayout();
    markNeedsPaint();
  }

  void _listen(bool add) {
    for (final animation in [options.slide, options.arrival]) {
      if (add) {
        animation.addListener(markNeedsPaint);
      } else {
        animation.removeListener(markNeedsPaint);
      }
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen(true);
  }

  @override
  void detach() {
    _listen(false);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    final old = geometry!;
    final extent = math.max(old.scrollExtent, options.minimumExtent);
    final paint = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = old.copyWith(
      scrollExtent: extent,
      maxPaintExtent: math.max(old.maxPaintExtent, extent),
      paintExtent: paint,
      layoutExtent: paint,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hasVisualOverflow:
          old.hasVisualOverflow || extent > constraints.remainingPaintExtent,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final shift = options.horizontalShift;
    final alpha =
        ((.4 + .6 * Curves.easeOut.transform(options.arrival.value)) * 255)
            .round();
    void draw(PaintingContext context, Offset offset) =>
        context.paintChild(child!, offset + Offset(shift, 0));
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent),
      (context, offset) {
        if (alpha == 255) {
          draw(context, offset);
        } else {
          context.pushOpacity(offset, alpha, draw);
        }
      },
      oldLayer: layer as ClipRectLayer?,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    transform.translateByDouble(options.horizontalShift, 0, 0, 1);
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => super.hitTestChildren(
    result,
    mainAxisPosition: mainAxisPosition,
    crossAxisPosition: crossAxisPosition - options.horizontalShift,
  );
}

class _ProfilePanelFailure extends StatelessWidget {
  const _ProfilePanelFailure({required this.page, required this.retry});
  final NativePageState page;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('profile.activity.error'),
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(page.c.t('Unable to load activity. ', 'تعذّر تحميل النشاط. ')),
        TextButton(
          key: const ValueKey('profile.activity.retry'),
          onPressed: retry,
          child: Text(page.c.t('Try again', 'إعادة المحاولة')),
        ),
      ],
    ),
  );
}

/// The same avatar/body placeholders as profile/partials/activity-skeleton.
class _ProfilePanelSkeleton extends StatelessWidget {
  const _ProfilePanelSkeleton({required this.tab});
  final String tab;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    Widget bar(double width, double height, [double radius = 7]) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return ExcludeSemantics(
      key: const ValueKey('profile.activity.loading'),
      child: Container(
        decoration: BoxDecoration(
          color: colors.secondary,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  border: i == 2
                      ? null
                      : Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(42, 42, 21),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: bar(120, 14),
                          ),
                          const SizedBox(height: 12),
                          FractionallySizedBox(
                            widthFactor: .88,
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: colors.border,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                          if (tab != 'posts') ...[
                            const SizedBox(height: 9),
                            FractionallySizedBox(
                              widthFactor: .72,
                              alignment: AlignmentDirectional.centerStart,
                              child: Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  color: colors.border,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: bar(48, 12),
                          ),
                        ],
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
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({
    required this.page,
    required this.item,
    required this.person,
    required this.comment,
    required this.first,
    required this.last,
  });
  final NativePageState page;
  final Json item, person;
  final bool comment, first, last;

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final post = comment ? object(item['post']) : item;
    final path = '/community/posts/${post['id'] ?? item['feed_post_id']}';

    Widget entry(
      Json author,
      String subtitle,
      String content, {
      bool parent = false,
      bool response = false,
    }) => Stack(
      children: [
        PositionedDirectional(
          start: 14,
          top: response ? 8 : 16,
          child: Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.secondary,
              shape: BoxShape.circle,
            ),
            child: _Avatar(page: page, person: author, size: 36),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: EdgeInsetsDirectional.fromSTEB(
            72,
            response ? 10 : 18,
            14,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value(
                        author['name'],
                        page.c.t('Deleted user', 'مستخدم محذوف'),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => page.c.open(
                  response ? '$path?focus_comment=${item['id']}' : path,
                ),
                child: Text(
                  content,
                  maxLines: parent ? 2 : null,
                  overflow: parent ? TextOverflow.ellipsis : TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: parent ? colors.muted : colors.text,
                  ),
                ),
              ),
              if (response && value(item['sticker_id']).isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 160,
                        maxHeight: 160,
                      ),
                      child: networkImage(
                        page.c.api.media(
                          '/comment-stickers/${item['sticker_id']}.webp',
                        ),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              if (!comment) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    InkWell(
                      onTap: () => page.c.open('$path?comment=1#new-comment'),
                      borderRadius: BorderRadius.circular(999),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebIcon('message', size: 15, color: colors.muted),
                          const SizedBox(width: 5),
                          Text(
                            value(item['comments_count'], '0'),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    if (yes(item['is_private']))
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebIcon('lock', size: 15, color: colors.muted),
                          const SizedBox(width: 5),
                          Text(
                            page.c.t('Private', 'خاص'),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: CustomPaint(
        painter: _Connector(
          color: colors.border,
          rtl: Directionality.of(context) == TextDirection.rtl,
          top: first ? 37 : 0,
          endAtAvatar: last && !comment,
        ),
        child: comment
            ? Column(
                children: [
                  entry(
                    object(post['author']),
                    page.c.t('Original post', 'المنشور الأصلي'),
                    value(post['content']),
                    parent: true,
                  ),
                  entry(
                    person,
                    _relativeTime(page, item['created_at']),
                    value(item['content']),
                    response: true,
                  ),
                ],
              )
            : entry(
                person,
                _relativeTime(page, item['created_at']),
                value(item['content']),
              ),
      ),
    );
  }
}

class _Connector extends CustomPainter {
  const _Connector({
    required this.color,
    required this.rtl,
    this.top = 0,
    this.endAtAvatar = false,
  });
  final Color color;
  final bool rtl, endAtAvatar;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final x = rtl ? size.width - 35 : 35.0;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, endAtAvatar ? 37 : size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Connector oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.rtl != rtl ||
      oldDelegate.top != top ||
      oldDelegate.endAtAvatar != endAtAvatar;
}

class _AskThread extends StatelessWidget {
  const _AskThread({
    required this.page,
    required this.item,
    required this.person,
    required this.own,
  });
  final NativePageState page;
  final Json item, person;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final answered = value(item['answer']).isNotEmpty;
    Widget entry(
      Json author,
      dynamic time,
      String text, {
      bool first = false,
    }) => Stack(
      clipBehavior: Clip.none,
      children: [
        if (first && answered)
          PositionedDirectional(
            start: 19,
            top: 43,
            bottom: -24,
            child: Container(width: 2, color: colors.border),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: author['id'] == null
                  ? null
                  : () => page.c.open('/users/${author['id']}'),
              child: _Avatar(page: page, person: author, size: 40),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: first && own ? 30 : 0,
                      ),
                      child: Wrap(
                        spacing: 9,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            value(
                              author['name'],
                              page.c.t('Deleted user', 'مستخدم محذوف'),
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _relativeTime(page, time),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text,
                      style: const TextStyle(fontSize: 15, height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 15, 13, 12),
      decoration: BoxDecoration(
        color: colors.secondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              entry(
                object(item['sender']),
                item['created_at'],
                value(item['question']),
                first: true,
              ),
              if (answered) ...[
                const SizedBox(height: 22),
                entry(person, item['answered_at'], value(item['answer'])),
              ],
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 50, top: 18),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item['published_at'] != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebIcon(
                            yes(item['is_private']) ? 'lock' : 'globe',
                            size: 14,
                            color: colors.muted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            yes(item['is_private'])
                                ? page.c.t('Private', 'خاص')
                                : page.c.t('Public', 'عام'),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                    InkWell(
                      onTap: () => page.c.open('/ask/${item['id']}'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            page.c.t('View question', 'عرض السؤال'),
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 5),
                          _ForwardIcon(size: 14, color: colors.accent),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (own && item['answered_at'] != null)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: AppPopupMenuButton<String>(
                tooltip: page.c.t('Question options', 'خيارات السؤال'),
                onSelected: (_) async {
                  if (item['published_at'] == null) {
                    await page.run('PATCH', '/ask/${item['id']}/publication', {
                      'published': true,
                      'is_private': false,
                    });
                  } else {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        content: Text(
                          page.c.t(
                            'Remove this question and answer from your profile?',
                            'تحذف السؤال وإجابته من ملفك الشخصي؟',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(page.c.t('Cancel', 'إلغاء')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(page.c.t('Remove', 'إزالة')),
                          ),
                        ],
                      ),
                    );
                    if (remove == true) {
                      await page.run(
                        'DELETE',
                        '/ask/${item['id']}/publication',
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'publication',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WebIcon(
                          item['published_at'] == null ? 'post' : 'delete',
                          size: 17,
                          color: item['published_at'] == null
                              ? colors.text
                              : colors.danger,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            item['published_at'] == null
                                ? page.c.t(
                                    'Publish on my profile',
                                    'انشر على ملفي الشخصي',
                                  )
                                : page.c.t(
                                    'Remove from profile',
                                    'إزالة من الملف الشخصي',
                                  ),
                            style: TextStyle(
                              fontSize: 13,
                              color: item['published_at'] == null
                                  ? colors.text
                                  : colors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.main,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '⋯',
                    style: TextStyle(
                      fontSize: 21,
                      color: colors.muted,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Flat mobile results and live search from people/index.blade.php + people.css.
class WebPeople extends StatefulWidget {
  const WebPeople({super.key, required this.page});
  final NativePageState page;

  @override
  State<WebPeople> createState() => _WebPeopleState();
}

class _WebPeopleState extends State<WebPeople> {
  late final TextEditingController search;
  late Json data;
  Timer? timer;
  int request = 0;
  bool searching = false;
  late String completedQuery;
  NativePageState get page => widget.page;

  @override
  void initState() {
    super.initState();
    data = page.data;
    completedQuery = value(data['search']);
    search = TextEditingController(text: completedQuery);
  }

  @override
  void didUpdateWidget(WebPeople oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(data, page.data) && !searching) {
      data = page.data;
      completedQuery = value(data['search']);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    request++;
    search.dispose();
    super.dispose();
  }

  Future<void> fetch(String destination, {bool force = false}) async {
    timer?.cancel();
    final query = Uri.parse(destination).queryParameters['q'] ?? '';
    if (!force && query == completedQuery) {
      if (mounted) setState(() => searching = false);
      return;
    }
    final current = ++request;
    setState(() => searching = true);
    try {
      final envelope = await page.c.get(destination);
      if (!mounted || current != request) return;
      final updated = object(envelope['data']);
      // Keep the page's navigation/refresh destination in sync without replacing
      // the search input (and dropping keyboard focus) on each typed character.
      page.path = destination;
      page.envelope = envelope;
      page.data = updated;
      setState(() {
        data = updated;
        completedQuery = value(updated['search']);
        searching = false;
      });
    } catch (error) {
      if (!mounted || current != request) return;
      setState(() => searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String destination(String query) => Uri(
    path: '/people',
    queryParameters: query.isEmpty ? null : {'q': query},
  ).toString();

  void schedule(String input) {
    timer?.cancel();
    request++;
    final trimmed = input.trim();
    final query = trimmed.runes.length >= 2 ? trimmed : '';
    if (query == completedQuery) {
      setState(() => searching = false);
      return;
    }
    setState(() => searching = true);
    timer = Timer(const Duration(milliseconds: 300), () {
      fetch(destination(query));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final people = rows(data['people']);
    final query = value(data['search']);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          page.c.t('Discover', 'اكتشف'),
          style: TextStyle(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: page.c.settings.language == 'ar' ? 0 : -1.05,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.secondary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              WebIcon('search', size: 20, color: colors.text),
              const SizedBox(width: 10),
              Expanded(
                child: AdaptiveTextField(
                  controller: search,
                  field: (direction) => TextField(
                    controller: search,
                    textDirection: direction,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    decoration: InputDecoration(
                      hintText: page.c.t(
                        'Type a skill, like Python…',
                        'اكتب مهارة، مثل Python…',
                      ),
                      hintStyle: TextStyle(
                        color: colors.muted,
                        fontSize: 16,
                        height: 1.5,
                      ),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: schedule,
                    onSubmitted: (input) {
                      timer?.cancel();
                      fetch(destination(input.trim()), force: true);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        if (searching)
          _PeopleSkeleton(colors: colors)
        else
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(2, 0, 2, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        query.isEmpty
                            ? page.c.t('Suggested for you', 'مقترح لك')
                            : page.c.t('Search results', 'نتائج البحث'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (query.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          page.c.t(
                            'People matching “$query”',
                            'أشخاص مطابقون لـ «$query»',
                          ),
                          style: TextStyle(
                            color: colors.muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (query.isNotEmpty) ...[
                  const SizedBox(width: 20),
                  InkWell(
                    onTap: () {
                      search.clear();
                      fetch(destination(''));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        page.c.t('Clear search', 'مسح البحث'),
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    final hasPagination = !searching && query.isNotEmpty;
    final bodyCount = searching
        ? 0
        : (people.isEmpty ? 1 : people.length) + (hasPagination ? 1 : 0);
    return RefreshIndicator.adaptive(
      onRefresh: () {
        page.c.markAllStale();
        return fetch(page.path, force: true);
      },
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          10,
          22,
          10,
          112 + MediaQuery.paddingOf(context).bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1 + bodyCount,
        itemBuilder: (context, index) {
          if (index == 0) return header;
          final rowIndex = index - 1;
          if (people.isEmpty && rowIndex == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.soft,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: WebIcon('users', size: 27, color: colors.accent),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    page.c.t('No people found', 'مفيش أشخاص مطابقين'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    query.isEmpty
                        ? page.c.t(
                            'People will appear here as the community grows.',
                            'الأشخاص هيظهروا هنا مع نمو المجتمع.',
                          )
                        : page.c.t(
                            'Try another name, ID, or skill. A shorter search may help.',
                            'جرب اسم، رقم تعريفي، أو مهارة تانية. ممكن تجرب كلمة أقصر.',
                          ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            );
          }
          if (rowIndex < people.length) {
            return _PeopleRow(page: page, person: people[rowIndex]);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: _Pagination(
              page: data['people'],
              nativePage: page,
              onNavigate: (url) => fetch(url, force: true),
            ),
          );
        },
      ),
    );
  }
}

class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.page, required this.person});
  final NativePageState page;
  final Json person;

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final narrow = MediaQuery.sizeOf(context).width < 359;
    final size = narrow ? 42.0 : 48.0;
    final gap = narrow ? 7.0 : 9.0;
    final skills = rows(person['skills']);
    final skillCount =
        int.tryParse(value(person['skills_count'])) ?? skills.length;
    final major = value(person['major']);
    final bio = major.isEmpty ? value(person['job']) : major;
    final own = '${person['id']}' == '${page.c.user?['id']}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => page.c.open('/users/${person['id']}'),
              child: Row(
                children: [
                  _Avatar(page: page, person: person, size: size),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                value(person['name']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_hasBadge(person)) ...[
                              const SizedBox(width: 5),
                              if ('${person['badge']}' == '2')
                                UserBadge(
                                  api: page.c.api,
                                  badge: person['badge'],
                                )
                              else
                                SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: FittedBox(
                                    child: UserBadge(
                                      api: page.c.api,
                                      badge: person['badge'],
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '@${value(person['university_id'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: colors.muted,
                          ),
                        ),
                        if (bio.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              bio,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        if (skills.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              [
                                skills
                                    .take(2)
                                    .map((s) => value(s['skill_name']))
                                    .join(' · '),
                                if (skillCount > 2)
                                  page.c.t(
                                    '+${skillCount - 2} more',
                                    '+${skillCount - 2} مهارات أخرى',
                                  ),
                              ].join(' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.4,
                                color: colors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  _ForwardIcon(size: narrow ? 12 : 14, color: colors.muted),
                ],
              ),
            ),
          ),
          if (!own) ...[
            SizedBox(width: narrow ? 6 : 9),
            _PillAction(
              text: page.c.t('Ask', 'اسأل'),
              minWidth: narrow ? 68 : 80,
              onTap: () => showWebAskComposer(context, page, person),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeopleSkeleton extends StatefulWidget {
  const _PeopleSkeleton({required this.colors});
  final _Colors colors;
  @override
  State<_PeopleSkeleton> createState() => _PeopleSkeletonState();
}

class _PeopleSkeletonState extends State<_PeopleSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height, [double radius = 5]) =>
        AnimatedBuilder(
          animation: shimmer,
          builder: (_, _) => ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              width: width,
              height: height,
              color: Color.alphaBlend(
                widget.colors.muted.withValues(alpha: .12),
                widget.colors.secondary,
              ),
              child: FractionalTranslation(
                translation: Offset(shimmer.value * 2 - 1, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        widget.colors.text.withValues(alpha: .08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: bar(140, 18, 7),
            ),
          ),
          for (var i = 0; i < 6; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: widget.colors.border)),
              ),
              child: Row(
                children: [
                  bar(48, 48, 24),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: bar(85, 15),
                        ),
                        const SizedBox(height: 7),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: bar(65, 12),
                        ),
                        const SizedBox(height: 7),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: bar(110, 11),
                        ),
                      ],
                    ),
                  ),
                  bar(14, 20),
                  const SizedBox(width: 9),
                  bar(80, 40, 999),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The same full-height, rounded mobile ask sheet used by profiles and People.
Future<void> showWebAskComposer(
  BuildContext context,
  NativePageState page,
  Json recipient,
) async {
  final sent = await showModalBottomSheet<bool>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AskComposer(page: page, recipient: recipient),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(page.c.t('Your question was sent.', 'تم إرسال سؤالك.')),
      ),
    );
  }
}

class _AskComposer extends StatefulWidget {
  const _AskComposer({required this.page, required this.recipient});
  final NativePageState page;
  final Json recipient;
  @override
  State<_AskComposer> createState() => _AskComposerState();
}

class _AskComposerState extends State<_AskComposer> {
  final input = TextEditingController();
  String _lastText = '';
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);
  final ValueNotifier<int> _charCount = ValueNotifier<int>(0);
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    input.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final current = input.text;
    if (identical(current, _lastText) || current == _lastText) return;
    _lastText = current;
    final hasText = current.trim().isNotEmpty;
    if (_hasText.value != hasText) _hasText.value = hasText;
    _charCount.value = current.characters.length;
  }

  @override
  void dispose() {
    input.removeListener(_onTextChanged);
    _hasText.dispose();
    _charCount.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || input.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.page.c.action(
        'POST',
        '/users/${widget.recipient['id']}/ask',
        {'question': input.text.trim()},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final colors = _Colors(context);
    final media = MediaQuery.of(context);
    return Container(
      height: media.size.height - media.padding.top - 30,
      padding: EdgeInsets.fromLTRB(
        22,
        20,
        22,
        24 + media.padding.bottom + media.viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.main,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                _SheetButton(
                  text: page.c.t('Cancel', 'إلغاء'),
                  onTap: busy ? null : () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    page.c.t('Ask', 'اسأل'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _hasText,
                  builder: (context, hasText, _) => _SheetButton(
                    text: busy
                        ? page.c.t('Sending…', 'جاري الإرسال…')
                        : page.c.t('Send', 'إرسال'),
                    primary: true,
                    onTap: busy || !hasText ? null : send,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            page.c.t(
              '${widget.recipient['name']} will see your name and profile picture.',
              '${widget.recipient['name']} هيشوف اسمك وصورتك مع السؤال.',
            ),
            style: TextStyle(color: colors.muted, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RepaintBoundary(
              child: AdaptiveTextField(
                controller: input,
                field: (direction) => TextField(
                  controller: input,
                  textDirection: direction,
                  autofocus: true,
                  enabled: !busy,
                  maxLength: 1000,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 19, height: 1.5),
                  decoration: InputDecoration(
                    hintText: page.c.t(
                      'Type something nice (or spicy)…',
                      'اكتب سؤال لطيف (أو جريء)…',
                    ),
                    hintStyle: TextStyle(
                      color: colors.muted.withValues(alpha: .64),
                      fontSize: 19,
                      height: 1.5,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 5,
                    ),
                    counterText: '',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Avatar(page: page, person: widget.recipient, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value(widget.recipient['name']),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ),
              const SizedBox(width: 12),
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _charCount,
                  builder: (context, count, _) => Text(
                    '$count / 1000',
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: TextStyle(fontSize: 13, color: colors.danger)),
          ],
        ],
      ),
    );
  }
}

/// Shared by NativePage's mobile ellipsis header, so it has the web actions.
Future<void> showWebProfileOptions(
  BuildContext context,
  NativePageState page, {
  BuildContext? anchorContext,
}) async {
  final person = object(page.data['profile_user'] ?? page.data['user']);
  final own = '${person['id']}' == '${page.c.user?['id']}';
  final colors = _Colors(context);
  final choice = await showAppMenu<String>(
    useRootNavigator: true,
    context: context,
    anchorContext: anchorContext ?? context,
    color: colors.secondary,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.border),
    ),
    items: [
      PopupMenuItem(
        value: 'share',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WebIcon('share'),
            const SizedBox(width: 12),
            Text(page.c.t('Share profile', 'مشاركة الملف الشخصي')),
          ],
        ),
      ),
      if (!own)
        PopupMenuItem(
          value: 'report',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebIcon('flag', color: colors.danger),
              const SizedBox(width: 12),
              Text(
                page.c.t('Report profile', 'الإبلاغ عن الملف الشخصي'),
                style: TextStyle(color: colors.danger),
              ),
            ],
          ),
        ),
    ],
  );
  if (!context.mounted) return;
  if (choice == 'share') {
    final url = page.c.api.media('/users/${person['id']}');
    if (await shareNative(url, value(person['name']))) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.main,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeading(
                title: page.c.t('Share profile', 'مشاركة الملف الشخصي'),
              ),
              const SizedBox(height: 20),
              Text(page.c.t('Profile link', 'رابط الملف الشخصي')),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(url, textDirection: TextDirection.ltr),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _SheetButton(
                  text: page.c.t('Copy link', 'نسخ الرابط'),
                  primary: true,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          page.c.t(
                            'Profile link copied.',
                            'تم نسخ رابط الملف الشخصي.',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } else if (choice == 'report') {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProfileReport(page: page, person: person),
    );
  }
}

class _ProfileReport extends StatefulWidget {
  const _ProfileReport({required this.page, required this.person});
  final NativePageState page;
  final Json person;
  @override
  State<_ProfileReport> createState() => _ProfileReportState();
}

class _ProfileReportState extends State<_ProfileReport> {
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
        '/users/${widget.person['id']}/reports',
        {'reason': reason.text.trim()},
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.page.c.t(
              'Your profile report was sent to the Super Admin.',
              'بلاغ الملف الشخصي وصل لمسؤول الموقع الرئيسي.',
            ),
          ),
        ),
      );
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    final page = widget.page;
    return Dialog(
      backgroundColor: colors.main,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeading(
              title: page.c.t(
                'Report this profile',
                'الإبلاغ عن هذا الملف الشخصي',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              page.c.t(
                'Your report will be sent to the Super Admin for review.',
                'سيصل بلاغك إلى مسؤول الموقع الرئيسي للمراجعة.',
              ),
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
            const SizedBox(height: 20),
            Text(
              page.c.t('Reason (optional)', 'السبب (اختياري)'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            AdaptiveTextField(
              controller: reason,
              field: (direction) => TextField(
                controller: reason,
                textDirection: direction,
                enabled: !busy,
                minLines: 4,
                maxLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: page.c.t(
                    'Tell us what is wrong with this profile…',
                    'قول لنا إيه المشكلة في الملف ده…',
                  ),
                  counterText: '',
                  fillColor: colors.secondary,
                  filled: true,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(color: colors.danger, fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _SheetButton(
                text: busy
                    ? page.c.t('Sending…', 'جاري الإرسال…')
                    : page.c.t('Submit report', 'إرسال البلاغ'),
                primary: true,
                onTap: busy ? null : submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeading extends StatelessWidget {
  const _DialogHeading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 16),
      InkWell(
        onTap: () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _Colors(context).secondary,
            shape: BoxShape.circle,
          ),
          child: const Text('×', style: TextStyle(fontSize: 22)),
        ),
      ),
    ],
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.page, required this.person, required this.size});
  final NativePageState page;
  final Json person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = value(
      person['avatar_url'],
      '/avatars/${value(person['avatar'], 'jko.webp')}',
    );
    return ClipOval(
      child: networkImage(
        page.c.api.media(url),
        width: size,
        height: size,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: _Colors(context).secondary,
          alignment: Alignment.center,
          child: WebIcon(
            'user',
            size: size * .48,
            color: _Colors(context).muted,
          ),
        ),
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.page, required this.person});
  final NativePageState page;
  final Json person;
  @override
  Widget build(BuildContext context) {
    if ('${person['badge']}' == '2') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        decoration: BoxDecoration(
          color: _Colors(context).accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebIcon('graduation', size: 11, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'PROFESSOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    final size = '${person['badge']}' == '1' ? 20.0 : 18.0;
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        child: UserBadge(api: page.c.api, badge: person['badge']),
      ),
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  const _ProfileMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.secondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 14, color: colors.accent),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.text,
    required this.onTap,
    this.profile = false,
    this.minWidth = 80,
  });
  final String text;
  final VoidCallback onTap;
  final bool profile;
  final double minWidth;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    return Material(
      color: profile ? colors.accent : const Color(0xff2e855d),
      borderRadius: BorderRadius.circular(profile ? 14 : 999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(profile ? 14 : 999),
        child: Container(
          constraints: BoxConstraints(
            minWidth: profile ? 0 : minWidth,
            minHeight: profile ? 46 : 40,
          ),
          alignment: profile ? Alignment.center : null,
          padding: EdgeInsets.symmetric(
            horizontal: profile ? 24 : 12,
            vertical: profile ? 10 : 8,
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: profile && colors.dark
                  ? const Color(0xff0a0a0a)
                  : Colors.white,
              fontSize: profile ? 15 : 13,
              fontWeight: profile ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.text,
    required this.onTap,
    this.primary = false,
  });
  final String text;
  final VoidCallback? onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final colors = _Colors(context);
    return Material(
      color: primary && onTap != null
          ? const Color(0xff2e855d)
          : colors.secondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: primary && onTap != null ? Colors.transparent : colors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: primary && onTap != null
                  ? Colors.white
                  : onTap == null
                  ? colors.muted
                  : colors.text,
              fontSize: 14,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ForwardIcon extends StatelessWidget {
  const _ForwardIcon({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: Directionality.of(context) == TextDirection.rtl,
    child: WebIcon('chevron-right', size: size, color: color),
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.nativePage,
    required this.onNavigate,
  });
  final dynamic page;
  final NativePageState nativePage;
  final Future<void> Function(String) onNavigate;
  @override
  Widget build(BuildContext context) {
    final source = object(page);
    if (source['prev_page_url'] == null && source['next_page_url'] == null) {
      return const SizedBox.shrink();
    }
    final colors = _Colors(context);
    Widget button(String text, dynamic destination) => Material(
      color: destination == null ? colors.main : colors.secondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: destination == null ? null : () => onNavigate('$destination'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: destination == null ? colors.muted : colors.text,
            ),
          ),
        ),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        button(
          nativePage.c.t('« Previous', '« السابق'),
          source['prev_page_url'],
        ),
        button(nativePage.c.t('Next »', 'التالي »'), source['next_page_url']),
      ],
    );
  }
}

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
  Color get soft => accent.withValues(alpha: dark ? .12 : .10);
  Color get danger => dark ? const Color(0xffe7767d) : const Color(0xffc53d46);
}

bool _hasBadge(Json person) => ['1', '2', '3'].contains('${person['badge']}');

final _hexPattern = RegExp(r'^[0-9a-fA-F]{6}$');

Color? _hex(dynamic input) {
  final text = value(input).replaceFirst('#', '');
  if (!_hexPattern.hasMatch(text)) return null;
  return Color(int.parse('ff$text', radix: 16));
}

String _relativeTime(NativePageState page, dynamic input) {
  final parsed = DateTime.tryParse(value(input));
  if (parsed == null) return '';
  final seconds = DateTime.now().difference(parsed).inSeconds;
  if (seconds < 60) return page.c.t('a few seconds ago', 'منذ ثوانٍ');
  if (seconds < 3600) {
    final count = seconds ~/ 60;
    return page.c.t(
      count == 1 ? '1 minute ago' : '$count minutes ago',
      count == 1
          ? 'منذ دقيقة'
          : count == 2
          ? 'منذ دقيقتين'
          : 'منذ $count دقائق',
    );
  }
  if (seconds < 86400) {
    final count = seconds ~/ 3600;
    return page.c.t(
      count == 1 ? '1 hour ago' : '$count hours ago',
      count == 1
          ? 'منذ ساعة'
          : count == 2
          ? 'منذ ساعتين'
          : 'منذ $count ساعات',
    );
  }
  final days = seconds ~/ 86400;
  if (days < 7) {
    return page.c.t(
      days == 1 ? '1 day ago' : '$days days ago',
      days == 1
          ? 'منذ يوم'
          : days == 2
          ? 'منذ يومين'
          : 'منذ $days أيام',
    );
  }
  if (days < 30) {
    final count = days ~/ 7;
    return page.c.t(
      count == 1 ? '1 week ago' : '$count weeks ago',
      count == 1
          ? 'منذ أسبوع'
          : count == 2
          ? 'منذ أسبوعين'
          : 'منذ $count أسابيع',
    );
  }
  if (days < 365) {
    final count = days ~/ 30;
    return page.c.t(
      count == 1 ? '1 month ago' : '$count months ago',
      count == 1
          ? 'منذ شهر'
          : count == 2
          ? 'منذ شهرين'
          : 'منذ $count أشهر',
    );
  }
  final count = days ~/ 365;
  return page.c.t(
    count == 1 ? '1 year ago' : '$count years ago',
    count == 1
        ? 'منذ سنة'
        : count == 2
        ? 'منذ سنتين'
        : 'منذ $count سنوات',
  );
}

/// The level pill under the profile handle (section and group stay private).
class _StudyPlacement extends StatelessWidget {
  const _StudyPlacement({required this.page, required this.person});
  final NativePageState page;
  final Json person;
  @override
  Widget build(BuildContext context) {
    final level = value(person['level']);
    if (level.isEmpty) return const SizedBox(height: 4);
    final colors = _Colors(context);
    Widget pill(String text, {bool accent = false, IconData? icon}) =>
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: accent ? colors.accent.withValues(alpha: .12) : null,
            border: accent ? null : Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: colors.accent),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent ? colors.accent : colors.muted,
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (level.isNotEmpty)
            pill(
              page.c.t('Level $level', 'الفرقة $level'),
              accent: true,
              icon: Icons.layers_outlined,
            ),
        ],
      ),
    );
  }
}
