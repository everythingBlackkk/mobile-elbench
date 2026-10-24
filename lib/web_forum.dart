import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'api.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'infinite_feed.dart';
import 'text_direction.dart';
import 'web_style.dart';
import 'web_home.dart' show webAgo, webMuted;

class _ForumColors {
  _ForumColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get main => dark ? const Color(0xff0a0a0a) : Colors.white;
  Color get secondary =>
      dark ? const Color(0xff141414) : const Color(0xfff9fafb);
  Color get text => dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
  Color get muted => dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get border => dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
  Color get hover => dark ? const Color(0xff202020) : const Color(0xfff3f4f6);
  Color get accent => dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
  Color get fill => const Color(0xff2e855d);
}

final _forumAvatarFilenamePattern = RegExp(r'^u[A-Za-z0-9]{14}\.webp$');

Json _questionPerson(Json question) {
  final person = object(question['author']);
  if (person.isNotEmpty) return person;
  final avatar = value(question['avatar'], 'jko.webp');
  return {
    'id': question['user_id'],
    'name': question['name'],
    'university_id': question['university_id'],
    'avatar': avatar,
    'avatar_url':
        question['avatar_url'] ??
        (_forumAvatarFilenamePattern.hasMatch(avatar)
            ? '/profile-media/$avatar'
            : '/avatars/$avatar'),
    'badge': question['badge'],
  };
}

String _forumDate(dynamic source, {bool padded = false}) {
  final parsed = DateTime.tryParse(value(source));
  return parsed == null
      ? value(source)
      : DateFormat(
          padded ? 'MMM dd, yyyy' : 'MMM d, yyyy',
          'en',
        ).format(parsed.toLocal());
}

String _forumAgo(Json question) {
  final source = question['created_at'];
  final parsed = DateTime.tryParse(value(source));
  if (parsed == null) return value(source);
  if (DateTime.now().difference(parsed).inDays >= 7) return _forumDate(source);
  return webAgo(source, false);
}

String _approvalHelp(NativePageState page) => page.c.t(
  yes(page.data['questionRequiresApproval'])
      ? 'Your question will appear after a Community Admin approves it.'
      : 'Your question will be published immediately.',
  yes(page.data['questionRequiresApproval'])
      ? 'سيظهر سؤالك بعد موافقة مدير المجتمع عليه.'
      : 'سيتم نشر سؤالك فورًا.',
);

Widget _forumButton(
  BuildContext context,
  String text,
  VoidCallback? tap, {
  String? icon,
  Color? background,
  Color? foreground,
  Color? border,
  double radius = 14,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  double minHeight = 42,
}) {
  final colors = _ForumColors(context);
  return Material(
    color: background ?? colors.secondary,
    borderRadius: BorderRadius.circular(radius),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              WebIcon(icon, size: 16, color: foreground ?? colors.text),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: foreground ?? colors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _forumStatus(NativePageState page) {
  final status = value(page.envelope['status']);
  return status.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(
            status,
            style: TextStyle(
              color: webMuted(page.context),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
}

class WebForum extends StatefulWidget {
  const WebForum({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebForum> createState() => _WebForumState();
}

class _WebForumState extends State<WebForum> {
  late final search = TextEditingController(
    text: Uri.parse(widget.page.path).queryParameters['search'],
  );
  NativePageState get page => widget.page;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> compose() async {
    final changed = await Navigator.of(context, rootNavigator: true).push<Json>(
      PageRouteBuilder<Json>(
        fullscreenDialog: true,
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _CommunityComposer(page: page),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.of(context).accessibleNavigation) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.22, 1.0, 0.36, 1.0),
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (changed != null && page.mounted) {
      await page.load(
        value(
          changed['redirect_url'],
          '/forum?community_id=${object(page.data['community'])['id']}&my_questions=1',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final community = object(page.data['community']);
    final id = community['id'] ?? page.data['community_id'];
    final image = value(community['image_url'] ?? page.data['comm_img']);
    final questions = rows(page.data['questions']);
    return RefreshIndicator.adaptive(
      onRefresh: page.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 110),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            height: 140,
            margin: const EdgeInsets.only(bottom: 24),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [const Color(0xff1e1b4b), colors.accent],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image.isNotEmpty)
                  networkImage(
                    c.api.media(image),
                    fit: BoxFit.cover,
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(320, 1440),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                const ColoredBox(color: Color(0x73000000)),
                if (yes(page.data['can_moderate']) &&
                    (int.tryParse(value(page.data['pending_count'])) ?? 0) > 0)
                  PositionedDirectional(
                    top: 12,
                    end: 12,
                    child: _forumButton(
                      context,
                      '${c.t('Pending Questions', 'الأسئلة المعلقة')} (${page.data['pending_count']})',
                      () => c.open('/moderate?community_id=$id'),
                      icon: 'check',
                      background: Colors.white.withValues(alpha: .12),
                      foreground: Colors.white,
                      border: Colors.white.withValues(alpha: .2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minHeight: 34,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value(community['name']),
            style: TextStyle(
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w900,
              letterSpacing: -.75,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value(community['description']),
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _forumButton(
                context,
                c.t('Ask Question', 'اسأل سؤال'),
                compose,
                icon: 'plus',
                background: colors.dark ? Colors.white : Colors.black,
                foreground: colors.main,
              ),
              _forumButton(
                context,
                c.t('My Questions', 'أسئلتي'),
                () => page.query({'my_questions': 1}),
                icon: 'user',
                border: colors.border,
              ),
            ],
          ),
          const SizedBox(height: 32),
          _forumStatus(page),
          SizedBox(
            height: 54,
            child: AdaptiveTextField(
              controller: search,
              field: (direction) => TextField(
                controller: search,
                textDirection: direction,
                onSubmitted: (text) => page.query({'search': text}),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 16, color: colors.text),
                decoration: InputDecoration(
                  hintText: c.t('Search questions...', 'ابحث في الأسئلة...'),
                  hintStyle: TextStyle(
                    color: colors.muted.withValues(alpha: .7),
                  ),
                  filled: true,
                  fillColor: colors.hover,
                  isDense: true,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: WebIcon('search', size: 17, color: colors.muted),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    maxWidth: 44,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: colors.dark ? Colors.white : Colors.black,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (questions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
              decoration: BoxDecoration(
                color: colors.secondary,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  WebIcon('message', size: 40, color: colors.muted),
                  const SizedBox(height: 16),
                  Text(
                    c.t('No Questions Yet', 'مفيش أسئلة لسه'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.t('Be the first to ask a question!', 'كن أول واحد يسأل!'),
                    style: TextStyle(fontSize: 14.4, color: colors.muted),
                  ),
                ],
              ),
            ),
          for (final item in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ForumQuestionCard(page: page, item: item),
            ),
          page.more('pagination', listKey: 'questions'),
        ],
      ),
    );
  }
}

class _ForumQuestionCard extends StatelessWidget {
  const _ForumQuestionCard({required this.page, required this.item});
  final NativePageState page;
  final Json item;
  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final person = _questionPerson(item);
    final content = value(item['content']).trim();
    return Material(
      color: colors.secondary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTapDown: (_) => c.prefetch('/question?id=${item['id']}'),
        onTap: () => c.open(
          '/question?id=${item['id']}',
          // The question renders from this row while its answers load.
          seed: {
            'screen': 'community.question',
            'data': {
              'question': item,
              'answers': null,
              'pagination': null,
              'can_answer': true,
            },
          },
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border, width: 1.5),
                    ),
                    child: page.avatar(person, radius: 20.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              value(person['name']),
                              style: const TextStyle(
                                fontSize: 14.4,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                            if (person['badge'] != null)
                              UserBadge(api: c.api, badge: person['badge']),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _forumAgo(item),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                content.characters.take(280).toString(),
                textDirection: contentDirection(content),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.4,
                  height: 1.5,
                  color: colors.text.withValues(alpha: .95),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    WebIcon('message', size: 14, color: colors.muted),
                    const SizedBox(width: 5),
                    Text(
                      '${item['answer_count'] ?? item['answers_count'] ?? 0} ${c.t('answers', 'إجابات')}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _eye(colors.muted),
                    const SizedBox(width: 5),
                    Text(
                      c.t('View', 'عرض'),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _eyeSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>';

Widget _eye(Color color) => SvgPicture.string(
  _eyeSvg,
  width: 14,
  height: 14,
  colorFilter: svgColorFilter(color),
);

class WebCommunityAsk extends StatefulWidget {
  const WebCommunityAsk({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebCommunityAsk> createState() => _WebCommunityAskState();
}

class _WebCommunityAskState extends State<WebCommunityAsk> {
  final input = TextEditingController();
  bool busy = false;
  String? error;
  NativePageState get page => widget.page;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || input.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await page.c.action('POST', '/ask-question', {
        'community_id':
            page.data['community_id'] ?? object(page.data['community'])['id'],
        'content': input.text.trim(),
      });
      if (page.mounted) {
        await page.load(
          value(
            result['redirect_url'],
            '/forum?community_id=${object(page.data['community'])['id']}&my_questions=1',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final status = value(page.envelope['status']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 110),
      children: [
        Text(
          c.t(
            'Share your question with the community',
            'شارك سؤالك مع المجتمع',
          ),
          style: TextStyle(fontSize: 14, height: 1.6, color: colors.muted),
        ),
        Text(
          _approvalHelp(page),
          style: TextStyle(fontSize: 14, height: 1.6, color: colors.muted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: colors.secondary,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (status.isNotEmpty || error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: error != null
                        ? const Color(0x1aef4444)
                        : colors.accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      WebIcon(
                        error != null ? 'flag' : 'check',
                        color: error != null
                            ? const Color(0xffc53d46)
                            : colors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error ?? status,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: error != null
                                ? const Color(0xffc53d46)
                                : colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Text(
                    c.t('Question', 'السؤال'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: input,
                    builder: (_, text, _) => Text(
                      '${text.text.characters.length} / 500',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              AdaptiveTextField(
                controller: input,
                field: (direction) => TextField(
                  controller: input,
                  textDirection: direction,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 500,
                  style: const TextStyle(fontSize: 16, height: 1.6),
                  decoration: InputDecoration(
                    hintText: c.t('Write your question...', 'اكتب سؤالك...'),
                    hintStyle: TextStyle(
                      color: colors.muted.withValues(alpha: .8),
                    ),
                    filled: true,
                    fillColor: colors.main,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(color: colors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _forumButton(
                    context,
                    busy ? '…' : c.t('Submit Question', 'نشر السؤال'),
                    busy ? null : submit,
                    icon: 'paper-plane',
                    background: colors.fill,
                    foreground: Colors.white,
                    radius: 13,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    minHeight: 46,
                  ),
                  _forumButton(
                    context,
                    c.t('Cancel', 'إلغاء'),
                    () => page.c.open(
                      '/forum?community_id=${object(page.data['community'])['id']}',
                    ),
                    background: colors.hover,
                    radius: 13,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    minHeight: 46,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityComposer extends StatefulWidget {
  const _CommunityComposer({required this.page, this.answer});
  final NativePageState page;
  final Json? answer;
  @override
  State<_CommunityComposer> createState() => _CommunityComposerState();
}

class _CommunityComposerState extends State<_CommunityComposer> {
  late final input = TextEditingController(
    text: value(widget.answer?['content']),
  );
  bool busy = false;
  String? error;
  NativePageState get page => widget.page;
  bool get editing => widget.answer != null;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || input.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await page.c.action(
        editing ? 'PUT' : 'POST',
        editing ? '/question/answers/${widget.answer!['id']}' : '/ask-question',
        editing
            ? {'comment_content': input.text.trim()}
            : {
                'community_id': object(page.data['community'])['id'],
                'content': input.text.trim(),
              },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final max = editing ? 1000 : 500;
    return Scaffold(
      backgroundColor: colors.main,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.text,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 38),
                    ),
                    child: Text(
                      c.t('Cancel', 'إلغاء'),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: input,
                    builder: (_, text, _) => Opacity(
                      opacity: busy || text.text.trim().isEmpty ? .45 : 1,
                      child: _forumButton(
                        context,
                        busy
                            ? '…'
                            : editing
                            ? c.t('Save changes', 'حفظ التغييرات')
                            : c.t('Submit Question', 'نشر السؤال'),
                        busy || text.text.trim().isEmpty ? null : submit,
                        background: colors.fill,
                        foreground: Colors.white,
                        radius: 99,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 9,
                        ),
                        minHeight: 38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    page.avatar(c.user ?? {}, radius: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!editing) ...[
                            Text(
                              value(c.user?['name']),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              value(object(page.data['community'])['name']),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Expanded(
                            child: AdaptiveTextField(
                              controller: input,
                              field: (direction) => TextField(
                                controller: input,
                                textDirection: direction,
                                maxLength: max,
                                maxLines: null,
                                expands: true,
                                autofocus: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: colors.text,
                                ),
                                decoration: InputDecoration(
                                  hintText: c.t(
                                    'Write your question...',
                                    'اكتب سؤالك...',
                                  ),
                                  hintStyle: TextStyle(
                                    color: colors.muted.withValues(alpha: .85),
                                  ),
                                  counterText: '',
                                  filled: false,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ),
                          if (error != null)
                            Text(
                              error!,
                              style: const TextStyle(
                                color: Color(0xffef4444),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  if (!editing) ...[
                    WebIcon(
                      yes(page.data['questionRequiresApproval'])
                          ? 'clock'
                          : 'globe',
                      size: 17,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _approvalHelp(page),
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.accent,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else
                    const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: input,
                    builder: (_, text, _) => Text(
                      '${text.text.characters.length} / ${editing ? '1,000' : '500'}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WebCommunityQuestion extends StatefulWidget {
  const WebCommunityQuestion({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebCommunityQuestion> createState() => _WebCommunityQuestionState();
}

class _WebCommunityQuestionState extends State<WebCommunityQuestion> {
  final reply = TextEditingController();
  bool busy = false;
  String? error;
  NativePageState get page => widget.page;
  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || reply.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await page.c.action('POST', '/question/answer', {
        'id': object(page.data['question'])['id'],
        'answer_content': reply.text.trim(),
      });
      reply.clear();
      if (page.mounted) await page.load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final question = object(page.data['question']);
    final author = _questionPerson(question);
    final answers = rows(page.data['answers']);
    return Stack(
      children: [
        RefreshIndicator.adaptive(
          onRefresh: page.pullRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 106),
            children: [
              _QuestionAuthor(
                page: page,
                person: author,
                date: _forumDate(question['created_at']),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 16),
                child: Text(
                  value(question['content']).trim(),
                  textDirection: contentDirection(value(question['content'])),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: colors.text,
                  ),
                ),
              ),
              Row(
                children: [
                  WebIcon('message', size: 18, color: colors.muted),
                  const SizedBox(width: 8),
                  Text(
                    '${question['answer_count'] ?? question['answers_count'] ?? 0} ${c.t('answers', 'إجابات')}',
                    style: TextStyle(fontSize: 13, color: colors.muted),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Divider(color: colors.border, height: 1, thickness: 1),
              ),
              if (page.provisional && page.data['answers'] == null)
                const CommentsSkeleton()
              else if (answers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      WebIcon(
                        'message',
                        size: 36,
                        color: colors.muted.withValues(alpha: .65),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        c.t('No answers yet.', 'مفيش إجابات لسه.'),
                        style: TextStyle(fontSize: 14, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              for (var index = 0; index < answers.length; index++)
                _QuestionAnswer(
                  page: page,
                  item: answers[index],
                  last: index == answers.length - 1,
                ),
              page.more('pagination', listKey: 'answers', compact: true),
            ],
          ),
        ),
        PositionedDirectional(
          start: 10,
          end: 10,
          bottom: 12 + MediaQuery.paddingOf(context).bottom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  color: colors.main,
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xffef4444),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.main.withValues(alpha: .94),
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0f000000),
                      offset: Offset(0, 4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: yes(page.data['can_answer'])
                    ? Row(
                        children: [
                          page.avatar(c.user ?? {}, radius: 17),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AdaptiveTextField(
                              controller: reply,
                              field: (direction) => TextField(
                                controller: reply,
                                textDirection: direction,
                                maxLength: 1000,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colors.text,
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => submit(),
                                decoration: InputDecoration(
                                  hintText: c.t(
                                    'Write your answer...',
                                    'اكتب إجابتك...',
                                  ),
                                  hintStyle: TextStyle(color: colors.muted),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: colors.fill,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: busy ? null : submit,
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: Center(
                                  child: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const WebIcon(
                                          'send',
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          WebIcon('lock', color: colors.muted),
                          const SizedBox(width: 8),
                          Text(
                            c.t('This question is locked.', 'السؤال ده مقفول.'),
                            style: TextStyle(fontSize: 14, color: colors.muted),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionAuthor extends StatelessWidget {
  const _QuestionAuthor({
    required this.page,
    required this.person,
    required this.date,
    this.avatar = true,
    this.edited = false,
  });
  final NativePageState page;
  final Json person;
  final String date;
  final bool avatar, edited;
  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context);
    return Row(
      children: [
        if (avatar) ...[
          InkWell(
            onTap: () => page.c.open('/users/${person['id']}'),
            child: page.avatar(person, radius: 21),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    onTap: () => page.c.open('/users/${person['id']}'),
                    child: Text(
                      value(person['name']),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                  ),
                  if (person['badge'] != null)
                    UserBadge(api: page.c.api, badge: person['badge']),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  Text(
                    '@${value(person['university_id'])}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '·',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    date,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  if (edited)
                    Text(
                      '· ${page.c.t('Edited', 'تم التعديل')}',
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionAnswer extends StatelessWidget {
  const _QuestionAnswer({
    required this.page,
    required this.item,
    required this.last,
  });
  final NativePageState page;
  final Json item;
  final bool last;
  Future<void> edit(BuildContext context) async {
    final changed = await Navigator.of(context).push<Json>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CommunityComposer(page: page, answer: item),
      ),
    );
    if (changed != null && page.mounted) await page.load();
  }

  Future<void> remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ForumColors(context).main,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          page.c.t('Delete comment?', 'حذف التعليق؟'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: Text(
          page.c.t(
            'This comment will be permanently deleted.',
            'سيتم حذف التعليق نهائيًا.',
          ),
          style: const TextStyle(fontSize: 14, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(page.c.t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              page.c.t('Delete', 'حذف'),
              style: const TextStyle(color: Color(0xffdc2626)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && page.mounted) {
      await page.run('DELETE', '/question/answers/${item['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context), c = page.c;
    final person = object(item['author']);
    final own = '${item['user_id']}' == '${c.user?['id']}';
    final canDelete = own || c.permission('communities.manage');
    return Stack(
      children: [
        if (!last)
          PositionedDirectional(
            start: 20,
            top: 46,
            bottom: 0,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => c.open('/users/${person['id']}'),
                child: page.avatar(person, radius: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _QuestionAuthor(
                            page: page,
                            person: person,
                            avatar: false,
                            date: webAgo(
                              item['created_at'],
                              c.settings.language == 'ar',
                            ),
                            edited: item['edited_at'] != null,
                          ),
                        ),
                        if (canDelete)
                          AppPopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            color: colors.main,
                            position: PopupMenuPosition.under,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: colors.border),
                            ),
                            onSelected: (action) => action == 'edit'
                                ? edit(context)
                                : remove(context),
                            itemBuilder: (_) => [
                              if (own)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const WebIcon('edit', size: 17),
                                      const SizedBox(width: 9),
                                      Text(
                                        c.t('Edit comment', 'تعديل التعليق'),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const WebIcon(
                                      'delete',
                                      size: 17,
                                      color: Color(0xffef4444),
                                    ),
                                    const SizedBox(width: 9),
                                    Text(
                                      c.t('Delete comment', 'حذف التعليق'),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xffef4444),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            child: SizedBox(
                              width: 36,
                              height: 32,
                              child: Center(
                                child: Text(
                                  '⋯',
                                  style: TextStyle(
                                    fontSize: 25,
                                    color: colors.muted,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 10),
                      child: Text(
                        value(item['content']).trim(),
                        textDirection: contentDirection(value(item['content'])),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.7,
                          color: colors.text,
                        ),
                      ),
                    ),
                    _AnswerReactions(page: page, item: item),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _answerThumbSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000"><path d="M7 10v10H4V10h3Zm0 0 5-7c2 0 2.5 2 1.5 5H19a2 2 0 0 1 2 2l-1.5 8A2 2 0 0 1 17.5 20H7" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>';

class _AnswerReactions extends StatefulWidget {
  const _AnswerReactions({required this.page, required this.item});
  final NativePageState page;
  final Json item;
  @override
  State<_AnswerReactions> createState() => _AnswerReactionsState();
}

class _AnswerReactionsState extends State<_AnswerReactions> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context);
    final selected = rows(widget.item['reactions']).firstOrNull?['type'];
    const emojis = {'like': '👍', 'love': '❤️', 'funny': '😂'};
    final total = emojis.keys.fold<int>(
      0,
      (sum, key) =>
          sum + (int.tryParse(value(widget.item['${key}_count'])) ?? 0),
    );
    return Row(
      children: [
        Material(
          color: selected == null
              ? colors.hover
              : colors.accent.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => setState(() => open = !open),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: selected != null
                    ? Text(
                        emojis[selected] ?? '',
                        style: const TextStyle(fontSize: 18, height: 1),
                      )
                    : SvgPicture.string(
                        _answerThumbSvg,
                        width: 20,
                        height: 20,
                        colorFilter: svgColorFilter(colors.muted),
                      ),
              ),
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(width: 6),
          for (final emoji in emojis.entries)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                setState(() => open = false);
                await widget.page.react(
                  '/answers/${widget.item['id']}/reactions',
                  widget.item,
                  emoji.key,
                );
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    emoji.value,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
        ] else if (total > 0) ...[
          const SizedBox(width: 10),
          for (final emoji in emojis.entries)
            if ((int.tryParse(value(widget.item['${emoji.key}_count'])) ?? 0) >
                0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Text(
                  emoji.value,
                  style: const TextStyle(fontSize: 14, height: 20 / 14),
                ),
              ),
          const SizedBox(width: 3),
          Text('$total', style: TextStyle(fontSize: 13, color: colors.muted)),
        ],
      ],
    );
  }
}

class WebModerate extends StatelessWidget {
  const WebModerate({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final colors = _ForumColors(context);
    final community = object(page.data['community']);
    final questions = rows(page.data['pending_questions']);
    return RefreshIndicator.adaptive(
      onRefresh: page.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 40, 10, 110),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            'Pending Questions in ${value(community['name'])}',
            style: TextStyle(
              fontSize: 36,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -.9,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review and approve or delete questions submitted by community members.',
            style: TextStyle(
              fontSize: 18,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 40),
          if (questions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.secondary,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const Text('✅', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  const Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'There are no pending questions to review.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          for (final item in questions)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.secondary,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Submitted by '),
                            TextSpan(
                              text: value(item['name']),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.text,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: colors.muted,
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(fontSize: 14, color: colors.muted),
                      ),
                      Text(
                        _forumDate(item['created_at'], padded: true),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.main.withValues(alpha: .5),
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      value(item['content']),
                      textDirection: contentDirection(value(item['content'])),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.625,
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _ModerationButton(
                        page: page,
                        question: item,
                        communityId: community['id'],
                        approve: true,
                      ),
                      _ModerationButton(
                        page: page,
                        question: item,
                        communityId: community['id'],
                        approve: false,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: page.pagination(page.data['pagination']),
          ),
        ],
      ),
    );
  }
}

class _ModerationButton extends StatelessWidget {
  const _ModerationButton({
    required this.page,
    required this.question,
    required this.communityId,
    required this.approve,
  });
  final NativePageState page;
  final Json question;
  final dynamic communityId;
  final bool approve;
  Future<void> submit(BuildContext context) async {
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text('Are you sure you want to delete this question?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (page.mounted) {
      await page.run('POST', '/moderate', {
        'community_id': communityId,
        'question_id': question['id'],
        'action': approve ? 'approve' : 'delete',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = approve ? const Color(0xff22c55e) : const Color(0xffef4444);
    return InkWell(
      onTap: () => submit(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebIcon(approve ? 'check' : 'delete', size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              approve ? 'Approve' : 'Delete',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
