import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:elbench/api.dart';
import 'package:elbench/main.dart';
import 'package:elbench/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

ResponseBody _json(Json body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

class _UploadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final uploaded = <Uint8List>[];
  bool failDuringUpload = false;
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'GET') return _json({'csrf_token': 'upload-csrf'});
    final bytes = BytesBuilder();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
        if (failDuringUpload) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
      }
    }
    uploaded.add(bytes.takeBytes());
    return _json(
      status == 422
          ? {
              'message': 'The image must be smaller.',
              'errors': {
                'avatar_upload': ['The image must be smaller.'],
              },
            }
          : {'saved': true},
      status: status,
    );
  }

  @override
  void close({bool force = false}) {}
}

MultipartFile _image() => MultipartFile.fromStream(
  () => Stream<List<int>>.fromIterable([
    List.filled(1024, 65),
    List.filled(2048, 66),
    List.filled(1024, 67),
  ]),
  4096,
  filename: 'profile.jpg',
);

class _SendOnlyApi extends MobileApi {
  @override
  Uri get baseUri => Uri.parse('https://uploads.example.test');
  int sends = 0, clears = 0;
  @override
  Future<Json> get(String path) async => {};
  @override
  Future<Json> send(String method, String path, [Json data = const {}]) async {
    sends++;
    return {'legacy': true};
  }

  @override
  Future<void> clearSession() async {
    clears++;
  }
}

class _ProgressApi extends _SendOnlyApi {
  final response = Completer<Json>();
  String? sentPath;
  @override
  Future<Json> sendWithProgress(
    String method,
    String path,
    Json data, {
    required UploadProgress onSendProgress,
  }) {
    sentPath = path;
    onSendProgress(32, 128);
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'multipart reports real consumed bytes while retaining CSRF and method spoofing',
    () async {
      final adapter = _UploadAdapter();
      final api = LaravelApi(
        baseUrl: 'https://uploads.example.test',
        client: Dio()..httpClientAdapter = adapter,
      );
      final progress = <(int, int)>[];

      final response = await api.sendWithProgress('PUT', '/profile', {
        'avatar_upload': _image(),
        'city': 'Cairo',
      }, onSendProgress: (sent, total) => progress.add((sent, total)));

      expect(response['saved'], isTrue);
      expect(adapter.requests.map((r) => r.uri.path), [
        '/mobile/session',
        '/profile',
      ]);
      expect(adapter.requests.first.onSendProgress, isNull);
      final upload = adapter.requests.last;
      expect(upload.method, 'POST');
      expect(upload.headers['X-CSRF-TOKEN'], 'upload-csrf');
      expect(
        (upload.data as FormData).fields.map(
          (entry) => (entry.key, entry.value),
        ),
        contains(('_method', 'PUT')),
      );
      expect((upload.data as FormData).files.single.key, 'avatar_upload');
      final length = adapter.uploaded.single.length;
      expect(length, greaterThan(4096));
      expect(progress.length, greaterThan(2));
      expect(progress.last, (length, length));
      expect(progress.any((p) => p.$1 < p.$2), isTrue);
      for (var i = 0; i < progress.length; i++) {
        expect(progress[i].$2, length);
        expect(progress[i].$1, greaterThan(i == 0 ? 0 : progress[i - 1].$1));
      }
    },
  );

  test(
    'a transmitted upload can fail validation without changing field errors',
    () async {
      final adapter = _UploadAdapter()..status = 422;
      final api = LaravelApi(
        baseUrl: 'https://uploads.example.test',
        client: Dio()..httpClientAdapter = adapter,
      );
      final progress = <(int, int)>[];

      await expectLater(
        api.sendWithProgress(
          'POST',
          '/community/4/materials',
          {'file': _image()},
          onSendProgress: (sent, total) => progress.add((sent, total)),
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.status, 'status', 422).having(
            (e) => e.fields['avatar_upload'],
            'field error',
            ['The image must be smaller.'],
          ),
        ),
      );

      expect(progress.last.$1, adapter.uploaded.single.length);
      expect(progress.last.$1, progress.last.$2);
    },
  );

  test(
    'interrupted upload never invents completion and the action queue recovers',
    () async {
      final adapter = _UploadAdapter()..failDuringUpload = true;
      final api = LaravelApi(
        baseUrl: 'https://uploads.example.test',
        client: Dio()..httpClientAdapter = adapter,
      );
      final progress = <(int, int)>[];

      await expectLater(
        api.sendWithProgress(
          'PATCH',
          '/profile',
          {'banner_upload': _image()},
          onSendProgress: (sent, total) => progress.add((sent, total)),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.connection,
          ),
        ),
      );

      expect(progress, isNotEmpty);
      expect(progress.last.$1, lessThan(progress.last.$2));
      adapter.failDuringUpload = false;
      expect(await api.send('POST', '/follow-up', {'value': 1}), {
        'saved': true,
      });
      expect(adapter.requests.last.onSendProgress, isNull);
    },
  );

  test(
    'send-only clients remain compatible without fabricated progress',
    () async {
      final api = _SendOnlyApi();
      final progress = <(int, int)>[];

      expect(
        await api.sendWithProgress(
          'POST',
          '/upload',
          {},
          onSendProgress: (sent, total) => progress.add((sent, total)),
        ),
        {'legacy': true},
      );

      expect(api.sends, 1);
      expect(progress, isEmpty);
    },
  );

  test(
    'controller progress actions preserve localization, mutations and invalidation',
    () async {
      final api = _ProgressApi();
      final c = AppController(
        api,
        AppSettings(language: 'en'),
        GlobalKey<NavigatorState>(),
        enablePush: false,
      );
      addTearDown(c.dispose);
      c.absorb({
        'user': {'id': 7},
        'counts': {'notifications': 1, 'inbox': 0},
      });
      final generation = c.cacheGeneration;
      final progress = <(int, int)>[];

      final action = c.actionWithProgress('PUT', '/profile', {
        'avatar_upload': 'test-file',
      }, onSendProgress: (sent, total) => progress.add((sent, total)));
      expect(c.mutationEpoch, 1);
      api.response.complete({
        'user': {'id': 7},
        'counts': {'notifications': 2, 'inbox': 0},
        'message': 'Saved',
      });
      final response = await action;

      expect(api.sentPath, '/profile?lang=en');
      expect(progress, [(32, 128)]);
      expect(c.mutationEpoch, 2);
      expect(c.cacheGeneration, generation + 1);
      expect(c.counts['notifications'], 2);
      expect(response['message'], 'Saved');
    },
  );

  test(
    'upload response cannot replace a session that changed in flight',
    () async {
      final api = _ProgressApi();
      final c = AppController(
        api,
        AppSettings(language: 'en'),
        GlobalKey<NavigatorState>(),
        enablePush: false,
      );
      addTearDown(c.dispose);
      c.absorb({
        'user': {'id': 7},
      });
      final action = c.actionWithProgress(
        'POST',
        '/upload',
        {},
        onSendProgress: (_, _) {},
      );
      c.absorb({
        'user': {'id': 9},
      });
      final generation = c.cacheGeneration;

      api.response.complete({
        'user': {'id': 7},
        'message': 'Old response',
      });
      await action;

      expect(c.user?['id'], 9);
      expect(c.cacheGeneration, generation);
    },
  );

  test('expired upload action retains existing sign-out handling', () async {
    final api = _ProgressApi();
    final c = AppController(
      api,
      AppSettings(language: 'en'),
      GlobalKey<NavigatorState>(),
      enablePush: false,
    );
    addTearDown(c.dispose);
    c.absorb({
      'user': {'id': 7},
    });
    final action = c.actionWithProgress(
      'PUT',
      '/profile',
      {},
      onSendProgress: (_, _) {},
    );

    api.response.completeError(const ApiFailure('Expired', status: 419));
    await expectLater(
      action,
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 419)),
    );

    expect(c.user, isNull);
    expect(api.clears, 1);
  });
}
