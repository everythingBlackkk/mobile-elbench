import 'package:flutter/material.dart';

/// The GET screen before its first document arrives. Quiz results use a
/// loading-only seed because results and active attempts share the same URL.
String initialScreenForPath(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) return '';
  final route = uri.path.replaceFirst(RegExp(r'/$'), '');
  const screens = {
    '': 'home',
    '/terms': 'terms',
    '/login': 'auth.login',
    '/signup': 'auth.signup',
    '/password/forgot': 'auth.forgot-password',
    '/community': 'community.index',
    '/community/subjects': 'community.subjects',
    '/forum': 'community.forum',
    '/ask-question': 'community.ask',
    '/question': 'community.question',
    '/moderate': 'community.moderate',
    '/profile': 'profile.show',
    '/profile/edit': 'profile.edit',
    '/profile/password/reset': 'profile.password-reset',
    '/people': 'people.index',
    '/inbox': 'ask.inbox',
    '/notifications': 'notifications.index',
    '/announcements': 'notifications.index',
    '/schedule': 'schedule.index',
    '/menu': 'content.menu',
    '/menu/notifications': 'notifications.settings',
    '/menu/login-activity': 'login-activity.index',
    '/hall-of-fame': 'content.hall',
    '/campus': 'content.campus',
    '/suggestions': 'content.suggestions',
    '/ai-chat': 'ai.index',
    '/quiz': 'quiz.index',
    '/quiz/history': 'quiz.history',
    '/quiz/manage': 'quiz.admin.index',
    '/quiz/manage/create': 'quiz.admin.form',
    '/admin': 'admin.index',
    '/admin/feed': 'admin.feed',
    '/admin/schedule': 'admin.schedule',
    '/admin/schedule-appearance': 'admin.schedule-appearance',
  };
  if (screens.containsKey(route)) return screens[route]!;
  for (final (pattern, screen) in <(String, String)>[
    (r'^/community/\d+/materials$', 'community.materials'),
    (r'^/community/\d+/notifications$', 'community.notifications'),
    (r'^/community/materials/\d+$', 'community.material'),
    (r'^/community/posts/\d+$', 'community.post'),
    (r'^/users/[^/]+$', 'profile.user'),
    (r'^/ask/\d+$', 'ask.show'),
    (
      r'^/(notifications/announcements|announcements)/\d+$',
      'notifications.announcement',
    ),
    (r'^/admin/post-reports/\d+/post$', 'admin.report-post'),
    (r'^/quiz/manage/\d+/edit$', 'quiz.admin.form'),
    (r'^/quiz/[^/]+$', 'quiz.attempt'),
  ]) {
    if (RegExp(pattern).hasMatch(route)) return screen;
  }
  return '';
}

class _PulseScope extends InheritedWidget {
  const _PulseScope({required super.child});
  @override
  bool updateShouldNotify(_PulseScope oldWidget) => false;
}

/// One render-layer opacity animation for a whole placeholder group. Nested
/// cards reuse their enclosing pulse instead of allocating tickers per row.
class SkeletonPulse extends StatelessWidget {
  const SkeletonPulse({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseScope>() != null
      ? child
      : _Pulse(child: child);
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: .62,
    value: 1,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation ||
        !TickerMode.valuesOf(context).enabled) {
      pulse.stop();
      pulse.value = 1;
    } else if (!pulse.isAnimating) {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PulseScope(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: FadeTransition(opacity: pulse, child: widget.child),
      ),
    ),
  );
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.ring = false,
  });
  final double? width;
  final double height, radius;
  final bool ring;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: .10),
      scheme.surface,
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ring ? null : fill,
        border: ring ? Border.all(color: fill, width: 11) : null,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.fraction = 1, this.height = 12});
  final double fraction, height;
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: fraction,
    child: SkeletonBlock(height: height),
  );
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.padding = 16});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

Widget _space([double height = 16]) => SizedBox(height: height);
Widget _lines({int count = 3, double first = 1}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < count; i++) ...[
      if (i > 0) _space(9),
      SkeletonLine(
        fraction: i == 0
            ? first
            : i == count - 1
            ? .64
            : .9,
      ),
    ],
  ],
);

Widget _heading({double fraction = .54, bool subtitle = true}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    SkeletonLine(fraction: fraction, height: 23),
    if (subtitle) ...[_space(12), const SkeletonLine(fraction: .78)],
  ],
);

Widget _slots(int count, double height, {double radius = 12}) => Row(
  children: [
    for (var i = 0; i < count; i++) ...[
      if (i > 0) const SizedBox(width: 8),
      Expanded(
        child: SkeletonBlock(height: height, radius: radius),
      ),
    ],
  ],
);

Widget _person({double size = 38, bool action = false}) => Row(
  children: [
    SkeletonBlock(width: size, height: size, radius: size / 2),
    const SizedBox(width: 10),
    Expanded(child: _lines(count: 2, first: .5)),
    if (action) ...[
      const SizedBox(width: 10),
      const SkeletonBlock(width: 24, height: 24, radius: 12),
    ],
  ],
);

class SkeletonPostCard extends StatelessWidget {
  const SkeletonPostCard({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => SkeletonCard(
    padding: 14,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _person(action: true),
        _space(18),
        _lines(count: compact ? 2 : 3),
        if (!compact) ...[_space(22), _slots(3, 18)],
      ],
    ),
  );
}

class SkeletonComment extends StatelessWidget {
  const SkeletonComment({super.key, this.reply = false});
  final bool reply;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: reply ? 34 : 0, bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBlock(width: 32, height: 32, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SkeletonCard(padding: 12, child: _lines(count: 3, first: .4)),
              _space(9),
              const SkeletonLine(fraction: .48, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Each layout follows its loaded screen's major blocks; no network data,
/// images, gestures, or text measurement is needed while it is loading.
class ScreenSkeleton extends StatelessWidget {
  const ScreenSkeleton({super.key, required this.screen, this.path = ''});
  final String screen, path;

  String get family => switch (screen) {
    'community.index' =>
      (Uri.tryParse(path)?.queryParameters['q'] ?? '').trim().isNotEmpty
          ? 'homeSearch'
          : 'home',
    'profile.show' || 'profile.user' => 'profile',
    'community.forum' => 'forum',
    'community.post' || 'admin.report-post' => 'post',
    'community.question' => 'question',
    'notifications.index' => 'notifications',
    'community.notifications' => 'notices',
    'ask.inbox' => 'inbox',
    'ask.show' => 'ask',
    'notifications.announcement' => 'announcement',
    'schedule.index' => 'schedule',
    'quiz.index' => 'quizOverview',
    'quiz.history' => 'quizHistory',
    'quiz.result' => 'quizResult',
    'quiz.attempt' => 'quizAttempt',
    'community.materials' => 'materials',
    'community.material' => 'material',
    'community.subjects' => 'subjects',
    'content.campus' => 'campus',
    'people.index' => 'people',
    'content.hall' => 'hall',
    'profile.edit' => 'profileEditor',
    'profile.password-reset' => 'security',
    'community.ask' || 'content.suggestions' || 'quiz.admin.form' => 'editor',
    'content.menu' => 'menu',
    'notifications.settings' => 'preferences',
    'login-activity.index' => 'loginActivity',
    'admin.feed' || 'community.moderate' => 'moderation',
    'admin.schedule' => 'scheduleAdmin',
    'admin.schedule-appearance' => 'appearance',
    'admin.index' || 'quiz.admin.index' => 'admin',
    'ai.index' || 'ai.chat' => 'chat',
    'auth.login' || 'auth.signup' || 'auth.forgot-password' => 'security',
    _ => 'information',
  };

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: ListView(
      key: ValueKey('skeleton.$family'),
      physics: const NeverScrollableScrollPhysics(),
      padding: family == 'profile'
          ? EdgeInsets.zero
          : EdgeInsets.fromLTRB(
              family == 'schedule' ? 18 : 10,
              family == 'schedule' ? 24 : 22,
              family == 'schedule' ? 18 : 10,
              24,
            ),
      children: _layout(context),
    ),
  );

  List<Widget> _layout(BuildContext context) => switch (family) {
    'home' => _home(),
    'homeSearch' => [
      _field(height: 56),
      _space(28),
      _heading(),
      _space(24),
      const SkeletonPostCard(),
      _space(12),
      const SkeletonPostCard(),
    ],
    'profile' => _profile(context),
    'forum' => _forum(),
    'post' || 'question' => [
      const SkeletonPostCard(),
      _space(24),
      if (family == 'question') ...[_field(height: 110), _space(20)],
      _heading(fraction: .35, subtitle: false),
      _space(20),
      const SkeletonComment(),
      const SkeletonComment(reply: true),
      const SkeletonComment(),
    ],
    'notifications' => [_tabs(3), _space(20), ..._activityRows()],
    'notices' => [
      _heading(fraction: .6),
      _space(22),
      for (var i = 0; i < 4; i++) ...[
        SkeletonCard(
          child: Column(children: [_person(size: 32), _space(16), _lines()]),
        ),
        _space(12),
      ],
    ],
    'inbox' => [
      _tabs(2),
      _space(20),
      for (var i = 0; i < 3; i++) ...[_messageCard(), _space(14)],
    ],
    'ask' => [
      _messageCard(),
      _space(20),
      _field(height: 132),
      _space(),
      _slots(1, 44),
    ],
    'announcement' => [
      _person(),
      _space(28),
      _heading(fraction: .82, subtitle: false),
      _space(24),
      SkeletonCard(
        child: Column(
          children: [_lines(count: 6), _space(24), _lines(count: 5)],
        ),
      ),
    ],
    'schedule' => _schedule(),
    'quizOverview' => _quizOverview(),
    'quizHistory' => _quizHistory(),
    'quizResult' => _quizResult(),
    'quizAttempt' => _quizAttempt(),
    'subjects' => [
      _lines(count: 1, first: .84),
      _space(16),
      _slots(2, 48),
      _space(24),
      SkeletonCard(child: _lines(count: 3)),
      _space(18),
      _slots(3, 36),
      _space(16),
      _grid(height: 170),
      _space(12),
      _grid(height: 170),
    ],
    'materials' => [
      _lines(count: 2),
      _space(18),
      _slots(2, 40),
      _space(20),
      _field(height: 48),
      _space(14),
      _slots(4, 32),
      _space(20),
      ..._fileRows(),
    ],
    'material' => [
      _person(size: 42),
      _space(18),
      _slots(2, 36),
      _space(20),
      SkeletonBlock(
        key: const ValueKey('skeleton.material.preview'),
        height: 420,
        radius: 18,
      ),
    ],
    'campus' => [
      SkeletonBlock(
        key: const ValueKey('skeleton.campus.map'),
        height: (MediaQuery.sizeOf(context).height * .68).clamp(240, 700),
        radius: 20,
      ),
    ],
    'people' => [
      _field(height: 52),
      _space(24),
      for (var i = 0; i < 5; i++) ...[
        SkeletonCard(child: _person(size: 48, action: true)),
        _space(10),
      ],
    ],
    'hall' => _hall(),
    'profileEditor' => [
      const SkeletonBlock(height: 150, radius: 20),
      _space(12),
      const Align(
        alignment: AlignmentDirectional.centerStart,
        child: SkeletonBlock(width: 90, height: 90, radius: 45),
      ),
      _space(24),
      ..._fields(5),
      _slots(2, 44),
    ],
    'editor' => [
      _heading(),
      _space(28),
      _field(),
      _space(22),
      _field(height: 160),
      _space(22),
      _slots(2, 44),
    ],
    'security' => [_heading(), _space(28), ..._fields(3), _slots(1, 48)],
    'menu' => [
      ..._settingsRows(5),
      _space(20),
      _heading(fraction: .4, subtitle: false),
      _space(20),
      ..._settingsRows(5),
    ],
    'preferences' => [
      SkeletonCard(
        child: Column(children: [_person(size: 42), _space(22), _slots(1, 42)]),
      ),
      _space(28),
      _heading(fraction: .46, subtitle: false),
      _space(16),
      ..._settingsRows(5, switches: true),
    ],
    'loginActivity' => [
      _lines(count: 2),
      _space(24),
      ..._activityRows(cards: true),
    ],
    'moderation' => [
      _heading(),
      _space(22),
      _field(height: 48),
      _space(18),
      _tabs(2),
      _space(18),
      for (var i = 0; i < 3; i++) ...[const SkeletonPostCard(), _space(10)],
    ],
    'scheduleAdmin' => [
      _heading(),
      _space(24),
      _slots(3, 44),
      _space(18),
      ..._fields(3),
      ..._fileRows(),
    ],
    'appearance' => [
      _heading(),
      _space(22),
      _slots(2, 40),
      _space(22),
      SkeletonCard(child: _lines(count: 6)),
      _space(24),
      _heading(fraction: .45, subtitle: false),
      _space(18),
      _slots(4, 52),
    ],
    'admin' => [
      _heading(),
      _space(20),
      _slots(3, 36),
      _space(18),
      _grid(height: 100),
      _space(20),
      _field(height: 46),
      _space(20),
      ..._fileRows(),
    ],
    'chat' => [
      Center(
        child: Column(
          children: [
            const SkeletonBlock(width: 76, height: 76, radius: 38),
            _space(22),
            _heading(fraction: .66),
          ],
        ),
      ),
      _space(36),
      _grid(height: 92),
      _space(14),
      _grid(height: 92),
      _space(80),
      _field(height: 56),
    ],
    _ => [
      _heading(fraction: .7),
      _space(32),
      for (var i = 0; i < 3; i++) ...[
        SkeletonCard(
          child: Column(
            children: [
              _heading(fraction: .55, subtitle: false),
              _space(22),
              _lines(count: 5),
            ],
          ),
        ),
        _space(18),
      ],
    ],
  };

  Widget _tabs(int count) => Padding(
    key: const ValueKey('skeleton.tabs'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: _slots(count, 26, radius: 14),
  );

  Widget _field({double height = 50}) => SkeletonCard(
    padding: 14,
    child: SizedBox(
      height: height - 28,
      child: const SkeletonLine(fraction: .62),
    ),
  );

  List<Widget> _fields(int count) => [
    for (var i = 0; i < count; i++) ...[
      const SkeletonLine(fraction: .34, height: 11),
      _space(9),
      _field(),
      _space(22),
    ],
  ];

  Widget _grid({required double height}) => Row(
    children: [
      for (var i = 0; i < 2; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(
          child: SkeletonCard(
            child: Column(
              children: [
                SkeletonBlock(height: height - 60, radius: 14),
                _space(14),
                const SkeletonLine(fraction: .7),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  List<Widget> _home() => [
    SkeletonCard(padding: 12, child: _person(size: 44, action: true)),
    _space(28),
    _field(height: 56),
    _space(48),
    _heading(),
    _space(40),
    const SkeletonBlock(
      key: ValueKey('skeleton.home.events'),
      height: 182,
      radius: 20,
    ),
    _space(72),
    _heading(fraction: .68),
    _space(40),
    KeyedSubtree(
      key: const ValueKey('skeleton.home.communities'),
      child: _grid(height: 312),
    ),
    _space(92),
    _heading(),
    _space(16),
    const SkeletonPostCard(),
  ];

  List<Widget> _profile(BuildContext context) {
    final diameter = MediaQuery.sizeOf(context).width < 360 ? 100.0 : 116.0;
    return [
      SizedBox(
        height: 240,
        child: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SkeletonBlock(
                key: ValueKey('skeleton.profile.banner'),
                height: 184,
                radius: 0,
              ),
            ),
            PositionedDirectional(
              start: 14,
              top: 126,
              child: SkeletonBlock(
                key: const ValueKey('skeleton.profile.avatar'),
                width: diameter,
                height: diameter,
                radius: diameter / 2,
              ),
            ),
            PositionedDirectional(
              start: diameter + 26,
              end: 12,
              top: 194,
              child: _slots(3, 30),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(fraction: .52),
            _space(18),
            const SkeletonLine(fraction: .35, height: 28),
            _space(18),
            _lines(count: 2, first: .85),
            _space(20),
            _slots(2, 18),
            _space(22),
            _slots(1, 44),
            _space(34),
            _tabs(3),
            _space(16),
            const SkeletonPostCard(),
          ],
        ),
      ),
    ];
  }

  List<Widget> _forum() => [
    const SkeletonBlock(
      key: ValueKey('skeleton.forum.banner'),
      height: 140,
      radius: 20,
    ),
    _space(24),
    _heading(fraction: .7),
    _space(22),
    _slots(2, 42),
    _space(24),
    _messageCard(),
    _space(24),
    _field(height: 48),
    _space(20),
    const SkeletonPostCard(compact: true),
    _space(12),
    const SkeletonPostCard(compact: true),
  ];

  Widget _messageCard() => SkeletonCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _person(size: 34, action: true),
        _space(18),
        _lines(),
        _space(18),
        const SkeletonLine(fraction: .38, height: 28),
      ],
    ),
  );

  List<Widget> _activityRows({bool cards = false}) => [
    for (var i = 0; i < 6; i++) ...[
      if (cards)
        SkeletonCard(child: _person(size: 40))
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: _person(size: 42),
        ),
      _space(cards ? 12 : 6),
    ],
  ];

  List<Widget> _fileRows() => [
    for (var i = 0; i < 4; i++) ...[
      SkeletonCard(
        child: Row(
          children: [
            const SkeletonBlock(width: 42, height: 50, radius: 10),
            const SizedBox(width: 12),
            Expanded(child: _lines(count: 2, first: .76)),
            const SizedBox(width: 12),
            const SkeletonBlock(width: 24, height: 24, radius: 12),
          ],
        ),
      ),
      _space(12),
    ],
  ];

  List<Widget> _settingsRows(int count, {bool switches = false}) => [
    for (var i = 0; i < count; i++)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        child: Row(
          children: [
            const SkeletonBlock(width: 24, height: 24),
            const SizedBox(width: 14),
            const Expanded(child: SkeletonLine(fraction: .66)),
            SkeletonBlock(
              width: switches ? 40 : 14,
              height: switches ? 24 : 14,
              radius: 16,
            ),
          ],
        ),
      ),
  ];

  List<Widget> _schedule() => [
    _heading(fraction: .48, subtitle: false),
    _space(24),
    _slots(3, 40),
    _space(16),
    KeyedSubtree(
      key: const ValueKey('skeleton.schedule.days'),
      child: _slots(7, 86, radius: 20),
    ),
    _space(24),
    SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(fraction: .55),
          _space(24),
          for (var i = 0; i < 2; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBlock(width: 42, height: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: SkeletonCard(
                    child: Column(
                      children: [_lines(count: 3), _space(14), _slots(2, 22)],
                    ),
                  ),
                ),
              ],
            ),
            _space(18),
          ],
        ],
      ),
    ),
  ];

  List<Widget> _quizOverview() => [
    _heading(fraction: .88),
    _space(20),
    _slots(3, 18),
    _space(18),
    const Align(
      alignment: AlignmentDirectional.centerStart,
      child: SkeletonBlock(width: 120, height: 38, radius: 20),
    ),
    _space(30),
    _heading(fraction: .48, subtitle: false),
    _space(18),
    Center(child: _scoreRing(108)),
    _space(18),
    _grid(height: 90),
    _space(24),
    _heading(fraction: .55, subtitle: false),
    _space(18),
    ..._fileRows(),
  ];

  List<Widget> _quizHistory() => [
    _heading(fraction: .72),
    _space(22),
    _grid(height: 100),
    _space(20),
    _slots(2, 44),
    _space(24),
    for (var i = 0; i < 2; i++) ...[
      SkeletonCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _person(size: 40),
            _space(18),
            _slots(2, 26),
            _space(16),
            SkeletonCard(child: _slots(2, 56)),
            _space(16),
            _slots(1, 42),
          ],
        ),
      ),
      _space(12),
    ],
  ];

  Widget _scoreRing(double size) => SkeletonBlock(
    key: const ValueKey('skeleton.quiz.score'),
    width: size,
    height: size,
    radius: size / 2,
    ring: true,
  );

  List<Widget> _quizResult() => [
    _heading(fraction: .7),
    _space(26),
    SkeletonCard(
      child: Column(
        children: [
          _heading(fraction: .6, subtitle: false),
          _space(24),
          _scoreRing(132),
          _space(24),
          _slots(3, 44),
          _space(24),
          _slots(2, 40),
        ],
      ),
    ),
    _space(28),
    _heading(fraction: .6, subtitle: false),
    _space(20),
    SkeletonCard(child: _lines(count: 5)),
  ];

  List<Widget> _quizAttempt() => [
    _slots(2, 34),
    _space(20),
    _slots(5, 34),
    _space(24),
    SkeletonCard(
      key: const ValueKey('skeleton.quiz.question'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonLine(fraction: .36, height: 24),
          _space(22),
          _lines(count: 3),
          _space(26),
          for (var i = 0; i < 4; i++) ...[
            SkeletonCard(
              padding: 16,
              child: Row(
                children: [
                  const SkeletonBlock(width: 24, height: 24, radius: 12),
                  const SizedBox(width: 12),
                  const Expanded(child: SkeletonLine(fraction: .76)),
                ],
              ),
            ),
            _space(10),
          ],
        ],
      ),
    ),
    _space(18),
    _slots(2, 44),
  ];

  List<Widget> _hall() => [
    _heading(fraction: .65),
    _space(38),
    SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SkeletonBlock(
                    width: i == 1 ? 70 : 54,
                    height: i == 1 ? 70 : 54,
                    radius: 40,
                  ),
                  _space(12),
                  SkeletonBlock(height: i == 1 ? 94 : 64, radius: 14),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    _space(30),
    ..._activityRows(),
  ];
}
