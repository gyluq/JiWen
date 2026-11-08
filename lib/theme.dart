import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colour tokens shared with the HTML prototype (warm paper, ink text, one
/// cinnabar accent). A dark variant keeps the same hierarchy for F-46.
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.tagBg,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color tagBg;
  final Color danger;

  static const light = AppPalette(
    bg: Color(0xFFF6F2E9),
    surface: Color(0xFFFFFCF5),
    ink: Color(0xFF1D1B18),
    ink2: Color(0xFF4A453D),
    muted: Color(0xFF8A8377),
    line: Color(0xFFE4DCCE),
    accent: Color(0xFFBE5638),
    accentInk: Color(0xFFA4482F),
    accentSoft: Color(0xFFF6E4DB),
    tagBg: Color(0xFFEDE6D9),
    danger: Color(0xFFB3261E),
  );

  static const dark = AppPalette(
    bg: Color(0xFF17140F),
    surface: Color(0xFF211D17),
    ink: Color(0xFFF0E9DD),
    ink2: Color(0xFFC8BFB1),
    muted: Color(0xFF948B7B),
    line: Color(0xFF38322A),
    accent: Color(0xFFD9785A),
    accentInk: Color(0xFFEAA487),
    accentSoft: Color(0xFF3B2820),
    tagBg: Color(0xFF2C2720),
    danger: Color(0xFFE58C83),
  );
}

/// The palette currently in use by the widgets.
///
/// Widgets read these getters directly, which keeps every screen on the same
/// tokens without passing a palette through the whole tree. [apply] runs when
/// the resolved theme changes.
class AppColors {
  static AppPalette _active = AppPalette.light;

  static AppPalette get palette => _active;

  static void apply(AppPalette palette) {
    _active = palette;
  }

  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get ink => _active.ink;
  static Color get ink2 => _active.ink2;
  static Color get muted => _active.muted;
  static Color get line => _active.line;
  static Color get accent => _active.accent;
  static Color get accentInk => _active.accentInk;
  static Color get accentSoft => _active.accentSoft;
  static Color get tagBg => _active.tagBg;
  static Color get danger => _active.danger;
}

ThemeData buildAppTheme(AppPalette palette, {String? fontFamily}) {
  final dark = palette == AppPalette.dark;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final themed = fontFamily == null
      ? base
      : base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: fontFamily),
          primaryTextTheme: base.primaryTextTheme.apply(
            fontFamily: fontFamily,
          ),
        );
  return themed.copyWith(
    brightness: brightness,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: const Color(0xFFFFF8F1),
      surface: palette.surface,
      onSurface: palette.ink,
      outline: palette.line,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: fontFamily,
        color: palette.ink,
      ),
      contentTextStyle: TextStyle(
        fontSize: 13,
        height: 1.7,
        fontFamily: fontFamily,
        color: palette.ink2,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accentSoft,
      selectionHandleColor: palette.accent,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
