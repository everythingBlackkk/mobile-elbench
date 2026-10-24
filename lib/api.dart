import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> rows(dynamic value) {
  if (value is Map) value = value['data'];
  return value is List ? value.whereType<Map>().map(object).toList() : [];
}

String value(dynamic v, [String fallback = '']) => v == null ? fallback : '$v';
bool yes(dynamic v) => v == true || v == 1 || v == '1';

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        '${entry.key}': _cloneJsonValue(entry.value),
    };
  }
  if (value is List) {
    return [for (final item in value) _cloneJsonValue(item)];
  }
  return value;
}

Json cloneJsonMap(Json source) => _cloneJsonValue(source) as Json;

bool deepJsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !deepJsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

enum ApiFailureKind { general, connection, timeout }

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.status,
    this.fields = const {},
    this.body = const {},
    this.kind = ApiFailureKind.general,
  });
  final String message;
  final int? status;
  final Json fields;
  final Json body;
  final ApiFailureKind kind;
  @override
  String toString() => message;
}

/// The production site. It moved from sahbak.site to elbench.com in
/// October 2026; links and cached pages may still name the old addresses.
const productionOrigin = 'https://elbench.com';
const legacyProductionOrigins = {
  'https://sahbak.site',
  'https://www.sahbak.site',
  'https://www.elbench.com',
};

abstract class MobileApi {
  Uri get baseUri;
  Future<Json> get(String path);
  Future<Json> send(String method, String path, [Json data = const {}]);
  Future<void> clearSession();

  /// Resolve [path] against the server, mapping the production site's former
  /// and alternate addresses onto the current one.
  Uri _resolve(String path) {
    final uri = baseUri.resolve(path);
    if (baseUri.origin == productionOrigin &&
        uri.hasAuthority &&
        legacyProductionOrigins.contains(uri.origin)) {
      return uri.replace(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.port,
      );
    }
    return uri;
  }

  String media(String path) => _resolve(path).toString();
  String safePath(String path) {
    final uri = _resolve(path);
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.origin != baseUri.origin ||
        uri.userInfo.isNotEmpty) {
      throw const ApiFailure('This destination is outside the app.');
    }
    return '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}';
  }
}

/// A first-party Laravel session. Credentials and passwords are never persisted.
class LaravelApi extends MobileApi {
  LaravelApi({String? baseUrl, Dio? client, FlutterSecureStorage? storage})
    : baseUri = Uri.parse(
        baseUrl ??
            (const String.fromEnvironment('API_BASE_URL').isNotEmpty
                ? const String.fromEnvironment('API_BASE_URL')
                : (const String.fromEnvironment('API_URL').isNotEmpty
                      ? const String.fromEnvironment('API_URL')
                      : productionOrigin)),
      ),
      _dio = client ?? _keepAliveClient(),
      _storage = storage ?? const FlutterSecureStorage() {
    final loopback = [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '::1',
    ].contains(baseUri.host);
    final address = InternetAddress.tryParse(baseUri.host);
    final bytes = address?.type == InternetAddressType.IPv4
        ? address!.rawAddress
        : const <int>[];
    final privateIpv4 =
        bytes.length == 4 &&
        (bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168));
    if (baseUri.scheme != 'https' &&
        !(loopback || privateIpv4) &&
        baseUri.scheme == 'http') {
      throw ArgumentError(
        'API_BASE_URL must use HTTPS (loopback and private LAN addresses may use HTTP).',
      );
    }
    if (baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('Credentials cannot be in API_BASE_URL.');
    }
    _dio.options = BaseOptions(
      baseUrl: baseUri.origin,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (_) => true,
    );
  }

  /// Reuse TLS connections across taps. Dart closes idle sockets after 15 s
  /// by default, so a tap after a short pause paid a new TCP and TLS
  /// handshake (about 0.2 s to the production site) before every page.
  static Dio _keepAliveClient() =>
      Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()
            ..idleTimeout = const Duration(seconds: 90)
            ..maxConnectionsPerHost = 6
            ..autoUncompress = true,
        );

  @override
  final Uri baseUri;
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final Map<String, Cookie> _cookies = {};
  static final _leadingDot = RegExp(r'^\.');
  String? _csrf;
  String? _persistedCookieIdentity;
  Future<void>? _loaded;
  // Serialize requests so CSRF/session rotation cannot race a concurrent action.
  Future<void> _queue = Future.value();
  String _cookieIdentity() =>
      _cookies.entries.map((e) => '${e.key}=${e.value.value}').join(';');
  // Laravel re-encrypts its cookies on every response, so values alone do
  // not justify a secure-storage write. Names and (hourly) expiry do.
  String _cookieShape() => _cookies.entries
      .map(
        (e) =>
            '${e.key}@${e.value.expires == null ? '' : e.value.expires!.millisecondsSinceEpoch ~/ 3600000}',
      )
      .join(';');
  String? _persistedCookieShape;
  Future<void> _load() async {
    try {
      var raw = await _storage.read(key: 'elbench.session.${baseUri.origin}');
      if (raw == null && baseUri.origin == productionOrigin) {
        // Laravel's session lives on the server, so the sign-in saved under
        // the old address stays valid on the new one: move it across once.
        for (final origin in legacyProductionOrigins) {
          final key = 'elbench.session.$origin';
          final legacy = await _storage.read(key: key);
          if (legacy == null) continue;
          raw = legacy;
          await _storage.write(
            key: 'elbench.session.${baseUri.origin}',
            value: legacy,
          );
          await _storage.delete(key: key);
          break;
        }
      }
      if (raw != null) {
        for (final item in (jsonDecode(raw) as List)) {
          final cookie = Cookie.fromSetCookieValue(item as String);
          if (cookie.expires == null ||
              cookie.expires!.isAfter(DateTime.now())) {
            _cookies[cookie.name] = cookie;
          }
        }
        _persistedCookieIdentity = _cookieIdentity();
        _persistedCookieShape = _cookieShape();
      }
    } catch (_) {
      _cookies.clear();
      _persistedCookieIdentity = null;
    }
  }

  @override
  Future<void> clearSession() async {
    _cookies.clear();
    _csrf = null;
    _persistedCookieIdentity = null;
    _persistedCookieShape = null;
    await _storage.delete(key: 'elbench.session.${baseUri.origin}');
  }

  Future<void> warmUp() => _loaded ??= _load();

  @override
  Future<Json> get(String path) => _request('GET', path, const {});
  @override
  Future<Json> send(String method, String path, [Json data = const {}]) =>
      _request(method, path, data);
  Future<Json> _request(String method, String path, Json data) {
    final task = _queue.then((_) => _execute(method, path, data));
    if (method != 'GET') {
      _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
    return task;
  }

  Future<Json> _execute(String method, String path, Json data) async {
    await (_loaded ??= _load());
    if (method != 'GET' && _csrf == null) {
      await _execute('GET', '/mobile/session', {});
    }
    String destination = safePath(path);
    for (int redirects = 0; redirects < 6; redirects++) {
      final uri = baseUri.resolve(destination).replace(fragment: '');
      _cookies.removeWhere(
        (_, c) => c.expires?.isBefore(DateTime.now()) ?? false,
      );
      final headers = <String, dynamic>{
        'Accept': 'application/json',
        'User-Agent': Platform.isIOS
            ? 'ElBench/2.0.0 (iPhone; iOS)'
            : Platform.isAndroid
            ? 'ElBench/2.0.0 (Android; Mobile)'
            : 'ElBench/2.0.0 (Desktop)',
        'X-ElBench-Mobile': '1',
        if (_csrf != null) 'X-CSRF-TOKEN': _csrf,
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.values
              .where((c) => !c.secure || uri.scheme == 'https')
              .map((c) => '${c.name}=${c.value}')
              .join('; '),
      };
      Response<dynamic> response;
      try {
        // PHP accepts multipart uploads through POST with method spoofing.
        final hasFile = data.values.any((v) => v is MultipartFile);
        final payload = hasFile
            ? FormData.fromMap({
                ...data,
                if (method != 'POST') '_method': method,
              })
            : data;
        response = await _dio.request<dynamic>(
          uri.toString(),
          data: method == 'GET' ? null : payload,
          options: Options(method: hasFile ? 'POST' : method, headers: headers),
        );
      } on DioException catch (e) {
        final kind = switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => ApiFailureKind.timeout,
          DioExceptionType.connectionError => ApiFailureKind.connection,
          DioExceptionType.unknown when e.error is SocketException =>
            ApiFailureKind.connection,
          _ => ApiFailureKind.general,
        };
        throw ApiFailure(
          switch (kind) {
            ApiFailureKind.timeout =>
              'The connection timed out. Please try again.',
            ApiFailureKind.connection =>
              'Unable to connect. Check your internet connection and try again.',
            ApiFailureKind.general => 'The request could not be completed.',
          },
          kind: kind,
          status: e.response?.statusCode,
        );
      }
      for (final raw in response.headers['set-cookie'] ?? <String>[]) {
        try {
          final c = Cookie.fromSetCookieValue(raw);
          // Reject cookies scoped to another site. Requests remain same-origin.
          if (c.domain != null &&
              c.domain!.isNotEmpty &&
              c.domain!.replaceFirst(_leadingDot, '') != baseUri.host) {
            continue;
          }
          if (c.maxAge == 0 || (c.expires?.isBefore(DateTime.now()) ?? false)) {
            _cookies.remove(c.name);
          } else {
            _cookies[c.name] = c;
          }
        } catch (_) {
          /* Ignore malformed remote cookies. */
        }
      }
      final nextIdentity = _cookieIdentity();
      final nextShape = _cookieShape();
      if (nextIdentity != _persistedCookieIdentity &&
          // Sign-in, sign-out and other writes may rotate the session itself.
          (method != 'GET' || nextShape != _persistedCookieShape)) {
        _persistedCookieIdentity = nextIdentity;
        _persistedCookieShape = nextShape;
        await _storage.write(
          key: 'elbench.session.${baseUri.origin}',
          value: jsonEncode(_cookies.values.map((c) => c.toString()).toList()),
        );
      }
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400 && method == 'GET') {
        final location = response.headers.value('location');
        if (location == null) {
          throw const ApiFailure('The server returned an invalid redirect.');
        }
        destination = safePath(uri.resolve(location).toString());
        continue;
      }
      final body = object(response.data);
      if (body['csrf_token'] is String) _csrf = body['csrf_token'];
      if (status == 401 || status == 419) {
        _csrf = null;
        throw ApiFailure(
          'Your session has expired. Please sign in again.',
          status: status,
          body: body,
        );
      }
      if (status >= 400 || body['success'] == false) {
        final fields = object(body['errors']);
        final first = fields.values.firstOrNull;
        final message = value(
          body['message'],
          value(
            body['error'],
            first is List
                ? first.join('\n')
                : value(
                    first,
                    status == 403
                        ? 'You do not have access to this action.'
                        : 'The request could not be completed.',
                  ),
          ),
        );
        throw ApiFailure(message, status: status, fields: fields, body: body);
      }
      if (method == 'GET' && body['redirect_url'] is String) {
        destination = safePath(body['redirect_url']);
        continue;
      }
      if (response.data is! Map) {
        throw const ApiFailure(
          'The server does not yet support the mobile app. Please update the server.',
        );
      }
      return method == 'GET' ? {...body, 'canonical_url': destination} : body;
    }
    throw const ApiFailure('The server redirected too many times.');
  }
}
