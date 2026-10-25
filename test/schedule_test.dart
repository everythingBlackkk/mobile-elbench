import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:elbench/api.dart';
import 'package:elbench/image_cache.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_schedule.dart';
import 'package:elbench/web_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledImage extends ImageStreamCompleter {
  void show(ui.Image image) => setImage(ImageInfo(image: image));
  void fail() => reportError(
    context: ErrorDescription('loading a configured day-off image'),
    exception: const FormatException('Invalid image'),
    silent: true,
  );
}

_ControlledImage _configuredImage(String path) {
  final stream = _ControlledImage();
  PaintingBinding.instance.imageCache.putIfAbsent(
    CachedNetworkImage(
      'https://schedule.example.test$path',
      width: 220,
      cover: false,
    ),
    () => stream,
  );
  return stream;
}

Future<void> _showConfiguredImage(
  WidgetTester tester,
  _ControlledImage stream,
) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(16, 16));
  picture.dispose();
  stream.show(image!);
  await tester.pumpAndSettle();
}

class _Api extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://schedule.example.test');
  final requests = <Uri>[];
  final writes = <(String, String, Json)>[];
  String lectureSubject = 'Data Structures';
  String today = '2026-10-25';
  String? nextClassDate;
  Completer<Json>? refresh;
  int notificationCount = 0;
  Json appearance = {'mode': 'text', 'image_url': null};
  final emptyDates = <String>{'2026-10-30'};
  final user = <String, dynamic>{
    'id': 7,
    'name': 'Mariam',
    'level': 1,
    'group_number': 1,
    'section': 2,
    'permissions': ['schedule.manage'],
  };
  Json entry(String type, int id, {String? date}) => {
    'id': id,
    'type': type,
    'subject': type == 'lecture' ? lectureSubject : 'Logic Design',
    'instructor': 'Dr. Original Name',
    'location': type == 'lecture' ? 'Hall B2' : 'Lab 3',
    'level': 1,
    'group_number': 1,
    'section_numbers': [2],
    'source_label': type == 'lecture' ? 'Lecture G1' : 'Section S2',
    'day_of_week': DateTime.parse(date ?? today).weekday % 7,
    'start_time': '10:00',
    'end_time': '11:30',
    'starts_at': '${date ?? today}T10:00:00+02:00',
    'ends_at': '${date ?? today}T11:30:00+02:00',
    'is_active': true,
  };
  Json payload(Uri uri) {
    final q = uri.queryParameters;
    final date = q['date'] ?? today;
    final parts = date.split('-').map(int.parse).toList();
    final selected = DateTime.utc(parts[0], parts[1], parts[2]);
    return {
      'date': date,
      'timezone': 'Africa/Cairo',
      'server_time': '${today}T09:40:00+02:00',
      'profile': {'level': 1, 'group_number': 1, 'section': 2},
      'profile_complete': true,
      'day_off': {...appearance},
      'filters': {
        'level': q.containsKey('level') ? int.tryParse(q['level']!) : 1,
        'group': q.containsKey('group') ? int.tryParse(q['group']!) : 1,
        'section': q.containsKey('section') ? int.tryParse(q['section']!) : 2,
        'all': q['all'] == '1',
      },
      'options': {
        'levels': [1, 2],
        'groups': [1, 2],
        'sections': [1, 2, 3, 4, 5, 6],
      },
      // Like the server: the Saturday-to-Friday week of the selected day.
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': selected
                .subtract(
                  Duration(days: (selected.weekday - DateTime.saturday) % 7),
                )
                .add(Duration(days: i))
                .toIso8601String()
                .substring(0, 10),
            'weekday': (i + 6) % 7,
            'is_today': selected
                .subtract(
                  Duration(days: (selected.weekday - DateTime.saturday) % 7),
                )
                .add(Duration(days: i))
                .toIso8601String()
                .startsWith(today),
          },
      ],
      'entries': emptyDates.contains(date)
          ? []
          : [entry('lecture', 1, date: date), entry('section', 2, date: date)],
      'next_lecture': entry('lecture', 1, date: nextClassDate ?? date),
      'next_section': entry('section', 2, date: nextClassDate ?? date),
      'next_class': entry('lecture', 1, date: nextClassDate ?? date),
    };
  }

  Json envelope(String screen, Json data) => {
    'screen': screen,
    'data': data,
    'user': user,
    'features': {'community': true, 'quiz': true},
    'counts': {'notifications': notificationCount, 'inbox': 0},
  };
  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (uri.path == '/schedule' && refresh != null) return refresh!.future;
    return switch (uri.path) {
      '/schedule' => envelope('schedule.index', {'schedule': payload(uri)}),
      '/community' => envelope('community.index', {
        'scheduleSummary': payload(uri),
        'posts': {'data': []},
        'communities': [],
        'featured_events': [],
      }),
      '/menu/notifications' => envelope('notifications.settings', {
        'preferences': {
          'inbox': true,
          'replies': true,
          'reactions': true,
          'announcements': true,
        },
      }),
      '/admin/schedule' => envelope('admin.schedule', {
        'entries': {
          'data': [entry('lecture', 1)],
        },
        'options': object(payload(uri)['options']),
        'filters': {},
      }),
      '/admin/schedule-appearance' => envelope('admin.schedule-appearance', {
        'appearance': {...appearance},
      }),
      '/admin' => envelope('admin.index', {
        'activeSection': 'events',
        'sections': {'events': 'Events'},
        'records': {
          'data': [
            {
              'id': 3,
              'title': 'Original Event',
              'arenas': 'Hall A',
              'event_date': '2026-11-01',
              'image_url': '',
              'link_url': '',
              'details': 'Original event details',
            },
          ],
        },
      }),
      '/notifications' => envelope('notifications.index', {
        'tab': 'all',
        'announcements': [],
        'notifications': {
          'data': [
            {
              'id': 9,
              'type': 'schedule_lecture',
              'schedule_meta': {
                'subject': 'Data Structures',
                'instructor': 'Dr. Original Name',
                'location': 'Hall B2',
                'phase': 'before',
              },
              'created_at': '2026-10-25T09:50:00+02:00',
              'url': '/notifications/9',
            },
          ],
        },
      }),
      '/notifications/9' => envelope('schedule.index', {
        'schedule': payload(uri),
      }),
      '/menu' => envelope('content.menu', {}),
      _ => envelope('', {}),
    };
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    writes.add((method, Uri.parse(path).path, cloneJsonMap(data)));
    if (method == 'PUT' &&
        Uri.parse(path).path == '/admin/schedule-appearance') {
      appearance = {
        'mode': data['mode'],
        'image_url': data['remove_image'] == 1 ? null : appearance['image_url'],
      };
    }
    return {'user': user};
  }

  @override
  Future<void> clearSession() async {}
}

final _previewBoundary = GlobalKey();

Future<NativePageState> _open(
  WidgetTester tester,
  _Api api,
  String path, {
  String language = 'en',
  Size size = const Size(390, 844),
  TargetPlatform? platform,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'appearance.language': language,
    'appearance.liquidGlass': false,
  });
  final settings = AppSettings(language: language);
  await settings.load();
  final navigator = GlobalKey<NavigatorState>();
  final rootNavigator = GlobalKey<NavigatorState>();
  final controller = AppController(
    api,
    settings,
    navigator,
    enablePush: false,
    rootNavigator: rootNavigator,
  )..user = api.user;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    settings.dispose();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _previewBoundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigator,
        locale: Locale(language),
        theme: settings.theme(Brightness.light).copyWith(platform: platform),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: SharedNavigationChrome(
          controller: controller,
          child: Navigator(
            key: navigator,
            observers: [controller.routeObserver],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => NativePage(controller: controller, path: path),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<NativePageState>(find.byType(NativePage));
}

Future<void> _expectDayOffText(
  WidgetTester tester, {
  String message = "Today's a day off, buddy!",
}) async {
  expect(find.byKey(const ValueKey('schedule.dayOff')), findsOneWidget);
  expect(find.byKey(const ValueKey('schedule.dayOff.image')), findsNothing);
  expect(find.text(message), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('schedule.dayOff')),
      matching: find.byType(Text),
    ),
    findsOneWidget,
  );
  expect(find.text('🏖️'), findsNothing);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  final haptics = <Object?>[];
  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'Schedule uses the shared adaptive spinner on $platform, including a short day-off page',
      (tester) async {
        final api = _Api()..today = '2026-10-30';
        final page = await _open(tester, api, '/schedule', platform: platform);
        final scroll = find
            .descendant(
              of: find.byType(WebSchedule),
              matching: find.byType(Scrollable),
            )
            .first;
        expect(
          tester.state<ScrollableState>(scroll).position.maxScrollExtent,
          0,
          reason: 'a short page must still support pull to refresh',
        );
        final initialEpoch = page.c.refreshEpoch;
        await tester.drag(scroll, const Offset(0, 40));
        await tester.pumpAndSettle();
        expect(page.c.refreshEpoch, initialEpoch);
        expect(haptics, isEmpty);

        final pending = api.refresh = Completer<Json>();
        final gesture = await tester.startGesture(tester.getCenter(scroll));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 600));
        await tester.pump(const Duration(milliseconds: 100));
        expect(haptics, isEmpty, reason: 'a held pull has not triggered');
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 200));
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        expect(page.c.refreshEpoch, initialEpoch + 1);
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
          expect(find.byType(RefreshProgressIndicator), findsNothing);
          expect(
            tester
                .widget<CupertinoActivityIndicator>(
                  find.byType(CupertinoActivityIndicator),
                )
                .animating,
            isTrue,
          );
        } else {
          final spinner = find.byType(RefreshProgressIndicator);
          expect(spinner, findsOneWidget);
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(
            tester.widget<RefreshProgressIndicator>(spinner).value,
            isNull,
          );
          final theme = Theme.of(tester.element(spinner));
          expect(theme.progressIndicatorTheme.strokeCap, StrokeCap.round);
          expect(theme.progressIndicatorTheme.color, page.c.settings.accent);
          expect(
            theme.progressIndicatorTheme.refreshBackgroundColor,
            Colors.white,
          );
        }
        api.refresh = null;
        pending.complete(
          api.envelope('schedule.index', {
            'schedule': api.payload(Uri.parse(page.path)),
          }),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Schedule pull retains selected day and filters while refreshing badges and cached days',
    (tester) async {
      final api = _Api();
      final page = await _open(tester, api, '/schedule');
      await tester.tap(find.byKey(const ValueKey('schedule.filter.level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-26')));
      await tester.pumpAndSettle();
      final initialEpoch = page.c.refreshEpoch;
      api.lectureSubject = 'Fresh selected-day subject';
      api.notificationCount = 4;
      final scroll = find
          .descendant(
            of: find.byType(WebSchedule),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scroll, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(Uri.parse(page.path).queryParameters['date'], '2026-10-26');
      expect(Uri.parse(page.path).queryParameters['level'], '2');
      expect(find.text('Fresh selected-day subject'), findsWidgets);
      expect(page.c.counts['notifications'], 4);
      expect(page.c.refreshEpoch, initialEpoch + 1);
      expect(haptics, ['HapticFeedbackType.lightImpact']);

      // Revisiting a previously cached day must not restore its pre-pull data.
      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-30')));
      await tester.pumpAndSettle();
      final beforeRevisit = api.requests.length;
      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-26')));
      await tester.pumpAndSettle();
      expect(api.requests.length, greaterThan(beforeRevisit));
      expect(find.text('Fresh selected-day subject'), findsWidgets);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Home hides an empty weekday even when the next classes are on a later day',
    (tester) async {
      final api = _Api()
        ..today = '2026-10-26'
        ..nextClassDate = '2026-10-27'
        ..emptyDates.add('2026-10-26');
      await _open(tester, api, '/community');
      expect(find.byKey(const ValueKey('schedule.home')), findsNothing);
      expect(find.byKey(const ValueKey('schedule.home.open')), findsNothing);
      expect(find.byKey(const ValueKey('schedule.dayOff')), findsNothing);
      expect(find.byType(ScheduleClassCard), findsNothing);
      expect(find.text('Your Schedule'), findsNothing);
      final gap =
          tester.getTopLeft(find.text('Upcoming Events')).dy -
          tester.getBottomLeft(find.byType(TextField).first).dy;
      expect(
        gap,
        closeTo(48, 1),
        reason: 'a hidden summary leaves no extra card spacing',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final date in ['2026-10-30', '2026-10-31']) {
    testWidgets(
      'Home hides $date and Schedule shows only day-off text even with class rows',
      (tester) async {
        final api = _Api()
          ..today = date
          ..emptyDates.clear();
        final page = await _open(tester, api, '/community');
        expect(
          rows(api.payload(Uri.parse('/community'))['entries']),
          isNotEmpty,
        );
        expect(find.byKey(const ValueKey('schedule.home')), findsNothing);
        expect(find.byKey(const ValueKey('schedule.home.open')), findsNothing);
        expect(find.byType(ScheduleClassCard), findsNothing);
        page.c.open('/schedule');
        await tester.pumpAndSettle();
        await _expectDayOffText(tester);
        expect(find.byType(ScheduleClassCard), findsNothing);
      },
    );
  }

  testWidgets('Home retains its normal schedule card on a class weekday', (
    tester,
  ) async {
    final api = _Api()..today = '2026-10-26';
    await _open(tester, api, '/community');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('schedule.home.open')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('schedule.home')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule.home.open')), findsOneWidget);
    expect(find.byType(ScheduleClassCard), findsNWidgets(2));
    expect(find.byKey(const ValueKey('schedule.dayOff')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a hidden Home summary keeps refreshing and appears when classes return',
    (tester) async {
      final api = _Api()
        ..today = '2026-10-26'
        ..nextClassDate = '2026-10-27'
        ..emptyDates.add('2026-10-26');
      await _open(tester, api, '/community');
      expect(find.byKey(const ValueKey('schedule.home')), findsNothing);
      final before = api.requests
          .where((uri) => uri.path == '/community')
          .length;
      api.emptyDates.remove(api.today);
      api.nextClassDate = null;
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(
        api.requests.where((uri) => uri.path == '/community').length,
        greaterThan(before),
      );
      expect(find.byKey(const ValueKey('schedule.home')), findsOneWidget);
      expect(find.byType(ScheduleClassCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an empty selected weekday defaults to text instead of a future class or static photo',
    (tester) async {
      final api = _Api()
        ..nextClassDate = '2026-10-27'
        ..emptyDates.add('2026-10-26');
      await _open(tester, api, '/schedule');
      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-26')));
      await tester.pumpAndSettle();
      expect(
        api.requests.any((uri) => uri.queryParameters['date'] == '2026-10-26'),
        isTrue,
      );
      await _expectDayOffText(tester, message: "It's a day off, buddy!");
      expect(find.byType(ScheduleClassCard), findsNothing);
      expect(find.text('Data Structures'), findsNothing);
    },
  );

  testWidgets('image mode without a configured URL falls back to text only', (
    tester,
  ) async {
    final api = _Api()
      ..today = '2026-10-30'
      ..appearance = {'mode': 'image', 'image_url': null};
    await _open(tester, api, '/schedule');
    await _expectDayOffText(tester);
  });

  testWidgets(
    'configured image mode uses cached media, text while loading, and only the loaded image',
    (tester) async {
      const path = '/profile-media/day-off-configured.png';
      final stream = _configuredImage(path);
      final api = _Api()
        ..today = '2026-10-30'
        ..appearance = {'mode': 'image', 'image_url': path};
      await _open(tester, api, '/schedule');
      final photo = find.byKey(const ValueKey('schedule.dayOff.image'));
      final image = tester.widget<Image>(photo);
      expect(
        image.image,
        isA<CachedNetworkImage>()
            .having(
              (p) => p.url,
              'configured URL',
              'https://schedule.example.test$path',
            )
            .having((p) => p.width, 'decode width', 220)
            .having((p) => p.cover, 'keep image proportions', isFalse),
      );
      expect(find.text("Today's a day off, buddy!"), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('schedule.dayOff'))).height,
        lessThan(245),
        reason:
            'loading keeps the text fallback, without an empty image-sized gap',
      );
      await _showConfiguredImage(tester, stream);
      expect(find.text("Today's a day off, buddy!"), findsNothing);
      final raw = find.descendant(of: photo, matching: find.byType(RawImage));
      expect(tester.widget<RawImage>(raw).image, isNotNull);
      expect(tester.getSize(photo).width, lessThanOrEqualTo(220));
      expect(tester.getSize(photo).height, lessThanOrEqualTo(245));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed configured image displays only the localized day-off text',
    (tester) async {
      const path = '/profile-media/day-off-missing.png';
      final controlled = _configuredImage(path);
      final api = _Api()
        ..today = '2026-10-30'
        ..appearance = {'mode': 'image', 'image_url': path};
      await _open(tester, api, '/schedule', language: 'ar');
      final photo = find.byKey(const ValueKey('schedule.dayOff.image'));
      final image = tester.widget<Image>(photo);
      final failures = <Object>[];
      final stream = image.image.resolve(
        createLocalImageConfiguration(tester.element(photo)),
      );
      final listener = ImageStreamListener(
        (_, _) {},
        onError: (error, _) => failures.add(error),
      );
      stream.addListener(listener);
      addTearDown(() => stream.removeListener(listener));
      controlled.fail();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(failures, isNotEmpty);
      expect(find.text('النهارده إجازة يا صاحبي'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('schedule.dayOff')),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['student', 'admin']) {
    testWidgets(
      '$role cannot open or save native day-off appearance settings',
      (tester) async {
        final api = _Api();
        api.user['role'] = role;
        final page = await _open(tester, api, '/admin/schedule');
        expect(
          find.byKey(const ValueKey('schedule.admin.appearance')),
          findsNothing,
        );
        page.c.open('/admin/schedule-appearance');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('schedule.appearance.mode')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('schedule.appearance.save')),
          findsNothing,
        );
        expect(
          find.text('Only the super admin can change the day off appearance.'),
          findsOneWidget,
        );
        expect(api.writes, isEmpty);
      },
    );
  }

  testWidgets(
    'super admin sees the appearance link and cannot save image mode without an image',
    (tester) async {
      final api = _Api();
      api.user['role'] = 'super_admin';
      await _open(tester, api, '/admin/schedule');
      await tester.tap(find.byKey(const ValueKey('schedule.admin.appearance')));
      await tester.pumpAndSettle();
      expect(
        api.requests.any((uri) => uri.path == '/admin/schedule-appearance'),
        isTrue,
      );
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byKey(const ValueKey('schedule.appearance.mode')),
            )
            .selected,
        {'text'},
      );
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('schedule.appearance.choose-image')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule.appearance.save')),
      );
      await tester.tap(find.byKey(const ValueKey('schedule.appearance.save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose an image first, or select Text only.'),
        findsOneWidget,
      );
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['image', 'text']) {
    testWidgets(
      'super admin saves $mode mode without deleting an existing image',
      (tester) async {
        const url = '/profile-media/appearance-existing.png';
        final api = _Api()..appearance = {'mode': 'image', 'image_url': url};
        api.user['role'] = 'super_admin';
        await _open(tester, api, '/admin/schedule-appearance');
        if (mode == 'text') {
          await tester.tap(find.text('Text only'));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('schedule.appearance.save')),
        );
        await tester.tap(
          find.byKey(const ValueKey('schedule.appearance.save')),
        );
        await tester.pumpAndSettle();
        final saved = api.writes.single;
        expect(saved.$1, 'PUT');
        expect(saved.$2, '/admin/schedule-appearance');
        expect(saved.$3, {'mode': mode});
        expect(api.appearance['image_url'], url);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'explicit Remove image switches to text and sends the removal flag',
    (tester) async {
      final api = _Api()
        ..appearance = {
          'mode': 'image',
          'image_url': '/profile-media/remove-this.png',
        };
      api.user['role'] = 'super_admin';
      await _open(tester, api, '/admin/schedule-appearance');
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule.appearance.remove-image')),
      );
      await tester.tap(
        find.byKey(const ValueKey('schedule.appearance.remove-image')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byKey(const ValueKey('schedule.appearance.mode')),
            )
            .selected,
        {'text'},
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('schedule.appearance.save')),
      );
      await tester.tap(find.byKey(const ValueKey('schedule.appearance.save')));
      await tester.pumpAndSettle();
      expect(api.writes.single.$3, {'mode': 'text', 'remove_image': 1});
      expect(api.appearance['image_url'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visible schedules refresh from the server every minute', (
    tester,
  ) async {
    final api = _Api();
    await _open(tester, api, '/schedule');
    api.lectureSubject = 'Updated Original Subject';
    final before = api.requests.length;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(api.requests.length, greaterThan(before));
    expect(find.text('Updated Original Subject'), findsWidgets);
    expect(haptics, isEmpty, reason: 'automatic refresh has no user gesture');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schedule and Home visual references',
    (tester) async {
      final output = Directory(
        const String.fromEnvironment(
          'SCHEDULE_CAPTURE_DIR',
          defaultValue: '../.local/flutter-schedule-previews',
        ),
      );
      output.createSync(recursive: true);
      await tester.runAsync(() async {
        final arabic = FontLoader('SF Arabic');
        for (final weight in ['Regular', 'Medium', 'Semibold', 'Bold']) {
          arabic.addFont(rootBundle.load('assets/fonts/SFArabic-$weight.ttf'));
        }
        await arabic.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        const fonts = String.fromEnvironment('SCHEDULE_REVIEW_FONTS');
        if (fonts.isNotEmpty) {
          final latin = FontLoader('Roboto');
          for (final weight in ['Regular', 'Medium']) {
            final bytes = File('$fonts/Roboto-$weight.ttf').readAsBytesSync();
            latin.addFont(Future.value(ByteData.sublistView(bytes)));
          }
          await latin.load();
        }
      });
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final boundary =
            _previewBoundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage(pixelRatio: 2);
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          File(
            '${output.path}/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          screenshot.dispose();
        });
      }

      for (final language in ['ar', 'en']) {
        await _open(tester, _Api(), '/schedule', language: language);
        await capture('schedule-$language');
        await tester.drag(find.byType(ListView).first, const Offset(0, -360));
        await capture('schedule-$language-timeline');
        await _open(tester, _Api(), '/community', language: language);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('schedule.home.open')),
          260,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, 350));
        await capture('home-schedule-$language');
      }
      await _open(
        tester,
        _Api()..today = '2026-10-30',
        '/schedule',
        language: 'ar',
      );
      await Scrollable.ensureVisible(
        find.byKey(const ValueKey('schedule.dayOff')).evaluate().single,
        alignment: .25,
      );
      await _expectDayOffText(tester, message: 'النهارده إجازة يا صاحبي');
      await capture('schedule-day-off-text-ar');
      const configuredImage = '/profile-media/capture-configured.png';
      final configuredStream = _configuredImage(configuredImage);
      await _open(
        tester,
        _Api()
          ..today = '2026-10-30'
          ..appearance = {'mode': 'image', 'image_url': configuredImage},
        '/schedule',
        language: 'ar',
      );
      await _showConfiguredImage(tester, configuredStream);
      await Scrollable.ensureVisible(
        find.byKey(const ValueKey('schedule.dayOff')).evaluate().single,
        alignment: .25,
      );
      await capture('schedule-day-off-configured-ar');
      await _open(
        tester,
        _Api()
          ..today = '2026-10-26'
          ..nextClassDate = '2026-10-27'
          ..emptyDates.add('2026-10-26'),
        '/community',
        language: 'ar',
      );
      expect(find.byKey(const ValueKey('schedule.home')), findsNothing);
      await capture('home-day-off-ar');
    },
    skip: !const bool.fromEnvironment('CAPTURE_SCHEDULE'),
  );

  testWidgets(
    'schedule switches days in place with cached days, 12-hour times and a day-off message',
    (tester) async {
      final api = _Api();
      final page = await _open(tester, api, '/schedule');
      expect(find.byType(WebSchedule), findsOneWidget);
      for (final removed in [
        'schedule.pickDate',
        'schedule.previousDay',
        'schedule.nextDay',
        'schedule.showAll',
        'schedule.profileFilters',
      ]) {
        expect(find.byKey(ValueKey(removed)), findsNothing);
      }
      expect(find.textContaining('all in one place'), findsNothing);
      expect(find.text('10:00 AM'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('schedule.filter.level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Level 2').last);
      await tester.pumpAndSettle();
      expect(api.requests.last.queryParameters['level'], '2');
      final path = page.path;

      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-26')));
      await tester.pumpAndSettle();
      final monday = api.requests.lastWhere(
        (uri) => uri.queryParameters['date'] == '2026-10-26',
      );
      expect(monday.queryParameters['level'], '2');
      expect(page.path, path, reason: 'days switch in place, not as a visit');

      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-30')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule.dayOff')), findsOneWidget);
      expect(find.text("It's a day off, buddy!"), findsOneWidget);
      expect(find.byType(ScheduleClassCard), findsNothing);

      final before = api.requests.length;
      await tester.tap(find.byKey(const ValueKey('schedule.day.2026-10-26')));
      await tester.pumpAndSettle();
      expect(
        api.requests.length,
        before,
        reason: 'a day seen moments ago is reused',
      );
      expect(find.byKey(const ValueKey('schedule.dayOff')), findsNothing);
      expect(page.c.user!['level'], 1);
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('next lecture and section cards always share one height', (
    tester,
  ) async {
    // A long subject makes the lecture card's content taller than the section's.
    final api = _Api()
      ..lectureSubject =
          'Probabilty and Statistics and Statistical Analysis (Advanced)';
    await _open(tester, api, '/schedule');
    final lecture = tester.getSize(
      find.byKey(const ValueKey('schedule.next.lecture')),
    );
    final section = tester.getSize(
      find.byKey(const ValueKey('schedule.next.section')),
    );
    expect(lecture.height, section.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping the day card moves to the next and previous day', (
    tester,
  ) async {
    final api = _Api();
    await _open(tester, api, '/schedule');
    await tester.fling(
      find.byKey(const ValueKey('schedule.swipe')),
      const Offset(-300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(
      api.requests.map((uri) => uri.queryParameters['date']),
      contains('2026-10-26'),
    );
    expect(find.text('Today'), findsNothing);
    await tester.fling(
      find.byKey(const ValueKey('schedule.swipe')),
      const Offset(300, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Arabic schedule keeps original academic strings on a small phone',
    (tester) async {
      final api = _Api();
      await _open(
        tester,
        api,
        '/schedule',
        language: 'ar',
        size: const Size(360, 800),
      );
      expect(find.text('الجدول'), findsWidgets);
      expect(find.text('صباح الخير'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Dr. Original Name').first,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Data Structures'), findsWidgets);
      expect(find.text('Dr. Original Name'), findsWidgets);
      expect(find.textContaining('Hall B2'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home summary opens schedule and dock replaces quiz while menu keeps it',
    (tester) async {
      final api = _Api();
      final page = await _open(tester, api, '/community');
      expect(find.byKey(const ValueKey('dock.schedule')), findsOneWidget);
      expect(find.byKey(const ValueKey('dock.quiz')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('schedule.home.open')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('schedule.home.open')));
      await tester.pumpAndSettle();
      expect(api.requests.any((uri) => uri.path == '/schedule'), isTrue);
      page.c.open('/menu');
      await tester.pumpAndSettle();
      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lecture and section notifications default on and can be changed independently',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/menu/notifications');
      final lecture = find.byWidgetPredicate(
        (widget) => widget is WebSwitch && widget.label == 'Lecture reminders',
      );
      final section = find.byWidgetPredicate(
        (widget) => widget is WebSwitch && widget.label == 'Section reminders',
      );
      await tester.scrollUntilVisible(
        lecture,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(tester.widget<WebSwitch>(lecture).value, isTrue);
      expect(tester.widget<WebSwitch>(section).value, isTrue);
      await tester.tap(lecture);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      final categories = api.writes.last.$3['categories'] as List;
      expect(categories, isNot(contains('schedule_lectures')));
      expect(categories, contains('schedule_sections'));
      expect(categories, contains('inbox'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authorized schedule editor preserves original academic fields and sends update',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/admin/schedule');
      await tester.tap(find.byKey(const ValueKey('schedule.admin.edit.1')));
      await tester.pumpAndSettle();
      expect(find.text('Data Structures'), findsWidgets);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(api.writes.last.$1, 'PUT');
      expect(api.writes.last.$2, '/admin/schedule/1');
      expect(api.writes.last.$3['subject'], 'Data Structures');
      expect(api.writes.last.$3['instructor'], 'Dr. Original Name');
      expect(api.writes.last.$3['section_numbers'], ['2']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native event editor offers image upload and preserves information in PATCH updates',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/admin?section=events');
      await tester.scrollUntilVisible(
        find.text('Edit event'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Edit event'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('admin.image.image_upload')),
        findsOneWidget,
      );
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.controller?.text == 'Original Event',
      );
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Updated Event');
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(api.writes.last.$1, 'PATCH');
      expect(api.writes.last.$2, '/admin/events/3');
      expect(api.writes.last.$3['title'], 'Updated Event');
      expect(api.writes.last.$3['arenas'], 'Hall A');
      expect(api.writes.last.$3.containsKey('image_upload'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'schedule notifications translate only UI copy and use the read-marking URL',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/notifications', language: 'ar');
      final reminder = find.textContaining(
        'تذكير بالمحاضرة',
        findRichText: true,
      );
      await tester.scrollUntilVisible(
        reminder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Data Structures'), findsOneWidget);
      expect(find.textContaining('Dr. Original Name'), findsOneWidget);
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      expect(api.requests.any((uri) => uri.path == '/notifications/9'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
