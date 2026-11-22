import 'package:flutter/material.dart';

class AppColors {
  static const bgTop = Color(0xFF1E2026);
  static const bg = Color(0xFF17181C);
  static const surface = Color(0xFF25272E);
  static const accent = Color(0xFF6CF29E);
  static const onAccent = Color(0xFF0F1A13);
  static const highlight = accent;
  static const muted = Color(0xFF8C8F99);
}

ThemeData buildTheme() {
  Color navColor(Set<WidgetState> s) =>
      s.contains(WidgetState.selected) ? AppColors.highlight : AppColors.muted;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: AppColors.bg,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg),
    scaffoldBackgroundColor: AppColors.bg,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: navColor(s))),
      labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(fontSize: 11, color: navColor(s))),
    ),
  );
}
