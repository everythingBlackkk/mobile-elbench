import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'app_spinner.dart';

/// Where each page sits in the scrolling document, at scale 1.
/// Pages are as wide as the view (less [padding]) and keep their own shape.
class PdfPageLayout {
  PdfPageLayout({
    required this.width,
    required this.padding,
    required List<double> aspects,
  }) : tops = List<double>.filled(aspects.length, 0),
       heights = [for (final a in aspects) (width - padding * 2) * a] {
    var y = padding;
    for (var i = 0; i < heights.length; i++) {
      tops[i] = y;
      y += heights[i] + padding;
    }
    height = y;
  }

  final double width, padding;
  final List<double> tops, heights;
  late final double height;

  int get pages => heights.length;

  Rect rect(int index) =>
      Rect.fromLTWH(padding, tops[index], width - padding * 2, heights[index]);

  /// The page (0-based) under [y], or the nearest one.
  int indexAt(double y) {
    var low = 0, high = pages - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (tops[mid] <= y) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

/// A rendered page bitmap, encoded small and decoded by Flutter off the UI thread.
class _PageImage {
  _PageImage(this.provider, this.width);
  final MemoryImage provider;
  final int width;
}

/// Shows a PDF as one continuous, zoomable column of pages.
///
/// Pages are rendered by the platform on a background thread (`renderPage`)
/// as screen-sized JPEGs, one at a time: visible pages first, then the ones
/// next to them. Pages that scroll away before their turn are skipped, only a
/// few bitmaps stay in memory, and a sharper copy is rendered only for the
/// pages on screen once a zoom gesture settles. Nothing heavy runs on the
/// thread that also drives scrolling.
class PdfPagesView extends StatefulWidget {
  const PdfPagesView({
    super.key,
    required this.path,
    required this.onLoaded,
    required this.onPageChanged,
    required this.onError,
    this.padding = 12,
    this.maxScale = 6,
  });

  final String path;
  final void Function(int pages) onLoaded;
  final void Function(int page) onPageChanged;
  final void Function(Object error) onError;
  final double padding, maxScale;

  @override
  State<PdfPagesView> createState() => PdfPagesViewState();
}

class PdfPagesViewState extends State<PdfPagesView>
    with SingleTickerProviderStateMixin {
  /// Bitmaps kept at the base resolution; the oldest-used ones are dropped.
  static const _keepPages = 6;

  /// Base bitmaps are at most this wide; zoomed ones at most [_sharpWidth].
  static const _baseWidth = 1440, _sharpWidth = 2400;

  final transform = TransformationController();
  late final AnimationController _motion = AnimationController(vsync: this)
    ..addListener(() {
      final animation = _matrix;
      if (animation != null) transform.value = animation.value;
    });
  Animation<Matrix4>? _matrix;

  PdfDocument? _document;
  List<double> _aspects = const [];
  final _sized = <int>{};
  final _base = <int, _PageImage>{};
  final _sharp = <int, _PageImage>{};
  PdfPageLayout? _layout;
  Size _view = Size.zero;
  double _dpr = 2;
  int _page = 1;
  bool _working = false, _disposed = false, _interacting = false;

  double get _scale => transform.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    transform.addListener(_moved);
    _open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void dispose() {
    _disposed = true;
    transform.removeListener(_moved);
    _motion.dispose();
    transform.dispose();
    for (final image in [..._base.values, ..._sharp.values]) {
      image.provider.evict();
    }
    // The worker closes the document itself if a page is still rendering.
    if (!_working) _document?.close().catchError((_) {});
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final document = await PdfDocument.openFile(widget.path);
      if (_disposed) {
        await document.close();
        return;
      }
      final first = await document.getPage(1);
      final aspect = first.height / first.width;
      await first.close();
      if (_disposed) {
        await document.close();
        return;
      }
      _sized.add(0);
      setState(() {
        _document = document;
        // Most documents use one page size; others are corrected as they load.
        _aspects = List<double>.filled(document.pagesCount, aspect);
        _layout = null;
      });
      widget.onLoaded(document.pagesCount);
      _schedule();
    } catch (error) {
      if (!_disposed) widget.onError(error);
    }
  }

  PdfPageLayout _layoutFor(Size view) {
    final current = _layout;
    if (current != null && current.width == view.width) return current;
    return _layout = PdfPageLayout(
      width: view.width,
      padding: widget.padding,
      aspects: _aspects,
    );
  }

  /// The document area on screen, in unscaled document coordinates.
  Rect _visible() {
    final m = transform.value, s = _scale;
    final dx = -m.storage[12] / s, dy = -m.storage[13] / s;
    return Rect.fromLTWH(dx, dy, _view.width / s, _view.height / s);
  }

  void _moved() {
    final layout = _layout;
    if (layout == null || layout.pages == 0) return;
    final visible = _visible();
    final page = layout.indexAt(visible.center.dy) + 1;
    if (page != _page) {
      _page = page;
      widget.onPageChanged(page);
    }
    _schedule();
  }

  /// Pages to render, most urgent first: on screen (nearest the middle
  /// first), then the next two and the previous one.
  List<int> _wanted() {
    final layout = _layout;
    if (layout == null || layout.pages == 0) return const [];
    final visible = _visible();
    final first = layout.indexAt(visible.top);
    final last = layout.indexAt(visible.bottom);
    final middle = layout.indexAt(visible.center.dy);
    final onScreen = [for (var i = first; i <= last; i++) i]
      ..sort((a, b) => (a - middle).abs().compareTo((b - middle).abs()));
    return [
      ...onScreen,
      for (final i in [last + 1, last + 2, first - 1])
        if (i >= 0 && i < layout.pages) i,
    ];
  }

  int _targetWidth(int index, {required bool sharp}) {
    final layout = _layout!;
    final shown = (layout.width - layout.padding * 2) * _dpr;
    if (!sharp) return math.min(shown, _baseWidth).round();
    return math.min(shown * _scale, _sharpWidth).round();
  }

  /// The next render job, or null when everything wanted is ready.
  (int, bool)? _nextJob() {
    final wanted = _wanted();
    for (final index in wanted) {
      if (!_base.containsKey(index)) return (index, false);
    }
    if (!_interacting && _scale > 1.15) {
      for (final index in wanted.take(2)) {
        final have = _sharp[index]?.width ?? 0;
        final need = _targetWidth(index, sharp: true);
        if (need > _targetWidth(index, sharp: false) && have < need * .9) {
          return (index, true);
        }
      }
    }
    return null;
  }

  void _schedule() {
    if (_working || _disposed || _document == null || _view.isEmpty) return;
    _working = true;
    unawaited(_work());
  }

  Future<void> _work() async {
    try {
      while (!_disposed) {
        final job = _nextJob();
        if (job == null) break;
        await _render(job.$1, sharp: job.$2);
      }
    } catch (error) {
      if (!_disposed) widget.onError(error);
    } finally {
      _working = false;
      if (_disposed) {
        _document?.close().catchError((_) {});
      }
    }
  }

  Future<void> _render(int index, {required bool sharp}) async {
    final document = _document!;
    final page = await document.getPage(index + 1);
    PdfPageImage? image;
    try {
      if (!_sized.contains(index)) {
        _sized.add(index);
        final aspect = page.height / page.width;
        if ((aspect - _aspects[index]).abs() > .001 && !_disposed) {
          setState(() {
            _aspects = [..._aspects]..[index] = aspect;
            _layout = null;
          });
        }
      }
      final width = _targetWidth(index, sharp: sharp);
      image = await page.render(
        width: width.toDouble(),
        height: (width * page.height / page.width).roundToDouble(),
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 88,
      );
    } finally {
      await page.close();
    }
    if (_disposed || image == null) return;
    final rendered = _PageImage(MemoryImage(image.bytes), image.width ?? 0);
    setState(() {
      if (sharp) {
        _sharp.remove(index)?.provider.evict();
        _sharp[index] = rendered;
      } else {
        _base.remove(index)?.provider.evict();
        _base[index] = rendered;
      }
      _trim();
    });
  }

  /// Drops bitmaps for pages far from the screen, and sharp copies once the
  /// reader zooms back out.
  void _trim() {
    final keep = _wanted().toSet();
    while (_base.length > _keepPages) {
      final oldest = _base.keys.firstWhere(
        (i) => !keep.contains(i),
        orElse: () => -1,
      );
      if (oldest < 0) break;
      _base.remove(oldest)!.provider.evict();
    }
    final onScreen = _wanted().take(2).toSet();
    for (final index in _sharp.keys.toList()) {
      if (_scale <= 1.15 || !onScreen.contains(index)) {
        _sharp.remove(index)!.provider.evict();
      }
    }
  }

  void _touch(int index) {
    final image = _base.remove(index);
    if (image != null) _base[index] = image;
  }

  void _animateTo(Matrix4 target, Duration duration) {
    if (duration == Duration.zero) {
      transform.value = target;
      return;
    }
    _matrix = Matrix4Tween(
      begin: transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic));
    _motion
      ..duration = duration
      ..forward(from: 0);
  }

  Matrix4 _clamped(double scale, double x, double y) {
    final layout = _layout!;
    final maxX = math.max(0.0, layout.width * scale - _view.width);
    final maxY = math.max(0.0, layout.height * scale - _view.height);
    return Matrix4.identity()
      ..setTranslationRaw(-x.clamp(0.0, maxX), -y.clamp(0.0, maxY), 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Scrolls so [page] (1-based) starts at the top of the view.
  void goToPage(int page, {Duration duration = Duration.zero}) {
    final layout = _layout;
    if (layout == null || layout.pages == 0) return;
    final index = page.clamp(1, layout.pages) - 1;
    final s = _scale;
    _animateTo(
      _clamped(
        s,
        -transform.value.storage[12],
        (layout.tops[index] - layout.padding) * s,
      ),
      duration,
    );
  }

  /// Double tap: zoom in around [point], or back to the page width.
  void toggleZoomAt(Offset point, {Duration duration = Duration.zero}) {
    final layout = _layout;
    if (layout == null) return;
    final m = transform.value, s = _scale;
    final docX = (point.dx - m.storage[12]) / s;
    final docY = (point.dy - m.storage[13]) / s;
    final next = s > 1.05 ? 1.0 : 2.5;
    _animateTo(
      _clamped(next, docX * next - point.dx, docY * next - point.dy),
      duration,
    );
    Timer(duration + const Duration(milliseconds: 60), _schedule);
  }

  Widget _pageBox(int index, PdfPageLayout layout) {
    final image = _sharp[index] ?? _base[index];
    if (image != null) _touch(index);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x240f172a),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: image == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: AppSpinner(strokeWidth: 2),
              ),
            )
          : Image(
              image: image.provider,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              // Bitmaps are already at screen size; medium would build mipmaps
              // for every page as it arrives.
              filterQuality: FilterQuality.low,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null) {
      return const Center(child: AppSpinner());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.biggest;
        final resized = view != _view;
        _view = view;
        final layout = _layoutFor(view);
        if (resized) scheduleMicrotask(_schedule);
        return InteractiveViewer.builder(
          transformationController: transform,
          minScale: 1,
          maxScale: widget.maxScale,
          boundaryMargin: EdgeInsets.zero,
          onInteractionStart: (_) => _interacting = true,
          onInteractionEnd: (_) {
            _interacting = false;
            // Sharper pages once the fling settles.
            Timer(const Duration(milliseconds: 160), () {
              if (!_disposed) {
                setState(_trim);
                _schedule();
              }
            });
          },
          builder: (context, viewport) {
            final ys = [
              viewport.point0.y,
              viewport.point1.y,
              viewport.point2.y,
              viewport.point3.y,
            ];
            final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
            final first = layout.indexAt(top - view.height);
            final last = layout.indexAt(bottom + view.height);
            return SizedBox(
              width: layout.width,
              height: layout.height,
              child: Stack(
                children: [
                  for (var i = first; i <= last; i++)
                    Positioned.fromRect(
                      key: ValueKey('pdf.page.${i + 1}'),
                      rect: layout.rect(i),
                      child: RepaintBoundary(child: _pageBox(i, layout)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
