import 'dart:async';

import 'package:elbench/api.dart';
import 'package:elbench/image_cache.dart';
import 'package:elbench/main.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_home.dart';
import 'package:elbench/web_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingImage extends ImageStreamCompleter {}

class _SearchRequest {
  _SearchRequest(this.uri);
  final Uri uri;
  final result = Completer<Json>();
}

class _SearchApi extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://home-search.example.test');
  final requests = <Uri>[];
  final pending = <_SearchRequest>[];
  bool richSections = true;
  final user = <String, dynamic>{'id': 7, 'name': 'Mariam', 'role': 'student'};

  Json response(Uri uri, {List<String>? contents, bool more = false}) {
    final query = (uri.queryParameters['q'] ?? '').trim();
    final number = int.parse(uri.queryParameters['page'] ?? '1');
    return {
      'screen': 'community.index',
      'user': user,
      'features': {'community': true},
      'counts': {'notifications': 0, 'inbox': 0},
      'data': {
        'search': query,
        'has_communities': true,
        'communities': [
          if (richSections)
            {
              'id': 4,
              'name': 'Logic',
              'description': 'Computer science',
              'image_url': '/community.webp',
              'question_count': 1,
            },
        ],
        'featured_events': [
          if (richSections)
            {
              'id': 1,
              'title': 'Campus festival',
              'image_url': '/event.webp',
              'event_date': '2026-11-01',
            },
        ],
        'scheduleSummary': {
          'date': '2026-10-26',
          'entries': [
            {'type': 'lecture'},
          ],
        },
        'posts': {
          'data': [
            for (final (index, content)
                in (contents ?? ['Unrelated Home post']).indexed)
              {
                'id': number * 100 + index,
                'content': content,
                'author': user,
                'created_at': '2026-10-25T10:00:00Z',
                'visibility': 'public',
                'comments_count': 0,
              },
          ],
          'current_page': number,
          'next_page_url': more
              ? '/community?q=${Uri.encodeQueryComponent(query)}&page=${number + 1}'
              : null,
        },
      },
    };
  }

  @override
  Future<Json> get(String path) {
    final uri = Uri.parse(path);
    if (uri.path == '/community') {
      requests.add(uri);
      if ((uri.queryParameters['q'] ?? '').isEmpty) {
        return Future.value(response(uri));
      }
      final request = _SearchRequest(uri);
      pending.add(request);
      return request.result.future;
    }
    return Future.value({
      'user': user,
      'features': {'community': true},
      'counts': {'notifications': 0, 'inbox': 0},
    });
  }

  void complete(int index, List<String> contents, {bool more = false}) {
    final request = pending[index];
    request.result.complete(
      response(request.uri, contents: contents, more: more),
    );
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};
  @override
  Future<void> clearSession() async {}
}

Future<_SearchApi> _open(
  WidgetTester tester, {
  bool richSections = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1100);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings();
  await settings.load();
  final api = _SearchApi()..richSections = richSections;
  for (final image in ['/event.webp', '/community.webp']) {
    PaintingBinding.instance.imageCache.putIfAbsent(
      CachedNetworkImage(api.media(image), width: 280),
      _PendingImage.new,
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  await tester.pumpWidget(
    ElBenchApp(
      api: api,
      settings: settings,
      enablePush: false,
      enableLaunchExperience: false,
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Finder get _field => find.byKey(const ValueKey('home.search'));
Finder get _loading => find.byKey(const ValueKey('home.search.loading'));
Finder get _scroll => find
    .descendant(of: find.byType(WebHome), matching: find.byType(Scrollable))
    .first;

void _expectPostsOnly() {
  for (final text in [
    'What’s on your mind?',
    'Your Schedule',
    'Upcoming Events',
    "Don't miss out on campus activities",
    'No upcoming events.',
    'Campus festival',
    'Featured Communities',
    'Join and grow with like-minded peers',
    'Logic',
    'Edit subjects',
    'You turned off all subjects.',
    'Community feed',
    'Share a thought. Start a conversation.',
    'Unrelated Home post',
  ]) {
    expect(
      find.text(text),
      findsNothing,
      reason: '$text is unrelated to search',
    );
  }
  expect(find.byType(HomeScheduleCard), findsNothing);
}

void main() {
  for (final richSections in [true, false]) {
    testWidgets(
      'one character hides all Home sections immediately (populated=$richSections)',
      (tester) async {
        final api = await _open(tester, richSections: richSections);
        final initialLoads = api.requests.length;
        final fieldTop = tester.getTopLeft(_field);
        final originalField = tester.state<EditableTextState>(
          find.descendant(of: _field, matching: find.byType(EditableText)),
        );
        await tester.enterText(_field, 'a');
        await tester.pump();
        _expectPostsOnly();
        expect(
          find.text('Type at least 2 characters to search posts.'),
          findsOneWidget,
        );
        expect(_loading, findsNothing);
        expect(
          tester.state<EditableTextState>(
            find.descendant(of: _field, matching: find.byType(EditableText)),
          ),
          same(originalField),
          reason: 'typing keeps the same focused field',
        );
        expect(originalField.widget.focusNode.hasFocus, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          api.requests.length,
          initialLoads,
          reason: 'server minimum is two characters',
        );

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(_field), fieldTop);
        expect(find.text('Upcoming Events'), findsOneWidget);
        expect(find.text('Featured Communities'), findsOneWidget);
        expect(find.byType(HomeScheduleCard), findsOneWidget);
        expect(find.text('What’s on your mind?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'debounce and older responses never reveal posts for another query',
    (tester) async {
      final api = await _open(tester);
      await tester.enterText(_field, 'alpha');
      await tester.pump();
      _expectPostsOnly();
      expect(_loading, findsOneWidget);
      expect(api.pending, isEmpty);
      await tester.pump(const Duration(milliseconds: 399));
      expect(api.pending, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.pending, hasLength(1));
      expect(api.pending[0].uri.queryParameters['q'], 'alpha');
      await tester.enterText(_field, 'beta');
      await tester.pump();
      api.complete(0, ['Alpha match']);
      await tester.pump();
      await tester.pump();
      expect(find.text('Alpha match'), findsNothing);
      expect(_loading, findsOneWidget);
      _expectPostsOnly();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.pending, hasLength(2));
      api.complete(1, ['Beta match']);
      await tester.pumpAndSettle();
      expect(find.text('Beta match'), findsOneWidget);
      expect(find.text('Alpha match'), findsNothing);
      expect(_loading, findsNothing);
      _expectPostsOnly();

      await tester.enterText(_field, 'missing');
      await tester.pump();
      expect(find.text('Beta match'), findsNothing);
      expect(_loading, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      api.complete(2, []);
      await tester.pumpAndSettle();
      expect(find.text('No posts match your search.'), findsOneWidget);
      _expectPostsOnly();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Upcoming Events'), findsOneWidget);
      expect(find.text('Featured Communities'), findsOneWidget);
      expect(find.byType(HomeScheduleCard), findsOneWidget);
      expect(find.text('No posts match your search.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search pagination retains its query and whitespace follows server normalization',
    (tester) async {
      final api = await _open(tester);
      await tester.enterText(_field, '  alpha   beta  ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.pending.single.uri.queryParameters['q'], 'alpha beta');
      api.complete(
        0,
        List.generate(12, (i) => 'Alpha beta result $i'),
        more: true,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Alpha beta result 0'), findsOneWidget);
      for (var i = 0; i < 10 && api.pending.length == 1; i++) {
        await tester.drag(_scroll, const Offset(0, -550));
        await tester.pump();
        await tester.pump();
      }
      expect(api.pending, hasLength(2));
      expect(api.pending[1].uri.queryParameters['q'], 'alpha beta');
      expect(api.pending[1].uri.queryParameters['page'], '2');
      api.complete(1, ['Alpha beta result 12']);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Alpha beta result 12'),
        300,
        scrollable: _scroll,
      );
      expect(find.text('Alpha beta result 12'), findsOneWidget);
      expect(find.text('Upcoming Events'), findsNothing);
      expect(find.text('Featured Communities'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
