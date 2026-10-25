import 'dart:async';
import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RefreshApi extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://refresh.example.test');
  Completer<Json>? refresh;
  int homeLoads = 0;
  final user = <String, dynamic>{'id': 7, 'name': 'Mariam', 'role': 'student'};
  Json envelope(String screen, Json data) => {
    'screen': screen,
    'data': data,
    'user': user,
    'features': {'community': true, 'quiz': true},
    'counts': {'notifications': 0, 'inbox': 0},
  };
  Json get home => envelope('community.index', {
    'communities': [],
    'featured_events': [],
    'posts': {
      'data': [
        for (var i = 0; i < 20; i++)
          {
            'id': i + 1,
            'author': user,
            'content': 'A campus conversation $i.',
            'created_at': '2026-10-01T00:00:00Z',
            'visibility': 'public',
            'comments_count': 0,
          },
      ],
    },
  });
  @override
  Future<Json> get(String path) async {
    if (Uri.parse(path).path == '/community') {
      homeLoads++;
      return refresh == null ? home : refresh!.future;
    }
    return envelope('', {});
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      envelope('', {});
  @override
  Future<void> clearSession() async {}
}

Future<_RefreshApi> _open(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'appearance.language': 'en',
    'appearance.liquidGlass': false,
  });
  final settings = AppSettings();
  await settings.load();
  final api = _RefreshApi();
  await tester.pumpWidget(
    ElBenchApp(
      api: api,
      settings: settings,
      enablePush: false,
      enableLaunchExperience: false,
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/logo.png'),
      tester.element(find.byType(ElBenchHeaderLogo)),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Finder get _scroll => find
    .descendant(of: find.byType(WebHome), matching: find.byType(Scrollable))
    .first;
NativePageState _page(WidgetTester tester) =>
    tester.stateList<NativePageState>(find.byType(NativePage)).last;
Future<Uint8List> _logoPixels(WidgetTester tester) async {
  late Uint8List pixels;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(
        of: find.byType(ElBenchHeaderLogo),
        matching: find.byType(RepaintBoundary),
      ),
    );
    final image = await boundary.toImage();
    pixels = Uint8List.fromList(
      (await image.toByteData())!.buffer.asUint8List(),
    );
    image.dispose();
  });
  return pixels;
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
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'ordinary scrolling stays still and cancelled pulls restore logo',
    (tester) async {
      final api = await _open(tester);
      final resting = await _logoPixels(tester);
      final initialLoads = api.homeLoads;
      await tester.drag(_scroll, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.drag(_scroll, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(await _logoPixels(tester), orderedEquals(resting));
      tester.state<ScrollableState>(_scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      for (final distance in [8.0, 55.0]) {
        final gesture = await tester.startGesture(tester.getCenter(_scroll));
        await gesture.moveBy(Offset(0, distance));
        await tester.pump(const Duration(milliseconds: 60));
        if (distance > 20) {
          expect(await _logoPixels(tester), isNot(orderedEquals(resting)));
        }
        expect(_page(tester).homeRefreshing.value, isFalse);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(await _logoPixels(tester), orderedEquals(resting));
        expect(_page(tester).homePullProgress.value, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(api.homeLoads, initialLoads);
      expect(haptics, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('full pull dims logo, then refresh refills it and settles', (
    tester,
  ) async {
    final api = await _open(tester);
    final resting = await _logoPixels(tester);
    final initialLoads = api.homeLoads;
    api.refresh = Completer<Json>();
    final gesture = await tester.startGesture(tester.getCenter(_scroll));
    await gesture.moveBy(const Offset(0, 450));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.homeLoads, initialLoads, reason: 'still holding the pull');
    expect(_page(tester).homeRefreshing.value, isFalse);
    expect(haptics, isEmpty, reason: 'arming a held pull is not a refresh');
    expect(await _logoPixels(tester), isNot(orderedEquals(resting)));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 60));
    expect(api.homeLoads, initialLoads + 1);
    expect(_page(tester).homeRefreshing.value, isTrue);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(await _logoPixels(tester), isNot(orderedEquals(resting)));
    api.refresh!.complete(api.home);
    await tester.pumpAndSettle();
    expect(_page(tester).homeRefreshing.value, isFalse);
    expect(_page(tester).homePullProgress.value, 0);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(await _logoPixels(tester), orderedEquals(resting));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
