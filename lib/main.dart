import 'dart:async' show Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart' show svg;
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'app_links.dart';
import 'native_glass.dart';
import 'settings.dart';
import 'push.dart';
import 'screens.dart';
import 'web_motion.dart';
import 'launch_experience.dart';
import 'page_store.dart';
import 'scroll_physics.dart';
import 'web_materials.dart' show MaterialFiles;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Icons, reactions and post actions use more distinct SVGs than the
  // default 100-entry compiled-picture cache holds, so scrolling evicted and
  // recompiled them (each recompile is an isolate hop and a late pop-in).
  svg.cache.maximumSize = 400;
  final settings = AppSettings();
  final api = LaravelApi();
  runApp(
    ElBenchApp(
      api: api,
      settings: settings,
      pageStore: PageStore(),
      initialize: () => Future.wait<void>([
        settings.load(),
        api.warmUp(),
        nativeGlassAvailable().then((_) {}),
      ]).then((_) {}),
    ),
  );
}

class ElBenchApp extends StatefulWidget {
  const ElBenchApp({
    super.key,
    required this.api,
    required this.settings,
    this.enablePush = true,
    this.enableLaunchExperience = true,
    this.initialize,
    this.pageStore,
  });
  final PageStore? pageStore;
  final MobileApi api;
  final AppSettings settings;
  final bool enablePush;
  final bool enableLaunchExperience;
  final Future<void> Function()? initialize;
  @override
  State<ElBenchApp> createState() => _ElBenchAppState();
}

class _ElBenchAppState extends State<ElBenchApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  final rootNavigator = GlobalKey<NavigatorState>();
  late final AppController controller;
  late (bool, Object?, Object?, bool) _appState;
  bool _animationFinished = false, _introDismissed = false;
  bool _launchReleased = false;
  bool _initializing = true;
  Object? _initializationError;
  String? _pendingAppLink, _lastAppLink;
  DateTime? _lastAppLinkAt;
  bool _appLinkScheduled = false;
  @override
  void initState() {
    super.initState();
    controller = AppController(
      widget.api,
      widget.settings,
      navigator,
      enablePush: widget.enablePush,
      rootNavigator: rootNavigator,
      pageStore: widget.pageStore,
    );
    _appState = _currentAppState;
    widget.settings.addListener(_changed);
    controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addObserver(this);
    _receiveAppLink(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    unawaited(_initialize());
  }

  @override
  Future<bool> didPushRoute(String route) async {
    _receiveAppLink(route);
    return true;
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    _receiveAppLink(routeInformation.uri.toString());
    return true;
  }

  void _receiveAppLink(String location) {
    final path = appLinkPath(location);
    if (!mounted || path == null || path == _pendingAppLink) return;
    if (controller.user != null &&
        path == _lastAppLink &&
        _lastAppLinkAt != null &&
        DateTime.now().difference(_lastAppLinkAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _pendingAppLink = path;
    _scheduleAppLink();
  }

  bool get _canOpenAppLink =>
      mounted &&
      !_initializing &&
      _initializationError == null &&
      !controller.starting &&
      controller.startError == null &&
      controller.user != null;

  void _scheduleAppLink() {
    if (_pendingAppLink == null || _appLinkScheduled || !_canOpenAppLink) {
      return;
    }
    _appLinkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appLinkScheduled = false;
      if (!_canOpenAppLink || _pendingAppLink == null) return;
      if (navigator.currentState == null) {
        _scheduleAppLink();
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      final path = _pendingAppLink!;
      _pendingAppLink = null;
      _lastAppLink = path;
      _lastAppLinkAt = DateTime.now();
      rootNavigator.currentState?.popUntil((route) => route.isFirst);
      controller.open(path);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  DateTime? _backgroundedAt;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (_initializing || controller.user == null) return;
      // Badges must be current whenever the app returns to the foreground;
      // after a longer absence, the visible screen is revalidated as well.
      unawaited(controller.refreshSession());
      if (away >= const Duration(minutes: 2)) {
        controller.markAllStale();
        controller.activePage?.reloadOnResume();
      }
    }
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _initializing = true;
      });
    }
    try {
      await widget.initialize?.call();
      if (!mounted) return;
      await controller.start();
      if (mounted) _initializationError = null;
    } catch (error) {
      if (mounted) _initializationError = error;
    } finally {
      if (mounted) {
        setState(() {
          _initializing = false;
          _releaseLaunchIfReady();
        });
        _scheduleAppLink();
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  (bool, Object?, Object?, bool) get _currentAppState => (
    controller.starting,
    controller.startError,
    controller.user?['id'],
    controller.enabled('community'),
  );

  void _controllerChanged() {
    // A restored session and a later logout must retain their existing flow.
    if (controller.user != null) _introDismissed = true;
    final next = _currentAppState;
    if (next == _appState) return;
    _appState = next;
    _changed();
    _scheduleAppLink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingAppLink = null;
    widget.settings.removeListener(_changed);
    controller.removeListener(_controllerChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ElBench',
    debugShowCheckedModeBanner: false,
    scrollBehavior: const AppScrollBehavior(),
    navigatorKey: rootNavigator,
    initialRoute: '/',
    theme: widget.settings.theme(Brightness.light),
    darkTheme: widget.settings.theme(Brightness.dark),
    themeMode: widget.settings.mode,
    themeAnimationDuration: Duration.zero,
    locale: Locale(widget.settings.language),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => Actions(
      actions: <Type, Action<Intent>>{
        // Apply the same outside-tap behavior to inputs on mobile, including
        // dialogs and sheets. Flutter keeps taps inside TextFieldTapRegion
        // (such as field controls) associated with their input.
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (Theme.of(context).brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Theme.of(
                    context,
                  ).scaffoldBackgroundColor,
                ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              excluding: _showLaunch,
              child: child ?? const SizedBox.shrink(),
            ),
            if (_showLaunch)
              Positioned.fill(
                child: LaunchAnimation(
                  onFinished: () {
                    if (mounted) {
                      setState(() {
                        _animationFinished = true;
                        _releaseLaunchIfReady();
                      });
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    ),
    home: _initializationError != null
        ? Scaffold(
            body: ErrorPanel(
              error: _initializationError!,
              retry: _initialize,
              retrying: _initializing,
            ),
          )
        : controller.startError != null
        ? Scaffold(
            body: ErrorPanel(
              error: controller.startError!,
              retry: controller.start,
              retrying: _initializing || controller.starting,
            ),
          )
        : _initializing || controller.starting
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : controller.user == null
        ? widget.enableLaunchExperience && !_introDismissed
              ? IntroductionPage(
                  settings: widget.settings,
                  onLogin: () => setState(() => _introDismissed = true),
                  onCreateAccount: () {
                    // Signup's existing Back/Log in actions return to Login.
                    setState(() => _introDismissed = true);
                    rootNavigator.currentState?.push(
                      MaterialPageRoute<void>(
                        builder: (_) => SignupPage(controller: controller),
                      ),
                    );
                  },
                )
              : LoginPage(controller: controller)
        : MobileShell(controller: controller),
  );

  void _releaseLaunchIfReady() {
    if (_animationFinished && !_initializing) _launchReleased = true;
  }

  bool get _showLaunch => widget.enableLaunchExperience && !_launchReleased;
}

class AppController extends ChangeNotifier {
  AppController(
    this.api,
    this.settings,
    this.navigator, {
    this.enablePush = true,
    this.rootNavigator,
    this.pageStore,
  }) {
    push = PushService(api, open);
    _language = settings.language;
    settings.addListener(_settingsChanged);
  }
  final MobileApi api;
  final AppSettings settings;
  final GlobalKey<NavigatorState> navigator;
  final GlobalKey<NavigatorState>? rootNavigator;
  final PageStore? pageStore;
  final bool enablePush;
  late final PushService push;
  Json? user;
  Json features = {}, counts = {};
  bool starting = true;
  Object? startError;
  late final routeObserver = ChromeRouteObserver(this);
  final chromeRevision = ValueNotifier<int>(0);
  final dockHidden = ValueNotifier<bool>(false);
  bool? _pendingDockHidden;
  bool _dockVisibilityScheduled = false;
  bool modalVisible = false, _chromeScheduled = false;

  void setDockHidden(bool hidden) {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _pendingDockHidden = hidden;
      if (!_dockVisibilityScheduled) {
        _dockVisibilityScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dockVisibilityScheduled = false;
          final pending = _pendingDockHidden;
          _pendingDockHidden = null;
          if (!_disposed && pending != null) dockHidden.value = pending;
        });
      }
    } else {
      _pendingDockHidden = null;
      dockHidden.value = hidden;
    }
  }

  void updateChrome({bool immediate = false}) {
    // Async page failures must hide chrome in the same frame as the error body.
    if (immediate &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      if (!_disposed) chromeRevision.value++;
      return;
    }
    if (_chromeScheduled) return;
    _chromeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chromeScheduled = false;
      if (!_disposed) chromeRevision.value++;
    });
  }

  bool _disposed = false;
  NativePageState? activePage;
  final _pages = <String, KeptNativePage>{};
  final _positions = <String, double>{};
  final _dockAliases = <String, String>{};
  final _routes = <WebPageRoute<void>>[];
  int cacheGeneration = 0, _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;
  late String _language;
  bool _preparingVisit = false;

  String _pageKey(String path) {
    final uri = Uri.parse(localized(path));
    final keys = uri.queryParameters.keys.toList()..sort();
    return uri
        .replace(
          fragment: '',
          queryParameters: {
            for (final key in keys) key: uri.queryParameters[key]!,
          },
        )
        .toString();
  }

  String retainedPath(String path) {
    final uri = Uri.parse(path);
    final hasQuery = uri.queryParameters.keys.any((key) => key != 'lang');
    return !hasQuery ? _dockAliases[uri.path] ?? path : path;
  }

  KeptNativePage? cachedPage(String path) {
    if (user == null) return null;
    final key = _pageKey(retainedPath(path));
    final kept = _pages.remove(key);
    if (kept == null ||
        kept.viewerId != user?['id'] ||
        DateTime.now().difference(kept.storedAt) > keptPageLifetime) {
      return null;
    }
    _pages[key] = kept;
    return kept;
  }

  double keptScrollOffset(String path) =>
      _positions[_pageKey(retainedPath(path))] ?? 0;
  void rememberScroll(String path, double offset) {
    if (user == null || !offset.isFinite) return;
    final key = _pageKey(path);
    _positions.remove(key);
    _positions[key] = offset < 0 ? 0 : offset;
    while (_positions.length > 8) {
      _positions.remove(_positions.keys.first);
    }
  }

  void rememberPage(
    String path,
    Json envelope, {
    double offset = 0,
    DateTime? fetchedAt,
  }) {
    final screen = value(envelope['screen']);
    if (user == null ||
        screen.isEmpty ||
        screen.startsWith('auth.') ||
        screen == 'quiz.attempt' ||
        screen == 'profile.password-reset' ||
        screen.startsWith('ai.')) {
      return;
    }
    final key = _pageKey(path);
    // Only authorized, sanitized GET documents live in this session's memory.
    // CSRF, presence tokens, credentials, and local form controllers are excluded.
    final stripped = <String, dynamic>{
      for (final entry in envelope.entries)
        if (entry.key != 'user' &&
            entry.key != 'features' &&
            entry.key != 'counts')
          entry.key: entry.value,
    };
    final kept = object(_withoutCredentials(stripped));
    kept['canonical_url'] = api.safePath(path);
    if ([
      '/profile',
      '/inbox',
      '/notifications',
    ].contains(Uri.parse(path).path)) {
      _dockAliases[Uri.parse(path).path] = api.safePath(path);
    }
    final previous = _pages.remove(key);
    _pages[key] = KeptNativePage(
      kept,
      user?['id'],
      fetchedAt: fetchedAt ?? previous?.fetchedAt,
    );
    final route = Uri.parse(path);
    if (PageStore.persistedPaths.contains(route.path) &&
        route.queryParameters.keys.every((name) => name == 'lang')) {
      _persistPages();
    }
    rememberScroll(path, offset);
    while (_pages.length > maxKeptPages) {
      _pages.remove(_pages.keys.first);
    }
  }

  /// Bumped by every pull-to-refresh. Covered screens compare it on reveal.
  int refreshEpoch = 0;
  void markAllStale() {
    _pages.clear();
    _inflight.clear();
    refreshEpoch++;
  }

  /// Fetch fresh badge counts (notifications, inbox) for the signed-in user.
  Future<void> refreshSession() async {
    if (user == null || _disposed) return;
    final session = _sessionGeneration, language = settings.language;
    try {
      final response = await api.get(localized('/mobile/session'));
      if (session == _sessionGeneration && language == settings.language) {
        if (response['user'] == null && user != null) {
          await expired();
        } else {
          absorb(response);
        }
      }
    } on ApiFailure catch (e) {
      if (session == _sessionGeneration &&
          (e.status == 401 || e.status == 419)) {
        await expired();
      }
    } catch (_) {}
  }

  /// Retained screens are shown instantly and revalidated in the background
  /// (stale-while-revalidate). Documents are sanitized JSON of a few KB each.
  static const maxKeptPages = 32;
  static const keptPageLifetime = Duration(minutes: 30);

  /// A retained document this recent is shown without a network request.
  static const freshPageAge = Duration(seconds: 20);

  // Provisional documents for the next visit of a path (a tapped post renders
  // from its feed row while the full page loads).
  final _seeds = <String, Json>{};
  Json? takeSeed(String path) => _seeds.remove(_pageKey(path));

  // One network request per page document at a time, shared by prefetches
  // and the visit that follows them.
  final _inflight = <String, Future<Json>>{};
  Future<Json> fetchPage(String path) {
    final key = _pageKey(path);
    final existing = _inflight[key];
    if (existing != null) return existing;
    final request = api.get(localized(path));
    _inflight[key] = request;
    void release() {
      if (identical(_inflight[key], request)) _inflight.remove(key);
    }

    request.then<void>((_) => release(), onError: (Object _) => release());
    return request;
  }

  /// Warm the cache for a likely next visit (e.g. on touch-down). Only
  /// side-effect-free documents may be prefetched.
  void prefetch(String path) {
    if (user == null || _disposed) return;
    final String safe;
    try {
      safe = api.safePath(path);
    } catch (_) {
      return;
    }
    final key = _pageKey(safe);
    final kept = _pages[key];
    if (_inflight.containsKey(key) ||
        (kept != null &&
            DateTime.now().difference(kept.fetchedAt) < freshPageAge)) {
      return;
    }
    final session = _sessionGeneration, viewer = user?['id'];
    final language = settings.language, mutation = mutationEpoch;
    final generation = cacheGeneration;
    fetchPage(safe).then<void>((response) {
      if (_disposed ||
          mutation != mutationEpoch ||
          generation != cacheGeneration ||
          session != _sessionGeneration ||
          viewer != user?['id'] ||
          language != settings.language) {
        return;
      }
      absorb(response);
      final canonical = response['canonical_url'];
      if (canonical is String && _pageKey(canonical) != key) return;
      rememberPage(safe, response, fetchedAt: DateTime.now());
    }, onError: (Object _, StackTrace _) {});
  }

  void _restoreStored(Map<String, dynamic> stored) {
    final pages = stored['pages'];
    if (pages is! Map) return;
    for (final entry in pages.entries) {
      final page = entry.value;
      if (page is! Map || page['envelope'] is! Map) continue;
      final key = _pageKey('${entry.key}');
      _pages[key] = KeptNativePage(
        object(page['envelope']),
        user?['id'],
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          page['fetchedAt'] is int ? page['fetchedAt'] as int : 0,
        ),
      );
    }
  }

  /// Share an already-started request with the visit that follows it.
  void _adopt(String path, Future<Json> request) {
    final key = _pageKey(path);
    _inflight[key] = request;
    void release() {
      // A completed result stays shareable briefly: the page that will use
      // it is created on the next frame.
      Timer(const Duration(seconds: 2), () {
        if (identical(_inflight[key], request)) _inflight.remove(key);
      });
    }

    request.then<void>((_) => release(), onError: (Object _) => release());
  }

  void _persistPages() {
    final store = pageStore, viewer = user?['id'];
    if (store == null || viewer == null) return;
    final pages = <String, ({Json envelope, DateTime fetchedAt})>{};
    for (final path in PageStore.persistedPaths) {
      final kept = _pages[_pageKey(path)];
      if (kept != null && kept.viewerId == viewer) {
        pages[path] = (envelope: kept.envelope, fetchedAt: kept.fetchedAt);
      }
    }
    if (pages.isNotEmpty) store.write('$viewer', settings.language, pages);
  }

  /// Record that a retained document was revalidated unchanged.
  void markFetched(String path, DateTime at) {
    final key = _pageKey(path);
    final kept = _pages[key];
    if (kept != null) {
      _pages[key] = KeptNativePage(kept.envelope, kept.viewerId, fetchedAt: at);
    }
  }

  int? _warmedSession;

  /// Once per session, after Home has loaded and the network is idle, fetch
  /// the viewer's own Profile so the first dock visit is instant. Profile
  /// GETs have no side effects (unlike Inbox, which marks messages read).
  void warmLikelyPages() {
    if (_warmedSession == _sessionGeneration || user == null) return;
    _warmedSession = _sessionGeneration;
    final session = _sessionGeneration;
    // After the Home frame is on screen, and only while nothing else is
    // loading, so it never competes with what the viewer is waiting for.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && session == _sessionGeneration && _inflight.isEmpty) {
        prefetch('/profile');
      }
    });
  }

  /// Age of a retained document, or null when none is kept.
  Duration? keptPageAge(String path) {
    final kept = _pages[_pageKey(retainedPath(path))];
    return kept == null ? null : DateTime.now().difference(kept.fetchedAt);
  }

  /// Keep retained documents for instant display but require every one of
  /// them to be revalidated before it counts as fresh again.
  void markStale() {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    for (final entry in _pages.entries.toList()) {
      _pages[entry.key] = KeptNativePage(
        entry.value.envelope,
        entry.value.viewerId,
        fetchedAt: epoch,
      );
    }
    _inflight.clear();
    _seeds.clear();
    _persistPages();
  }

  void invalidatePages({bool authorization = false}) {
    _inflight.clear();
    _seeds.clear();
    if (authorization) {
      _pages.clear();
      unawaited(pageStore?.clear());
    } else {
      // After a write, retained screens are still shown instantly and then
      // revalidated (stale-while-revalidate) instead of starting empty.
      markStale();
    }
    cacheGeneration++;
    if (authorization) {
      _positions.clear();
      _dockAliases.clear();
    }
  }

  void activatePage(NativePageState page) {
    if (!identical(activePage, page)) setDockHidden(false);
    activePage = page;
    currentPath = page.path;
    updateChrome();
  }

  void _settingsChanged() {
    if (_language != settings.language) {
      _language = settings.language;
      invalidatePages(authorization: true);
      final page = activePage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (page != null && page.mounted && identical(page, activePage)) {
          page.reloadForLocale();
        }
      });
    }
    // The glass preference can change without changing ThemeData. Pushed bars
    // therefore observe the controller as well as the root MaterialApp.
    notifyListeners();
  }

  String t(String en, String ar) => settings.tr(en, ar);
  Future<void> start() async {
    starting = true;
    notifyListeners();
    try {
      final session = api.get(localized('/mobile/session'));
      // Observed below; this keeps a failure during the disk read handled.
      unawaited(session.then<void>((_) {}, onError: (Object _) {}));
      final stored = await pageStore?.read();
      // A returning viewer's Home is requested alongside the session check
      // instead of after it, saving a full round trip on every cold start.
      Future<Json>? home;
      if (stored != null && stored['locale'] == settings.language) {
        home = api.get(localized('/community'));
        unawaited(home.then<void>((_) {}, onError: (Object _) {}));
      }
      absorb(await session);
      startError = null;
      // Signed out on the server: drop the previous viewer's saved pages.
      if (user == null && stored != null) unawaited(pageStore?.clear());
      if (stored != null &&
          user != null &&
          value(stored['viewer']) == value(user!['id']) &&
          stored['locale'] == settings.language) {
        _restoreStored(stored);
        if (home != null) _adopt('/community', home);
      }
    } catch (e) {
      startError = e;
    }
    starting = false;
    notifyListeners();
    if (enablePush && startError == null && !_disposed) {
      unawaited(_initializePush());
    }
  }

  Future<void> _initializePush() async {
    try {
      await push.initialize();
      if (!_disposed) await push.bind(user, settings.language);
    } catch (_) {}
  }

  void absorb(Json envelope, {bool forceNotify = false}) {
    final oldUser = user, oldFeatures = features, oldCounts = counts;
    final previousId = user?['id'];
    if (envelope.containsKey('user')) {
      user = envelope['user'] is Map ? object(envelope['user']) : null;
    }
    if (previousId != user?['id']) _sessionGeneration++;
    if (envelope['features'] is Map) features = object(envelope['features']);
    // Reaction endpoints also answer with a `counts` map (like/love/funny);
    // only the session's badge counts may replace the dock badges.
    final nextCounts = envelope['counts'];
    if (nextCounts is Map &&
        (nextCounts.containsKey('notifications') ||
            nextCounts.containsKey('inbox'))) {
      counts = object(nextCounts);
    }
    final identityChanged =
        !deepJsonEquals(oldUser, user) ||
        !deepJsonEquals(oldFeatures, features);
    if (identityChanged) {
      // Profile details such as points or avatar only make cached pages
      // stale; scroll positions are kept unless access itself changed.
      bool same(String key) => deepJsonEquals(oldUser?[key], user?[key]);
      final accessChanged =
          !same('id') ||
          !same('role') ||
          !same('permissions') ||
          !same('community_ids') ||
          !deepJsonEquals(oldFeatures, features);
      invalidatePages(authorization: accessChanged);
    }
    // A page GET usually repeats the same session metadata. Broadcasting that
    // response used to rebuild every retained route and the entire MaterialApp.
    if (identityChanged || !deepJsonEquals(oldCounts, counts) || forceNotify) {
      notifyListeners();
    }
  }

  String localized(String path) {
    final uri = Uri.parse(api.safePath(path));
    return uri
        .replace(
          queryParameters: {...uri.queryParameters, 'lang': settings.language},
        )
        .toString();
  }

  Future<Json> get(String path) async {
    final session = _sessionGeneration,
        language = settings.language,
        viewer = user?['id'];
    try {
      final response = await api.get(localized(path));
      if (session == _sessionGeneration &&
          language == settings.language &&
          viewer == user?['id']) {
        absorb(response);
      }
      return response;
    } on ApiFailure catch (e) {
      if (session == _sessionGeneration &&
          viewer == user?['id'] &&
          (e.status == 401 || e.status == 419)) {
        await expired();
      }
      rethrow;
    }
  }

  /// Bumped by every write, so a GET that started before it cannot
  /// overwrite what the write changed.
  int mutationEpoch = 0;

  Future<Json> action(
    String method,
    String path, [
    Json data = const {},
    bool invalidate = true,
  ]) async {
    final session = _sessionGeneration, viewer = user?['id'];
    mutationEpoch++;
    try {
      final response = await api.send(method, localized(path), data);
      mutationEpoch++;
      if (session == _sessionGeneration && viewer == user?['id']) {
        if (invalidate) {
          invalidatePages();
        } else {
          markStale();
        }
        absorb(response, forceNotify: invalidate);
      }
      return response;
    } on ApiFailure catch (e) {
      if (session == _sessionGeneration &&
          viewer == user?['id'] &&
          (e.status == 401 || e.status == 419)) {
        await expired();
      }
      rethrow;
    }
  }

  Future<void> expired() async {
    unawaited(pageStore?.clear());
    // Study materials downloaded by the previous account stay private to it.
    unawaited(MaterialFiles.clear());
    // Stop showing the previous account's notifications on this device.
    if (enablePush && user != null) unawaited(push.unbind().catchError((_) {}));
    _sessionGeneration++;
    invalidatePages(authorization: true);
    activePage = null;
    user = null;
    await api.clearSession();
    navigator.currentState?.popUntil((r) => r.isFirst);
    rootNavigator?.currentState?.popUntil((r) => r.isFirst);
    notifyListeners();
  }

  Future<void> login(Json data) async {
    await action('POST', '/login', data);
    final session = _sessionGeneration;
    // The login response already signed the user in; a failed follow-up
    // refresh must not report the successful login as an error.
    try {
      final response = await api.get(localized('/mobile/session'));
      if (session != _sessionGeneration) return;
      absorb(response);
    } catch (_) {}
    if (enablePush && user != null) {
      try {
        await push.bind(user, settings.language);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> logout() async {
    if (enablePush) await push.unbind();
    await action('POST', '/logout');
    await expired();
  }

  bool enabled(String key) => features[key] != false;
  bool permission(String key) =>
      user?['role'] == 'super_admin' ||
      (user?['permissions'] is List &&
          (user!['permissions'] as List).contains(key)) ||
      (user?['admin_permissions'] is List &&
          (user!['admin_permissions'] as List).contains(key));
  Future<bool> Function()? navigationGuard;
  String currentPath = '/community';

  /// Leave a one-off screen (such as Edit profile) for [path] so Back does
  /// not return to the submitted or cancelled form.
  void leaveTo(String path, NativePageState from) =>
      open(path, replacing: from.pageRoute);

  void open(
    String path, {
    int tabDirection = 0,
    PageRoute<dynamic>? replacing,
    Json? seed,
  }) async {
    try {
      path = retainedPath(api.safePath(path));
    } catch (_) {
      return;
    }
    if (seed != null && user != null) {
      _seeds
        ..clear()
        ..[_pageKey(path)] = seed;
    }
    if (user == null || _preparingVisit) return;
    if (activePage != null && _pageKey(activePage!.path) == _pageKey(path)) {
      activePage!.scrollToTop();
      return;
    }
    _preparingVisit = true;
    try {
      if (navigationGuard != null && !await navigationGuard!()) return;
      final previous = activePage?.path ?? currentPath;
      final motion = WebVisitMotion.between(
        previous,
        path,
        tabDirection: tabDirection,
        rtl: settings.language == 'ar',
      );
      if (user == null || navigator.currentState == null) {
        return;
      }
      currentPath = path;
      final previousPage = activePage;
      final currentRoute = previousPage?.pageRoute;
      final targetKey = _pageKey(path);
      _routes.removeWhere((r) => !r.isActive || r.navigator == null);
      for (final old in _routes.toList()) {
        if (!identical(old, currentRoute) &&
            old.isActive &&
            (_pageKey(old.path) == targetKey || _routes.length >= 6)) {
          _routes.remove(old);
          navigator.currentState!.removeRoute(old);
        }
      }
      final route = WebPageRoute<void>(
        path: path,
        motion: motion,
        builder: (_) => NativePage(controller: this, path: path),
      );
      _routes.add(route);
      if (route.hasPreviousBody) previousPage?.departTo(route);
      final navigatorState = navigator.currentState!;
      navigatorState.push(route).whenComplete(() {
        previousPage?.finishDeparture(route);
      });
      if (replacing != null) {
        void removeReplaced() {
          if (replacing.isActive && replacing.navigator == navigatorState) {
            _routes.remove(replacing);
            navigatorState.removeRoute(replacing);
          }
        }

        final animation = route.animation;
        if (animation == null || animation.isCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => removeReplaced());
        } else {
          void listener(AnimationStatus status) {
            if (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed) {
              animation.removeStatusListener(listener);
              if (status == AnimationStatus.completed) removeReplaced();
            }
          }

          animation.addStatusListener(listener);
        }
      }
    } finally {
      _preparingVisit = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    chromeRevision.dispose();
    dockHidden.dispose();
    settings.removeListener(_settingsChanged);
    invalidatePages(authorization: true);
    push.dispose();
    super.dispose();
  }
}

class KeptNativePage {
  KeptNativePage(this.envelope, this.viewerId, {DateTime? fetchedAt})
    : storedAt = DateTime.now(),
      // Documents of unknown age are treated as old, never as fresh.
      fetchedAt = fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final dynamic viewerId;
  final Json envelope;
  final DateTime storedAt;

  /// When the server produced this document (not when it was last kept).
  final DateTime fetchedAt;
}

final _credentialKeyPattern = RegExp(
  r'password|token|secret|authorization|cookie',
  caseSensitive: false,
);

dynamic _withoutCredentials(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        if (!_credentialKeyPattern.hasMatch('${entry.key}'))
          '${entry.key}': _withoutCredentials(entry.value),
    };
  }
  if (value is List) return value.map(_withoutCredentials).toList();
  return value;
}
