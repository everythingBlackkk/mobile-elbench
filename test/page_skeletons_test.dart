import 'dart:async';

import 'package:elbench/api.dart';
import 'package:elbench/infinite_feed.dart';
import 'package:elbench/main.dart';
import 'package:elbench/page_skeletons.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(
  Widget child, {
  bool reduced = true,
  bool ticker = true,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
  themeAnimationDuration: Duration.zero,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 740),
      disableAnimations: reduced,
      textScaler: const TextScaler.linear(2),
    ),
    child: Directionality(
      textDirection: direction,
      child: TickerMode(enabled: ticker, child: child),
    ),
  ),
);

class _Api extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://skeleton.example.test');
  final requests = <String>[];
  final pending = <Completer<Json>>[];
  final user = <String, dynamic>{'id': 7, 'name': 'Mariam'};
  @override
  Future<Json> get(String path) {
    requests.add(path);
    final uri = Uri.parse(path);
    if (uri.path == '/mobile/session' ||
        uri.path == '/profile' ||
        (uri.path == '/community' && !uri.queryParameters.containsKey('q'))) {
      return Future.value({
        'user': user,
        'features': {'community': true},
        'counts': {'notifications': 0, 'inbox': 0},
        'screen': 'community.index',
        'data': {'posts': [], 'communities': []},
      });
    }
    final request = Completer<Json>();
    pending.add(request);
    return request.future;
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};
  @override
  Future<void> clearSession() async {}
}

Finder pulses() => find.descendant(
  of: find.byType(SkeletonPulse).first,
  matching: find.byType(FadeTransition),
);

void main() {
  test(
    'uncached routes infer editors, detail screens and quiz screens before GET',
    () {
      for (final (path, screen) in [
        ('/community?q=algorithms', 'community.index'),
        ('/forum?community_id=4', 'community.forum'),
        ('/question?id=12', 'community.question'),
        ('/ask-question?community_id=4', 'community.ask'),
        ('/users/7?tab=ask', 'profile.user'),
        ('/profile/edit', 'profile.edit'),
        ('/profile/password/reset', 'profile.password-reset'),
        ('/ask/12', 'ask.show'),
        ('/notifications/announcements/9', 'notifications.announcement'),
        ('/menu/notifications', 'notifications.settings'),
        ('/menu/login-activity', 'login-activity.index'),
        ('/quiz/history', 'quiz.history'),
        ('/quiz/manage', 'quiz.admin.index'),
        ('/quiz/manage/create', 'quiz.admin.form'),
        ('/quiz/manage/2/edit', 'quiz.admin.form'),
        ('/quiz/attempt-uuid', 'quiz.attempt'),
        ('/community/4/materials/', 'community.materials'),
        ('/community/materials/9', 'community.material'),
        ('/community/4/notifications', 'community.notifications'),
        ('/admin/schedule-appearance', 'admin.schedule-appearance'),
        ('/admin/post-reports/8/post', 'admin.report-post'),
        ('/terms', 'terms'),
      ]) {
        expect(initialScreenForPath(path), screen, reason: path);
      }
    },
  );

  testWidgets(
    'profile, forum, schedule and quiz retain their familiar geometry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const PageSkeleton(screen: 'profile.user')));
      final banner = tester.getRect(
        find.byKey(const ValueKey('skeleton.profile.banner')),
      );
      final avatar = tester.getRect(
        find.byKey(const ValueKey('skeleton.profile.avatar')),
      );
      expect(banner.height, 184);
      expect(avatar.width, 100);
      expect(avatar.top, lessThan(banner.bottom));
      expect(avatar.bottom, greaterThan(banner.bottom));
      await tester.pumpWidget(
        host(const PageSkeleton(screen: 'community.forum')),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('skeleton.forum.banner')))
            .height,
        140,
      );
      await tester.pumpWidget(
        host(const PageSkeleton(screen: 'schedule.index')),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('skeleton.schedule.days')))
            .height,
        86,
      );
      await tester.pumpWidget(host(const PageSkeleton(screen: 'quiz.result')));
      expect(
        tester.getSize(find.byKey(const ValueKey('skeleton.quiz.score'))),
        const Size(132, 132),
      );
      await tester.pumpWidget(host(const PageSkeleton(screen: 'quiz.attempt')));
      expect(
        find.byKey(const ValueKey('skeleton.quiz.question')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page families fit narrow RTL in both themes without feed fallbacks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        for (final screen in [
          'community.index',
          'community.subjects',
          'community.materials',
          'community.material',
          'notifications.index',
          'ask.inbox',
          'quiz.history',
          'quiz.index',
          'profile.edit',
          'notifications.settings',
          'admin.index',
          'content.campus',
        ]) {
          await tester.pumpWidget(
            host(
              PageSkeleton(screen: screen),
              dark: dark,
              direction: TextDirection.rtl,
            ),
          );
          expect(find.byType(ScreenSkeleton), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$screen dark=$dark');
        }
      }
    },
  );

  testWidgets(
    'one pulse drives a page or a whole pagination/comment group and pauses',
    (tester) async {
      await tester.pumpWidget(
        host(const PageSkeleton(screen: 'community.post'), reduced: false),
      );
      expect(pulses(), findsOneWidget);
      final pulse = tester.widget<FadeTransition>(pulses()).opacity;
      expect(pulse, isA<AnimationController>());
      expect((pulse as AnimationController).isAnimating, isTrue);
      await tester.pumpWidget(
        host(
          const PageSkeleton(screen: 'community.post'),
          ticker: false,
          reduced: false,
        ),
      );
      expect(pulse.isAnimating, isFalse);
      expect(pulse.value, 1);
      await tester.pumpWidget(
        host(
          const SingleChildScrollView(child: CommentsSkeleton(count: 5)),
          reduced: false,
        ),
      );
      expect(pulses(), findsOneWidget);
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: InfiniteScrollFooter(
              hasMore: true,
              loading: true,
              failed: false,
              onLoadMore: () {},
              translate: (en, ar) => en,
              skeletons: 4,
            ),
          ),
        ),
      );
      expect(find.byType(PostSkeleton), findsNWidgets(4));
      expect(pulses(), findsOneWidget);
      expect(
        (tester.widget<FadeTransition>(pulses()).opacity as AnimationController)
            .isAnimating,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending search GET has only results placeholders and quiz hint stays loading-only',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      SharedPreferences.setMockInitialValues({
        'appearance.language': 'en',
        'appearance.liquidGlass': false,
      });
      final settings = AppSettings();
      await settings.load();
      final api = _Api();
      await tester.pumpWidget(
        ElBenchApp(
          api: api,
          settings: settings,
          enablePush: false,
          enableLaunchExperience: false,
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .stateList<NativePageState>(find.byType(NativePage))
          .last
          .c;
      controller.open('/community?q=needle');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widgetList<WebPageEntrance>(find.byType(WebPageEntrance))
            .last
            .ready,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester
            .widgetList<WebPageEntrance>(find.byType(WebPageEntrance))
            .last
            .ready,
        isTrue,
      );
      expect(find.byKey(const ValueKey('skeleton.homeSearch')), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton.home.events')), findsNothing);
      expect(
        find.byKey(const ValueKey('skeleton.home.communities')),
        findsNothing,
      );
      controller.open(
        '/quiz/completed',
        seed: const {'loading_screen': 'quiz.result'},
      );
      await tester.pump();
      final page = tester
          .stateList<NativePageState>(find.byType(NativePage))
          .last;
      expect(page.screen, 'quiz.result');
      expect(page.envelope, isEmpty);
      expect(page.provisional, isFalse);
      expect(find.byKey(const ValueKey('skeleton.quizResult')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
    },
  );
}
