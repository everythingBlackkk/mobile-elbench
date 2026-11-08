import 'package:flutter/material.dart';

import 'api.dart';

/// Which reply threads are open on a post, and their replies loaded so far.
///
/// The comment list arrives with the first replies of each thread; opening a
/// thread with more fetches the rest a page at a time, in place.
class CommentThreads extends ChangeNotifier {
  CommentThreads({required this.load});

  /// Fetches one page of a thread: `/community/posts/{post}?thread={root}&page={n}`.
  final Future<Json> Function(String path) load;

  final _open = <String>{};
  final _perThread = <String, ChangeNotifier>{};

  /// Changes to one thread only, so opening a thread rebuilds just that
  /// thread and not every comment on the page.
  Listenable of(String root) =>
      _perThread.putIfAbsent(root, ChangeNotifier.new);

  void _changed(String root) {
    _perThread[root]?.notifyListeners();
    notifyListeners();
  }

  final _replies = <String, List<Json>>{};
  final _next = <String, String?>{};
  final _loading = <String>{};
  final _failed = <String>{};
  int _generation = 0;

  bool isOpen(String root) => _open.contains(root);
  bool isLoading(String root) => _loading.contains(root);
  bool failed(String root) => _failed.contains(root);
  bool hasMore(String root) => _next[root] != null;

  /// Replies to show for [root]: the fetched list when there is one, else
  /// the preview that came with the comment.
  List<Json> replies(String root, List<Json> preview) =>
      _replies[root] ?? preview;

  void open(
    String root, {
    required String postId,
    required int total,
    required int shown,
  }) {
    if (_open.add(root)) _changed(root);
    if (total > shown && !_replies.containsKey(root)) {
      fetch(root, postId: postId);
    }
  }

  void close(String root) {
    if (_open.remove(root)) _changed(root);
  }

  /// Loads (or reloads, when [reset]) the thread's replies.
  Future<void> fetch(
    String root, {
    required String postId,
    bool reset = true,
  }) async {
    if (_loading.contains(root)) return;
    final page = reset ? null : _next[root];
    if (!reset && page == null) return;
    final generation = _generation;
    _loading.add(root);
    _failed.remove(root);
    _changed(root);
    try {
      final response = await load(
        page ?? '/community/posts/$postId?thread=$root',
      );
      if (generation != _generation) return;
      final comments = object(object(response['data'])['comments']);
      final incoming = rows(comments['data']);
      final next = comments['next_page_url'];
      final known = reset ? <Json>[] : [...?_replies[root]];
      final ids = {for (final reply in known) '${reply['id']}'};
      _replies[root] = [
        ...known,
        for (final reply in incoming)
          if (ids.add('${reply['id']}')) reply,
      ];
      if (next is String) {
        final uri = Uri.parse(next);
        _next[root] = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      } else {
        _next[root] = null;
      }
    } catch (_) {
      if (generation == _generation) _failed.add(root);
    } finally {
      if (generation == _generation) {
        _loading.remove(root);
        _changed(root);
      }
    }
  }

  /// Forget fetched replies (after a full reload) but keep threads open.
  void forgetReplies() {
    _generation++;
    _replies.clear();
    _next.clear();
    _loading.clear();
    _failed.clear();
    for (final thread in _perThread.values) {
      thread.notifyListeners();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final thread in _perThread.values) {
      thread.dispose();
    }
    super.dispose();
  }
}

/// Fades and slides a reply in the first time it is shown; [order] staggers
/// replies that appear together.
class RevealReply extends StatefulWidget {
  const RevealReply({super.key, required this.order, required this.child});
  final int order;
  final Widget child;
  @override
  State<RevealReply> createState() => _RevealReplyState();
}

class _RevealReplyState extends State<RevealReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 45 * widget.order.clamp(0, 6));
    Future<void>.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, -.08),
        end: Offset.zero,
      ).animate(_curve),
      child: widget.child,
    ),
  );
}
