import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'image_cache.dart';
import 'media_permissions.dart';
import 'screens.dart';
import 'upload_progress.dart';

class ScheduleAppearanceAdminContent extends StatefulWidget {
  const ScheduleAppearanceAdminContent({super.key, required this.page});

  final NativePageState page;

  @override
  State<ScheduleAppearanceAdminContent> createState() =>
      _ScheduleAppearanceAdminContentState();
}

class _ScheduleAppearanceAdminContentState
    extends State<ScheduleAppearanceAdminContent> {
  late String _mode;
  late String _savedImageUrl;
  Uint8List? _image;
  String _filename = 'day-off.jpg';
  bool _removeImage = false, _picking = false, _saving = false;
  bool _uploading = false;
  double? _uploadProgress;
  String? _error, _status;

  String tr(String en, String ar) => widget.page.c.t(en, ar);

  @override
  void initState() {
    super.initState();
    _readAppearance();
  }

  void _readAppearance() {
    final appearance = object(widget.page.data['appearance']);
    _mode = appearance['mode'] == 'image' ? 'image' : 'text';
    _savedImageUrl = value(appearance['image_url']);
  }

  bool get _hasImage =>
      _image != null || (!_removeImage && _savedImageUrl.isNotEmpty);

  Future<void> _chooseImage() async {
    if (_picking || _saving) return;
    setState(() {
      _picking = true;
      _error = null;
      _status = null;
    });
    try {
      final picked = await pickUploadImage(tr: tr);
      if (picked == null || !mounted) return;
      if (await picked.length() > 2 * 1024 * 1024) {
        throw ApiFailure(
          tr(
            'Choose an image up to 2 MB.',
            'اختار صورة حجمها ٢ ميجابايت أو أقل.',
          ),
        );
      }
      final bytes = await picked.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 8192 ||
            descriptor.height > 8192 ||
            descriptor.width * descriptor.height > 16000000) {
          throw ApiFailure(
            tr(
              'Choose a smaller image, up to 16 megapixels.',
              'اختار صورة أصغر لا تتجاوز ١٦ ميجابكسل.',
            ),
          );
        }
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _filename = picked.name;
        _removeImage = false;
        _mode = 'image';
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Could not read this image. Choose another image.',
            'تعذر فتح الصورة. اختار صورة تانية.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _picking || widget.page.c.user?['role'] != 'super_admin') {
      return;
    }
    if (_mode == 'image' && !_hasImage) {
      setState(
        () => _error = tr(
          'Choose an image first, or select Text only.',
          'اختار صورة الأول، أو اختار نص فقط.',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
      _uploading = _image != null && _mode == 'image';
      _uploadProgress = _uploading ? 0 : null;
    });
    try {
      final payload = <String, dynamic>{
        'mode': _mode,
        if (_removeImage) 'remove_image': 1,
        if (_image != null && _mode == 'image')
          'image': MultipartFile.fromBytes(_image!, filename: _filename),
      };
      if (_uploading) {
        await widget.page.c.actionWithProgress(
          'PUT',
          '/admin/schedule-appearance',
          payload,
          onSendProgress: _updateUploadProgress,
        );
      } else {
        await widget.page.c.action(
          'PUT',
          '/admin/schedule-appearance',
          payload,
        );
      }
      if (!mounted) return;
      await widget.page.load();
      if (!mounted) return;
      setState(() {
        _readAppearance();
        _image = null;
        _removeImage = false;
        _status = tr('Changes saved.', 'تم حفظ التغييرات.');
      });
    } on ApiFailure catch (error) {
      if (mounted) {
        setState(
          () => _error = error.fields.isEmpty
              ? error.message
              : error.fields.values
                    .map((field) => field is List ? field.join('\n') : '$field')
                    .join('\n'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Could not save changes. Please try again.',
            'تعذر حفظ التغييرات. حاول مرة تانية.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploading = false;
        });
      }
    }
  }

  void _updateUploadProgress(int sent, int total) {
    if (!mounted || !_uploading) return;
    final next = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
    if (next == null && _uploadProgress == null ||
        next != null &&
            _uploadProgress != null &&
            uploadProgressPercent(next) ==
                uploadProgressPercent(_uploadProgress)) {
      return;
    }
    setState(() => _uploadProgress = next);
  }

  Widget _preview() {
    if (_mode == 'text') {
      return Padding(
        key: const ValueKey('schedule.appearance.preview'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Text(
          tr("Today's a day off, buddy!", 'النهارده إجازة يا صاحبي'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (!_hasImage) {
      return Padding(
        key: const ValueKey('schedule.appearance.preview'),
        padding: const EdgeInsets.all(24),
        child: Text(tr('No image selected.', 'لم يتم اختيار صورة.')),
      );
    }
    final label = tr('Day off image preview', 'معاينة صورة يوم الإجازة');
    Widget failed(BuildContext _, Object _, StackTrace? _) => Center(
      child: Text(tr('Could not load the image.', 'تعذر تحميل الصورة.')),
    );
    return SizedBox(
      key: const ValueKey('schedule.appearance.preview'),
      width: 220,
      height: 160,
      child: _image != null
          ? Image.memory(
              _image!,
              fit: BoxFit.contain,
              cacheWidth: 640,
              semanticLabel: label,
              errorBuilder: failed,
            )
          : networkImage(
              widget.page.c.api.media(_savedImageUrl),
              width: 220,
              height: 160,
              fit: BoxFit.contain,
              semanticLabel: label,
              errorBuilder: failed,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.page.c.user?['role'] != 'super_admin') {
      return Center(
        child: Text(
          tr(
            'Only the super admin can change the day off appearance.',
            'السوبر أدمن فقط يقدر يغيّر شكل يوم الإجازة.',
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final busy = _saving || _picking;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 120),
      children: [
        Text(
          tr('Day off appearance', 'شكل يوم الإجازة'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Choose what students see on a day with no classes.',
            'اختار اللي يظهر للطلاب في اليوم اللي مفيهوش محاضرات أو سكاشن.',
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SegmentedButton<String>(
            key: const ValueKey('schedule.appearance.mode'),
            segments: [
              ButtonSegment(
                value: 'text',
                label: Text(tr('Text only', 'نص فقط')),
                icon: const Icon(Icons.text_fields),
              ),
              ButtonSegment(
                value: 'image',
                label: Text(tr('Image', 'صورة')),
                icon: const Icon(Icons.image_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: busy
                ? null
                : (selected) => setState(() {
                    _mode = selected.single;
                    _error = null;
                    _status = null;
                  }),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: _preview()),
          ),
        ),
        if (_mode == 'image') ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('schedule.appearance.choose-image'),
            onPressed: busy ? null : _chooseImage,
            icon: _picking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _hasImage
                  ? tr('Replace image', 'تغيير الصورة')
                  : tr('Choose image', 'اختيار صورة'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Choose a JPG, PNG or WebP image up to 2 MB.',
              'اختار صورة JPG أو PNG أو WebP حجمها ٢ ميجابايت أو أقل.',
            ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          if (_hasImage)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('schedule.appearance.remove-image'),
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _image = null;
                        _removeImage = true;
                        _mode = 'text';
                        _error = null;
                        _status = null;
                      }),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Remove image', 'حذف الصورة')),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_status!)),
        ],
        if (_uploading)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: UploadProgressIndicator(
              key: const ValueKey('schedule.image.upload.progress'),
              value: _uploadProgress,
              label: tr('Uploading image…', 'جاري رفع الصورة…'),
              finishingLabel: tr('Saving image…', 'جاري حفظ الصورة…'),
            ),
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const ValueKey('schedule.appearance.save'),
          onPressed: busy ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            _saving
                ? tr('Saving…', 'جاري الحفظ…')
                : tr('Save changes', 'حفظ التغييرات'),
          ),
        ),
      ],
    );
  }
}
