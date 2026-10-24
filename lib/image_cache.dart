import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Disk cache for remote images (avatars, banners, stickers, community art).
///
/// Flutter's [NetworkImage] caches decoded images in memory only, so every
/// launch downloaded every avatar again although the server allows a week of
/// caching. Files live in the platform cache directory, which the OS may
/// purge; entries expire after [maxAge] and the folder is trimmed to
/// [maxBytes].
class ImageDiskCache {
  ImageDiskCache._();
  static final instance = ImageDiskCache._();

  static const maxAge = Duration(days: 7);
  static const maxBytes = 80 * 1024 * 1024;

  final HttpClient _client = _configure(HttpClient());

  static HttpClient _configure(HttpClient client) {
    // Test doubles installed through HttpOverrides may not implement these.
    try {
      client
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 90)
        ..maxConnectionsPerHost = 6
        ..autoUncompress = true;
    } on NoSuchMethodError {
      // Keep the defaults.
    }
    return client;
  }

  final _pending = <String, Future<Uint8List>>{};
  Future<Directory>? _directory;
  bool _trimmed = false;

  Future<Directory> _folder() => _directory ??= () async {
    final base = await getApplicationCacheDirectory();
    final folder = Directory('${base.path}/elbench-images');
    await folder.create(recursive: true);
    return folder;
  }();

  /// 64-bit FNV-1a of the URL; file names never contain the URL itself.
  static String _name(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${hash.toUnsigned(64).toRadixString(16)}-${url.length}';
  }

  Future<Uint8List> load(String url) =>
      _pending[url] ??= _load(url).whenComplete(() => _pending.remove(url));

  Future<Uint8List> _load(String url) async {
    File? file;
    try {
      file = File('${(await _folder()).path}/${_name(url)}');
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file &&
          stat.size > 0 &&
          DateTime.now().difference(stat.modified) < maxAge) {
        return await file.readAsBytes();
      }
    } catch (_) {
      // A missing or unreadable cache must never block the network path.
    }
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: Uri.parse(url),
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(
      response,
    ).timeout(const Duration(seconds: 45));
    if (bytes.isEmpty) {
      throw NetworkImageLoadException(statusCode: 204, uri: Uri.parse(url));
    }
    if (file != null) {
      final target = file;
      // Write beside, then rename, so a crash never leaves a partial image.
      unawaited(() async {
        try {
          final temporary = File('${target.path}.part');
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(target.path);
          _trimOnce();
        } catch (_) {}
      }());
    }
    return bytes;
  }

  void _trimOnce() {
    if (_trimmed) return;
    _trimmed = true;
    unawaited(() async {
      try {
        final folder = await _folder();
        final files = <File, FileStat>{};
        await for (final entity in folder.list()) {
          if (entity is File) files[entity] = await entity.stat();
        }
        var total = files.values.fold<int>(0, (sum, stat) => sum + stat.size);
        final oldestFirst = files.entries.toList()
          ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
        for (final entry in oldestFirst) {
          final expired =
              DateTime.now().difference(entry.value.modified) > maxAge;
          if (!expired && total <= maxBytes) break;
          total -= entry.value.size;
          await entry.key.delete();
        }
      } catch (_) {}
    }());
  }
}

/// An [ImageProvider] backed by [ImageDiskCache]. With a target size
/// (device pixels) the image is decoded no larger than needed, keeping its
/// aspect ratio: [cover] fills the target (avatars, banners), otherwise it
/// fits inside it (stickers). Resizing happens here rather than through
/// [ResizeImage], so each image has one cache key that a failure can evict.
@immutable
class CachedNetworkImage extends ImageProvider<CachedNetworkImage> {
  const CachedNetworkImage(
    this.url, {
    this.scale = 1,
    this.width,
    this.height,
    this.cover = true,
  });
  final String url;
  final double scale;
  final int? width, height;
  final bool cover;

  @override
  Future<CachedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _codec(key, decode),
    scale: key.scale,
    debugLabel: key.url,
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
    ],
  );

  ui.TargetImageSize _target(int intrinsicWidth, int intrinsicHeight) {
    if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      return const ui.TargetImageSize();
    }
    final scales = [
      if (width != null) width! / intrinsicWidth,
      if (height != null) height! / intrinsicHeight,
    ];
    if (scales.isEmpty) return const ui.TargetImageSize();
    var factor = cover
        ? scales.reduce((a, b) => a > b ? a : b)
        : scales.reduce((a, b) => a < b ? a : b);
    if (factor >= 1) return const ui.TargetImageSize();
    factor = factor <= 0 ? 1 / intrinsicWidth : factor;
    return ui.TargetImageSize(
      width: (intrinsicWidth * factor).ceil().clamp(1, intrinsicWidth),
      height: (intrinsicHeight * factor).ceil().clamp(1, intrinsicHeight),
    );
  }

  Future<ui.Codec> _codec(
    CachedNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await ImageDiskCache.instance.load(key.url);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return key.width == null && key.height == null
          ? decode(buffer)
          : decode(buffer, getTargetSize: key._target);
    } catch (_) {
      // Let the image cache retry this URL later instead of keeping a failure.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImage &&
      other.url == url &&
      other.scale == scale &&
      other.width == width &&
      other.height == height &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(url, scale, width, height, cover);

  @override
  String toString() =>
      'CachedNetworkImage("$url", ${width ?? '-'}x${height ?? '-'}, cover: $cover)';
}

/// Drop-in replacement for [Image.network] that uses the disk cache and
/// decodes no larger than needed. Without explicit cache dimensions, a fixed
/// box (stickers, thumbnails) decodes at its own size.
Widget networkImage(
  String url, {
  double? width,
  double? height,
  BoxFit? fit,
  int? cacheWidth,
  int? cacheHeight,
  String? semanticLabel,
  ImageErrorWidgetBuilder? errorBuilder,
}) => Builder(
  builder: (context) {
    var targetWidth = cacheWidth, targetHeight = cacheHeight;
    if (targetWidth == null && targetHeight == null) {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
      if (width != null && width.isFinite) {
        targetWidth = (width * ratio).ceil();
      }
      if (height != null && height.isFinite) {
        targetHeight = (height * ratio).ceil();
      }
    }
    return Image(
      image: CachedNetworkImage(
        url,
        width: targetWidth,
        height: targetHeight,
        cover: fit == BoxFit.cover || fit == BoxFit.fill,
      ),
      width: width,
      height: height,
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: errorBuilder,
      gaplessPlayback: true,
    );
  },
);
