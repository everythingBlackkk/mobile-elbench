import 'dart:async';
import 'package:elbench/api.dart';
import 'package:elbench/app_menus.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_motion.dart';
import 'package:elbench/web_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NavigationApi extends MobileApi {
  _NavigationApi({this.peopleCount = 0});
  final int peopleCount;
  @override
  Uri get baseUri => Uri.parse('https://navigation.example.test');
  Json user = {
    'id': 7,
    'name': 'Mariam',
    'banner_color': '#111111',
    'role': 'student',
    'permissions': <String>[],
  };
  final holds = <String, Completer<Json>>{};
  final gets = <String>[];
  Json envelope(String screen, Json data) => {
    'screen': screen,
    'data': data,
    'user': {...user},
    'features': {'community': true, 'quiz': true},
    'counts': {'notifications': 0, 'inbox': 0},
    'csrf_token': 'never-cache-this',
  };
  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    final route = uri.path;
    gets.add(route);
    if (holds[route] case final hold?) return hold.future;
    return switch (route) {
      '/mobile/session' => envelope('', {}),
      '/community' => envelope('community.index', {
        'search': (uri.queryParameters['q'] ?? '').trim(),
        'communities': [],
        'posts': [],
        'featured_events': [],
      }),
      '/people' => envelope('people.index', {
        'people': [
          for (var i = 0; i < peopleCount; i++)
            {'id': i + 20, 'name': 'Student $i', 'university_id': '$i'},
        ],
      }),
      '/profile' => envelope('profile.show', {
        'profile_user': user,
        'skills': [],
        'activityTab': 'posts',
        'profile_posts': {'data': []},
      }),
      '/menu' => envelope('content.menu', {}),
      '/inbox' => envelope('ask.inbox', {'questions': [], 'tab': 'inbox'}),
      _ => envelope('content.suggestions', {}),
    };
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      envelope('', {});
  @override
  Future<void> clearSession() async {}
}

Future<AppSettings> _settings([String language = 'en']) async {
  SharedPreferences.setMockInitialValues({
    'appearance.language': language,
    'appearance.liquidGlass': false,
  });
  final settings = AppSettings();
  await settings.load();
  return settings;
}

NativePageState _current(WidgetTester tester) =>
    tester.stateList<NativePageState>(find.byType(NativePage)).last;
Future<void> _visitStarted(WidgetTester tester, String path) async {
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    final page = _current(tester);
    if (page.path == path &&
        find
            .descendant(
              of: find.byWidget(page.widget),
              matching: find.byKey(const ValueKey('navigation.incomingBody')),
            )
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  expect(_current(tester).path, path);
}

Finder _inside(NativePageState page, Finder child) {
  final local = find.descendant(
    of: find.byWidget(page.widget),
    matching: child,
  );
  return local.evaluate().isEmpty ? child : local;
}

double _translation(WidgetTester tester, NativePageState page) => tester
    .widget<Transform>(
      _inside(page, find.byKey(const ValueKey('navigation.incomingBody'))),
    )
    .transform
    .storage[12];

void main() {
  testWidgets(
    'retained content refreshes prebuilt menu labels after theme changes',
    (tester) async {
      final settings = await _settings();
      settings.setMode(ThemeMode.light);
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: settings,
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      _current(tester).c.open('/menu');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Switch Theme'), 250);
      await tester.pumpAndSettle();
      expect(find.text('Light'), findsOneWidget);
      settings.setMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsNothing);
    },
  );

  testWidgets('returning from a live transition retains local page state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ElBenchApp(
        api: _NavigationApi(),
        settings: await _settings(),
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    final homeState = tester.state(find.byType(WebHome));
    await tester.enterText(find.byType(TextField).first, 'Retained search');
    _current(tester).c.open('/people', tabDirection: 1);
    await tester.pumpAndSettle();
    _current(tester).c.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(WebHome)), same(homeState));
    expect(find.text('Retained search'), findsOneWidget);
    expect(find.text('No posts match your search.'), findsOneWidget);
    expect(find.byKey(const ValueKey('home.search.loading')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delayed visits keep the previous body until the slide completes',
    (tester) async {
      final api = _NavigationApi();
      await tester.pumpWidget(
        ElBenchApp(
          api: api,
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final hold = Completer<Json>();
      api.holds['/people'] = hold;
      _current(tester).c.open('/people', tabDirection: 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final page = _current(tester);
      final route = ModalRoute.of(page.context) as WebPageRoute;
      expect(route.opaque, isFalse);
      expect(find.byType(WebHome), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      hold.complete(api.envelope('people.index', {'people': []}));
      await tester.pumpAndSettle();
      expect(route.opaque, isTrue);
      expect(find.byType(WebHome), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covered activity routes defer badge refresh until returning', (
    tester,
  ) async {
    final api = _NavigationApi();
    await tester.pumpWidget(
      ElBenchApp(
        api: api,
        settings: await _settings(),
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    _current(tester).c.open('/inbox', tabDirection: 1);
    await tester.pumpAndSettle();
    final inbox = _current(tester);
    inbox.c.open('/people', tabDirection: -1);
    await tester.pumpAndSettle();
    final before = api.gets.where((path) => path == '/inbox').length;
    inbox.c.absorb({
      'counts': {'notifications': 0, 'inbox': 4},
    });
    await tester.pumpAndSettle();
    expect(api.gets.where((path) => path == '/inbox').length, before);
    inbox.c.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_current(tester), same(inbox));
    expect(api.gets.where((path) => path == '/inbox').length, before + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared chrome retains the same native views across tab and profile changes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('elbench/native-glass'),
        (_) async => true,
      );
      var creations = 0, disposals = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') creations++;
        if (call.method == 'dispose') disposals++;
        return null;
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        messenger.setMockMethodCallHandler(
          const MethodChannel('elbench/native-glass'),
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        debugDefaultTargetPlatformOverride = null;
      });
      final settings = await _settings();
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: settings,
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final dock = tester.getRect(find.byKey(const ValueKey('dock.home')));
      final views = find.byType(UiKitView).evaluate().toList();
      expect(creations, 3);
      for (var i = 0; i < 9; i++) {
        await tester.tap(
          find
              .byKey(
                ValueKey(['dock.people', 'dock.profile', 'dock.home'][i % 3]),
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(find.byType(UiKitView, skipOffstage: false), findsNWidgets(3));
        expect(
          find.byType(UiKitView).evaluate().toList(),
          orderedEquals(views),
        );
        expect(creations, 3);
        expect(disposals, 0);
        expect(
          tester.getRect(find.byKey(const ValueKey('dock.home')).last),
          dock,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('options retain native chrome through selection in $mode', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('elbench/native-glass'),
        (_) async => true,
      );
      var creations = 0, disposals = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') creations++;
        if (call.method == 'dispose') disposals++;
        return null;
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        messenger.setMockMethodCallHandler(
          const MethodChannel('elbench/native-glass'),
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        debugDefaultTargetPlatformOverride = null;
      });
      final settings = await _settings();
      settings.setMode(mode);
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: settings,
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final page = _current(tester);
      final dock = tester.element(find.byType(WebBottomNav));
      final originalViews = find.byType(UiKitView).evaluate().toList();
      expect(originalViews, hasLength(3));
      final selection = showAppMenu<String>(
        context: page.context,
        anchorContext: tester.element(
          find.byKey(const ValueKey('header.menu')),
        ),
        items: const [
          PopupMenuItem(value: 'people', child: Text('Visit people')),
        ],
      );
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(WebBottomNav)), same(dock));
      expect(
        find.byType(UiKitView).evaluate().take(3),
        orderedEquals(originalViews),
      );
      expect(creations, 4);
      expect(disposals, 0);
      expect(
        find.byKey(const ValueKey('dock.people')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.text('Visit people'));
      await tester.pumpAndSettle();
      expect(await selection, 'people');
      expect(find.byType(UiKitView).evaluate(), orderedEquals(originalViews));
      expect(disposals, 1);
      expect(tester.element(find.byType(WebBottomNav)), same(dock));

      // A remaining nested dialog must also leave native surfaces painted.
      showDialog<void>(
        context: page.context,
        useRootNavigator: false,
        builder: (_) => const AlertDialog(content: Text('Nested dialog')),
      );
      await tester.pumpAndSettle();
      expect(page.c.modalVisible, isTrue);
      expect(
        tester
            .widgetList<ExcludeFocus>(
              find.ancestor(
                of: find.byType(WebBottomNav),
                matching: find.byType(ExcludeFocus),
              ),
            )
            .any((widget) => widget.excluding),
        isTrue,
      );
      expect(
        tester
            .widgetList<ExcludeSemantics>(
              find.ancestor(
                of: find.byType(WebBottomNav),
                matching: find.byType(ExcludeSemantics),
              ),
            )
            .any((widget) => widget.excluding),
        isTrue,
      );
      expect(find.byType(UiKitView).evaluate(), orderedEquals(originalViews));
      expect(
        find.byKey(const ValueKey('dock.people')).hitTestable(),
        findsNothing,
      );
      Navigator.of(page.context).pop();
      await tester.pumpAndSettle();
      expect(page.c.modalVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('dock.people')));
      await tester.pumpAndSettle();
      expect(_current(tester).path, '/people');
      expect(tester.element(find.byType(WebBottomNav)), same(dock));
      expect(find.byType(UiKitView).evaluate(), orderedEquals(originalViews));
      expect(creations, 4);
      expect(disposals, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'selection glides through intermediate positions and reverses on rapid retaps',
    (tester) async {
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      Finder lens() => find.descendant(
        of: find.byKey(const ValueKey('dock.selection')),
        matching: find.byType(FractionallySizedBox),
      );
      final start = tester.getCenter(lens()).dx;
      final target = tester
          .getCenter(find.byKey(const ValueKey('dock.profile')))
          .dx;
      await tester.tap(find.byKey(const ValueKey('dock.profile')));
      await _visitStarted(tester, '/profile');
      await tester.pump(const Duration(milliseconds: 70));
      final middle = tester.getCenter(lens()).dx;
      expect(middle, inExclusiveRange(start, target));
      await tester.tap(find.byKey(const ValueKey('dock.home')));
      await _visitStarted(tester, '/community');
      await tester.pumpAndSettle();
      expect(tester.getCenter(lens()).dx, closeTo(start, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal drag across dock smoothly tracks finger and activates hovered tab on release',
    (tester) async {
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      Finder lens() => find.descendant(
        of: find.byKey(const ValueKey('dock.selection')),
        matching: find.byType(FractionallySizedBox),
      );
      final homeCenter = tester.getCenter(
        find.byKey(const ValueKey('dock.home')),
      );
      final peopleCenter = tester.getCenter(
        find.byKey(const ValueKey('dock.people')),
      );
      final profileCenter = tester.getCenter(
        find.byKey(const ValueKey('dock.profile')),
      );
      expect(tester.getCenter(lens()).dx, closeTo(homeCenter.dx, 1.0));

      final gesture = await tester.startGesture(homeCenter);
      await tester.pump();
      await gesture.moveTo(peopleCenter);
      await tester.pump();
      expect(tester.getCenter(lens()).dx, closeTo(peopleCenter.dx, 2.0));

      await gesture.moveTo(profileCenter);
      await tester.pump();
      expect(tester.getCenter(lens()).dx, closeTo(profileCenter.dx, 2.0));

      await gesture.up();
      await _visitStarted(tester, '/profile');
      await tester.pumpAndSettle();
      expect(_current(tester).path, '/profile');
      expect(tester.getCenter(lens()).dx, closeTo(profileCenter.dx, 1.0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll updates retain chrome widgets and do not notify the app',
    (tester) async {
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final page = _current(tester);
      final back = tester.widget(find.byKey(const ValueKey('header.back')));
      final dock = tester.element(find.byType(WebBottomNav));
      var broadcasts = 0;
      page.c.addListener(() => broadcasts++);
      for (var offset = 0; offset < 1000; offset += 10) {
        page.reportScrollOffset(offset.toDouble());
      }
      await tester.pump();
      expect(
        tester.widget(find.byKey(const ValueKey('header.back'))),
        same(back),
      );
      expect(tester.element(find.byType(WebBottomNav)), same(dock));
      expect(broadcasts, 0);
    },
  );

  testWidgets('root sheets cover shared chrome without removing its state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ElBenchApp(
        api: _NavigationApi(),
        settings: await _settings(),
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    final page = _current(tester);
    final dock = tester.element(find.byType(WebBottomNav));
    showModalBottomSheet<void>(
      context: page.context,
      useRootNavigator: true,
      builder: (_) => const SizedBox(height: 280, child: Text('Sheet content')),
    );
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(WebBottomNav)), same(dock));
    expect(
      find.byKey(const ValueKey('dock.people')).hitTestable(),
      findsNothing,
    );
    Navigator.of(page.context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(WebBottomNav)), same(dock));
    expect(
      find.byKey(const ValueKey('dock.people')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets(
    'profile status icons stay legible over the banner and collapsed header',
    (tester) async {
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dock.profile')));
      await tester.pumpAndSettle();
      Finder region() => find.descendant(
        of: find.byKey(const ValueKey('navigation.sharedHeader')),
        matching: find.byWidgetPredicate(
          (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
        ),
      );
      expect(
        tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(region())
            .value
            .statusBarIconBrightness,
        Brightness.light,
      );
      _current(tester).reportScrollOffset(200);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(region())
            .value
            .statusBarIconBrightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared header survives immediate route disposal and metadata refresh',
    (tester) async {
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final c = _current(tester).c;
      for (var i = 0; i < 4; i++) {
        c.open('/suggestions');
        await tester.pumpAndSettle();
        c.navigator.currentState!.pop();
        c.absorb({
          'counts': {'notifications': i + 1, 'inbox': 0},
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('header.back')), findsOneWidget);
      }
    },
  );

  testWidgets(
    'unchanged GET metadata is quiet but mutations still invalidate',
    (tester) async {
      final api = _NavigationApi();
      final c = AppController(
        api,
        await _settings(),
        GlobalKey<NavigatorState>(),
        enablePush: false,
      );
      addTearDown(c.dispose);
      c.absorb(api.envelope('', {}));
      var notifications = 0;
      c.addListener(() => notifications++);
      final generation = c.cacheGeneration;
      await c.get('/people');
      await c.get('/community');
      expect(notifications, 0);
      expect(c.cacheGeneration, generation);
      await c.action('POST', '/some-action');
      expect(notifications, 1);
      expect(c.cacheGeneration, generation + 1);
      c.absorb({
        'counts': {'notifications': 2, 'inbox': 0},
      });
      expect(notifications, 2);
    },
  );

  testWidgets('badge updates preserve the app theme and display live counts', (
    tester,
  ) async {
    final settings = await _settings();
    await tester.pumpWidget(
      ElBenchApp(
        api: _NavigationApi(),
        settings: settings,
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    final page = _current(tester);
    final theme = Theme.of(page.context);
    page.c.absorb({
      'counts': {'notifications': 5, 'inbox': 0},
    });
    await tester.pumpAndSettle();
    expect(Theme.of(page.context), same(theme));
    expect(find.text('5'), findsOneWidget);
    settings.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(page.context).brightness, Brightness.dark);
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      'dock stays fixed while body moves in both physical directions ($language)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(375, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ElBenchApp(
            api: _NavigationApi(),
            settings: await _settings(language),
            enablePush: false,
            enableLaunchExperience: false,
          ),
        );
        await tester.pumpAndSettle();
        final home = _current(tester);
        final firstDock = tester.getRect(
          _inside(home, find.byKey(const ValueKey('dock.home'))),
        );
        final firstBack = tester.getRect(
          _inside(home, find.byKey(const ValueKey('header.back'))),
        );
        expect(
          tester
              .getCenter(_inside(home, find.byKey(const ValueKey('dock.home'))))
              .dx,
          lessThan(
            tester
                .getCenter(
                  _inside(home, find.byKey(const ValueKey('dock.people'))),
                )
                .dx,
          ),
        );
        await tester.tap(
          _inside(home, find.byKey(const ValueKey('dock.people'))),
        );
        await _visitStarted(tester, '/people');
        final people = _current(tester);
        expect(_translation(tester, people), greaterThan(0));
        expect(
          tester
              .widgetList<Visibility>(
                find.byKey(
                  const ValueKey('navigation.dockVisibility'),
                  skipOffstage: false,
                ),
              )
              .where((v) => v.visible)
              .length,
          1,
        );
        for (final duration in [
          const Duration(milliseconds: 40),
          const Duration(milliseconds: 70),
        ]) {
          await tester.pump(duration);
          expect(
            tester.getRect(
              _inside(people, find.byKey(const ValueKey('dock.home'))),
            ),
            firstDock,
          );
          expect(
            tester.getRect(
              _inside(people, find.byKey(const ValueKey('header.back'))),
            ),
            firstBack,
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(
          _inside(people, find.byKey(const ValueKey('dock.home'))),
        );
        await _visitStarted(tester, '/community');
        final returned = _current(tester);
        expect(_translation(tester, returned), lessThan(0));
        expect(
          tester
              .widgetList<Visibility>(
                find.byKey(
                  const ValueKey('navigation.dockVisibility'),
                  skipOffstage: false,
                ),
              )
              .where((v) => v.visible)
              .length,
          1,
        );
        await tester.pump(const Duration(milliseconds: 70));
        expect(
          tester.getRect(
            _inside(returned, find.byKey(const ValueKey('dock.home'))),
          ),
          firstDock,
        );
        expect(
          tester.getRect(
            _inside(returned, find.byKey(const ValueKey('header.back'))),
          ),
          firstBack,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('menu pop reverses body while both shared bars stay fixed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ElBenchApp(
        api: _NavigationApi(),
        settings: await _settings(),
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    final home = _current(tester);
    final dock = tester.getRect(
      _inside(home, find.byKey(const ValueKey('dock.home'))),
    );
    final previousHeader = tester.getRect(
      _inside(home, find.byKey(const ValueKey('header.back'))),
    );
    await tester.tap(_inside(home, find.byKey(const ValueKey('header.menu'))));
    await _visitStarted(tester, '/menu');
    await tester.pumpAndSettle();
    final menu = _current(tester);
    expect((ModalRoute.of(menu.context) as WebPageRoute).opaque, isTrue);
    final background = Theme.of(menu.context).scaffoldBackgroundColor;
    expect(
      tester
          .widgetList<ColoredBox>(_inside(menu, find.byType(ColoredBox)))
          .where((box) => box.color == background),
      isNotEmpty,
    );
    expect(_translation(tester, menu), 0);
    await tester.tap(_inside(menu, find.byKey(const ValueKey('header.back'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, menu), greaterThan(0));
    expect(
      tester
          .widgetList<Visibility>(
            find.byKey(
              const ValueKey('navigation.dockVisibility'),
              skipOffstage: false,
            ),
          )
          .where((v) => v.visible)
          .length,
      1,
    );
    expect(
      tester.getRect(_inside(menu, find.byKey(const ValueKey('dock.home')))),
      dock,
    );
    expect(
      tester.getRect(_inside(home, find.byKey(const ValueKey('header.back')))),
      previousHeader,
    );
    expect(
      tester
          .getRect(_inside(menu, find.byKey(const ValueKey('header.back'))))
          .left,
      previousHeader.left,
    );
    await tester.pumpAndSettle();
    expect(_current(tester), same(home));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cached dock body appears before revalidation and restores vertical offset',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _NavigationApi();
      await tester.pumpWidget(
        ElBenchApp(
          api: api,
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final home = _current(tester);
      await tester.drag(
        _inside(home, find.byType(ListView).first),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      // Reveal the scroll-hidden dock before choosing another tab.
      await tester.drag(
        _inside(home, find.byType(ListView).first),
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      final offset = home.scrollOffset.value;
      expect(offset, greaterThan(0));
      await tester.tap(
        _inside(home, find.byKey(const ValueKey('dock.people'))),
      );
      await _visitStarted(tester, '/people');
      await tester.pumpAndSettle();
      final gate = Completer<Json>();
      api.holds['/community'] = gate;
      await tester.tap(
        _inside(_current(tester), find.byKey(const ValueKey('dock.home'))),
      );
      await _visitStarted(tester, '/community');
      final cached = _current(tester);
      expect(cached.screen, 'community.index');
      expect(cached.envelope, isNotEmpty);
      expect(
        find.byKey(const ValueKey('home.search.loading')),
        findsNothing,
        reason: 'same-query cache revalidation keeps accepted Home content',
      );
      expect(cached.scrollOffset.value, closeTo(offset, 1));
      expect(cached.envelope.containsKey('csrf_token'), isFalse);
      gate.complete(
        api.envelope('community.index', {
          'communities': [],
          'posts': [],
          'featured_events': [],
        }),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        _inside(cached, find.byKey(const ValueKey('dock.home'))),
      );
      await tester.pumpAndSettle();
      expect(cached.scrollOffset.value, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final path in ['/community', '/people', '/menu', '/profile']) {
    testWidgets('dock slides offscreen on down and returns on up in $path', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(peopleCount: 40),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      if (path != '/community') {
        _current(tester).c.open(path);
        await tester.pumpAndSettle();
      }
      final page = _current(tester);
      final scroll = find
          .descendant(
            of: find.byWidget(page.widget),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final dock = find.byKey(const ValueKey('navigation.sharedDock'));
      final original = tester.getRect(dock);
      final element = tester.element(find.byType(WebBottomNav));
      final header = tester.getRect(find.byKey(const ValueKey('header.back')));
      var broadcasts = 0;
      page.c.addListener(() => broadcasts++);
      await tester.drag(scroll, const Offset(0, -140));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final intermediate = tester.getRect(dock);
      expect(intermediate.top, greaterThan(original.top));
      expect(
        intermediate.top,
        lessThan(original.bottom + original.height * .3),
      );
      await tester.pumpAndSettle();
      final hidden = tester.getRect(dock);
      expect(hidden.top, greaterThanOrEqualTo(original.bottom));
      expect(
        find.byKey(const ValueKey('dock.home')).hitTestable(),
        findsNothing,
      );
      expect(tester.element(find.byType(WebBottomNav)), same(element));
      expect(tester.getRect(find.byKey(const ValueKey('header.back'))), header);
      await tester.drag(scroll, const Offset(0, 60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(dock).top, lessThan(hidden.top));
      expect(tester.getRect(dock).top, greaterThanOrEqualTo(original.top));
      await tester.pumpAndSettle();
      expect(tester.getRect(dock), original);
      expect(
        find.byKey(const ValueKey('dock.home')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.element(find.byType(WebBottomNav)), same(element));
      expect(broadcasts, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dock ignores restored offsets and returns on route changes and top pulls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ElBenchApp(
          api: _NavigationApi(peopleCount: 40),
          settings: await _settings(),
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final c = _current(tester).c;
      c.open('/people');
      await tester.pumpAndSettle();
      final page = _current(tester);
      final scroll = find
          .descendant(
            of: find.byWidget(page.widget),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(200);
      await tester.pumpAndSettle();
      expect(c.dockHidden.value, isFalse);
      await tester.drag(scroll, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(c.dockHidden.value, isTrue);
      c.open('/menu');
      await tester.pumpAndSettle();
      expect(c.dockHidden.value, isFalse);
      c.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(c.dockHidden.value, isFalse);
      page.scrollToTop();
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(c.dockHidden.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dock respects reduced motion when hiding and revealing', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.binding.setSurfaceSize(const Size(375, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ElBenchApp(
        api: _NavigationApi(peopleCount: 40),
        settings: await _settings(),
        enablePush: false,
        enableLaunchExperience: false,
      ),
    );
    await tester.pumpAndSettle();
    _current(tester).c.open('/people');
    await tester.pumpAndSettle();
    final page = _current(tester);
    final scroll = find
        .descendant(
          of: find.byWidget(page.widget),
          matching: find.byType(Scrollable),
        )
        .first;
    final slide = find.byKey(const ValueKey('navigation.dockSlide'));
    await tester.drag(scroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(page.c.dockHidden.value, isTrue);
    expect(tester.widget<AnimatedSlide>(slide).duration, Duration.zero);
    await tester.drag(scroll, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(page.c.dockHidden.value, isFalse);
    expect(tester.widget<AnimatedSlide>(slide).duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  test('dock motion direction is independent of interface text direction', () {
    for (final rtl in [false, true]) {
      expect(
        WebVisitMotion.between(
          '/community',
          '/people',
          tabDirection: 1,
          rtl: rtl,
        ).fraction,
        1,
      );
      expect(
        WebVisitMotion.between(
          '/people',
          '/community',
          tabDirection: -1,
          rtl: rtl,
        ).fraction,
        -1,
      );
    }
  });
  testWidgets(
    'page cache is bounded, sanitized, and invalidated by locale and permissions',
    (tester) async {
      final settings = await _settings(), api = _NavigationApi();
      final c = AppController(
        api,
        settings,
        GlobalKey<NavigatorState>(),
        enablePush: false,
      );
      addTearDown(c.dispose);
      c.absorb(api.envelope('', {}));
      final kept = AppController.maxKeptPages;
      for (int i = 0; i <= kept; i++) {
        c.rememberPage(
          '/page/$i',
          api.envelope('content.suggestions', {
            'value': i,
            'presence_token': 'private',
            'password': 'private',
          }),
          offset: i.toDouble(),
        );
      }
      expect(c.cachedPage('/page/0'), isNull);
      expect(c.cachedPage('/page/$kept')!.envelope, {
        'screen': 'content.suggestions',
        'data': {'value': kept},
        'canonical_url': '/page/$kept',
      });
      expect(c.keptScrollOffset('/page/$kept'), kept.toDouble());
      settings.setLanguage('ar');
      await tester.pump();
      expect(c.cachedPage('/page/8'), isNull);
      expect(c.keptScrollOffset('/page/8'), 0);
      c.rememberPage('/people', api.envelope('people.index', {}));
      c.absorb({
        'user': {
          ...api.user,
          'role': 'admin',
          'permissions': ['users.manage'],
        },
      });
      expect(c.cachedPage('/people'), isNull);
    },
  );
  testWidgets('stale GET cannot replace a newer signed-in account', (
    tester,
  ) async {
    final api = _NavigationApi(), settings = await _settings();
    final c = AppController(
      api,
      settings,
      GlobalKey<NavigatorState>(),
      enablePush: false,
    );
    addTearDown(c.dispose);
    c.absorb(api.envelope('', {}));
    final held = Completer<Json>();
    api.holds['/people'] = held;
    final pending = c.get('/people');
    c.absorb({
      'user': {'id': 99, 'name': 'New account', 'role': 'student'},
    });
    held.complete(api.envelope('people.index', {}));
    await pending;
    expect(c.user?['id'], 99);
  });
}
