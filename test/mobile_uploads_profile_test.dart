import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/screens.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_materials.dart';
import 'package:elbench/web_profile_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _files = MethodChannel('flutter_file_dialog');
const _photos = MethodChannel('plugins.flutter.io/image_picker');
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);
final _bannerPixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGUlEQVR4nGP4z8DwnxLMMGrAqAGjBgwXAwAwxP4QHCfkAAAAAABJRU5ErkJggg==',
);

class _Api extends MobileApi {
  bool canManage = true, storageReady = true, canUploadMedia = true;
  int maxBytes = 30 * 1024 * 1024;
  final actions = <({String method, String path, Json data})>[];

  @override
  Uri get baseUri => Uri.parse('https://uploads.example.test');

  Json get person => {
    'id': 7,
    'name': 'Unique Student Name',
    'university_id': '123456789',
    'gender': 'Female',
    'can_upload_media': canUploadMedia,
    'major': 'Computer Science',
    'level': 2,
    'group_number': 1,
    'section': 3,
    'city': 'Cairo',
    'job': 'Student',
    'birthdate': '2000-03-04',
    'graduation_year': 2027,
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
    switch (Uri.parse(path).path) {
      case '/community/4/materials':
        return envelope('community.materials', {
          'community': {'id': 4, 'name': 'Data Structures'},
          'materials': {'data': []},
          'can_manage': canManage,
          'storage_ready': storageReady,
          'max_bytes': maxBytes,
        });
      case '/profile/edit':
        return envelope('profile.edit', {
          'user': person,
          'skills': [],
          'available_avatars': ['jko.webp'],
          'allowed_banner_images': <String>[],
          'allowed_majors': ['Computer Science'],
          'egyptian_cities': ['Cairo'],
          'job_options': ['Student'],
        });
      case '/profile':
        return envelope('profile.show', {
          'profile_user': person,
          'activityTab': 'posts',
          'profile_posts': {'data': []},
          'skills': [],
        });
      default:
        return envelope('community.index', {'communities': [], 'posts': []});
    }
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    actions.add((method: method, path: Uri.parse(path).path, data: {...data}));
    return {};
  }

  @override
  Future<void> clearSession() async {}
}

Future<void> _open(WidgetTester tester, _Api api, String path) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'appearance.language': 'en',
    'appearance.liquidGlass': false,
  });
  final settings = AppSettings();
  await settings.load();
  final navigator = GlobalKey<NavigatorState>();
  final controller = AppController(api, settings, navigator, enablePush: false)
    ..user = api.person;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: settings.theme(Brightness.light),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: NativePage(controller: controller, path: path),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    settings.dispose();
  });
}

Future<void> _tapWithIo(WidgetTester tester, Finder target) async {
  await tester.runAsync(() async {
    await tester.tap(target);
    // Let native file reads and the image codec finish outside fake time.
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fileCalls = <MethodCall>[], photoCalls = <MethodCall>[];
  String? pickedFile, pickedPhoto;

  setUp(() {
    fileCalls.clear();
    photoCalls.clear();
    pickedFile = null;
    pickedPhoto = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, (call) async {
          fileCalls.add(call);
          return pickedFile;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, (call) async {
          photoCalls.add(call);
          return pickedPhoto;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_files, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_photos, null);
  });

  testWidgets(
    'Community files and images open separate native pickers and cancel safely',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/community/4/materials');
      expect(find.byType(WebMaterials), findsOneWidget);
      expect(find.text('Upload Files'), findsOneWidget);
      expect(find.text('Upload Images'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('materials.upload.files')));
      await tester.pumpAndSettle();
      expect(fileCalls.single.method, 'pickFile');
      expect(
        fileCalls.single.arguments['fileExtensionsFilter'],
        contains('pdf'),
      );
      expect(photoCalls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('materials.upload.images')));
      await tester.pumpAndSettle();
      expect(photoCalls.single.method, 'pickImage');
      expect(photoCalls.single.arguments['source'], 1); // gallery
      expect(photoCalls.single.arguments['requestFullMetadata'], isFalse);
      expect(fileCalls, hasLength(1));
      expect(api.actions, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('Community Manage image shortcut opens the gallery directly', (
    tester,
  ) async {
    final api = _Api();
    await _open(tester, api, '/community/4/materials?upload=images');
    expect(photoCalls.single.arguments['source'], 1);
    expect(fileCalls, isEmpty);
    expect(api.actions, isEmpty);
  });

  testWidgets('gallery image uploads through the existing material endpoint', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('elbench-photo-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/lecture.png')
      ..writeAsBytesSync(_pixel);
    pickedPhoto = file.path;
    final api = _Api();
    await _open(tester, api, '/community/4/materials');

    await _tapWithIo(
      tester,
      find.byKey(const ValueKey('materials.upload.images')),
    );
    expect(find.text('Upload an image'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'lecture',
    );
    await tester.enterText(find.byType(TextField), 'Lecture diagram');
    await _tapWithIo(tester, find.text('Upload'));

    expect(api.actions, hasLength(1));
    expect(api.actions.single.method, 'POST');
    expect(api.actions.single.path, '/community/4/materials');
    expect(api.actions.single.data['title'], 'Lecture diagram');
    final uploaded = api.actions.single.data['file'] as MultipartFile;
    expect(uploaded.filename, 'lecture.png');
    expect(uploaded.length, _pixel.length);
    expect(fileCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery validates selected image type and server size limit', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('elbench-invalid-');
    addTearDown(() => directory.deleteSync(recursive: true));
    pickedPhoto = (File(
      '${directory.path}/document.pdf',
    )..writeAsBytesSync(_pixel)).path;
    final api = _Api()..maxBytes = 4;
    await _open(tester, api, '/community/4/materials');
    final images = find.byKey(const ValueKey('materials.upload.images'));

    await _tapWithIo(tester, images);
    expect(find.text('Choose a JPEG, PNG or WebP image.'), findsOneWidget);
    expect(api.actions, isEmpty);
    expect(find.text('Upload an image'), findsNothing);

    pickedPhoto = (File(
      '${directory.path}/large.png',
    )..writeAsBytesSync(_pixel)).path;
    await _tapWithIo(tester, images);
    expect(find.text('Choose a file up to 4 B.'), findsOneWidget);
    expect(api.actions, isEmpty);
    expect(fileCalls, isEmpty);
  });

  testWidgets('Community upload permissions still control both pickers', (
    tester,
  ) async {
    final api = _Api()..storageReady = false;
    await _open(tester, api, '/community/4/materials?upload=images');
    await tester.tap(find.byKey(const ValueKey('materials.upload.files')));
    await tester.tap(find.byKey(const ValueKey('materials.upload.images')));
    await tester.pumpAndSettle();
    expect(fileCalls, isEmpty);
    expect(photoCalls, isEmpty);
    expect(api.actions, isEmpty);
  });

  testWidgets('members without manage permission cannot upload materials', (
    tester,
  ) async {
    final api = _Api()..canManage = false;
    await _open(tester, api, '/community/4/materials?upload=images');
    expect(find.text('Upload Files'), findsNothing);
    expect(find.text('Upload Images'), findsNothing);
    expect(fileCalls, isEmpty);
    expect(photoCalls, isEmpty);
  });

  testWidgets(
    'profile editor hides identity fields and cameras open Photos',
    (tester) async {
      final api = _Api();
      await _open(tester, api, '/profile/edit');
      expect(find.byType(WebProfileEdit), findsOneWidget);
      for (final text in [
        'Student ID',
        'Name',
        'Gender',
        'Unique Student Name',
        '@123456789',
      ]) {
        expect(find.text(text), findsNothing);
      }
      expect(find.text('Major'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('profile.edit.avatar.camera')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('profile.edit.banner.camera')),
      );
      await tester.pumpAndSettle();
      expect(photoCalls, hasLength(2));
      expect(photoCalls.every((call) => call.arguments['source'] == 1), isTrue);
      expect(fileCalls, isEmpty);
      expect(api.actions, isEmpty);
      expect(find.text('Major'), findsOneWidget); // Cancel keeps the form open.
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'profile avatar chosen from camera control is saved as multipart',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('elbench-avatar-');
      addTearDown(() => directory.deleteSync(recursive: true));
      pickedPhoto = (File(
        '${directory.path}/profile.png',
      )..writeAsBytesSync(_pixel)).path;
      final api = _Api();
      await _open(tester, api, '/profile/edit');
      await _tapWithIo(
        tester,
        find.byKey(const ValueKey('profile.edit.avatar.camera')),
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(WebProfileEdit),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .join(' | '),
      );
      await _tapWithIo(tester, find.text('Save changes'));

      final saved = api.actions.single;
      expect(saved.method, 'PUT');
      expect(saved.path, '/profile');
      final photo = saved.data['avatar_upload'] as MultipartFile;
      expect(photo.filename, 'profile.png');
      expect(photo.length, _pixel.length);
      expect(saved.data['major'], 'Computer Science');
      expect(saved.data['birthdate'], '2000-03-04');
      expect(saved.data['banner_color'], '#2E855D');
      expect(saved.data.containsKey('name'), isFalse);
      expect(saved.data.containsKey('university_id'), isFalse);
      expect(saved.data.containsKey('gender'), isFalse);
      expect(fileCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile banner camera selects a photo for crop and upload', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('elbench-banner-');
    addTearDown(() => directory.deleteSync(recursive: true));
    pickedPhoto = (File(
      '${directory.path}/cover.png',
    )..writeAsBytesSync(_bannerPixels)).path;
    final api = _Api();
    await _open(tester, api, '/profile/edit');
    await _tapWithIo(
      tester,
      find.byKey(const ValueKey('profile.edit.banner.camera')),
    );
    expect(find.text('Use this banner'), findsOneWidget);
    await _tapWithIo(tester, find.text('Use this banner'));
    await _tapWithIo(tester, find.text('Save changes'));

    final saved = api.actions.single;
    expect(saved.path, '/profile');
    final photo = saved.data['banner_upload'] as MultipartFile;
    expect(photo.filename, 'banner.png');
    expect(photo.length, greaterThan(0));
    expect(saved.data['avatar_upload'], isNull);
    expect(saved.data['major'], 'Computer Science');
    expect(photoCalls.single.arguments['source'], 1);
    expect(fileCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
