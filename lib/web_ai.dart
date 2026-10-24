import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart';
import 'text_direction.dart';
import 'web_home.dart';
import 'web_style.dart';

class WebAiChat extends StatefulWidget {
  const WebAiChat({super.key, required this.page});
  final NativePageState page;
  @override
  State<WebAiChat> createState() => _WebAiChatState();
}

class _WebAiChatState extends State<WebAiChat>
    with SingleTickerProviderStateMixin {
  final input = TextEditingController(), scroll = ScrollController();
  final messages = <(String, bool, bool)>[];
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool busy = false;
  NativePageState get p => widget.page;
  @override
  void initState() {
    super.initState();
    messages.add((
      p.c.t(
        "Hi! I'm Tamer Elgayar, your AI assistant. I'm not ready to work yet, but I'll be here soon. Stay tuned!",
        'عامل إيه؟ أنا تامر الجيار.',
      ),
      false,
      false,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !busy) {
      motion.stop();
    } else {
      motion.repeat();
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    motion.dispose();
    super.dispose();
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    }
  });
  Future<void> send() async {
    if (busy || input.text.trim().isEmpty) return;
    final text = input.text.trim();
    input.clear();
    setState(() {
      busy = true;
      messages.add((text, true, false));
    });
    bottom();
    if (!MediaQuery.disableAnimationsOf(context)) motion.repeat();
    try {
      final result = await p.c.action('POST', '/ai-chat', {
        'message': text,
        'ajax_request': true,
      });
      if (mounted) {
        setState(
          () => messages.add((
            value(result['message']),
            false,
            result['success'] != true,
          )),
        );
      }
    } catch (e) {
      if (mounted) setState(() => messages.add(('$e', false, true)));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        motion.stop();
        bottom();
      }
    }
  }

  Widget logo(double size) => ClipOval(
    child: Image.asset(
      'assets/ai-logo.jpg',
      width: size,
      height: size,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -.6),
    ),
  );
  Widget bubble((String, bool, bool) message) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = dark ? Colors.white : Colors.black;
    final child = Container(
      constraints: BoxConstraints(
        maxWidth:
            (MediaQuery.sizeOf(context).width - 24) * .85 -
            (message.$2 ? 0 : 36),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: message.$3
            ? const Color(0xffffeeee)
            : message.$2
            ? primary
            : webSecondary(context),
        border: message.$2
            ? null
            : Border.all(
                color: message.$3
                    ? const Color(0xffffcccc)
                    : webBorder(context),
              ),
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(18),
          topEnd: const Radius.circular(18),
          bottomStart: Radius.circular(message.$2 ? 18 : 4),
          bottomEnd: Radius.circular(message.$2 ? 4 : 18),
        ),
      ),
      child: Text(
        message.$1,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: message.$3
              ? const Color(0xffcc3333)
              : message.$2
              ? Theme.of(context).scaffoldBackgroundColor
              : null,
        ),
      ),
    );
    final row = message.$2
        ? Align(alignment: AlignmentDirectional.centerEnd, child: child)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 4), child: logo(28)),
              const SizedBox(width: 8),
              Flexible(child: child),
            ],
          );
    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - v)),
          child: child,
        ),
      ),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = dark ? Colors.white : Colors.black;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            children: [
              for (final (i, message) in messages.indexed)
                KeyedSubtree(
                  key: ValueKey('ai.message.$i'),
                  child: bubble(message),
                ),
              if (busy)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: webSecondary(context),
                      border: Border.all(color: webBorder(context)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        logo(24),
                        const SizedBox(width: 10),
                        for (var i = 0; i < 3; i++)
                          AnimatedBuilder(
                            animation: motion,
                            builder: (_, _) => Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Transform.scale(
                                scale: MediaQuery.disableAnimationsOf(context)
                                    ? 1
                                    : math.max(
                                        0,
                                        math.sin(
                                          (motion.value - i * .12) *
                                              2 *
                                              math.pi,
                                        ),
                                      ),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 8, 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border.all(color: webBorder(context), width: 1.5),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .04),
                        offset: const Offset(0, 8),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AdaptiveTextField(
                          controller: input,
                          field: (direction) => TextField(
                            controller: input,
                            textDirection: direction,
                            enabled: !busy,
                            onSubmitted: (_) => send(),
                            textInputAction: TextInputAction.send,
                            maxLength: 2000,
                            style: const TextStyle(fontSize: 16, height: 1.4),
                            decoration: InputDecoration(
                              hintText: p.c.t(
                                'Ask anything...',
                                'اسأل أي حاجة...',
                              ),
                              counterText: '',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: IconButton(
                          onPressed: busy ? null : send,
                          style: IconButton.styleFrom(
                            backgroundColor: primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: RotatedBox(
                            quarterTurns: 1,
                            child: WebIcon(
                              'send',
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: .4,
                  child: Text(
                    p.c
                        .t(
                          'Tamer Elgayar ▪ Coming soon',
                          'تامر الجيار ▪ استنّانا قريب',
                        )
                        .toUpperCase(),
                    style: TextStyle(
                      color: webMuted(context),
                      fontSize: 9,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w700,
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
}
