import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/upload_progress.dart';
import 'package:elbench/web_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _files = MethodChannel('flutter_file_dialog');
const _photos = MethodChannel('plugins.flutter.io/image_picker');
final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class _UploadApi extends MobileApi {
  final sent = <({String method, String path, Json data})>[];
  UploadProgress? progress;
  Completer<Json>? response;

  @override
  Uri get baseUri => Uri.parse('https://upload-progress.example.test');

  Json envelope(String screen, Json data) => {
    'screen': screen,
    'data': data,
    'user': {'id': 7, 'name': 'Student'},
    'features': {'community': true},
    'counts': {'notifications': 0, 'inbox': 0},
  };

  @override
  Future<Json> get(String path) async =>
      Uri.parse(path).path == '/community/materials/10'
      ? envelope('community.material', {
          'community': {'id': 4, 'name': 'Data Structures'},
          'material': {
            'id': 10,
            'kind': 'text',
            'title': 'Lecture notes',
            'extension': 'txt',
            'size': 12,
          },
          'preview': {'type': 'text', 'text': 'Preview text'},
        })
      : envelope('community.materials', {
          'community': {'id': 4, 'name': 'Data Structures'},
          'materials': {'data': []},
          'can_manage': true,
          'storage_ready': true,
          'max_bytes': 1024,
        });

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async =>
      throw StateError('Uploads must use the progress-aware API.');

  @override
  Future<Json> sendWithProgress(
    String method,
    String path,
    Json data, {
    required UploadProgress onSendProgress,
  }) {
    sent.add((method: method, path: Uri.parse(path).path, data: {...data}));
    progress = onSendProgress;
    response = Completer<Json>();
    return response!.future;
  }

  @override
  Future<void> clearSession() async {}
}

Future<void> _open(
  WidgetTester tester,
  _UploadApi api, {
  String path = '/community/4/materials',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.reset);
  final settings = AppSettings(language: 'en');
  final navigator = GlobalKey<NavigatorState>();
  final c = AppController(api, settings, navigator, enablePush: false)
    ..user = {'id': 7, 'name': 'Student'};
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: settings.theme(Brightness.light),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(padding: const EdgeInsets.only(bottom: 34)),
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
}

Future<void> _tapWithIo(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 60));
  });
  await tester.pumpAndSettle();
}

Finder get _indicator =>
    find.byKey(const ValueKey('materials.upload.progress'));

Future<void> _respond(
  WidgetTester tester,
  _UploadApi api, {
  bool fail = false,
}) async {
  await tester.runAsync(() async {
    if (fail) {
      api.response!.completeError(const ApiFailure('Upload failed.'));
    } else {
      api.response!.complete({});
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fileCalls = <MethodCall>[], photoCalls = <MethodCall>[];
  String? picked;

  setUp(() {
    picked = null;
    fileCalls.clear();
    photoCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, (call) async {
          fileCalls.add(call);
          return picked;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, (call) async {
          photoCalls.add(call);
          return picked;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, null);
  });

  test(
    'transport percent preserves exact boundaries and reserves 100 for completion',
    () {
      expect(uploadProgressPercent(29 / 100), 29);
      expect(uploadProgressPercent(.9999999999999999), 99);
      expect(uploadProgressPercent(1), 100);
      expect(uploadProgressPercent(-.2), 0);
      expect(uploadProgressPercent(1.2), 100);
      expect(uploadProgressPercent(null), isNull);
      expect(uploadProgressPercent(double.nan), isNull);
      expect(uploadProgressPercent(double.infinity), isNull);
    },
  );

  for (final images in [false, true]) {
    testWidgets(
      '${images ? 'image' : 'file'} upload shows actual bytes and waits '
      'for the server after 100 percent',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'elbench-progress-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        picked = (File(
          '${directory.path}/lecture.${images ? 'png' : 'pdf'}',
        )..writeAsBytesSync(_imageBytes)).path;
        final api = _UploadApi();
        await _open(tester, api);
        final button = find.byKey(
          ValueKey('materials.upload.${images ? 'images' : 'files'}'),
        );
        if (images) {
          expect(
            find.descendant(
              of: button,
              matching: find.byWidgetPredicate(
                (widget) => widget is WebIcon && widget.name == 'image',
              ),
            ),
            findsOneWidget,
          );
        }
        await _tapWithIo(tester, button);
        expect(
          _indicator,
          findsNothing,
        ); // No fake progress while choosing a title.
        await _tapWithIo(tester, find.text('Upload'));

        expect(api.sent, hasLength(1));
        expect(api.sent.single.path, '/community/4/materials');
        expect(api.sent.single.data['file'], isA<MultipartFile>());
        expect(find.text('0%'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('0%'), findsOneWidget); // Time never advances the bar.

        api.progress!(25, 100);
        await tester.pump();
        expect(find.text('25%'), findsOneWidget);
        expect(tester.widget<UploadProgressIndicator>(_indicator).value, .25);
        api.progress!(259, 1000);
        await tester.pump();
        expect(tester.widget<UploadProgressIndicator>(_indicator).value, .25);
        api.progress!(29, 100);
        await tester.pump();
        expect(find.text('29%'), findsOneWidget);
        api.progress!(999, 1000);
        await tester.pump();
        expect(find.text('99%'), findsOneWidget);
        expect(find.text('100%'), findsNothing);
        api.progress!(1000, 1000);
        await tester.pump();
        expect(find.text('100%'), findsOneWidget);
        expect(find.text('Finishing upload…'), findsOneWidget);
        expect(find.text('Material uploaded.'), findsNothing);

        await tester.tap(button);
        await tester.pump();
        expect(api.sent, hasLength(1));
        expect(fileCalls, hasLength(images ? 0 : 1));
        expect(photoCalls, hasLength(images ? 1 : 0));
        await _respond(tester, api);
        expect(_indicator, findsNothing);
        expect(find.text('Material uploaded.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unknown-length upload stays indeterminate and failure resets it',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'elbench-progress-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      picked = (File(
        '${directory.path}/lecture.pdf',
      )..writeAsBytesSync(_imageBytes)).path;
      final api = _UploadApi();
      await _open(tester, api);
      final button = find.byKey(const ValueKey('materials.upload.files'));
      await _tapWithIo(tester, button);
      await _tapWithIo(tester, find.text('Upload'));
      api.progress!(50, -1);
      await tester.pump();
      expect(tester.widget<UploadProgressIndicator>(_indicator).value, isNull);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(find.text('0%'), findsNothing);
      expect(find.text('100%'), findsNothing);

      final previousProgress = api.progress!;
      await _respond(tester, api, fail: true);
      expect(_indicator, findsNothing);
      expect(find.text('Upload failed.'), findsOneWidget);
      api.progress!(
        100,
        100,
      ); // Late callbacks cannot resurrect a finished request.
      await tester.pump();
      expect(_indicator, findsNothing);

      await _tapWithIo(tester, button);
      await _tapWithIo(tester, find.text('Upload'));
      expect(api.sent, hasLength(2));
      expect(find.text('0%'), findsOneWidget);
      previousProgress(100, 100);
      await tester.pump();
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Finishing upload…'), findsNothing);
      await _respond(tester, api);
      expect(_indicator, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled gallery selection never starts an upload indicator', (
    tester,
  ) async {
    final api = _UploadApi();
    await _open(tester, api);
    await tester.tap(find.byKey(const ValueKey('materials.upload.images')));
    await tester.pumpAndSettle();
    expect(photoCalls.single.arguments['source'], 1);
    expect(api.sent, isEmpty);
    expect(_indicator, findsNothing);
  });

  testWidgets(
    'shared image glyph paints visible strokes for all image buttons',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: Colors.white,
                child: WebIcon('image', size: 32, color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var painted = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) < 128 && bytes.getUint8(i + 3) > 0) painted++;
        }
        image.dispose();
        expect(painted, greaterThan(50));
      });
    },
  );

  testWidgets('upload progress is themed and fits narrow RTL with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);
    final settings = AppSettings(language: 'ar');
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: settings.theme(brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: UploadProgressIndicator(
                    value: .9999,
                    label: 'جاري رفع الملف المحدد إلى المجتمع',
                    finishingLabel: 'جاري إنهاء الرفع…',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, .9999);
      expect(bar.color, settings.theme(brightness).colorScheme.primary);
      expect(tester.takeException(), isNull);
    }
    settings.dispose();
  });

  testWidgets(
    'text file preview uses device safe area instead of dock clearance',
    (tester) async {
      await _open(tester, _UploadApi(), path: '/community/materials/10');
      final preview = find
          .ancestor(
            of: find.text('Preview text'),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final padding =
          tester.widget<SingleChildScrollView>(preview).padding as EdgeInsets;
      expect(
        padding.bottom,
        MediaQuery.paddingOf(tester.element(preview)).bottom + 16,
      );
      expect(padding.bottom, lessThan(120));
      expect(tester.takeException(), isNull);
    },
  );
}
