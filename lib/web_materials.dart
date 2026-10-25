import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'api.dart';
import 'image_cache.dart';
import 'main.dart' show AppController;
import 'screens.dart';
import 'web_home.dart' show webAgo, webBorder, webMuted, webSecondary;
import 'web_settings.dart' show WebSwitch;
import 'web_style.dart';

/// The file types community admins may upload, matching the server's list.
const materialExtensions = [
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'txt',
  'doc',
  'docx',
  'xls',
  'xlsx',
];

const _materialMimeTypes = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
];

const _materialUtis = [
  'com.adobe.pdf',
  'public.jpeg',
  'public.png',
  'org.webmproject.webp',
  'public.plain-text',
  'com.microsoft.word.doc',
  'org.openxmlformats.wordprocessingml.document',
  'com.microsoft.excel.xls',
  'org.openxmlformats.spreadsheetml.sheet',
];

String _fileSize(Object? bytes) {
  final size = int.tryParse('$bytes') ?? 0;
  if (size >= 1024 * 1024) {
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
  return '$size B';
}

/// Keeps downloaded materials in the app's private cache, so a file opened
/// once opens instantly next time and works offline. Files never change once
/// uploaded, so the material id and size identify a cached copy. The oldest
/// files are removed once the cache passes [_limitBytes].
class MaterialFiles {
  MaterialFiles._();
  static const _limitBytes = 400 * 1024 * 1024;
  // Signed R2 links carry their own authorization, so no app cookies are sent.
  static final Dio _storage = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );
  static final Map<int, Future<File>> _downloads = {};

  static Future<Directory> _directory() async {
    final base = await getApplicationCacheDirectory();
    final directory = Directory('${base.path}/materials');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<File?> cached(Json material) async {
    final id = int.tryParse('${material['id']}');
    if (id == null) return null;
    final file = File(
      '${(await _directory()).path}/$id.${value(material['extension'], 'bin')}',
    );
    final size = int.tryParse('${material['size']}');
    if (await file.exists() && (size == null || await file.length() == size)) {
      return file;
    }
    return null;
  }

  /// The material's file on this device, downloading it once. Concurrent
  /// calls for the same file share one download.
  static Future<File> fetch(
    AppController c,
    Json material, {
    void Function(double progress)? onProgress,
  }) {
    final id = int.parse('${material['id']}');
    return _downloads[id] ??= () async {
      try {
        final existing = await cached(material);
        if (existing != null) return existing;
        final link = await c.api.get('/community/materials/$id/file');
        final url = value(link['signed_url']);
        final uri = Uri.tryParse(url);
        if (uri == null || uri.scheme != 'https') {
          throw const ApiFailure('The file could not be opened.');
        }
        final directory = await _directory();
        final extension = value(material['extension'], 'bin');
        final partial = File('${directory.path}/$id.$extension.part');
        // Streams straight to disk, so large files never sit in memory.
        await _storage.download(
          url,
          partial.path,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );
        final file = await partial.rename('${directory.path}/$id.$extension');
        unawaited(_trim(directory, keep: file.path));
        return file;
      } finally {
        unawaited(Future(() => _downloads.remove(id)));
      }
    }();
  }

  static Future<void> _trim(Directory directory, {required String keep}) async {
    try {
      final files = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final stats = {for (final f in files) f: await f.stat()};
      var total = stats.values.fold<int>(0, (sum, s) => sum + s.size);
      final oldest = files.toList()
        ..sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final file in oldest) {
        if (total <= _limitBytes) break;
        if (file.path == keep) continue;
        total -= stats[file]!.size;
        await file.delete();
      }
    } catch (_) {
      /* A full or locked cache only costs a later re-download. */
    }
  }

  /// Removes every cached material, for example after signing out.
  static Future<void> clear() async {
    try {
      final directory = await _directory();
      await directory.delete(recursive: true);
    } catch (_) {}
  }

  /// Lets the member save the file anywhere on their device (Files on iOS,
  /// the system picker on Android). No storage permission is needed.
  static Future<void> save(
    BuildContext context,
    AppController c,
    Json material,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await fetch(c, material);
      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: file.path,
          fileName: value(
            material['original_name'],
            '${value(material['title'], 'material')}.${value(material['extension'])}',
          ),
        ),
      );
      if (saved != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(c.t('File saved.', 'الملف اتحفظ.'))),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _MaterialIcon extends StatelessWidget {
  const _MaterialIcon({required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      'pdf' => const Color(0xffdc2626),
      'document' => const Color(0xff2563eb),
      'spreadsheet' => const Color(0xff16a34a),
      _ => const Color(0xff2e855d),
    };
    final label = switch (kind) {
      'pdf' => 'PDF',
      'document' => 'W',
      'spreadsheet' => 'X',
      'text' => 'TXT',
      _ => '',
    };
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: label.isEmpty
          ? WebIcon('file', size: 22, color: color)
          : Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: label.length > 1 ? 12 : 17,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

Widget _pill(
  BuildContext context,
  String label,
  VoidCallback? onTap, {
  String? icon,
  bool primary = false,
  bool selected = false,
}) {
  final foreground = primary
      ? Colors.white
      : Theme.of(context).colorScheme.onSurface;
  return Material(
    color: primary ? const Color(0xff2e855d) : webSecondary(context),
    shape: StadiumBorder(
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.onSurface
            : primary
            ? Colors.transparent
            : webBorder(context),
      ),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              WebIcon(icon, size: 17, color: foreground),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Home › Edit subjects: choose which communities appear on Home and send
/// notifications, from either level.
class WebSubjects extends StatefulWidget {
  const WebSubjects({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebSubjects> createState() => _WebSubjectsState();
}

class _WebSubjectsState extends State<WebSubjects> {
  NativePageState get p => widget.page;
  late Set<String> enabled = {
    for (final id in (p.data['enabled_ids'] as List? ?? const [])) '$id',
  };
  late String filter = p.data['user_level'] == null
      ? 'all'
      : '${p.data['user_level']}';
  bool saving = false, dirty = false;
  String status = '';

  Future<void> save() async {
    setState(() {
      saving = true;
      status = '';
    });
    try {
      final response = await p.c.action('PUT', '/community/subjects', {
        'community_ids': enabled.map(int.parse).toList(),
      });
      if (!mounted) return;
      setState(() {
        dirty = false;
        status = value(response['message'], p.c.t('Saved.', 'اتحفظ.'));
      });
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void setVisible(List<Json> visible, bool on) => setState(() {
    for (final community in visible) {
      on
          ? enabled.add('${community['id']}')
          : enabled.remove('${community['id']}');
    }
    dirty = true;
    status = '';
  });

  @override
  Widget build(BuildContext context) {
    final c = p.c;
    final level = p.data['user_level'];
    final all = rows(p.data['communities']);
    final communities = all
        .where(
          (community) =>
              filter == 'all' ||
              community['level'] == null ||
              '${community['level']}' == filter,
        )
        .toList();
    final accent = const Color(0xff2e855d);
    String levelName(Object? value) => value == null
        ? c.t('Both levels', 'الفرقتين')
        : c.t('Level $value', 'الفرقة $value');
    final bottom = MediaQuery.paddingOf(context).bottom + 86;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(10, 12, 10, bottom + 90),
          children: [
            Text(
              c.t(
                'Choose the subjects shown on Home. You get notifications from every subject you turn on, from any level, and none from the ones you turn off.',
                'اختار المواد اللي تظهرلك في الرئيسية. هيوصلك إشعارات من كل مادة مفعّلة من أي فرقة، ومش هيوصلك حاجة من اللي قفلتها.',
              ),
              style: TextStyle(
                color: webMuted(context),
                fontSize: 14.5,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    context,
                    c.t('All', 'الكل'),
                    filter == 'all',
                    () => setState(() => filter = 'all'),
                  ),
                  for (final option in const [1, 2])
                    _chip(
                      context,
                      levelName(option),
                      filter == '$option',
                      () => setState(() => filter = '$option'),
                      note: level == option ? c.t('Mine', 'فرقتي') : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.t(
                      '${enabled.length} of ${all.length} subjects on Home',
                      '${enabled.length} من ${all.length} مادة ظاهرين في الرئيسية',
                    ),
                    style: TextStyle(color: webMuted(context), fontSize: 13),
                  ),
                ),
                if (communities.isNotEmpty) ...[
                  TextButton(
                    onPressed: () => setVisible(communities, true),
                    style: TextButton.styleFrom(foregroundColor: accent),
                    child: Text(c.t('All on', 'فعّل الكل')),
                  ),
                  TextButton(
                    onPressed: () => setVisible(communities, false),
                    style: TextButton.styleFrom(foregroundColor: accent),
                    child: Text(c.t('All off', 'اقفل الكل')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (communities.isEmpty)
              _emptyState(
                context,
                'book',
                c.t('No subjects yet.', 'مفيش مواد لسه.'),
                '',
              ),
            for (final community in communities)
              Builder(
                builder: (context) {
                  final id = '${community['id']}';
                  final on = enabled.contains(id);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: on
                          ? accent.withValues(alpha: .08)
                          : webSecondary(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: on ? accent : webBorder(context),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() {
                        dirty = true;
                        status = '';
                        on ? enabled.remove(id) : enabled.add(id);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox.square(
                                dimension: 52,
                                child: networkImage(
                                  c.api.media(value(community['image_url'])),
                                  fit: BoxFit.cover,
                                  cacheWidth:
                                      (52 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .ceil(),
                                  errorBuilder: (_, _, _) =>
                                      ColoredBox(color: webBorder(context)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    value(community['name']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: webBorder(context),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      levelName(community['level']),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: webMuted(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            WebSwitch(
                              value: on,
                              label: value(community['name']),
                              onChanged: (value) => setState(() {
                                dirty = true;
                                status = '';
                                value ? enabled.add(id) : enabled.remove(id);
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        // The save bar slides in once something changed, and confirms the save.
        PositionedDirectional(
          start: 10,
          end: 10,
          bottom: bottom,
          child: AnimatedSlide(
            offset: dirty || saving || status.isNotEmpty
                ? Offset.zero
                : const Offset(0, 1.6),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Material(
              elevation: 8,
              shadowColor: Colors.black26,
              color: Theme.of(context).colorScheme.surface,
              shape: StadiumBorder(side: BorderSide(color: webBorder(context))),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dirty
                            ? c.t(
                                'You have unsaved changes',
                                'فيه تغييرات لسه ماتحفظتش',
                              )
                            : status,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: saving || !dirty ? null : save,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        minimumSize: const Size(96, 42),
                        shape: const StadiumBorder(),
                      ),
                      child: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(c.t('Save', 'احفظ')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _chip(
  BuildContext context,
  String label,
  bool selected,
  VoidCallback onTap, {
  String? note,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: Material(
      color: selected ? onSurface : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? onSurface : webBorder(context)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Theme.of(context).colorScheme.surface
                      : webMuted(context),
                ),
              ),
              if (note != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff2e855d),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    note,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _emptyState(
  BuildContext context,
  String icon,
  String title,
  String body, {
  Widget? action,
}) => Container(
  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
  decoration: BoxDecoration(
    color: webSecondary(context),
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: webBorder(context)),
  ),
  child: Column(
    children: [
      Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xff2e855d).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: WebIcon(icon, size: 28, color: const Color(0xff2e855d)),
      ),
      const SizedBox(height: 14),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      if (body.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: webMuted(context), height: 1.5),
        ),
      ],
      if (action != null) ...[const SizedBox(height: 16), action],
    ],
  ),
);

/// A community's study materials. Admins of the community can upload and
/// delete files; everyone can open and download them.
class WebMaterials extends StatefulWidget {
  const WebMaterials({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebMaterials> createState() => _WebMaterialsState();
}

class _WebMaterialsState extends State<WebMaterials> {
  NativePageState get p => widget.page;
  bool uploading = false;

  int get maxBytes =>
      int.tryParse('${p.data['max_bytes']}') ?? 30 * 1024 * 1024;

  Future<void> upload() async {
    final c = p.c, messenger = ScaffoldMessenger.of(context);
    final community = object(p.data['community']);
    final String? path;
    try {
      path = await FlutterFileDialog.pickFile(
        params: const OpenFileDialogParams(
          fileExtensionsFilter: materialExtensions,
          mimeTypesFilter: _materialMimeTypes,
          allowedUtiTypes: _materialUtis,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (path == null || !mounted) return;
    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!materialExtensions.contains(extension)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            c.t(
              'This type of file is not allowed. Use PDF, JPG, PNG, WEBP, TXT, DOC, DOCX, XLS or XLSX.',
              'نوع الملف ده مش مسموح. استخدم PDF أو JPG أو PNG أو WEBP أو TXT أو DOC أو DOCX أو XLS أو XLSX.',
            ),
          ),
        ),
      );
      return;
    }
    final size = await file.length();
    if (size == 0 || size > maxBytes) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            c.t('This file is larger than 30 MB.', 'الملف ده أكبر من 30 ميجا.'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final title = await _askTitle(context, c, name);
    if (title == null || !mounted) return;
    setState(() => uploading = true);
    try {
      await c.action('POST', '/community/${community['id']}/materials', {
        'title': title,
        'file': await MultipartFile.fromFile(path, filename: name),
      });
      messenger.showSnackBar(
        SnackBar(content: Text(c.t('Material uploaded.', 'الملف اترفع.'))),
      );
      if (mounted) await p.load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> delete(Json material) async {
    final c = p.c;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        content: Text(
          c.t('Delete this file for everyone?', 'تمسح الملف ده عند الكل؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.t('Cancel', 'إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(c.t('Delete', 'امسح')),
          ),
        ],
      ),
    );
    if (sure == true) {
      await p.run('DELETE', '/community/materials/${material['id']}');
    }
  }

  final search = TextEditingController();
  String kind = 'all';

  @override
  void initState() {
    super.initState();
    // Community page › Manage › Upload material goes straight to the picker.
    if (Uri.parse(p.path).queryParameters['upload'] == '1' &&
        yes(p.data['can_manage'])) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && yes(p.data['storage_ready'])) upload();
      });
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c;
    final page = object(p.data['materials']);
    final materials = rows(page['data']);
    final canManage = yes(p.data['can_manage']);
    final ready = yes(p.data['storage_ready']);
    final kinds = {for (final m in materials) value(m['kind'])};
    final term = search.text.trim().toLowerCase();
    final shown = materials
        .where(
          (m) =>
              (kind == 'all' || value(m['kind']) == kind) &&
              (term.isEmpty ||
                  '${value(m['title'])} ${value(m['original_name'])}'
                      .toLowerCase()
                      .contains(term)),
        )
        .toList();
    String kindName(String kind) => switch (kind) {
      'pdf' => 'PDF',
      'document' => 'Word',
      'spreadsheet' => 'Excel',
      'image' => c.t('Images', 'صور'),
      'text' => c.t('Text', 'نص'),
      _ => kind,
    };
    final uploadButton = _pill(
      context,
      uploading ? c.t('Uploading…', 'جاري الرفع…') : c.t('Upload', 'ارفع ملف'),
      uploading || !ready ? null : upload,
      icon: 'plus',
      primary: true,
    );
    return RefreshIndicator.adaptive(
      onRefresh: p.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 110),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            c.t(
              'Lecture notes, sheets and files shared by the community admins.',
              'ملخصات وشيتات وملفات بيرفعها مسؤولين المجتمع.',
            ),
            style: TextStyle(
              color: webMuted(context),
              fontSize: 14.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          if (materials.isNotEmpty || canManage)
            Row(
              children: [
                if (materials.isNotEmpty)
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: TextField(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: c.t('Search files', 'دوّر في الملفات'),
                          isDense: true,
                          filled: true,
                          fillColor: webSecondary(context),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: WebIcon(
                              'search',
                              size: 17,
                              color: webMuted(context),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(99),
                            borderSide: BorderSide(color: webBorder(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(99),
                            borderSide: BorderSide(color: webBorder(context)),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (canManage && materials.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  uploadButton,
                ],
              ],
            ),
          if (canManage && uploading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (canManage && !ready)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                c.t(
                  'File storage is not set up yet. Please try again later.',
                  'تخزين الملفات لسه مش جاهز. جرب تاني بعدين.',
                ),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (kinds.length > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    context,
                    c.t('All', 'الكل'),
                    kind == 'all',
                    () => setState(() => kind = 'all'),
                  ),
                  for (final option in const [
                    'pdf',
                    'document',
                    'spreadsheet',
                    'image',
                    'text',
                  ])
                    if (kinds.contains(option))
                      _chip(
                        context,
                        kindName(option),
                        kind == option,
                        () => setState(() => kind = option),
                      ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (materials.isEmpty)
            _emptyState(
              context,
              'book',
              c.t('No materials yet.', 'مفيش ملفات لسه.'),
              canManage
                  ? c.t(
                      'Upload the first file for this community.',
                      'ارفع أول ملف للمجتمع ده.',
                    )
                  : c.t(
                      'Files shared by the community admins will appear here.',
                      'الملفات اللي بيشاركها مسؤولين المجتمع هتظهر هنا.',
                    ),
              action: canManage ? uploadButton : null,
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                c.t('No files match your search.', 'مفيش ملفات مطابقة للبحث.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: webMuted(context)),
              ),
            ),
          for (final material in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: webSecondary(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: webBorder(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => c.open(
                    '/community/materials/${material['id']}',
                    seed: {
                      'screen': 'community.material',
                      'data': {
                        'material': material,
                        'community': object(p.data['community']),
                        'can_manage': canManage,
                      },
                    },
                  ),
                  onLongPress: canManage ? () => delete(material) : null,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      12,
                      4,
                      12,
                    ),
                    child: Row(
                      children: [
                        _MaterialIcon(kind: value(material['kind'])),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                value(material['title']),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${value(material['extension']).toUpperCase()} · ${_fileSize(material['size'])} · ${webAgo(material['created_at'], c.settings.language == 'ar')}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: webMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: c.t('Download', 'تحميل'),
                          onPressed: () =>
                              MaterialFiles.save(context, c, material),
                          icon: WebIcon(
                            'download',
                            size: 20,
                            color: webMuted(context),
                          ),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            tooltip: c.t('More', 'المزيد'),
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: webMuted(context),
                            ),
                            onSelected: (_) => delete(material),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  c.t('Delete', 'امسح'),
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (value(page['next_page_url']).isNotEmpty)
            Center(
              child: TextButton(
                onPressed: () => p.load(value(page['next_page_url'])),
                child: Text(c.t('More', 'المزيد')),
              ),
            ),
        ],
      ),
    );
  }
}

Future<String?> _askTitle(
  BuildContext context,
  AppController c,
  String fileName,
) {
  final controller = TextEditingController(
    text: fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName,
  );
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(c.t('Upload a file', 'رفع ملف')),
      content: Material(
        color: Colors.transparent,
        child: TextField(
          controller: controller,
          maxLength: 150,
          autofocus: true,
          decoration: InputDecoration(labelText: c.t('Title', 'العنوان')),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.t('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(c.t('Upload', 'ارفع')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Opens one material inside the app: PDFs and images from a cached copy of
/// the file, text, Word and Excel files from the server's safe preview.
class WebMaterialViewer extends StatefulWidget {
  const WebMaterialViewer({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebMaterialViewer> createState() => _WebMaterialViewerState();
}

class _WebMaterialViewerState extends State<WebMaterialViewer> {
  NativePageState get p => widget.page;
  Json get material => object(p.data['material']);
  String get kind => value(material['kind']);
  File? file;
  Object? failure;
  double progress = 0;
  PdfControllerPinch? pdf;
  int sheet = 0;

  @override
  void initState() {
    super.initState();
    if (kind == 'pdf' || kind == 'image') _open();
  }

  Future<void> _open() async {
    setState(() {
      failure = null;
      progress = 0;
    });
    try {
      final opened = await MaterialFiles.fetch(
        p.c,
        material,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        file = opened;
        if (kind == 'pdf') {
          pdf?.dispose();
          pdf = PdfControllerPinch(document: PdfDocument.openFile(opened.path));
        }
      });
    } catch (e) {
      if (mounted) setState(() => failure = e);
    }
  }

  @override
  void dispose() {
    pdf?.dispose();
    super.dispose();
  }

  Widget _loading(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          child: LinearProgressIndicator(value: progress > 0 ? progress : null),
        ),
        const SizedBox(height: 12),
        Text(
          '${_fileSize(material['size'])}${progress > 0 ? ' · ${(progress * 100).round()}%' : ''}',
          style: TextStyle(color: webMuted(context)),
        ),
      ],
    ),
  );

  Widget _failed(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$failure', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _open,
            child: Text(p.c.t('Try again', 'جرّب تاني')),
          ),
        ],
      ),
    ),
  );

  Widget _viewer(BuildContext context) {
    final c = p.c, preview = object(p.data['preview']);
    if (kind == 'pdf' || kind == 'image') {
      if (failure != null) return _failed(context);
      if (file == null) return _loading(context);
      if (kind == 'pdf') {
        return PdfViewPinch(
          controller: pdf!,
          backgroundDecoration: BoxDecoration(color: webSecondary(context)),
          onDocumentError: (error) {
            if (mounted) setState(() => failure = error);
          },
        );
      }
      final width =
          MediaQuery.sizeOf(context).width *
          MediaQuery.devicePixelRatioOf(context);
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            file!,
            cacheWidth: (width * 2).round(),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Text(c.t('The file could not be opened.', 'الملف ماتفتحش.')),
          ),
        ),
      );
    }
    // A row tapped in the list opens at once; its preview arrives with the
    // full page a moment later.
    if (p.provisional) return const Center(child: CircularProgressIndicator());
    final padding = const EdgeInsets.fromLTRB(16, 16, 16, 120);
    switch (value(preview['type'])) {
      case 'text':
        return SingleChildScrollView(
          padding: padding,
          child: SelectableText(
            value(preview['text']),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.6,
            ),
          ),
        );
      case 'document':
        final blocks = rows(preview['blocks']);
        return ListView.builder(
          padding: padding,
          itemCount: blocks.length,
          itemBuilder: (context, index) {
            final block = blocks[index];
            return switch (value(block['type'])) {
              'heading' => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: SelectableText(
                  value(block['text']),
                  style: TextStyle(
                    fontSize: switch (block['level']) {
                      1 => 21.0,
                      2 => 18.0,
                      _ => 16.0,
                    },
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              'table' => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _table(context, (block['rows'] as List? ?? const [])),
              ),
              _ => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectableText(
                  value(block['text']),
                  style: const TextStyle(fontSize: 15, height: 1.7),
                ),
              ),
            };
          },
        );
      case 'spreadsheet':
        final sheets = rows(preview['sheets']);
        if (sheets.isEmpty) break;
        final current = sheets[sheet.clamp(0, sheets.length - 1)];
        final shown = (current['rows'] as List? ?? const []);
        return ListView(
          padding: padding,
          children: [
            if (sheets.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (index, item) in sheets.indexed)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _pill(
                          context,
                          value(item['name']),
                          () => setState(() => sheet = index),
                          selected: index == sheet,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _table(context, shown, numbered: true),
            if (yes(current['truncated']))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  c.t(
                    'Only the first ${shown.length} rows are shown.',
                    'ظاهر أول ${shown.length} صف بس.',
                  ),
                  style: TextStyle(color: webMuted(context), fontSize: 12.5),
                ),
              ),
          ],
        );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MaterialIcon(kind: kind),
            const SizedBox(height: 14),
            Text(
              c.t(
                'A preview isn’t available for this file. Download it to open it.',
                'مفيش معاينة للملف ده. حمّله عشان تفتحه.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: webMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(
    BuildContext context,
    List<dynamic> tableRows, {
    bool numbered = false,
  }) {
    final columns = tableRows.fold<int>(
      0,
      (most, row) => row is List && row.length > most ? row.length : most,
    );
    if (columns == 0) return const SizedBox.shrink();
    final border = BorderSide(color: webBorder(context));
    Widget cell(String text, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: header ? webMuted(context) : null,
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          top: border,
          bottom: border,
          left: border,
          right: border,
          horizontalInside: border,
          verticalInside: border,
        ),
        children: [
          for (final (index, row) in tableRows.indexed)
            TableRow(
              children: [
                if (numbered) cell('${index + 1}', header: true),
                for (var column = 0; column < columns; column++)
                  cell(
                    row is List && column < row.length
                        ? '${row[column] ?? ''}'
                        : '',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c;
    final community = object(p.data['community']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _MaterialIcon(kind: kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value(material['title']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        value(community['name']),
                        value(material['extension']).toUpperCase(),
                        _fileSize(material['size']),
                      ].where((v) => v.isNotEmpty).join(' · '),
                      style: TextStyle(
                        color: webMuted(context),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              _pill(
                context,
                c.t('Download', 'تحميل'),
                () => MaterialFiles.save(context, c, material),
                icon: 'download',
              ),
            ],
          ),
        ),
        Divider(height: 1, color: webBorder(context)),
        Expanded(child: _viewer(context)),
      ],
    );
  }
}
