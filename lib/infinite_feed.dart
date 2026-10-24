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

/// A shimmering placeholder shaped like a feed post card.
class PostSkeleton extends StatefulWidget {
  const PostSkeleton({super.key, this.compact = false});
  final bool compact;
  @override
  State<PostSkeleton> createState() => _PostSkeletonState();
}

class _PostSkeletonState extends State<PostSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = webBorder(context);
    final base = Color.alphaBlend(
      webMuted(context).withValues(alpha: .14),
      webSecondary(context),
    );
    final highlight = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .07);
    Widget bar({double? width, required double height, double radius = 6}) =>
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            width: width,
            height: height,
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + _shimmer.value * 3, 0),
                    end: Alignment(_shimmer.value * 3, 0),
                    colors: [base, highlight, base],
                  ),
                ),
              ),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: webSecondary(context),
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                bar(width: 40, height: 40, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(width: 120, height: 13),
                      const SizedBox(height: 7),
                      bar(width: 70, height: 10),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            bar(height: 13),
            const SizedBox(height: 8),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: .8,
              child: bar(height: 13),
            ),
            if (!widget.compact) ...[
              const SizedBox(height: 8),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: .55,
                child: bar(height: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  bar(width: 56, height: 22, radius: 11),
                  const SizedBox(width: 10),
                  bar(width: 56, height: 22, radius: 11),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
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
