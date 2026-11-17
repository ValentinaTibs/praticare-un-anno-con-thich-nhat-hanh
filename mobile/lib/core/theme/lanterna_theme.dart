import 'package:flutter/material.dart';

/// "Lanterna" visual style for the participants' mobile app.
/// See docs/design-lanterna.md for the full design notes.
///
/// Fonts: Literata (serif) and Inter (sans), expected as bundled assets
/// declared in pubspec.yaml with the family names 'Literata' and 'Inter'.
abstract final class LanternaColors {
  static const background = Color(0xFF14182B);
  static const surface = Color(0xFF1E2338);
  static const line = Color(0xFF2C3250);
  static const outline = Color(0xFF3A4163);
  static const text = Color(0xFFECE9E2);
  static const muted = Color(0xFFA7ABBE);
  static const accent = Color(0xFFE8B66B);
  static const accentLight = Color(0xFFF2CC8F);
  static const onAccent = Color(0xFF14182B);
  static const error = Color(0xFFF2A39A);
}

abstract final class LanternaFonts {
  static const serif = 'Literata';
  static const sans = 'Inter';
}

/// Text styles that do not map cleanly onto Material's TextTheme.
abstract final class LanternaText {
  static const quote = TextStyle(
    fontFamily: LanternaFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: 25,
    height: 1.38,
    color: LanternaColors.text,
  );

  static const quoteLarge = TextStyle(
    fontFamily: LanternaFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: 27,
    height: 1.36,
    color: LanternaColors.text,
  );

  static const circleMessage = TextStyle(
    fontFamily: LanternaFonts.serif,
    fontSize: 17,
    height: 1.5,
    color: LanternaColors.text,
  );

  static const sectionLabel = TextStyle(
    fontFamily: LanternaFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.3,
    color: LanternaColors.muted,
  );

  static const caption = TextStyle(
    fontFamily: LanternaFonts.sans,
    fontSize: 13,
    color: LanternaColors.muted,
  );
}

const _pill = StadiumBorder();

final lanternaTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: LanternaFonts.sans,
  scaffoldBackgroundColor: LanternaColors.background,
  colorScheme: const ColorScheme.dark(
    surface: LanternaColors.background,
    surfaceContainer: LanternaColors.surface,
    surfaceContainerHigh: LanternaColors.surface,
    onSurface: LanternaColors.text,
    onSurfaceVariant: LanternaColors.muted,
    primary: LanternaColors.accent,
    onPrimary: LanternaColors.onAccent,
    secondary: LanternaColors.accent,
    onSecondary: LanternaColors.onAccent,
    outline: LanternaColors.outline,
    outlineVariant: LanternaColors.line,
    error: LanternaColors.error,
    onError: LanternaColors.onAccent,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(fontFamily: LanternaFonts.serif, fontSize: 22, color: LanternaColors.text),
    titleLarge: TextStyle(fontFamily: LanternaFonts.serif, fontSize: 20, color: LanternaColors.text),
    titleMedium: TextStyle(fontFamily: LanternaFonts.serif, fontSize: 19, color: LanternaColors.text),
    bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: LanternaColors.text),
    bodyMedium: TextStyle(fontSize: 15, height: 1.55, color: LanternaColors.text),
    bodySmall: TextStyle(fontSize: 13, color: LanternaColors.muted),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: LanternaColors.background,
    foregroundColor: LanternaColors.text,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(fontFamily: LanternaFonts.serif, fontSize: 22, color: LanternaColors.text),
  ),
  cardTheme: CardThemeData(
    color: LanternaColors.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: LanternaColors.accent,
      foregroundColor: LanternaColors.onAccent,
      disabledBackgroundColor: LanternaColors.line,
      disabledForegroundColor: LanternaColors.muted,
      minimumSize: const Size.fromHeight(52),
      shape: _pill,
      textStyle: const TextStyle(fontFamily: LanternaFonts.sans, fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: LanternaColors.text,
      side: const BorderSide(color: LanternaColors.outline),
      minimumSize: const Size.fromHeight(52),
      shape: _pill,
      textStyle: const TextStyle(fontFamily: LanternaFonts.sans, fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: LanternaColors.accent),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: LanternaColors.surface,
    hintStyle: const TextStyle(color: LanternaColors.muted),
    labelStyle: const TextStyle(color: LanternaColors.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: LanternaColors.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: LanternaColors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: LanternaColors.accent, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: const BorderSide(color: LanternaColors.error),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: LanternaColors.surface,
    indicatorColor: Colors.transparent,
    elevation: 0,
    height: 72,
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? LanternaColors.accent : LanternaColors.muted,
      ),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: LanternaFonts.sans,
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        color: states.contains(WidgetState.selected) ? LanternaColors.accent : LanternaColors.muted,
      ),
    ),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? LanternaColors.onAccent : LanternaColors.muted,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected) ? LanternaColors.accent : LanternaColors.line,
    ),
  ),
  dividerTheme: const DividerThemeData(color: LanternaColors.line, thickness: 1),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: LanternaColors.accent,
    circularTrackColor: LanternaColors.line,
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: LanternaColors.surface,
    contentTextStyle: TextStyle(color: LanternaColors.text),
    actionTextColor: LanternaColors.accent,
  ),
);
