import 'package:flutter/material.dart';
import 'api.dart';
import 'web_home.dart' show webMuted;
import 'page_skeletons.dart';

export 'page_skeletons.dart' show initialScreenForPath;

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
      return SkeletonPulse(
        child: Column(
          key: const ValueKey('infinite.loading'),
          children: [
            for (var i = 0; i < widget.skeletons; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PostSkeleton(compact: widget.compact),
              ),
          ],
        ),
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

/// Feed placeholders also share a single pulse when grouped by a page/footer.
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) =>
      SkeletonPulse(child: SkeletonPostCard(compact: compact));
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

/// The page's own geometry is visible while its first document is loading.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key, this.screen = '', this.path = ''});
  final String screen, path;
  @override
  Widget build(BuildContext context) => ScreenSkeleton(
    key: const ValueKey('page.skeleton'),
    screen: screen,
    path: path,
  );
}

enum ShapeSkeletonKind { list, grid, block }

/// Kept for the embedded campus-artwork placeholder and older callers.
class ShapeSkeleton extends StatelessWidget {
  const ShapeSkeleton(this.kind, {super.key});
  final ShapeSkeletonKind kind;
  @override
  Widget build(BuildContext context) => ScreenSkeleton(
    key: ValueKey('page.skeleton.${kind.name}'),
    screen: switch (kind) {
      ShapeSkeletonKind.list => 'community.notifications',
      ShapeSkeletonKind.grid => 'community.subjects',
      ShapeSkeletonKind.block => 'content.campus',
    },
  );
}

/// Avatar, bubble and reply-action rows under a seeded post or question.
class CommentsSkeleton extends StatelessWidget {
  const CommentsSkeleton({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: Column(
      key: const ValueKey('comments.skeleton'),
      children: [
        for (var i = 0; i < count; i++) SkeletonComment(reply: i == 1),
      ],
    ),
  );
}
