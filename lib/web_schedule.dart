import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_menus.dart';
import 'image_cache.dart';
import 'main.dart';
import 'native_glass.dart';
import 'screens.dart';
import 'text_direction.dart';

const _lectureBlue = Color(0xff3185c2);
const _sectionOrange = Color(0xffce8b46);

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dayName(DateTime date, bool ar, {bool short = false}) {
  const arabic = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  const english = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final name = (ar ? arabic : english)[date.weekday - 1];
  return !ar && short ? name.substring(0, 3) : name;
}

String _displayDate(DateTime date, bool ar) {
  const arabic = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  const english = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${date.day} ${(ar ? arabic : english)[date.month - 1]}';
}

String _time(String raw, AppController c) {
  final parts = raw.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  return '${hour % 12 == 0 ? 12 : hour % 12}:${parts.length > 1 ? parts[1] : '00'} ${hour >= 12 ? 'PM' : 'AM'}';
}

DateTime _serverNow(Json schedule, DateTime received) {
  final server = DateTime.tryParse(value(schedule['server_time']));
  return (server ?? received).add(DateTime.now().difference(received));
}

/// Uses the timetable's Cairo calendar date, including when the next class
/// belongs to a later day or the device uses a different timezone.
bool isScheduleDayOff(Json schedule) {
  final rawDate = value(
    schedule['date'],
    value(schedule['server_time']).split('T').first,
  );
  final date = DateTime.tryParse(rawDate);
  return date?.weekday == DateTime.friday ||
      date?.weekday == DateTime.saturday ||
      !rows(schedule['entries']).any(
        (entry) => entry['type'] == 'lecture' || entry['type'] == 'section',
      );
}

String _countdown(Json entry, DateTime now, AppController c) {
  final start = DateTime.tryParse(value(entry['starts_at']));
  if (start == null) return '';
  final minutes = start.difference(now).inSeconds;
  if (minutes <= 0) return c.t('Starting now', 'تبدأ الآن');
  final total = (minutes / 60).ceil();
  final hours = total ~/ 60, remaining = total % 60;
  if (hours == 0) return c.t('In $remaining min', 'بعد $remaining دقيقة');
  return c.t('In ${hours}h ${remaining}m', 'بعد $hours س و$remaining د');
}

String _remainingDuration(Json entry, DateTime now, AppController c) {
  final start = DateTime.tryParse(value(entry['starts_at']));
  if (start == null) return '';
  final minutes = (start.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0) return c.t('Now', 'الآن');
  if (minutes < 60) return c.t('${minutes}m', '$minutes د');
  return c.t(
    '${minutes ~/ 60}h ${minutes % 60}m',
    '${minutes ~/ 60} س ${minutes % 60} د',
  );
}

class WebSchedule extends StatefulWidget {
  const WebSchedule({super.key, required this.page});
  final NativePageState page;

  @override
  State<WebSchedule> createState() => _WebScheduleState();
}

class _WebScheduleState extends State<WebSchedule> {
  /// Days already fetched, shared across visits for two minutes so moving
  /// between days (and coming back) does not wait for the server.
  static final Map<String, ({DateTime at, Json schedule})> _days = {};
  static const _dayLifetime = Duration(minutes: 2);

  late DateTime _received = DateTime.now();
  Timer? _clock;
  Json? _freshSchedule;
  String? _path;
  String? _pendingDate;
  int _direction = 0;
  int _switch = 0;
  bool _refreshing = false;
  Json get schedule => _freshSchedule ?? object(widget.page.data['schedule']);
  NativePageState get p => widget.page;
  String get _currentPath => _path ?? p.path;
  bool get ar => p.c.settings.language == 'ar';
  DateTime get selected =>
      DateTime.tryParse(value(schedule['date'])) ?? DateTime.now();

  String _cacheKey(String path) =>
      '${identityHashCode(p.c)}|${p.c.sessionGeneration}|${p.c.cacheGeneration}|$path';

  Future<({DateTime at, Json schedule})?> _fetchDay(
    String path, {
    bool fresh = false,
  }) async {
    final key = _cacheKey(path), cached = _days[key];
    if (!fresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _dayLifetime) {
      return cached;
    }
    final response = await p.c.fetchPage(path);
    final day = object(object(response['data'])['schedule']);
    if (response['screen'] != 'schedule.index' || day.isEmpty) return null;
    _days.removeWhere(
      (_, value) => DateTime.now().difference(value.at) >= _dayLifetime,
    );
    return _days[key] = (at: DateTime.now(), schedule: day);
  }

  void _prefetchNeighbours() {
    final days = rows(schedule['days']);
    final index = days.indexWhere(
      (d) => value(d['date']) == value(schedule['date']),
    );
    Future<void>(() async {
      for (final offset in [-1, 1]) {
        final i = index + offset;
        if (index < 0 || i < 0 || i >= days.length || !mounted) continue;
        try {
          await _fetchDay(_pathFor(DateTime.parse(value(days[i]['date']))));
        } catch (_) {}
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      _refresh();
    });
  }

  Future<void> _refresh() async {
    if (!mounted ||
        _refreshing ||
        p.loading ||
        !identical(p.c.activePage, p) ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    final path = _currentPath, generation = p.c.sessionGeneration;
    _refreshing = true;
    try {
      final fresh = await _fetchDay(path, fresh: true);
      if (!mounted ||
          path != _currentPath ||
          generation != p.c.sessionGeneration) {
        return;
      }
      if (fresh != null) {
        setState(() {
          _freshSchedule = fresh.schedule;
          _received = fresh.at;
        });
      }
    } catch (_) {
      // Keep the last timetable visible through a temporary network failure.
      if (mounted) setState(() {});
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didUpdateWidget(WebSchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    _freshSchedule = null;
    _path = null;
    _pendingDate = null;
    _received = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefetchNeighbours();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _pathFor(DateTime date, {String? field, String? choice}) {
    final parameters = {...Uri.parse(_currentPath).queryParameters}
      ..remove('lang')
      ..remove('all');
    parameters['date'] = _dateKey(date);
    if (field != null) parameters[field] = choice ?? '';
    return Uri(path: '/schedule', queryParameters: parameters).toString();
  }

  /// Shows another day (or the same day with other filters) in place: the
  /// tapped day is selected at once and the content changes when it arrives.
  Future<void> _open({DateTime? date, String? field, String? choice}) async {
    final target = date ?? selected;
    final path = _pathFor(target, field: field, choice: choice);
    final ticket = ++_switch;
    setState(() {
      _pendingDate = _dateKey(target);
      _direction = target.compareTo(selected).sign;
    });
    try {
      final day = await _fetchDay(path);
      if (!mounted || ticket != _switch) return;
      if (day == null) {
        p.load(path);
        return;
      }
      setState(() {
        _freshSchedule = day.schedule;
        _received = day.at;
        _path = path;
        _pendingDate = null;
      });
      _prefetchNeighbours();
    } catch (_) {
      if (!mounted || ticket != _switch) return;
      setState(() => _pendingDate = null);
      p.load(path);
    }
  }

  Widget _filter(
    String field,
    String english,
    String arabic,
    IconData icon,
    Json filters,
    Json options,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final values = (options['${field}s'] as List? ?? [])
        .map((e) => '$e')
        .toSet();
    final current = value(filters[field]);
    if (current.isNotEmpty) values.add(current);
    final label = p.c.t(english, arabic);
    final radius = BorderRadius.circular(22);
    return Expanded(
      child: ClipRRect(
        borderRadius: radius,
        child: NativeGlassSurface(
          key: ValueKey('schedule.filterSurface.$field'),
          decoration: BoxDecoration(
            color: dark ? const Color(0xe6232825) : const Color(0xe6ffffff),
            borderRadius: radius,
            border: Border.all(
              color: dark ? const Color(0x35ffffff) : const Color(0x261c513c),
              width: .75,
            ),
          ),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: AppDropdownButton<String>(
                  key: ValueKey('schedule.filter.$field'),
                  value: current,
                  isExpanded: true,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  icon: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  menuMaxHeight: MediaQuery.sizeOf(context).height * .5,
                  onChanged: (v) => _open(field: field, choice: v),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        p.c.t('All', 'الكل'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final option in values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(
                          '$label $option',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c, theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final filters = object(schedule['filters']),
        options = object(schedule['options']);
    final entries = rows(schedule['entries']);
    final next = object(schedule['next_class']);
    final days = rows(schedule['days']);
    final date = selected;
    final now = _serverNow(schedule, _received);
    final isToday = days.any(
      (d) => value(d['date']) == _dateKey(date) && yes(d['is_today']),
    );
    final muted = theme.colorScheme.onSurfaceVariant;
    final motion = !MediaQuery.disableAnimationsOf(context);
    void swipe(DragEndDetails details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity.abs() < 280) return;
      // Swiping toward the start of the reading direction shows the next day.
      final forward = (velocity < 0) != ar;
      _open(
        date: DateTime.utc(
          date.year,
          date.month,
          date.day + (forward ? 1 : -1),
        ),
      );
    }

    return ColoredBox(
      // Dark mode uses the same plain black as every other page.
      color: dark ? Colors.black : const Color(0xfff7f7fc),
      child: RefreshIndicator(
        onRefresh: () => p.load(_currentPath),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 120),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.t('Schedule', 'الجدول'),
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _filter(
                  'level',
                  'Level',
                  'الفرقة',
                  Icons.school_outlined,
                  filters,
                  options,
                ),
                const SizedBox(width: 7),
                _filter(
                  'group',
                  'Group',
                  'جروب',
                  Icons.menu_book_outlined,
                  filters,
                  options,
                ),
                const SizedBox(width: 7),
                _filter(
                  'section',
                  'Section',
                  'سكشن',
                  Icons.science_outlined,
                  filters,
                  options,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 86,
              child: Row(
                children: [
                  for (final day in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _DayPill(
                          day: day,
                          selected:
                              value(day['date']) ==
                              (_pendingDate ?? _dateKey(date)),
                          arabic: ar,
                          onTap: () =>
                              _open(date: DateTime.parse(value(day['date']))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              key: const ValueKey('schedule.swipe'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: swipe,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                ),
                // The card grows or shrinks smoothly to the new day while the
                // old day fades out and the new one slides in from its side.
                // One continuous motion per day change: the card's height goes
                // straight to the new day's height (the leaving day is laid out
                // over it, not beside it) while the old day slides out one way
                // and the new day slides in from the other.
                child: AnimatedSize(
                  duration: motion
                      ? const Duration(milliseconds: 380)
                      : Duration.zero,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: motion
                        ? const Duration(milliseconds: 380)
                        : Duration.zero,
                    reverseDuration: motion
                        ? const Duration(milliseconds: 240)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        for (final child in previous)
                          Positioned(top: 0, left: 0, right: 0, child: child),
                        ?current,
                      ],
                    ),
                    transitionBuilder: (child, animation) {
                      final entering =
                          child.key == ValueKey(_dayContentKey(schedule));
                      final shift = (ar ? -1.0 : 1.0) * _direction * .18;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: Offset(entering ? shift : -shift, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: ScaleTransition(
                            scale: Tween(
                              begin: .985,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_dayContentKey(schedule)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isToday
                                      ? c.t('Today', 'اليوم')
                                      : '${_dayName(date, ar)}${ar ? '،' : ','} ${_displayDate(date, ar)}',
                                  style: const TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (value(filters['level']).isNotEmpty)
                                _ScheduleTag(
                                  label:
                                      '${c.t('Level', 'الفرقة')} ${filters['level']}',
                                  color: const Color(0xff8275ce),
                                ),
                            ],
                          ),
                          if (isScheduleDayOff(schedule))
                            ScheduleDayOff(
                              controller: c,
                              today: isToday,
                              appearance: object(schedule['day_off']),
                            )
                          else ...[
                            const SizedBox(height: 8),
                            Text(
                              entries.length == 1
                                  ? c.t(
                                      '1 class scheduled',
                                      'حصة واحدة في الجدول',
                                    )
                                  : c.t(
                                      '${entries.length} classes scheduled',
                                      entries.length == 2
                                          ? 'حصتين في الجدول'
                                          : '${entries.length} حصص في الجدول',
                                    ),
                              style: TextStyle(color: muted, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              c.t(
                                'Your next classes',
                                'المحاضرات والسكاشن القادمة',
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _EqualHeightRow(
                              children: [
                                Expanded(
                                  child: ScheduleClassCard(
                                    entry: object(schedule['next_lecture']),
                                    lecture: true,
                                    controller: c,
                                    now: now,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ScheduleClassCard(
                                    entry: object(schedule['next_section']),
                                    lecture: false,
                                    controller: c,
                                    now: now,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Text(
                              c.t('Day’s schedule', 'جدول اليوم'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            for (final entry in entries)
                              _ScheduleTimelineEntry(
                                entry: entry,
                                next: entry['id'] == next['id'],
                                controller: c,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              c.t(
                'All times are in Cairo time.',
                'كل المواعيد بتوقيت القاهرة.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.7, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

String _dayContentKey(Json schedule) {
  final filters = object(schedule['filters']);
  return '${schedule['date']}|${filters['level']}|${filters['group']}|${filters['section']}';
}

/// Shown instead of the class cards on a day without lectures or sections.
class ScheduleDayOff extends StatelessWidget {
  const ScheduleDayOff({
    super.key,
    required this.controller,
    required this.today,
    this.appearance = const {},
    this.compact = false,
  });
  final AppController controller;
  final bool today, compact;
  final Json appearance;

  @override
  Widget build(BuildContext context) {
    final c = controller,
        dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('schedule.dayOff'),
      margin: EdgeInsets.only(top: compact ? 4 : 22),
      padding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: compact ? 24 : 34,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0xff1f1b33), Color(0xff2a2117)]
              : const [Color(0xfff3f0ff), Color(0xfffff6ec)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Builder(
        builder: (context) {
          final message = Text(
            today
                ? c.t("Today's a day off, buddy!", 'النهارده إجازة يا صاحبي')
                : c.t("It's a day off, buddy!", 'اليوم ده إجازة يا صاحبي'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          );
          if (appearance['mode'] != 'image' ||
              value(appearance['image_url']).isEmpty) {
            return message;
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 245),
              child: Image(
                key: const ValueKey('schedule.dayOff.image'),
                image: CachedNetworkImage(
                  c.api.media(value(appearance['image_url'])),
                  width: (220 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                  cover: false,
                ),
                width: 220,
                fit: BoxFit.contain,
                semanticLabel: c.t(
                  "Today's a day off, buddy!",
                  'النهارده إجازة يا صاحبي',
                ),
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null && !synchronous
                    ? message
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: child,
                      ),
                errorBuilder: (_, _, _) => message,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.arabic,
    required this.onTap,
  });
  final Json day;
  final bool selected, arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(value(day['date']));
    final theme = Theme.of(context);
    final color = selected ? const Color(0xff7b6aec) : const Color(0xff8e84c7);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('schedule.day.${day['date']}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(
                    const Color(0xff7b6aec).withValues(alpha: .08),
                    theme.colorScheme.surface,
                  )
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(19),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: color.withValues(alpha: selected ? 1 : .14),
                child: Text(
                  _dayName(date, arabic, short: true),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: arabic ? 8 : 11,
                    color: selected ? Colors.white : color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 21,
                      color: selected ? color : null,
                      fontWeight: FontWeight.w700,
                    ),
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

class ScheduleClassCard extends StatelessWidget {
  const ScheduleClassCard({
    super.key,
    required this.entry,
    required this.lecture,
    required this.controller,
    required this.now,
    this.home = false,
  });
  final Json entry;
  final bool lecture, home;
  final AppController controller;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = lecture ? _lectureBlue : _sectionOrange;
    final subject = value(entry['subject']);
    return Container(
      key: ValueKey(
        home
            ? 'schedule.home.${lecture ? 'lecture' : 'section'}'
            : 'schedule.next.${lecture ? 'lecture' : 'section'}',
      ),
      constraints: BoxConstraints(minHeight: home ? 196 : 185),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: .14)
            : lecture
            ? const Color(0xffedf7ff)
            : const Color(0xfffff3e8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                lecture ? Icons.menu_book_outlined : Icons.science_outlined,
                size: 21,
                color: color,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  lecture ? c.t('LECTURE', 'محاضرة') : c.t('SECTION', 'سكشن'),
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (entry.isEmpty)
            Text(
              c.t('No upcoming class', 'لا توجد مواعيد قادمة'),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.8,
              ),
            )
          else ...[
            Text(
              home
                  ? _time(value(entry['start_time']), c)
                  : _remainingDuration(entry, now, c),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: home ? 24 : 26,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: home ? null : color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: contentDirection(subject),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              home
                  ? value(entry['location'])
                  : '${_time(value(entry['start_time']), c)} · ${value(entry['location'])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: contentDirection(value(entry['location'])),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            if (value(entry['source_label']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                value(entry['source_label']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: contentDirection(value(entry['source_label'])),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
            if (home) ...[
              // The pill sits at the bottom so both cards in a row line up.
              const Spacer(),
              const SizedBox(height: 10),
              _ScheduleTag(label: _countdown(entry, now, c), color: color),
            ],
          ],
        ],
      ),
    );
  }
}

/// The next-lecture and next-section cards always share one height, so a
/// card with a longer subject never leaves its neighbour shorter.
class _EqualHeightRow extends StatelessWidget {
  const _EqualHeightRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _ScheduleTag extends StatelessWidget {
  const _ScheduleTag({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

class _ScheduleTimelineEntry extends StatelessWidget {
  const _ScheduleTimelineEntry({
    required this.entry,
    required this.next,
    required this.controller,
  });
  final Json entry;
  final bool next;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final lecture = entry['type'] == 'lecture';
    final color = lecture ? _lectureBlue : _sectionOrange;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final subject = value(entry['subject']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 47,
            child: Column(
              children: [
                if (next)
                  _ScheduleTag(
                    label: controller.t('Next', 'التالي'),
                    color: const Color(0xff58b86c),
                  ),
                const SizedBox(height: 8),
                Text(
                  _time(value(entry['start_time']), controller),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
                const SizedBox(height: 8),
                Icon(
                  next ? Icons.radio_button_checked : Icons.circle_outlined,
                  color: next ? const Color(0xff58b86c) : muted,
                  size: 14,
                ),
                Container(
                  width: 1,
                  height: 64,
                  color: muted.withValues(alpha: .15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: .13),
                    color.withValues(alpha: .025),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject,
                    textDirection: contentDirection(subject),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      value(entry['source_label']),
                      value(entry['location']),
                    ].where((v) => v.isNotEmpty).join(' · '),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  if (value(entry['instructor']).isNotEmpty)
                    Text(
                      value(entry['instructor']),
                      textDirection: contentDirection(
                        value(entry['instructor']),
                      ),
                      style: TextStyle(fontSize: 11, color: muted, height: 1.7),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${_time(value(entry['start_time']), controller)} – ${_time(value(entry['end_time']), controller)}',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScheduleCard extends StatefulWidget {
  const HomeScheduleCard({
    super.key,
    required this.schedule,
    required this.controller,
  });
  final Json schedule;
  final AppController controller;

  @override
  State<HomeScheduleCard> createState() => _HomeScheduleCardState();
}

class _HomeScheduleCardState extends State<HomeScheduleCard> {
  Timer? _clock;
  Json? _freshSchedule;
  late DateTime _received = DateTime.now();
  bool _refreshing = false;
  Json get schedule => _freshSchedule ?? widget.schedule;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(HomeScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!deepJsonEquals(oldWidget.schedule, widget.schedule)) {
      _freshSchedule = null;
      _received = DateTime.now();
    }
  }

  Future<void> _refresh() async {
    final c = widget.controller, page = widget.controller.activePage;
    if (!mounted ||
        _refreshing ||
        page?.screen != 'community.index' ||
        !deepJsonEquals(page?.data['scheduleSummary'], widget.schedule) ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    final generation = c.sessionGeneration;
    _refreshing = true;
    try {
      final response = await c.fetchPage('/community');
      if (!mounted ||
          !identical(c.activePage, page) ||
          generation != c.sessionGeneration) {
        return;
      }
      final fresh = object(object(response['data'])['scheduleSummary']);
      if (response['screen'] == 'community.index' && fresh.isNotEmpty) {
        setState(() {
          _freshSchedule = fresh;
          _received = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) setState(() {});
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isScheduleDayOff(schedule)) return const SizedBox.shrink();
    final c = widget.controller, theme = Theme.of(context);
    final now = _serverNow(schedule, _received);
    final next = object(schedule['next_class']);
    final date = DateTime.tryParse(value(next['starts_at']));
    final today = value(next['starts_at']).startsWith(value(schedule['date']));
    final filters = object(schedule['profile']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Container(
        key: const ValueKey('schedule.home'),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
          ),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.t('Your Schedule', 'جدولك'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _ScheduleTag(
                  label: today || date == null
                      ? c.t('Today', 'اليوم')
                      : _displayDate(date, c.settings.language == 'ar'),
                  color: const Color(0xff2e855d),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              c.t('Stay on top of your classes', 'تابع محاضراتك وسكاشنك'),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (filters['group_number'] != null) ...[
              const SizedBox(height: 5),
              Text(
                '${c.t('Group', 'المجموعة')} ${filters['group_number']} · ${c.t('Level', 'الفرقة')} ${filters['level'] ?? '—'}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _EqualHeightRow(
              children: [
                Expanded(
                  child: ScheduleClassCard(
                    entry: object(schedule['next_lecture']),
                    lecture: true,
                    controller: c,
                    now: now,
                    home: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ScheduleClassCard(
                    entry: object(schedule['next_section']),
                    lecture: false,
                    controller: c,
                    now: now,
                    home: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            FilledButton.tonalIcon(
              key: const ValueKey('schedule.home.open'),
              onPressed: () => c.open('/schedule'),
              icon: const Icon(Icons.calendar_month_outlined, size: 20),
              label: Text(c.t('View Full Schedule', 'عرض الجدول كاملًا')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff2e855d).withValues(alpha: .1),
                foregroundColor: const Color(0xff2e855d),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
