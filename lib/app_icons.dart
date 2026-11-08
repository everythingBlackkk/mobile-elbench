import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons drawn from inline SVG rather than the Material icon font. Adding a
/// new Material icon changes the app's tree-shaken font, which an
/// over-the-air (Shorebird) patch cannot ship; these paths need no asset.
abstract final class AppIcons {
  static const replyArrow =
      'M19 15l-6 6-1.42-1.42L15.17 16H4V4h2v10h9.17l-3.59-3.58L13 9l6 6z';
  static const chevronUp = 'M7.41 15.41 12 10.83l4.59 4.58L18 14l-6-6-6 6z';
  static const play =
      'M8 6.82v10.36c0 .79.87 1.27 1.54.84l8.14-5.18c.62-.39.62-1.29 0-1.69L9.54 5.98C8.87 5.55 8 6.03 8 6.82z';
}

/// A 24×24 SVG path painted like an [Icon]: it takes its colour and size
/// from the surrounding [IconTheme] (buttons set it) unless given.
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.path, {super.key, this.size, this.color});

  final String path;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="$path"/></svg>',
      width: side,
      height: side,
      excludeFromSemantics: true,
      colorFilter: ColorFilter.mode(
        color ?? theme.color ?? const Color(0xff000000),
        BlendMode.srcIn,
      ),
    );
  }
}
