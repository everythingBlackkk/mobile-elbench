import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_home.dart';
import 'web_style.dart';

class WebNotificationSettings extends StatefulWidget {
  const WebNotificationSettings({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebNotificationSettings> createState() =>
      _WebNotificationSettingsState();
}

class _WebNotificationSettingsState extends State<WebNotificationSettings> {
  late Map<String, bool> preferences;
  Timer? timer;
  Future<void>? pending;
  int revision = 0, saved = 0;
  String status = '';
  bool failed = false;
  NativePageState get p => widget.page;
  @override
  void initState() {
    super.initState();
    preferences = object(
      p.data['preferences'],
    ).map((key, v) => MapEntry(key, yes(v)));
  }

  Future<void> flush() {
    timer?.cancel();
    if (pending != null) return pending!;
    if (revision == saved) return Future.value();
    final future = () async {
      try {
        while (saved != revision) {
          final submitted = revision;
          await p.c.action('PUT', '/menu/notifications', {
            'categories': preferences.entries
                .where((e) => e.value)
                .map((e) => e.key)
                .toList(),
          });
          saved = submitted;
        }
        if (mounted) {
          setState(() {
            failed = false;
            status = p.c.t('Saved.', 'اتحفظ.');
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            failed = true;
            status = p.c.t(
              'Could not change notifications. Please try again.',
              'معرفناش نغيّر الإشعارات. جرّب تاني.',
            );
          });
        }
      }
    }();
    pending = future;
    future.whenComplete(() => pending = null);
    return future;
  }

  void changed(String? category, bool on) {
    setState(() {
      if (category == null) {
        preferences.updateAll((_, _) => on);
      } else {
        preferences[category] = on;
      }
      revision++;
      status = '';
    });
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 250), flush);
  }

  @override
  void dispose() {
    timer?.cancel();
    flush();
    super.dispose();
  }

  (String, String) copy(String key) => switch (key) {
    'inbox' => (
      p.c.t('Inbox', 'صندوق الوارد'),
      p.c.t(
        'New questions you are asked, and answers to questions you asked.',
        'الأسئلة الجديدة اللي بتتسألها، والإجابات على أسئلتك.',
      ),
    ),
    'replies' => (
      p.c.t('Replies', 'الردود'),
      p.c.t(
        'Comments on your posts and answers to your community questions.',
        'التعليقات على منشوراتك والإجابات على أسئلتك في المجتمع.',
      ),
    ),
    'reactions' => (
      p.c.t('Reactions', 'التفاعلات'),
      p.c.t(
        'Reactions to your posts and comments.',
        'التفاعلات على منشوراتك وتعليقاتك.',
      ),
    ),
    'announcements' => (
      p.c.t('University announcements', 'إعلانات الجامعة'),
      p.c.t(
        'Official updates from the university.',
        'التحديثات الرسمية من الجامعة.',
      ),
    ),
    _ => (key, ''),
  };
  Widget row(
    String title,
    String description,
    bool on,
    ValueChanged<bool> changed, {
    bool all = false,
    bool last = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(
              bottom: BorderSide(color: webBorder(context), width: all ? 2 : 1),
            ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.68,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12.8,
                  height: 1.5,
                  color: webMuted(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        WebSwitch(value: on, onChanged: changed, label: title),
      ],
    ),
  );
  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      title,
      style: TextStyle(
        color: webMuted(context),
        fontSize: 13.12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(10, 12, 10, 110),
    children: [
      Text(
        p.c.t(
          'Choose which notifications reach your phone, even when the app is closed.',
          'اختار الإشعارات اللي توصل موبايلك، حتى لو التطبيق مقفول.',
        ),
        style: TextStyle(
          color: webMuted(context),
          fontSize: 14.72,
          height: 1.6,
        ),
      ),
      ListenableBuilder(
        listenable: p.c.push,
        builder: (_, _) => p.c.push.registered
            ? const SizedBox()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section(p.c.t('This device', 'الجهاز ده')),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: webSecondary(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: webBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !p.c.push.available
                              ? p.c.t(
                                  'Notifications on this device are coming soon.',
                                  'الإشعارات على الجهاز ده جاية قريب.',
                                )
                              : p.c.push.enabled
                              ? p.c.t(
                                  'Could not change notifications. Please try again.',
                                  'معرفناش نغيّر الإشعارات. جرّب تاني.',
                                )
                              : p.c.t(
                                  'Notifications are off for this device.',
                                  'الإشعارات متوقفة على الجهاز ده.',
                                ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                        if (p.c.push.available) ...[
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: p.c.push.enable,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 9,
                              ),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(p.c.t('Turn on', 'تفعيل')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
      section(p.c.t('Notify me about', 'ابعتلي إشعار عن')),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: webSecondary(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: webBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              p.c.t('All notifications', 'كل الإشعارات'),
              p.c.t(
                'Turn every kind on or off at once.',
                'شغّل أو اقفل كل الأنواع مرة واحدة.',
              ),
              preferences.values.every((v) => v),
              (v) => changed(null, v),
              all: true,
            ),
            for (final entry in preferences.entries)
              row(
                copy(entry.key).$1,
                copy(entry.key).$2,
                entry.value,
                (v) => changed(entry.key, v),
                last: entry.key == preferences.keys.last,
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 13.6,
                      color: failed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (failed)
                  TextButton(
                    onPressed: flush,
                    child: Text(p.c.t('Save', 'حفظ')),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        p.c.t(
          'Your choices apply to every device you use. The Notifications page in the app still lists everything.',
          'اختياراتك بتتطبق على كل أجهزتك. صفحة الإشعارات في التطبيق هتفضل تعرض كل حاجة.',
        ),
        style: TextStyle(color: webMuted(context), fontSize: 12.8, height: 1.6),
      ),
    ],
  );
}

class WebSwitch extends StatelessWidget {
  const WebSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: value,
    child: GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        width: 51,
        height: 31,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? const Color(0xff2e855d) : const Color(0x52787880),
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .22),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WebSuggestions extends StatefulWidget {
  const WebSuggestions({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebSuggestions> createState() => _WebSuggestionsState();
}

class _WebSuggestionsState extends State<WebSuggestions> {
  final title = TextEditingController(), details = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? message;
  bool failed = false;
  NativePageState get p => widget.page;
  @override
  void dispose() {
    title.dispose();
    details.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final response = await p.c.action('POST', '/suggestions', {
        'suggestion_title': title.text.trim(),
        'suggestion_details': details.text.trim(),
        'submit_suggestion': '1',
      });
      if (!mounted) return;
      setState(() {
        failed = false;
        message = value(
          response['message'],
          p.c.t('Your suggestion has been submitted.', 'تم إرسال اقتراحك.'),
        );
      });
      title.clear();
      details.clear();
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController input,
    String label,
    String hint,
    int max, {
    int lines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: input,
            builder: (context, value, _) => Text(
              '${value.text.characters.length} / $max',
              textDirection: TextDirection.ltr,
              style: TextStyle(color: webMuted(context), fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      RepaintBoundary(
        child: AdaptiveTextField(
          controller: input,
          field: (direction) => TextFormField(
            controller: input,
            textDirection: direction,
            minLines: lines,
            maxLines: lines,
            maxLength: max,
            validator: (v) => v!.trim().isEmpty
                ? p.c.t('This field is required.', 'هذا الحقل مطلوب.')
                : null,
            style: const TextStyle(fontSize: 16, height: 1.6),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: webBorder(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: webBorder(context)),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
    children: [
      Text(
        p.c.t(
          'Help us improve by sharing your ideas',
          'ساعدنا نطور المنصة بأفكارك',
        ),
        style: TextStyle(fontSize: 14, height: 1.6, color: webMuted(context)),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: webSecondary(context),
          border: Border.all(color: webBorder(context)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    message!,
                    style: TextStyle(
                      color: failed
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              field(
                title,
                p.c.t('Title', 'العنوان'),
                p.c.t(
                  'Enter your suggestion title...',
                  'اكتب عنوان الاقتراح...',
                ),
                250,
              ),
              const SizedBox(height: 20),
              field(
                details,
                p.c.t('Details', 'التفاصيل'),
                p.c.t(
                  'Describe your suggestion in detail...',
                  'اشرح اقتراحك بالتفصيل...',
                ),
                1000,
                lines: 6,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.c.t('Submit Suggestion', 'إرسال الاقتراح')),
                      const SizedBox(width: 10),
                      const WebIcon('paper-plane', color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class WebLoginActivity extends StatelessWidget {
  const WebLoginActivity({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final p = page;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 110),
      children: [
        Text(
          p.c.t(
            'Your latest seven successful sign-ins, newest first.',
            'آخر ٧ تسجيلات دخول ناجحة لحسابك، الأحدث الأول.',
          ),
          style: TextStyle(
            fontSize: 14.72,
            height: 1.6,
            color: webMuted(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          p.c.t(
            'Device details are reported by your browser.',
            'تفاصيل الجهاز حسب المعلومات اللي بيبعتها المتصفح.',
          ),
          style: TextStyle(
            fontSize: 12.8,
            height: 1.6,
            color: webMuted(context),
          ),
        ),
        const SizedBox(height: 16),
        for (final activity in rows(p.data['activities']))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            decoration: BoxDecoration(
              color: webSecondary(context),
              border: Border.all(color: webBorder(context)),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: WebIcon(
                    [
                          'phone',
                          'tablet',
                          'laptop',
                        ].contains(activity['device_type'])
                        ? value(activity['device_type'])
                        : 'monitor',
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            switch (activity['device_type']) {
                              'phone' => p.c.t('Phone', 'هاتف'),
                              'tablet' => p.c.t('Tablet', 'جهاز لوحي'),
                              'laptop' => p.c.t('Laptop', 'كمبيوتر محمول'),
                              'computer' => p.c.t('Computer', 'كمبيوتر'),
                              _ => p.c.t('Unknown device', 'جهاز غير معروف'),
                            },
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                            ),
                          ),
                          Text(
                            webAgo(
                              activity['logged_in_at'],
                              p.c.settings.language == 'ar',
                            ),
                            style: TextStyle(
                              fontSize: 12.16,
                              height: 1.5,
                              color: webMuted(context),
                            ),
                          ),
                        ],
                      ),
                      for (final entry in [
                        (
                          p.c.t('Browser', 'المتصفح'),
                          '${value(activity['browser_name'])} ${value(activity['browser_version'])}'
                              .trim(),
                        ),
                        (
                          p.c.t('Operating system', 'نظام التشغيل'),
                          value(activity['os_name']),
                        ),
                        (
                          p.c.t('Signed in at', 'وقت تسجيل الدخول'),
                          '${DateTime.tryParse(value(activity['logged_in_at'])) == null ? value(activity['logged_in_at']) : DateFormat('d MMM yyyy, HH:mm:ss', p.c.settings.language).format(DateTime.parse(value(activity['logged_in_at'])).toUtc())} UTC',
                        ),
                        if (value(activity['ip_address']).isNotEmpty)
                          (
                            p.c.t('IP address', 'عنوان IP'),
                            value(activity['ip_address']),
                          ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.$1,
                                style: TextStyle(
                                  fontSize: 11.68,
                                  height: 1.5,
                                  color: webMuted(context),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.$2,
                                style: const TextStyle(
                                  fontSize: 13.6,
                                  height: 1.6,
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
        if (rows(p.data['activities']).isEmpty) p.empty(),
        p.pagination(p.data['activities']),
      ],
    );
  }
}
