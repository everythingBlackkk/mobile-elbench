import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_typography.dart';

class AppSettings extends ChangeNotifier {
  AppSettings({
    this.preferences,
    this.mode = ThemeMode.system,
    this.language = 'ar',
  });
  SharedPreferences? preferences;
  ThemeMode mode;
  String language;
  final Color accent = const Color(0xff2e855d);
  ThemeData? _lightTheme, _darkTheme;
  TargetPlatform? _themePlatform;

  void _invalidateThemes() {
    _lightTheme = null;
    _darkTheme = null;
  }

  Future<void> load() async {
    preferences ??= await SharedPreferences.getInstance();
    final p = preferences!;
    final savedMode = p.getInt('appearance.mode');
    mode = savedMode == null
        ? ThemeMode.system
        : ThemeMode.values[savedMode.clamp(0, 2)];
    language = p.getString('appearance.language') ?? 'ar';
    for (final obsolete in const [
      'appearance.liquidGlass',
      'appearance.accent',
      'appearance.background',
      'appearance.surface',
      'appearance.text',
    ]) {
      if (p.containsKey(obsolete)) {
        p.remove(obsolete);
      }
    }
    _invalidateThemes();
    notifyListeners();
  }

  void setMode(ThemeMode value) {
    if (mode == value) return;
    mode = value;
    preferences?.setInt('appearance.mode', value.index);
    notifyListeners();
  }

  void setLanguage(String value) {
    if (language == value) return;
    language = value;
    preferences?.setString('appearance.language', value);
    notifyListeners();
  }

  ThemeData theme(Brightness brightness) {
    if (_themePlatform != defaultTargetPlatform) {
      _themePlatform = defaultTargetPlatform;
      _invalidateThemes();
    }
    if (brightness == Brightness.dark) {
      return _darkTheme ??= _buildTheme(Brightness.dark);
    }
    return _lightTheme ??= _buildTheme(Brightness.light);
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final main = dark ? const Color(0xff0a0a0a) : Colors.white;
    final secondary = dark ? const Color(0xff141414) : const Color(0xfff9fafb);
    final foreground = dark ? const Color(0xfff3f4f6) : const Color(0xff111827);
    final border = dark ? const Color(0xff303030) : const Color(0xffe5e7eb);
    final muted = dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
    final accentText = dark ? const Color(0xff7ace9f) : accent;
    final font = AppTypography.fontFamily;
    final fontFallback = AppTypography.fontFamilyFallback;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accentText,
          onPrimary: Colors.white,
          secondary: accentText,
          surface: secondary,
          onSurface: foreground,
          onSurfaceVariant: muted,
          outline: border,
          outlineVariant: border,
          surfaceTint: Colors.transparent,
          primaryContainer: accentText.withValues(alpha: dark ? .12 : .1),
          onPrimaryContainer: accentText,
          error: dark ? const Color(0xffe7767d) : const Color(0xffc53d46),
        );
    final textTheme =
        (dark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              fontFamily: font,
              fontFamilyFallback: fontFallback,
              bodyColor: foreground,
              displayColor: foreground,
            )
            .copyWith(
              headlineLarge: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                fontSize: 32,
                height: 1.3,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
                color: foreground,
              ),
              headlineSmall: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                fontSize: 24,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
              titleLarge: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
              titleMedium: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
              bodyLarge: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 16,
                height: 1.5,
                color: foreground,
              ),
              bodyMedium: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 14,
                height: 1.6,
                color: foreground,
              ),
              bodySmall: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 12,
                height: 1.5,
                color: muted,
              ),
              labelLarge: TextStyle(
                fontFamily: font,
                fontFamilyFallback: fontFallback,
                letterSpacing: 0,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: main,
      canvasColor: main,
      dividerColor: border,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      // Android's pull-to-refresh: the brand green arc with rounded ends on a chip matching the page
      // (iOS uses its native spinner through RefreshIndicator.adaptive).
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentText,
        refreshBackgroundColor: dark ? const Color(0xff1c1c1e) : Colors.white,
        strokeWidth: 3,
        strokeCap: StrokeCap.round,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 64,
        backgroundColor: main,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: secondary,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        hintStyle: TextStyle(color: muted.withValues(alpha: .65), fontSize: 16),
        labelStyle: TextStyle(color: foreground, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 46),
          elevation: 0,
          textStyle: TextStyle(
            fontFamily: font,
            fontFamilyFallback: fontFallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: BorderSide(color: border),
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: main,
        selectedColor: accentText.withValues(alpha: .1),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          fontFamily: font,
          fontFamilyFallback: fontFallback,
          fontSize: 13,
          color: foreground,
        ),
      ),
      iconTheme: IconThemeData(color: foreground, size: 20),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: main,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: foreground,
        textColor: foreground,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),
    );
  }

  String tr(String en, String ar) => language == 'ar' ? ar : en;
}
