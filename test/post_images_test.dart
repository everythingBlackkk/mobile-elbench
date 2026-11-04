import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:elbench/api.dart';
import 'package:elbench/image_cache.dart';
import 'package:elbench/main.dart';
import 'package:elbench/post_images.dart';
import 'package:elbench/settings.dart';
import 'package:elbench/web_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _photos = MethodChannel('plugins.flutter.io/image_picker');
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);
final _gif = base64Decode(
  'R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==',
);

Json _image(int id, int width, int height) => {
  'id': id,
  'width': width,
  'height': height,
  'placeholder': '#336699',
  'url': 'https://r2.example.test/post-images/$id/w1280.webp?sig=a',
  'full_url': 'https://r2.example.test/post-images/$id/w2048.webp?sig=a',
  'cache_key': 'post-image:$id:1280',
  'full_cache_key': 'post-image:$id:2048',
};

class _Api extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://post-images.example.test');
  final user = <String, dynamic>{'id': 7, 'name': 'Mariam', 'role': 'student'};
  final sent = <({String method, String path, Json data})>[];
  List<Json> postImages = [];

  @override
  Future<Json> get(String path) async {
    final uri = Uri.parse(path);
    if (uri.path == '/community') {
      return {
        'screen': 'community.index',
        'user': user,
        'features': {'community': true},
        'counts': {'notifications': 0, 'inbox': 0},
        'data': {
          'search': '',
          'has_communities': true,
          'communities': [],
          'featured_events': [],
          'scheduleSummary': {'date': '2026-11-04', 'entries': []},
          'posts': {
            'data': [
              {
                'id': 41,
                'content': '',
                'author': user,
                'user_id': 7,
                'created_at': '2026-11-04T10:00:00Z',
                'comments_count': 0,
                'images': postImages,
              },
            ],
            'current_page': 1,
            'next_page_url': null,
          },
        },
      };
    }
    return {
      'user': user,
      'features': {'community': true},
      'counts': {'notifications': 0, 'inbox': 0},
    };
  }

  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    sent.add((method: method, path: Uri.parse(path).path, data: {...data}));
    return {};
  }

  @override
  Future<void> clearSession() async {}
}

Future<_Api> _open(WidgetTester tester, {List<Json> images = const []}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appearance.language': 'en'});
  final settings = AppSettings();
  await settings.load();
  final api = _Api()..postImages = images;
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

/// Grid tiles as laid out, with the size each picture is decoded at.
List<({Size tile, int? decodeWidth, int? decodeHeight, String? key})> _tiles(
  WidgetTester tester,
) => [
  for (final element in find.byType(Image).evaluate())
    if ((element.widget as Image).image case final CachedNetworkImage image)
      if (image.cacheKey?.startsWith('post-image:') ?? false)
        (
          tile: tester.getSize(find.byWidget(element.widget)),
          decodeWidth: image.width,
          decodeHeight: image.height,
          key: image.cacheKey,
        ),
];

Future<void> _grid(WidgetTester tester, List<Json> images) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1200, 2700);
  addTearDown(tester.view.reset);
  addTearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: PostImageView(
              images: images,
              t: (english, _) => english,
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('only real PNG, JPEG, WebP and HEIC bytes are recognised', () {
    List<int> bytes(String text) => latin1.encode(text);
    expect(sniffPostImage([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]), 'jpeg');
    expect(sniffPostImage(_png), 'png');
    expect(sniffPostImage(bytes('RIFF\x00\x00\x00\x00WEBPVP8 ')), 'webp');
    expect(
      sniffPostImage(bytes('\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic')),
      'heif',
    );
    // AVIF also lists mif1, but its own brand decides.
    expect(
      sniffPostImage(
        bytes('\x00\x00\x00\x1Cftypavif\x00\x00\x00\x00avifmif1miaf'),
      ),
      isNull,
    );
    expect(sniffPostImage(_gif), isNull);
    expect(
      sniffPostImage(bytes('<svg xmlns="http://www.w3.org/2000/svg">')),
      isNull,
    );
    expect(sniffPostImage(bytes('<?php system(\$_GET["c"]); ?>')), isNull);
    expect(sniffPostImage(const []), isNull);
  });

  test('picked photos upload under names that match their contents', () async {
    final folder = await Directory.systemTemp.createTemp('post-images');
    addTearDown(() => folder.delete(recursive: true));
    // The Android picker keeps the original name on the JPEG it re-encodes.
    final file = File('${folder.path}/scaled_IMG_1.heic')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(40, 0)]);
    final drafts = [
      PostImageDraft.existing(_image(5, 10, 10)),
      PostImageDraft.picked(XFile(file.path), 'jpeg'),
    ];

    final multipart = await postImageFields(drafts, [9, 12]);
    expect(multipart.keys, [
      'images[0]',
      'remove_images[0]',
      'remove_images[1]',
    ]);
    expect((multipart['images[0]'] as MultipartFile).filename, 'photo-1.jpg');
    expect(carriesUpload(multipart), isTrue);

    final json = await postImageFields([drafts.first], [9]);
    expect(json, {
      'remove_images': [9],
    });
    expect(carriesUpload(json), isFalse);
    expect(await postImageFields([drafts.first], const []), isEmpty);
  });

  test('a signed link that changes keeps the same cached picture', () {
    const first = CachedNetworkImage(
      'https://r2.example.test/a?sig=1',
      cacheKey: 'post-image:a:1280',
      width: 600,
    );
    const renewed = CachedNetworkImage(
      'https://r2.example.test/a?sig=2',
      cacheKey: 'post-image:a:1280',
      width: 600,
    );
    expect(first, renewed);
    expect(first.hashCode, renewed.hashCode);
    expect(
      const CachedNetworkImage('https://r2.example.test/a?sig=1'),
      isNot(const CachedNetworkImage('https://r2.example.test/a?sig=2')),
    );
  });

  testWidgets('one picture keeps its shape and decodes at tile size', (
    tester,
  ) async {
    await _grid(tester, [_image(1, 2048, 1024)]);
    final tiles = _tiles(tester);
    expect(tiles, hasLength(1));
    expect(tiles.single.tile, const Size(400, 200));
    expect((tiles.single.decodeWidth, tiles.single.decodeHeight), (1200, 600));
    expect(tiles.single.key, 'post-image:1:1280');

    // A tall phone photo is capped instead of filling several screens.
    await _grid(tester, [_image(2, 1024, 4096)]);
    expect(_tiles(tester).single.tile, const Size(400, 560));
  });

  testWidgets('only the first picture is shown if a post somehow has more', (
    tester,
  ) async {
    await _grid(tester, [_image(1, 800, 600), _image(2, 600, 800)]);
    expect(_tiles(tester).map((t) => t.key), ['post-image:1:1280']);
  });

  testWidgets(
    'the feed shows a picture-only post and opens the full-screen viewer',
    (tester) async {
      final images = [_image(2, 1600, 1200)];
      await _open(tester, images: images);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('post.image.2')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(WebHome),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post.images.41')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('post.image.2')));
      await tester.pumpAndSettle();
      expect(find.byType(PostImageViewer), findsOneWidget);
      // One photo: no counter.
      expect(find.textContaining(' / '), findsNothing);

      await tester.tap(find.byKey(const ValueKey('post.viewer.close')));
      await tester.pumpAndSettle();
      expect(find.byType(PostImageViewer), findsNothing);
    },
  );

  group('composer', () {
    late Directory folder;
    final calls = <MethodCall>[];
    List<String> picked = [];

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('post-composer');
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_photos, (call) async {
            calls.add(call);
            return picked.isEmpty ? null : picked.removeAt(0);
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_photos, null);
      await folder.delete(recursive: true);
    });

    testWidgets(
      'picks one photo beside the text, refuses GIF and posts a photo only',
      (tester) async {
        final png = File('${folder.path}/IMG_2.HEIC')..writeAsBytesSync(_png);
        final gif = File('${folder.path}/funny.gif')..writeAsBytesSync(_gif);
        picked = [gif.path, png.path];
        final api = await _open(tester);

        await tester.tap(find.text('What’s on your mind?').first);
        await tester.pumpAndSettle();
        expect(find.byType(WebPostEditor), findsOneWidget);
        final publish = find.byKey(const ValueKey('post.editor.publish'));
        expect(tester.widget<FilledButton>(publish).onPressed, isNull);
        final add = find.byKey(const ValueKey('post.editor.addImages'));
        expect(tester.getSize(add), const Size(36, 44));

        Future<void> pick() async {
          await tester.runAsync(() async {
            await tester.tap(add);
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
        }

        await pick();
        expect(calls.single.method, 'pickImage');
        expect(calls.single.arguments['maxWidth'], postImageUploadSize);
        expect(calls.single.arguments['maxHeight'], postImageUploadSize);
        expect(calls.single.arguments['imageQuality'], postImageUploadQuality);
        expect(
          find.text(
            'Only PNG, JPG, WebP and iPhone (HEIC) photos can be added.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('post.editor.image.${gif.path}')),
          findsNothing,
        );
        expect(tester.widget<FilledButton>(publish).onPressed, isNull);

        await pick();
        expect(
          find.byKey(ValueKey('post.editor.image.${png.path}')),
          findsOneWidget,
        );
        // One photo per post: the button turns off until it is removed.
        expect(tester.widget<InkWell>(add).onTap, isNull);
        expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);

        await tester.runAsync(() async {
          await tester.tap(publish);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();

        final request = api.sent.single;
        expect(request.method, 'POST');
        expect(request.path, '/community/posts');
        expect(request.data['content'], '');
        final upload = request.data['images[0]'] as MultipartFile;
        // Named after its real contents (PNG), not the misleading .HEIC name.
        expect(upload.filename, 'photo-1.png');
        expect(request.data.containsKey('images[1]'), isFalse);
        expect(find.byType(WebPostEditor), findsNothing);
      },
    );

    testWidgets('removing the photo turns the photo button back on', (
      tester,
    ) async {
      picked = [(File('${folder.path}/p.png')..writeAsBytesSync(_png)).path];
      await _open(tester);
      await tester.tap(find.text('What’s on your mind?').first);
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('post.editor.addImages'));

      await tester.runAsync(() async {
        await tester.tap(add);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(tester.widget<InkWell>(add).onTap, isNull);
      await tester.tap(find.byKey(const ValueKey('post.editor.removeImage.0')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('post.editor.removeImage.0')),
        findsNothing,
      );
      expect(tester.widget<InkWell>(add).onTap, isNotNull);
    });
  });
}
