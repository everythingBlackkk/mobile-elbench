import 'package:flutter/foundation.dart';

/// Uses installed platform fonts, matching the web UI's font stack:
/// Latin: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
///        "Helvetica Neue", Arial, sans-serif
/// Arabic: 'SF Arabic', sans-serif
abstract final class AppTypography {
  // 'CupertinoSystemText' / '.AppleSystemUIFont' are Flutter's names for the
  // platform system font (-apple-system, BlinkMacSystemFont).
  static String get fontFamily => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'CupertinoSystemText',
    TargetPlatform.macOS => '.AppleSystemUIFont',
    TargetPlatform.windows => 'Segoe UI',
    _ => 'Roboto',
  };

  // Keep one stack for both languages so mixed text uses the same Latin face.
  // Arabic first: the primary font covers Latin, so 'SF Arabic' only ever
  // resolves for Arabic glyphs. Names missing on a platform are skipped.
  static List<String> get fontFamilyFallback => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      '.SF Arabic',
      'SF Arabic',
      'SFArabic',
      'Helvetica Neue',
      'Arial',
    ],
    TargetPlatform.windows => const ['SF Arabic', 'Segoe UI', 'Arial'],
    _ => const ['SF Arabic', 'Helvetica Neue', 'Arial'],
  };
}
