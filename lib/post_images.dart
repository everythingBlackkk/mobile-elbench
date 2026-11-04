import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'image_cache.dart';
import 'web_style.dart' show svgColorFilter;

/// Pictures on community posts: up to four PNG, JPG, WebP or iPhone photos of
/// up to 10 MB each (the server enforces the same limits).
const postImageLimit = 4;
const postImageMaxBytes = 10 * 1024 * 1024;

/// The longest edge a picture is uploaded at. The platform picker scales and
/// re-encodes photos natively before Dart sees them, so a 12 MB HEIC photo
/// leaves the phone as a JPEG of a few hundred kilobytes.
const postImageUploadSize = 2048.0;
const postImageUploadQuality = 85;

/// Same line style, size and weight as the comment sticker button.
const postImageButtonSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7"><path d="M18 3a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3h12Z"/><path d="m3.5 17.5 4.8-4.8a2 2 0 0 1 2.8 0L18 19.6M14 15l1.6-1.6a2 2 0 0 1 2.8 0L21 16M15.5 8.5h.01" stroke-linecap="round" stroke-linejoin="round"/></svg>';

typedef Translate = String Function(String english, String arabic);

const _heifBrands = {
  'heic',
  'heix',
  'heim',
  'heis',
  'mif1',
  'msf1',
  'hevc',
  'hevx',
};

/// The format a file's first bytes announce (jpeg, png, webp or heif),
/// whatever its name says; null for anything else, including GIF and SVG.
String? sniffPostImage(List<int> head) {
  bool starts(List<int> bytes) =>
      head.length >= bytes.length &&
      Iterable<int>.generate(bytes.length).every((i) => head[i] == bytes[i]);
  String ascii(int from, int to) =>
      head.length < to ? '' : String.fromCharCodes(head.sublist(from, to));
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpeg';
  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'png';
  }
  if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'WEBP') return 'webp';
  if (head.length >= 16 && ascii(4, 8) == 'ftyp') {
    final boxSize =
        (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
    final brands = [ascii(8, 12)];
    for (
      var offset = 16;
      offset + 4 <= math.min(boxSize, head.length);
      offset += 4
    ) {
      brands.add(ascii(offset, offset + 4));
    }
    if (!brands.any((brand) => brand == 'avif' || brand == 'avis') &&
        brands.any(_heifBrands.contains)) {
      return 'heif';
    }
  }
  return null;
}

const _uploadExtensions = {
  'jpeg': 'jpg',
  'png': 'png',
  'webp': 'webp',
  'heif': 'heic',
};

/// One picture in the post composer: either already on the post (shown from
/// the server) or picked on this device and not yet uploaded.
class PostImageDraft {
  PostImageDraft.existing(Json this.existing) : file = null, family = null;
  PostImageDraft.picked(XFile this.file, String this.family) : existing = null;

  final Json? existing;
  final XFile? file;
  final String? family;

  int? get id => existing == null ? null : int.tryParse(value(existing!['id']));
  bool get isNew => file != null;

  /// The upload is named after its real format: the Android picker keeps the
  /// original name (IMG_1.heic) on the JPEG it re-encodes.
  Future<MultipartFile> multipart(int index) => MultipartFile.fromFile(
    file!.path,
    filename: 'photo-${index + 1}.${_uploadExtensions[family]}',
  );
}

/// Checks a picked file the way the server will: size, and a format that is
/// readable and allowed. Returns the format, or throws [ApiFailure].
Future<String> checkPostImage(XFile file, Translate t) async {
  final size = await file.length();
  if (size <= 12 || size > postImageMaxBytes) {
    throw ApiFailure(
      t(
        'Each photo must be 10 MB or smaller.',
        'كل صورة لازم تكون 10 ميجا أو أقل.',
      ),
    );
  }
  final head = <int>[];
  await for (final chunk in file.openRead(0, 64)) {
    head.addAll(chunk);
  }
  final family = sniffPostImage(head);
  if (family == null) {
    throw ApiFailure(
      t(
        'Only PNG, JPG, WebP and iPhone (HEIC) photos can be added.',
        'ينفع تضيف صور PNG و JPG و WebP وصور الآيفون (HEIC) بس.',
      ),
    );
  }
  return family;
}

/// Opens the system photo picker for up to [remaining] photos. Android hands
/// over only the chosen photos and iOS asks for photo access only if needed,
/// so no new permission or native code is involved.
Future<List<XFile>> pickPostImages({
  required Translate t,
  required int remaining,
}) async {
  if (remaining <= 0) return const [];
  try {
    final picker = ImagePicker();
    if (remaining == 1) {
      final one = await picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
        maxWidth: postImageUploadSize,
        maxHeight: postImageUploadSize,
        imageQuality: postImageUploadQuality,
      );
      return one == null ? const [] : [one];
    }
    final picked = await picker.pickMultiImage(
      requestFullMetadata: false,
      maxWidth: postImageUploadSize,
      maxHeight: postImageUploadSize,
      imageQuality: postImageUploadQuality,
      limit: remaining,
    );
    return picked.take(remaining).toList();
  } on PlatformException catch (error) {
    if (error.code.contains('denied') || error.code.contains('restricted')) {
      throw ApiFailure(
        t(
          'Photo access is off. Allow ElBench to access selected photos in your device Settings, then try again.',
          'الوصول للصور متوقف. اسمح لتطبيق ElBench بالوصول للصور المختارة من إعدادات الجهاز ثم حاول مرة أخرى.',
        ),
      );
    }
    throw ApiFailure(
      t(
        'Could not open the photo picker. Please try again.',
        'تعذر فتح الصور. حاول مرة أخرى.',
      ),
    );
  }
}

/// The request fields for a post's pictures. Multipart requests need indexed
/// names (images[0]); a JSON body can carry the removals as a list.
Future<Json> postImageFields(
  List<PostImageDraft> drafts,
  Iterable<int> removed,
) async {
  final picked = drafts.where((draft) => draft.isNew).toList();
  final removals = removed.toList();
  return {
    for (var i = 0; i < picked.length; i++)
      'images[$i]': await picked[i].multipart(i),
    if (picked.isEmpty && removals.isNotEmpty) 'remove_images': removals,
    if (picked.isNotEmpty)
      for (var i = 0; i < removals.length; i++)
        'remove_images[$i]': removals[i],
  };
}

/// Whether a request carries a file and so goes out as multipart.
bool carriesUpload(Json data) =>
    data.values.any((field) => field is MultipartFile);

List<Json> postImages(Json post) =>
    rows(post['images']).take(postImageLimit).toList();

Color _placeholder(Json image, Color fallback) {
  final hex = value(image['placeholder']);
  final parsed = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)
      ? int.tryParse(hex.substring(1), radix: 16)
      : null;
  return parsed == null ? fallback : Color(0xff000000 | parsed);
}

double _ratio(Json image) {
  final width = double.tryParse(value(image['width'])) ?? 0;
  final height = double.tryParse(value(image['height'])) ?? 0;
  return width > 0 && height > 0 ? width / height : 4 / 3;
}

/// A post's pictures in a 1-4 tile grid. Every tile has its final size before
/// its picture arrives (from the stored width and height), painted in the
/// picture's average colour, so the feed never jumps while scrolling. Each
/// picture is decoded at the tile's size in device pixels, not at its full
/// size, keeping memory flat however many posts are on screen.
class PostImageGrid extends StatelessWidget {
  const PostImageGrid({
    super.key,
    required this.images,
    required this.onOpen,
    required this.t,
    this.radius = 12,
  });

  final List<Json> images;
  final void Function(int index) onOpen;
  final Translate t;
  final double radius;

  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final count = math.min(images.length, postImageLimit);
    if (count == 0) return const SizedBox.shrink();
    final media = MediaQuery.maybeOf(context);
    final ratio = media?.devicePixelRatio ?? 3;
    final screenHeight = media?.size.height ?? 800;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (media?.size.width ?? 400);
        Widget tile(int index, double w, double h) => _PostImageTile(
          image: images[index],
          width: w,
          height: h,
          devicePixelRatio: ratio,
          label: t(
            'Open photo ${index + 1} of $count',
            'افتح الصورة ${index + 1} من $count',
          ),
          onTap: () => onOpen(index),
        );
        final half = (width - gap) / 2;
        final Widget grid = switch (count) {
          1 => tile(
            0,
            width,
            (width / _ratio(images[0])).clamp(
              160.0,
              math.min(560.0, screenHeight * .7),
            ),
          ),
          2 => Row(
            children: [
              tile(0, half, half * 5 / 4),
              const SizedBox(width: gap),
              tile(1, half, half * 5 / 4),
            ],
          ),
          3 => Column(
            children: [
              tile(0, width, width / 2),
              const SizedBox(height: gap),
              Row(
                children: [
                  tile(1, half, half),
                  const SizedBox(width: gap),
                  tile(2, half, half),
                ],
              ),
            ],
          ),
          _ => Column(
            children: [
              Row(
                children: [
                  tile(0, half, half),
                  const SizedBox(width: gap),
                  tile(1, half, half),
                ],
              ),
              const SizedBox(height: gap),
              Row(
                children: [
                  tile(2, half, half),
                  const SizedBox(width: gap),
                  tile(3, half, half),
                ],
              ),
            ],
          ),
        };
        // Its own layer: scrolling moves the grid without repainting it.
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: grid,
          ),
        );
      },
    );
  }
}

class _PostImageTile extends StatelessWidget {
  const _PostImageTile({
    required this.image,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    required this.label,
    required this.onTap,
  });

  final Json image;
  final double width, height, devicePixelRatio;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = value(image['url']);
    return Semantics(
      button: true,
      image: true,
      label: label,
      child: GestureDetector(
        key: ValueKey('post.image.${image['id']}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: _placeholder(image, scheme.surfaceContainerHighest),
            child: url.isEmpty
                ? const SizedBox.expand()
                : Image(
                    image: CachedNetworkImage(
                      url,
                      cacheKey: _key(image, 'cache_key'),
                      width: (width * devicePixelRatio).ceil(),
                      height: (height * devicePixelRatio).ceil(),
                    ),
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    frameBuilder: _fadeIn,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

String? _key(Json image, String field) {
  final key = value(image[field]);
  return key.isEmpty ? null : key;
}

/// Fades a picture in once when it arrives from the network; a picture that
/// is already decoded (scrolling back) appears at once.
Widget _fadeIn(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    child: child,
  );
}

/// Opens the full-screen viewer at [index].
Future<void> openPostImageViewer(
  BuildContext context, {
  required List<Json> images,
  required int index,
  required Translate t,
}) {
  final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration(milliseconds: reduced ? 0 : 180),
      reverseTransitionDuration: Duration(milliseconds: reduced ? 0 : 160),
      pageBuilder: (context, animation, secondaryAnimation) =>
          PostImageViewer(images: images, initialIndex: index, t: t),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Full-screen pictures: swipe sideways between them, pinch or double-tap to
/// zoom, swipe down or tap close to leave. The feed-sized copy (usually
/// cached already) shows at once; the sharper copy replaces it when it has
/// arrived.
class PostImageViewer extends StatefulWidget {
  const PostImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.t,
  });

  final List<Json> images;
  final int initialIndex;
  final Translate t;

  @override
  State<PostImageViewer> createState() => _PostImageViewerState();
}

class _PostImageViewerState extends State<PostImageViewer> {
  late final PageController pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int current = widget.initialIndex;
  bool zoomed = false;
  double drag = 0;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void _dragEnd(DragEndDetails details) {
    if (drag.abs() > 120 || (details.primaryVelocity ?? 0).abs() > 900) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    final fade = (1 - drag.abs() / 400).clamp(0.3, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragUpdate: zoomed
                ? null
                : (details) => setState(() => drag += details.delta.dy),
            onVerticalDragEnd: zoomed ? null : _dragEnd,
            child: Transform.translate(
              offset: Offset(0, drag),
              child: PageView.builder(
                controller: pages,
                physics: zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: count,
                onPageChanged: (index) => setState(() => current = index),
                itemBuilder: (context, index) => _ZoomablePicture(
                  key: ValueKey('post.viewer.${widget.images[index]['id']}'),
                  image: widget.images[index],
                  label: widget.t(
                    'Photo ${index + 1} of $count',
                    'الصورة ${index + 1} من $count',
                  ),
                  onZoomChanged: (value) {
                    if (value != zoomed) setState(() => zoomed = value);
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('post.viewer.close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .14),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: widget.t('Close', 'اقفل'),
                  ),
                  const Spacer(),
                  if (count > 1)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: Text(
                        '${current + 1} / $count',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePicture extends StatefulWidget {
  const _ZoomablePicture({
    super.key,
    required this.image,
    required this.label,
    required this.onZoomChanged,
  });

  final Json image;
  final String label;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePicture> createState() => _ZoomablePictureState();
}

class _ZoomablePictureState extends State<_ZoomablePicture> {
  final transform = TransformationController();
  Offset? _doubleTap;

  @override
  void initState() {
    super.initState();
    transform.addListener(_reportZoom);
  }

  void _reportZoom() =>
      widget.onZoomChanged(transform.value.getMaxScaleOnAxis() > 1.01);

  @override
  void dispose() {
    transform.removeListener(_reportZoom);
    transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (transform.value.getMaxScaleOnAxis() > 1.01) {
      transform.value = Matrix4.identity();
      return;
    }
    final point = _doubleTap ?? Offset.zero;
    const scale = 2.5;
    transform.value = Matrix4.identity()
      ..translateByDouble(
        -point.dx * (scale - 1),
        -point.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final media = MediaQuery.of(context);
    final ratio = _ratio(image);
    // Decode no larger than the screen can show at the deepest zoom step
    // that still looks sharp; the server's copy is at most 2048 px anyway.
    final target = (media.size.longestSide * media.devicePixelRatio)
        .clamp(1.0, 2048.0)
        .ceil();
    final display = value(image['url']);
    final full = value(image['full_url']);
    return Semantics(
      image: true,
      label: widget.label,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTap = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: transform,
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: _placeholder(image, Colors.black)),
                  if (display.isNotEmpty)
                    Image(
                      image: CachedNetworkImage(
                        display,
                        cacheKey: _key(image, 'cache_key'),
                        width: (media.size.width * media.devicePixelRatio)
                            .ceil(),
                        cover: false,
                      ),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  if (full.isNotEmpty && full != display)
                    Image(
                      image: CachedNetworkImage(
                        full,
                        cacheKey: _key(image, 'full_cache_key'),
                        width: target,
                        height: target,
                        cover: false,
                      ),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      frameBuilder: _fadeIn,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The composer's photo button, matching the comment sticker button.
class PostImageButton extends StatelessWidget {
  const PostImageButton({
    super.key,
    required this.onTap,
    required this.label,
    required this.color,
  });

  final VoidCallback? onTap;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: Tooltip(
      message: label,
      child: InkWell(
        key: const ValueKey('post.editor.addImages'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: onTap == null ? .4 : 1,
              child: SvgPicture.string(
                postImageButtonSvg,
                width: 24,
                height: 24,
                colorFilter: svgColorFilter(color),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The pictures chosen in the composer, each with a remove button.
class PostImageDrafts extends StatelessWidget {
  const PostImageDrafts({
    super.key,
    required this.drafts,
    required this.pending,
    required this.onRemove,
    required this.t,
  });

  final List<PostImageDraft> drafts;
  final int pending;
  final void Function(PostImageDraft draft) onRemove;
  final Translate t;

  static const size = 72.0;

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty && pending == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final cache = (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3))
        .ceil();
    Widget frame(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(color: scheme.surfaceContainerHighest, child: child),
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < drafts.length; i++)
          Stack(
            key: ValueKey(
              'post.editor.image.${drafts[i].id ?? drafts[i].file!.path}',
            ),
            children: [
              frame(
                drafts[i].isNew
                    ? Image.file(
                        File(drafts[i].file!.path),
                        fit: BoxFit.cover,
                        cacheWidth: cache,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(
                            (_uploadExtensions[drafts[i].family] ?? '')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : networkImage(
                        value(drafts[i].existing!['url']),
                        cacheKey: _key(drafts[i].existing!, 'cache_key'),
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
              PositionedDirectional(
                top: 4,
                end: 4,
                child: Semantics(
                  button: true,
                  label: t('Remove photo ${i + 1}', 'إزالة الصورة ${i + 1}'),
                  child: GestureDetector(
                    key: ValueKey('post.editor.removeImage.$i'),
                    onTap: () => onRemove(drafts[i]),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0x9E000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        for (var i = 0; i < pending; i++)
          frame(
            Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
