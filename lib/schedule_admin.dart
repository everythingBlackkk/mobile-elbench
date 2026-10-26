import 'package:flutter/material.dart';

import 'api.dart';
import 'forms.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_schedule.dart' show scheduleDayLabel;

class ScheduleAdminContent extends StatelessWidget {
  const ScheduleAdminContent({super.key, required this.page});
  final NativePageState page;

  Future<void> _edit([Json entry = const {}]) async {
    final c = page.c;
    final options = object(page.data['options']);
    Map<String, String> choices(String key, String label) => {
      for (final item in options[key] as List? ?? const [])
        '$item': '$label $item',
    };
    await page.form(
      entry.isEmpty
          ? c.t('Add class', 'إضافة محاضرة أو سكشن')
          : c.t('Edit class', 'تعديل الموعد'),
      entry.isEmpty ? '/admin/schedule' : '/admin/schedule/${entry['id']}',
      [
        FieldSpec(
          'type',
          c.t('Type', 'النوع'),
          initial: entry['type'] ?? 'lecture',
          options: {
            'lecture': c.t('Lecture', 'محاضرة'),
            'section': c.t('Section', 'سكشن'),
          },
        ),
        FieldSpec(
          'subject',
          c.t('Subject (original name)', 'المادة (الاسم الأصلي)'),
          initial: entry['subject'],
        ),
        FieldSpec(
          'instructor',
          c.t('Instructor (original name)', 'المحاضر (الاسم الأصلي)'),
          initial: entry['instructor'],
          required: false,
        ),
        FieldSpec(
          'location',
          c.t('Location (original name)', 'المكان (الاسم الأصلي)'),
          initial: entry['location'],
          required: false,
        ),
        FieldSpec(
          'level',
          c.t('Level', 'الفرقة'),
          initial: entry['level'],
          options: choices('levels', c.t('Level', 'الفرقة')),
        ),
        FieldSpec(
          'group_number',
          c.t('Group (optional)', 'المجموعة (اختياري)'),
          required: false,
          initial: entry['group_number'],
          options: {
            '': c.t('All groups', 'كل المجموعات'),
            ...choices('groups', c.t('Group', 'المجموعة')),
          },
        ),
        FieldSpec(
          'section_numbers',
          c.t('Sections (none means all)', 'السكاشن (بدون اختيار = الكل)'),
          required: false,
          initial: entry['section_numbers'] ?? [],
          multi: true,
          options: choices('sections', c.t('Section', 'سكشن')),
        ),
        FieldSpec(
          'day_of_week',
          c.t('Day', 'اليوم'),
          initial: entry['day_of_week'] ?? 0,
          options: {
            for (var i = 0; i < 7; i++)
              '$i': c.t(
                const [
                  'Sunday',
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                ][i],
                const [
                  'الأحد',
                  'الاثنين',
                  'الثلاثاء',
                  'الأربعاء',
                  'الخميس',
                  'الجمعة',
                  'السبت',
                ][i],
              ),
          },
        ),
        FieldSpec(
          'start_time',
          c.t('Start (HH:MM)', 'البداية (HH:MM)'),
          initial: value(entry['start_time']).isEmpty
              ? null
              : value(entry['start_time']).substring(0, 5),
          hint: '10:00',
        ),
        FieldSpec(
          'end_time',
          c.t('End (HH:MM)', 'النهاية (HH:MM)'),
          initial: value(entry['end_time']).isEmpty
              ? null
              : value(entry['end_time']).substring(0, 5),
          hint: '11:30',
        ),
        FieldSpec(
          'is_active',
          c.t('Status', 'الحالة'),
          initial: entry.isEmpty || yes(entry['is_active']) ? '1' : '0',
          options: {'1': c.t('Active', 'مفعّل'), '0': c.t('Inactive', 'متوقف')},
        ),
        FieldSpec(
          'valid_from',
          c.t(
            'From date (optional, YYYY-MM-DD)',
            'من تاريخ (اختياري، YYYY-MM-DD)',
          ),
          initial: entry['valid_from'],
          required: false,
        ),
        FieldSpec(
          'valid_until',
          c.t(
            'Until date (optional, YYYY-MM-DD)',
            'إلى تاريخ (اختياري، YYYY-MM-DD)',
          ),
          initial: entry['valid_until'],
          required: false,
        ),
      ],
      method: entry.isEmpty ? 'POST' : 'PUT',
    );
  }

  /// Cancels only the next occurrence of the class; later weeks stay as they are.
  Future<void> _cancelNext(BuildContext context, Json entry) async {
    final c = page.c;
    final day = scheduleDayLabel(entry['next_on'], c.settings.language == 'ar');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.t('Cancel the class on $day?', 'إلغاء ميعاد $day؟')),
        content: Text(
          c.t(
            'Only this one class is cancelled; the following weeks stay as usual.',
            'هيتلغي الميعاد ده بس، والأسابيع اللي بعده هتفضل زي ما هي.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.t('Keep it', 'سيبها')),
          ),
          FilledButton(
            key: const ValueKey('schedule.admin.cancel.confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.t('Cancel class', 'إلغاء الميعاد')),
          ),
        ],
      ),
    );
    if (confirmed == true && page.mounted) {
      await page.run('POST', '/admin/schedule/${entry['id']}/cancellation');
    }
  }

  Future<void> _delete(BuildContext context, Json entry) async {
    final c = page.c;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.t('Delete this class?', 'حذف هذا الموعد؟')),
        content: Text(
          value(entry['subject']),
          textDirection: contentDirection(value(entry['subject'])),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (confirmed == true && page.mounted) {
      await page.run('DELETE', '/admin/schedule/${entry['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = page.c;
    if (!c.permission('schedule.manage')) {
      return Center(
        child: Text(
          c.t(
            'You cannot manage the schedule.',
            'ليس لديك صلاحية إدارة الجدول.',
          ),
        ),
      );
    }
    final entries = rows(page.data['entries']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 120),
      children: [
        Text(
          c.t('Manage schedule', 'إدارة الجدول'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          c.t(
            'Keep original academic names. Changes also update upcoming reminders.',
            'احتفظ بالأسماء الأكاديمية الأصلية. التغييرات تحدّث إشعارات المواعيد القادمة.',
          ),
        ),
        const SizedBox(height: 18),
        if (c.user?['role'] == 'super_admin') ...[
          OutlinedButton.icon(
            key: const ValueKey('schedule.admin.appearance'),
            onPressed: () => c.open('/admin/schedule-appearance'),
            icon: const Icon(Icons.palette_outlined),
            label: Text(c.t('Day off appearance', 'شكل يوم الإجازة')),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          key: const ValueKey('schedule.admin.add'),
          onPressed: _edit,
          icon: const Icon(Icons.add),
          label: Text(c.t('Add lecture or section', 'إضافة محاضرة أو سكشن')),
        ),
        const SizedBox(height: 16),
        for (final entry in entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value(entry['subject']),
                    textDirection: contentDirection(value(entry['subject'])),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      value(entry['instructor']),
                      value(entry['location']),
                      value(entry['source_label']),
                    ].where((v) => v.isNotEmpty).join(' · '),
                    textDirection: TextDirection.ltr,
                  ),
                  Text(
                    '${entry['start_time']} – ${entry['end_time']}',
                    textDirection: TextDirection.ltr,
                  ),
                  Text(
                    '${c.t('Level', 'الفرقة')} ${entry['level']} · ${entry['type'] == 'lecture' ? c.t('Lecture', 'محاضرة') : c.t('Section', 'سكشن')}',
                  ),
                  // One-time cancellation: the pending one with Restore, or the date "Cancel next" would hit.
                  if (value(entry['cancelled_on']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1fe5484d),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              c.t(
                                'Cancelled on ${scheduleDayLabel(entry['cancelled_on'], false)}',
                                'ملغية يوم ${scheduleDayLabel(entry['cancelled_on'], true)}',
                              ),
                              style: const TextStyle(
                                color: Color(0xffe5484d),
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          TextButton(
                            key: ValueKey(
                              'schedule.admin.restore.${entry['id']}',
                            ),
                            onPressed: () => page.run(
                              'DELETE',
                              '/admin/schedule/${entry['id']}/cancellation',
                            ),
                            child: Text(c.t('Restore', 'رجّعها')),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (value(entry['cancelled_on']).isEmpty &&
                          value(entry['next_on']).isNotEmpty)
                        TextButton.icon(
                          key: ValueKey('schedule.admin.cancel.${entry['id']}'),
                          onPressed: () => _cancelNext(context, entry),
                          icon: const Icon(Icons.event_busy_outlined, size: 18),
                          label: Text(c.t('Cancel next', 'إلغاء الجاية')),
                        ),
                      TextButton.icon(
                        key: ValueKey('schedule.admin.edit.${entry['id']}'),
                        onPressed: () => _edit(entry),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(c.t('Edit', 'تعديل')),
                      ),
                      TextButton.icon(
                        onPressed: () => _delete(context, entry),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        label: Text(c.t('Delete', 'حذف')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              c.t(
                'No schedule entries yet.',
                'لا توجد مواعيد في الجدول حتى الآن.',
              ),
            ),
          ),
        page.pagination(page.data['entries']),
      ],
    );
  }
}
