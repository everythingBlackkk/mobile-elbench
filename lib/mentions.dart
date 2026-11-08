import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'link_preview.dart' show findLinks, openExternalLink;
import 'text_direction.dart';
import 'web_home.dart' show webMuted;
import 'web_style.dart';

/// The "@query" being typed at the cursor.
@immutable
class MentionQuery {
  const MentionQuery(this.range, this.text);
  final TextRange range;
  final String text;
  @override
  bool operator ==(Object other) =>
      other is MentionQuery && other.range == range && other.text == text;
  @override
  int get hashCode => Object.hash(range, text);
}

/// Text field controller that tracks mentions: it highlights them, keeps
/// their user ids, and finds the "@query" being typed.
///
/// Like Facebook, "@" only starts a search: picking a person leaves their
/// plain name in the text (no "@", so Arabic and English mix without the
/// sign jumping sides). The ids travel next to the text.
class MentionTextController extends TextEditingController
    implements DirectionalTextController {
  MentionTextController({super.text, Iterable<Json> mentions = const []}) {
    for (final mention in mentions) {
      final id = int.tryParse(value(mention['id']));
      final name = value(mention['name']);
      if (id != null && name.isNotEmpty) _mentions[id] = name;
    }
  }

  static const maxMentions = 10;
  final _mentions = <int, String>{};

  /// Style for mentioned names; set by the field that shows this controller.
  TextStyle? highlight;

  /// Mentions whose name is still in the text.
  List<Json> get mentions {
    final present = {
      for (final range in mentionRanges())
        text.substring(range.start, range.end).replaceFirst('@', ''),
    };
    return [
      for (final entry in _mentions.entries)
        if (present.contains(entry.value))
          {'id': entry.key, 'name': entry.value},
    ];
  }

  List<int> get mentionIds => [for (final m in mentions) m['id'] as int];

  Iterable<String> get _names => _mentions.values;

  bool get canMention => mentions.length < maxMentions;

  /// Puts "Full Name " in place of the "@query" [range] and tracks the person.
  void insertMention(TextRange range, int id, String name) {
    if (name.isEmpty || range.start < 0 || range.end > text.length) return;
    final insert = '$name ';
    _mentions[id] = name;
    this.value = TextEditingValue(
      text: text.replaceRange(range.start, range.end, insert),
      selection: TextSelection.collapsed(offset: range.start + insert.length),
    );
  }

  /// Starts a reply with the person's mention, like Facebook.
  void startWith(int id, String name) {
    if (name.isEmpty) return;
    final tag = '$name ';
    _mentions[id] = name;
    final body = text.startsWith(tag) ? text.substring(tag.length) : text;
    this.value = TextEditingValue(
      text: '$tag$body',
      selection: TextSelection.collapsed(offset: tag.length + body.length),
    );
  }

  /// Removes a leading mention added by [startWith] when nothing else was typed.
  void dropLeading(String name) {
    if (name.isNotEmpty && text.trim() == name) clear();
  }

  @override
  void clear() {
    super.clear();
    _mentions.clear();
  }

  /// Ranges of tracked names in the text (with a leading "@" when older
  /// text has one), in order, never overlapping, on word boundaries.
  List<TextRange> mentionRanges() => findMentionRanges(text, _names);

  /// The "@query" right before the cursor, if the person is typing one.
  MentionQuery? activeQuery() {
    final selection = this.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return null;
    if (at > 0 && !_space.hasMatch(before[at - 1])) return null;
    final query = before.substring(at + 1);
    if (query.isEmpty ||
        query.length > 40 ||
        query.contains('\n') ||
        _space.hasMatch(query[0]) ||
        ' '.allMatches(query).length > 2) {
      return null;
    }
    for (final range in mentionRanges()) {
      if (range.start <= at && at < range.end) return null;
    }
    return MentionQuery(TextRange(start: at, end: cursor), query);
  }

  @override
  TextDirection textDirection(TextDirection fallback) =>
      mentionAwareDirection(text, _names, fallback);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ranges = highlight == null ? const <TextRange>[] : mentionRanges();
    if (ranges.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // Split at mention and composing boundaries, so keyboards that compose
    // words (Arabic, predictive text) keep their underline and caret.
    final composing = withComposing && this.value.isComposingRangeValid
        ? this.value.composing
        : TextRange.empty;
    final cuts = <int>{0, text.length};
    for (final range in ranges) {
      cuts
        ..add(range.start)
        ..add(range.end);
    }
    if (composing.isValid) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final points = cuts.where((i) => i >= 0 && i <= text.length).toList()
      ..sort();
    final underline = (style ?? const TextStyle()).merge(
      const TextStyle(decoration: TextDecoration.underline),
    );
    final children = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i], end = points[i + 1];
      if (start == end) continue;
      final inMention = ranges.any((r) => r.start <= start && end <= r.end);
      final inComposing =
          composing.isValid && composing.start <= start && end <= composing.end;
      var piece = inComposing ? underline : style;
      if (inMention) piece = (piece ?? const TextStyle()).merge(highlight);
      children.add(TextSpan(text: text.substring(start, end), style: piece));
    }
    return TextSpan(style: style, children: children);
  }

  static final _space = RegExp(r'\s');
}

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

/// Where [names] appear in [text] as whole words, longest name first.
List<TextRange> findMentionRanges(String text, Iterable<String> names) {
  final unique = names.where((n) => n.isNotEmpty).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (unique.isEmpty || text.isEmpty) return const [];
  final found = <TextRange>[];
  for (final name in unique) {
    var from = 0;
    while (true) {
      final at = text.indexOf(name, from);
      if (at < 0) break;
      final end = at + name.length;
      from = end;
      final before = at > 0 ? text[at - 1] : '';
      final after = end < text.length ? text[end] : '';
      if (_wordChar.hasMatch(before) || _wordChar.hasMatch(after)) continue;
      final start = before == '@' ? at - 1 : at;
      if (!found.any((r) => r.start < end && start < r.end)) {
        found.add(TextRange(start: start, end: end));
      }
    }
  }
  return found..sort((a, b) => a.start.compareTo(b.start));
}

class _Found {
  _Found(this.people, this.complete);
  final List<Json> people;
  final bool complete;
}

/// Mention search with a small per-account cache. When the server says a
/// query's answer was complete, longer queries are filtered on the device, so
/// typing "@sa" → "@sar" → "@sara" costs one request.
class MentionSearch {
  MentionSearch._(this.api);
  final MobileApi api;

  static final _byAccount = <String, MentionSearch>{};
  static MentionSearch of(MobileApi api, Object? viewerId) {
    final key = '${identityHashCode(api)}:$viewerId';
    if (!_byAccount.containsKey(key)) {
      _byAccount
        ..removeWhere((k, _) => k.startsWith('${identityHashCode(api)}:'))
        ..[key] = MentionSearch._(api);
    }
    return _byAccount[key]!;
  }

  static const _cacheSize = 60;
  final _cache = <String, _Found>{};
  final _inflight = <String, Future<_Found>>{};

  static String normalize(String query) => query
      .replaceAll('@', '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  static bool matches(Json person, String query) {
    final name = value(person['name']).toLowerCase();
    if (RegExp(r'^[0-9]+$').hasMatch(query)) {
      return value(person['university_id']).startsWith(query);
    }
    if (name.startsWith(query)) return true;
    for (final match in RegExp(r'\s').allMatches(name)) {
      if (name.substring(match.end).startsWith(query)) return true;
    }
    return false;
  }

  /// Results available without a request, or null.
  List<Json>? cached(String raw) {
    final query = normalize(raw);
    if (query.isEmpty) return const [];
    final hit = _cache.remove(query);
    if (hit != null) {
      _cache[query] = hit;
      return hit.people;
    }
    for (var n = query.length - 1; n >= 1; n--) {
      final shorter = _cache[query.substring(0, n)];
      if (shorter != null && shorter.complete) {
        final people = [
          for (final person in shorter.people)
            if (matches(person, query)) person,
        ];
        _remember(query, _Found(people, true));
        return people;
      }
    }
    return null;
  }

  Future<List<Json>> search(String raw) async {
    final query = normalize(raw);
    final ready = cached(query);
    if (ready != null) return ready;
    final found = await (_inflight[query] ??= _fetch(query).whenComplete(() {
      // A block body: returning the removed future would make it wait on itself.
      _inflight.remove(query);
    }));
    return found.people;
  }

  Future<_Found> _fetch(String query) async {
    final response = await api.get(
      '/mentions/search?q=${Uri.encodeQueryComponent(query)}',
    );
    final found = _Found(rows(response['data']), response['complete'] == true);
    _remember(query, found);
    return found;
  }

  void _remember(String query, _Found found) {
    _cache.remove(query);
    _cache[query] = found;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }
}

/// Wraps a composer and shows Facebook-style mention suggestions above it
/// while "@name" is being typed.
class MentionField extends StatefulWidget {
  const MentionField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.api,
    required this.viewerId,
    required this.avatar,
    required this.accent,
    required this.child,
    this.excludeIds = const {},
    this.insideBottom = false,
    this.fullWidth = false,
  });
  final MentionTextController controller;
  final FocusNode focusNode;
  final MobileApi api;
  final Object? viewerId;
  final Widget Function(Json person) avatar;
  final Color accent;
  final Widget child;
  final Set<int> excludeIds;

  /// Show the list over the bottom of a tall field (full-screen editors)
  /// instead of above it.
  final bool insideBottom;

  /// Span the screen width (minus margins) instead of the composer's width,
  /// for editors where the text box sits beside a profile picture.
  final bool fullWidth;

  static const screenMargin = 16.0;

  @override
  State<MentionField> createState() => _MentionFieldState();
}

class _MentionFieldState extends State<MentionField> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _target = GlobalKey();
  MentionQuery? _query;
  List<Json> _results = const [];
  Timer? _debounce;
  int _sequence = 0;

  MentionSearch get _search => MentionSearch.of(widget.api, widget.viewerId);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MentionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_changed);
      widget.focusNode.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final controller = widget.controller;
    final query = widget.focusNode.hasFocus && controller.canMention
        ? controller.activeQuery()
        : null;
    if (query == _query) return;
    _query = query;
    _debounce?.cancel();
    final sequence = ++_sequence;
    if (query == null) {
      _show(const []);
      return;
    }
    final ready = _search.cached(query.text);
    if (ready != null) {
      _show(ready);
      return;
    }
    // One request per pause in typing; earlier answers keep showing meanwhile.
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final people = await _search.search(query.text);
        if (mounted && sequence == _sequence) _show(people);
      } catch (_) {
        if (mounted && sequence == _sequence) _show(const []);
      }
    });
  }

  void _show(List<Json> people) {
    final visible = [
      for (final person in people)
        if (!widget.excludeIds.contains(int.tryParse(value(person['id']))))
          person,
    ];
    if (!mounted) return;
    setState(() => _results = visible);
    if (visible.isEmpty) {
      if (_portal.isShowing) _portal.hide();
    } else if (!_portal.isShowing) {
      _portal.show();
    }
  }

  void _pick(Json person) {
    final query = _query;
    final id = int.tryParse(value(person['id']));
    if (query == null || id == null) return;
    widget.controller.insertMention(query.range, id, value(person['name']));
    if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    widget.controller.highlight = TextStyle(
      color: widget.accent,
      fontWeight: FontWeight.w600,
    );
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _overlay,
        child: KeyedSubtree(key: _target, child: widget.child),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final box = _target.currentContext?.findRenderObject();
    final laidOut = box is RenderBox && box.hasSize && box.attached;
    var width = laidOut
        ? box.size.width
        : MediaQuery.sizeOf(context).width - 24;
    var rtl = Directionality.of(context) == TextDirection.rtl;
    var dx = 0.0;
    if (widget.fullWidth && laidOut) {
      // Line the list up with the screen edges, wherever the field starts.
      final overlay = Overlay.of(context).context.findRenderObject();
      final screen = MediaQuery.sizeOf(context);
      final safe = MediaQuery.paddingOf(context);
      final left = box
          .localToGlobal(
            Offset.zero,
            ancestor: overlay is RenderBox ? overlay : null,
          )
          .dx;
      final start = safe.left + MentionField.screenMargin;
      width = screen.width - safe.horizontal - 2 * MentionField.screenMargin;
      dx = start - left;
      rtl = false; // anchored by the left edges; the list itself stays RTL.
    }
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: widget.insideBottom
          ? (rtl ? Alignment.bottomRight : Alignment.bottomLeft)
          : (rtl ? Alignment.topRight : Alignment.topLeft),
      followerAnchor: rtl ? Alignment.bottomRight : Alignment.bottomLeft,
      offset: Offset(dx, -8),
      child: Align(
        alignment: rtl ? Alignment.bottomRight : Alignment.bottomLeft,
        child: TextFieldTapRegion(
          child: SizedBox(
            width: width,
            child: MentionSuggestions(
              people: _results,
              avatar: widget.avatar,
              api: widget.api,
              onPick: _pick,
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating list of people: three rows at a time, scrollable.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    super.key,
    required this.people,
    required this.avatar,
    required this.api,
    required this.onPick,
  });
  final List<Json> people;
  final Widget Function(Json person) avatar;
  final MobileApi api;
  final ValueChanged<Json> onPick;

  static const rowHeight = 60.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = webMuted(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final visibleRows = people.length.clamp(1, 3);
    final card = Material(
      key: const ValueKey('mention.suggestions'),
      color: dark ? const Color(0xff3a3b3c) : Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .28),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: visibleRows * rowHeight + 8,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            physics: const ClampingScrollPhysics(),
            itemExtent: rowHeight,
            itemCount: people.length,
            itemBuilder: (context, index) {
              final person = people[index];
              final name = value(person['name']);
              final id = value(person['university_id']);
              return InkWell(
                key: ValueKey('mention.option.${person['id']}'),
                onTap: () => onPick(person),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      SizedBox(width: 40, height: 40, child: avatar(person)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: contentDirection(name),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (person['badge'] != null &&
                                    '${person['badge']}' != '0') ...[
                                  const SizedBox(width: 4),
                                  UserBadge(api: api, badge: person['badge']),
                                ],
                              ],
                            ),
                            if (id.isNotEmpty)
                              Text(
                                '@$id',
                                maxLines: 1,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (reduce) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: child,
        ),
      ),
      child: card,
    );
  }
}

/// Post or comment text with its @mentions highlighted and tappable.
class MentionText extends StatefulWidget {
  const MentionText(
    this.text, {
    super.key,
    required this.mentions,
    required this.style,
    required this.accent,
    required this.onOpen,
    this.maxLines,
    this.overflow,
  });
  final String text;
  final List<Json> mentions;
  final TextStyle style;
  final Color accent;
  final ValueChanged<Json> onOpen;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final people = [
      for (final mention in widget.mentions)
        if (value(mention['name']).isNotEmpty &&
            text.contains(value(mention['name'])))
          mention,
    ];
    final names = [for (final m in people) value(m['name'])];
    final mentionRanges = names.isEmpty
        ? const <TextRange>[]
        : findMentionRanges(text, names);
    // Web links too, where they do not overlap a mention.
    final links = text.contains('http') || text.contains('www.')
        ? [
            for (final link in findLinks(text))
              if (!mentionRanges.any(
                (r) => r.start < link.$2 && link.$1 < r.end,
              ))
                link,
          ]
        : const <(int, int, String)>[];
    if (mentionRanges.isEmpty && links.isEmpty) {
      return Text(
        text,
        textDirection: contentDirection(text),
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
      );
    }
    final direction = mentionAwareDirection(
      text,
      names,
      Directionality.of(context),
    );
    final pieces = <(int, int, String?)>[
      for (final range in mentionRanges) (range.start, range.end, null),
      for (final link in links) (link.$1, link.$2, link.$3),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    _clear();
    final children = <InlineSpan>[];
    var at = 0;
    final style = widget.style.merge(
      TextStyle(color: widget.accent, fontWeight: FontWeight.w600),
    );
    final linkStyle = widget.style.merge(TextStyle(color: widget.accent));
    for (final (start, end, url) in pieces) {
      if (start > at) {
        children.add(TextSpan(text: text.substring(at, start)));
      }
      final shown = text.substring(start, end);
      final recognizer = TapGestureRecognizer();
      _recognizers.add(recognizer);
      if (url != null) {
        recognizer.onTap = () => openExternalLink(url);
        children
          ..add(const TextSpan(text: '\u2066'))
          ..add(TextSpan(text: shown, style: linkStyle, recognizer: recognizer))
          ..add(const TextSpan(text: '\u2069'));
      } else {
        final person = people.firstWhere(
          (m) => value(m['name']) == shown.replaceFirst('@', ''),
          orElse: () => const {},
        );
        recognizer.onTap = () => widget.onOpen(person);
        // Isolate each name so a Latin name inside Arabic text (and the
        // reverse) keeps its own order without flipping the sentence.
        children
          ..add(const TextSpan(text: '\u2068'))
          // Shown as "@Name", like the website, whether or not the text has the "@".
          ..add(
            TextSpan(
              text: shown.startsWith('@') ? shown : '@$shown',
              style: style,
              recognizer: recognizer,
            ),
          )
          ..add(const TextSpan(text: '\u2069'));
      }
      at = end;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: widget.style, children: children),
      key: const ValueKey('mention.text'),
      textDirection: direction,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
