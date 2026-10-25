import 'dart:async';

import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_materials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MaterialApi extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://material-navigation.example.test');
  final viewer = Completer<Json>();
  final material = <String, dynamic>{
    'id': 21,
    'title': 'Lecture notes',
    'kind': 'text',
    'extension': 'txt',
    'size': 24,
  };
  Json envelope(String screen, Json data) => {
    'user': {'id': 7, 'name': 'Student'},
    'features': {'community': true},
    'counts': {'notifications': 0, 'inbox': 0},
    'screen': screen,
    'data': data,
  };
  Json get document => envelope('community.material', {
    'material': material,
    'community': {'id': 7, 'name': 'Logic'},
    'preview': {'type': 'text', 'text': 'Contents of the lecture notes.'},
  });
  @override
  Future<Json> get(String path) async {
    switch (Uri.parse(path).path) {
      case '/community/materials/21':
        return viewer.future;
      case '/community/7/materials':
        return envelope('community.materials', {
          'community': {'id': 7, 'name': 'Logic'},
          'materials': {
            'data': [material],
          },
          'can_manage': false,
          'storage_ready': true,
        });
      default:
        return envelope('community.index', {
          'search': '',
          'posts': [],
          'communities': [],
        });
    }
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};
  @override
  Future<void> clearSession() async {}
}

NativePageState _page(WidgetTester tester) =>
    tester.stateList<NativePageState>(find.byType(NativePage)).last;
bool _dockVisible(WidgetTester tester) => tester
    .widget<Visibility>(find.byKey(const ValueKey('navigation.dockVisibility')))
    .visible;

void main() {
  for (final seeded in [false, true]) {
    testWidgets(
      'file viewer hides dock while loading and reading; back restores it (seeded=$seeded)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 932);
        SharedPreferences.setMockInitialValues({
          'appearance.language': 'en',
          'appearance.liquidGlass': false,
        });
        final settings = AppSettings();
        await settings.load();
        final api = _MaterialApi();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          settings.dispose();
          tester.view.reset();
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
        final controller = _page(tester).c;
        controller.open('/community/7/materials');
        await tester.pumpAndSettle();
        expect(find.byType(WebMaterials), findsOneWidget);
        expect(_dockVisible(tester), isTrue);
        if (seeded) {
          await tester.tap(find.text('Lecture notes'));
        } else {
          controller.open('/community/materials/21');
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(_page(tester).screen, 'community.material');
        expect(_dockVisible(tester), isFalse);
        api.viewer.complete(api.document);
        await tester.pumpAndSettle();
        expect(find.byType(WebMaterialViewer), findsOneWidget);
        expect(find.text('Contents of the lecture notes.'), findsOneWidget);
        expect(_dockVisible(tester), isFalse);
        controller.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(WebMaterials), findsOneWidget);
        expect(_dockVisible(tester), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
