import 'package:elbench/api.dart';
import 'package:elbench/app_menus.dart';
import 'package:elbench/main.dart';
import 'package:elbench/quiz_views.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _HistoryApi extends MobileApi {
  _HistoryApi({this.arabic = false});
  final bool arabic;
  final requests = <Uri>[];

  @override
  Uri get baseUri => Uri.parse('https://quiz-history.example.test');

  String get bank => arabic
      ? 'بنك أسئلة مقدمة في برمجة الحاسب ونظم المعلومات للفرقة الثانية'
      : 'A complete question bank for Computer Science and Information Systems';

  Json attempt(String uuid, String status, Object score) => {
    'uuid': uuid,
    'category_name': bank,
    'category_slug': 'computing',
    'score': score,
    'status': status,
    'time_taken_seconds': 123,
    'started_at': '2026-10-23T12:00:00Z',
    if (status != 'abandoned') 'submitted_at': '2026-10-23T12:02:03Z',
  };

  Json envelope(String screen, Json data) => {
    'user': {'id': 7, 'name': 'Student'},
    'screen': screen,
    'data': data,
    'counts': {'notifications': 0, 'inbox': 0},
    'features': {'quiz': true},
  };

  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (uri.path == '/quiz/history') {
      return envelope('quiz.history', {
        'categories': [
          {'id': 1, 'name': bank},
        ],
        'attempts': {
          'total': 3,
          'data': [
            attempt('submitted-attempt', 'submitted', 80),
            attempt('timed-attempt', 'timed_out', 20),
            attempt('abandoned-attempt', 'abandoned', 0),
          ],
        },
      });
    }
    return envelope('quiz.result', {
      'attempt': attempt(uri.path.split('/').last, 'submitted', 80),
      'items': [],
    });
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};

  @override
  Future<void> clearSession() async {}
}

Future<AppController> _open(
  WidgetTester tester,
  _HistoryApi api, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
  String path = '/quiz/history',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  final language = api.arabic ? 'ar' : 'en';
  final settings = AppSettings(language: language);
  final navigator = GlobalKey<NavigatorState>();
  final c = AppController(api, settings, navigator, enablePush: false)
    ..user = {'id': 7, 'name': 'Student'};
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: settings.theme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: NativePage(controller: c, path: path),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    c.dispose();
    settings.dispose();
  });
  return c;
}

Finder _part(String part, [String uuid = 'submitted-attempt']) =>
    find.byKey(ValueKey('quiz.history.$part.$uuid'));

Future<void> _show(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find
          .descendant(
            of: find.byType(WebQuizHistory),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final testCase in [
    (brightness: Brightness.light, arabic: false, width: 390.0, scale: 1.0),
    (brightness: Brightness.dark, arabic: true, width: 320.0, scale: 1.0),
    (brightness: Brightness.light, arabic: true, width: 320.0, scale: 2.0),
    (brightness: Brightness.dark, arabic: false, width: 390.0, scale: 2.0),
  ]) {
    testWidgets(
      'history cards fit ${testCase.brightness.name} '
      '${testCase.arabic ? 'RTL' : 'LTR'} ${testCase.width} at ${testCase.scale}x',
      (tester) async {
        final api = _HistoryApi(arabic: testCase.arabic);
        await _open(
          tester,
          api,
          brightness: testCase.brightness,
          width: testCase.width,
          textScale: testCase.scale,
        );
        await _show(tester, _part('attempt'));

        final card = tester.getRect(_part('attempt'));
        for (final part in ['bank', 'status', 'date', 'summary', 'review']) {
          final bounds = tester.getRect(_part(part));
          expect(bounds.left, greaterThanOrEqualTo(card.left));
          expect(bounds.right, lessThanOrEqualTo(card.right));
        }
        final title = tester.widget<Text>(_part('bank'));
        expect(title.data, api.bank);
        expect(title.maxLines, isNull); // The entire bank name can wrap.
        expect(
          title.textDirection,
          testCase.arabic ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(
          tester.widget<Text>(_part('score')).semanticsLabel,
          testCase.arabic ? 'النتيجة 80 من ١٠٠' : 'Score 80 out of 100',
        );
        expect(tester.widget<Text>(_part('time')).data, '02:03');

        // Summary values stack before enlarged text would crowd each other.
        if (testCase.scale > 1 || testCase.width < 350) {
          expect(
            tester.getTopLeft(_part('time')).dy,
            greaterThan(tester.getBottomLeft(_part('score')).dy),
          );
        } else {
          expect(
            tester.getTopLeft(_part('time')).dy,
            lessThan(tester.getBottomLeft(_part('score')).dy),
          );
        }

        final outer = tester.widget<Container>(
          find
              .descendant(
                of: _part('attempt'),
                matching: find.byType(Container),
              )
              .first,
        );
        final theme = Theme.of(tester.element(_part('attempt')));
        expect(
          (outer.decoration as BoxDecoration).color,
          theme.colorScheme.surface,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'previous result action is accessible and opens its own attempt',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final api = _HistoryApi();
      await _open(tester, api);
      await tester.ensureVisible(_part('review'));
      await tester.pumpAndSettle();
      final data = tester.getSemantics(_part('review')).getSemanticsData();
      expect(data.label, 'View result');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      semantics.dispose();

      await tester.tap(_part('review'));
      await tester.pumpAndSettle();
      expect(api.requests.last.path, '/quiz/submitted-attempt');
      expect(find.byType(WebQuizResult), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all result statuses retain their score and date fallback', (
    tester,
  ) async {
    final api = _HistoryApi();
    await _open(tester, api);
    for (final entry in [
      (uuid: 'submitted-attempt', label: 'Submitted', score: '80'),
      (uuid: 'timed-attempt', label: 'Timed out', score: '20'),
      (uuid: 'abandoned-attempt', label: 'Abandoned', score: '0'),
    ]) {
      await tester.ensureVisible(_part('attempt', entry.uuid));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _part('status', entry.uuid),
          matching: find.text(entry.label),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(_part('score', entry.uuid)).semanticsLabel,
        'Score ${entry.score} out of 100',
      );
      expect(tester.widget<Text>(_part('date', entry.uuid)).data, isNotEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing history sorting preserves bank and status filters', (
    tester,
  ) async {
    final api = _HistoryApi();
    await _open(
      tester,
      api,
      path: '/quiz/history?category_id=1&status=timed_out&sort=oldest',
    );
    final filters = find.byType(AppDropdownButtonFormField<String>);
    expect(filters, findsNWidgets(3));
    await tester.ensureVisible(filters.at(2));
    await tester.tap(filters.at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest first').last);
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/quiz/history');
    expect(api.requests.last.queryParameters, {
      'category_id': '1',
      'status': 'timed_out',
      'sort': 'newest',
      'lang': 'en',
    });
    expect(tester.takeException(), isNull);
  });
}
