import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart' show svgColorFilter;

const _stickerButtonSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7"><path d="M14 21H6a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8l-7 7Z"/><path d="M14 21v-4a3 3 0 0 1 3-3h4M8 9h.01M15 9h.01M8 13c2 2 5 2 7 0" stroke-linecap="round" stroke-linejoin="round"/></svg>';

class _CommentColors {
  _CommentColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get main => dark ? const Color(0xff0a0a0a) : Colors.white;
  Color get secondary =>
      dark ? const Color(0xff141414) : const Color(0xfff9fafb);
  Color get text => dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
  Color get muted => dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get border => dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
  Color get accent => dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
}

Future<void> editWebComment(
  BuildContext context,
  NativePageState page,
  Json comment,
  String endpoint,
) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          WebCommentEditor(page: page, comment: comment, endpoint: endpoint),
    ),
  );
  if (changed == true && page.mounted) await page.load();
}

Future<void> deleteWebPost(
  BuildContext context,
  NativePageState page,
  Json post,
) async {
  final result = await _deleteDialog(
    context,
    page,
    '/community/posts/${post['id']}',
    page.c.t('Delete this post?', 'تمسح المنشور؟'),
    page.c.t(
      'This will permanently remove your post, comments and reactions.',
      'المنشور وتعليقاته والتفاعلات عليه هيتشالوا نهائي.',
    ),
  );
  if (result == null || !page.mounted) return;
  // The detail resource no longer exists; honor the server's destination there.
  // A feed/profile list can refresh in place without losing its current page.
  await page.load(
    page.screen == 'community.post'
        ? value(result['redirect_url'], '/community')
        : null,
  );
}

Future<void> deleteWebComment(
  BuildContext context,
  NativePageState page,
  Json comment,
  String endpoint,
) async {
  final result = await _deleteDialog(
    context,
    page,
    endpoint,
    page.c.t('Delete this comment?', 'تحذف التعليق ده؟'),
    page.c.t(
      'This will permanently remove the comment, its reactions and any existing replies.',
      'التعليق وتفاعلاته وأي ردود قديمة عليه هيتحذفوا نهائيًا.',
    ),
  );
  if (result == null || !page.mounted) return;
  final postId = object(page.data['post'])['id'] ?? comment['feed_post_id'];
  final root = object(page.data['threadRoot']);
  final removedRoot = root.isNotEmpty && '${root['id']}' == '${comment['id']}';
  final current = Uri.parse(page.path);
  final parameters = <String, String>{
    if (current.path.startsWith('/community/posts/'))
      ...current.queryParameters,
  };
  // A deleted focus target (or a deleted root's descendant) cannot be resolved
  // by the server. Use the canonical post route after every successful delete.
  parameters.remove('focus_comment');
  parameters.remove('comment');
  if (removedRoot) {
    parameters.remove('thread');
    parameters.remove('page');
  } else if (root.isNotEmpty) {
    parameters['thread'] = '${root['id']}';
  }
  await page.load(
    Uri(
      path: '/community/posts/$postId',
      queryParameters: parameters.isEmpty ? null : parameters,
    ).toString(),
  );
}

Future<Json?> _deleteDialog(
  BuildContext context,
  NativePageState page,
  String endpoint,
  String title,
  String description,
) => showDialog<Json>(
  context: context,
  barrierColor: const Color(0x73000000),
  builder: (_) => _DeleteDialog(
    page: page,
    endpoint: endpoint,
    title: title,
    description: description,
  ),
);

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.page,
    required this.endpoint,
    required this.title,
    required this.description,
  });
  final NativePageState page;
  final String endpoint, title, description;
  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool busy = false;
  String? error;
  Future<void> remove() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.page.c.action('DELETE', widget.endpoint);
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
    final colors = _CommentColors(context), c = widget.page.c;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Dialog(
        backgroundColor: colors.secondary,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: colors.muted,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xffef4444),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _dialogButton(
                      context,
                      c.t('Cancel', 'إلغاء'),
                      busy ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    _dialogButton(
                      context,
                      busy ? c.t('Deleting…', 'بنمسح…') : c.t('Delete', 'حذف'),
                      busy ? null : remove,
                      danger: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _dialogButton(
  BuildContext context,
  String label,
  VoidCallback? tap, {
  bool danger = false,
}) {
  final colors = _CommentColors(context);
  return Material(
    color: danger ? const Color(0xffdc2626) : colors.main,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      key: danger ? const ValueKey('delete.confirm') : null,
      onTap: tap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: danger ? const Color(0xffdc2626) : colors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: danger ? Colors.white : colors.text,
            height: 1.5,
          ),
        ),
      ),
    ),
  );
}

class WebCommentEditor extends StatefulWidget {
  const WebCommentEditor({
    super.key,
    required this.page,
    required this.comment,
    required this.endpoint,
  });
  final NativePageState page;
  final Json comment;
  final String endpoint;
  @override
  State<WebCommentEditor> createState() => _WebCommentEditorState();
}

class _WebCommentEditorState extends State<WebCommentEditor> {
  late final text = TextEditingController(
    text: value(widget.comment['content']),
  );
  late String stickerId = value(widget.comment['sticker_id']);
  bool busy = false;
  String? error;
  NativePageState get page => widget.page;
  bool get canSave =>
      !busy && (text.text.trim().isNotEmpty || stickerId.isNotEmpty);
  String stickerUrl(String id) =>
      page.c.api.media('/comment-stickers/$id.webp');
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!canSave) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await page.c.action('PUT', widget.endpoint, {
        'comment_content': text.text.trim(),
        // Explicit empty removes a sticker; omission would preserve it.
        'sticker_id': stickerId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> chooseSticker() async {
    final colors = _CommentColors(context), c = page.c;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: colors.secondary,
        insetPadding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.border),
        ),
        child: SizedBox(
          width: 360,
          height: 350,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.t('Stickers', 'الملصقات'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        c.t('Close', 'اقفل'),
                        style: TextStyle(fontSize: 13, color: colors.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      for (final sticker in rows(page.data['stickers']))
                        Material(
                          color: colors.main,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colors.border),
                          ),
                          child: InkWell(
                            key: ValueKey('sticker.${sticker['id']}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                Navigator.pop(context, value(sticker['id'])),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Image.network(
                                value(sticker['url']).isEmpty
                                    ? stickerUrl(value(sticker['id']))
                                    : page.c.api.media(value(sticker['url'])),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => stickerId = selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _CommentColors(context), c = page.c;
    return Scaffold(
      backgroundColor: colors.main,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 38),
                      foregroundColor: colors.text,
                    ),
                    child: Text(
                      c.t('Cancel', 'إلغاء'),
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: text,
                    builder: (_, _, _) => Opacity(
                      opacity: canSave ? 1 : .45,
                      child: Material(
                        color: const Color(0xff2e855d),
                        borderRadius: BorderRadius.circular(99),
                        child: InkWell(
                          key: const ValueKey('comment.editor.save'),
                          onTap: canSave ? save : null,
                          borderRadius: BorderRadius.circular(99),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 9,
                            ),
                            child: Text(
                              busy
                                  ? c.t('Saving…', 'جاري الحفظ…')
                                  : c.t('Save changes', 'احفظ التعديل'),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    page.avatar(c.user ?? {}, radius: 21),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AdaptiveTextField(
                        controller: text,
                        field: (direction) => TextField(
                          key: const ValueKey('comment.editor.text'),
                          controller: text,
                          textDirection: direction,
                          autofocus: true,
                          maxLength: 1000,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: colors.text,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xffef4444),
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          label: c.t('Choose a sticker', 'اختار ملصق'),
                          button: true,
                          child: InkWell(
                            key: const ValueKey('comment.editor.chooseSticker'),
                            onTap: busy ? null : chooseSticker,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 36,
                              height: 44,
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: stickerId.isEmpty
                                    ? null
                                    : colors.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SvgPicture.string(
                                _stickerButtonSvg,
                                width: 24,
                                height: 24,
                                colorFilter: svgColorFilter(
                                  stickerId.isEmpty
                                      ? colors.muted
                                      : colors.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (stickerId.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colors.secondary,
                              border: Border.all(color: colors.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.network(
                                  stickerUrl(stickerId),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox(width: 64, height: 64),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.t('Sticker', 'ملصق'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.muted,
                                        ),
                                      ),
                                      InkWell(
                                        key: const ValueKey(
                                          'comment.editor.removeSticker',
                                        ),
                                        onTap: busy
                                            ? null
                                            : () => setState(
                                                () => stickerId = '',
                                              ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            c.t(
                                              'Remove sticker',
                                              'إزالة الملصق',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: colors.accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder(
                    valueListenable: text,
                    builder: (_, value, _) => Text(
                      '${value.text.length} / 1,000',
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
