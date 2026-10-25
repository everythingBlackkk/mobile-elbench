import 'dart:async';

import 'package:elbench/api.dart';
import 'package:elbench/app_links.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MobileApi {
  @override
  Uri get baseUri => Uri.parse(productionOrigin);
  bool signedIn = true;
  Completer<void>? sessionGate;
  final requests = <String>[];
  Json get viewer => {'id': 7, 'name': 'Mariam', 'role': 'student'};

  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri.toString());
    if (uri.path == '/mobile/session') await sessionGate?.future;
    final profile = uri.path.startsWith('/users/');
    final post = uri.path.startsWith('/community/posts/');
    return {
      'user': signedIn ? viewer : null,
      'features': {'community': true},
      'counts': {'notifications': 0, 'inbox': 0},
      'screen': profile
          ? 'profile.user'
          : post
          ? 'community.post'
          : 'community.index',
      'data': profile
          ? {
              'profile_user': {
                'id': int.parse(uri.pathSegments.last),
                'name': 'Linked person',
              },
              'skills': [],
              'profile_posts': [],
            }
          : post
          ? {
              'post': {
                'id': int.parse(uri.pathSegments.last),
                'author': viewer,
                'content': 'Linked post body',
              },
              'comments': [],
            }
          : {'communities': [], 'posts': []},
    };
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    if (Uri.parse(path).path == '/login') signedIn = true;
    return {'user': signedIn ? viewer : null};
  }

  @override
  Future<void> clearSession() async => signedIn = false;
}

Future<void> _mount(WidgetTester tester, _Api api) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'appearance.language': 'en',
    'appearance.liquidGlass': false,
  });
  final settings = AppSettings();
  await settings.load();
  await tester.pumpWidget(
    ElBenchApp(
      api: api,
      settings: settings,
      enablePush: false,
      enableLaunchExperience: false,
    ),
  );
}

NativePageState _page(WidgetTester tester) =>
    tester.stateList<NativePageState>(find.byType(NativePage)).last;

void main() {
  test('trusted content links preserve their destination and comment focus', () {
    for (final host in [
      'elbench.com',
      'www.elbench.com',
      'sahbak.site',
      'www.sahbak.site',
    ]) {
      expect(appLinkPath('https://$host/users/42'), '/users/42');
      expect(
        appLinkPath(
          'https://$host/community/posts/81?focus_comment=9&thread=2#comment-9',
        ),
        '/community/posts/81?focus_comment=9&thread=2#comment-9',
      );
    }
    expect(appLinkPath('/users/42/'), '/users/42');
    expect(appLinkPath('elbench://users/42'), '/users/42');
    expect(appLinkPath('elbench:///community/posts/81'), '/community/posts/81');
    expect(appLinkPath('elbench://community/4'), '/forum?community_id=4');
    expect(appLinkPath('https://elbench.com/ask/5'), '/ask/5');
    expect(
      appLinkPath('https://elbench.com/forum?community_id=4'),
      '/forum?community_id=4',
    );
    expect(
      appLinkPath('https://elbench.com/question?id=12'),
      '/question?id=12',
    );
    expect(
      appLinkPath('https://elbench.com/notifications/announcements/6'),
      '/notifications/announcements/6',
    );
    expect(
      appLinkPath('https://elbench.com/announcements/6'),
      '/notifications/announcements/6',
    );
    expect(
      appLinkPath('https://elbench.com/community/4/notifications'),
      '/community/4/notifications',
    );
    expect(
      appLinkPath('https://elbench.com/community/materials/8'),
      '/community/materials/8',
    );
    expect(
      appLinkPath(
        'https://elbench.com/users/42?redirect=https%3A%2F%2Fevil.test&tab=asks',
      ),
      '/users/42?tab=asks',
    );
  });

  test(
    'external, credentialed, malformed and account-management links are rejected',
    () {
      for (final input in [
        '',
        '/',
        'https://example.com/users/42',
        'https://elbench.com.evil.test/users/42',
        'https://elbench.com@evil.test/users/42',
        'https://name:secret@elbench.com/users/42',
        'https://elbench.com:8443/users/42',
        'http://elbench.com/users/42',
        '//elbench.com/users/42',
        'javascript:alert(1)',
        'file:///users/42',
        'elbench://evil.test/users/42',
        'elbench://name@users/42',
        'elbench:users/42',
        'https://elbench.com/profile/edit',
        'https://elbench.com/logout',
        'https://elbench.com/admin',
        'https://elbench.com/users/0',
        'https://elbench.com/users/-1',
        'https://elbench.com/users/42/reports',
        'https://elbench.com/users/42/../../admin',
        'https://elbench.com/users/%2F42',
        'https://elbench.com/users%2f42',
        'https://elbench.com/users/%2e%2e/admin',
        'https://elbench.com/users/7?lang=%FF',
        'https://elbench.com/users/7?x=%ZZ',
        'https://elbench.com/users/7?x=%',
        'https://elbench.com/users/7?x=%A',
        'https://elbench.com/users/7?x=%C0%AF',
        'https://elbench.com/users/7?x=%00',
        'https://elbench.com/users/7?lang=%0Aen',
        'https://elbench.com/users/7?x=%5C',
        'https://elbench.com/users/7#comment-1%0D',
        'https://elbench.com/users/42\n',
        'https://elbench.com/\\users/42',
        'https://elbench.com/forum?community_id=4&community_id=9',
        'https://elbench.com/question?id=bad',
      ]) {
        expect(appLinkPath(input), isNull, reason: input);
      }
    },
  );

  testWidgets('cold start waits for the session and opens the exact profile', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue =
        'https://elbench.com/users/42';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    final api = _Api()..sessionGate = Completer<void>();
    await _mount(tester, api);
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.requests.where((path) => path.startsWith('/users/')), isEmpty);
    expect(tester.takeException(), isNull);

    api.sessionGate!.complete();
    await tester.pumpAndSettle();

    expect(_page(tester).path, '/users/42');
    expect(find.text('Linked person'), findsWidgets);
    expect(
      api.requests.where((path) => path.startsWith('/users/42?')),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'warm links reach a post and duplicate delivery keeps one route',
    (tester) async {
      final api = _Api();
      await _mount(tester, api);
      await tester.pumpAndSettle();

      await tester.binding.handlePushRoute(
        'https://www.elbench.com/community/posts/81?focus_comment=9#comment-9',
      );
      await tester.pumpAndSettle();
      final linkedPage = _page(tester);
      expect(linkedPage.path, '/community/posts/81?focus_comment=9#comment-9');
      expect(
        find.textContaining('Linked post body', findRichText: true),
        findsWidgets,
      );
      final observer =
          tester.state(find.byType(ElBenchApp)) as WidgetsBindingObserver;
      // Exercise legacy platform delivery alongside RouteInformation.
      // ignore: deprecated_member_use
      await observer.didPushRoute(
        'elbench://community/posts/81?focus_comment=9#comment-9',
      );
      await tester.pumpAndSettle();

      expect(_page(tester), same(linkedPage));
      expect(
        api.requests.where((path) => path.startsWith('/community/posts/81?')),
        hasLength(1),
      );
      await tester.binding.handlePushRoute('https://evil.test/users/99');
      await tester.pumpAndSettle();
      expect(_page(tester), same(linkedPage));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signed-out links are retained until login mounts the navigator',
    (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue =
          'https://elbench.com/community/posts/81';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final api = _Api()..signedIn = false;
      await _mount(tester, api);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(
        api.requests.where((path) => path.startsWith('/community/posts/')),
        isEmpty,
      );

      await tester
          .widget<LoginPage>(find.byType(LoginPage))
          .controller
          .login({});
      await tester.pumpAndSettle();

      expect(_page(tester).path, '/community/posts/81');
      expect(
        api.requests.where((path) => path.startsWith('/community/posts/81?')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing the app cancels scheduled incoming navigation', (
    tester,
  ) async {
    final api = _Api();
    await _mount(tester, api);
    await tester.pumpAndSettle();
    await tester.binding.handlePushRoute('https://elbench.com/users/42');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(api.requests.where((path) => path.startsWith('/users/42')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
