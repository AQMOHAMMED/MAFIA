import 'package:flutter/material.dart';

// نفس ألوان الموقع
class C {
  static const bg = Color(0xFF0A0204);
  static const bg2 = Color(0xFF160307);
  static const panel = Color(0xFF1A0B10);
  static const text = Color(0xFFF7E9EC);
  static const muted = Color(0xFFA8939A);
  static const gold = Color(0xFFF3C75A);
  static const gold2 = Color(0xFFE0A93A);
  static const red = Color(0xFFFF3B55);
  static const red2 = Color(0xFFC80134);
  static const pink = Color(0xFFFF8D97);
  static const green = Color(0xFF2EF08A);
  static const line = Color(0x38E0A93A); // gold2 22%
  static const line2 = Color(0x80E0A93A); // gold2 50%
  static const dark = Color(0xFF2A1903);
  static const field = Color(0xFF0B0C10);

  static const goldGrad = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF1B8), Color(0xFFF0C45A), Color(0xFFC98A22)], stops: [0, .45, 1]);
  static const goldMetal = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF0B0), Color(0xFFE0A93A), Color(0xFF8A5A12), Color(0xFFF6D36F), Color(0xFFA06C18)],
      stops: [0, .25, .5, .7, 1]);
  static const goldText = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF0B0), Color(0xFFF3C75A), Color(0xFFC98A22)], stops: [.1, .45, .8]);
  static const panelGrad = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEB280C12), Color(0xEB120609)]);
}

TextStyle lalezar(double size, [Color color = C.gold]) => TextStyle(fontFamily: 'Lalezar', fontSize: size, color: color, height: 1.3);
const tsMuted = TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 13);
const tsBold = TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.text);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(primary: C.gold, secondary: C.red, surface: C.panel, onPrimary: C.dark, onSurface: C.text);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'Cairo',
    textTheme: const TextTheme(bodyMedium: TextStyle(color: C.text, fontSize: 15)),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1E0A10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: C.line2)),
      titleTextStyle: lalezar(24),
      contentTextStyle: const TextStyle(fontFamily: 'Cairo', color: C.text, fontSize: 16, fontWeight: FontWeight.w600),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.gold, selectionColor: Color(0x55F3C75A), selectionHandleColor: C.gold),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.gold : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(C.dark),
      side: const BorderSide(color: C.gold2, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.gold : const Color(0x22FFFFFF)),
      trackOutlineColor: const WidgetStatePropertyAll(C.line),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.gold),
  );
}
