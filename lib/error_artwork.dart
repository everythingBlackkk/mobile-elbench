import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The supplied SVG uses SMIL path morphs, transforms and motion paths.
/// A local system webview preserves those animations without a network request.
class AnimatedErrorArtwork extends StatefulWidget {
  const AnimatedErrorArtwork({super.key});
  static const asset = 'assets/error-cat.svg';

  @override
  State<AnimatedErrorArtwork> createState() => _AnimatedErrorArtworkState();
}

class _AnimatedErrorArtworkState extends State<AnimatedErrorArtwork>
    with WidgetsBindingObserver {
  static final _source = rootBundle.loadString(AnimatedErrorArtwork.asset);
  static final _still = _source.then(
    (svg) =>
        svg.replaceAll(RegExp(r'<animate(?:Transform|Motion)?\b[^>]*/>'), ''),
  );
  WebViewController? controller;
  bool ready = false, _starting = false, _failed = false;
  bool _reduce = false, _visible = true, _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.of(context).accessibleNavigation;
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_starting &&
        WebViewPlatform.instance != null &&
        !kIsWeb &&
        [
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
        ].contains(defaultTargetPlatform)) {
      _starting = true;
      unawaited(_start());
    }
    unawaited(_applyMotion());
  }

  Future<void> _start() async {
    try {
      final svg = await _source;
      if (!mounted) return;
      final view = WebViewController();
      await view.setBackgroundColor(Colors.transparent);
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await view.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url == 'about:blank' ||
                  request.url.startsWith('data:text/html')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => ready = true);
            await _applyMotion();
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame != false) {
              setState(() => _failed = true);
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() => controller = view);
      await view.loadHtmlString(errorArtworkDocument(svg));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _applyMotion() async {
    if (!ready || controller == null || _failed) return;
    final pause = _reduce || !_visible || !_active;
    try {
      await controller!.runJavaScript(
        "document.querySelector('svg').${pause ? 'pause' : 'unpause'}Animations();",
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    unawaited(_applyMotion());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!ready || _failed)
            FutureBuilder<String>(
              future: _still,
              builder: (_, snapshot) => snapshot.hasData
                  ? SvgPicture.string(snapshot.data!, fit: BoxFit.contain)
                  : const SizedBox.shrink(),
            ),
          if (controller != null && !_failed)
            Opacity(
              opacity: ready ? 1 : 0,
              child: WebViewWidget(controller: controller!),
            ),
        ],
      ),
    ),
  );
}

String errorArtworkDocument(String svg) => '''<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<style>
html,body{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:transparent}
svg{display:block;width:100%;height:100%;pointer-events:none}
</style></head><body>$svg</body></html>''';
