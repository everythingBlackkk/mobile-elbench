import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'api.dart';
import 'image_cache.dart';
import 'text_direction.dart';
import 'web_home.dart' show webBorder, webMuted, webSecondary;

/// Web links in member text: the same rule as the server (http(s) or "www.",
/// up to a space, quote or Arabic punctuation; sentence punctuation after a
/// link is not part of it).
final _linkPattern = RegExp(
  r'''\b(?:https?://|www\.)[^\s<>"'،؛؟۔]+''',
  caseSensitive: false,
);
final _trailing = RegExp(r'[.,;:!?)\]}،؛؟۔]+$');

/// Where links appear in [text]: [start, end, url].
List<(int, int, String)> findLinks(String text) => [
  for (final match in _linkPattern.allMatches(text))
    if (match.group(0)!.replaceFirst(_trailing, '') case final shown
        when shown.isNotEmpty)
      (
        match.start,
        match.start + shown.length,
        shown.toLowerCase().startsWith('www.') ? 'https://$shown' : shown,
      ),
];

/// Opens a link in the browser (or the app that owns it, such as YouTube).
Future<void> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// What a shared link shows below a post, comment, question or answer:
/// a YouTube player, an X post or a page card (from the server's
/// `link_preview`).
class LinkPreviewView extends StatelessWidget {
  const LinkPreviewView({
    super.key,
    required this.preview,
    required this.api,
    this.compact = false,
  });

  final Json preview;
  final MobileApi api;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final kind = value(preview['kind']);
    final card = switch (kind) {
      'youtube' => _YouTubePreview(preview: preview),
      'tweet' => _TweetCard(preview: preview),
      _ => _PageCard(preview: preview, compact: compact),
    };
    return Padding(
      key: ValueKey('link.preview.${value(preview['url'])}'),
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: webSecondary(context),
            border: Border.all(color: webBorder(context)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: card,
        ),
      ),
    );
  }
}

/// A thumbnail with YouTube's play button; tapping it starts the
/// privacy-enhanced player in place. No player loads until then.
class _YouTubePreview extends StatefulWidget {
  const _YouTubePreview({required this.preview});
  final Json preview;
  @override
  State<_YouTubePreview> createState() => _YouTubePreviewState();
}

class _YouTubePreviewState extends State<_YouTubePreview> {
  WebViewController? _player;

  String get _id => value(widget.preview['video_id']);

  void _play() {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(_id)) return;
    // YouTube refuses embedded players whose page has no origin, so the
    // player sits in a tiny page that names ElBench as its origin.
    final html =
        '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000}iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style></head>'
        '<body><iframe src="https://www.youtube-nocookie.com/embed/$_id?autoplay=1&playsinline=1&rel=0&modestbranding=1" '
        'allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen '
        'referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>';
    // The tap on the thumbnail is the member's gesture, so the player starts
    // playing at once instead of waiting for a second tap inside it.
    final platform = WebViewPlatform.instance;
    final controller =
        WebViewController.fromPlatformCreationParams(
            platform is WebKitWebViewPlatform
                ? WebKitWebViewControllerCreationParams(
                    allowsInlineMediaPlayback: true,
                    mediaTypesRequiringUserAction: const {},
                  )
                : const PlatformWebViewControllerCreationParams(),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              // Links inside the player (the YouTube logo, "watch on YouTube")
              // open outside the app rather than inside the small frame.
              onNavigationRequest: (request) {
                final url = request.url;
                if (url.startsWith('https://elbench.com') ||
                    url.startsWith('about:') ||
                    url.contains('youtube-nocookie.com/embed/') ||
                    url.contains('youtube.com/embed/')) {
                  return NavigationDecision.navigate;
                }
                openExternalLink(url);
                return NavigationDecision.prevent;
              },
            ),
          );
    if (controller.platform case final AndroidWebViewController android) {
      android.setMediaPlaybackRequiresUserGesture(false);
    }
    controller.loadHtmlString(html, baseUrl: 'https://elbench.com/');
    setState(() => _player = controller);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final title = value(widget.preview['title']);
    final image = value(widget.preview['image']);
    final player = _player;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: player != null
              ? WebViewWidget(
                  key: ValueKey('link.youtube.player.$_id'),
                  controller: player,
                )
              : Semantics(
                  button: true,
                  label: title.isEmpty ? 'Play video' : 'Play video: $title',
                  child: GestureDetector(
                    key: ValueKey('link.youtube.play.$_id'),
                    onTap: _play,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        if (image.isNotEmpty)
                          Image(
                            image: CachedNetworkImage(image, width: 960),
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        const Center(child: _YouTubeButton()),
                      ],
                    ),
                  ),
                ),
        ),
        if (title.isNotEmpty)
          InkWell(
            onTap: () => openExternalLink(value(widget.preview['url'])),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: contentDirection(title),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _YouTubeButton extends StatelessWidget {
  const _YouTubeButton();
  @override
  Widget build(BuildContext context) => Container(
    width: 68,
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xffff0000),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 8)],
    ),
    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
  );
}

class _TweetCard extends StatelessWidget {
  const _TweetCard({required this.preview});
  final Json preview;
  @override
  Widget build(BuildContext context) {
    final text = value(preview['description']);
    return InkWell(
      onTap: () => openExternalLink(value(preview['url'])),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '𝕏',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value(preview['author']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              textDirection: contentDirection(text),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              'x.com',
              style: TextStyle(fontSize: 12, color: webMuted(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.preview, required this.compact});
  final Json preview;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final image = value(preview['image']);
    final title = value(preview['title']);
    final description = value(preview['description']);
    final site = value(
      preview['site'],
      Uri.tryParse(value(preview['url']))?.host.replaceFirst('www.', '') ?? '',
    );
    return InkWell(
      onTap: () => openExternalLink(value(preview['url'])),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image.isNotEmpty && !compact)
            AspectRatio(
              aspectRatio: 1.91,
              child: Image(
                image: CachedNetworkImage(image, width: 960),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: webBorder(context)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  site.toLowerCase(),
                  style: TextStyle(fontSize: 12, color: webMuted(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: contentDirection(title),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: contentDirection(description),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: webMuted(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
