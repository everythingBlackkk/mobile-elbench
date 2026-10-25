import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://keyboard.example.test');
  @override
  Future<Json> get(String path) async => {'user': null};
  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      {};
  @override
  Future<void> clearSession() async {}
}

Future<NavigatorState> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1000);
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings();
  await settings.load();
  await tester.pumpWidget(
    ElBenchApp(
      api: _Api(),
      settings: settings,
      enablePush: false,
      enableLaunchExperience: false,
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    settings.dispose();
    tester.view.reset();
    debugDefaultTargetPlatformOverride = null;
  });
  return tester
      .widget<MaterialApp>(find.byType(MaterialApp))
      .navigatorKey!
      .currentState!;
}

Widget _outside() => Container(
  key: const ValueKey('outside'),
  height: 100,
  width: double.infinity,
  color: Colors.transparent,
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '${platform.name}: all input types dismiss on empty-space touch',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final navigator = await _mount(tester);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const TextField(key: ValueKey('plain')),
                      TextFormField(key: const ValueKey('form')),
                      const CupertinoTextField(key: ValueKey('cupertino')),
                      const TextField(key: ValueKey('multiline'), maxLines: 3),
                      _outside(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final name in ['plain', 'form', 'cupertino', 'multiline']) {
          final field = find.byKey(ValueKey(name));
          await tester.tap(field);
          await tester.pump();
          final editable = tester.widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.tap(find.byKey(const ValueKey('outside')));
          await tester.pump();
          expect(editable.focusNode.hasFocus, isFalse, reason: name);
          expect(tester.testTextInput.isVisible, isFalse, reason: name);
        }
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name}: switching inputs and field controls retain focus',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final navigator = await _mount(tester);
        var suffixTaps = 0;
        var actionTaps = 0;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('first'),
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          key: const ValueKey('suffix'),
                          onPressed: () => suffixTaps++,
                          icon: const Icon(Icons.visibility),
                        ),
                      ),
                    ),
                    const TextField(key: ValueKey('second')),
                    TextButton(
                      key: const ValueKey('action'),
                      onPressed: () => actionTaps++,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('first'));
        final second = find.byKey(const ValueKey('second'));
        await tester.tap(first);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('suffix')));
        await tester.pump();
        expect(suffixTaps, 1);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: first, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.tap(second);
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: second, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.tap(find.byKey(const ValueKey('action')));
        await tester.pump();
        expect(actionTaps, 1);
        expect(editable.focusNode.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '${platform.name}: dialogs and bottom sheets inherit dismissal',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final navigator = await _mount(tester);
        for (final sheet in [false, true]) {
          Widget content() => SizedBox(
            height: 300,
            child: Column(
              children: [
                const TextField(key: ValueKey('overlay.input')),
                _outside(),
              ],
            ),
          );
          if (sheet) {
            showModalBottomSheet<void>(
              context: navigator.context,
              builder: (_) => content(),
            );
          } else {
            showDialog<void>(
              context: navigator.context,
              builder: (_) => Dialog(child: content()),
            );
          }
          await tester.pumpAndSettle();
          final field = find.byKey(const ValueKey('overlay.input'));
          await tester.tap(field);
          await tester.pump();
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.tap(find.byKey(const ValueKey('outside')));
          await tester.pump();
          expect(tester.testTextInput.isVisible, isFalse);
          navigator.pop();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
