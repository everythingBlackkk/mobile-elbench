import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'api.dart';
import 'app_menus.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_style.dart';

class QuizScoreRing extends StatelessWidget {
  const QuizScoreRing({super.key, required this.score, this.average = false});
  final dynamic score;
  final bool average;
  @override
  Widget build(BuildContext context) {
    final numeric = double.tryParse(value(score)) ?? 0;
    return SizedBox(
      width: average ? 108 : 132,
      height: average ? 108 : 132,
      child: CustomPaint(
        painter: _ScorePainter(
          numeric / 100,
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.outlineVariant,
          average,
        ),
        child: Center(
          child: average
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value(score, '—'),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    if (score != null)
                      Text(
                        '/100',
                        style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value(score, '0'),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        letterSpacing: -1.7,
                      ),
                    ),
                    Text(
                      '/ 100',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ScorePainter extends CustomPainter {
  _ScorePainter(this.progress, this.accent, this.border, this.average);
  final double progress;
  final Color accent, border;
  final bool average;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = average ? 8.0 : 6.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    // Canvas angles run clockwise from the right. A 330° arc from 105°
    // leaves its 30° gap centered at 90°, directly below the score.
    final start = average ? 105 * math.pi / 180 : -math.pi / 2;
    final sweep = (average ? 330 : 360) * math.pi / 180;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, start, sweep, false, paint..color = border);
    canvas.drawArc(
      rect,
      start,
      sweep * progress.clamp(0, 1),
      false,
      paint..color = accent,
    );
  }

  @override
  bool shouldRepaint(_ScorePainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.border != border ||
      old.average != average;
}

Widget quizSurface(
  BuildContext context,
  Widget child, {
  double radius = 18,
  EdgeInsets padding = const EdgeInsets.all(16),
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    borderRadius: BorderRadius.circular(radius),
  ),
  child: child,
);
String quizStatus(NativePageState p, dynamic status) => switch (status) {
  'submitted' => p.c.t('Submitted', 'تم التسليم'),
  'timed_out' => p.c.t('Timed out', 'انتهى الوقت'),
  'abandoned' => p.c.t('Abandoned', 'تم الانسحاب'),
  _ => value(status),
};
Widget quizStatusPill(
  BuildContext context,
  NativePageState p,
  dynamic status,
) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
  decoration: BoxDecoration(
    color: status == 'abandoned'
        ? Theme.of(context).colorScheme.error.withValues(alpha: .09)
        : Theme.of(context).colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    quizStatus(p, status),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: status == 'abandoned'
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
    ),
  ),
);
Widget quizSection(BuildContext context, String title, String count) =>
    Container(
      margin: const EdgeInsets.only(bottom: 17),
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            count,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

class WebQuizOverview extends StatelessWidget {
  const WebQuizOverview({super.key, required this.page, required this.start});
  final NativePageState page;
  final void Function(Json) start;
  @override
  Widget build(BuildContext context) {
    final p = page,
        c = p.c,
        d = p.data,
        scheme = Theme.of(context).colorScheme,
        stats = object(p.data['stats']);
    Widget fact(String icon, String title) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WebIcon(icon, size: 13, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
    Widget statistic(String icon, String label, dynamic number) => Expanded(
      child: quizSurface(
        context,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: WebIcon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.55,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value(number, '0'),
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      ),
    );
    return RefreshIndicator.adaptive(
      onRefresh: p.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.t(
                    'A little challenge. A sharper you.',
                    'شويه اسئله على الماشي',
                  ),
                  style: TextStyle(
                    fontSize: 29,
                    height: 1.22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: c.settings.language == 'en' ? -1 : 0,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 15,
                  runSpacing: 10,
                  children: [
                    fact('message', c.t('5 questions', '٥ أسئلة')),
                    fact('clock', c.t('5 minutes', '٥ دقايق')),
                    fact('trophy', c.t('100 points', '١٠٠ نقطة')),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => c.open('/quiz/history'),
                      icon: const WebIcon('clock', size: 17),
                      label: Text(c.t('My history', 'سجلّي')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: scheme.surface,
                      ),
                    ),
                    if (c.permission('quiz.manage'))
                      OutlinedButton.icon(
                        onPressed: () => c.open('/quiz/manage'),
                        icon: const WebIcon('settings', size: 17),
                        label: Text(c.t('Manage questions', 'إدارة الأسئلة')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: scheme.surface,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.t('Your progress', 'تقدّمك في الاختبارات'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  c.t('Pass mark: 60 / 100', 'درجة النجاح: ٦٠ / ١٠٠'),
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            c.t('Average score', 'متوسط النتيجة'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 9),
          Center(
            child: QuizScoreRing(score: stats['average_score'], average: true),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              statistic(
                'graduation',
                c.t('Completed quizzes', 'اختبارات مكتملة'),
                stats['completed'],
              ),
              const SizedBox(width: 9),
              statistic(
                'check',
                c.t('Quizzes passed', 'اختبارات ناجحة'),
                stats['passed'],
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (d['activeAttempt'] != null) ...[
            quizSurface(
              context,
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.t(
                            'You have an unfinished quiz.',
                            'عندك اختبار لسه مخلصش.',
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value(object(d['activeAttempt'])['category_name']),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () =>
                        c.open('/quiz/${object(d['activeAttempt'])['uuid']}'),
                    child: Text(
                      c.t('Resume quiz', 'كمّل الاختبار'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              radius: 16,
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 16),
          ],
          quizSection(
            context,
            c.t('Choose your topic', 'اختار موضوعك'),
            rows(d['categories']).length.toString().padLeft(2, '0'),
          ),
          for (final category in rows(d['categories']))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                onTap: yes(category['available_for_attempt'])
                    ? () => start(category)
                    : null,
                borderRadius: BorderRadius.circular(18),
                child: quizSurface(
                  context,
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QuizCategoryIcon(
                          value(category['slug']),
                          color: scheme.primary,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value(category['name']),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              c.t(
                                '5 questions · 5 minutes',
                                '٥ أسئلة · ٥ دقايق',
                              ),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      if (yes(category['available_for_attempt']))
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: WebIcon(
                            c.settings.language == 'ar'
                                ? 'back'
                                : 'chevron-right',
                            size: 15,
                            color: scheme.primary,
                          ),
                        )
                      else
                        Text(
                          c.t('Coming soon', 'قريبًا'),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 19,
                  ),
                ),
              ),
            ),
          if (rows(d['categories']).isEmpty)
            p.empty(
              c.t(
                'No question banks are available yet.',
                'مفيش بنوك أسئلة متاحة دلوقتي.',
              ),
            ),
        ],
      ),
    );
  }
}

class WebQuizHistory extends StatelessWidget {
  const WebQuizHistory({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final p = page,
        c = p.c,
        d = p.data,
        scheme = Theme.of(context).colorScheme,
        params = Uri.parse(p.path).queryParameters;
    return RefreshIndicator.adaptive(
      onRefresh: p.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => c.open('/quiz'),
                  icon: const WebIcon('back', size: 17),
                  label: Text(
                    c.t('Back to quiz banks', 'الرجوع لبنوك الأسئلة'),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  c.t('Quiz history', 'سجل الاختبارات'),
                  style: const TextStyle(
                    fontSize: 29,
                    height: 1.22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  c.t(
                    'Your results, ready to revisit.',
                    'كل نتائجك في مكان واحد، راجعها وقت ما تحب.',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.65,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => c.open('/quiz'),
                    child: Text(c.t('Try another bank', 'جرّب بنك تاني')),
                  ),
                ),
              ],
            ),
          ),
          AppDropdownButtonFormField<String>(
            isExpanded: true,
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
            initialValue: params['category_id'] ?? '',
            decoration: const InputDecoration(isDense: true),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(c.t('All question banks', 'كل بنوك الأسئلة')),
              ),
              ...rows(d['categories']).map(
                (cat) => DropdownMenuItem(
                  value: '${cat['id']}',
                  child: Text(
                    value(cat['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) => p.query({'category_id': v}),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: AppDropdownButtonFormField<String>(
                  isExpanded: true,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  initialValue: params['status'] ?? '',
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(c.t('All results', 'كل النتائج')),
                    ),
                    for (final status in [
                      'submitted',
                      'timed_out',
                      'abandoned',
                    ])
                      DropdownMenuItem(
                        value: status,
                        child: Text(quizStatus(p, status)),
                      ),
                  ],
                  onChanged: (v) => p.query({'status': v}),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AppDropdownButtonFormField<String>(
                  isExpanded: true,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  initialValue: params['sort'] ?? 'newest',
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text(c.t('Newest first', 'الأحدث الأول')),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text(c.t('Oldest first', 'الأقدم الأول')),
                    ),
                  ],
                  onChanged: (v) => p.query({'sort': v}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FilledButton(onPressed: p.load, child: Text(c.t('Filter', 'تصفية'))),
          const SizedBox(height: 20),
          Text(
            '${object(d['attempts'])['total'] ?? rows(d['attempts']).length} ${c.t('quizzes', 'اختبار')}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 13),
          for (final a in rows(d['attempts']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: quizSurface(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: QuizCategoryIcon(
                            value(a['category_slug']),
                            color: scheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            value(a['category_name']),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              value(a['score'], '0'),
                              style: TextStyle(
                                fontSize: 27,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color:
                                    (double.tryParse(value(a['score'])) ?? 0) >=
                                        60
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                            Text(
                              '/ 100',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      p.date(a['submitted_at'] ?? a['started_at']),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.t('Status', 'الحالة'),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 5),
                            quizStatusPill(context, p, a['status']),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              c.t('Time taken', 'الوقت المستغرق'),
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              duration(a['time_taken_seconds']),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => c.open('/quiz/${a['uuid']}'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).scaffoldBackgroundColor,
                          minimumSize: const Size(0, 40),
                        ),
                        child: Text(
                          c.t('Review', 'مراجعة'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                radius: 19,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
          if (rows(d['attempts']).isEmpty)
            p.empty(
              c.t(
                'Your completed quizzes will appear here.',
                'اختباراتك المكتملة هتظهر هنا.',
              ),
            ),
          p.pagination(d['attempts']),
        ],
      ),
    );
  }
}

String duration(dynamic input) {
  final sec = int.tryParse(value(input)) ?? 0;
  return '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
}

class WebQuizResult extends StatelessWidget {
  const WebQuizResult({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final p = page,
        c = p.c,
        d = p.data,
        a = object(p.data['attempt']),
        scheme = Theme.of(context).colorScheme;
    final items = rows(d['items']),
        correct =
            int.tryParse(value(a['correct_count'])) ??
            items.where((i) => yes(i['is_correct'])).length,
        unanswered = items.where((i) => i['answer'] == null).length,
        incorrect = items.length - correct - unanswered;
    final score = double.tryParse(value(a['score'])) ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 112),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => c.open('/quiz'),
            icon: const WebIcon('back', size: 17),
            label: Text(c.t('Quiz', 'أسئلة')),
          ),
        ),
        const SizedBox(height: 24),
        quizSurface(
          context,
          Column(
            children: [
              quizStatusPill(context, p, a['status']),
              const SizedBox(height: 16),
              Text(
                value(a['category_name']),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 7),
              Text(
                a['status'] == 'abandoned'
                    ? c.t('Quiz abandoned', 'انسحبت من الاختبار')
                    : score >= 60
                    ? c.t('Nice work!', 'عاش، شغل حلو!')
                    : c.t('Your score', 'نتيجتك'),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              QuizScoreRing(score: a['score']),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                runSpacing: 8,
                children: [
                  for (final (n, label) in [
                    (correct, c.t('Correct', 'صح')),
                    (incorrect, c.t('Incorrect', 'غلط')),
                    (unanswered, c.t('Unanswered', 'من غير إجابة')),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            '$n',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if ((int.tryParse(value(a['penalty_points'])) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    c.t(
                      '−10 · 10 points deducted from your total.',
                      '−١٠ · اتخصم ١٠ نقط من مجموعك.',
                    ),
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              const SizedBox(height: 23),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WebIcon('clock', size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    duration(a['time_taken_seconds']),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    p.date(a['submitted_at']),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 23),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => c.open('/quiz'),
                      child: Text(
                        c.t('Try another bank', 'جرّب بنك تاني'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => c.open('/quiz/history'),
                      child: Text(
                        c.t('My history', 'سجلّي'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
        ),
        const SizedBox(height: 26),
        quizSection(
          context,
          c.t('Answer review', 'مراجعة الإجابات'),
          items.length.toString().padLeft(2, '0'),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: quizSurface(
              context,
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                leading: Text(
                  value(item['position']).padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                title: Text(
                  value(item['statement']),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      yes(item['is_correct'])
                          ? '✓'
                          : item['answer'] == null
                          ? '—'
                          : '×',
                      style: TextStyle(
                        color: yes(item['is_correct'])
                            ? scheme.primary
                            : scheme.error,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    WebIcon(
                      'chevron-down',
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                children: [
                  if (value(item['code']).isNotEmpty) QuizCode(item: item),
                  for (final (key, label) in [
                    ('answer', c.t('Your answer', 'إجابتك')),
                    ('correct_answer', c.t('Correct answer', 'الإجابة الصح')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              value(
                                object(item['options'])[value(item[key])],
                                c.t('Unanswered', 'من غير إجابة'),
                              ),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.65,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value(item['explanation']),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.75,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              radius: 16,
              padding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

class QuizCode extends StatelessWidget {
  const QuizCode({super.key, required this.item});
  final Json item;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark,
        scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff111a20) : const Color(0xfff0f3f5),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value(item['code_language']),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Clipboard.setData(
                      ClipboardData(text: value(item['code'])),
                    ),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'نسخ الكود'
                          : 'Copy code',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(13),
              child: SelectableText(
                value(item['code']),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.7,
                  color: dark
                      ? const Color(0xffdbe4ea)
                      : const Color(0xff25333c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _categoryShapes = <String, String>{
  "cpp": "<path d=\"m12 9-7 7 7 7m8-14 7 7-7 7m-3-18-3 22\"/>",
  "oop-cpp":
      "<rect x=\"3\" y=\"5\" width=\"11\" height=\"9\" rx=\"2\"/><rect x=\"18\" y=\"5\" width=\"11\" height=\"9\" rx=\"2\"/><rect x=\"10.5\" y=\"20\" width=\"11\" height=\"9\" rx=\"2\"/><path d=\"M8.5 14v3h15v-3M16 17v3\"/>",
  "data-structures-cpp":
      "<circle cx=\"16\" cy=\"5\" r=\"3\"/><circle cx=\"7\" cy=\"25\" r=\"3\"/><circle cx=\"16\" cy=\"25\" r=\"3\"/><circle cx=\"25\" cy=\"25\" r=\"3\"/><path d=\"M16 8v8M7 22v-6h18v6M16 16v6\"/>",
  "intel-x64":
      "<rect x=\"7\" y=\"7\" width=\"18\" height=\"18\" rx=\"3\"/><rect x=\"12\" y=\"12\" width=\"8\" height=\"8\" rx=\"1\"/><path d=\"M12 3v4m8-4v4M12 25v4m8-4v4M3 12h4m-4 8h4m18-8h4m-4 8h4\"/>",
  "application-security":
      "<path d=\"M16 3 27 7v8c0 7-5 11-11 14C10 26 5 22 5 15V7l11-4Z\"/><path d=\"m11 16 3 3 7-7\"/>",
  "cybersecurity":
      "<path d=\"M16 3 27 7v8c0 7-5 11-11 14C10 26 5 22 5 15V7l11-4Z\"/><path d=\"m11 16 3 3 7-7\"/>",
  "frontend":
      "<rect x=\"3\" y=\"5\" width=\"26\" height=\"22\" rx=\"3\"/><path d=\"M3 11h26M9 8h.01M13 8h.01m1 8-4 4 4 4m6-8 4 4-4 4\"/>",
  "backend":
      "<rect x=\"5\" y=\"4\" width=\"22\" height=\"10\" rx=\"2\"/><rect x=\"5\" y=\"18\" width=\"22\" height=\"10\" rx=\"2\"/><path d=\"M10 9h.01M10 23h.01m5-14h8m-8 14h8\"/>",
  "ai":
      "<path d=\"M12 5c-4-2-8 1-8 5 0 2 1 3 2 4-2 2-2 6 1 8 0 4 5 6 8 3V7c0-1-1-2-3-2Zm8 0c4-2 8 1 8 5 0 2-1 3-2 4 2 2 2 6-1 8 0 4-5 6-8 3V7c0-1 1-2 3-2Z\"/><path d=\"M9 12c3 0 4 2 4 4m10-4c-3 0-4 2-4 4M9 21c3 0 4-2 4-4m10 4c-3 0-4-2-4-4\"/>",
  "iot":
      "<rect x=\"10\" y=\"17\" width=\"12\" height=\"11\" rx=\"2\"/><path d=\"M16 17v-4M8 11a11 11 0 0 1 16 0M4 7a17 17 0 0 1 24 0M13 22h6m-6 3h3\"/>",
  "linux":
      "<rect x=\"3\" y=\"5\" width=\"26\" height=\"22\" rx=\"4\"/><path d=\"m8 12 5 4-5 4m9 1h7M9 8h.01m4 0h.01\"/>",
  "python":
      "<path d=\"M16 3h-5a4 4 0 0 0-4 4v5h11V8m-7 4H6a4 4 0 0 0-4 4v4a4 4 0 0 0 4 4h5m5 5h5a4 4 0 0 0 4-4v-5H14v4m7-4h5a4 4 0 0 0 4-4v-4a4 4 0 0 0-4-4h-5M16 3a4 4 0 0 1 4 4v5a4 4 0 0 1-4 4h-1a4 4 0 0 0-4 4v5a4 4 0 0 0 5 4\"/><circle cx=\"12\" cy=\"7\" r=\".8\" fill=\"currentColor\" stroke=\"none\"/><circle cx=\"20\" cy=\"25\" r=\".8\" fill=\"currentColor\" stroke=\"none\"/>",
  "general-knowledge":
      "<circle cx=\"16\" cy=\"16\" r=\"12\"/><ellipse cx=\"16\" cy=\"16\" rx=\"5\" ry=\"12\"/><path d=\"M4 16h24M6 10h20M6 22h20\"/>",
  "default":
      "<path d=\"m16 3 2.8 9.2L28 15l-9.2 2.8L16 27l-2.8-9.2L4 15l9.2-2.8L16 3Z\"/>",
};

class QuizCategoryIcon extends StatelessWidget {
  const QuizCategoryIcon(this.slug, {super.key, this.color, this.size = 23});
  final String slug;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="${resolved.toARGB32().toRadixString(16).replaceRange(0, 2, '#')}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${_categoryShapes[slug] ?? _categoryShapes['default']}</svg>',
      width: size,
      height: size,
    );
  }
}

class WebQuizAdmin extends StatelessWidget {
  const WebQuizAdmin({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    final p = page,
        c = p.c,
        d = p.data,
        scheme = Theme.of(context).colorScheme,
        stats = object(p.data['stats']),
        params = Uri.parse(p.path).queryParameters;
    return RefreshIndicator.adaptive(
      onRefresh: p.pullRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => c.open('/quiz'),
                  icon: const WebIcon('back', size: 17),
                  label: Text(
                    c.t('Back to quiz banks', 'الرجوع لبنوك الأسئلة'),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  c.t('Question manager', 'إدارة الأسئلة'),
                  style: const TextStyle(
                    fontSize: 29,
                    height: 1.22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  c.t(
                    'Keep the question bank clear and useful.',
                    'خلّي بنك الأسئلة واضح ومفيد.',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => c.open('/quiz/manage/create'),
                  icon: const WebIcon('plus', size: 17, color: Colors.white),
                  label: Text(c.t('Add question', 'إضافة سؤال')),
                ),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.3,
            children: [
              for (final (key, label) in [
                ('questions', c.t('Questions', 'الأسئلة')),
                ('categories', c.t('Categories', 'التصنيفات')),
                ('easy', c.t('Easy', 'سهل')),
                ('medium', c.t('Medium', 'متوسط')),
                ('hard', c.t('Hard', 'صعب')),
              ])
                quizSurface(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value(stats[key], '0'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  radius: 15,
                  padding: const EdgeInsets.all(12),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            c.t('Questions by category', 'الأسئلة حسب التصنيف'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final category in rows(d['categories']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: quizSurface(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value(category['name']),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${category['questions_count'] ?? 0} ${c.t('questions', 'سؤال')}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${c.t('Easy', 'سهل')} ${category['easy_count'] ?? 0} · ${c.t('Medium', 'متوسط')} ${category['medium_count'] ?? 0} · ${c.t('Hard', 'صعب')} ${category['hard_count'] ?? 0}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                radius: 12,
                padding: const EdgeInsets.all(13),
              ),
            ),
          const SizedBox(height: 26),
          p.search('search', c.t('Search questions', 'بحث عن الأسئلة')),
          AppDropdownButtonFormField<String>(
            initialValue: params['category_id'] ?? '',
            decoration: const InputDecoration(isDense: true),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(c.t('All categories', 'كل التصنيفات')),
              ),
              ...rows(d['categories']).map(
                (cat) => DropdownMenuItem(
                  value: '${cat['id']}',
                  child: Text(value(cat['name'])),
                ),
              ),
            ],
            onChanged: (v) => p.query({'category_id': v}),
          ),
          const SizedBox(height: 9),
          AppDropdownButtonFormField<String>(
            initialValue: params['difficulty'] ?? '',
            decoration: const InputDecoration(isDense: true),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(c.t('All difficulties', 'كل المستويات')),
              ),
              DropdownMenuItem(value: 'easy', child: Text(c.t('Easy', 'سهل'))),
              DropdownMenuItem(
                value: 'medium',
                child: Text(c.t('Medium', 'متوسط')),
              ),
              DropdownMenuItem(value: 'hard', child: Text(c.t('Hard', 'صعب'))),
            ],
            onChanged: (v) => p.query({'difficulty': v}),
          ),
          const SizedBox(height: 9),
          FilledButton(onPressed: p.load, child: Text(c.t('Filter', 'تصفية'))),
          const SizedBox(height: 20),
          for (final q in rows(d['questions']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: quizSurface(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 9,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          value(object(q['category'])['name']),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            value(q['difficulty']),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                        if (q['deleted_at'] != null)
                          quizStatusPill(context, p, c.t('Archived', 'مؤرشف')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      value(q['statement']),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (value(q['code']).isNotEmpty) QuizCode(item: q),
                    for (final option in object(q['options']).entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: q['correct_answer'] == option.key
                                ? scheme.primaryContainer
                                : Theme.of(context).scaffoldBackgroundColor,
                            border: Border.all(
                              color: q['correct_answer'] == option.key
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${option.key}  ${option.value}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    if (q['deleted_at'] == null)
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                c.open('/quiz/manage/${q['id']}/edit'),
                            child: Text(c.t('Edit', 'تعديل')),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () => p.form(
                              c.t('Delete this question?', 'حذف السؤال؟'),
                              '/quiz/manage/${q['id']}',
                              [],
                              method: 'DELETE',
                              destructive: true,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                            ),
                            child: Text(c.t('Delete', 'حذف')),
                          ),
                        ],
                      ),
                  ],
                ),
                radius: 18,
                padding: const EdgeInsets.all(16),
              ),
            ),
          if (rows(d['questions']).isEmpty)
            p.empty(
              c.t(
                'No questions match those filters.',
                'مفيش أسئلة مطابقة للتصفية.',
              ),
            ),
          p.pagination(d['questions']),
        ],
      ),
    );
  }
}

class WebQuizEditor extends StatefulWidget {
  const WebQuizEditor({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebQuizEditor> createState() => _WebQuizEditorState();
}

class _WebQuizEditorState extends State<WebQuizEditor> {
  final form = GlobalKey<FormState>();
  final inputs = <String, TextEditingController>{};
  String? category, correct;
  String difficulty = 'medium', language = 'none';
  bool busy = false;
  String? error;
  NativePageState get p => widget.page;
  @override
  void initState() {
    super.initState();
    final q = object(p.data['question']);
    category = q['category_id']?.toString();
    correct = q['correct_answer'];
    difficulty = value(q['difficulty'], 'medium');
    language = value(q['code_language'], 'none');
    for (final key in [
      'statement',
      'explanation',
      'code',
      'A',
      'B',
      'C',
      'D',
    ]) {
      inputs[key] = TextEditingController(
        text: value(
          ['A', 'B', 'C', 'D'].contains(key)
              ? object(q['options'])[key]
              : q[key],
        ),
      );
      inputs[key]!.addListener(changed);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final input in inputs.values) {
      input.removeListener(changed);
      input.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (correct == null) {
      setState(
        () => error = p.c.t(
          'Choose the correct answer.',
          'اختر الإجابة الصحيحة.',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final q = object(p.data['question']);
      await p.c.action(
        q.isEmpty ? 'POST' : 'PUT',
        q.isEmpty ? '/quiz/manage' : '/quiz/manage/${q['id']}',
        {
          'statement': inputs['statement']!.text,
          'category_id': category,
          'difficulty': difficulty,
          'options': {
            for (final l in ['A', 'B', 'C', 'D']) l: inputs[l]!.text,
          },
          'correct_answer': correct,
          'explanation': inputs['explanation']!.text,
          'code': inputs['code']!.text.trim().isEmpty
              ? null
              : inputs['code']!.text,
          'code_language': language,
        },
      );
      await p.load('/quiz/manage');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = p.c,
        scheme = Theme.of(context).colorScheme,
        q = object(p.data['question']);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
    Widget input(String key, String title, int lines, {bool required = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label(title),
              AdaptiveTextField(
                controller: inputs[key],
                field: (direction) => TextFormField(
                  controller: inputs[key],
                  maxLines: lines,
                  textDirection: key == 'code' ? TextDirection.ltr : direction,
                  enabled: !busy,
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: key == 'code' ? 'monospace' : null,
                  ),
                  validator: (v) => required && (v?.trim().isEmpty ?? true)
                      ? c.t('This field is required', 'هذا الحقل مطلوب')
                      : null,
                ),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 112),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => p.load('/quiz/manage'),
                icon: const WebIcon('back', size: 17),
                label: Text(c.t('Question manager', 'إدارة الأسئلة')),
              ),
              const SizedBox(height: 18),
              Text(
                q.isEmpty
                    ? c.t('Add question', 'إضافة سؤال')
                    : c.t('Edit', 'تعديل'),
                style: const TextStyle(
                  fontSize: 29,
                  height: 1.22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        quizSurface(
          context,
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ),
                input('statement', c.t('Question text', 'نص السؤال'), 4),
                label(c.t('Question bank', 'بنك الأسئلة')),
                AppDropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  items: rows(p.data['categories'])
                      .map(
                        (cat) => DropdownMenuItem(
                          value: '${cat['id']}',
                          child: Text(value(cat['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => category = v,
                  validator: (v) => v == null
                      ? c.t('Choose a category', 'اختر تصنيفًا')
                      : null,
                ),
                const SizedBox(height: 18),
                label(c.t('Difficulty', 'المستوى')),
                AppDropdownButtonFormField<String>(
                  initialValue: difficulty,
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'easy',
                      child: Text(c.t('Easy', 'سهل')),
                    ),
                    DropdownMenuItem(
                      value: 'medium',
                      child: Text(c.t('Medium', 'متوسط')),
                    ),
                    DropdownMenuItem(
                      value: 'hard',
                      child: Text(c.t('Hard', 'صعب')),
                    ),
                  ],
                  onChanged: busy ? null : (v) => difficulty = v ?? 'medium',
                ),
                const SizedBox(height: 18),
                label(c.t('Answer options', 'الاختيارات')),
                for (final letter in ['A', 'B', 'C', 'D'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border.all(
                            color: correct == letter
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: busy
                                  ? null
                                  : () => setState(() => correct = letter),
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(
                                  correct == letter
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 18,
                                  color: correct == letter
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              letter,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdaptiveTextField(
                                controller: inputs[letter],
                                field: (direction) => TextFormField(
                                  controller: inputs[letter],
                                  textDirection: direction,
                                  enabled: !busy,
                                  decoration: InputDecoration(
                                    hintText: 'Option $letter',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                  validator: (v) =>
                                      v!.trim().isEmpty ? 'Required' : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                label(c.t('Code language', 'لغة الكود')),
                AppDropdownButtonFormField<String>(
                  initialValue: language,
                  decoration: InputDecoration(
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  items: [
                    for (final lang
                        in (p.data['languages'] as List? ?? ['none']))
                      DropdownMenuItem(
                        value: '$lang',
                        child: Text(
                          lang == 'none' ? '—' : '$lang'.toUpperCase(),
                        ),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => language = v ?? 'none'),
                ),
                const SizedBox(height: 18),
                input(
                  'code',
                  c.t('Code sample', 'مثال الكود'),
                  7,
                  required: false,
                ),
                label(c.t('Preview', 'معاينة')),
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        inputs['statement']!.text,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final letter in ['A', 'B', 'C', 'D'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '$letter  ${inputs[letter]!.text}',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 13,
                              color: correct == letter
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (inputs['code']!.text.isNotEmpty)
                        QuizCode(
                          item: {
                            'code': inputs['code']!.text,
                            'code_language': language,
                          },
                        ),
                    ],
                  ),
                ),
                input('explanation', c.t('Explanation', 'التفسير'), 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => p.load('/quiz/manage'),
                        child: Text(c.t('Cancel', 'إلغاء')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : save,
                        child: Text(
                          busy
                              ? c.t('Saving…', 'جارٍ الحفظ…')
                              : c.t('Save question', 'حفظ السؤال'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          radius: 18,
          padding: const EdgeInsets.all(17),
        ),
      ],
    );
  }
}
