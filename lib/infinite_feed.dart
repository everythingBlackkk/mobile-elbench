import 'package:flutter/material.dart';
import 'api.dart';
import 'web_home.dart' show webBorder, webMuted, webSecondary;

/// Replaces Next/Previous buttons at the end of a paginated list. [onLoadMore]
/// runs when the reader nears the end of the enclosing scroll view (or when
/// the loaded rows do not fill it) and skeleton cards show until the rows
/// arrive.
class InfiniteScrollFooter extends StatefulWidget {
  const InfiniteScrollFooter({
    super.key,
    required this.hasMore,
    required this.loading,
    required this.failed,
    required this.onLoadMore,
    required this.translate,
    this.skeletons = 2,
    this.compact = false,
  });
  final bool hasMore, loading, failed;
  final VoidCallback onLoadMore;
  final String Function(String en, String ar) translate;
  final int skeletons;
  final bool compact;

  @override
  State<InfiniteScrollFooter> createState() => _InfiniteScrollFooterState();
}

class _InfiniteScrollFooterState extends State<InfiniteScrollFooter> {
  ScrollPosition? _position;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_check);
      _position = next?..addListener(_check);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _check();
    });
  }

  void _check() {
    if (!mounted || !widget.hasMore || widget.loading || widget.failed) return;
    final position = _position;
    if (position == null ||
        !position.hasContentDimensions ||
        !position.hasPixels) {
      return;
    }
    if (position.extentAfter < position.viewportDimension * 1.5) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return Column(
        key: const ValueKey('infinite.loading'),
        children: [
          for (var i = 0; i < widget.skeletons; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PostSkeleton(compact: widget.compact),
            ),
        ],
      );
    }
    if (widget.failed) {
      return Padding(
        key: const ValueKey('infinite.retry'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              widget.translate(
                'Could not load more. Check your connection.',
                'تعذّر تحميل المزيد. تأكد من الاتصال.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: webMuted(context), fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: widget.onLoadMore,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(widget.translate('Try again', 'حاول مرة أخرى')),
            ),
          ],
        ),
      );
    }
    if (widget.hasMore) _scheduleCheck();
    return const SizedBox(height: 8);
  }
}

/// A softly pulsing placeholder shaped like a feed post card.
class PostSkeleton extends StatefulWidget {
  const PostSkeleton({super.key, this.compact = false});
  final bool compact;
  @override
  State<PostSkeleton> createState() => _PostSkeletonState();
}

class _PostSkeletonState extends State<PostSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: .55,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      webMuted(context).withValues(alpha: .16),
      webSecondary(context),
    );
    Widget bar({double? width, required double height, double radius = 6}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    Widget line(double widthFactor) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: bar(height: 12),
    );
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: webSecondary(context),
          border: Border.all(color: webBorder(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: FadeTransition(
          opacity: _pulse,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  bar(width: 36, height: 36, radius: 18),
                  const SizedBox(width: 10),
                  bar(width: 110, height: 12),
                ],
              ),
              const SizedBox(height: 14),
              line(1),
              const SizedBox(height: 8),
              line(widget.compact ? .6 : .75),
              if (!widget.compact) ...[const SizedBox(height: 8), line(.45)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows to show after reloading a first page that the reader had scrolled
/// past: the fresh rows, then the kept rows that followed the last row the
/// fresh page still contains. Kept rows inside the fresh page's span that
/// are missing were deleted and are dropped. Null when nothing is kept.
List<Json>? continueRows(List<Json> fresh, List<Json> kept) {
  if (kept.length <= fresh.length) return null;
  final ids = {for (final row in fresh) value(row['id'])};
  var last = -1;
  for (var i = 0; i < kept.length; i++) {
    if (ids.contains(value(kept[i]['id']))) last = i;
  }
  if (last < 0) return null;
  return [
    ...fresh,
    for (final row in kept.skip(last + 1))
      if (!ids.contains(value(row['id']))) row,
  ];
}

/// Merge a newly fetched page into the rows already shown, skipping rows
/// that shifted into the next page because content was posted meanwhile.
List<Json> mergeRows(List<Json> existing, List<Json> incoming) {
  final seen = {for (final row in existing) value(row['id'])};
  return [
    ...existing,
    for (final row in incoming)
      if (value(row['id']).isEmpty || seen.add(value(row['id']))) row,
  ];
}

/// Placeholder for a page whose document has not arrived yet. The page can
/// slide in immediately instead of keeping the previous page on screen for
/// the whole network round trip.
/// The placeholder for a page that is not in memory yet, shaped like the page that is coming: feed posts by
/// default, a list for notification-style pages, tiles for Edit subjects and one block for the campus map.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key, this.screen = ''});
  final String screen;
  @override
  Widget build(BuildContext context) => switch (screen) {
    'community.notifications' ||
    'admin.feed' ||
    'community.materials' => const ShapeSkeleton(ShapeSkeletonKind.list),
    'community.subjects' => const ShapeSkeleton(ShapeSkeletonKind.grid),
    'content.campus' => const ShapeSkeleton(ShapeSkeletonKind.block),
    _ => ListView(
      key: const ValueKey('page.skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 22, 10, 0),
      children: const [
        PostSkeleton(),
        SizedBox(height: 8),
        PostSkeleton(),
        SizedBox(height: 8),
        PostSkeleton(compact: true),
      ],
    ),
  };
}

enum ShapeSkeletonKind { list, grid, block }

/// Pulsing placeholder in the same colours as [PostSkeleton].
class ShapeSkeleton extends StatefulWidget {
  const ShapeSkeleton(this.kind, {super.key});
  final ShapeSkeletonKind kind;
  @override
  State<ShapeSkeleton> createState() => _ShapeSkeletonState();
}

class _ShapeSkeletonState extends State<ShapeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: .55,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      webMuted(context).withValues(alpha: .16),
      webSecondary(context),
    );
    Widget bar(double widthFactor, double height, {double radius = 6}) =>
        FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );
    final border = Border.all(color: webBorder(context));
    final Widget body = switch (widget.kind) {
      ShapeSkeletonKind.list => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(.35, 13),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) Divider(height: 1, color: webBorder(context)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      children: [
                        bar(.4, 11),
                        const SizedBox(height: 10),
                        bar(.92, 13),
                        const SizedBox(height: 7),
                        bar(i.isEven ? .6 : .75, 13),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      ShapeSkeletonKind.grid => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(.5, 14),
          const SizedBox(height: 16),
          Container(
            height: 92,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 16),
          for (var row = 0; row < 2; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 170,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      ShapeSkeletonKind.block => Container(
        height: MediaQuery.sizeOf(context).height * .66,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    };
    return ExcludeSemantics(
      child: ListView(
        key: ValueKey('page.skeleton.${widget.kind.name}'),
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
        children: [FadeTransition(opacity: _pulse, child: body)],
      ),
    );
  }
}

/// Skeleton rows for comments or answers still loading under a seeded post.
class CommentsSkeleton extends StatelessWidget {
  const CommentsSkeleton({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('comments.skeleton'),
    children: [
      for (var i = 0; i < count; i++)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: PostSkeleton(compact: true),
        ),
    ],
  );
}
