import 'package:elbench/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('toast slides up, matches $brightness and dismisses quickly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppToast(context, 'Saved successfully'),
                child: const Text('Show message'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show message'));
      await tester.pump();
      final toast = find.byKey(const ValueKey('app.toast'));
      final start = tester.getTopLeft(toast).dy;
      final surface = tester.widget<Material>(toast);
      expect(
        surface.color,
        brightness == Brightness.dark ? const Color(0xff242424) : Colors.white,
      );
      expect(
        (surface.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(18),
      );
      expect(
        tester.widget<Text>(find.text('Saved successfully')).style!.color,
        brightness == Brightness.dark
            ? const Color(0xfff3f4f6)
            : const Color(0xff111827),
      );
      await tester.pump(const Duration(milliseconds: 110));
      final midway = tester.getTopLeft(toast).dy;
      await tester.pump(const Duration(milliseconds: 110));
      final resting = tester.getTopLeft(toast).dy;
      expect(start, greaterThan(midway));
      expect(midway, greaterThan(resting));
      expect(
        tester
            .widget<SlideTransition>(
              find.byKey(const ValueKey('app.toast.slide')),
            )
            .position
            .value,
        Offset.zero,
      );
      await tester.pump(const Duration(milliseconds: 1680));
      expect(toast, findsOneWidget, reason: 'visible for about two seconds');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle(const Duration(milliseconds: 20));
      expect(toast, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new toast replaces the old one and survives closing a sheet', (
    tester,
  ) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => TextButton(
                    onPressed: () {
                      showAppToast(sheet, 'Upload complete');
                      Navigator.pop(sheet);
                    },
                    child: const Text('Finish upload'),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            );
          },
        ),
      ),
    );
    showAppToast(host, 'Old message');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish upload'));
    await tester.pumpAndSettle();
    expect(find.text('Old message'), findsNothing);
    expect(find.text('Finish upload'), findsNothing);
    expect(find.text('Upload complete'), findsOneWidget);
    expect(find.byKey(const ValueKey('app.toast')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion shows a still toast and keeps its short lifetime',
    (tester) async {
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      showAppToast(host, 'Saved');
      await tester.pump();
      expect(
        tester
            .widget<SlideTransition>(
              find.byKey(const ValueKey('app.toast.slide')),
            )
            .position
            .value,
        Offset.zero,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('app.toast')), findsNothing);
    },
  );
}
