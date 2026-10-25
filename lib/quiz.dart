import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'api.dart';
import 'app_toast.dart';
import 'screens.dart';
import 'web_style.dart';
import 'quiz_views.dart';

class QuizContent extends StatelessWidget {
  const QuizContent({super.key, required this.page});
  final NativePageState page;
  @override
  Widget build(BuildContext context) {
    if (page.screen == 'quiz.index') {
      return WebQuizOverview(
        page: page,
        start: (category) => start(context, category),
      );
    }
    if (page.screen == 'quiz.history') return WebQuizHistory(page: page);
    if (page.screen == 'quiz.result') return WebQuizResult(page: page);
    if (page.screen == 'quiz.attempt') {
      return QuizAttemptView(
        key: ValueKey(
          '${object(page.data['attempt'])['uuid']}:${page.data['presence_token']}',
        ),
        page: page,
      );
    }
    if (page.screen == 'quiz.admin.index') return WebQuizAdmin(page: page);
    if (page.screen == 'quiz.admin.form') return WebQuizEditor(page: page);
    return page.empty();
  }

  Future<void> start(BuildContext context, Json category) async {
    final c = page.c;
    final accept = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          28,
          24,
          26 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: WebIcon(
                'clock',
                size: 23,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              value(category['name']),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              c.t('Ready when you are.', 'جاهز للتحدّي؟'),
              style: const TextStyle(
                fontSize: 24,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              c.t(
                'You have 5 minutes and 5 questions. Saved answers are scored if time runs out.',
                'قدامك ٥ دقايق و٥ أسئلة. لو الوقت خلص، هتتحسب إجاباتك اللي اتحفظت.',
              ),
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.error.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    '−10',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      c.t(
                        'Leaving through the app without submitting, or a detected page departure, deducts 10 points. A timed-out quiz keeps points from saved answers.',
                        'لو خرجت من التطبيق من غير ما تسلّم، هيتخصم ١٠ نقط. لو الوقت خلص، هتحتفظ بنقط الإجابات المحفوظة.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.65,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(c.t('Cancel', 'إلغاء')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('quiz.confirmStart'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(c.t('Start quiz', 'ابدأ الاختبار')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (accept != true) return;
    try {
      final response = await c.action(
        'POST',
        '/quiz/${category['slug']}/start',
        {'accepted_rules': true},
      );
      c.open(value(response['url'], '/quiz/${response['attempt_id']}'));
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '$e');
      }
    }
  }
}

List<MapEntry<String, String>> optionEntries(dynamic source) {
  if (source is Map) {
    return source.entries
        .map(
          (e) => MapEntry(
            '${e.key}',
            e.value is Map ? value(e.value['text']) : '${e.value}',
          ),
        )
        .toList();
  }
  return rows(
    source,
  ).map((e) => MapEntry(value(e['label']), value(e['text']))).toList();
}

Widget code(Json item) => Container(
  width: double.infinity,
  margin: const EdgeInsets.symmetric(vertical: 14),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: const Color(0xff152019),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: SelectableText(
      value(item['code']),
      style: const TextStyle(fontFamily: 'monospace', color: Color(0xffdef0df)),
    ),
  ),
);

class QuizAttemptView extends StatefulWidget {
  const QuizAttemptView({super.key, required this.page});
  final NativePageState page;
  @override
  State<QuizAttemptView> createState() => _QuizAttemptViewState();
}

class _QuizAttemptViewState extends State<QuizAttemptView>
    with WidgetsBindingObserver {
  late List<Json> items;
  late final String endpoint, presence;
  int index = 0, baseSeconds = 0;
  final elapsed = Stopwatch();
  Timer? ticker;
  bool finishing = false, complete = false, departed = false;
  final Map<String, Future<void>> pending = {};
  final Map<String, String> errors = {};
  final Set<String> saving = {};
  NativePageState get p => widget.page;
  int get remaining => (baseSeconds - elapsed.elapsed.inSeconds).clamp(0, 7200);
  @override
  void initState() {
    super.initState();
    items = rows(p.data['items']).map((v) => <String, dynamic>{...v}).toList();
    endpoint = '/quiz/${object(p.data['attempt'])['uuid']}';
    presence = value(p.data['presence_token']);
    baseSeconds = (p.data['secondsRemaining'] as num?)?.toInt() ?? 0;
    elapsed.start();
    WidgetsBinding.instance.addObserver(this);
    p.c.navigationGuard = () async {
      final leave = await confirmLeave();
      if (leave && mounted) unawaited(p.load());
      return leave;
    };
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || complete) return;
      if (remaining == 0 &&
          !finishing &&
          (_nextAutoSubmit == null ||
              DateTime.now().isAfter(_nextAutoSubmit!))) {
        finish(automatic: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (complete) return;
    if ([
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ].contains(state)) {
      depart();
    }
    if (state == AppLifecycleState.resumed && departed) {
      complete = true;
      p.c.navigationGuard = null;
      p.load();
    }
  }

  Future<void> depart() async {
    if (departed || complete || presence.isEmpty) return;
    departed = true;
    try {
      await p.c.action('POST', '$endpoint/depart', {
        'presence_token': presence,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    ticker?.cancel();
    elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    p.c.navigationGuard = null;
    if (!complete) {
      depart();
    }
    super.dispose();
  }

  Future<void> save(Json item, String? answer) async {
    final id = '${item['id']}';
    if (saving.contains(id) || finishing) return;
    setState(() {
      item['answer'] = answer;
      saving.add(id);
      errors.remove(id);
    });
    final task = () async {
      try {
        final result = await p.c.action('PATCH', '$endpoint/questions/$id', {
          'answer': answer,
          'revision': item['revision'] ?? 0,
        });
        item['answer'] = result['answer'];
        item['revision'] = result['revision'];
        syncClock(result);
      } on ApiFailure catch (e) {
        if (e.status == 409) {
          item['answer'] = e.body['answer'];
          item['revision'] = e.body['revision'];
          syncClock(e.body);
          errors[id] = p.c.t(
            'Another session changed this answer. The server version is shown. Select again if needed.',
            'تم تغيير الإجابة في جلسة أخرى. تظهر نسخة الخادم. اختر مجددًا عند الحاجة.',
          );
        } else if (e.status == 410) {
          complete = true;
          p.c.navigationGuard = null;
          await p.load();
        } else {
          errors[id] = e.message;
        }
      } catch (e) {
        errors[id] = '$e';
      } finally {
        saving.remove(id);
        pending.remove(id);
        if (mounted) setState(() {});
      }
    }();
    pending[id] = task;
    await task;
  }

  void syncClock(Json result) {
    if (result['seconds_remaining'] is num) {
      baseSeconds = (result['seconds_remaining'] as num).toInt();
      elapsed.reset();
    }
  }

  Future<bool> confirmLeave() async {
    if (complete) return true;
    if (finishing) return false;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.c.t('Leave this quiz?', 'مغادرة الاختبار؟')),
        content: Text(
          p.c.t(
            'Leaving abandons this attempt and deducts 10 points. Your attempt cannot be resumed.',
            'المغادرة تنهي هذا الاختبار وتخصم ١٠ نقاط. لن تتمكن من استكماله.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(p.c.t('Stay', 'بقاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(p.c.t('Leave quiz', 'مغادرة الاختبار')),
          ),
        ],
      ),
    );
    if (leave != true) return false;
    setState(() => finishing = true);
    try {
      await Future.wait(pending.values.toList());
      await p.c.action('POST', '$endpoint/abandon', {
        'presence_token': presence,
      });
      complete = true;
      p.c.navigationGuard = null;
      return true;
    } catch (e) {
      if (mounted) {
        showAppToast(context, '$e');
      }
      return false;
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  // Automatic submission after time runs out backs off on failure instead of
  // retrying (and showing an error) every second.
  DateTime? _nextAutoSubmit;
  int _autoFailures = 0;

  Future<void> finish({bool automatic = false}) async {
    if (finishing || complete) return;
    if (!automatic) {
      final unanswered = items.where((i) => i['answer'] == null).length;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(p.c.t('Submit quiz?', 'تسليم الاختبار؟')),
          content: Text(
            p.c.t(
              '$unanswered unanswered questions. You cannot change answers after submitting.',
              '$unanswered سؤال بدون إجابة. لا يمكن تغيير الإجابات بعد التسليم.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(p.c.t('Keep working', 'متابعة الحل')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              key: const ValueKey('quiz.confirmSubmit'),
              child: Text(p.c.t('Submit', 'تسليم')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    setState(() => finishing = true);
    try {
      await Future.wait(pending.values.toList());
      if (errors.isNotEmpty && !automatic) {
        throw ApiFailure(
          p.c.t(
            'Some answers are not saved. Retry them before submitting.',
            'بعض الإجابات لم تُحفظ. أعد حفظها قبل التسليم.',
          ),
        );
      }
      await p.c.action('POST', '$endpoint/submit');
      complete = true;
      p.c.navigationGuard = null;
      await p.load();
    } catch (e) {
      if (automatic) {
        _autoFailures++;
        _nextAutoSubmit = DateTime.now().add(
          Duration(seconds: (5 * (1 << (_autoFailures - 1))).clamp(5, 60)),
        );
        // The server finalizes expired attempts when the attempt is shown.
        if (_autoFailures > 1 && mounted) unawaited(p.load());
        if (_autoFailures > 1) return;
      }
      if (mounted) {
        showAppToast(context, '$e');
      }
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return p.empty();
    final item = items[index], id = '${items[index]['id']}', c = p.c;
    final scheme = Theme.of(context).colorScheme;
    final answered = items.where((i) => i['answer'] != null).length;
    final selected = value(item['answer']);
    return PopScope(
      canPop: complete,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirmLeave() && context.mounted) {
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 22),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: [
                Container(
                  width: 104,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(
                      color: remaining < 30
                          ? scheme.error
                          : scheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: remaining < 30 ? scheme.error : scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: remaining < 30
                              ? scheme.error
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              c.t(
                '$answered of ${items.length} answered',
                '$answered من ${items.length} تمت الإجابة',
              ),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: answered / items.length,
              minHeight: 3,
              color: scheme.primary,
              backgroundColor: scheme.outlineVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (i, q) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5),
                    child: InkWell(
                      key: ValueKey('quiz.number.${i + 1}'),
                      onTap: () => setState(() => index = i),
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: q['answer'] != null
                              ? scheme.primaryContainer
                              : scheme.surface,
                          border: Border.all(
                            color: i == index
                                ? scheme.primary
                                : Colors.transparent,
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: i == index || q['answer'] != null
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            if (q['answer'] != null)
                              Positioned(
                                bottom: 4,
                                child: Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: math.max(
              360,
              math.min(MediaQuery.sizeOf(context).height * .58, 620),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          c.t(
                            'Question ${index + 1} of ${items.length}',
                            'السؤال ${index + 1} من ${items.length}',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          value(item['statement']),
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (value(item['code']).isNotEmpty)
                          QuizCode(item: item),
                        for (final option in optionEntries(item['options']))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: InkWell(
                                key: ValueKey('quiz.option.${option.key}'),
                                onTap:
                                    saving.contains(id) ||
                                        finishing ||
                                        remaining == 0
                                    ? null
                                    : () => save(item, option.key),
                                borderRadius: BorderRadius.circular(13),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 55,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: selected == option.key
                                        ? scheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).scaffoldBackgroundColor,
                                    border: Border.all(
                                      color: selected == option.key
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: selected == option.key
                                              ? c.settings.accent
                                              : scheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          option.key,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: selected == option.key
                                                ? Colors.white
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          option.value,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (errors[id] != null) ...[
                          Text(
                            errors[id]!,
                            style: TextStyle(color: scheme.error, fontSize: 11),
                          ),
                          TextButton.icon(
                            onPressed: () => save(item, item['answer']),
                            icon: const WebIcon('clock', size: 14),
                            label: Text(c.t('Retry save', 'إعادة الحفظ')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    InkWell(
                      onTap: saving.contains(id) || finishing
                          ? null
                          : () => save(item, null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          c.t('Clear answer', 'مسح الإجابة'),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      saving.contains(id)
                          ? c.t('Saving answer…', 'بنحفظ الإجابة…')
                          : c.t('All answers saved', 'كل الإجابات اتحفظت'),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: index == 0 ? null : () => setState(() => index--),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: scheme.surface,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(c.t('Previous', 'السابق')),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('quiz.next'),
                  onPressed: index == items.length - 1
                      ? null
                      : () => setState(() => index++),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: scheme.surface,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(c.t('Next', 'التالي')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            key: const ValueKey('quiz.submit'),
            onPressed: finishing ? null : finish,
            style: OutlinedButton.styleFrom(
              backgroundColor: index == items.length - 1
                  ? const Color(0xff1b3b25)
                  : const Color(0xff101612),
              foregroundColor: index == items.length - 1
                  ? const Color(0xffc9f0d3)
                  : const Color(0xff8bd5a2),
              side: BorderSide(
                color: index == items.length - 1
                    ? const Color(0xff76c78e)
                    : const Color(0xff4ca86b),
              ),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const WebIcon('check', size: 14, color: Color(0xff8bd5a2)),
            label: Text(
              finishing
                  ? c.t('Submitting…', 'جارٍ التسليم…')
                  : c.t('Submit quiz', 'سلّم الاختبار'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
