import 'dart:async';
import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TabRequest {
  _TabRequest(this.uri);
  final Uri uri;
  final result = Completer<Json>();
}

class _TabsApi extends MobileApi {
  _TabsApi(this.inbox);
  final bool inbox;
  @override
  Uri get baseUri => Uri.parse('https://tabs.example.test');
  Json user = {'id': 7, 'name': 'Mariam', 'role': 'student', 'permissions': []};
  final gets = <Uri>[];
  final waiting = <_TabRequest>[];
  bool first = true;
  int inboxVisits = 0;

  Json response(Uri uri, {int count = 8, bool initial = false}) {
    final tab = uri.queryParameters['tab'] ?? (inbox ? 'inbox' : 'all');
    final locale = uri.queryParameters['lang'] ?? 'en';
    return {
      'user': {...user},
      'screen': inbox ? 'ask.inbox' : 'notifications.index',
      'canonical_url': uri.toString(),
      'features': {'community': true},
      'counts': {'inbox': initial && inbox ? 2 : 0, 'notifications': 0},
      'data': {
        'tab': tab,
        if (inbox) ...{
          'unreadInboxCounts': {'inbox': 0, 'sent': initial ? 2 : 0},
          'unreadQuestionIds': initial ? {'1': 0} : {},
          'questions': {
            'data': [
              for (var i = 0; i < count; i++)
                {
                  'id': i + 1,
                  'question': '$locale/${user['id']}/$tab/question$i',
                  'sender': {'id': 11, 'name': 'Sender'},
                  'recipient': {'id': 12, 'name': 'Recipient'},
                  'created_at': '2026-10-23T00:00:00Z',
                },
            ],
          },
        } else ...{
          'canAddAnnouncement': false,
          'readAnnouncementIds': {},
          'notifications': {
            'data': [
              for (var i = 0; i < count; i++)
                {
                  'id': i + 1,
                  'type': tab == 'likes' ? 'post_like' : 'post_reply',
                  'actor': {'id': 11, 'name': 'Actor'},
                  'post': {'content': '$locale/${user['id']}/$tab/notice$i'},
                  'read_at': null,
                  'created_at': '2026-10-23T00:00:00Z',
                  'url': '/notifications/${i + 1}',
                },
            ],
          },
        },
      },
    };
  }

  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    gets.add(uri);
    if (uri.path == '/inbox') inboxVisits++;
    if (first) {
      first = false;
      return response(uri, initial: true, count: inbox ? 25 : 8);
    }
    final request = _TabRequest(uri);
    waiting.add(request);
    return request.result.future;
  }

  void complete(int index, {int count = 8}) {
    final request = waiting[index];
    request.result.complete(response(request.uri, count: count));
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      throw StateError('Tab tests never write to a server.');
  @override
  Future<void> clearSession() async {}
}

Future<(NativePageState, AppController)> _mount(
  WidgetTester tester,
  _TabsApi api,
) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings(language: 'en');
  await settings.load();
  final navigator = GlobalKey<NavigatorState>();
  final controller = AppController(api, settings, navigator, enablePush: false)
    ..user = api.user;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    settings.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: settings.theme(Brightness.light),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: NativePage(
        controller: controller,
        path: api.inbox ? '/inbox' : '/notifications',
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (tester.state<NativePageState>(find.byType(NativePage)), controller);
}

Finder _tab(bool inbox, String tab) => find.byKey(
  ValueKey('activity.${inbox ? 'inbox' : 'notifications'}.tab.$tab'),
);
double _offset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('activity.list.motion')))
    .transform
    .storage[12];

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
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final inbox in [true, false]) {
    testWidgets(
      '${inbox ? 'inbox' : 'notifications'} pull vibrates once and automatic refresh stays silent',
      (tester) async {
        final api = _TabsApi(inbox);
        final (page, controller) = await _mount(tester, api);
        final scroll = find.byKey(
          ValueKey('activity.${inbox ? 'inbox' : 'notifications'}.scroll'),
        );
        final initialEpoch = controller.refreshEpoch;
        final gesture = await tester.startGesture(tester.getCenter(scroll));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 700));
        await tester.pump(const Duration(milliseconds: 100));
        expect(haptics, isEmpty);
        expect(api.waiting, isEmpty);
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        expect(controller.refreshEpoch, initialEpoch + 1);
        expect(api.waiting, hasLength(1));
        api.complete(0);
        await tester.pumpAndSettle();

        // The same loader runs after a resume/cache invalidation without a pull.
        final beforeAutomatic = api.waiting.length;
        controller.invalidatePages();
        controller.notifyListeners();
        await tester.pump();
        await tester.pump();
        expect(api.waiting.length, greaterThan(beforeAutomatic));
        api.complete(beforeAutomatic);
        await tester.pumpAndSettle();
        expect(haptics, ['HapticFeedbackType.lightImpact']);
        expect(page.data['tab'], inbox ? 'inbox' : 'all');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'inbox tab retains shell during GET and slides only incoming rows by 48 pixels over 260 ms',
    (tester) async {
      final api = _TabsApi(true);
      final (page, controller) = await _mount(tester, api);
      final tabPosition = tester.getTopLeft(_tab(true, 'inbox'));
      await tester.tap(_tab(true, 'sent'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(page.loading, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const ValueKey('activity.list.skeleton')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(_tab(true, 'inbox')), tabPosition);
      api.complete(0, count: 2);
      await tester.pump();
      expect(_offset(tester), closeTo(48, .01));
      await tester.pump(const Duration(milliseconds: 130));
      expect(_offset(tester), inExclusiveRange(0, 48));
      await tester.pump(const Duration(milliseconds: 130));
      expect(_offset(tester), closeTo(0, .01));
      expect(page.data['tab'], 'sent');
      expect(controller.counts['inbox'], 0);
      expect(object(page.data['unreadInboxCounts'])['sent'], 0);
      expect(tester.getTopLeft(_tab(true, 'inbox')), tabPosition);
    },
  );

  testWidgets(
    'cached inbox tab is instant while revalidation preserves mark-read and scroll',
    (tester) async {
      final api = _TabsApi(true);
      final (page, _) = await _mount(tester, api);
      final selectSent = tester.widget<InkWell>(_tab(true, 'sent')).onTap!;
      final selectInbox = tester.widget<InkWell>(_tab(true, 'inbox')).onTap!;
      final scroll = tester
          .widget<ListView>(find.byKey(const ValueKey('activity.inbox.scroll')))
          .controller!;
      scroll.jumpTo(350);
      selectSent();
      await tester.pump();
      api.complete(0, count: 1);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(350, .01));
      selectInbox();
      await tester.pump();
      expect(page.data['tab'], 'inbox');
      expect(
        find.byKey(const ValueKey('activity.list.skeleton')),
        findsNothing,
      );
      expect(api.inboxVisits, 3);
      expect(scroll.offset, closeTo(350, .01));
      api.complete(1, count: 25);
      await tester.pumpAndSettle();
      expect(object(page.data['unreadQuestionIds']), isEmpty);
      expect(object(page.data['unreadInboxCounts'])['sent'], 0);
    },
  );

  testWidgets(
    'notifications cache all/replies/likes and ignore a superseded tab response',
    (tester) async {
      final api = _TabsApi(false);
      final (page, _) = await _mount(tester, api);
      await tester.tap(_tab(false, 'replies'));
      await tester.pump();
      await tester.tap(_tab(false, 'likes'));
      await tester.pump();
      api.complete(0);
      await tester.pump();
      expect(page.data['tab'], 'all');
      api.complete(1, count: 2);
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'likes');
      await tester.tap(_tab(false, 'all'));
      await tester.pump();
      expect(page.data['tab'], 'all');
      expect(_offset(tester), closeTo(-48, .01));
      await tester.pumpAndSettle();
      await tester.tap(_tab(false, 'likes'));
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'likes');
      expect(api.gets, hasLength(3));
    },
  );

  testWidgets(
    'failed tab request restores previous data and permits retry without a page spinner',
    (tester) async {
      final api = _TabsApi(false);
      final (page, _) = await _mount(tester, api);
      await tester.tap(_tab(false, 'replies'));
      await tester.pump(const Duration(milliseconds: 100));
      api.waiting.single.result.completeError(
        const ApiFailure('Offline tab request.'),
      );
      await tester.pumpAndSettle();
      expect(page.loading, isFalse);
      expect(page.data['tab'], 'all');
      expect(find.text('Offline tab request.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      api.complete(1, count: 1);
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'replies');
      expect(find.text('Offline tab request.'), findsNothing);
    },
  );

  testWidgets(
    'a server mutation invalidates cached tabs and refreshes current rows',
    (tester) async {
      final api = _TabsApi(false);
      final (page, controller) = await _mount(tester, api);
      await tester.tap(_tab(false, 'likes'));
      await tester.pump();
      api.complete(0, count: 2);
      await tester.pumpAndSettle();
      controller.invalidatePages();
      controller.notifyListeners();
      await tester.pump();
      expect(api.waiting, hasLength(2));
      api.complete(1, count: 1);
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'likes');
      await tester.tap(_tab(false, 'all'));
      await tester.pump();
      expect(api.waiting, hasLength(3));
      api.complete(2, count: 1);
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'all');
    },
  );

  testWidgets(
    'viewer and locale changes discard cached authorized tabs and stale responses',
    (tester) async {
      final api = _TabsApi(false);
      final (page, controller) = await _mount(tester, api);
      await tester.tap(_tab(false, 'likes'));
      await tester.pump();
      api.complete(0, count: 1);
      await tester.pumpAndSettle();
      api.user = {
        'id': 9,
        'name': 'Different viewer',
        'role': 'student',
        'permissions': [],
      };
      controller.user = api.user;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('en/7/likes/notice0'), findsNothing);
      expect(
        find.byKey(const ValueKey('activity.list.skeleton')),
        findsOneWidget,
      );
      api.complete(1, count: 1);
      await tester.pumpAndSettle();
      expect(find.text('en/9/likes/notice0'), findsOneWidget);
      await tester.tap(_tab(false, 'all'));
      await tester.pump();
      expect(api.gets, hasLength(4));
      controller.settings.setLanguage('ar');
      await tester.pump();
      expect(api.waiting.last.uri.queryParameters['lang'], 'ar');
      api.complete(2, count: 1);
      await tester.pump();
      expect(find.text('en/9/all/notice0'), findsNothing);
      api.complete(3, count: 1);
      await tester.pumpAndSettle();
      expect(page.data['tab'], 'all');
      expect(find.text('ar/9/all/notice0'), findsOneWidget);
      await tester.tap(_tab(false, 'replies'));
      await tester.pump();
      api.complete(4, count: 1);
      await tester.pump();
      expect(_offset(tester), closeTo(-48, .01));
      await tester.pumpAndSettle();
    },
  );
}
