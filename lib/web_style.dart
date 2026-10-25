import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'api.dart';
import 'image_cache.dart';

// Paths are shared with Laravel components/ui-icon.blade.php.
const _paths = <String, String>{
  'calendar':
      'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
  'location':
      'M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0zM15 11a3 3 0 11-6 0 3 3 0 016 0z',

  "compass": "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM16 8l-3 5-5 3 3-5 5-3Z",
  "search": "M11 19a8 8 0 1 1 0-16 8 8 0 0 1 0 16Zm10 2-4.35-4.35",
  "chart": "M4 20V10m8 10V4m8 16v-7M2 22h20",
  "map": "m3 5 6-3 6 3 6-3v17l-6 3-6-3-6 3V5Zm6-3v17m6-14v17",
  "send": "M12 20V4m-7 7 7-7 7 7",
  "paper-plane": "m22 2-7 20-4-9-9-4L22 2ZM22 2 11 13",
  "ai":
      "M9 3h6m-3 0v3M5 8h14v11H5zM5 12H3v4h2m14-4h3v4h-3m-10-4h.01M15 12h.01M9 16h6",
  "back": "m15 5-7 7 7 7",
  "menu": "M4 7h16M4 12h16M4 17h16",
  "chevron-down": "m5 9 7 7 7-7",
  "chevron-right": "m9 5 7 7-7 7",
  "user": "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM5 21v-2a7 7 0 0 1 14 0v2",
  "building": "M5 21V3h14v18M3 21h18M9 7h1m4 0h1M9 11h1m4 0h1M10 21v-6h4v6",
  "users":
      "M15 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM5 21v-2a7 7 0 0 1 14 0v2M18 4a3 3 0 0 1 0 6m3 10v-2a5 5 0 0 0-3-4",
  "book":
      "M12 5c-3-2-6-2-9-1v15c3-1 6-1 9 1 3-2 6-2 9-1V4c-3-1-6-1-9 1Zm0 0v15",
  "trophy":
      "M8 3h8v6a4 4 0 0 1-8 0V3ZM8 5H4v2a4 4 0 0 0 4 4m8-6h4v2a4 4 0 0 1-4 4m-4 2v5m-4 3h8m-6-3h4v3h-4v-3Z",
  "moon": "M21 13a9 9 0 0 1-10-10A9 9 0 1 0 21 13Z",
  "monitor": "M3 4h18v13H3V4Zm9 13v4m-4 0h8",
  "phone":
      "M7 2h10a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Zm3 3h4m-3 14h2",
  "tablet":
      "M5 2h14a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1Zm6 17h2",
  "laptop": "M5 3h14v13H5V3ZM2 20l3-4h14l3 4H2Zm8-1h4",
  "message":
      "M21 11a8 8 0 0 1-8 8H7l-4 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v4ZM7 8h10M7 12h7",
  "clock": "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM12 7v5l3 2",
  "bell": "M18 8a6 6 0 0 0-12 0c0 7-3 8-3 9h18c0-1-3-2-3-9ZM10 21h4",
  "inbox": "M4 4h16l2 12v4H2v-4L4 4Zm-2 12h6l2 3h4l2-3h6",
  "reply": "m9 5-6 6 6 6M3 11h10a7 7 0 0 1 7 7v2",
  "heart":
      "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z",
  "post":
      "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm3 5h8M8 12h8M8 16h5",
  "graduation": "m2 8 10-5 10 5-10 5L2 8Zm4 2v6c4 3 8 3 12 0v-6m4-2v8",
  "settings":
      "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68h.08A1.65 1.65 0 0 0 10 3.17V3a2 2 0 0 1 4 0v.09A1.65 1.65 0 0 0 15 4.6a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.32 9v.08A1.65 1.65 0 0 0 20.83 10H21a2 2 0 0 1 0 4h-.09A1.65 1.65 0 0 0 19.4 15ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z",
  "logout": "M9 5H4v14h5m7-14 7 7-7 7m7-7H9",
  "check": "m5 12 4 4L19 6",
  "plus": "M12 5v14M5 12h14",
  "share": "M12 16V3m-4 4 4-4 4 4M7 10H5v11h14V10h-2",
  "flag": "M5 21V3m0 1c5-4 9 4 14 0v10c-5 4-9-4-14 0",
  "edit": "m16 3 5 5-12 12-6 1 1-6L16 3Z",
  "delete": "M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7",
  "lock": "M7 11V7a5 5 0 0 1 10 0v4M5 11h14v10H5V11Z",
  "globe": "M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z",
  "home":
      "M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6",
  "profile":
      "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
  "download": "M4 16v2a2 2 0 002 2h12a2 2 0 002-2v-2M7 10l5 5 5-5M12 15V3",
  "upload": "M4 16v2a2 2 0 002 2h12a2 2 0 002-2v-2M17 8l-5-5-5 5M12 3v12",
  "file":
      "M14 3H7a2 2 0 00-2 2v14a2 2 0 002 2h10a2 2 0 002-2V8l-5-5zM14 3v5h5M9 13h6M9 17h6",
  "image":
      "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2ZM3 16l5-5 4 4 3-3 6 6M16 8a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z",
  "sliders":
      "M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1M15 4v4M9 10v4M17 16v4",
};

final _svgByIcon = <String, String>{
  for (final entry in _paths.entries)
    entry.key:
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${entry.key == 'globe' ? '<circle cx="12" cy="12" r="9"/>' : ''}<path d="${entry.value}"/></svg>',
};
const _emptyIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none"/>';

ColorFilter svgColorFilter(Color color) => ColorFilter.mode(
  Color(0xff000000 | (color.toARGB32() & 0x00ffffff)),
  BlendMode.srcIn,
);

class WebIcon extends StatelessWidget {
  const WebIcon(this.name, {super.key, this.size = 20, this.color});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.string(
      _svgByIcon[name] ?? _emptyIconSvg,
      width: size,
      height: size,
      colorFilter: svgColorFilter(resolved),
    );
  }
}

class UserBadge extends StatelessWidget {
  const UserBadge({
    super.key,
    required this.api,
    required this.badge,
    this.large = false,
  });
  final MobileApi api;
  final dynamic badge;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final size = large ? 24.0 : 18.0;
    if ('$badge' == '1') {
      final cacheExtent = (size * MediaQuery.devicePixelRatioOf(context))
          .ceil();
      return networkImage(
        api.media('/Picture/blur-ver.png'),
        width: size,
        height: size,
        cacheWidth: cacheExtent,
        cacheHeight: cacheExtent,
        semanticLabel: 'Verified',
        errorBuilder: (_, _, _) =>
            Icon(Icons.verified, size: size, color: const Color(0xff3b82f6)),
      );
    }
    if ('$badge' == '3') {
      return SvgPicture.network(
        api.media('/Picture/gold-ver.svg'),
        width: size,
        height: size,
        semanticsLabel: 'Golden Verified',
        placeholderBuilder: (_) =>
            Icon(Icons.verified, size: size, color: const Color(0xffeab308)),
      );
    }
    if ('$badge' == '2') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xffa855f7), Color(0xff7c3aed)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebIcon('graduation', size: 11, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'PROFESSOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
