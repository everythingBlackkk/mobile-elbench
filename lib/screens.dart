import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'image_cache.dart';
import 'main.dart';
import 'forms.dart';
import 'quiz.dart';
import 'admin.dart';
import 'text_direction.dart';
import 'web_style.dart';
import 'web_home.dart';
import 'web_schedule.dart';
import 'schedule_admin.dart';
import 'schedule_appearance_admin.dart';
import 'web_messages.dart';
import 'web_profile.dart';
import 'native_glass.dart';
import 'web_settings.dart';
import 'web_forum.dart';
import 'web_motion.dart';
import 'web_profile_edit.dart';
import 'web_hall.dart';
import 'web_content.dart';
import 'web_ai.dart';
import 'web_security.dart';
import 'web_auth.dart';
import 'app_menus.dart';
import 'refresh_wordmark.dart';
import 'error_panel.dart';
import 'infinite_feed.dart';

export 'refresh_wordmark.dart' show ElBenchHeaderLogo;
export 'error_panel.dart' show ErrorPanel;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final id = TextEditingController(), password = TextEditingController();
  bool busy = false, obscured = true;
  String? error;
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.login({
        'university_id': id.text.trim(),
        'password': password.text,
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context),
        muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            AuthHeader(controller: c),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      c.t('Log in', 'تسجيل الدخول'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 28,
                        height: 1.4,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.t(
                        'Pick up where you left off.',
                        'كمّل حكايتك من آخر مرة.',
                      ),
                      style: TextStyle(fontSize: 14, height: 1.8, color: muted),
                    ),
                    const SizedBox(height: 28),
                    if (error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: .08),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(
                              alpha: .25,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                            height: 1.7,
                          ),
                        ),
                      ),
                    label(c.t('University ID', 'رقم الكارنيه (ID)')),
                    TextFormField(
                      key: const ValueKey('login.id'),
                      controller: id,
                      keyboardType: TextInputType.text,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        hintText: c.t(
                          'Enter your university ID',
                          'اكتب رقم الكارنيه بتاعك',
                        ),
                      ),
                      style: const TextStyle(fontSize: 16),
                      validator: (v) => v!.trim().isEmpty
                          ? c.t(
                              'Enter your university ID',
                              'أدخل الرقم الجامعي',
                            )
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.t('Password', 'كلمة السر'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: forgotPassword,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              c.t('Forgot your password?', 'نسيت كلمة السر؟'),
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('login.password'),
                      controller: password,
                      obscureText: obscured,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscured ? Icons.visibility : Icons.visibility_off,
                            size: 18,
                            color: muted,
                          ),
                          onPressed: () => setState(() => obscured = !obscured),
                        ),
                      ),
                      onFieldSubmitted: (_) => busy ? null : login(),
                      validator: (v) => v!.isEmpty
                          ? c.t('Enter your password', 'أدخل كلمة المرور')
                          : null,
                    ),
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xff18251a),
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        key: const ValueKey('login.submit'),
                        onPressed: busy ? null : login,
                        style:
                            FilledButton.styleFrom(
                              backgroundColor: const Color(0xff428735),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xff356e2a),
                              disabledForegroundColor: Colors.white.withValues(
                                alpha: 0.92,
                              ),
                              minimumSize: const Size(double.infinity, 49),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                                side: const BorderSide(
                                  color: Color(0xff18251a),
                                  width: 1.5,
                                ),
                              ),
                            ).copyWith(
                              overlayColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.pressed)) {
                                  return const Color(
                                    0xff2c5d23,
                                  ).withValues(alpha: 0.35);
                                }
                                if (states.contains(WidgetState.hovered) ||
                                    states.contains(WidgetState.focused)) {
                                  return Colors.white.withValues(alpha: 0.08);
                                }
                                return null;
                              }),
                            ),
                        child: Text(
                          busy
                              ? c.t('Signing in…', 'جارٍ الدخول…')
                              : c.t('Log in', 'دخول'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(
                          c.t('Don’t have an account?', 'معندكش حساب؟'),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.8,
                            color: muted,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SignupPage(controller: c),
                            ),
                          ),
                          child: Text(
                            c.t('Create an account', 'سجل حساب جديد'),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.8,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void forgotPassword() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          WebSignupPage(controller: widget.controller, passwordReset: true),
    ),
  );
}

class ElBenchBrandLogo extends StatelessWidget {
  const ElBenchBrandLogo({
    super.key,
    this.width = 120,
    this.height = 28,
    this.semanticLabel = 'ElBench',
  });
  final double width;
  final double height;
  final String? semanticLabel;

  static const _lightInvertMatrix = ColorFilter.matrix(<double>[
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/logo.png',
      width: width,
      height: height,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.09),
      semanticLabel: semanticLabel,
    );
    return Theme.of(context).brightness == Brightness.dark
        ? logo
        : ColorFiltered(colorFilter: _lightInvertMatrix, child: logo);
  }
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context), scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const ElBenchBrandLogo(width: 120, height: 28),
          Row(
            children: [
              InkWell(
                onTap: () => c.settings.setLanguage(
                  c.settings.language == 'ar' ? 'en' : 'ar',
                ),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 39,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      const WebIcon('globe', size: 16),
                      const SizedBox(width: 7),
                      Text(
                        c.t('العربية', 'English'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => c.settings.setMode(
                  theme.brightness == Brightness.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: WebIcon(
                    theme.brightness == Brightness.dark ? 'moon' : 'moon',
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SignupPage extends StatelessWidget {
  const SignupPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => WebSignupPage(controller: controller);
}

/// One chrome tree for the whole signed-in session. Route transitions only
/// animate bodies; platform glass views never leave the tree on tab changes.
class SharedNavigationChrome extends StatelessWidget {
  const SharedNavigationChrome({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      ValueListenableBuilder<int>(
        valueListenable: controller.chromeRevision,
        builder: (context, _, _) {
          final page = controller.activePage;
          return Offstage(
            offstage: page == null || !page.mounted || controller.user == null,
            // Keep UIKit glass mounted and painted while a menu is open.
            // Hiding its render subtree can leave the native surface black
            // when the popup closes. The modal still owns all interaction.
            child: ExcludeFocus(
              excluding: controller.modalVisible,
              child: ExcludeSemantics(
                excluding: controller.modalVisible,
                child: IgnorePointer(
                  ignoring: controller.modalVisible,
                  child: page == null || !page.mounted
                      ? const SizedBox.shrink()
                      : Material(
                          type: MaterialType.transparency,
                          child: Stack(
                            children: [
                              Align(
                                key: const ValueKey('navigation.headerSlot'),
                                alignment: Alignment.topCenter,
                                child: Visibility(
                                  key: const ValueKey(
                                    'navigation.headerVisibility',
                                  ),
                                  visible:
                                      page.screen != 'terms' &&
                                      page.error == null,
                                  maintainState: true,
                                  maintainAnimation: true,
                                  maintainSize: true,
                                  child: RepaintBoundary(
                                    key: const ValueKey(
                                      'navigation.sharedHeader',
                                    ),
                                    child: ColoredBox(
                                      color: page.effectiveProfileChrome
                                          ? Colors.transparent
                                          : page.chromeBackground(context),
                                      child: page.header(context, active: true),
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                key: const ValueKey('navigation.dockSlot'),
                                alignment: Alignment.bottomCenter,
                                child: Visibility(
                                  key: const ValueKey(
                                    'navigation.dockVisibility',
                                  ),
                                  visible:
                                      !page.hideBottomNav && page.error == null,
                                  maintainState: true,
                                  maintainAnimation: true,
                                  maintainSize: true,
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: controller.dockHidden,
                                    child: RepaintBoundary(
                                      key: const ValueKey(
                                        'navigation.sharedDock',
                                      ),
                                      child: WebBottomNav(
                                        controller: controller,
                                        path: page.path,
                                      ),
                                    ),
                                    builder: (context, hidden, child) {
                                      final reduce =
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          ) ||
                                          MediaQuery.of(
                                            context,
                                          ).accessibleNavigation;
                                      return ExcludeFocus(
                                        excluding: hidden,
                                        child: ExcludeSemantics(
                                          excluding: hidden,
                                          child: IgnorePointer(
                                            ignoring: hidden,
                                            child: AnimatedSlide(
                                              key: const ValueKey(
                                                'navigation.dockSlide',
                                              ),
                                              offset: hidden
                                                  ? const Offset(0, 1.3)
                                                  : Offset.zero,
                                              duration: reduce
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 280,
                                                    ),
                                              curve: Curves.easeOutCubic,
                                              child: child,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

class ChromeRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  ChromeRouteObserver(this.controller);
  final AppController controller;
  final _popups = <Route<dynamic>>{};
  void _sync() {
    controller.modalVisible = _popups.isNotEmpty;
    controller.updateChrome();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is! WebPageRoute && route.settings.name != '/') {
      _popups.add(route);
    }
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _popups.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _popups.remove(route);
    _sync();
  }
}

class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => SharedNavigationChrome(
    controller: controller,
    child: NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => controller.navigator.currentState?.pop(),
      child: Navigator(
        key: controller.navigator,
        observers: [controller.routeObserver],
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/'),
          builder: (_) => NativePage(
            controller: controller,
            path: controller.enabled('community') ? '/community' : '/profile',
            root: true,
          ),
        ),
      ),
    ),
  );
}

class WebBottomNav extends StatefulWidget {
  const WebBottomNav({
    super.key,
    required this.controller,
    required this.path,
    this.active = true,
  });
  final AppController controller;
  final String path;
  final bool active;
  @override
  State<WebBottomNav> createState() => _WebBottomNavState();
}

class _WebBottomNavState extends State<WebBottomNav> {
  final _pillKey = GlobalKey();
  final ValueNotifier<double?> _dragPosition = ValueNotifier<double?>(null);
  final ValueNotifier<int?> _hoveredIndex = ValueNotifier<int?>(null);
  int? _settledIndex;
  int? _activePointer;
  Offset? _downPosition;
  bool _isDragging = false;

  @override
  void didUpdateWidget(WebBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _settledIndex = null;
    }
  }

  @override
  void dispose() {
    _dragPosition.dispose();
    _hoveredIndex.dispose();
    super.dispose();
  }

  void _updateDrag(Offset localPosition, int count) {
    if (!widget.active || count <= 0) return;
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    final totalWidth = box?.size.width ?? 0;
    if (totalWidth <= 20) return;
    final slotWidth = (totalWidth - 20) / count;
    final raw = ((localPosition.dx - 10) / slotWidth) - 0.5;
    final clamped = raw.clamp(0.0, (count - 1).toDouble());
    _dragPosition.value = clamped;
    final nextHover = clamped.round().clamp(0, count - 1);
    if (_hoveredIndex.value != nextHover) {
      final hadPrevious = _hoveredIndex.value != null;
      _hoveredIndex.value = nextHover;
      if (hadPrevious) HapticFeedback.selectionClick();
    }
  }

  void _endDrag(
    List<(String, String, String)> items,
    String uri,
    int activeSelection,
  ) {
    final target = _hoveredIndex.value;
    _dragPosition.value = null;
    _hoveredIndex.value = null;
    if (!widget.active ||
        target == null ||
        target < 0 ||
        target >= items.length) {
      return;
    }
    final item = items[target];
    if (uri == item.$1) {
      widget.controller.activePage?.scrollToTop();
      return;
    }
    final direction = activeSelection < 0 ? 0 : (target - activeSelection).sign;
    setState(() => _settledIndex = target);
    widget.controller.open(item.$1, tabDirection: direction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _settledIndex != null) {
        setState(() => _settledIndex = null);
      }
    });
  }

  void _cancelDrag() {
    _activePointer = null;
    _downPosition = null;
    _isDragging = false;
    _dragPosition.value = null;
    _hoveredIndex.value = null;
  }

  @override
  Widget build(BuildContext context) => widget.active
      ? ListenableBuilder(listenable: widget.controller, builder: _contents)
      : _contents(context, null);

  Widget _contents(BuildContext context, Widget? _) {
    final c = widget.controller, scheme = Theme.of(context).colorScheme;
    final items = <(String, String, String)>[
      if (c.enabled('community'))
        ('/community', 'home', c.t('Home', 'الرئيسية')),
      ('/people', 'compass', c.t('Find People', 'اكتشف الناس')),
      ('/schedule', 'calendar', c.t('Schedule', 'الجدول')),
      ('/notifications', 'bell', c.t('Notifications', 'الإشعارات')),
      ('/inbox', 'inbox', c.t('Inbox', 'الوارد')),
      ('/profile', 'profile', c.t('Profile', 'البروفايل')),
    ];
    final uri = Uri.parse(widget.path).path;
    bool selected((String, String, String) item) => item.$1 == '/community'
        ? ['/community', '/forum', '/moderate', '/ask-question'].contains(uri)
        : uri.startsWith(item.$1) ||
              item.$1 == '/inbox' && uri.startsWith('/ask/');
    final selection = items.indexWhere(selected);
    final decoration = BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .97),
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .28 : .08,
          ),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: .04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: ValueListenableBuilder<int?>(
          valueListenable: _hoveredIndex,
          builder: (context, hovered, child) {
            final effectiveSelection =
                hovered ?? _settledIndex ?? (selection < 0 ? null : selection);
            return NativeGlassSurface(
              enabled: widget.active,
              selectionIndex: effectiveSelection,
              selectionCount: items.length,
              dragPosition: _dragPosition,
              decoration: decoration,
              child: child!,
            );
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              _activePointer = e.pointer;
              _downPosition = e.localPosition;
              _isDragging = false;
            },
            onPointerMove: (e) {
              if (_activePointer != e.pointer || _downPosition == null) return;
              if (!_isDragging &&
                  (e.localPosition.dx - _downPosition!.dx).abs() > 2.5) {
                _isDragging = true;
                HapticFeedback.selectionClick();
              }
              if (_isDragging) {
                _updateDrag(e.localPosition, items.length);
              }
            },
            onPointerUp: (e) {
              if (_activePointer != e.pointer) return;
              _activePointer = null;
              _downPosition = null;
              if (_isDragging || _dragPosition.value != null) {
                _endDrag(items, uri, selection);
                Future.microtask(() => _isDragging = false);
              }
            },
            onPointerCancel: (e) {
              if (_activePointer == e.pointer) _cancelDrag();
            },
            child: GestureDetector(
              key: _pillKey,
              behavior: HitTestBehavior.translucent,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: (d) {
                _isDragging = true;
                _updateDrag(d.localPosition, items.length);
              },
              onHorizontalDragUpdate: (d) {
                _isDragging = true;
                _updateDrag(d.localPosition, items.length);
              },
              onHorizontalDragEnd: (_) {
                _endDrag(items, uri, selection);
                Future.microtask(() => _isDragging = false);
              },
              onHorizontalDragCancel: _cancelDrag,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  textDirection: TextDirection.ltr,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final (itemIndex, item) in items.indexed)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final active = item.$1 == '/community'
                                ? uri == '/community' ||
                                      uri == '/forum' ||
                                      uri == '/moderate' ||
                                      uri == '/ask-question'
                                : uri.startsWith(item.$1) ||
                                      item.$1 == '/inbox' &&
                                          uri.startsWith('/ask/');
                            final count = item.$1 == '/notifications'
                                ? int.tryParse(
                                        value(c.counts['notifications']),
                                      ) ??
                                      0
                                : item.$1 == '/inbox'
                                ? int.tryParse(value(c.counts['inbox'])) ?? 0
                                : 0;
                            return Tooltip(
                              message: item.$3,
                              child: Semantics(
                                label: item.$3,
                                button: true,
                                selected: active,
                                child: InkWell(
                                  key: ValueKey(
                                    'dock.${item.$1.substring(1) == 'community' ? 'home' : item.$1.substring(1)}',
                                  ),
                                  borderRadius: BorderRadius.circular(50),
                                  onTap: () {
                                    if (_isDragging) return;
                                    if (uri == item.$1) {
                                      c.activePage?.scrollToTop();
                                    } else {
                                      final current = items.indexWhere(
                                        (i) => i.$1 == '/community'
                                            ? uri == '/community' ||
                                                  uri == '/forum' ||
                                                  uri == '/moderate' ||
                                                  uri == '/ask-question'
                                            : uri.startsWith(i.$1) ||
                                                  i.$1 == '/inbox' &&
                                                      uri.startsWith('/ask/'),
                                      );
                                      final target = itemIndex;
                                      final direction = current < 0
                                          ? 0
                                          : (target - current).sign;
                                      c.open(item.$1, tabDirection: direction);
                                    }
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ValueListenableBuilder<int?>(
                                          valueListenable: _hoveredIndex,
                                          builder: (context, hovered, _) {
                                            final override =
                                                hovered ?? _settledIndex;
                                            final highlighted = override != null
                                                ? override == itemIndex
                                                : active;
                                            return WebIcon(
                                              item.$2,
                                              size: 24,
                                              color: highlighted
                                                  ? scheme.primary
                                                  : scheme.onSurfaceVariant,
                                            );
                                          },
                                        ),
                                        if (count > 0)
                                          Positioned(
                                            top: -8,
                                            right: -9,
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: c.settings.accent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(
                                                    context,
                                                  ).scaffoldBackgroundColor,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Text(
                                                count > 99 ? '99+' : '$count',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
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
          ),
        ),
      ),
    );
  }
}

class NativePage extends StatefulWidget {
  const NativePage({
    super.key,
    required this.controller,
    required this.path,
    this.root = false,
  });
  final AppController controller;
  final String path;
  final bool root;
  @override
  State<NativePage> createState() => NativePageState();
}

class NativePageState extends State<NativePage> with RouteAware {
  Json envelope = {}, data = {};
  String screen = '', path = '';
  bool loading = true;
  Object? error;
  AppController get c => widget.controller;
  Widget? _contentWidget;
  ThemeData? _contentTheme;
  Size? _contentViewport;
  WebPageRoute<dynamic>? _incomingVisit;
  final ValueNotifier<double> scrollOffset = ValueNotifier<double>(0);
  final ValueNotifier<double> headerOffset = ValueNotifier<double>(0);
  final ValueNotifier<bool> headerCollapsed = ValueNotifier<bool>(false);
  final ValueNotifier<double> homePullProgress = ValueNotifier<double>(0);
  final ValueNotifier<bool> homeRefreshing = ValueNotifier<bool>(false);
  late final ScrollController _pageScroll;
  ScrollPosition? _observedPosition;
  PageRoute<dynamic>? _observedRoute;
  PageRoute<dynamic>? get pageRoute => _observedRoute;
  int _request = 0, _loadedGeneration = 0, _loadedRefreshEpoch = 0;
  double? _pendingScrollOffset;
  bool _scrollNotificationScheduled = false;
  ScrollDirection _dockScrollDirection = ScrollDirection.idle;
  double _dockScrollDistance = 0;
  final Map<String, TextEditingController> _searchControllers = {};
  TextEditingController _searchController(String key) =>
      _searchControllers.putIfAbsent(
        key,
        () => TextEditingController(
          text: Uri.parse(path).queryParameters[key] ?? '',
        ),
      );
  @override
  void initState() {
    super.initState();
    path = c.retainedPath(widget.path);
    final cached = c.cachedPage(path);
    final offset = c.keptScrollOffset(path);
    scrollOffset.value = offset;
    headerOffset.value = offset <= 48 ? 0.0 : offset.clamp(48.0, 120.0);
    headerCollapsed.value = offset >= 108;
    _pageScroll = ScrollController(initialScrollOffset: offset);
    if (cached == null) {
      screen = switch (Uri.parse(path).path) {
        '/community' => 'community.index',
        '/people' => 'people.index',
        '/quiz' => 'quiz.index',
        '/schedule' => 'schedule.index',
        '/notifications' => 'notifications.index',
        '/inbox' => 'ask.inbox',
        '/profile' => 'profile.show',
        '/menu' => 'content.menu',
        '/hall-of-fame' => 'content.hall',
        final route when RegExp(r'^/community/posts/\d+/?$').hasMatch(route) =>
          'community.post',
        final route when RegExp(r'^/users/[^/]+/?$').hasMatch(route) =>
          'profile.user',
        _ => '',
      };
    }
    var fresh = false;
    if (cached != null) {
      envelope = cached.envelope;
      data = object(envelope['data']);
      screen = value(envelope['screen']);
      loading = false;
      _fetchedAt = cached.fetchedAt;
      fresh =
          DateTime.now().difference(cached.fetchedAt) <
              AppController.freshPageAge &&
          // These two reflect read state and keep their own revalidation.
          screen != 'ask.inbox' &&
          screen != 'notifications.index';
    } else {
      // A tapped row (for example a feed post) renders at once; the full
      // document, including comments, replaces it when it arrives.
      final seed = c.takeSeed(path);
      if (seed != null && value(seed['screen']).isNotEmpty) {
        envelope = seed;
        data = object(seed['data']);
        screen = value(seed['screen']);
        provisional = true;
      } else {
        // Uncached pages slide in with a skeleton instead of holding the
        // previous page on screen for the whole network round trip.
        _revealTimer = Timer(const Duration(milliseconds: 90), () {
          if (mounted && loading && envelope.isEmpty) {
            setState(() => _revealLoading = true);
          }
        });
      }
    }
    c.addListener(_controllerChanged);
    _loadedGeneration = c.cacheGeneration;
    _loadedRefreshEpoch = c.refreshEpoch;
    if (!fresh) load(null, true);
  }

  /// True while showing a seeded preview instead of the server's document.
  bool provisional = false;
  Json? _rememberedData;
  bool _revealLoading = false;
  Timer? _revealTimer;
  DateTime? _fetchedAt;

  void _controllerChanged() {
    _contentWidget = null;
    if (mounted && (_observedRoute?.isCurrent ?? true)) {
      setState(() {});
      c.updateChrome();
    }
  }

  void departTo(WebPageRoute<dynamic> route) {
    if (mounted) setState(() => _incomingVisit = route);
  }

  void finishDeparture(WebPageRoute<dynamic> route) {
    if (mounted && identical(_incomingVisit, route)) {
      setState(() => _incomingVisit = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context), viewport = MediaQuery.sizeOf(context);
    if (_contentTheme != theme || _contentViewport != viewport) {
      _contentTheme = theme;
      _contentViewport = viewport;
      _contentWidget = null;
    }
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _observedRoute) {
      if (_observedRoute != null) c.routeObserver.unsubscribe(this);
      _observedRoute = route;
      c.routeObserver.subscribe(this, route);
    }
    if (route?.isCurrent ?? false) c.activatePage(this);
  }

  @override
  void didPush() => c.activatePage(this);
  @override
  void didPop() {
    c.rememberScroll(path, scrollOffset.value);
  }

  @override
  void didPopNext() {
    _dockScrollDirection = ScrollDirection.idle;
    _dockScrollDistance = 0;
    c.activatePage(this);
    _contentWidget = null;
    // Metadata may have changed while this route was covered. Hidden pages do
    // not need to rebuild on every badge or session update.
    if (mounted) setState(() {});
    if (_loadedGeneration != c.cacheGeneration ||
        _loadedRefreshEpoch != c.refreshEpoch) {
      load();
    }
  }

  @override
  void didPushNext() {
    _dockScrollDirection = ScrollDirection.idle;
    _dockScrollDistance = 0;
    if (provisional || envelope.isEmpty) return;
    // This runs in the frame of every push; skip the sanitizing deep copy
    // when the retained document already holds exactly this data.
    if (identical(data, _rememberedData) && c.keptPageAge(path) != null) {
      c.rememberScroll(path, scrollOffset.value);
      return;
    }
    _rememberedData = data;
    c.rememberPage(
      path,
      {...envelope, 'screen': screen, 'data': data},
      offset: scrollOffset.value,
      fetchedAt: _fetchedAt,
    );
  }

  void reportScrollOffset(double offset) {
    if (!mounted || !offset.isFinite) return;
    final next = offset < 0 ? 0.0 : offset;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _pendingScrollOffset = next;
      if (!_scrollNotificationScheduled) {
        _scrollNotificationScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollNotificationScheduled = false;
          final pending = _pendingScrollOffset;
          _pendingScrollOffset = null;
          if (mounted && pending != null) reportScrollOffset(pending);
        });
      }
      return;
    }
    if (scrollOffset.value != next) scrollOffset.value = next;
    if (profilePage) {
      final bounded = next <= 48 ? 0.0 : next.clamp(48.0, 120.0);
      if (headerOffset.value != bounded) headerOffset.value = bounded;
      final collapsed = bounded >= 108;
      if (headerCollapsed.value != collapsed) headerCollapsed.value = collapsed;
    }
  }

  void _reportDockScroll(ScrollNotification notification) {
    if (!identical(c.activePage, this) || hideBottomNav || c.modalVisible) {
      return;
    }
    final metrics = notification.metrics;
    if (notification is UserScrollNotification) {
      _dockScrollDirection = notification.direction;
      _dockScrollDistance = 0;
    }
    // Restoring a cached offset and programmatic scrolling should not hide the
    // dock. Only a user's vertical scroll supplies a non-idle direction.
    if (notification is ScrollEndNotification) {
      _dockScrollDirection = ScrollDirection.idle;
      _dockScrollDistance = 0;
    }
    if (metrics.pixels <= metrics.minScrollExtent + 1) {
      c.setDockHidden(false);
      return;
    }
    if (metrics.outOfRange ||
        metrics.maxScrollExtent <= metrics.minScrollExtent ||
        notification is! ScrollUpdateNotification ||
        _dockScrollDirection == ScrollDirection.idle) {
      return;
    }
    final delta = notification.scrollDelta ?? 0;
    final down = _dockScrollDirection == ScrollDirection.reverse;
    // Ignore the return leg of an iOS overscroll bounce and tiny finger jitter.
    if ((down && delta <= 0) || (!down && delta >= 0)) return;
    _dockScrollDistance += delta.abs();
    if (_dockScrollDistance >= 8) c.setDockHidden(down);
  }

  void scrollToTop() {
    c.setDockHidden(false);
    final positions = _pageScroll.hasClients
        ? _pageScroll.positions.toList()
        : <ScrollPosition>[
            if (_observedPosition?.hasPixels == true) _observedPosition!,
          ];
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    for (final position in positions) {
      if (reduce) {
        position.jumpTo(0);
      } else {
        position.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: WebVisitMotion.curve,
        );
      }
    }
    reportScrollOffset(0);
  }

  /// Revalidate after the app returns from a longer stay in the background.
  /// Screens holding unsent input or a running quiz keep their state.
  void reloadOnResume() {
    if (!mounted ||
        loading ||
        screen.startsWith('quiz.') ||
        screen.startsWith('ai.') ||
        screen == 'profile.edit' ||
        screen == 'community.ask' ||
        screen == 'profile.password-reset' ||
        profilePage ||
        screen == 'ask.inbox' ||
        screen == 'notifications.index') {
      return;
    }
    _loadedRefreshEpoch = c.refreshEpoch;
    load();
  }

  void reloadForLocale() {
    if (profilePage ||
        screen == 'ask.inbox' ||
        screen == 'notifications.index') {
      _loadedGeneration = c.cacheGeneration;
      return;
    }
    if (mounted) load();
  }

  @override
  void dispose() {
    c.routeObserver.unsubscribe(this);
    c.removeListener(_controllerChanged);
    if (identical(c.activePage, this)) {
      c.activePage = null;
      c.updateChrome();
    }
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    _revealTimer?.cancel();
    _pageScroll.dispose();
    scrollOffset.dispose();
    headerOffset.dispose();
    headerCollapsed.dispose();
    homePullProgress.dispose();
    homeRefreshing.dispose();
    super.dispose();
  }

  /// A user's pull-to-refresh: reload this screen and make every other
  /// retained screen fetch fresh content (and badge counts) when revealed.
  Future<void> pullRefresh() {
    if (!mounted) return Future.value();
    c.markAllStale();
    _loadedRefreshEpoch = c.refreshEpoch;
    _pullRefreshing = true;
    return load().whenComplete(() => _pullRefreshing = false);
  }

  Future<void> refreshHome() async {
    if (!mounted) return;
    homeRefreshing.value = true;
    try {
      await pullRefresh();
    } finally {
      if (mounted) {
        homeRefreshing.value = false;
        homePullProgress.value = 0;
      }
    }
  }

  Future<void> load([String? destination, bool initial = false]) async {
    if (!mounted) return;
    final request = ++_request,
        session = c.sessionGeneration,
        viewer = c.user?['id'],
        language = c.settings.language,
        mutation = c.mutationEpoch;
    if (destination != null && path != destination) {
      c.rememberScroll(path, scrollOffset.value);
      path = destination;
      reportScrollOffset(c.keptScrollOffset(path));
    }
    final hadCached =
        initial && envelope.isNotEmpty && error == null && destination == null;
    final previousScreen = screen;
    final previousData = data;
    final recovering = error != null;
    var unchanged = false;
    if (envelope.isEmpty || error != null) {
      setState(() {
        loading = true;
      });
    } else {
      loading = true;
    }
    try {
      // Validate the request's viewer before absorbing its session envelope.
      // A first authorized GET can legitimately establish a previously unknown
      // viewer; checking afterwards rejects that response as an account switch.
      final response = await c.fetchPage(path);
      if (mounted && request == _request && mutation != c.mutationEpoch) {
        // A write finished while this GET was in flight; its answer may
        // predate the write. Ask again rather than showing older data.
        unawaited(Future.microtask(load));
        return;
      }
      if (!mounted ||
          request != _request ||
          session != c.sessionGeneration ||
          viewer != c.user?['id'] ||
          language != c.settings.language) {
        return;
      }
      c.absorb(response);
      envelope = response;
      if (envelope['canonical_url'] is String) {
        path = c.api.safePath(envelope['canonical_url']);
      }
      data = object(envelope['data']);
      screen = value(envelope['screen']);
      provisional = false;
      _fetchedAt = DateTime.now();
      if (screen == 'community.index') c.warmLikelyPages();
      _loadedGeneration = c.cacheGeneration;
      _appendErrors.clear();
      // A reload after an action (or on return) fetches the first page only.
      // Keep the rows the reader already scrolled through below it; a
      // pull-to-refresh or a different destination starts from the top.
      if (_pullRefreshing ||
          _resetPaging ||
          destination != null ||
          previousScreen != screen) {
        _appended.clear();
      } else {
        // A reload (after an action, on return, or of a restored document)
        // fetches the first page only. Keep the rows the reader already
        // scrolled through below it; a pull-to-refresh starts at the top.
        final keys = <String, String?>{..._appended};
        for (final entry in previousData.entries) {
          final kept = entry.value;
          if (kept is Map &&
              kept['data'] is List &&
              kept.containsKey('next_page_url') &&
              rows(kept).length > rows(data[entry.key]).length) {
            keys.putIfAbsent(entry.key, () => null);
          }
        }
        if (keys.isNotEmpty) {
          final merged = <String, dynamic>{...data};
          keys.forEach((pageKey, listKey) {
            final fresh = object(merged[pageKey]),
                kept = object(previousData[pageKey]);
            if (fresh.isEmpty || kept.isEmpty) return;
            final freshRows = listKey == null
                ? rows(fresh)
                : rows({'data': merged[listKey]});
            final keptRows = listKey == null
                ? rows(kept)
                : rows({'data': previousData[listKey]});
            final continued = continueRows(freshRows, keptRows);
            if (continued == null) return;
            merged[pageKey] = {
              ...fresh,
              'next_page_url': kept['next_page_url'],
              if (listKey == null) 'data': continued,
            };
            if (listKey != null) merged[listKey] = continued;
            _appended[pageKey] = listKey;
          });
          data = merged;
          envelope = {...envelope, 'data': data};
        }
      }
      _resetPaging = false;
      unchanged =
          hadCached &&
          previousScreen == screen &&
          screen != 'ask.inbox' &&
          screen != 'notifications.index' &&
          deepJsonEquals(previousData, data);
      if (unchanged) {
        c.rememberScroll(path, scrollOffset.value);
        c.markFetched(path, _fetchedAt!);
        _rememberedData = data;
      } else {
        c.rememberPage(
          path,
          envelope,
          offset: scrollOffset.value,
          fetchedAt: _fetchedAt,
        );
        _rememberedData = data;
      }
      error = null;
      if (_observedRoute?.isCurrent ?? false) {
        if (recovering) c.setDockHidden(false);
        c.activatePage(this);
      }
    } catch (e) {
      if (mounted &&
          request == _request &&
          session == c.sessionGeneration &&
          viewer == c.user?['id'] &&
          language == c.settings.language) {
        if (e is ApiFailure && (e.status == 401 || e.status == 419)) {
          await c.expired();
          return;
        }
        error = e;
      }
    } finally {
      if (mounted && request == _request) {
        if (unchanged && error == null && _contentWidget != null) {
          loading = false;
        } else {
          setState(() {
            _contentWidget = null;
            loading = false;
          });
        }
        if (identical(c.activePage, this) && (recovering || error != null)) {
          c.updateChrome(immediate: true);
        }
      }
    }
  }

  Future<void> run(
    String method,
    String destination, [
    Json payload = const {},
    bool back = false,
  ]) async {
    try {
      await c.action(method, destination, payload);
      if (!mounted) return;
      if (method == 'DELETE') _resetPaging = true;
      if (back) {
        Navigator.pop(context);
      } else {
        await load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<Json?> form(
    String title,
    String destination,
    List<FieldSpec> fields, {
    String method = 'POST',
    Json fixed = const {},
    bool follow = false,
    bool destructive = false,
  }) async {
    final result = await showActionForm(
      context,
      c,
      title: title,
      path: destination,
      method: method,
      fields: fields,
      fixed: fixed,
      destructive: destructive,
    );
    if (result != null && mounted) {
      final redirect = result['redirect_url'] ?? result['url'];
      if (follow && redirect is String) {
        c.open(redirect);
      } else {
        await load();
      }
    }
    return result;
  }

  void query(Json changes) {
    final uri = Uri.parse(path);
    final params = {...uri.queryParameters};
    for (final e in changes.entries) {
      if (e.value == null || e.value == '') {
        params.remove(e.key);
      } else {
        params[e.key] = '${e.value}';
      }
    }
    params.remove('page');
    load(uri.replace(queryParameters: params).toString());
  }

  Widget heading(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 18),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
  Widget empty([String? message]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        Icon(
          Icons.spa_outlined,
          size: 42,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(
          message ??
              c.t(
                'Nothing here yet. Check back soon.',
                'لا يوجد شيء هنا بعد. عُد قريبًا.',
              ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
  Widget search(String key, String hint) {
    final controller = _searchController(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AdaptiveTextField(
        controller: controller,
        field: (direction) => TextFormField(
          key: ValueKey('$path-search'),
          controller: controller,
          textDirection: direction,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (v) => query({key: v}),
        ),
      ),
    );
  }

  Widget chips(List<(String, String)> tabs, String key, String selected) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8, bottom: 16),
                child: ChoiceChip(
                  label: Text(tab.$2),
                  selected: selected == tab.$1,
                  onSelected: (_) => query({key: tab.$1}),
                ),
              ),
          ],
        ),
      );
  Widget pagination(dynamic page) {
    final p = object(page);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (p['prev_page_url'] is String)
          TextButton.icon(
            onPressed: () => load(p['prev_page_url']),
            icon: const Icon(Icons.chevron_left),
            label: Text(c.t('Previous', 'السابق')),
          ),
        if (p['next_page_url'] is String)
          TextButton.icon(
            onPressed: () => load(p['next_page_url']),
            icon: const Icon(Icons.chevron_right),
            label: Text(c.t('Next', 'التالي')),
          ),
      ],
    );
  }

  /// Paginated lists that have rows appended beyond their first page,
  /// mapped to the key that holds their rows (null: the paginator's own).
  final Map<String, String?> _appended = {};
  bool _pullRefreshing = false;
  // Set by deletions: a removed row must not be restored from older pages.
  bool _resetPaging = false;

  /// Apply a reaction and update the row in place from the server's counts,
  /// so lists extended by infinite scroll keep their rows and position.
  Future<void> react(String endpoint, Json row, String reaction) async {
    try {
      final response = await c.action('POST', endpoint, {
        'reaction': reaction,
      }, false);
      if (!mounted) return;
      final counts = object(response['counts']);
      if (!response.containsKey('selected') || counts.isEmpty) {
        await load();
        return;
      }
      final selected = response['selected'];
      final changes = <String, dynamic>{
        'reactions': selected is String
            ? [
                {'type': selected, 'user_id': c.user?['id']},
              ]
            : <Json>[],
        for (final type in const ['like', 'love', 'funny'])
          '${type}_count': int.tryParse(value(counts[type])) ?? 0,
      };
      setState(() {
        _patchRow(data, row, changes);
        _contentWidget = null;
      });
      // Keep the patched row when this screen is restored from the cache.
      c.rememberPage(
        path,
        {...envelope, 'data': data},
        offset: scrollOffset.value,
        fetchedAt: _fetchedAt,
      );
      _rememberedData = null;
      _loadedGeneration = c.cacheGeneration;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Rendered rows are copies; find the source rows by identity fields.
  static void _patchRow(dynamic node, Json row, Json changes) {
    if (node is Map) {
      if (node['id'] != null &&
          value(node['id']) == value(row['id']) &&
          value(node['content']) == value(row['content']) &&
          value(node['created_at']) == value(row['created_at'])) {
        node.addAll(changes);
      }
      for (final child in node.values) {
        if (child is Map || child is List) _patchRow(child, row, changes);
      }
    } else if (node is List) {
      for (final child in node) {
        if (child is Map || child is List) _patchRow(child, row, changes);
      }
    }
  }

  final Set<String> _appending = {};
  final Map<String, Object> _appendErrors = {};
  bool appending(String key) => _appending.contains(key);
  bool appendFailed(String key) => _appendErrors.containsKey(key);
  bool canAppend(String key) => object(data[key])['next_page_url'] is String;

  /// Fetch the paginator's next page and append its rows to the list on
  /// screen. A pull-to-refresh or navigation that starts meanwhile wins.
  Future<void> appendPage(String pageKey, {String? listKey}) async {
    final next = object(data[pageKey])['next_page_url'];
    if (!mounted || next is! String || _appending.contains(pageKey)) return;
    final request = _request,
        origin = path,
        expectedScreen = screen,
        session = c.sessionGeneration,
        viewer = c.user?['id'],
        language = c.settings.language;
    bool stale() =>
        !mounted ||
        request != _request ||
        origin != path ||
        session != c.sessionGeneration ||
        viewer != c.user?['id'] ||
        language != c.settings.language;
    setState(() {
      _appending.add(pageKey);
      _appendErrors.remove(pageKey);
      _contentWidget = null;
    });
    try {
      // Only the path and query are trusted; the origin is always the API's.
      final uri = Uri.parse(next);
      final response = await c.api.get(
        c.localized('${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'),
      );
      if (stale()) return;
      final incoming = object(response['data']);
      final incomingPage = object(incoming[pageKey]);
      if (value(response['screen']) != expectedScreen || incomingPage.isEmpty) {
        throw ApiFailure(c.t('Unable to load more.', 'تعذّر تحميل المزيد.'));
      }
      c.absorb(response);
      if (stale()) return;
      final currentPage = object(data[pageKey]);
      final updated = <String, dynamic>{...data};
      if (listKey == null) {
        updated[pageKey] = {
          ...incomingPage,
          'prev_page_url': currentPage['prev_page_url'],
          'data': mergeRows(rows(currentPage), rows(incomingPage)),
        };
      } else {
        updated[pageKey] = {
          ...incomingPage,
          'prev_page_url': currentPage['prev_page_url'],
        };
        updated[listKey] = mergeRows(
          rows({'data': data[listKey]}),
          rows({'data': incoming[listKey]}),
        );
      }
      data = updated;
      envelope = {...envelope, 'data': data};
      _appended[pageKey] = listKey;
      c.rememberPage(
        path,
        envelope,
        offset: scrollOffset.value,
        fetchedAt: _fetchedAt,
      );
      _rememberedData = data;
    } catch (e) {
      if (e is ApiFailure && (e.status == 401 || e.status == 419)) {
        if (!stale()) await c.expired();
        return;
      }
      if (!stale()) _appendErrors[pageKey] = e;
    } finally {
      if (mounted) {
        setState(() {
          _appending.remove(pageKey);
          _contentWidget = null;
        });
      }
    }
  }

  /// An infinite-scroll footer for a paginated list on this page.
  Widget more(String pageKey, {String? listKey, bool compact = false}) =>
      InfiniteScrollFooter(
        hasMore: canAppend(pageKey),
        loading: appending(pageKey),
        failed: appendFailed(pageKey),
        onLoadMore: () => appendPage(pageKey, listKey: listKey),
        translate: c.t,
        compact: compact,
      );

  Widget avatar(Json person, {double radius = 22}) {
    final preset = value(person['avatar']);
    final url = value(
      person['avatar_url'],
      preset.isEmpty ? '' : '/avatars/$preset',
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: url.isEmpty
          ? null
          : CachedNetworkImage(
              c.api.media(url),
              width: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              height: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
            ),
      child: url.isEmpty
          ? Text(value(person['name'], '?').characters.first.toUpperCase())
          : null,
    );
  }

  Widget personLine(
    Json person, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: avatar(person),
    title: Row(
      children: [
        Flexible(
          child: Text(
            value(person['name'], c.t('Member', 'عضو')),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        if (person['badge'] != null && '${person['badge']}' != '0') ...[
          const SizedBox(width: 4),
          UserBadge(api: c.api, badge: person['badge']),
        ],
      ],
    ),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: trailing,
    onTap:
        onTap ??
        (person['id'] != null ? () => c.open('/users/${person['id']}') : null),
  );
  Widget card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  String title() {
    if (path.startsWith('/community/posts')) {
      return c.t('Conversation', 'المحادثة');
    }
    if (path.startsWith('/users/')) return c.t('Profile', 'الملف الشخصي');
    return switch (screen) {
      'community.index' => c.t('Home', 'الرئيسية'),
      'people.index' => c.t('Find People', 'اكتشف الناس'),
      'schedule.index' => c.t('Schedule', 'الجدول'),
      'admin.schedule' => c.t('Manage schedule', 'إدارة الجدول'),
      'admin.schedule-appearance' => c.t(
        'Day off appearance',
        'شكل يوم الإجازة',
      ),
      'ask.inbox' => c.t('Inbox', 'الوارد'),
      'profile.show' => c.t('Your profile', 'ملفك الشخصي'),
      'profile.edit' => c.t('Edit profile', 'تعديل الملف'),
      'content.menu' => c.t('Settings and activity', 'الإعدادات والنشاط'),
      'community.post' => c.t('Post', 'منشور'),
      'community.forum' => value(
        object(data['community'])['name'],
        'Community',
      ),
      'community.question' => c.t('Question', 'السؤال'),
      'notifications.index' => c.t('Notifications', 'الإشعارات'),
      'notifications.settings' => c.t(
        'Notification settings',
        'إعدادات الإشعارات',
      ),
      'content.hall' => c.t('Hall of fame', 'لوحة الشرف'),
      'content.campus' => c.t('Campus map', 'خريطة الجامعة'),
      'content.suggestions' => c.t('Suggestions', 'الاقتراحات'),
      'quiz.index' => c.t('Quiz arena', 'ساحة الاختبارات'),
      'quiz.attempt' => value(object(data['attempt'])['category_name'], 'Quiz'),
      'quiz.result' => c.t('Quiz result', 'نتيجة الاختبار'),
      'quiz.history' => c.t('Your quiz history', 'سجل الاختبارات'),
      'admin.index' => c.t('Administration', 'الإدارة'),
      'login-activity.index' => c.t('Login activity', 'نشاط تسجيل الدخول'),
      'terms' => c.t('Terms & guidelines', 'الشروط والإرشادات'),
      'ai.index' => c.t('Tamer Elgayar', 'تامر الجيار'),
      _ => c.t('ElBench', 'البنش'),
    };
  }

  bool get profilePage => screen == 'profile.show' || screen == 'profile.user';
  bool get effectiveProfileChrome =>
      profilePage && (!loading || envelope.isNotEmpty);
  bool get hideBottomNav =>
      c.user == null ||
      screen == 'profile.edit' ||
      screen == 'terms' ||
      screen == 'community.question' ||
      screen == 'community.post' ||
      screen == 'quiz.attempt' ||
      screen.startsWith('ai.');
  Color chromeBackground(BuildContext context) => screen == 'content.hall'
      ? Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff292313)
            : const Color(0xfffbf5e7)
      : Theme.of(context).scaffoldBackgroundColor;
  Widget header(BuildContext chromeContext, {required bool active}) =>
      ValueListenableBuilder<double>(
        valueListenable: headerOffset,
        child: active
            ? ListenableBuilder(
                listenable: c,
                builder: (context, _) => _headerContents(context, active: true),
              )
            : _headerContents(chromeContext, active: false),
        builder: (context, offset, child) {
          final person = object(data['profile_user'] ?? data['user']);
          final hex = value(person['banner_color']).replaceFirst('#', '');
          final parsed = hex.length == 6
              ? int.tryParse('ff$hex', radix: 16)
              : null;
          final darkBanner =
              value(person['banner_url']).isNotEmpty ||
              parsed != null && Color(parsed).computeLuminance() < .4;
          final lightIcons =
              Theme.of(context).brightness == Brightness.dark ||
              profilePage && offset < 108 && darkBanner;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (lightIcons
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark)
                    .copyWith(statusBarColor: Colors.transparent),
            child: ColoredBox(
              color: effectiveProfileChrome
                  ? Theme.of(context).scaffoldBackgroundColor.withValues(
                      alpha: ((offset - 48) / 72).clamp(0.0, 1.0),
                    )
                  : chromeBackground(context),
              child: child!,
            ),
          );
        },
      );
  Widget _headerContents(BuildContext context, {required bool active}) {
    final scheme = Theme.of(context).colorScheme;
    final menuPage = screen == 'content.menu';
    Widget circle(
      String icon,
      String tooltip,
      ValueChanged<BuildContext> onTap, {
      Widget? glyph,
    }) => Builder(
      builder: (buttonContext) => Tooltip(
        message: tooltip,
        child: InkWell(
          key: ValueKey('header.$icon'),
          onTap: () => onTap(buttonContext),
          borderRadius: BorderRadius.circular(50),
          child: SizedBox(
            width: 44,
            height: 44,
            child: NativeGlassSurface(
              enabled: active,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effectiveProfileChrome
                    ? Theme.of(
                        context,
                      ).scaffoldBackgroundColor.withValues(alpha: .78)
                    : scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(child: glyph ?? WebIcon(icon, size: 20)),
            ),
          ),
        ),
      ),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: ValueListenableBuilder<double>(
            valueListenable: headerOffset,
            builder: (context, offset, child) => DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: screen == 'content.hall'
                        ? Colors.transparent
                        : effectiveProfileChrome
                        ? scheme.outlineVariant.withValues(
                            alpha: ((offset - 48) / 72).clamp(0.0, 1.0),
                          )
                        : scheme.outlineVariant,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: child,
              ),
            ),
            child: Row(
              children: [
                circle('back', c.t('Back', 'رجوع'), (_) {
                  c.navigator.currentState?.maybePop();
                }),
                Expanded(
                  child: profilePage
                      ? ValueListenableBuilder<bool>(
                          valueListenable: headerCollapsed,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value(
                                    object(
                                      data['profile_user'] ?? data['user'],
                                    )['name'],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  value(
                                    object(
                                      data['profile_user'] ?? data['user'],
                                    )['university_id'],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          builder: (context, collapsed, child) =>
                              AnimatedOpacity(
                                opacity: collapsed ? 1 : 0,
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 250),
                                child: AnimatedSlide(
                                  offset: collapsed
                                      ? Offset.zero
                                      : const Offset(0, .2),
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 250),
                                  child: child!,
                                ),
                              ),
                        )
                      : screen == 'community.index'
                      ? Center(
                          child: ElBenchHeaderLogo(
                            pullProgress: homePullProgress,
                            refreshing: homeRefreshing,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (screen.startsWith('ai.')) ...[
                              const WebIcon('ai', size: 20),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                profilePage
                                    ? ''
                                    : (c.settings.language == 'en' &&
                                              !screen.startsWith('ai.')
                                          ? title().toUpperCase()
                                          : title()),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  height: 28 / 18,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                Visibility(
                  visible: !menuPage,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: circle(
                    'menu',
                    profilePage || screen == 'community.post'
                        ? c.t('Options', 'الخيارات')
                        : c.t('Menu', 'القائمة'),
                    (buttonContext) {
                      if (profilePage) {
                        showWebProfileOptions(
                          context,
                          this,
                          anchorContext: buttonContext,
                        );
                      } else if (screen == 'community.post') {
                        showWebPostOptions(
                          context,
                          this,
                          object(data['post']),
                          anchorContext: buttonContext,
                        );
                      } else {
                        c.open('/menu');
                      }
                    },
                    glyph: profilePage || screen == 'community.post'
                        ? const Text('•••', style: TextStyle(fontSize: 18))
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = error != null
        ? ErrorPanel(error: error!, retry: load, retrying: loading)
        : loading && envelope.isEmpty
        ? const PageSkeleton()
        : content();
    final modal = ModalRoute.of(context);
    final route = modal is WebPageRoute ? modal : null;
    return Scaffold(
      // A fraction slide reveals the retained previous body, not a screenshot
      // or an empty window. The incoming body paints its own solid background.
      backgroundColor: route?.hasPreviousBody == true
          ? Colors.transparent
          : Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      extendBodyBehindAppBar: profilePage,
      // The shared chrome is above Navigator. Non-profile routes paint their
      // own top bar surface and border so transitioning into or out of Profile
      // never leaves an uncolored gap above the outgoing body.
      appBar: error != null || screen == 'terms'
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: profilePage
                      ? Colors.transparent
                      : chromeBackground(context),
                  border: Border(
                    bottom: BorderSide(
                      color: profilePage || screen == 'content.hall'
                          ? Colors.transparent
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SizedBox(height: MediaQuery.paddingOf(context).top + 64),
              ),
            ),
      bottomNavigationBar: error != null || hideBottomNav
          ? null
          : SizedBox(height: 76 + MediaQuery.paddingOf(context).bottom),
      body: WebPageEntrance(
        motion: route?.motion ?? const WebVisitMotion(),
        ready:
            error != null || !loading || envelope.isNotEmpty || _revealLoading,
        child: WebPageDeparture(
          visit: _incomingVisit,
          child: RepaintBoundary(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: TickerMode(
                enabled:
                    (_observedRoute?.isCurrent ?? true) ||
                    _incomingVisit != null,
                child: PrimaryScrollController(
                  controller: _pageScroll,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.metrics.axis == Axis.vertical) {
                        _observedPosition = notification.context == null
                            ? null
                            : Scrollable.maybeOf(
                                notification.context!,
                              )?.position;
                        reportScrollOffset(notification.metrics.pixels);
                        _reportDockScroll(notification);
                        if (notification is ScrollEndNotification) {
                          c.rememberScroll(path, notification.metrics.pixels);
                        }
                      }
                      return false;
                    },
                    child: error != null
                        ? SafeArea(child: body)
                        : screen == 'terms'
                        ? SafeArea(bottom: false, child: body)
                        : body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget content() => _contentWidget ??= _buildContent();

  Widget _buildContent() {
    if (screen == 'community.index') return WebHome(page: this);
    if (screen == 'schedule.index') return WebSchedule(page: this);
    if (screen == 'admin.schedule') return ScheduleAdminContent(page: this);
    if (screen == 'admin.schedule-appearance') {
      return ScheduleAppearanceAdminContent(page: this);
    }
    if (screen.startsWith('ai.')) return WebAiChat(page: this);
    if (screen == 'community.forum') return WebForum(page: this);
    if (screen == 'community.question') return WebCommunityQuestion(page: this);
    if (screen == 'community.ask') return WebCommunityAsk(page: this);
    if (screen == 'community.moderate') return WebModerate(page: this);
    if (screen == 'ask.inbox') return WebInbox(page: this);
    if (screen == 'ask.show') return WebAskDetail(page: this);
    if (screen == 'notifications.index') return WebNotifications(page: this);
    if (screen == 'notifications.announcement') {
      return WebAnnouncement(page: this);
    }
    if (profilePage) return WebProfile(page: this);
    if (screen == 'people.index') return WebPeople(page: this);
    if (screen == 'profile.edit') return WebProfileEdit(page: this);
    if (screen == 'content.hall') return WebHall(page: this);
    if (screen == 'terms') return WebTerms(page: this);
    if (screen == 'profile.password-reset') return WebPasswordReset(page: this);
    if (screen == 'content.campus') return WebCampus(page: this);
    if (screen == 'community.post') return WebPostDetail(page: this);
    if (screen == 'notifications.settings') {
      return WebNotificationSettings(page: this);
    }
    if (screen == 'content.suggestions') return WebSuggestions(page: this);
    if (screen == 'login-activity.index') return WebLoginActivity(page: this);
    if (screen.startsWith('quiz.')) return QuizContent(page: this);
    if (screen == 'admin.index') return AdminContent(page: this);
    if (screen == 'content.campus') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              c.t(
                'Pinch to zoom. Drag to explore your campus.',
                'كبّر بإصبعين واسحب لاستكشاف الجامعة.',
              ),
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: .3,
              maxScale: 8,
              constrained: false,
              child: SvgPicture.asset(
                'assets/campus.svg',
                width: 1100,
                semanticsLabel: 'Campus map',
              ),
            ),
          ),
        ],
      );
    }
    final children = switch (screen) {
      'community.index' => home(),
      'community.forum' => forum(),
      'community.ask' => askCommunity(),
      'community.moderate' => moderate(),
      'community.question' => question(),
      'community.post' => postDetail(),
      'admin.report-post' => reportInspect(),
      'people.index' => people(),
      'profile.show' || 'profile.user' => profile(),
      'profile.edit' => editProfile(),
      'ask.inbox' => inbox(),
      'ask.show' => askDetail(),
      'content.menu' => menu(),
      'notifications.index' => notifications(),
      'notifications.announcement' => announcement(),
      'notifications.settings' => notificationSettings(),
      'content.suggestions' => suggestions(),
      'content.hall' => hall(),
      'login-activity.index' => activity(),
      'profile.password-reset' => resetPassword(),
      'ai.index' || 'ai.chat' => [
        empty(
          c.t(
            'AI chat is coming soon. Stay tuned.',
            'المساعد الذكي قريبًا. تابعنا.',
          ),
        ),
      ],
      'terms' => terms(),
      _ => [
        empty(
          c.t(
            'This screen is unavailable. Please try again later.',
            'هذه الشاشة غير متاحة. حاول لاحقًا.',
          ),
        ),
      ],
    };
    return RefreshIndicator.adaptive(
      onRefresh: pullRefresh,
      child: ListView(
        padding: screen == 'content.menu'
            ? const EdgeInsets.only(top: 6, bottom: 112)
            : EdgeInsets.fromLTRB(10, 22, 10, hideBottomNav ? 28 : 112),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (value(envelope['status']).isNotEmpty)
            card(Text(value(envelope['status']))),
          ...children,
        ],
      ),
    );
  }

  List<Widget> home() => [
    Text(
      c.t(
        'Hey, ${c.user?['first_name'] ?? ''} 👋',
        'أهلاً، ${c.user?['first_name'] ?? ''} 👋',
      ),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 6),
    Text(c.t('Make yourself at home.', 'اعتبر نفسك في بيتك.')),
    const SizedBox(height: 20),
    if (c.enabled('community')) ...[
      heading(c.t('Your communities', 'مجتمعاتك')),
      if (rows(data['communities']).isNotEmpty)
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rows(data['communities']).length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final item = rows(data['communities'])[i];
              return SizedBox(
                width: 170,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => c.open('/forum?community_id=${item['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.groups_2_outlined, size: 30),
                          const Spacer(),
                          Text(
                            value(item['name']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${item['question_count'] ?? 0} ${c.t('questions', 'سؤال')}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
    for (final event in rows(data['featured_events']))
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_outlined),
            const SizedBox(height: 8),
            Text(
              value(event['title']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(value(event['arenas'])),
            Text(value(event['event_date'])),
            if (value(event['details']).isNotEmpty)
              Text(value(event['details'])),
            if (value(event['link_url']).isNotEmpty)
              TextButton(
                onPressed: () => external(value(event['link_url'])),
                child: Text(c.t('View event', 'عرض الفعالية')),
              ),
          ],
        ),
      ),
    heading(
      c.t('On the bench', 'على البنش'),
      trailing: IconButton(
        onPressed: () =>
            form(c.t('Share something', 'شارك شيئًا'), '/community/posts', [
              FieldSpec(
                'content',
                c.t('What’s on your mind?', 'بماذا تفكر؟'),
                lines: 5,
              ),
              FieldSpec(
                'visibility',
                c.t('Who can see this?', 'من يمكنه رؤية هذا؟'),
                initial: 'public',
                options: {
                  'public': c.t('Everyone', 'الجميع'),
                  'private': c.t('Only me', 'أنا فقط'),
                },
              ),
            ]),
        icon: const Icon(Icons.edit_square),
      ),
    ),
    for (final post in rows(data['posts'])) postCard(post),
    if (rows(data['posts']).isEmpty)
      empty(
        c.t(
          'Start a conversation with your community.',
          'ابدأ محادثة مع مجتمعك.',
        ),
      ),
    pagination(data['posts']),
  ];
  Future<void> external(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && ['https', 'http'].contains(uri.scheme)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget postCard(Json post, {bool detail = false}) =>
      WebPostCard(page: this, post: post, detail: detail);
  Widget reactionRow(String endpoint, Json item) => Wrap(
    spacing: 8,
    children: [
      for (final (type, emoji) in [
        ('like', '👍'),
        ('love', '❤️'),
        ('funny', '😂'),
      ])
        ActionChip(
          label: Text(
            '$emoji ${value(item['${type}_count'] ?? object(item['reaction_counts'])[type], '0')}',
          ),
          onPressed: () => run('POST', endpoint, {'reaction': type}),
        ),
    ],
  );
  Future<void> report(String endpoint) async {
    await form(c.t('Report content', 'إبلاغ عن المحتوى'), endpoint, [
      FieldSpec(
        'reason',
        c.t('Tell us what happened', 'أخبرنا بما حدث'),
        lines: 4,
        required: false,
      ),
    ]);
  }

  String date(dynamic input) {
    final parsed = DateTime.tryParse(value(input));
    if (parsed == null) return value(input);
    final d = parsed.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  List<Widget> postDetail() => [
    postCard(object(data['post']), detail: true),
    if (data['threadRoot'] != null)
      commentCard(object(data['threadRoot']), object(data['post'])['id']),
    heading(c.t('Comments', 'التعليقات')),
    FilledButton.tonalIcon(
      onPressed: () => commentForm(),
      icon: const Icon(Icons.add_comment_outlined),
      label: Text(c.t('Add a comment', 'أضف تعليقًا')),
    ),
    const SizedBox(height: 16),
    for (final comment in rows(data['comments']))
      commentCard(comment, object(data['post'])['id']),
    if (rows(data['comments']).isEmpty) empty(),
    pagination(data['comments']),
  ];
  Future<void> commentForm() async {
    final stickers = {
      for (final s in rows(data['stickers'])) '${s['id']}': '${s['id']}',
    };
    if (stickers.isNotEmpty && mounted) {
      await showModalBottomSheet<void>(
        useRootNavigator: true,
        context: context,
        showDragHandle: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  form(
                    c.t('Add a comment', 'أضف تعليقًا'),
                    '/community/posts/${object(data['post'])['id']}/comments',
                    [
                      FieldSpec(
                        'comment_content',
                        c.t('Comment', 'التعليق'),
                        lines: 4,
                      ),
                    ],
                    fixed: {'comment_context': 'detail'},
                  );
                },
                icon: const Icon(Icons.edit_outlined),
                label: Text(c.t('Write a comment', 'اكتب تعليقًا')),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: GridView.count(
                  crossAxisCount: 4,
                  children: [
                    for (final s in rows(data['stickers']))
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          run(
                            'POST',
                            '/community/posts/${object(data['post'])['id']}/comments',
                            {
                              'sticker_id': s['id'],
                              'comment_context': 'detail',
                            },
                          );
                        },
                        child: networkImage(
                          cacheWidth: 200,
                          c.api.media(value(s['url'])),
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.emoji_emotions_outlined),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      await form(
        c.t('Add a comment', 'أضف تعليقًا'),
        '/community/posts/${object(data['post'])['id']}/comments',
        [FieldSpec('comment_content', c.t('Comment', 'التعليق'), lines: 4)],
        fixed: {'comment_context': 'detail'},
      );
    }
  }

  Widget commentCard(Json item, dynamic postId, {bool answer = false}) {
    final own = '${item['user_id']}' == '${c.user?['id']}';
    final endpoint = answer
        ? '/question/answers/${item['id']}'
        : '/community/posts/$postId/comments/${item['id']}';
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          personLine(
            object(item['author']),
            subtitle: date(item['created_at']),
            trailing: AppPopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await form(c.t('Edit comment', 'تعديل التعليق'), endpoint, [
                    FieldSpec(
                      'comment_content',
                      c.t('Comment', 'التعليق'),
                      initial: item['content'],
                      lines: 4,
                    ),
                  ], method: 'PUT');
                }
                if (v == 'delete') {
                  await form(
                    c.t('Delete comment?', 'حذف التعليق؟'),
                    endpoint,
                    [],
                    method: 'DELETE',
                    destructive: true,
                  );
                }
                if (v == 'report') await report('$endpoint/reports');
              },
              itemBuilder: (_) => [
                if (own)
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(c.t('Edit', 'تعديل')),
                  ),
                if (own || c.permission('communities.manage'))
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(c.t('Delete', 'حذف')),
                  ),
                if (!own && !answer)
                  PopupMenuItem(
                    value: 'report',
                    child: Text(c.t('Report', 'إبلاغ')),
                  ),
              ],
            ),
          ),
          Text(value(item['content'])),
          if (item['sticker_id'] != null)
            networkImage(
              c.api.media('/comment-stickers/${item['sticker_id']}.webp'),
              height: 130,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const SizedBox(height: 10),
          reactionRow(
            answer ? '/answers/${item['id']}/reactions' : '$endpoint/reactions',
            item,
          ),
          if (!answer &&
              (int.tryParse(value(item['thread_replies_count'])) ?? 0) > 0)
            TextButton(
              onPressed: () =>
                  c.open('/community/posts/$postId?thread=${item['id']}'),
              child: Text(c.t('View replies', 'عرض الردود')),
            ),
          for (final reply in rows(item['thread_replies']))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 20, top: 12),
              child: Text(
                '${object(reply['author'])['name'] ?? ''}: ${reply['content'] ?? ''}',
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> forum() {
    final id = data['community_id'] ?? object(data['community'])['id'];
    final selected = Uri.parse(
      path,
    ).queryParameters.containsKey('my_questions');
    return [
      if (value(object(data['community'])['description']).isNotEmpty)
        card(Text(value(object(data['community'])['description']))),
      search('search', c.t('Search this community', 'ابحث في المجتمع')),
      Wrap(
        spacing: 10,
        children: [
          FilterChip(
            label: Text(c.t('My questions', 'أسئلتي')),
            selected: selected,
            onSelected: (v) => query({'my_questions': v ? 1 : null}),
          ),
          ActionChip(
            label: Text(c.t('Ask a question', 'اسأل سؤالًا')),
            avatar: const Icon(Icons.add),
            onPressed: () => c.open('/ask-question?community_id=$id'),
          ),
          if (yes(data['can_moderate']))
            ActionChip(
              label: Text(
                '${c.t('Moderate', 'الإشراف')} (${data['pending_count'] ?? 0})',
              ),
              onPressed: () => c.open('/moderate?community_id=$id'),
            ),
        ],
      ),
      const SizedBox(height: 18),
      for (final item in rows(data['questions'])) questionCard(item),
      if (rows(data['questions']).isEmpty) empty(),
      pagination(data['pagination']),
    ];
  }

  Widget questionCard(Json item) => card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        personLine({
          'id': item['user_id'],
          'name': item['name'],
          'avatar_url': item['avatar_url'],
        }, subtitle: date(item['created_at'])),
        InkWell(
          onTap: () => c.open('/question?id=${item['id']}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              value(item['content']),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => c.open('/question?id=${item['id']}'),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(
            '${item['answer_count'] ?? 0} ${c.t('answers', 'إجابة')}',
          ),
        ),
      ],
    ),
  );
  List<Widget> askCommunity() => [
    Text(
      c.t('Ask your community', 'اسأل مجتمعك'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    if (yes(data['questionRequiresApproval']))
      Text(
        c.t(
          'A moderator will review your question before it appears.',
          'سيراجع المشرف سؤالك قبل ظهوره.',
        ),
      ),
    const SizedBox(height: 20),
    FilledButton.icon(
      onPressed: () => form(
        c.t('Ask your community', 'اسأل مجتمعك'),
        '/ask-question',
        [FieldSpec('content', c.t('Your question', 'سؤالك'), lines: 6)],
        fixed: {'community_id': data['community_id']},
        follow: true,
      ),
      icon: const Icon(Icons.edit_outlined),
      label: Text(c.t('Write a question', 'اكتب سؤالًا')),
    ),
  ];
  List<Widget> moderate() => [
    for (final item in rows(data['pending_questions']))
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value(item['name']),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(value(item['content'])),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: () => run('POST', '/moderate', {
                    'community_id':
                        data['community_id'] ?? object(data['community'])['id'],
                    'question_id': item['id'],
                    'action': 'approve',
                  }),
                  child: Text(c.t('Approve', 'قبول')),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => run('POST', '/moderate', {
                    'community_id':
                        data['community_id'] ?? object(data['community'])['id'],
                    'question_id': item['id'],
                    'action': 'delete',
                  }),
                  child: Text(c.t('Reject', 'رفض')),
                ),
              ],
            ),
          ],
        ),
      ),
    if (rows(data['pending_questions']).isEmpty)
      empty(
        c.t(
          'All caught up. No questions need review.',
          'انتهيت! لا توجد أسئلة تحتاج مراجعة.',
        ),
      ),
    pagination(data['pagination']),
  ];
  List<Widget> question() => [
    questionCard(object(data['question'])),
    heading(c.t('Answers', 'الإجابات')),
    FilledButton.tonalIcon(
      onPressed: () => form(
        c.t('Add an answer', 'أضف إجابة'),
        '/question/answer',
        [FieldSpec('answer_content', c.t('Your answer', 'إجابتك'), lines: 5)],
        fixed: {'id': data['question_id'] ?? object(data['question'])['id']},
      ),
      icon: const Icon(Icons.edit_outlined),
      label: Text(c.t('Share an answer', 'شارك بإجابة')),
    ),
    const SizedBox(height: 18),
    for (final item in rows(data['answers']))
      commentCard(item, null, answer: true),
    if (rows(data['answers']).isEmpty) empty(),
    pagination(data['pagination']),
  ];
  List<Widget> people() => [
    search(
      'q',
      c.t('Name, university ID, or skill', 'الاسم أو الرقم الجامعي أو المهارة'),
    ),
    Text(
      c.t(
        'Find a familiar face. Or meet someone new.',
        'اعثر على وجه مألوف أو تعرّف على شخص جديد.',
      ),
    ),
    const SizedBox(height: 20),
    for (final person in rows(data['people']))
      card(
        personLine(
          person,
          subtitle: [
            value(person['major']),
            rows(
              person['skills'],
            ).map((s) => value(s['skill_name'])).join(' · '),
          ].where((s) => s.isNotEmpty).join('\n'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    if (rows(data['people']).isEmpty)
      empty(c.t('No people match your search.', 'لا توجد نتائج تطابق بحثك.')),
    pagination(data['people']),
  ];
  List<Widget> profile() {
    final person = object(data['profile_user'] ?? data['user']);
    final own = '${person['id']}' == '${c.user?['id']}';
    final tab = value(data['activityTab'], 'posts');
    final compact = MediaQuery.sizeOf(context).width <= 375;
    final avatarSize = compact ? 94.0 : 116.0;
    final scheme = Theme.of(context).colorScheme;
    final currentItems =
        data[tab == 'posts'
            ? 'profile_posts'
            : tab == 'comments'
            ? 'profile_comments'
            : 'profile_asks'];
    final banner = value(person['banner_url']);
    Widget stat(String number, String label) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            number,
            style: TextStyle(
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              height: 1.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return [
      Container(
        height: 184,
        decoration: BoxDecoration(
          color: hex(value(person['banner_color'])) ?? c.settings.accent,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          image: banner.isEmpty
              ? null
              : DecorationImage(
                  image: CachedNetworkImage(
                    c.api.media(banner),
                    width:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .ceil(),
                  ),
                  fit: BoxFit.cover,
                ),
        ),
      ),
      Transform.translate(
        offset: const Offset(0, -22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 112),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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
                          color: Theme.of(context).scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .12),
                              blurRadius: 26,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: avatar(person, radius: avatarSize / 2 - 4),
                      ),
                    ),
                    PositionedDirectional(
                      start: avatarSize + 8,
                      end: 0,
                      bottom: 9,
                      child: Row(
                        children: [
                          stat(
                            value(data['posts_count'], '0'),
                            c.t('Posts', 'المنشورات'),
                          ),
                          stat(
                            value(data['comments_count'], '0'),
                            c.t('Comments', 'التعليقات'),
                          ),
                          stat(
                            value(data['reactions_count'], '0'),
                            c.t('Reactions', 'التفاعلات'),
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
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                  ),
                  if ('${person['badge']}' != '0') ...[
                    const SizedBox(width: 6),
                    UserBadge(api: c.api, badge: person['badge'], large: true),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '@${person['university_id'] ?? ''}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WebIcon('chart', size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${data['user_points'] ?? 0}',
                        style: TextStyle(
                          color: scheme.primary,
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
                [
                  value(person['job']),
                  value(person['major']),
                ].where((s) => s.isNotEmpty).join(' ▪ '),
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
                  for (final (key, icon) in [
                    ('city', 'map'),
                    ('graduation_year', 'graduation'),
                    ('birthdate', 'clock'),
                  ])
                    if (value(person[key]).isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebIcon(icon, size: 16, color: scheme.primary),
                          const SizedBox(width: 7),
                          Text(
                            value(person[key]),
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: own
                    ? () => c.open('/profile/edit')
                    : () => form(
                        c.t('Ask ${person['name']}', 'اسأل ${person['name']}'),
                        '/users/${person['id']}/ask',
                        [
                          FieldSpec(
                            'question',
                            c.t('Your question', 'سؤالك'),
                            lines: 4,
                          ),
                        ],
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xff0a0a0a)
                      : Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  own
                      ? c.t('Edit Profile', 'تعديل الملف الشخصي')
                      : c.t('Ask', 'اسأل'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (rows(data['skills']).isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final skill in rows(data['skills']))
                      Chip(label: Text(value(skill['skill_name']))),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final (key, title) in [
                          ('posts', c.t('Posts', 'المنشورات')),
                          ('comments', c.t('Comments', 'التعليقات')),
                          ('ask', c.t('Ask', 'الأسئلة')),
                        ])
                          Expanded(
                            child: InkWell(
                              onTap: () => query({'tab': key}),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 8,
                                ),
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: tab == key
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: AnimatedAlign(
                        alignment: AlignmentDirectional(switch (tab) {
                          'comments' => 0.0,
                          'ask' => 1.0,
                          _ => -1.0,
                        }, 1.0),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                        child: FractionallySizedBox(
                          widthFactor: 1 / 3,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (tab == 'posts') ...[
                for (final item in rows(currentItems)) postCard(item),
              ] else if (tab == 'comments') ...[
                for (final item in rows(currentItems))
                  card(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(value(item['content'])),
                      subtitle: Text(
                        value(object(item['post'])['content']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => c.open(
                        '/community/posts/${item['feed_post_id']}?focus_comment=${item['id']}',
                      ),
                    ),
                  ),
              ] else ...[
                for (final item in rows(currentItems)) askCard(item),
              ],
              if (rows(currentItems).isEmpty) empty(),
              pagination(currentItems),
            ],
          ),
        ),
      ),
    ];
  }

  String label(String key) => switch (key) {
    'city' => c.t('City', 'المدينة'),
    'birthdate' => c.t('Birth date', 'تاريخ الميلاد'),
    'graduation_year' => c.t('Graduation year', 'سنة التخرج'),
    _ => key.replaceAll('_', ' '),
  };
  Map<String, String> options(dynamic source) => source is List
      ? {for (final v in source) '$v': '$v'}
      : object(source).map((k, v) => MapEntry(k, '$v'));
  List<Widget> editProfile() {
    final person = object(data['user']);
    return [
      card(
        personLine(
          person,
          subtitle: c.t('Make your profile yours.', 'اجعل ملفك يعبر عنك.'),
        ),
      ),
      FilledButton.icon(
        onPressed: () => form(
          c.t('Edit profile', 'تعديل الملف الشخصي'),
          '/profile',
          [
            FieldSpec(
              'major',
              c.t('Major', 'التخصص'),
              initial: person['major'],
              required: false,
              options: options(data['allowed_majors']),
            ),
            FieldSpec(
              'job',
              c.t('Occupation', 'الوظيفة'),
              initial: person['job'],
              required: false,
              options: options(data['job_options']),
            ),
            FieldSpec(
              'city',
              c.t('City', 'المدينة'),
              initial: person['city'],
              required: false,
              options: options(data['egyptian_cities']),
            ),
            FieldSpec(
              'birthdate',
              c.t('Birth date (YYYY-MM-DD)', 'تاريخ الميلاد (YYYY-MM-DD)'),
              initial: person['birthdate'],
              required: false,
            ),
            FieldSpec(
              'graduation_year',
              c.t('Graduation year', 'سنة التخرج'),
              initial: person['graduation_year'],
              required: false,
              number: true,
            ),
          ],
          method: 'PUT',
          follow: true,
        ),
        icon: const Icon(Icons.person_outline),
        label: Text(c.t('Profile details', 'تفاصيل الملف')),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: () => form(
          c.t('Profile pictures', 'صور الملف'),
          '/profile',
          [
            FieldSpec(
              'avatar',
              c.t('Avatar preset', 'الصورة الرمزية'),
              initial: person['avatar'],
              required: false,
              options: options(data['available_avatars']),
            ),
            FieldSpec(
              'banner_image',
              c.t('Banner preset', 'صورة الغلاف'),
              initial: person['banner_image'],
              required: false,
              options: {
                '': c.t('Solid color', 'لون ثابت'),
                ...options(data['allowed_banner_images']),
              },
            ),
            FieldSpec(
              'banner_color',
              c.t('Banner color (#RRGGBB)', 'لون الغلاف (#RRGGBB)'),
              initial: person['banner_color'] ?? '#82a98a',
              required: false,
            ),
            if (yes(c.user?['can_upload_media'])) ...[
              FieldSpec(
                'avatar_upload',
                c.t('Upload avatar', 'رفع صورة شخصية'),
                file: true,
                required: false,
              ),
              FieldSpec(
                'banner_upload',
                c.t('Upload banner', 'رفع غلاف'),
                file: true,
                required: false,
              ),
            ],
          ],
          method: 'PUT',
          follow: true,
        ),
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(c.t('Avatar & banner', 'الصورة والغلاف')),
      ),
      heading(
        c.t('Your skills', 'مهاراتك'),
        trailing: IconButton(
          onPressed: () => form(
            c.t('Add skill', 'أضف مهارة'),
            '/profile/skills',
            [FieldSpec('skill_name', c.t('Skill', 'المهارة'))],
          ),
          icon: const Icon(Icons.add),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final skill in rows(data['skills']))
            InputChip(
              label: Text(value(skill['skill_name'])),
              onDeleted: () => run('DELETE', '/profile/skills/${skill['id']}'),
            ),
        ],
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: passwordForm,
        icon: const Icon(Icons.lock_outline),
        label: Text(c.t('Change password', 'تغيير كلمة المرور')),
      ),
      TextButton(
        onPressed: () => c.open('/profile/password/reset'),
        child: Text(
          c.t('Reset password by email', 'إعادة تعيين كلمة المرور بالبريد'),
        ),
      ),
    ];
  }

  Future<void> passwordForm() => showWebSecurity(context, this);

  List<Widget> inbox() => [
    chips(
      [('inbox', c.t('Received', 'المستلم')), ('sent', c.t('Sent', 'المرسل'))],
      'tab',
      value(data['tab'], 'inbox'),
    ),
    for (final item in rows(data['questions'])) askCard(item),
    if (rows(data['questions']).isEmpty)
      empty(
        c.t(
          'Questions from your people will appear here.',
          'ستظهر أسئلة أصدقائك هنا.',
        ),
      ),
    pagination(data['questions']),
  ];
  Widget askCard(Json item) => card(
    InkWell(
      onTap: () => c.open('/ask/${item['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          personLine(
            object(item['sender']),
            subtitle: date(item['created_at']),
          ),
          Text(
            value(item['question']),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (value(item['answer']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(value(item['answer'])),
            ),
          const SizedBox(height: 12),
          Text(
            item['answered_at'] == null
                ? c.t('Waiting for an answer', 'في انتظار الإجابة')
                : c.t('Answered', 'تمت الإجابة'),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    ),
  );
  List<Widget> askDetail() {
    final item = object(data['question']);
    final recipient = yes(data['isRecipient']);
    return [
      askCard(item),
      if (recipient && item['answered_at'] == null)
        FilledButton.icon(
          onPressed: () => form(
            c.t('Answer question', 'أجب عن السؤال'),
            '/ask/${item['id']}/answer',
            [
              FieldSpec('answer', c.t('Your answer', 'إجابتك'), lines: 6),
              FieldSpec(
                'publish',
                c.t('Publish on your profile?', 'نشر على ملفك؟'),
                initial: '0',
                options: {
                  '0': c.t('Keep private', 'إبقاء خاص'),
                  '1': c.t('Publish publicly', 'نشر للجميع'),
                },
              ),
            ],
          ),
          icon: const Icon(Icons.reply),
          label: Text(c.t('Write your answer', 'اكتب إجابتك')),
        ),
      if (recipient && item['answered_at'] != null) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.t('Show on my profile', 'إظهار على ملفي')),
          value: item['published_at'] != null,
          onChanged: (on) => run('PATCH', '/ask/${item['id']}/publication', {
            'published': on,
            'is_private': false,
          }),
        ),
        if (item['published_at'] != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.t('Only visible to me', 'مرئي لي فقط')),
            value: yes(item['is_private']),
            onChanged: (on) => run('PATCH', '/ask/${item['id']}/visibility', {
              'is_private': on,
            }),
          ),
        if (item['published_at'] != null)
          OutlinedButton(
            onPressed: () => run('DELETE', '/ask/${item['id']}/publication'),
            child: Text(c.t('Remove from profile', 'إزالة من الملف')),
          ),
      ],
      if (recipient)
        TextButton.icon(
          onPressed: () => report('/ask/${item['id']}/reports'),
          icon: const Icon(Icons.flag_outlined),
          label: Text(c.t('Report question', 'إبلاغ عن السؤال')),
        ),
    ];
  }

  Widget menuRow(
    String icon,
    String label,
    VoidCallback action, {
    String? detail,
    bool danger = false,
  }) {
    final color = danger
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: action,
      child: Container(
        constraints: BoxConstraints(minHeight: danger ? 76 : 64),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Center(child: WebIcon(icon, size: 26, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  height: 25 / 17,
                  fontWeight: FontWeight.w400,
                  color: color,
                ),
              ),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Text(
                  detail,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!danger)
              WebIcon(
                c.settings.language == 'ar' ? 'back' : 'chevron-right',
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: .65),
              ),
          ],
        ),
      ),
    );
  }

  Widget menuGroup(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
  List<Widget> menu() => [
    menuRow('calendar', c.t('Schedule', 'الجدول'), () => c.open('/schedule')),
    menuRow(
      'compass',
      c.t('Find People', 'اكتشف الناس'),
      () => c.open('/people'),
    ),
    if (c.enabled('quiz'))
      menuRow('graduation', c.t('Quiz', 'الاختبارات'), () => c.open('/quiz')),
    if (c.enabled('campus'))
      menuRow(
        'map',
        c.t('Campus map', 'خريطة الجامعة'),
        () => c.open('/campus'),
      ),
    if (c.enabled('hall'))
      menuRow(
        'trophy',
        c.t('Hall of Fame', 'لوحة الشرف'),
        () => c.open('/hall-of-fame'),
      ),
    if (c.enabled('ai'))
      menuRow('ai', c.t('AI Chat', 'المساعد الذكي'), () => c.open('/ai-chat')),
    menuGroup(c.t('Settings & Account', 'الإعدادات والحساب')),
    menuRow('inbox', c.t('Inbox', 'الوارد'), () => c.open('/inbox')),
    menuRow(
      'user',
      c.t('Your Profile', 'الملف الشخصي'),
      () => c.open('/profile'),
    ),
    menuRow('lock', c.t('Security', 'الأمان'), passwordForm),
    menuRow(
      'monitor',
      c.t('Login activity', 'نشاط تسجيل الدخول'),
      () => c.open('/menu/login-activity'),
    ),
    menuGroup(c.t('Preferences', 'التفضيلات')),
    menuRow(
      'bell',
      c.t('Notifications', 'الإشعارات'),
      () => c.open('/menu/notifications'),
    ),
    menuRow(
      'moon',
      c.t('Switch Theme', 'تغيير المظهر'),
      () => c.settings.setMode(
        Theme.of(context).brightness == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark,
      ),
      detail: Theme.of(context).brightness == Brightness.dark
          ? c.t('Dark', 'داكن')
          : c.t('Light', 'فاتح'),
    ),
    menuRow(
      'monitor',
      c.t('Use device theme', 'استخدام مظهر الجهاز'),
      () => c.settings.setMode(ThemeMode.system),
    ),
    menuRow('globe', c.t('العربية', 'English'), () async {
      final language = c.settings.language == 'en' ? 'ar' : 'en';
      c.settings.setLanguage(language);
      try {
        await c.action('POST', '/language', {'locale': language});
        if (c.enablePush) await c.push.bind(c.user, language);
      } catch (_) {}
      await load();
    }, detail: c.settings.language.toUpperCase()),
    if (c.enabled('suggestions') ||
        ['admin', 'super_admin'].contains(c.user?['role']))
      menuGroup(c.t('Support & tools', 'الدعم والأدوات')),
    if (c.enabled('suggestions'))
      menuRow(
        'message',
        c.t('Submit Feedback', 'إرسال اقتراح'),
        () => c.open('/suggestions'),
      ),
    if (['admin', 'super_admin'].contains(c.user?['role']))
      menuRow(
        'settings',
        c.t('Super Admin', 'الإدارة'),
        () => c.open('/admin'),
      ),
    if (c.permission('quiz.manage'))
      menuRow(
        'book',
        c.t('Quiz question bank', 'بنك أسئلة الاختبارات'),
        () => c.open('/quiz/manage'),
      ),
    if (c.permission('schedule.manage'))
      menuRow(
        'calendar',
        c.t('Manage schedule', 'إدارة الجدول'),
        () => c.open('/admin/schedule'),
      ),
    const SizedBox(height: 10),
    menuRow('logout', c.t('Logout', 'تسجيل الخروج'), () async {
      try {
        await c.logout();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }, danger: true),
  ];
  List<Widget> notifications() => [
    chips(
      [
        ('all', c.t('All', 'الكل')),
        ('replies', c.t('Replies', 'الردود')),
        ('likes', c.t('Reactions', 'التفاعلات')),
      ],
      'tab',
      value(data['tab'], 'all'),
    ),
    if (yes(data['canAddAnnouncement']))
      FilledButton.tonalIcon(
        onPressed: () => form(
          c.t('New announcement', 'إعلان جديد'),
          '/notifications/announcements',
          [
            FieldSpec('title', c.t('Title', 'العنوان')),
            FieldSpec('details', c.t('Announcement', 'الإعلان'), lines: 6),
          ],
        ),
        icon: const Icon(Icons.campaign_outlined),
        label: Text(c.t('Post announcement', 'نشر إعلان')),
      ),
    if (rows(data['announcements']).isNotEmpty)
      heading(c.t('Announcements', 'الإعلانات')),
    for (final item in rows(data['announcements']))
      Card(
        child: ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: Text(value(item['title'])),
          subtitle: Text(date(item['created_at'])),
          onTap: () => c.open('/notifications/announcements/${item['id']}'),
        ),
      ),
    if (rows(data['notifications']).isNotEmpty)
      heading(c.t('Recent activity', 'النشاط الأخير')),
    for (final item in rows(data['notifications']))
      Card(
        child: ListTile(
          leading: Icon(
            item['kind'] == 'announcement'
                ? Icons.campaign_outlined
                : Icons.notifications_active_outlined,
          ),
          title: Text(
            value(
              item['message'] ??
                  item['title'] ??
                  item['actor_name'] ??
                  object(item['actor'])['name'],
              label(value(item['type'])),
            ),
          ),
          subtitle: Text(
            [
              notificationDescription(item),
              date(item['created_at']),
            ].where((v) => v.isNotEmpty).join(' · '),
          ),
          trailing: item['read_at'] == null
              ? const Icon(Icons.circle, size: 9)
              : null,
          onTap: () => c.open(
            value(
              item['destination'] ?? item['url'],
              '/notifications/${item['id']}',
            ),
          ),
        ),
      ),
    if (rows(data['notifications']).isEmpty &&
        rows(data['announcements']).isEmpty)
      empty(),
    pagination(data['notifications']),
  ];
  String notificationDescription(Json item) => switch (item['type']) {
    'post_reply' => c.t('Replied to your post', 'رد على منشورك'),
    'question_answer' => c.t('Answered your question', 'أجاب عن سؤالك'),
    'post_like' => c.t('Reacted to your post', 'تفاعل مع منشورك'),
    'comment_like' => c.t('Reacted to your comment', 'تفاعل مع تعليقك'),
    'answer_received' => c.t('Answered your question', 'أجاب عن سؤالك'),
    _ => value(item['details']),
  };
  List<Widget> announcement() {
    final item = object(data['announcement']);
    return [
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.campaign_outlined, size: 36),
            const SizedBox(height: 18),
            Text(
              value(item['title']),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(date(item['created_at'])),
            const SizedBox(height: 24),
            SelectableText(
              value(item['details']),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
      if (yes(c.user?['can_post_announcements']) ||
          c.permission('announcements.manage') ||
          '${item['user_id']}' == '${c.user?['id']}')
        OutlinedButton.icon(
          onPressed: () async {
            final result = await form(
              c.t('Delete announcement?', 'حذف الإعلان؟'),
              '/notifications/announcements/${item['id']}',
              [],
              method: 'DELETE',
              destructive: true,
            );
            if (result != null && mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(c.t('Delete', 'حذف')),
        ),
    ];
  }

  List<Widget> notificationSettings() {
    final prefs = object(data['preferences']);
    return [
      ListenableBuilder(
        listenable: c.push,
        builder: (_, _) => card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.notifications_outlined, size: 40),
              const SizedBox(height: 12),
              Text(c.push.state),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: c.push.available ? c.push.enable : null,
                child: Text(
                  c.t('Enable on this device', 'تفعيل على هذا الجهاز'),
                ),
              ),
            ],
          ),
        ),
      ),
      heading(c.t('What you receive', 'الإشعارات التي تصلك')),
      for (final entry in prefs.entries)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(categoryLabel(entry.key)),
          value: yes(entry.value),
          onChanged: (on) async {
            final enabled = prefs.entries
                .where((e) => e.key == entry.key ? on : yes(e.value))
                .map((e) => e.key)
                .toList();
            await run('PUT', '/menu/notifications', {'categories': enabled});
          },
        ),
      TextButton(
        onPressed: () => run('POST', '/push/test'),
        child: Text(c.t('Send a test notification', 'إرسال إشعار تجريبي')),
      ),
    ];
  }

  String categoryLabel(String key) => switch (key) {
    'inbox' => c.t('Inbox questions & answers', 'أسئلة وإجابات الوارد'),
    'announcements' => c.t('Announcements', 'الإعلانات'),
    'replies' => c.t('Replies', 'الردود'),
    'reactions' => c.t('Likes & reactions', 'الإعجابات والتفاعلات'),
    _ => key.replaceAll('_', ' '),
  };
  List<Widget> suggestions() => [
    const SizedBox(height: 20),
    const Icon(Icons.lightbulb_outline, size: 64),
    const SizedBox(height: 24),
    Text(
      c.t('Help make ElBench better.', 'ساعدنا نجعل البنش أفضل.'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    Text(
      c.t(
        'Have an idea or something we should improve? We’re listening.',
        'عندك فكرة أو شيء يحتاج تحسين؟ نحن نسمعك.',
      ),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: () =>
          form(c.t('Share a suggestion', 'شارك اقتراحًا'), '/suggestions', [
            FieldSpec('title', c.t('Title', 'العنوان')),
            FieldSpec('details', c.t('Your suggestion', 'اقتراحك'), lines: 6),
          ]),
      child: Text(c.t('Write a suggestion', 'اكتب اقتراحًا')),
    ),
  ];
  List<Widget> hall() => [
    Text(
      c.t('The people making a difference.', 'ناس بتصنع فرقًا.'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 24),
    for (final (i, person) in rows(data['top_users']).indexed)
      card(
        Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(
                i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                style: const TextStyle(fontSize: 24),
              ),
            ),
            Expanded(
              child: personLine(
                person,
                subtitle: '${person['points'] ?? 0} ${c.t('points', 'نقطة')}',
              ),
            ),
          ],
        ),
      ),
    if (rows(data['top_users']).isEmpty) empty(),
  ];
  List<Widget> activity() => [
    Text(c.t('Recent sign-ins to your account.', 'آخر مرات الدخول إلى حسابك.')),
    const SizedBox(height: 20),
    for (final item in rows(data['activities']))
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value(
                      [
                        item['device_type'],
                        item['os_name'],
                        item['browser_name'],
                        item['browser_version'],
                      ].where((v) => value(v).isNotEmpty).join(' · '),
                      c.t('Device', 'جهاز'),
                    ),
                    maxLines: 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(value(item['ip_address'])),
            Text(date(item['logged_in_at'] ?? item['created_at'])),
            if (value(item['location']).isNotEmpty)
              Text(value(item['location'])),
          ],
        ),
      ),
    if (rows(data['activities']).isEmpty) empty(),
  ];
  List<Widget> resetPassword() => [
    Text(
      c.t(
        'A verification code will be sent to ${data['email'] ?? ''}.',
        'سنرسل رمز تحقق إلى ${data['email'] ?? ''}.',
      ),
    ),
    const SizedBox(height: 24),
    FilledButton.tonal(
      onPressed: () => run('POST', '/profile/password/reset/code'),
      child: Text(c.t('Send verification code', 'إرسال رمز التحقق')),
    ),
    const SizedBox(height: 14),
    FilledButton(
      onPressed: () => form(
        c.t('Reset password', 'إعادة تعيين كلمة المرور'),
        '/profile/password/reset',
        [
          FieldSpec('code', c.t('Six-digit code', 'الرمز المكون من ستة أرقام')),
          FieldSpec(
            'password',
            c.t('New password', 'كلمة المرور الجديدة'),
            secret: true,
          ),
          FieldSpec(
            'password_confirmation',
            c.t('Confirm password', 'تأكيد كلمة المرور'),
            secret: true,
          ),
        ],
        follow: true,
      ),
      child: Text(
        c.t('Enter code & reset password', 'أدخل الرمز وأعد تعيين كلمة المرور'),
      ),
    ),
  ];
  List<Widget> terms() => [
    Text(
      c.t('Community guidelines', 'إرشادات المجتمع'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 20),
    SelectableText(
      value(
        data['terms_text'],
        c.t(
          'The published terms could not be loaded. Open the full terms below.',
          'تعذر تحميل الشروط المنشورة. افتح الشروط الكاملة أدناه.',
        ),
      ),
    ),
    const SizedBox(height: 20),
    TextButton.icon(
      onPressed: () => external(c.api.media('/terms')),
      icon: const Icon(Icons.open_in_new),
      label: Text(
        c.t('Read the full published terms', 'قراءة الشروط المنشورة بالكامل'),
      ),
    ),
  ];
  List<Widget> reportInspect() {
    final report = object(data['report']);
    final post = object(data['post']);
    final comment = object(data['reportedComment']);
    final scheme = Theme.of(context).colorScheme;
    Widget section(
      String title,
      String content, {
      String? author,
      bool small = false,
    }) => Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: small ? 17 : 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (author != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 16),
              child: Text(
                author,
                style: const TextStyle(fontSize: 16, height: 1.65),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: author == null ? 6 : 0, bottom: 16),
            child: SelectableText(
              content,
              style: const TextStyle(fontSize: 16, height: 1.65),
            ),
          ),
        ],
      ),
    );
    final reportedComment = report['reported_comment_id'];
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(
          onPressed: () => c.open('/admin?section=reports'),
          child: Text(c.t('Post reports', 'بلاغات المنشورات')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(
          reportedComment == null
              ? c.t(
                  'Reported post #${report['reported_post_id']}',
                  'المنشور المبلغ عنه #${report['reported_post_id']}',
                )
              : c.t(
                  'Reported comment #$reportedComment · Post #${report['reported_post_id']}',
                  'التعليق المبلغ عنه #$reportedComment · المنشور #${report['reported_post_id']}',
                ),
          style: const TextStyle(
            fontSize: 26,
            height: 1.2,
            letterSpacing: -1.04,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      section(
        c.t('Report reason', 'سبب البلاغ'),
        value(report['reason']).isEmpty
            ? c.t('No reason provided.', 'لم يُذكر سبب.')
            : value(report['reason']),
      ),
      section(
        c.t('Content when reported', 'المحتوى وقت البلاغ'),
        value(report['post_snapshot']),
        author: value(report['author_name']),
      ),
      if (reportedComment != null)
        section(
          c.t('Current reported comment', 'التعليق المبلغ عنه حاليًا'),
          comment.isEmpty
              ? c.t(
                  'The comment was deleted. Its report snapshot is retained.',
                  'التعليق اتحذف. محتواه وقت البلاغ لسه محفوظ.',
                )
              : value(comment['content']),
          author: comment.isEmpty
              ? null
              : value(object(comment['author'])['name']),
        ),
      section(
        c.t('Current post', 'المنشور الحالي'),
        post.isEmpty
            ? c.t(
                'The original post was deleted. The report snapshot is retained.',
                'تم حذف المنشور الأصلي. محتوى البلاغ محفوظ.',
              )
            : value(post['content']),
        author: post.isEmpty ? null : value(object(post['author'])['name']),
      ),
      for (final row in rows(data['comments']))
        section(
          value(object(row['author'])['name']),
          value(row['content']),
          small: true,
        ),
      if (post.isNotEmpty) pagination(data['comments']),
    ];
  }
}

Color? hex(String input) {
  final v = int.tryParse(input.replaceAll('#', ''), radix: 16);
  return input.length == 7 && v != null ? Color(0xff000000 | v) : null;
}
