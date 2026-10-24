import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'api.dart';
import 'image_cache.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';

/// Native rendering of admin/index.blade.php and CSS/admin.css.
class AdminContent extends StatelessWidget {
  const AdminContent({super.key, required this.page});
  final NativePageState page;
  String t(String key, [Json args = const {}]) => adminCopy(page, key, args);
  @override
  Widget build(BuildContext context) {
    final p = page, c = p.c, d = p.data, colors = Theme.of(context).colorScheme;
    final section = value(d['activeSection'], 'overview');
    final sections = object(d['sections']);
    final records = rows(d['records']);
    final selected = object(d['selectedUser']);
    final superAdmin = c.user?['role'] == 'super_admin';
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('workspace').toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.54,
                height: 1.65,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('subtitle'),
              style: TextStyle(
                fontSize: 16,
                height: 1.65,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            _AdminBadge(t('roles.${c.user?['role']}')),
          ],
        ),
      ),
      if (value(p.envelope['status']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _AdminAlert(value(p.envelope['status'])),
        ),
      Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (c.permission('quiz.manage') && c.enabled('quiz'))
                _tab(
                  context,
                  c.t('Manage questions', 'إدارة الأسئلة'),
                  false,
                  () => c.open('/quiz/manage'),
                ),
              for (final entry in sections.entries)
                _tab(
                  context,
                  value(entry.value),
                  entry.key == section,
                  () => p.load('/admin?section=${entry.key}'),
                ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value(sections[section], t('title')),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (d['records'] is Map) ...[
              const SizedBox(width: 20),
              _AdminBadge(
                '${object(d['records'])['total'] ?? records.length} ${t('records')}',
              ),
            ],
          ],
        ),
      ),
    ];
    if (section == 'overview') {
      children.addAll([
        for (final entry in sections.entries)
          if (entry.key != 'overview')
            _AdminCard(
              color: colors.surface,
              child: InkWell(
                onTap: () => p.load('/admin?section=${entry.key}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _h3(value(entry.value)),
                    Text(
                      '${t('open_section')} →',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                        height: 1.65,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ]);
    } else if (section == 'features') {
      final states = object(d['featureStates']);
      children.add(
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h3(t('feature_controls')),
              _paragraph(t('feature_guidance'), context, muted: true),
              _AdminForm(
                page: p,
                path: '/admin/features',
                submit: t('save_features'),
                fields: [
                  for (final entry in object(d['featureCatalog']).entries)
                    _AdminField(
                      'features.${entry.key}',
                      value(object(entry.value)['label'], entry.key),
                      kind: _FieldKind.checkbox,
                      initial:
                          states[entry.key] == null || yes(states[entry.key]),
                      description: t(
                        states[entry.key] == null || yes(states[entry.key])
                            ? 'enabled'
                            : 'disabled',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (section == 'announcement_permissions') {
      children.add(
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paragraph(t('announcement_permission_guidance'), context),
              _AdminSearch(page: p, section: section),
            ],
          ),
        ),
      );
      children.add(
        _AdminCard(
          child: _AdminTable(
            headers: [
              t('username'),
              t('university_id'),
              t('announcement_posting'),
            ],
            cells: [
              for (final user in records)
                [
                  Text(value(user['username'])),
                  Text(value(user['university_id'])),
                  if (user['role'] == 'super_admin')
                    Text(t('announcement_inherited'))
                  else
                    SizedBox(
                      width: 255,
                      child: _AdminForm(
                        page: p,
                        path: '/admin/users/${user['id']}/announcements',
                        method: 'PUT',
                        submit: t('save_access'),
                        fields: [
                          _AdminField(
                            'can_post_announcements',
                            t('announcement_posting'),
                            kind: _FieldKind.checkbox,
                            initial: yes(user['can_post_announcements']),
                          ),
                        ],
                      ),
                    ),
                ],
            ],
            empty: t('empty'),
          ),
        ),
      );
    } else if (section == 'users' || section == 'admins') {
      children.add(_AdminSearch(page: p, section: section));
      if (selected.isNotEmpty) {
        children.add(_selectedUser(context, selected));
      } else if (Uri.parse(p.path).queryParameters['search']?.isNotEmpty ??
          false) {
        children.add(_AdminEmpty(t('no_exact_user')));
      }
      if (c.permission('users.manage')) {
        children.add(
          _AdminExpansion(
            title: t('create_user'),
            children: [
              _AdminForm(
                page: p,
                path: '/admin/users',
                submit: t('create_user'),
                fixed: superAdmin ? {} : {'role': 'student'},
                fields: [
                  _AdminField(
                    'username',
                    t('username'),
                    required: true,
                    maxLength: 100,
                  ),
                  _AdminField(
                    'university_id',
                    t('university_id'),
                    required: true,
                    maxLength: 50,
                  ),
                  _AdminField('email', t('email'), email: true, maxLength: 100),
                  _AdminField(
                    'password',
                    t('password'),
                    secret: true,
                    required: true,
                    maxLength: 72,
                  ),
                  _AdminField(
                    'gender',
                    t('gender'),
                    kind: _FieldKind.select,
                    initial: 'Male',
                    options: {'Male': t('male'), 'Female': t('female')},
                    required: true,
                  ),
                  if (superAdmin) ...[
                    _AdminField(
                      'role',
                      t('role'),
                      kind: _FieldKind.select,
                      initial: 'student',
                      options: _roles(),
                      required: true,
                    ),
                    _AdminField(
                      'full_permissions',
                      t('full_permissions'),
                      kind: _FieldKind.checkbox,
                    ),
                    _AdminField(
                      'permissions',
                      t('permissions_label'),
                      kind: _FieldKind.multiple,
                      options: _permissions(),
                    ),
                    _AdminField(
                      'community_ids',
                      t('choose_communities'),
                      kind: _FieldKind.multiple,
                      options: _communities(),
                      required: true,
                      description: t('community_guidance'),
                      visible: (values) => values['role'] == 'community_admin',
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      }
      children.add(
        _AdminCard(
          child: _AdminTable(
            headers: [
              t('username'),
              t('university_id'),
              t('role'),
              t('email'),
              t('actions'),
            ],
            cells: [
              for (final user in records)
                [
                  Text(value(user['username'])),
                  Text(value(user['university_id'])),
                  _AdminBadge(t('roles.${user['role']}')),
                  Text(
                    value(user['email']).isEmpty ? '—' : value(user['email']),
                  ),
                  _AdminButton(
                    label: t('manage'),
                    secondary: true,
                    onPressed: () => p.load(
                      '/admin?section=$section&search=${Uri.encodeQueryComponent(value(user['university_id']))}',
                    ),
                  ),
                ],
            ],
            empty: t('empty'),
          ),
        ),
      );
    } else if (section == 'communities') {
      if (superAdmin) {
        children.addAll([
          _h3(t('community_information')),
          _paragraph(t('community_information_hint'), context, muted: true),
          for (final community in rows(d['communities']))
            _AdminExpansion(
              title: value(community['name']),
              summary: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: networkImage(
                      _communityImage(p, community),
                      width: 60,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 60, height: 36),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value(community['name']),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t('edit_community'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              children: [_AdminCommunityEditor(page: p, community: community)],
            ),
        ]);
        children.add(
          _AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _h3(t('community_question_settings')),
                _paragraph(
                  t('community_question_guidance'),
                  context,
                  muted: true,
                ),
                _AdminForm(
                  page: p,
                  path: '/admin/community-question-settings',
                  submit: t('community_question_save'),
                  fields: [
                    _AdminField(
                      'require_approval',
                      t('community_question_publishing'),
                      kind: _FieldKind.select,
                      initial: yes(d['communityQuestionsRequireApproval'])
                          ? '1'
                          : '0',
                      options: {
                        '1': t('community_question_require_approval'),
                        '0': t('community_question_publish_directly'),
                      },
                      required: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      children.add(
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h3(t('create_community')),
              _AdminForm(
                page: p,
                path: '/admin/communities',
                submit: t('create'),
                fields: [
                  _AdminField(
                    'name',
                    t('name'),
                    required: true,
                    maxLength: 100,
                  ),
                  _AdminField(
                    'description',
                    t('description'),
                    lines: 3,
                    maxLength: 2000,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      children.add(
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h3(t('assign_community')),
              _AdminForm(
                page: p,
                path: '/admin/assignments',
                submit: t('assign'),
                fixed: {'type': 'community'},
                fields: [
                  _AdminField(
                    'university_id',
                    t('university_id'),
                    required: true,
                  ),
                  _AdminField(
                    'community_ids',
                    t('choose_communities'),
                    kind: _FieldKind.multiple,
                    required: true,
                    options: _communities(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      children.add(
        _AdminExpansion(
          title: t('current_assignments'),
          children: [
            _AdminTable(
              headers: [
                t('username'),
                t('university_id'),
                t('name'),
                t('actions'),
              ],
              cells: [
                for (final assignment in rows(d['communityAssignments']))
                  [
                    Text(value(assignment['username'])),
                    Text(value(assignment['university_id'])),
                    Text(value(assignment['community_name'])),
                    _AdminForm(
                      page: p,
                      path: '/admin/assignments',
                      method: 'DELETE',
                      submit: t('remove'),
                      secondary: true,
                      fields: const [],
                      fixed: {'type': 'community', 'id': assignment['id']},
                    ),
                  ],
              ],
              empty: t('empty'),
            ),
          ],
        ),
      );
      if (d['assignmentPagination'] != null) {
        children.add(p.pagination(d['assignmentPagination']));
      }
      children.addAll(_records(context, records, section));
    } else if (section == 'events') {
      children.add(
        _AdminExpansion(
          title: t('create_event'),
          children: [
            _AdminForm(
              page: p,
              path: '/admin/events',
              submit: t('create_event'),
              fields: [
                _AdminField('title', t('name'), required: true, maxLength: 255),
                _AdminField(
                  'arenas',
                  t('arenas'),
                  required: true,
                  maxLength: 255,
                ),
                _AdminField(
                  'event_date',
                  t('event_date'),
                  required: true,
                  kind: _FieldKind.date,
                ),
                _AdminField('image_url', t('image_url'), maxLength: 500),
                _AdminField('link_url', t('link_url'), maxLength: 500),
                _AdminField(
                  'details',
                  t('description'),
                  lines: 4,
                  maxLength: 5000,
                ),
              ],
            ),
          ],
        ),
      );
      children.addAll(_records(context, records, section));
    } else if ([
      'reports',
      'profile_reports',
      'ask_reports',
    ].contains(section)) {
      children.add(
        _AdminCard(
          child: _AdminReportFilter(page: p, section: section),
        ),
      );
      children.addAll([
        for (final report in records) _report(context, report, section),
      ]);
      if (records.isEmpty) children.add(_AdminCard(child: Text(t('empty'))));
    } else if (section == 'suggestions') {
      children.addAll(_records(context, records, section));
    } else if (section == 'login_logs') {
      children.addAll(_loginLogs(context));
    }
    if (d['records'] != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: p.pagination(d['records']),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: p.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 112),
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String title,
    bool active,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: active ? page.c.settings.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: AnimatedDefaultTextStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          style: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            fontFamilyFallback: Theme.of(
              context,
            ).textTheme.bodyMedium?.fontFamilyFallback,
            fontSize: 14,
            color: active
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          child: Text(title),
        ),
      ),
    ),
  );
  Map<String, String> _roles() => {
    for (final role in ['student', 'community_admin', 'admin', 'super_admin'])
      role: t('roles.$role'),
  };
  Map<String, String> _permissions() => object(
    page.data['permissionCatalog'],
  ).map((key, label) => MapEntry(key, value(label)));
  Map<String, String> _communities() => {
    for (final community in rows(page.data['communities']))
      '${community['id']}': value(community['name']),
  };
  Widget _selectedUser(BuildContext context, Json user) {
    final p = page, c = p.c;
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _h3('${t('edit_user')} · ${user['username']}'),
          if (c.permission('users.manage')) ...[
            _AdminForm(
              page: p,
              path: '/admin/users/${user['id']}',
              method: 'PUT',
              submit: t('save_user'),
              fields: [
                _AdminField(
                  'username',
                  t('username'),
                  required: true,
                  initial: user['username'],
                  maxLength: 100,
                ),
                _AdminField(
                  'university_id',
                  t('university_id'),
                  required: true,
                  initial: user['university_id'],
                  maxLength: 50,
                ),
                _AdminField(
                  'email',
                  t('email'),
                  email: true,
                  initial: user['email'],
                  maxLength: 100,
                ),
                _AdminField(
                  'password',
                  t('password_optional'),
                  secret: true,
                  maxLength: 72,
                ),
                _AdminField(
                  'gender',
                  t('gender'),
                  kind: _FieldKind.select,
                  initial: user['gender'] ?? '',
                  options: {'': '—', 'Male': t('male'), 'Female': t('female')},
                ),
                _AdminField(
                  'badge',
                  t('badge'),
                  kind: _FieldKind.select,
                  initial: '${user['badge'] ?? 0}',
                  required: true,
                  options: {
                    for (final id in ['0', '1', '2', '3']) id: t('badges.$id'),
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            _AdminExpansion(
              title: t('delete_user'),
              danger: true,
              plain: true,
              children: [
                _paragraph(t('delete_warning'), context),
                _AdminForm(
                  page: p,
                  path: '/admin/users/${user['id']}',
                  method: 'DELETE',
                  submit: '${t('delete_user')} · ${user['username']}',
                  danger: true,
                  fields: const [],
                ),
              ],
            ),
          ],
          if (c.user?['role'] == 'super_admin') ...[
            const _AdminDivider(),
            _h3(t('access')),
            _paragraph(t('access_guidance'), context, muted: true),
            _AdminForm(
              page: p,
              path: '/admin/users/${user['id']}/access',
              method: 'PUT',
              submit: t('save_access'),
              fields: [
                _AdminField(
                  'role',
                  t('role'),
                  kind: _FieldKind.select,
                  options: _roles(),
                  initial: user['role'],
                  required: true,
                ),
                _AdminField(
                  'full_permissions',
                  t('full_permissions'),
                  kind: _FieldKind.checkbox,
                ),
                _AdminField(
                  'permissions',
                  t('permissions_label'),
                  kind: _FieldKind.multiple,
                  initial: p.data['selectedPermissions'] ?? [],
                  options: _permissions(),
                ),
              ],
            ),
          ],
          if (user['role'] == 'community_admin' &&
              c.permission('communities.manage') &&
              c.enabled('community')) ...[
            const _AdminDivider(),
            _h3(t('community_assignments')),
            _paragraph(t('community_guidance'), context, muted: true),
            _AdminForm(
              page: p,
              path: '/admin/users/${user['id']}/communities',
              submit: t('save_assignments'),
              fields: [
                _AdminField(
                  'community_ids',
                  t('choose_communities'),
                  kind: _FieldKind.multiple,
                  initial: rows(p.data['communityAssignments'])
                      .where((a) => '${a['user_id']}' == '${user['id']}')
                      .map((a) => '${a['community_id']}')
                      .toList(),
                  options: _communities(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _records(
    BuildContext context,
    List<Json> records,
    String section,
  ) => [
    for (final record in records)
      _AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _h3(
                    value(
                      record['title'] ?? record['username'],
                      '${t('record')} #${record['id']}',
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                _AdminBadge(value(record['status'], '#${record['id']}')),
              ],
            ),
            if (record['username'] != null)
              _paragraph(
                '${record['username']}${record['university_id'] != null ? ' · ${record['university_id']}' : ''}',
                context,
                muted: true,
              ),
            if (record['community_name'] != null)
              _paragraph(value(record['community_name']), context),
            for (final key in [
              'content',
              'suggestion',
              'description',
              'details',
            ])
              if (value(record[key]).isNotEmpty)
                _paragraph(value(record[key]), context),
            if (section == 'communities')
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminForm(
                    page: page,
                    path: '/admin/questions/${record['id']}',
                    submit: t('approve'),
                    fixed: {'status': 'approved'},
                    fields: const [],
                  ),
                  _AdminForm(
                    page: page,
                    path: '/admin/questions/${record['id']}',
                    submit: t('delete'),
                    danger: true,
                    fixed: {'status': 'deleted'},
                    fields: const [],
                  ),
                ],
              ),
            if (section == 'events') ...[
              _paragraph(
                '${record['event_date']} · ${record['arenas']}',
                context,
              ),
              if (value(record['link_url']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => page.external(value(record['link_url'])),
                    child: Text(
                      t('link_url'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              _AdminForm(
                page: page,
                path: '/admin/events/${record['id']}',
                method: 'DELETE',
                submit: t('delete'),
                danger: true,
                fields: const [],
              ),
            ],
          ],
        ),
      ),
    if (records.isEmpty) _AdminEmpty(t('empty')),
  ];
  Widget _report(BuildContext context, Json report, String section) {
    final post = section == 'reports', profile = section == 'profile_reports';
    final endpoint = post
        ? '/admin/post-reports/${report['id']}'
        : profile
        ? '/admin/profile-reports/${report['id']}'
        : '/admin/ask-reports/${report['id']}';
    final title = post
        ? report['reported_comment_id'] != null
              ? t('report_comment_number', {
                  'id': report['reported_comment_id'],
                  'post': report['reported_post_id'],
                })
              : t('report_post_number', {'id': report['reported_post_id']})
        : profile
        ? '${report['profile_name']} · #${report['reported_user_id']}'
        : '${page.c.t('Question', 'السؤال')} #${report['ask_question_id']}';
    return _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _h3(title)),
              const SizedBox(width: 20),
              _AdminBadge(t('report_states.${report['status']}')),
            ],
          ),
          _paragraph(
            '${post ? '${value(report['author_name'])} · ' : ''}${t('reported_by')} ${value(report['reporter_name'])}${section == 'ask_reports' ? ' · ${page.c.t('From', 'من')} ${value(report['sender_name'])}' : ''}',
            context,
          ),
          Text(
            _dateTime(report['created_at']),
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (section == 'ask_reports')
            _paragraph(value(report['question_snapshot']), context),
          _paragraph(value(report['reason'], t('no_report_reason')), context),
          if (post) ...[
            _paragraph(
              value(report['post_snapshot']).length > 240
                  ? '${value(report['post_snapshot']).substring(0, 240)}…'
                  : value(report['post_snapshot']),
              context,
              muted: true,
            ),
            _AdminButton(
              label: t(
                report['reported_comment_id'] != null
                    ? 'inspect_reported_comment'
                    : 'inspect_reported_post',
              ),
              secondary: true,
              onPressed: () => page.c.open('$endpoint/post'),
            ),
            const SizedBox(height: 18),
          ],
          if (profile) ...[
            if (report['profile_user_id'] != null)
              _AdminButton(
                label: t('inspect_reported_profile'),
                secondary: true,
                onPressed: () =>
                    page.c.open('/users/${report['profile_user_id']}'),
              )
            else
              _paragraph(t('report_profile_deleted'), context, muted: true),
            const SizedBox(height: 18),
          ],
          _AdminForm(
            page: page,
            path: endpoint,
            method: 'PATCH',
            submit: t('save'),
            fields: [
              _AdminField(
                'status',
                t('report_status'),
                kind: _FieldKind.select,
                initial: report['status'],
                required: true,
                options: {
                  for (final key in ['open', 'reviewed', 'resolved'])
                    key: t('report_states.$key'),
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _loginLogs(BuildContext context) {
    final p = page,
        d = p.data,
        selected = object(p.data['selectedUser']),
        colors = Theme.of(context).colorScheme;
    return [
      _AdminSearch(page: p, section: 'login_logs', login: true),
      if (selected.isNotEmpty)
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _h3(
                      '${t('login.selected_user')} · ${selected['username']}',
                    ),
                  ),
                  _AdminBadge('${rows(d['loginActivities']).length} / 7'),
                ],
              ),
              _paragraph(
                value(selected['university_id']),
                context,
                muted: true,
              ),
              _paragraph(t('login.admin_intro'), context, muted: true),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  t('login.device_notice'),
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              for (final activity in rows(d['loginActivities']))
                _AdminLoginCard(page: p, activity: activity),
              if (rows(d['loginActivities']).isEmpty) _AdminLoginEmpty(page: p),
            ],
          ),
        )
      else if (value(d['loginActivitySearch']).isNotEmpty)
        _AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rows(d['loginActivityUsers']).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    t('login.search_limit'),
                    style: TextStyle(
                      fontSize: 12.8,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final user in rows(d['loginActivityUsers']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => p.load(
                        '/admin?section=login_logs&search=${Uri.encodeQueryComponent(value(d['loginActivitySearch']))}&user_id=${user['id']}',
                      ),
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: WebIcon(
                                'user',
                                size: 20,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    value(user['username']),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    value(user['university_id']),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              t('login.select_user'),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            WebIcon(
                              'chevron-right',
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ] else
                _paragraph(t('login.search_empty'), context, muted: true),
            ],
          ),
        )
      else
        _AdminLoginEmpty(page: p, search: true),
    ];
  }
}

enum _FieldKind { text, select, checkbox, multiple, date }

class _AdminField {
  const _AdminField(
    this.name,
    this.label, {
    this.kind = _FieldKind.text,
    this.initial,
    this.description,
    this.required = false,
    this.maxLength,
    this.lines = 1,
    this.secret = false,
    this.email = false,
    this.options = const {},
    this.visible,
  });
  final String name, label;
  final _FieldKind kind;
  final dynamic initial;
  final String? description;
  final bool required, secret, email;
  final int? maxLength;
  final int lines;
  final Map<String, String> options;
  final bool Function(Json)? visible;
}

class _AdminForm extends StatefulWidget {
  const _AdminForm({
    required this.page,
    required this.path,
    required this.submit,
    required this.fields,
    this.method = 'POST',
    this.fixed = const {},
    this.secondary = false,
    this.danger = false,
  });
  final NativePageState page;
  final String path, method, submit;
  final List<_AdminField> fields;
  final Json fixed;
  final bool secondary, danger;
  @override
  State<_AdminForm> createState() => _AdminFormState();
}

class _AdminFormState extends State<_AdminForm> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final Json _values = {};
  Json _errors = {};
  String? _error, _status;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _values.clear();
    _errors = {};
    _error = null;
    _status = null;
    for (final field in widget.fields) {
      if (field.kind == _FieldKind.checkbox) {
        _values[field.name] = yes(field.initial);
      } else if (field.kind == _FieldKind.multiple) {
        _values[field.name] =
            (field.initial is List ? field.initial as List : const [])
                .map((v) => '$v')
                .toSet();
      } else {
        final initial =
            field.initial == null &&
                field.kind == _FieldKind.select &&
                field.options.isNotEmpty
            ? field.options.keys.first
            : value(field.initial);
        _values[field.name] = initial;
        _controllers[field.name] = TextEditingController(text: initial);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _AdminForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.fields.length != widget.fields.length ||
        !listEquals(
          oldWidget.fields.map((f) => '${f.name}:${f.initial}').toList(),
          widget.fields.map((f) => '${f.name}:${f.initial}').toList(),
        )) {
      _initialize();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _fieldError(String key) {
    final error = _errors[key];
    return error is List
        ? error.map((v) => '$v').join('\n')
        : error == null
        ? null
        : '$error';
  }

  String get _required =>
      widget.page.c.t('Please complete this field.', 'من فضلك أكمل هذا الحقل.');
  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final result = <String, dynamic>{...widget.fixed};
    for (final field in widget.fields) {
      if (!(field.visible?.call(_values) ?? true)) continue;
      dynamic current = _values[field.name];
      if (field.kind == _FieldKind.checkbox) {
        current = current == true ? 1 : 0;
      } else if (field.kind == _FieldKind.multiple) {
        current = (current as Set<String>).toList();
      } else {
        current = _controllers[field.name]?.text ?? current;
      }
      // Laravel expects the same nested structure as features[key] on the web.
      final parts = field.name.split('.');
      if (parts.length == 2) {
        final nested = object(result[parts.first]);
        nested[parts.last] = current;
        result[parts.first] = nested;
      } else {
        result[field.name] = current;
      }
    }
    setState(() {
      _busy = true;
      _errors = {};
      _error = null;
      _status = null;
    });
    try {
      final response = await widget.page.c.action(
        widget.method,
        widget.path,
        result,
      );
      if (!mounted) return;
      setState(
        () => _status = value(
          response['message'] ?? response['status'],
          adminCopy(widget.page, 'saved'),
        ),
      );
      // Re-fetch server-owned state; never synthesize successful moderation.
      await widget.page.load();
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errors = e.fields;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.page.c.t(
            'Unable to save. Please try again.',
            'تعذر الحفظ. حاول مرة أخرى.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.fields
        .where((f) => f.visible?.call(_values) ?? true)
        .toList();
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _field(context, field),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _AdminAlert(_error!, error: true),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _AdminAlert(_status!),
            ),
          _AdminButton(
            label: widget.submit,
            onPressed: _busy ? null : _save,
            busy: _busy,
            danger: widget.danger,
            secondary: widget.secondary,
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, _AdminField field) {
    if (field.kind == _FieldKind.checkbox) {
      return _AdminOption(
        label: field.label,
        description: field.description,
        selected: _values[field.name] == true,
        onChanged: _busy
            ? null
            : (v) => setState(() => _values[field.name] = v),
      );
    }
    if (field.kind == _FieldKind.multiple) {
      return FormField<Set<String>>(
        initialValue: Set<String>.from(_values[field.name]),
        validator: (_) => field.required && (_values[field.name] as Set).isEmpty
            ? _required
            : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AdminFieldset(
              label: field.label,
              children: [
                if (field.description != null)
                  _paragraph(field.description!, context, muted: true),
                for (final entry in field.options.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _AdminOption(
                      label: entry.value,
                      selected: (_values[field.name] as Set).contains(
                        entry.key,
                      ),
                      onChanged: _busy
                          ? null
                          : (v) {
                              setState(() {
                                final selected =
                                    _values[field.name] as Set<String>;
                                if (v) {
                                  selected.add(entry.key);
                                } else {
                                  selected.remove(entry.key);
                                }
                              });
                              state.didChange(
                                Set<String>.from(_values[field.name]),
                              );
                            },
                    ),
                  ),
              ],
            ),
            if (state.hasError || _fieldError(field.name) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorText ?? _fieldError(field.name)!,
                  style: const TextStyle(
                    color: Color(0xffb42335),
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final decoration = _inputDecoration(
      context,
      error: _fieldError(field.name),
    );
    final controller = _controllers[field.name]!;
    String? requiredValidator(String? input) =>
        field.required && (input?.trim().isEmpty ?? true)
        ? _required
        : field.secret && input != null && input.isNotEmpty && input.length < 8
        ? widget.page.c.t(
            'Use at least 8 characters.',
            'استخدم ٨ أحرف على الأقل.',
          )
        : null;
    Widget input;
    if (field.kind == _FieldKind.select) {
      final selected = value(_values[field.name]);
      input = AppDropdownButtonFormField<String>(
        key: ValueKey('${field.name}:$selected'),
        initialValue: field.options.containsKey(selected) ? selected : null,
        isExpanded: true,
        items: [
          for (final option in field.options.entries)
            DropdownMenuItem(
              value: option.key,
              child: Text(
                option.value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ],
        onChanged: _busy
            ? null
            : (v) => setState(() {
                _values[field.name] = v ?? '';
                controller.text = v ?? '';
              }),
        decoration: decoration,
        style: TextStyle(color: colors.onSurface, fontSize: 16),
        dropdownColor: colors.surface,
        validator: requiredValidator,
        icon: WebIcon('chevron-down', size: 16, color: colors.onSurfaceVariant),
      );
    } else {
      input = AdaptiveTextField(
        controller: controller,
        field: (direction) => TextFormField(
          controller: controller,
          textDirection: direction,
          readOnly: field.kind == _FieldKind.date,
          enabled: !_busy,
          obscureText: field.secret,
          autocorrect: !field.secret && !field.email,
          enableSuggestions: !field.secret,
          keyboardType: field.email
              ? TextInputType.emailAddress
              : field.lines > 1
              ? TextInputType.multiline
              : TextInputType.text,
          maxLength: field.maxLength,
          maxLines: field.secret ? 1 : field.lines,
          minLines: field.lines,
          style: TextStyle(
            fontSize: 16,
            color: colors.onSurface,
            fontWeight: FontWeight.w400,
          ),
          decoration: decoration.copyWith(
            counterText: '',
            suffixIcon: field.kind == _FieldKind.date
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : null,
          ),
          validator: requiredValidator,
          onChanged: (v) => _values[field.name] = v,
          onTap: field.kind != _FieldKind.date
              ? null
              : () async {
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(controller.text) ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2200),
                    locale: Locale(widget.page.c.settings.language),
                  );
                  if (chosen != null && mounted) {
                    setState(() {
                      controller.text = DateFormat('yyyy-MM-dd').format(chosen);
                      _values[field.name] = controller.text;
                    });
                  }
                },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        input,
        if (field.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              field.description!,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

InputDecoration _inputDecoration(
  BuildContext context, {
  String? hint,
  String? error,
}) {
  final colors = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    hintText: hint,
    hintStyle: TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    errorText: error,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.onSurface, width: 2),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xffb42335)),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xffb42335), width: 2),
    ),
  );
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: colors.onSurface, fontSize: 12),
      ),
    );
  }
}

Widget _h3(String label) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(
    label,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
  ),
);
Widget _paragraph(String label, BuildContext context, {bool muted = false}) =>
    Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          height: 1.65,
          color: muted
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

class _AdminButton extends StatelessWidget {
  const _AdminButton({
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.danger = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary, danger, busy;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = danger
        ? const Color(0xffb42335)
        : secondary
        ? colors.surface
        : colors.primary;
    final foreground = danger || !secondary ? Colors.white : colors.onSurface;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: secondary ? colors.outlineVariant : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminOption extends StatelessWidget {
  const _AdminOption({
    required this.label,
    required this.selected,
    required this.onChanged,
    this.description,
  });
  final String label;
  final String? description;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      enabled: onChanged != null,
      label: label,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 17,
                  height: 17,
                  child: Checkbox(
                    value: selected,
                    onChanged: onChanged == null
                        ? null
                        : (v) => onChanged!(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: colors.onSurfaceVariant),
                    activeColor: colors.onSurface,
                    checkColor: Theme.of(context).scaffoldBackgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: description == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
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
    );
  }
}

class _AdminFieldset extends StatelessWidget {
  const _AdminFieldset({required this.label, required this.children});
  final String label;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
        PositionedDirectional(
          start: 16,
          top: 0,
          child: Container(
            color: background,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminExpansion extends StatefulWidget {
  const _AdminExpansion({
    required this.title,
    required this.children,
    this.summary,
    this.danger = false,
    this.plain = false,
  });
  final String title;
  final Widget? summary;
  final List<Widget> children;
  final bool danger, plain;
  @override
  State<_AdminExpansion> createState() => _AdminExpansionState();
}

class _AdminExpansionState extends State<_AdminExpansion> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _open
                        ? Icons.arrow_drop_down
                        : Directionality.of(context) == TextDirection.rtl
                        ? Icons.arrow_left
                        : Icons.arrow_right,
                    size: 18,
                    color: widget.danger ? const Color(0xffd33b4e) : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        widget.summary ??
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: widget.danger
                                ? const Color(0xffd33b4e)
                                : null,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[const SizedBox(height: 18), ...widget.children],
      ],
    );
    return widget.plain ? body : _AdminCard(child: body);
  }
}

class _AdminDivider extends StatelessWidget {
  const _AdminDivider();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 24),
    padding: const EdgeInsets.only(top: 24),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
  );
}

class _AdminAlert extends StatelessWidget {
  const _AdminAlert(this.message, {this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: error
              ? const Color(0xffb42335)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(message, style: const TextStyle(fontSize: 14, height: 1.65)),
    ),
  );
}

class _AdminEmpty extends StatelessWidget {
  const _AdminEmpty(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    child: CustomPaint(
      painter: _DashedBorder(Theme.of(context).colorScheme.outlineVariant),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      );
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 8) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + 4, metric.length)),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder oldDelegate) =>
      oldDelegate.color != color;
}

class _AdminTable extends StatelessWidget {
  const _AdminTable({
    required this.headers,
    required this.cells,
    required this.empty,
  });
  final List<String> headers;
  final List<List<Widget>> cells;
  final String empty;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget cell(Widget child, {bool last = false}) => Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: 14,
          color: colors.onSurface,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback: Theme.of(
            context,
          ).textTheme.bodyMedium?.fontFamilyFallback,
        ),
        child: child,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  for (final header in headers)
                    cell(
                      Text(
                        header.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                          letterSpacing: .66,
                        ),
                      ),
                    ),
                ],
              ),
              if (cells.isEmpty)
                TableRow(
                  children: [
                    cell(Text(empty), last: true),
                    for (int i = 1; i < headers.length; i++)
                      cell(const SizedBox.shrink(), last: true),
                  ],
                )
              else
                for (int r = 0; r < cells.length; r++)
                  TableRow(
                    children: [
                      for (int col = 0; col < headers.length; col++)
                        cell(cells[r][col], last: r == cells.length - 1),
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSearch extends StatefulWidget {
  const _AdminSearch({
    required this.page,
    required this.section,
    this.login = false,
  });
  final NativePageState page;
  final String section;
  final bool login;
  @override
  State<_AdminSearch> createState() => _AdminSearchState();
}

class _AdminSearchState extends State<_AdminSearch> {
  late final TextEditingController _search = TextEditingController(
    text: Uri.parse(widget.page.path).queryParameters['search'] ?? '',
  );
  void _go() => widget.page.load(
    '/admin?section=${widget.section}&search=${Uri.encodeQueryComponent(_search.text.trim())}',
  );
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          adminCopy(
            widget.page,
            widget.login ? 'login.search_user' : 'search_user',
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: AdaptiveTextField(
                controller: _search,
                field: (direction) => TextField(
                  controller: _search,
                  textDirection: direction,
                  style: const TextStyle(fontSize: 16),
                  decoration: _inputDecoration(
                    context,
                    hint: adminCopy(
                      widget.page,
                      widget.login
                          ? 'login.search_placeholder'
                          : 'search_placeholder',
                    ),
                  ),
                  onSubmitted: (_) => _go(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _AdminButton(
              label: adminCopy(widget.page, 'search'),
              onPressed: _go,
            ),
          ],
        ),
      ],
    ),
  );
}

class _AdminReportFilter extends StatefulWidget {
  const _AdminReportFilter({required this.page, required this.section});
  final NativePageState page;
  final String section;
  @override
  State<_AdminReportFilter> createState() => _AdminReportFilterState();
}

class _AdminReportFilterState extends State<_AdminReportFilter> {
  late String _status =
      Uri.parse(widget.page.path).queryParameters['status'] ?? 'open';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        adminCopy(widget.page, 'report_status'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      AppDropdownButtonFormField<String>(
        initialValue: _status,
        isExpanded: true,
        decoration: _inputDecoration(context),
        items: [
          for (final status in ['open', 'reviewed', 'resolved', 'all'])
            DropdownMenuItem(
              value: status,
              child: Text(
                adminCopy(widget.page, 'report_states.$status'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
        ],
        onChanged: (v) => setState(() => _status = v ?? 'open'),
      ),
      const SizedBox(height: 10),
      _AdminButton(
        label: adminCopy(widget.page, 'filter'),
        onPressed: () => widget.page.load(
          '/admin?section=${widget.section}&status=$_status',
        ),
      ),
    ],
  );
}

String _communityImage(
  NativePageState page,
  Json community, {
  bool original = false,
}) {
  if (!original && value(community['image_url']).isNotEmpty) {
    return page.c.api.media(value(community['image_url']));
  }
  final file = value(community['image']);
  if (!original && RegExp(r'^u[A-Za-z0-9]{14}\.webp$').hasMatch(file)) {
    return page.c.api.media('/profile-media/$file');
  }
  final name = value(community['name']);
  return page.c.api.media(
    '/Picture/${name == 'ICPC'
        ? 'icpc_2018.webp'
        : name == 'Google'
        ? 'community_green_2.webp'
        : 'community_green_1.webp'}',
  );
}

class _AdminCommunityEditor extends StatefulWidget {
  const _AdminCommunityEditor({required this.page, required this.community});
  final NativePageState page;
  final Json community;
  @override
  State<_AdminCommunityEditor> createState() => _AdminCommunityEditorState();
}

class _AdminCommunityEditorState extends State<_AdminCommunityEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: value(widget.community['name']),
  );
  late final _description = TextEditingController(
    text: value(widget.community['description']),
  );
  Uint8List? _image;
  Uint8List? _source;
  bool _remove = false, _busy = false, _picking = false;
  String? _error, _status;
  String t(String key) => adminCopy(widget.page, key);
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    if (_picking || _busy) return;
    setState(() {
      _picking = true;
      _error = null;
      _status = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      if (await picked.length() > 5 * 1024 * 1024) {
        throw ApiFailure(t('community_image_size'));
      }
      final bytes = await picked.readAsBytes();
      await _crop(bytes);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = t('community_image_error'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _adjust() async {
    if (_picking || _busy) return;
    setState(() {
      _picking = true;
      _error = null;
      _status = null;
    });
    try {
      Uint8List? bytes = _source ?? _image;
      if (bytes == null) {
        final api = widget.page.c.api;
        final path = api.safePath(
          _communityImage(widget.page, widget.community),
        );
        final cancel = CancelToken();
        final response =
            await Dio(
              BaseOptions(connectTimeout: const Duration(seconds: 20)),
            ).get<List<int>>(
              api.baseUri.resolve(path).toString(),
              cancelToken: cancel,
              options: Options(
                responseType: ResponseType.bytes,
                followRedirects: false,
                validateStatus: (status) => status == 200,
                receiveTimeout: const Duration(seconds: 20),
              ),
              onReceiveProgress: (received, total) {
                if (received > 5 * 1024 * 1024 || total > 5 * 1024 * 1024) {
                  cancel.cancel('Image exceeds 5 MB.');
                }
              },
            );
        bytes = Uint8List.fromList(response.data ?? []);
      }
      if (bytes.length > 5 * 1024 * 1024) {
        throw ApiFailure(t('community_image_size'));
      }
      await _crop(bytes);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = t('community_image_error'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _crop(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 16000000) {
        throw ApiFailure(
          widget.page.c.t(
            'Choose an image up to 8192 pixels per side and 16 megapixels.',
            'اختار صورة لا تتجاوز ٨١٩٢ بكسل لكل جانب و١٦ ميجابكسل.',
          ),
        );
      }
      final codec = await descriptor.instantiateCodec();
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    if (!mounted) {
      image.dispose();
      return;
    }
    final cropped = await showDialog<Uint8List>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .55),
      builder: (_) => _CommunityCrop(page: widget.page, image: image!),
    );
    // The dialog keeps the decoded image alive through its exit transition.
    if (cropped != null && mounted) {
      setState(() {
        _source = bytes;
        _image = cropped;
        _remove = false;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_busy || _picking || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final payload = <String, dynamic>{
        'community_id': widget.community['id'],
        'name': _name.text,
        'description': _description.text,
        'remove_image': _remove ? 1 : 0,
        if (_image != null)
          'image_upload': MultipartFile.fromBytes(
            _image!,
            filename: 'community.png',
            contentType: DioMediaType('image', 'png'),
          ),
      };
      final response = await widget.page.c.action(
        'PUT',
        '/admin/communities/${widget.community['id']}',
        payload,
      );
      if (!mounted) return;
      setState(() {
        _status = value(response['message'] ?? response['status'], t('saved'));
        _image = null;
        _source = null;
        _remove = false;
      });
      await widget.page.load();
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = e.fields.isEmpty
              ? e.message
              : e.fields.values
                    .map((v) => v is List ? v.join('\n') : '$v')
                    .join('\n'),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = t('community_save_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage =
        !_remove &&
        (_image != null || value(widget.community['image']).isNotEmpty);
    Widget label(String title, Widget input) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        input,
      ],
    );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(
            t('name'),
            AdaptiveTextField(
              controller: _name,
              field: (direction) => TextFormField(
                controller: _name,
                textDirection: direction,
                enabled: !_busy,
                maxLength: 100,
                style: const TextStyle(fontSize: 16),
                decoration: _inputDecoration(context).copyWith(counterText: ''),
                validator: (v) => v?.trim().isNotEmpty == true
                    ? null
                    : widget.page.c.t(
                        'Please complete this field.',
                        'من فضلك أكمل هذا الحقل.',
                      ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          label(
            t('description'),
            AdaptiveTextField(
              controller: _description,
              field: (direction) => TextFormField(
                controller: _description,
                textDirection: direction,
                enabled: !_busy,
                maxLength: 2000,
                minLines: 3,
                maxLines: 3,
                style: const TextStyle(fontSize: 16),
                decoration: _inputDecoration(context).copyWith(counterText: ''),
              ),
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 5 / 3,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _image != null
                    ? Image.memory(
                        _image!,
                        fit: BoxFit.cover,
                        semanticLabel: t('community_image_preview'),
                      )
                    : networkImage(
                        _communityImage(
                          widget.page,
                          widget.community,
                          original: _remove,
                        ),
                        fit: BoxFit.cover,
                        semanticLabel: t('community_image_preview'),
                        errorBuilder: (_, _, _) =>
                            const Center(child: WebIcon('building', size: 40)),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          label(
            t('community_image'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AdminButton(
                    label: widget.page.c.t('Choose File', 'اختيار ملف'),
                    secondary: true,
                    onPressed: _picking || _busy ? null : _choose,
                    busy: _picking,
                  ),
                  Text(
                    _image != null
                        ? 'community.png'
                        : widget.page.c.t(
                            'No file chosen',
                            'لم يتم اختيار ملف',
                          ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          _paragraph(t('community_image_hint'), context, muted: true),
          if (hasImage)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AdminButton(
                  label: t('community_image_adjust'),
                  secondary: true,
                  onPressed: _picking || _busy ? null : _adjust,
                ),
                _AdminButton(
                  label: t('community_image_remove'),
                  secondary: true,
                  onPressed: _picking || _busy
                      ? null
                      : () => setState(() {
                          _remove = true;
                          _image = null;
                          _source = null;
                          _error = null;
                          _status = null;
                        }),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xffb42335),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          _AdminButton(
            label: t('save_community'),
            onPressed: _busy || _picking ? null : _save,
            busy: _busy,
          ),
        ],
      ),
    );
  }
}

class _CommunityCrop extends StatefulWidget {
  const _CommunityCrop({required this.page, required this.image});
  final NativePageState page;
  final ui.Image image;
  @override
  State<_CommunityCrop> createState() => _CommunityCropState();
}

class _CommunityCropState extends State<_CommunityCrop> {
  double _zoom = 1;
  Offset _offset = Offset.zero;
  Size _frame = Size.zero;
  bool _busy = false;
  String? _error;
  String t(String key) => adminCopy(widget.page, key);
  double get _scale =>
      math.max(
        _frame.width / widget.image.width,
        _frame.height / widget.image.height,
      ) *
      _zoom;
  Offset _clamp(Offset position) {
    final x = math.max(0.0, (widget.image.width * _scale - _frame.width) / 2);
    final y = math.max(0.0, (widget.image.height * _scale - _frame.height) / 2);
    return Offset(position.dx.clamp(-x, x), position.dy.clamp(-y, y));
  }

  Future<void> _apply() async {
    if (_busy || _frame.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imageSize = Size(
        widget.image.width.toDouble(),
        widget.image.height.toDouble(),
      );
      final topLeft =
          (_frame.center(Offset.zero) -
              imageSize.center(Offset.zero) * _scale) +
          _offset;
      final source = Rect.fromLTWH(
        -topLeft.dx / _scale,
        -topLeft.dy / _scale,
        _frame.width / _scale,
        _frame.height / _scale,
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        widget.image,
        source,
        const Rect.fromLTWH(0, 0, 1200, 720),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final result = await picture.toImage(1200, 720);
      picture.dispose();
      final png = await result.toByteData(format: ui.ImageByteFormat.png);
      result.dispose();
      if (png == null) throw StateError('Unable to encode image.');
      if (mounted) Navigator.of(context).pop(png.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t('community_image_error');
        });
      }
    }
  }

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height - 24,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('community_crop_title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _paragraph(t('community_crop_help'), context, muted: true),
              LayoutBuilder(
                builder: (context, constraints) {
                  _frame = Size(
                    constraints.maxWidth,
                    constraints.maxWidth * 3 / 5,
                  );
                  _offset = _clamp(_offset);
                  return Semantics(
                    label: t('community_crop_help'),
                    child: GestureDetector(
                      onPanUpdate: _busy
                          ? null
                          : (details) => setState(
                              () => _offset = _clamp(_offset + details.delta),
                            ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CustomPaint(
                          size: _frame,
                          painter: _CommunityCropPainter(
                            image: widget.image,
                            scale: _scale,
                            offset: _offset,
                            background: Theme.of(
                              context,
                            ).scaffoldBackgroundColor,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('community_crop_zoom'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Slider(
                      value: _zoom,
                      min: 1,
                      max: 4,
                      divisions: 300,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _zoom = v;
                              _offset = _clamp(_offset);
                            }),
                      semanticFormatterCallback: (v) =>
                          '${v.toStringAsFixed(2)}×',
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xffb42335)),
                  ),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminButton(
                    label: t('community_crop_reset'),
                    secondary: true,
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _zoom = 1;
                            _offset = Offset.zero;
                          }),
                  ),
                  _AdminButton(
                    label: widget.page.c.t('Cancel', 'إلغاء'),
                    secondary: true,
                    onPressed: _busy ? null : () => Navigator.pop(context),
                  ),
                  _AdminButton(
                    label: t('community_crop_apply'),
                    busy: _busy,
                    onPressed: _busy ? null : _apply,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityCropPainter extends CustomPainter {
  const _CommunityCropPainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.background,
  });
  final ui.Image image;
  final double scale;
  final Offset offset;
  final Color background;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(background, BlendMode.src);
    final dimensions = Size(image.width * scale, image.height * scale);
    final destination = Rect.fromLTWH(
      (size.width - dimensions.width) / 2 + offset.dx,
      (size.height - dimensions.height) / 2 + offset.dy,
      dimensions.width,
      dimensions.height,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _CommunityCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.scale != scale ||
      oldDelegate.offset != offset ||
      oldDelegate.background != background;
}

String _dateTime(dynamic input) {
  final date = DateTime.tryParse(value(input));
  return date == null
      ? value(input)
      : DateFormat('yyyy-MM-dd HH:mm').format(date.toUtc());
}

class _AdminLoginCard extends StatelessWidget {
  const _AdminLoginCard({required this.page, required this.activity});
  final NativePageState page;
  final Json activity;
  String t(String key) => adminCopy(page, 'login.$key');
  String _relative(DateTime? date) {
    if (date == null) return '';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inSeconds < 60) {
      return page.c.t('a few seconds ago', 'منذ بضع ثوانٍ');
    }
    final n = elapsed.inDays > 0
        ? elapsed.inDays
        : elapsed.inHours > 0
        ? elapsed.inHours
        : elapsed.inMinutes;
    if (elapsed.inDays > 0) {
      return page.c.t(
        '$n ${n == 1 ? 'day' : 'days'} ago',
        'منذ $n ${n == 1 ? 'يوم' : 'أيام'}',
      );
    }
    if (elapsed.inHours > 0) {
      return page.c.t(
        '$n ${n == 1 ? 'hour' : 'hours'} ago',
        'منذ $n ${n == 1 ? 'ساعة' : 'ساعات'}',
      );
    }
    return page.c.t(
      '$n ${n == 1 ? 'minute' : 'minutes'} ago',
      'منذ $n ${n == 1 ? 'دقيقة' : 'دقائق'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final device =
        [
          'phone',
          'tablet',
          'laptop',
          'computer',
        ].contains(activity['device_type'])
        ? value(activity['device_type'])
        : 'unknown';
    final at = DateTime.tryParse(value(activity['logged_in_at']));
    Widget detail(String title, String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11.68,
            height: 1.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(text, style: const TextStyle(fontSize: 13.6, height: 1.6)),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: WebIcon(
              device == 'computer' || device == 'unknown' ? 'monitor' : device,
              size: 22,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 10,
                  runSpacing: 3,
                  children: [
                    Text(
                      t('devices.$device'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    Text(
                      _relative(at),
                      style: TextStyle(
                        fontSize: 12.16,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final oneColumn = MediaQuery.sizeOf(context).width <= 380;
                    final width = oneColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          child: detail(
                            t('browser'),
                            '${value(activity['browser_name'], t('unknown_browser'))}${value(activity['browser_version']).isEmpty ? '' : ' ${activity['browser_version']}'}',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: detail(
                            t('operating_system'),
                            value(activity['os_name'], t('unknown_os')),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: detail(
                            t('signed_in_at'),
                            at == null
                                ? value(activity['logged_in_at'])
                                : '${DateFormat('d MMM yyyy, HH:mm:ss', page.c.settings.language).format(at.toUtc())} UTC',
                          ),
                        ),
                        if (value(activity['ip_address']).isNotEmpty)
                          SizedBox(
                            width: width,
                            child: detail(
                              t('ip_address'),
                              value(activity['ip_address']),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String adminCopy(NativePageState page, String key, [Json args = const {}]) {
  String result =
      (page.c.settings.language == 'ar' ? _adminArabic : _adminEnglish)[key] ??
      _adminEnglish[key] ??
      key;
  for (final entry in args.entries) {
    result = result.replaceAll(':${entry.key}', value(entry.value));
  }
  return result;
}

const _adminEnglish = <String, String>{
  "community_information": "Community information",
  "community_information_hint":
      "View every community and edit its name, description, or image. Only the Super Admin can save these changes.",
  "edit_community": "Edit details",
  "save_community": "Save community",
  "community_image": "Community image",
  "community_image_preview": "Community image preview",
  "community_image_hint":
      "JPEG, PNG, or WebP, up to 5 MB. Crop the image to fit the community card; the banner shows the center of the same image.",
  "community_image_adjust": "Adjust crop",
  "community_image_remove": "Remove image",
  "community_crop_title": "Crop community image",
  "community_crop_help":
      "Drag to position the image, then zoom to fit the frame. You can also use the arrow keys to move it.",
  "community_crop_zoom": "Zoom",
  "community_crop_reset": "Reset crop",
  "community_crop_apply": "Use image",
  "community_image_error":
      "The image could not be opened. Choose a valid JPEG, PNG, or WebP image.",
  "community_image_size": "Choose an image smaller than 5 MB.",
  "community_save_error": "The community could not be saved. Please try again.",
  "announcement_permissions": "Announcement permissions",
  "announcement_permission_guidance":
      "Grant or remove permission to publish announcements. Only the Super Admin can authorize an admin to grant this permission. Verified badges do not grant posting access.",
  "announcement_posting": "Can publish announcements",
  "announcement_inherited": "Included with Super Admin access",
  "inspect_reported_profile": "Open reported profile",
  "report_profile_deleted":
      "This profile was deleted; the report remains available.",
  "report_comment_number": "Reported comment #:id · Post #:post",
  "inspect_reported_comment": "Inspect reported comment",
  "current_comment": "Current reported comment",
  "report_comment_deleted":
      "The comment was deleted. Its report snapshot is retained.",
  "save": "Save status",
  "report_updated": "Report status updated.",
  "report_status": "Report status",
  "filter": "Filter",
  "report_post_number": "Reported post #:id",
  "reported_by": "Reported by",
  "no_report_reason": "No reason provided.",
  "inspect_reported_post": "Inspect original post",
  "report_reason": "Report reason",
  "report_snapshot": "Content when reported",
  "current_post": "Current post",
  "report_post_deleted":
      "The original post was deleted. The report snapshot is retained.",
  "report_states.open": "Open",
  "report_states.reviewed": "Reviewed",
  "report_states.resolved": "Resolved",
  "report_states.all": "All",
  "unknown_action": "Unknown admin action.",
  "saved": "Changes saved.",
  "community_question_settings": "Community question publishing",
  "community_question_guidance":
      "Only Super Admins can change this setting. It applies to new questions from all members in every community. Existing pending questions still need review. Community moderators can always publish directly.",
  "community_question_publishing": "Publishing mode",
  "community_question_require_approval": "Require Community Admin approval",
  "community_question_publish_directly": "Publish directly",
  "community_question_save": "Save publishing mode",
  "community_question_help_pending":
      "Your question will appear after a Community Admin approves it.",
  "community_question_help_direct":
      "Your question will be published immediately.",
  "last_super": "At least one Super Admin must remain.",
  "floor": "Floor",
  "area": "Area",
  "title": "Admin dashboard",
  "workspace": "Management workspace",
  "subtitle": "Manage people, review content, and control platform access.",
  "sections_label": "Dashboard sections",
  "records": "records",
  "open_section": "Open section",
  "feature_controls": "Platform features",
  "feature_guidance":
      "Uncheck a feature to hide it from navigation and block its routes for everyone, including super admins. Enable it again here to restore access.",
  "enabled": "Enabled",
  "disabled": "Disabled",
  "save_features": "Save features",
  "search_user": "Find a user",
  "search_placeholder": "University ID or username",
  "search": "Search",
  "edit_user": "Edit user",
  "username": "Username",
  "university_id": "University ID",
  "email": "Email",
  "password_optional": "New password (optional)",
  "gender": "Gender",
  "male": "Male",
  "female": "Female",
  "badge": "Badge",
  "save_user": "Save user",
  "delete_user": "Delete user",
  "delete_warning":
      "Deleting this account permanently removes the user and their associated data.",
  "access": "Role and permissions",
  "access_guidance":
      "Only super admins can change roles and permissions. Scoped permissions apply to the Admin role; Super Admin grants full access.",
  "role": "Role",
  "full_permissions": "Grant every admin permission",
  "permissions_label": "Admin permissions",
  "save_access": "Save access",
  "community_assignments": "Moderated communities",
  "community_guidance":
      "Choose which communities this moderator may review. This does not restrict anyone from browsing or participating.",
  "choose_communities": "Communities to moderate",
  "save_assignments": "Save moderation access",
  "no_exact_user":
      "No exact user match. The list below shows matching records.",
  "create_user": "Create user",
  "password": "Password",
  "create_community": "Create community",
  "name": "Name",
  "description": "Description",
  "create": "Create",
  "assign_community": "Assign a community moderator",
  "assign": "Assign",
  "current_assignments": "Current moderation assignments",
  "actions": "Actions",
  "remove": "Remove",
  "empty": "No records to display.",
  "create_event": "Create event",
  "arenas": "Venue / arenas",
  "event_date": "Event date",
  "image_url": "Image URL",
  "link_url": "Event link",
  "manage": "Manage",
  "record": "Record",
  "approve": "Approve",
  "reject": "Reject",
  "delete": "Delete",
  "sections.reports": "Reported posts & comments",
  "sections.profile_reports": "Reported profiles",
  "sections.overview": "Overview",
  "sections.features": "Features",
  "sections.admins": "Admins",
  "sections.users": "Users",
  "sections.communities": "Communities",
  "sections.events": "Events",
  "sections.suggestions": "Suggestions",
  "roles.student": "Student",
  "roles.community_admin": "Community Moderator",
  "roles.admin": "Admin",
  "roles.super_admin": "Super Admin",
  "roles.uni_admin": "University Admin",
  "features.hall": "Hall of Fame",
  "features.announcements": "Announcements",
  "features.ai": "Tamer Elgayar",
  "features.community": "Community",
  "features.suggestions": "Suggestions",
  "permissions.announcement_grants": "Grant announcement posting permission",
  "permissions.reports": "Review reports",
  "permissions.users": "Manage users",
  "permissions.communities": "Manage communities",
  "permissions.announcements": "Manage announcements",
  "permissions.events": "Manage events",
  "permissions.suggestions": "Review suggestions",
  "permissions.features": "Control features",
  "badges.0": "None",
  "badges.1": "Verified",
  "badges.2": "Professor",
  "badges.3": "Special",
  "login.title": "Login activity",
  "login.admin_title": "Login logs",
  "login.menu_description": "See when and where you signed in.",
  "login.intro": "Your latest seven successful sign-ins, newest first.",
  "login.admin_intro":
      "The selected account’s latest seven successful sign-ins, newest first.",
  "login.search_user": "Find an account",
  "login.search_placeholder":
      "Username or university ID (at least 2 characters)",
  "login.select_user": "View login logs",
  "login.search_hint":
      "Search for an account, then select it to view its latest seven sign-ins.",
  "login.search_empty": "No matching accounts found.",
  "login.search_limit":
      "Up to 10 matches are shown. Refine your search if needed.",
  "login.selected_user": "Selected account",
  "login.device_notice": "Device details are reported by your browser.",
  "login.back_to_menu": "Back to settings",
  "login.account": "Account",
  "login.browser": "Browser",
  "login.operating_system": "Operating system",
  "login.signed_in_at": "Signed in at",
  "login.ip_address": "IP address",
  "login.unknown_account": "Unknown account",
  "login.unknown_browser": "Unknown browser",
  "login.unknown_os": "Unknown operating system",
  "login.empty_title": "No sign-ins yet",
  "login.empty_description": "New sign-ins will appear here.",
  "login.devices.phone": "Phone",
  "login.devices.tablet": "Tablet",
  "login.devices.laptop": "Laptop",
  "login.devices.computer": "Computer",
  "login.devices.unknown": "Unknown device",
};

const _adminArabic = <String, String>{
  "community_information": "معلومات المجتمعات",
  "community_information_hint":
      "اعرض كل المجتمعات وعدّل الاسم والوصف والصورة. السوبر أدمن فقط يقدر يحفظ التغييرات دي.",
  "edit_community": "تعديل البيانات",
  "save_community": "حفظ المجتمع",
  "community_image": "صورة المجتمع",
  "community_image_preview": "معاينة صورة المجتمع",
  "community_image_hint":
      "صورة JPEG أو PNG أو WebP، بحد أقصى 5 ميجابايت. قصّ الصورة علشان تناسب بطاقة المجتمع؛ البانر بيعرض الجزء الأوسط من نفس الصورة.",
  "community_image_adjust": "تعديل القصّ",
  "community_image_remove": "إزالة الصورة",
  "community_crop_title": "قصّ صورة المجتمع",
  "community_crop_help":
      "اسحب الصورة لتحديد مكانها، وعدّل التكبير علشان تناسب الإطار. تقدر كمان تستخدم أسهم لوحة المفاتيح لتحريكها.",
  "community_crop_zoom": "التكبير",
  "community_crop_reset": "إعادة ضبط القصّ",
  "community_crop_apply": "استخدام الصورة",
  "community_image_error":
      "معرفناش نفتح الصورة. اختار صورة JPEG أو PNG أو WebP سليمة.",
  "community_image_size": "اختار صورة حجمها أقل من 5 ميجابايت.",
  "community_save_error": "معرفناش نحفظ المجتمع. جرّب تاني.",
  "announcement_permissions": "صلاحيات نشر الإعلانات",
  "announcement_permission_guidance":
      "امنح أو ألغِ صلاحية نشر الإعلانات. السوبر أدمن فقط يقدر يفوّض أدمن لمنح الصلاحية دي. علامات التوثيق مش بتمنح صلاحية النشر.",
  "announcement_posting": "يقدر ينشر إعلانات",
  "announcement_inherited": "متاحة للسوبر أدمن",
  "inspect_reported_profile": "فتح الملف الشخصي المبلغ عنه",
  "report_profile_deleted": "تم حذف الملف الشخصي، والبلاغ ما زال محفوظًا.",
  "report_comment_number": "التعليق المبلغ عنه #:id · المنشور #:post",
  "inspect_reported_comment": "فحص التعليق المبلغ عنه",
  "current_comment": "التعليق المبلغ عنه حاليًا",
  "report_comment_deleted": "التعليق اتحذف. محتواه وقت البلاغ لسه محفوظ.",
  "save": "حفظ الحالة",
  "report_updated": "تم تحديث حالة البلاغ.",
  "report_status": "حالة البلاغ",
  "filter": "تصفية",
  "report_post_number": "المنشور المبلغ عنه #:id",
  "reported_by": "أبلغ عنه",
  "no_report_reason": "لم يُذكر سبب.",
  "inspect_reported_post": "فحص المنشور الأصلي",
  "report_reason": "سبب البلاغ",
  "report_snapshot": "المحتوى وقت البلاغ",
  "current_post": "المنشور الحالي",
  "report_post_deleted": "تم حذف المنشور الأصلي. محتوى البلاغ محفوظ.",
  "report_states.open": "جديد",
  "report_states.reviewed": "تمت المراجعة",
  "report_states.resolved": "تم الحل",
  "report_states.all": "الكل",
  "unknown_action": "إجراء إداري غير معروف.",
  "saved": "تم حفظ التغييرات.",
  "community_question_settings": "نشر أسئلة المجتمعات",
  "community_question_guidance":
      "المدير العام فقط يمكنه تغيير هذا الإعداد. يسري على الأسئلة الجديدة لجميع الأعضاء في كل المجتمعات. الأسئلة المعلقة الحالية تظل بحاجة إلى المراجعة. مديرو المجتمعات يمكنهم النشر مباشرة دائمًا.",
  "community_question_publishing": "طريقة النشر",
  "community_question_require_approval": "تتطلب موافقة مدير المجتمع",
  "community_question_publish_directly": "النشر مباشرة",
  "community_question_save": "حفظ طريقة النشر",
  "community_question_help_pending":
      "سيظهر سؤالك بعد موافقة مدير المجتمع عليه.",
  "community_question_help_direct": "سيتم نشر سؤالك فورًا.",
  "last_super": "يجب الاحتفاظ بمشرف أعلى واحد على الأقل.",
  "floor": "الطابق",
  "area": "المساحة",
  "title": "لوحة الإدارة",
  "workspace": "مساحة الإدارة",
  "subtitle": "إدارة الحسابات ومراجعة المحتوى والتحكم في خدمات المنصة.",
  "sections_label": "أقسام لوحة الإدارة",
  "records": "سجلات",
  "open_section": "فتح القسم",
  "feature_controls": "خدمات المنصة",
  "feature_guidance":
      "ألغِ تحديد الخدمة لإخفائها من التنقل وإيقاف الوصول إليها للجميع، بما في ذلك المدير العام. يمكنك تفعيلها مجددًا هنا.",
  "enabled": "مفعّل",
  "disabled": "متوقف",
  "save_features": "حفظ الخدمات",
  "search_user": "البحث عن مستخدم",
  "search_placeholder": "الرقم الجامعي أو اسم المستخدم",
  "search": "بحث",
  "edit_user": "تعديل المستخدم",
  "username": "اسم المستخدم",
  "university_id": "الرقم الجامعي",
  "email": "البريد الإلكتروني",
  "password_optional": "كلمة مرور جديدة (اختياري)",
  "gender": "الجنس",
  "male": "ذكر",
  "female": "أنثى",
  "badge": "الشارة",
  "save_user": "حفظ المستخدم",
  "delete_user": "حذف المستخدم",
  "delete_warning": "حذف هذا الحساب يزيل المستخدم وبياناته المرتبطة نهائيًا.",
  "access": "الدور والصلاحيات",
  "access_guidance":
      "المدير العام فقط يستطيع تغيير الأدوار والصلاحيات. الصلاحيات المحددة تخص دور المدير؛ ودور المدير العام يمنح الوصول الكامل.",
  "role": "الدور",
  "full_permissions": "منح جميع صلاحيات الإدارة",
  "permissions_label": "صلاحيات الإدارة",
  "save_access": "حفظ الصلاحيات",
  "community_assignments": "المجتمعات التي يشرف عليها المستخدم",
  "community_guidance":
      "حدد المجتمعات التي يستطيع المشرف مراجعتها. يستطيع الجميع تصفح كل المجتمعات والمشاركة فيها.",
  "choose_communities": "مجتمعات الإشراف",
  "save_assignments": "حفظ صلاحيات الإشراف",
  "no_exact_user":
      "لم يتم العثور على مستخدم مطابق تمامًا. القائمة تعرض نتائج البحث.",
  "create_user": "إنشاء مستخدم",
  "password": "كلمة المرور",
  "create_community": "إنشاء مجتمع",
  "name": "الاسم",
  "description": "الوصف",
  "create": "إنشاء",
  "assign_community": "تعيين مشرف للمجتمعات",
  "assign": "تعيين",
  "current_assignments": "تعيينات الإشراف الحالية",
  "actions": "الإجراءات",
  "remove": "إزالة",
  "empty": "لا توجد سجلات للعرض.",
  "create_event": "إنشاء فعالية",
  "arenas": "المكان / الساحات",
  "event_date": "تاريخ الفعالية",
  "image_url": "رابط الصورة",
  "link_url": "رابط الفعالية",
  "manage": "إدارة",
  "record": "سجل",
  "approve": "قبول",
  "reject": "رفض",
  "delete": "حذف",
  "sections.reports": "البلاغات عن المنشورات والتعليقات",
  "sections.profile_reports": "بلاغات الملفات الشخصية",
  "sections.overview": "نظرة عامة",
  "sections.features": "الخدمات",
  "sections.admins": "المديرون",
  "sections.users": "المستخدمون",
  "sections.communities": "المجتمعات",
  "sections.events": "الفعاليات",
  "sections.suggestions": "الاقتراحات",
  "roles.student": "طالب",
  "roles.community_admin": "مشرف مجتمع",
  "roles.admin": "مدير",
  "roles.super_admin": "مدير عام",
  "roles.uni_admin": "مدير الجامعة",
  "features.hall": "لوحة الشرف",
  "features.announcements": "الإعلانات",
  "features.ai": "تامر الجيار",
  "features.community": "المجتمعات",
  "features.suggestions": "الاقتراحات",
  "permissions.announcement_grants": "منح صلاحية نشر الإعلانات",
  "permissions.reports": "مراجعة البلاغات",
  "permissions.users": "إدارة المستخدمين",
  "permissions.communities": "إدارة المجتمعات",
  "permissions.announcements": "إدارة الإعلانات",
  "permissions.events": "إدارة الفعاليات",
  "permissions.suggestions": "مراجعة الاقتراحات",
  "permissions.features": "التحكم في الخدمات",
  "badges.0": "بدون",
  "badges.1": "موثق",
  "badges.2": "أستاذ",
  "badges.3": "مميز",
  "login.title": "نشاط تسجيل الدخول",
  "login.admin_title": "سجل تسجيل الدخول",
  "login.menu_description": "شوف سجل دخولك والأجهزة اللي استخدمتها.",
  "login.intro": "آخر ٧ تسجيلات دخول ناجحة لحسابك، الأحدث الأول.",
  "login.admin_intro": "آخر ٧ تسجيلات دخول ناجحة للحساب المحدد، الأحدث الأول.",
  "login.search_user": "ابحث عن حساب",
  "login.search_placeholder": "اسم المستخدم أو الرقم الجامعي (حرفين على الأقل)",
  "login.select_user": "عرض سجل الدخول",
  "login.search_hint": "ابحث عن حساب واختاره عشان تشوف آخر ٧ تسجيلات دخول ليه.",
  "login.search_empty": "مفيش حسابات مطابقة للبحث.",
  "login.search_limit": "بنعرض لحد ١٠ نتائج. حدّد البحث أكتر لو محتاج.",
  "login.selected_user": "الحساب المحدد",
  "login.device_notice": "تفاصيل الجهاز حسب المعلومات اللي بيبعتها المتصفح.",
  "login.back_to_menu": "الرجوع للإعدادات",
  "login.account": "الحساب",
  "login.browser": "المتصفح",
  "login.operating_system": "نظام التشغيل",
  "login.signed_in_at": "وقت تسجيل الدخول",
  "login.ip_address": "عنوان IP",
  "login.unknown_account": "حساب غير معروف",
  "login.unknown_browser": "متصفح غير معروف",
  "login.unknown_os": "نظام تشغيل غير معروف",
  "login.empty_title": "مفيش تسجيلات دخول لسه",
  "login.empty_description": "تسجيلات الدخول الجديدة هتظهر هنا.",
  "login.devices.phone": "موبايل",
  "login.devices.tablet": "جهاز لوحي",
  "login.devices.laptop": "لابتوب",
  "login.devices.computer": "كمبيوتر",
  "login.devices.unknown": "جهاز غير معروف",
};

/// The report inspection page uses the admin document layout, including snapshots
/// that remain available after the original post or comment has been deleted.
class WebAdminReportDetail extends StatelessWidget {
  const WebAdminReportDetail({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final report = object(page.data['report']);
    final post = object(page.data['post']);
    final comment = object(page.data['reportedComment']);
    String t(String key, [Json args = const {}]) => adminCopy(page, key, args);
    Widget section(String title, List<Widget> children) => _AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          ...children,
        ],
      ),
    );
    return RefreshIndicator.adaptive(
      onRefresh: page.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 112),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _AdminButton(
              label: t('sections.reports'),
              secondary: true,
              onPressed: () => page.c.open('/admin?section=reports'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(
              report['reported_comment_id'] != null
                  ? t('report_comment_number', {
                      'id': report['reported_comment_id'],
                      'post': report['reported_post_id'],
                    })
                  : t('report_post_number', {'id': report['reported_post_id']}),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.04,
                height: 1.2,
              ),
            ),
          ),
          section(t('report_reason'), [
            _paragraph(value(report['reason'], t('no_report_reason')), context),
          ]),
          section(t('report_snapshot'), [
            _paragraph(value(report['author_name']), context),
            _paragraph(value(report['post_snapshot']), context),
          ]),
          if (report['reported_comment_id'] != null)
            section(t('current_comment'), [
              if (comment.isNotEmpty) ...[
                _paragraph(
                  value(object(comment['author'])['username']),
                  context,
                ),
                _paragraph(value(comment['content']), context),
              ] else
                _paragraph(t('report_comment_deleted'), context),
            ]),
          section(t('current_post'), [
            if (post.isNotEmpty) ...[
              _paragraph(value(object(post['author'])['username']), context),
              _paragraph(value(post['content']), context),
            ] else
              _paragraph(t('report_post_deleted'), context),
          ]),
          for (final item in rows(page.data['comments']))
            _AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _h3(value(object(item['author'])['username'])),
                  _paragraph(value(item['content']), context),
                ],
              ),
            ),
          if (post.isNotEmpty) page.pagination(page.data['comments']),
        ],
      ),
    );
  }
}

class _AdminLoginEmpty extends StatelessWidget {
  const _AdminLoginEmpty({required this.page, this.search = false});
  final NativePageState page;
  final bool search;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 18),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(bottom: 17),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: WebIcon(
              search ? 'user' : 'monitor',
              size: 29,
              color: colors.primary,
            ),
          ),
          if (!search)
            Text(
              adminCopy(page, 'login.empty_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              adminCopy(
                page,
                search ? 'login.search_hint' : 'login.empty_description',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.08,
                height: 1.7,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
