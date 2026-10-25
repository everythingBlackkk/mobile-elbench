import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:elbench/api.dart';
import 'package:elbench/forms.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/upload_progress.dart';
import 'package:elbench/web_profile_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGUlEQVR4nGP4z8DwnxLMMGrAqAGjBgwXAwAwxP4QHCfkAAAAAABJRU5ErkJggg==',
);
const _photos = MethodChannel('plugins.flutter.io/image_picker');

class _Upload {
  _Upload(this.method, this.path, this.data, this.progress);
  final String method, path;
  final Json data;
  final UploadProgress progress;
  final response = Completer<Json>();
}

class _Api extends MobileApi {
  final uploads = <_Upload>[];
  final ordinary = <String>[];
  @override
  Uri get baseUri => Uri.parse('https://upload-progress.example.test');
  Json get person => {
    'id': 7,
    'name': 'Mariam',
    'role': 'super_admin',
    'can_upload_media': true,
    'major': 'Computer Science',
    'level': 2,
    'group_number': 1,
    'section': 3,
    'city': 'Cairo',
    'job': 'Student',
    'avatar': 'jko.webp',
    'banner_image': '',
    'banner_color': '#2e855d',
  };
  Json envelope(String screen, Json data) => {
    'screen': screen,
    'data': data,
    'user': person,
    'features': {'community': true},
    'counts': {'notifications': 0, 'inbox': 0},
  };

  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    return switch (uri.path) {
      '/profile/edit' => envelope('profile.edit', {
        'user': person,
        'skills': [],
        'available_avatars': ['jko.webp'],
        'allowed_banner_images': <String>[],
        'allowed_majors': ['Computer Science'],
        'egyptian_cities': ['Cairo'],
        'job_options': ['Student'],
      }),
      '/profile' => envelope('profile.show', {
        'profile_user': person,
        'skills': [],
        'activityTab': 'posts',
        'profile_posts': {'data': []},
      }),
      '/admin/schedule-appearance' => envelope('admin.schedule-appearance', {
        'appearance': {'mode': 'image', 'image_url': null},
      }),
      '/admin' => envelope('admin.index', {
        'activeSection': uri.queryParameters['section'] ?? 'events',
        'sections': {'events': 'Events', 'communities': 'Communities'},
        'records': {
          'data': [
            {
              'id': 3,
              'title': 'Original Event',
              'arenas': 'Hall A',
              'event_date': '2026-11-01',
              'image_url': '',
              'link_url': '',
              'details': 'Event details',
            },
          ],
        },
        'communities': [
          {'id': 4, 'name': 'Logic', 'description': 'CS', 'image': ''},
        ],
      }),
      _ => envelope('community.index', {'communities': [], 'posts': []}),
    };
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    ordinary.add(path);
    return {};
  }

  @override
  Future<Json> sendWithProgress(
    String method,
    String path,
    Json data, {
    required UploadProgress onSendProgress,
  }) {
    final request = _Upload(method, Uri.parse(path).path, data, onSendProgress);
    uploads.add(request);
    return request.response.future;
  }

  @override
  Future<void> clearSession() async {}
}

Future<void> _open(
  WidgetTester tester,
  _Api api,
  String path, {
  bool actionForm = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings();
  await settings.load();
  final navigator = GlobalKey<NavigatorState>();
  final controller = AppController(api, settings, navigator, enablePush: false)
    ..user = api.person;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    settings.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: settings.theme(Brightness.light),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: actionForm
          ? Scaffold(
              body: ActionForm(
                controller: controller,
                title: 'Photo form',
                path: '/photo',
                method: 'POST',
                fields: const [FieldSpec('photo', 'Choose photo', file: true)],
                fixed: const {},
              ),
            )
          : NativePage(controller: controller, path: path),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapWithIo(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

Future<void> _saveWithIo(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    await tester.tap(target);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pump();
}

Future<void> _complete(
  WidgetTester tester,
  _Upload upload, {
  Json data = const {},
  ApiFailure? error,
}) async {
  await tester.runAsync(() async {
    if (error == null) {
      upload.response.complete(data);
    } else {
      upload.response.completeError(error);
    }
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Finder _indicator(String key) => find.byKey(ValueKey(key));
UploadProgressIndicator _progress(WidgetTester tester, String key) =>
    tester.widget<UploadProgressIndicator>(_indicator(key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String photo;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('elbench-progress-');
    photo = (File(
      '${directory.path}/photo.png',
    )..writeAsBytesSync(_pixels)).path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, (_) async => photo);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, null);
    directory.deleteSync(recursive: true);
  });

  testWidgets(
    'avatar reports real bytes and waits for server after 100 percent',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/profile/edit');
      await _tapWithIo(
        tester,
        find.byKey(const ValueKey('profile.edit.avatar.camera')),
      );
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      const key = 'profile.upload.progress';
      expect(_progress(tester, key).value, 0);
      final request = api.uploads.single;
      expect(request.path, '/profile');
      expect(request.data['avatar_upload'], isA<MultipartFile>());
      request.progress(256, 1024);
      await tester.pump();
      expect(_progress(tester, key).value, .25);
      expect(find.text('25%'), findsOneWidget);
      final unchanged = _progress(tester, key);
      request.progress(257, 1024);
      await tester.pump();
      expect(_progress(tester, key), same(unchanged));
      request.progress(1024, 1024);
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Saving photo…'), findsOneWidget);
      expect(find.byType(WebProfileEdit), findsOneWidget);
      expect(request.response.isCompleted, isFalse);
      await _complete(tester, request, data: {'redirect_url': '/profile'});
      expect(find.byType(WebProfileEdit), findsNothing);
      expect(_indicator(key), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'banner unknown length stays honest and validation failure allows retry',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/profile/edit');
      await _tapWithIo(
        tester,
        find.byKey(const ValueKey('profile.edit.banner.camera')),
      );
      await _tapWithIo(tester, find.text('Use this banner'));
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      final request = api.uploads.single;
      expect(request.data['banner_upload'], isA<MultipartFile>());
      request.progress(500, -1);
      await tester.pump();
      const key = 'profile.upload.progress';
      expect(_progress(tester, key).value, isNull);
      expect(find.textContaining('%'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(
        _progress(tester, key).value,
        isNull,
        reason: 'time does not invent progress',
      );
      request.progress(800, 1000);
      await tester.pump();
      expect(find.text('80%'), findsOneWidget);
      await _complete(
        tester,
        request,
        error: const ApiFailure(
          'Image rejected.',
          status: 422,
          fields: {
            'banner_upload': ['Choose a different image.'],
          },
        ),
      );
      expect(_indicator(key), findsNothing);
      expect(find.text('Image rejected.'), findsOneWidget);
      expect(find.text('Choose a different image.'), findsOneWidget);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(api.uploads, hasLength(2));
      expect(_progress(tester, key).value, 0);
      await _complete(
        tester,
        api.uploads.last,
        data: {'redirect_url': '/profile'},
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared photo form exposes upload progress and preserves server errors',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/photo', actionForm: true);
      await _tapWithIo(tester, find.text('Choose photo'));
      await _saveWithIo(tester, find.text('Save'));
      final request = api.uploads.single;
      expect(request.data['photo'], isA<MultipartFile>());
      request.progress(51, 100);
      await tester.pump();
      expect(_progress(tester, 'action.upload.progress').value, .51);
      expect(find.text('51%'), findsOneWidget);
      await _complete(
        tester,
        request,
        error: const ApiFailure('Photo form rejected.'),
      );
      expect(find.text('Photo form rejected.'), findsOneWidget);
      expect(_indicator('action.upload.progress'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'schedule appearance image uses transport progress and waits to save',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/admin/schedule-appearance');
      await _tapWithIo(
        tester,
        find.byKey(const ValueKey('schedule.appearance.choose-image')),
      );
      await _saveWithIo(
        tester,
        find.byKey(const ValueKey('schedule.appearance.save')),
      );
      final request = api.uploads.single;
      expect(request.path, '/admin/schedule-appearance');
      expect(request.data['image'], isA<MultipartFile>());
      request.progress(500, 1000);
      await tester.pump();
      expect(_progress(tester, 'schedule.image.upload.progress').value, .5);
      request.progress(1000, 1000);
      await tester.pump();
      expect(find.text('Changes saved.'), findsNothing);
      expect(find.text('Saving image…'), findsOneWidget);
      await _complete(tester, request);
      expect(find.text('Changes saved.'), findsOneWidget);
      expect(_indicator('schedule.image.upload.progress'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'admin event image has progress without changing the PATCH payload',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/admin?section=events');
      await tester.scrollUntilVisible(
        find.text('Edit event'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Edit event'));
      await tester.pumpAndSettle();
      await _tapWithIo(
        tester,
        find.byKey(const ValueKey('admin.image.image_upload')),
      );
      await tester.scrollUntilVisible(
        find.text('Save changes'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await _saveWithIo(tester, find.text('Save changes'));
      final request = api.uploads.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/admin/events/3');
      expect(request.data['image_upload'], isA<MultipartFile>());
      expect(request.data['title'], 'Original Event');
      request.progress(99, 100);
      await tester.pump();
      expect(_progress(tester, 'admin.upload.progress').value, .99);
      await _complete(
        tester,
        request,
        error: const ApiFailure('Event image rejected.'),
      );
      expect(find.text('Event image rejected.'), findsOneWidget);
      expect(_indicator('admin.upload.progress'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cropped community photo reports real progress until server response',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/admin?section=communities');
      await tester.scrollUntilVisible(
        find.text('Edit details'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      await _tapWithIo(tester, find.text('Choose File'));
      await _tapWithIo(tester, find.text('Use image'));
      await tester.scrollUntilVisible(
        find.text('Save community'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await _saveWithIo(tester, find.text('Save community'));
      final request = api.uploads.single;
      expect(request.path, '/admin/communities/4');
      expect(request.data['image_upload'], isA<MultipartFile>());
      request.progress(300, 1000);
      await tester.pump();
      expect(_progress(tester, 'community.image.upload.progress').value, .3);
      request.progress(1000, 1000);
      await tester.pump();
      expect(find.text('Saving image…'), findsOneWidget);
      expect(request.response.isCompleted, isFalse);
      await _complete(tester, request, data: {'message': 'Saved photo.'});
      expect(_indicator('community.image.upload.progress'), findsNothing);
      expect(find.text('Saved photo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
