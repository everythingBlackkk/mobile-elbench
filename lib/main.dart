import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'api.dart';
import 'native_glass.dart';
import 'settings.dart';
import 'push.dart';
import 'screens.dart';
import 'web_motion.dart';
import 'launch_experience.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  final api = LaravelApi();
  runApp(
    ElBenchApp(
      api: api,
      settings: settings,
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
  });
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
  @override
  void initState() {
    super.initState();
    controller = AppController(
      widget.api,
      widget.settings,
      navigator,
      enablePush: widget.enablePush,
      rootNavigator: rootNavigator,
    );
    _appState = _currentAppState;
    widget.settings.addListener(_changed);
    controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_changed);
    controller.removeListener(_controllerChanged);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ElBench',
    debugShowCheckedModeBanner: false,
    navigatorKey: rootNavigator,
    theme: widget.settings.theme(Brightness.light),
    darkTheme: widget.settings.theme(Brightness.dark),
    themeMode: widget.settings.mode,
    themeAnimationDuration: Duration.zero,
    locale: Locale(widget.settings.language),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
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
  }) {
    push = PushService(api, open);
    _language = settings.language;
    settings.addListener(_settingsChanged);
  }
  final MobileApi api;
  final AppSettings settings;
  final GlobalKey<NavigatorState> navigator;
  final GlobalKey<NavigatorState>? rootNavigator;
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
        DateTime.now().difference(kept.storedAt) >
            const Duration(minutes: 10)) {
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

  void rememberPage(String path, Json envelope, {double offset = 0}) {
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
    _pages.remove(key);
    _pages[key] = KeptNativePage(kept, user?['id']);
    rememberScroll(path, offset);
    while (_pages.length > 8) {
      _pages.remove(_pages.keys.first);
    }
  }

  /// Bumped by every pull-to-refresh. Covered screens compare it on reveal.
  int refreshEpoch = 0;
  void markAllStale() {
    _pages.clear();
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

  void invalidatePages({bool authorization = false}) {
    _pages.clear();
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
      absorb(await api.get(localized('/mobile/session')));
      startError = null;
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
    if (envelope['counts'] is Map) counts = object(envelope['counts']);
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

  Future<Json> action(
    String method,
    String path, [
    Json data = const {},
  ]) async {
    final session = _sessionGeneration, viewer = user?['id'];
    try {
      final response = await api.send(method, localized(path), data);
      if (session == _sessionGeneration && viewer == user?['id']) {
        invalidatePages();
        absorb(response, forceNotify: true);
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
  }) async {
    try {
      path = retainedPath(api.safePath(path));
    } catch (_) {
      return;
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
  KeptNativePage(this.envelope, this.viewerId) : storedAt = DateTime.now();
  final dynamic viewerId;
  final Json envelope;
  final DateTime storedAt;
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
