import 'package:elbench/api.dart';
import 'package:elbench/image_cache.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingImage extends ImageStreamCompleter {}

class _SenderApi extends MobileApi {
  _SenderApi(this.screen);
  final String screen;
  String type = 'post_like';
  String tab = 'inbox';
  Json sender = {'id': 11, 'name': 'Dr. Mona'};
  final recipient = <String, dynamic>{'id': 12, 'name': 'Recipient'};
  final user = <String, dynamic>{'id': 7, 'name': 'Mariam', 'role': 'student'};

  @override
  Uri get baseUri => Uri.parse('https://sender.example.test');

  Json get notice => {
    'id': 1,
    'author': sender,
    'body': 'Community update body',
    'created_at': '2026-10-25T10:00:00Z',
  };

  @override
  Future<Json> get(String path) async => {
    'screen': screen,
    'user': user,
    'features': {'community': true},
    'counts': {'notifications': 0, 'inbox': 0},
    'data': switch (screen) {
      'notifications.index' => {
        'tab': 'all',
        'announcements': [],
        'notifications': {
          'data': [
            {
              'id': 1,
              'type': type,
              'actor': sender,
              'url': '/notifications/1',
              'post': {'content': 'Notification body'},
              'community_notice': {
                'title': 'Notification body',
                'community': {'name': 'Data Structures'},
              },
              'created_at': '2026-10-25T10:00:00Z',
            },
          ],
        },
      },
      'ask.inbox' => {
        'tab': tab,
        'questions': {
          'data': [
            {
              'id': 1,
              'question': 'Question body',
              'sender': sender,
              'recipient': recipient,
              'answered_at': '2026-10-25T11:00:00Z',
              'created_at': '2026-10-25T10:00:00Z',
            },
          ],
        },
      },
      _ => {
        'community': {'id': 4, 'name': 'Data Structures', 'description': 'DS'},
        'community_id': 4,
        'questions': [],
        'notices': [notice],
        'notice_unread': 0,
        'unread': 0,
      },
    },
  };

  @override
  Future<void> clearSession() async {}

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};
}

class _Controller extends AppController {
  _Controller(super.api, super.settings, super.navigator)
    : super(enablePush: false);
  final opened = <String>[];

  @override
  void open(
    String path, {
    int tabDirection = 0,
    PageRoute<dynamic>? replacing,
    Json? seed,
  }) => opened.add(path);
}

Future<_Controller> _mount(WidgetTester tester, _SenderApi api) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings(language: 'en');
  await settings.load();
  final navigator = GlobalKey<NavigatorState>();
  final controller = _Controller(api, settings, navigator)..user = api.user;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    settings.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  final avatar = api.sender['avatar_url'];
  if (avatar != null) {
    for (final size in [36, 40, 44]) {
      PaintingBinding.instance.imageCache.putIfAbsent(
        CachedNetworkImage(api.media(avatar), width: size, height: size),
        _PendingImage.new,
      );
    }
  }
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: settings.theme(Brightness.light),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: NativePage(
        controller: controller,
        path: switch (api.screen) {
          'notifications.index' => '/notifications',
          'ask.inbox' => '/inbox',
          'community.forum' => '/forum?community_id=4',
          _ => '/community/4/notifications',
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  for (final type in [
    'post_like',
    'comment_like',
    'post_reply',
    'question_answer',
    'answer_received',
    'community_notice',
  ]) {
    testWidgets(
      '$type sender opens profile while body opens the notification',
      (tester) async {
        final api = _SenderApi('notifications.index')..type = type;
        final controller = await _mount(tester, api);
        final avatar = find.byKey(const ValueKey('notification.avatar.1'));
        final size = tester.getSize(avatar);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        await tester.tap(avatar);
        await tester.pump();
        expect(controller.opened, ['/users/11']);
        await tester.tap(find.textContaining('Notification body'));
        await tester.pump();
        expect(controller.opened, ['/users/11', '/notifications/1']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sender in [
    <String, dynamic>{'name': 'Deleted user'},
    <String, dynamic>{'id': 11, 'name': 'Anonymous', 'is_anonymous': true},
  ]) {
    testWidgets('${sender['name']} avatar never navigates', (tester) async {
      final api = _SenderApi('notifications.index')..sender = sender;
      final controller = await _mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('notification.avatar.1')));
      await tester.pump();
      expect(controller.opened, isEmpty);
      await tester.tap(find.text('Notification body'));
      expect(controller.opened, ['/notifications/1']);
    });
  }

  for (final tab in ['inbox', 'sent']) {
    testWidgets('$tab question sender has an independent profile action', (
      tester,
    ) async {
      final api = _SenderApi('ask.inbox')..tab = tab;
      final controller = await _mount(tester, api);
      await tester.tap(find.byKey(const ValueKey('inbox.avatar.1')));
      expect(controller.opened, [tab == 'inbox' ? '/users/11' : '/users/12']);
      await tester.tap(find.text('View question'));
      expect(controller.opened.last, '/ask/1');
      expect(tester.takeException(), isNull);
    });
  }

  for (final screen in ['community.forum', 'community.notifications']) {
    testWidgets('$screen shows the sender picture and opens their profile', (
      tester,
    ) async {
      final api = _SenderApi(screen)
        ..sender = {
          'id': 11,
          'name': 'Dr. Mona',
          'avatar_url': '/profile-media/mona.webp',
          'profile_url': '/users/11',
        };
      final controller = await _mount(tester, api);
      final avatar = find.byKey(const ValueKey('notice.avatar.1'));
      await tester.ensureVisible(avatar);
      await tester.pumpAndSettle();
      final circle = tester.widget<CircleAvatar>(
        find.descendant(of: avatar, matching: find.byType(CircleAvatar)),
      );
      expect(circle.backgroundImage, isA<CachedNetworkImage>());
      expect(
        (circle.backgroundImage! as CachedNetworkImage).url,
        'https://sender.example.test/profile-media/mona.webp',
      );
      await tester.tap(avatar);
      expect(controller.opened, ['/users/11']);
      expect(find.text('Community update body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
