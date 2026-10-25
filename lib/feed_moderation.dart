import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_comments.dart' show confirmDelete;
import 'web_home.dart' show webAgo, webBorder, webMuted, webSecondary;

/// Admin › Feed moderation: find a member by student ID, page through their
/// public posts and comments five at a time, and delete any of them after a
/// confirmation dialog.
class FeedModerationContent extends StatefulWidget {
  const FeedModerationContent({super.key, required this.page});
  final NativePageState page;

  @override
  State<FeedModerationContent> createState() => _FeedModerationContentState();
}

class _FeedModerationContentState extends State<FeedModerationContent> {
  NativePageState get p => widget.page;
  late final search = TextEditingController(text: value(p.data['query']));

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _find() {
    final id = latinDigits(search.text.trim());
    if (id.isEmpty) return;
    FocusScope.of(context).unfocus();
    p.load(
      Uri(
        path: '/admin/feed',
        queryParameters: {'university_id': id},
      ).toString(),
    );
  }

  void _page(Object? url) {
    final link = value(url);
    if (link.isEmpty) return;
    final uri = Uri.parse(link);
    p.load(
      Uri(path: uri.path, queryParameters: uri.queryParameters).toString(),
    );
  }

  Future<void> _delete(String kind, Json item) async {
    final c = p.c;
    final post = kind == 'post';
    final result = await confirmDelete(
      context,
      p,
      '/admin/feed/${post ? 'posts' : 'comments'}/${item['id']}',
      post
          ? c.t('Delete this post?', 'تحذف المنشور ده؟')
          : c.t('Delete this comment?', 'تحذف التعليق ده؟'),
      c.t(
        'It will be removed for everyone and can’t be restored.',
        'هيتشال عند الكل ومش هينفع يرجع تاني.',
      ),
    );
    if (result == null || !mounted) return;
    final message = value(result['message']);
    if (message.isNotEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
    await p.load();
  }

  Widget _item(String kind, Json item) {
    final c = p.c, ar = c.settings.language == 'ar';
    final text = value(item['content']);
    final post = object(item['post']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: webSecondary(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: webBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  textDirection: contentDirection(text),
                  style: const TextStyle(fontSize: 14.5, height: 1.55),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    webAgo(item['created_at'], ar),
                    if (kind == 'post')
                      c.t(
                        '${item['comments_count'] ?? 0} comments',
                        '${item['comments_count'] ?? 0} تعليق',
                      ),
                    if (post.isNotEmpty)
                      c.t('On: ', 'على: ') + value(post['content']),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: webMuted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('moderation.delete.$kind.${item['id']}'),
            tooltip: c.t('Delete', 'حذف'),
            onPressed: () => _delete(kind, item),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xffc53d46),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String kind, String title, String empty, Json page) {
    final c = p.c;
    final items = rows(page['data']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (items.isEmpty)
          Text(empty, style: TextStyle(color: webMuted(context)))
        else
          for (final item in items) _item(kind, item),
        if (value(page['prev_page_url']).isNotEmpty ||
            value(page['next_page_url']).isNotEmpty)
          Row(
            children: [
              if (value(page['prev_page_url']).isNotEmpty)
                OutlinedButton(
                  onPressed: () => _page(page['prev_page_url']),
                  child: Text(c.t('Previous', 'السابق')),
                ),
              const Spacer(),
              if (value(page['next_page_url']).isNotEmpty)
                FilledButton(
                  key: ValueKey('moderation.next.$kind'),
                  onPressed: () => _page(page['next_page_url']),
                  child: Text(c.t('Next', 'التالي')),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c;
    final member = object(p.data['member']);
    final query = value(p.data['query']);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        14,
        14,
        14,
        MediaQuery.paddingOf(context).bottom + 110,
      ),
      children: [
        Text(
          c.t(
            'Find a member by student ID to review and delete their posts and comments.',
            'دوّر على طالب برقمه الجامعي عشان تراجع منشوراته وتعليقاته وتحذف منها.',
          ),
          style: TextStyle(color: webMuted(context), height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('moderation.search'),
                controller: search,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                textDirection: TextDirection.ltr,
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (_, value) => value.copyWith(text: latinDigits(value.text)),
                  ),
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: InputDecoration(
                  hintText: c.t('Student ID', 'الرقم الجامعي'),
                ),
                onSubmitted: (_) => _find(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _find, child: Text(c.t('Find', 'دوّر'))),
          ],
        ),
        if (query.isNotEmpty && member.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              c.t('No member has this student ID.', 'مفيش طالب بالرقم ده.'),
              style: TextStyle(color: webMuted(context)),
            ),
          ),
        if (member.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              p.avatar(member, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value(member['name']),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      value(member['university_id']),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: webMuted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _section(
            'post',
            c.t('Latest posts', 'آخر المنشورات'),
            c.t('No public posts.', 'مفيش منشورات عامة.'),
            object(p.data['posts']),
          ),
          _section(
            'comment',
            c.t('Latest comments', 'آخر التعليقات'),
            c.t('No comments.', 'مفيش تعليقات.'),
            object(p.data['comments']),
          ),
        ],
      ],
    );
  }
}
