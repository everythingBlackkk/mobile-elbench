import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'error_artwork.dart';

/// Shared recoverable page failure, including offline startup.
class ErrorPanel extends StatefulWidget {
  const ErrorPanel({
    super.key,
    required this.error,
    required this.retry,
    this.retrying = false,
  });
  final Object error;
  final VoidCallback retry;
  final bool retrying;

  @override
  State<ErrorPanel> createState() => _ErrorPanelState();
}

class _ErrorPanelState extends State<ErrorPanel> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar';
    String t(String en, String arabic) => ar ? arabic : en;
    final failure = widget.error is ApiFailure
        ? widget.error as ApiFailure
        : null;
    final (title, message) = switch (failure?.kind) {
      ApiFailureKind.connection => (
        t('Check your internet connection', 'تحقّق من اتصال الإنترنت'),
        t(
          'Unable to connect. Check Wi-Fi or mobile data, then try again.',
          'تعذّر الاتصال. تأكد من اتصالك بالواي فاي أو بيانات الهاتف، ثم حاول مجددًا.',
        ),
      ),
      ApiFailureKind.timeout => (
        t('Connection timed out', 'انتهت مهلة الاتصال'),
        t(
          'Check your internet connection and try again.',
          'تأكد من اتصالك بالإنترنت، ثم حاول مجددًا.',
        ),
      ),
      _ when failure?.status == 404 => (
        t('Page not found', 'الصفحة غير موجودة'),
        t(
          'This page may have moved or been removed. Please try again.',
          'قد تكون الصفحة اتنقلت أو اتحذفت. حاول مجددًا.',
        ),
      ),
      _ => (
        t('Something went wrong', 'حدث خطأ'),
        t(
          'We couldn’t load this page. Please try again.',
          'تعذّر تحميل الصفحة. حاول مجددًا.',
        ),
      ),
    };
    final theme = Theme.of(context);
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(
            300.0,
            math.max(0.0, constraints.maxWidth - 48),
          );
          final artWidth = constraints.hasBoundedHeight
              ? math.min(width, constraints.maxHeight * .44 * 950 / 847)
              : width;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : 0,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: artWidth,
                          height: artWidth * 847 / 950,
                          child: const AnimatedErrorArtwork(
                            key: ValueKey('error.artwork'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            title,
                            key: const ValueKey('error.title'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          key: const ValueKey('error.retry'),
                          onPressed: widget.retrying ? null : widget.retry,
                          icon: widget.retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            widget.retrying
                                ? t('Trying again…', 'جاري المحاولة…')
                                : t('Try again', 'حاول مجددًا'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
