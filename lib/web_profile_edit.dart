import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'api.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';

/// Native form with the same mobile layout and controls as profile-edit.css.
class WebProfileEdit extends StatefulWidget {
  const WebProfileEdit({
    super.key,
    required this.page,
    this.initialPanel = 'details',
  });
  final NativePageState page;
  final String initialPanel;

  @override
  State<WebProfileEdit> createState() => _WebProfileEditState();
}

class _WebProfileEditState extends State<WebProfileEdit> {
  late Json person;
  late List<Json> skills;
  late String panel, avatar, banner;
  String? major, city, job;
  int? day, month, year;
  bool imageBanner = false, saving = false, skillBusy = false;
  String? error, success;
  Json fieldErrors = {};
  Uint8List? avatarBytes, bannerBytes, bannerOriginal;
  String avatarFilename = 'avatar.png';
  late final TextEditingController graduation, hex;
  final skill = TextEditingController();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  NativePageState get page => widget.page;
  String tr(String en, String ar) => page.c.t(en, ar);

  @override
  void initState() {
    super.initState();
    person = object(page.data['user']);
    skills = rows(page.data['skills']);
    panel = widget.initialPanel;
    avatar = value(person['avatar'], 'jko.webp');
    banner = value(person['banner_image']);
    imageBanner = banner.isNotEmpty;
    major = _selected(person['major']);
    city = _selected(person['city']);
    job = _selected(person['job']);
    final birth = DateTime.tryParse(value(person['birthdate']));
    day = birth?.day;
    month = birth?.month;
    year = birth?.year;
    graduation = TextEditingController(text: value(person['graduation_year']));
    hex = TextEditingController(
      text: value(person['banner_color'], '#2e855d').toUpperCase(),
    );
  }

  @override
  void dispose() {
    graduation.dispose();
    hex.dispose();
    skill.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  String? _selected(dynamic input) => value(input).isEmpty ? null : '$input';
  Color get bannerColor => _parseColor(hex.text) ?? const Color(0xff2e855d);
  bool get canUpload => yes(page.c.user?['can_upload_media']);
  String? errorFor(String key) {
    final errors = fieldErrors[key];
    return errors is List
        ? errors.map((v) => '$v').join('\n')
        : errors?.toString();
  }

  Future<void> save() async {
    if (saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
      success = null;
      fieldErrors = {};
    });
    try {
      if (!imageBanner && _parseColor(hex.text) == null) {
        throw ApiFailure(tr('Enter a valid color code.', 'اكتب كود لون صحيح.'));
      }
      final data = <String, dynamic>{
        'major': major,
        'city': city,
        'job': job,
        'birthdate': day != null && month != null && year != null
            ? '${year!}-${month!.toString().padLeft(2, '0')}-${day!.toString().padLeft(2, '0')}'
            : null,
        'graduation_year': graduation.text.trim().isEmpty
            ? null
            : graduation.text.trim(),
        'avatar': avatar,
        'banner_image': imageBanner ? banner : '',
        'banner_color': hex.text.trim(),
      };
      if (avatarBytes != null) {
        data['avatar_upload'] = MultipartFile.fromBytes(
          avatarBytes!,
          filename: avatarFilename,
        );
      }
      if (imageBanner && bannerBytes != null) {
        data['banner_upload'] = MultipartFile.fromBytes(
          bannerBytes!,
          filename: 'banner.png',
        );
      }
      final result = await page.c.action('PUT', '/profile', data);
      if (!mounted) return;
      page.c.leaveTo(value(result['redirect_url'], '/profile'), page);
    } on ApiFailure catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message;
          fieldErrors = exception.fields;
          if ([
            'major',
            'city',
            'birthdate',
            'job',
            'graduation_year',
          ].any(fieldErrors.containsKey)) {
            panel = 'details';
          } else if (fieldErrors.containsKey('avatar_upload')) {
            panel = 'avatar';
          } else if (fieldErrors.containsKey('banner_upload')) {
            panel = 'banner';
          }
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> updateSkill({Json? remove}) async {
    if (skillBusy || remove == null && skill.text.trim().isEmpty) return;
    setState(() {
      skillBusy = true;
      error = null;
    });
    try {
      await page.c.action(
        remove == null ? 'POST' : 'DELETE',
        remove == null ? '/profile/skills' : '/profile/skills/${remove['id']}',
        remove == null ? {'skill_name': skill.text.trim()} : {},
      );
      final updated = await page.c.get('/profile/edit');
      if (!mounted) return;
      setState(() {
        skills = rows(object(updated['data'])['skills']);
        page.data['skills'] = skills;
        if (remove == null) skill.clear();
      });
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => skillBusy = false);
    }
  }

  Future<void> password() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
      fieldErrors = {};
    });
    try {
      await page.c.action('POST', '/profile/password', {
        'current_password': currentPassword.text,
        'password': newPassword.text,
        'password_confirmation': confirmPassword.text,
      });
      if (!mounted) return;
      page.c.leaveTo('/profile', page);
    } on ApiFailure catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.message;
          fieldErrors = exception.fields;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickPhoto(bool forBanner) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final data = await picked.readAsBytes();
      if (data.length > 5 * 1024 * 1024) {
        throw ApiFailure(
          tr(
            'Choose an image up to 5 MB.',
            'اختار صورة حجمها بحد أقصى ٥ ميجابايت.',
          ),
        );
      }
      final extension = picked.name.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
        throw ApiFailure(
          tr(
            'Choose a JPEG, PNG or WebP image.',
            'اختار صورة بصيغة JPEG أو PNG أو WebP.',
          ),
        );
      }
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final valid =
          image.width <= 8192 &&
          image.height <= 8192 &&
          image.width * image.height <= 16000000;
      image.dispose();
      codec.dispose();
      if (!valid) {
        throw ApiFailure(
          tr(
            'Choose an image up to 16 megapixels, with each side no larger than 8,192 pixels.',
            'اختار صورة بحد أقصى ١٦ ميجابكسل، وكل ضلع ما يزيدش عن ٨٬١٩٢ بكسل.',
          ),
        );
      }
      if (!mounted) return;
      if (forBanner) {
        await cropBanner(data);
      } else {
        setState(() {
          avatarBytes = data;
          avatarFilename = picked.name;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = '$exception');
    }
  }

  Future<void> cropBanner(Uint8List source) async {
    final cropped = await showDialog<Uint8List>(
      context: context,
      builder: (_) => _BannerCrop(page: page, bytes: source),
    );
    if (!mounted || cropped == null) return;
    setState(() {
      bannerBytes = cropped;
      bannerOriginal = source;
      imageBanner = true;
      error = null;
    });
  }

  String bannerUrl(String source) {
    if (source == person['banner_image'] &&
        value(person['banner_url']).isNotEmpty) {
      return value(person['banner_url']);
    }
    final name = Uri.tryParse(source)?.pathSegments.lastOrNull ?? '';
    if (name.startsWith('photo-')) {
      return '/Picture/banner-${name.substring(6)}.jpg';
    }
    return source;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EditColors(context);
    final mobile = MediaQuery.sizeOf(context).width < 768;
    final hideSave = panel == 'skills' || panel == 'security';
    final tabs = [
      ('details', tr('About you', 'معلومات عنك')),
      ('avatar', tr('Profile photo', 'صورة الملف الشخصي')),
      ('banner', tr('Banner', 'الغلاف')),
      ('skills', tr('Skills', 'المهارات')),
      if (!mobile || widget.initialPanel == 'security')
        (
          'security',
          tr('Security (Change Password)', 'الأمان (تغيير كلمة السر)'),
        ),
    ];
    final actions = Row(
      children: [
        Expanded(
          child: _EditButton(
            text: saving
                ? tr('Saving…', 'جاري الحفظ…')
                : tr('Save changes', 'حفظ التغييرات'),
            onTap: saving ? null : save,
            primary: true,
            busy: saving,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _EditButton(
            text: tr('Cancel', 'إلغاء'),
            onTap: saving ? null : () => page.c.leaveTo('/profile', page),
          ),
        ),
      ],
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (error != null || success != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: error == null
                  ? colors.soft
                  : colors.danger.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              error ?? success!,
              style: TextStyle(
                color: error == null ? colors.accent : colors.danger,
                fontSize: 14,
              ),
            ),
          ),
        if (mobile && !hideSave) ...[actions, const SizedBox(height: 14)],
        _preview(colors),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tab in tabs)
              Material(
                color: tab.$1 == panel ? colors.soft : colors.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: tab.$1 == panel ? Colors.transparent : colors.border,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: saving ? null : () => setState(() => panel = tab.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 9,
                    ),
                    child: Text(
                      tab.$2,
                      style: TextStyle(
                        color: tab.$1 == panel ? colors.accent : colors.text,
                        fontSize: 13.44,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _card(colors, switch (panel) {
          'avatar' => _avatarPanel(colors),
          'banner' => _bannerPanel(colors),
          'skills' => _skillsPanel(colors),
          'security' => _securityPanel(colors),
          _ => _detailsPanel(colors),
        }),
        if (!mobile && !hideSave) ...[
          const SizedBox(height: 6),
          actions,
          const SizedBox(height: 26),
        ],
      ],
    );
  }

  Widget _card(_EditColors colors, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 19),
    decoration: BoxDecoration(
      color: colors.secondary,
      border: Border.all(color: colors.border),
      borderRadius: BorderRadius.circular(17),
    ),
    child: child,
  );

  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18.56,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3712,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14.72,
            color: _EditColors(context).muted,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _preview(_EditColors colors) {
    final avatarSource =
        avatar == person['avatar'] && value(person['avatar_url']).isNotEmpty
        ? value(person['avatar_url'])
        : '/avatars/$avatar';
    final bannerSource = imageBanner ? bannerUrl(banner) : '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.secondary,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Container(
            height: 165,
            color: bannerColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageBanner && bannerBytes != null)
                  Image.memory(bannerBytes!, fit: BoxFit.cover)
                else if (bannerSource.isNotEmpty)
                  _networkImage(bannerSource, fit: BoxFit.cover),
                PositionedDirectional(
                  end: 18,
                  bottom: 15,
                  child: Material(
                    color: const Color(0xa6000000),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: () => setState(() => panel = 'banner'),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tr('Change banner', 'تغيير الغلاف'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.28,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (saving && bannerBytes != null)
                  Positioned.fill(child: _uploadOverlay()),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 15),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 53,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PositionedDirectional(
                        start: 0,
                        top: -35,
                        child: InkWell(
                          onTap: () => setState(() => panel = 'avatar'),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: colors.secondary,
                                  spreadRadius: 4,
                                ),
                                const BoxShadow(
                                  color: Color(0x26000000),
                                  offset: Offset(0, 4),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipOval(
                                  child: SizedBox.expand(
                                    child: avatarBytes != null
                                        ? Image.memory(
                                            avatarBytes!,
                                            fit: BoxFit.cover,
                                          )
                                        : _networkImage(
                                            avatarSource,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                PositionedDirectional(
                                  end: -3,
                                  bottom: 0,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xff2e855d),
                                      boxShadow: [
                                        BoxShadow(
                                          color: colors.secondary,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                  ),
                                ),
                                if (saving && avatarBytes != null)
                                  Positioned.fill(
                                    child: ClipOval(child: _uploadOverlay()),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        value(person['username']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18.08,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '@${value(person['university_id'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadOverlay() => ColoredBox(
    color: const Color(0x73000000),
    child: const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
      ),
    ),
  );

  Widget _networkImage(String url, {BoxFit fit = BoxFit.cover}) => networkImage(
    page.c.api.media(url),
    fit: fit,
    errorBuilder: (_, _, _) => Container(color: _EditColors(context).secondary),
  );

  Widget _detailsPanel(_EditColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        tr('About you', 'معلومات عنك'),
        tr(
          'Your details help people get to know you.',
          'بياناتك بتساعد الناس تتعرف عليك.',
        ),
      ),
      _EditSelect(
        label: tr('Major', 'التخصص'),
        hint: tr('Choose your major', 'اختار تخصصك'),
        selected: major,
        options: _options(page.data['allowed_majors']),
        translate: translateOption,
        onChanged: saving ? null : (v) => setState(() => major = v),
        error: errorFor('major'),
      ),
      const SizedBox(height: 15),
      _EditSelect(
        label: tr('City', 'المحافظة'),
        hint: tr('Choose your city', 'اختار محافظتك'),
        selected: city,
        options: _options(page.data['egyptian_cities']),
        translate: translateOption,
        onChanged: saving ? null : (v) => setState(() => city = v),
        error: errorFor('city'),
      ),
      const SizedBox(height: 15),
      _EditFieldLabel(
        label: tr('Birth date', 'تاريخ الميلاد'),
        error: errorFor('birthdate'),
        child: _birthPicker(),
      ),
      const SizedBox(height: 15),
      _EditSelect(
        label: tr('Current role', 'الوظيفة الحالية'),
        hint: tr('Choose your role', 'اختار وظيفتك'),
        selected: job,
        options: _options(page.data['job_options']),
        translate: translateOption,
        onChanged: saving ? null : (v) => setState(() => job = v),
        error: errorFor('job'),
      ),
      const SizedBox(height: 15),
      _EditTextField(
        label: tr('Graduation year', 'سنة التخرج'),
        controller: graduation,
        hint: '${DateTime.now().year}',
        numeric: true,
        enabled: !saving,
        error: errorFor('graduation_year'),
      ),
    ],
  );

  List<String> _options(dynamic input) => input is List
      ? input.map((v) => '$v').toList()
      : object(input).keys.toList();

  Widget _birthPicker() {
    final now = DateTime.now();
    final minYear = now.year - 100, maxYear = now.year - 16;
    final years = [for (var y = maxYear; y >= minYear; y--) '$y'];
    if (year != null && !years.contains('$year')) years.add('$year');
    final daysInMonth = DateTime(year ?? 2000, (month ?? 1) + 1, 0).day;
    Widget part(
      String hint,
      String? current,
      List<String> options,
      void Function(String?) changed, {
      String Function(String)? translate,
    }) => _EditSelect(
      hint: hint,
      selected: current,
      options: options,
      translate: translate,
      onChanged: saving ? null : changed,
    );
    final dayPicker = part(
      tr('Day', 'اليوم'),
      day?.toString(),
      [for (var d = 1; d <= daysInMonth; d++) '$d'],
      (v) => setState(() {
        day = int.tryParse(v ?? '');
        _clampBirth();
      }),
    );
    final monthPicker = part(
      tr('Month', 'الشهر'),
      month?.toString(),
      [for (var m = 1; m <= 12; m++) '$m'],
      (v) => setState(() {
        month = int.tryParse(v ?? '');
        _clampBirth();
      }),
      translate: (v) => DateFormat.MMMM(
        page.c.settings.language,
      ).format(DateTime(2000, int.parse(v))),
    );
    final yearPicker = part(
      tr('Year', 'السنة'),
      year?.toString(),
      years,
      (v) => setState(() {
        year = int.tryParse(v ?? '');
        _clampBirth();
      }),
    );
    if (MediaQuery.sizeOf(context).width <= 340) {
      return Column(
        children: [
          monthPicker,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: dayPicker),
              const SizedBox(width: 8),
              Expanded(child: yearPicker),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 9, child: dayPicker),
        const SizedBox(width: 8),
        Expanded(flex: 15, child: monthPicker),
        const SizedBox(width: 8),
        Expanded(flex: 11, child: yearPicker),
      ],
    );
  }

  void _clampBirth() {
    final now = DateTime.now();
    if (year == now.year - 16 && month != null && month! > now.month) {
      month = now.month;
    }
    if (year == now.year - 100 && month != null && month! < now.month) {
      month = now.month;
    }
    if (day != null && month != null) {
      day = math.min(day!, DateTime(year ?? 2000, month! + 1, 0).day);
      if (year == now.year - 16 && month == now.month) {
        day = math.min(day!, now.day);
      }
      if (year == now.year - 100 && month == now.month) {
        day = math.max(day!, now.day);
      }
    }
  }

  Widget _avatarPanel(_EditColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        tr('Profile photo', 'صورة الملف الشخصي'),
        tr('Pick a photo for your profile.', 'اختار الصورة اللي تظهر في ملفك.'),
      ),
      if (canUpload) _uploadControls(false, colors),
      LayoutBuilder(
        builder: (context, constraints) {
          final count = math.max(1, ((constraints.maxWidth + 13) / 73).floor());
          final available = _options(page.data['available_avatars']);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisSpacing: 13,
              crossAxisSpacing: 13,
            ),
            itemCount: available.length,
            itemBuilder: (_, index) {
              final file = available[index];
              final selected = avatarBytes == null && avatar == file;
              return Align(
                alignment: AlignmentDirectional.topStart,
                child: Semantics(
                  selected: selected,
                  button: true,
                  label:
                      '${tr('Profile photo', 'صورة الملف الشخصي')} ${index + 1}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: saving
                        ? null
                        : () => setState(() {
                            avatar = file;
                            avatarBytes = null;
                          }),
                    child: Container(
                      width: 60,
                      height: 60,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? colors.accent : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: colors.soft, spreadRadius: 3)]
                            : null,
                      ),
                      child: ClipOval(child: _networkImage('/avatars/$file')),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      if (errorFor('avatar_upload') != null)
        _fieldError(errorFor('avatar_upload')!),
    ],
  );

  Widget _uploadControls(bool forBanner, _EditColors colors) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _EditButton(
              text: forBanner
                  ? tr('Upload a banner', 'ارفع صورة للغلاف')
                  : tr('Upload a photo', 'ارفع صورتك'),
              icon: forBanner ? Icons.image : Icons.camera_alt,
              onTap: saving ? null : () => pickPhoto(forBanner),
            ),
            if (forBanner && bannerOriginal != null)
              _textLink(
                tr('Adjust crop', 'عدّل القص'),
                () => cropBanner(bannerOriginal!),
              ),
            if ((forBanner ? bannerBytes : avatarBytes) != null)
              _textLink(
                tr('Clear selection', 'إلغاء الاختيار'),
                () => setState(() {
                  if (forBanner) {
                    bannerBytes = null;
                    bannerOriginal = null;
                  } else {
                    avatarBytes = null;
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          forBanner
              ? tr(
                  'JPEG, PNG or WebP · Up to 5 MB. Your banner updates when you save.',
                  'JPEG أو PNG أو WebP · بحد أقصى ٥ ميجابايت. الغلاف هيتغير لما تحفظ.',
                )
              : tr(
                  'JPEG, PNG or WebP · Up to 5 MB. Your photo updates when you save.',
                  'JPEG أو PNG أو WebP · بحد أقصى ٥ ميجابايت. صورتك هتتغير لما تحفظ.',
                ),
          style: TextStyle(fontSize: 13.12, color: colors.muted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _bannerPanel(_EditColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        tr('Banner', 'الغلاف'),
        tr(
          'Choose a color or one of our images.',
          'اختار لون أو صورة من الصور المتاحة.',
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.main,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in [
                (false, tr('Solid color', 'لون ثابت')),
                (true, tr('Image', 'صورة')),
              ]) ...[
                if (item.$1) const SizedBox(width: 3),
                Material(
                  color: imageBanner == item.$1
                      ? colors.secondary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  elevation: imageBanner == item.$1 ? 2 : 0,
                  shadowColor: const Color(0x1a000000),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: saving
                        ? null
                        : () => setState(() {
                            imageBanner = item.$1;
                            if (!imageBanner) {
                              banner = '';
                              bannerBytes = null;
                              bannerOriginal = null;
                            }
                          }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 14.08,
                          fontWeight: FontWeight.w600,
                          color: imageBanner == item.$1
                              ? colors.text
                              : colors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      if (!imageBanner)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: saving
                  ? null
                  : () async {
                      final result = await showDialog<Color>(
                        context: context,
                        builder: (_) =>
                            _NativeColorPicker(initial: bannerColor),
                      );
                      if (result == null || !mounted) return;
                      setState(
                        () => hex.text =
                            '#${(result.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                      );
                    },
              child: Container(
                width: 48,
                height: 47,
                decoration: BoxDecoration(
                  color: bannerColor,
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _EditTextField(
                label: tr('Color code', 'كود اللون'),
                controller: hex,
                enabled: !saving,
                maxLength: 7,
                ltr: true,
                onChanged: (_) => setState(() {}),
                error: errorFor('banner_color'),
              ),
            ),
          ],
        )
      else ...[
        if (canUpload) _uploadControls(true, colors),
        LayoutBuilder(
          builder: (_, constraints) {
            final available = _options(page.data['allowed_banner_images']);
            final count = math.max(
              1,
              ((constraints.maxWidth + 12) / 152).floor(),
            );
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 16 / 9,
              ),
              itemCount: available.length,
              itemBuilder: (_, index) {
                final source = available[index];
                final selected = bannerBytes == null && banner == source;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: '${tr('Image', 'صورة')} ${index + 1}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: selected
                          ? [
                              BoxShadow(color: colors.soft, spreadRadius: 4),
                              BoxShadow(
                                color: colors.accent.withValues(alpha: .28),
                                offset: const Offset(0, 4),
                                blurRadius: 20,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: GestureDetector(
                        onTap: saving
                            ? null
                            : () => setState(() {
                                banner = source;
                                bannerBytes = null;
                                bannerOriginal = null;
                              }),
                        child: _networkImage(bannerUrl(source)),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
      if (errorFor('banner_upload') != null)
        _fieldError(errorFor('banner_upload')!),
    ],
  );

  Widget _skillsPanel(_EditColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        tr('Skills', 'المهارات'),
        tr(
          'Show what you know. Add or remove skills any time.',
          'اعرض مهاراتك، وضيف أو احذف في أي وقت.',
        ),
      ),
      if (skills.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            tr('No skills added yet.', 'لسه مفيش مهارات مضافة.'),
            style: TextStyle(fontSize: 14.4, color: colors.muted),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final item in skills)
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 5, 5),
                  decoration: BoxDecoration(
                    color: colors.soft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          value(item['skill_name']),
                          style: const TextStyle(
                            fontSize: 13.44,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: skillBusy
                            ? null
                            : () => updateSkill(remove: item),
                        child: SizedBox(
                          width: 27,
                          height: 27,
                          child: Center(
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: colors.muted,
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
      _EditTextField(
        label: tr('Add skill', 'إضافة مهارة'),
        controller: skill,
        hint: tr('Enter a skill', 'اكتب مهارة'),
        maxLength: 100,
        enabled: !skillBusy,
        onSubmitted: (_) => updateSkill(),
      ),
      const SizedBox(height: 10),
      _EditButton(
        text: tr('Add skill', 'إضافة مهارة'),
        icon: Icons.add,
        onTap: skillBusy ? null : updateSkill,
        busy: skillBusy,
      ),
    ],
  );

  Widget _securityPanel(_EditColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        tr('Security (Change Password)', 'الأمان (تغيير كلمة السر)'),
        tr('Keep your account protected.', 'حافظ على أمان حسابك.'),
      ),
      _EditTextField(
        label: tr('Current password', 'كلمة السر الحالية'),
        controller: currentPassword,
        secret: true,
        enabled: !saving,
        error: errorFor('current_password'),
      ),
      const SizedBox(height: 15),
      _EditTextField(
        label: tr('New password', 'كلمة السر الجديدة'),
        controller: newPassword,
        secret: true,
        enabled: !saving,
        maxLength: 72,
        hint: tr('At least 6 characters', '٦ أحرف على الأقل'),
        error: errorFor('password'),
      ),
      const SizedBox(height: 15),
      _EditTextField(
        label: tr('Confirm new password', 'تأكيد كلمة السر الجديدة'),
        controller: confirmPassword,
        secret: true,
        enabled: !saving,
        maxLength: 72,
        error: errorFor('password_confirmation'),
      ),
      const SizedBox(height: 20),
      _textLink(
        tr('Forgot your password? Reset it', 'نسيت كلمة السر؟ غيّرها'),
        () => page.c.open('/profile/password/reset'),
      ),
      const SizedBox(height: 16),
      _EditButton(
        text: tr('Change password', 'تغيير كلمة السر'),
        primary: true,
        onTap: saving ? null : password,
        busy: saving,
      ),
    ],
  );

  Widget _textLink(String label, VoidCallback onTap) => InkWell(
    onTap: saving ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          color: _EditColors(context).accent,
          fontSize: 13.44,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _fieldError(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(color: _EditColors(context).danger, fontSize: 12),
    ),
  );

  String translateOption(String text) =>
      page.c.settings.language != 'ar' ? text : _optionArabic[text] ?? text;
}

class _EditFieldLabel extends StatelessWidget {
  const _EditFieldLabel({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13.76, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      child,
      if (error != null) ...[
        const SizedBox(height: 8),
        Text(
          error!,
          style: TextStyle(color: _EditColors(context).danger, fontSize: 12),
        ),
      ],
    ],
  );
}

class _EditSelect extends StatelessWidget {
  const _EditSelect({
    this.label,
    required this.hint,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.translate,
    this.error,
  });
  final String? label, selected, error;
  final String hint;
  final List<String> options;
  final void Function(String?)? onChanged;
  final String Function(String)? translate;
  @override
  Widget build(BuildContext context) {
    final colors = _EditColors(context);
    final items = {...options, ?selected};
    final dropdown = Container(
      height: 47,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.main,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(13),
      ),
      child: DropdownButtonHideUnderline(
        child: AppDropdownButton<String>(
          value: selected,
          isExpanded: true,
          hint: Text(
            hint,
            style: TextStyle(fontSize: 16, color: colors.text),
            overflow: TextOverflow.ellipsis,
          ),
          style: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            fontFamilyFallback: Theme.of(
              context,
            ).textTheme.bodyMedium?.fontFamilyFallback,
            fontSize: 16,
            color: colors.text,
            fontWeight: FontWeight.w400,
          ),
          icon: const WebIcon(
            'chevron-down',
            size: 16,
            color: Color(0xff838b86),
          ),
          dropdownColor: colors.main,
          borderRadius: BorderRadius.circular(13),
          menuMaxHeight: MediaQuery.sizeOf(context).height * .55,
          onChanged: onChanged,
          items: [
            DropdownMenuItem<String>(value: null, child: Text(hint)),
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  translate?.call(item) ?? item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
    return label == null
        ? dropdown
        : _EditFieldLabel(label: label!, error: error, child: dropdown);
  }
}

class _EditTextField extends StatelessWidget {
  const _EditTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.secret = false,
    this.numeric = false,
    this.enabled = true,
    this.maxLength,
    this.error,
    this.ltr = false,
    this.onChanged,
    this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final String? hint, error;
  final bool secret, numeric, enabled, ltr;
  final int? maxLength;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) {
    final colors = _EditColors(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: colors.border),
    );
    return _EditFieldLabel(
      label: label,
      error: error,
      child: SizedBox(
        height: 47,
        child: AdaptiveTextField(
          controller: controller,
          field: (direction) => TextField(
            controller: controller,
            // Mobile touch events keep focus unless dismissal is explicit.
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            enabled: enabled,
            obscureText: secret,
            textDirection: ltr ? TextDirection.ltr : direction,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            inputFormatters: numeric
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            maxLength: maxLength,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: colors.text,
            ),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: true,
              fillColor: colors.main,
              hintStyle: TextStyle(
                fontSize: 16,
                color: colors.muted.withValues(alpha: .8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              disabledBorder: border,
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({
    required this.text,
    required this.onTap,
    this.primary = false,
    this.busy = false,
    this.icon,
  });
  final String text;
  final VoidCallback? onTap;
  final bool primary, busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final colors = _EditColors(context);
    return Material(
      color: primary ? const Color(0xff2e855d) : colors.secondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: primary ? Colors.transparent : colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary ? Colors.white : colors.text,
                  ),
                ),
                const SizedBox(width: 9),
              ] else if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: primary ? Colors.white : colors.text,
                ),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: primary ? Colors.white : colors.text,
                    fontSize: 14.56,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerCrop extends StatefulWidget {
  const _BannerCrop({required this.page, required this.bytes});
  final NativePageState page;
  final Uint8List bytes;
  @override
  State<_BannerCrop> createState() => _BannerCropState();
}

class _BannerCropState extends State<_BannerCrop> {
  ui.Image? image;
  double zoom = 1, startZoom = 1, cx = 0, cy = 0;
  Size stage = Size.zero;
  bool saving = false;
  String? error;
  String tr(String en, String ar) => widget.page.c.t(en, ar);

  @override
  void initState() {
    super.initState();
    decode();
  }

  Future<void> decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        image = frame.image;
        cx = image!.width / 2;
        cy = image!.height / 2;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            'This image could not be prepared. Try another one.',
            'معرفناش نجهز الصورة دي. جرّب صورة تانية.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  Rect get window => Rect.fromCenter(
    center: Offset(stage.width / 2, stage.height / 2),
    width: math.max(1, stage.width - 16),
    height: math.max(1, stage.width - 16) / (1080 / 260),
  );
  double get scale => image == null
      ? 1
      : math.max(window.width / image!.width, window.height / image!.height) *
            zoom;

  void constrain() {
    if (image == null) return;
    final halfW = window.width / scale / 2, halfH = window.height / scale / 2;
    cx = cx.clamp(halfW, image!.width - halfW);
    cy = cy.clamp(halfH, image!.height - halfH);
  }

  Future<void> apply() async {
    if (image == null || saving) return;
    setState(() => saving = true);
    try {
      constrain();
      final source = Rect.fromCenter(
        center: Offset(cx, cy),
        width: window.width / scale,
        height: window.height / scale,
      );
      final outputWidth = math.min(2400, source.width).round();
      final outputHeight = (outputWidth / (1080 / 260)).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image!,
        source,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outputWidth, outputHeight);
      picture.dispose();
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (data == null) throw StateError('Image encoding failed');
      final bytes = data.buffer.asUint8List();
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError(
          tr(
            'Choose an image up to 5 MB.',
            'اختار صورة حجمها بحد أقصى ٥ ميجابايت.',
          ),
        );
      }
      if (mounted) Navigator.pop(context, bytes);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$exception';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EditColors(context);
    return Dialog(
      backgroundColor: colors.secondary,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Adjust your banner', 'ظبط الغلاف'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Drag to choose what shows. Pinch, scroll or use the slider to zoom.',
                'اسحب الصورة عشان تختار الجزء اللي هيظهر، وكبّر بصباعين أو بالشريط.',
              ),
              style: TextStyle(fontSize: 14, height: 1.5, color: colors.muted),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * .42).clamp(
                190.0,
                340.0,
              ),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  stage = Size(constraints.maxWidth, constraints.maxHeight);
                  constrain();
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GestureDetector(
                      onScaleStart: (_) => startZoom = zoom,
                      onScaleUpdate: image == null
                          ? null
                          : (details) => setState(() {
                              zoom = (startZoom * details.scale).clamp(
                                1.0,
                                4.0,
                              );
                              cx -= details.focalPointDelta.dx / scale;
                              cy -= details.focalPointDelta.dy / scale;
                              constrain();
                            }),
                      child: CustomPaint(
                        size: stage,
                        painter: _CropPainter(
                          image: image,
                          cx: cx,
                          cy: cy,
                          zoom: zoom,
                          accent: colors.accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final guide in [
                  (0, tr('Computer', 'الكمبيوتر')),
                  (1, tr('Tablet', 'التابلت')),
                  (2, tr('Phone', 'الموبايل')),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 12,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: guide.$1 == 2 ? colors.accent : colors.text,
                            width: guide.$1 == 0 ? 2 : 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        guide.$2,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  tr('Zoom', 'التكبير'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: zoom,
                    min: 1,
                    max: 4,
                    activeColor: const Color(0xff2e855d),
                    onChanged: (v) => setState(() {
                      zoom = v;
                      constrain();
                    }),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: colors.danger, fontSize: 14),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _EditButton(
                    text: tr('Cancel', 'إلغاء'),
                    onTap: saving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _EditButton(
                    text: tr('Use this banner', 'استخدم الغلاف ده'),
                    primary: true,
                    onTap: image == null || saving ? null : apply,
                    busy: saving,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.cx,
    required this.cy,
    required this.zoom,
    required this.accent,
  });
  final ui.Image? image;
  final double cx, cy, zoom;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff111111), BlendMode.src);
    final window = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - 16,
      height: (size.width - 16) / (1080 / 260),
    );
    if (image != null) {
      final scale =
          math.max(window.width / image!.width, window.height / image!.height) *
          zoom;
      final rect = Rect.fromLTWH(
        window.center.dx - cx * scale,
        window.center.dy - cy * scale,
        image!.width * scale,
        image!.height * scale,
      );
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectAndRadius(window, const Radius.circular(6))),
      Paint()..color = const Color(0x94000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, const Radius.circular(6)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final factor in [758 / 1080, (375 / 184) / (1080 / 260)]) {
      final half = window.width * factor / 2;
      final phone = factor < .6;
      final paint = Paint()
        ..color = phone ? accent : const Color(0xd9ffffff)
        ..strokeWidth = phone ? 2 : 1.5;
      for (final x in [window.center.dx - half, window.center.dx + half]) {
        for (double y = window.top; y < window.bottom; y += phone ? 5 : 9) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x, math.min(window.bottom, y + (phone ? 2 : 5))),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => true;
}

class _NativeColorPicker extends StatefulWidget {
  const _NativeColorPicker({required this.initial});
  final Color initial;
  @override
  State<_NativeColorPicker> createState() => _NativeColorPickerState();
}

class _NativeColorPickerState extends State<_NativeColorPicker> {
  late HSVColor color = HSVColor.fromColor(widget.initial);
  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (_, constraints) => GestureDetector(
            onPanDown: (details) => setState(
              () => color = color
                  .withSaturation(
                    (details.localPosition.dx / constraints.maxWidth).clamp(
                      0.0,
                      1.0,
                    ),
                  )
                  .withValue(
                    (1 - details.localPosition.dy / 180).clamp(0.0, 1.0),
                  ),
            ),
            onPanUpdate: (details) => setState(
              () => color = color
                  .withSaturation(
                    (details.localPosition.dx / constraints.maxWidth).clamp(
                      0.0,
                      1.0,
                    ),
                  )
                  .withValue(
                    (1 - details.localPosition.dy / 180).clamp(0.0, 1.0),
                  ),
            ),
            child: SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                  Positioned(
                    left: color.saturation * constraints.maxWidth - 6,
                    top: (1 - color.value) * 180 - 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        color: color.toColor(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Slider(
          value: color.hue,
          max: 360,
          activeColor: color.toColor(),
          onChanged: (v) => setState(() => color = color.withHue(v)),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, color.toColor()),
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}

class _EditColors {
  _EditColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get main => dark ? const Color(0xff0a0a0a) : Colors.white;
  Color get secondary =>
      dark ? const Color(0xff141414) : const Color(0xfff9fafb);
  Color get text => dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
  Color get muted => dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get border => dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
  Color get accent => dark ? const Color(0xff7ace9f) : const Color(0xff2e855d);
  Color get soft => accent.withValues(alpha: dark ? .12 : .10);
  Color get danger => dark ? const Color(0xffe7767d) : const Color(0xffc53d46);
}

Color? _parseColor(String input) {
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(input.trim())) return null;
  return Color(int.parse('ff${input.trim().substring(1)}', radix: 16));
}

const _optionArabic = <String, String>{
  'Computer Science': 'علوم الحاسب',
  'Information Systems': 'نظم المعلومات',
  'Business Administration (Arabic)': 'إدارة الأعمال (عربي)',
  'Business Administration (English)': 'إدارة الأعمال (إنجليزي)',
  'Cairo': 'القاهرة',
  'Alexandria': 'الإسكندرية',
  'Giza': 'الجيزة',
  'Qalyubia': 'القليوبية',
  'Port Said': 'بورسعيد',
  'Suez': 'السويس',
  'Luxor': 'الأقصر',
  'Aswan': 'أسوان',
  'Asyut': 'أسيوط',
  'Beheira': 'البحيرة',
  'Beni Suef': 'بني سويف',
  'Dakahlia': 'الدقهلية',
  'Damietta': 'دمياط',
  'Faiyum': 'الفيوم',
  'Gharbia': 'الغربية',
  'Ismailia': 'الإسماعيلية',
  'Kafr El Sheikh': 'كفر الشيخ',
  'Matrouh': 'مطروح',
  'Minya': 'المنيا',
  'Monufia': 'المنوفية',
  'New Valley': 'الوادي الجديد',
  'North Sinai': 'شمال سيناء',
  'Qena': 'قنا',
  'Red Sea': 'البحر الأحمر',
  'Sharqia': 'الشرقية',
  'Sohag': 'سوهاج',
  'South Sinai': 'جنوب سيناء',
  'Student': 'طالب',
  'Software Engineer': 'مهندس برمجيات',
  'Cyber Security Engineer': 'مهندس أمن سيبراني',
  'Data Scientist': 'عالم بيانات',
  'Product Manager': 'مدير منتج',
  'Designer': 'مصمم',
  'Business Analyst': 'محلل أعمال',
  'Marketing Specialist': 'أخصائي تسويق',
  'Consultant': 'استشاري',
  'Entrepreneur': 'رائد أعمال',
  'Research Assistant': 'مساعد بحث',
  'Teaching Assistant': 'معيد',
  'Intern': 'متدرب',
  'Freelancer': 'مستقل',
  'Other': 'أخرى',
};
