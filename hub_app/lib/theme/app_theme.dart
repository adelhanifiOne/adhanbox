import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primaires
  static const emerald     = Color(0xFF10B981);
  static const emeraldDark = Color(0xFF059669);
  static const gold        = Color(0xFFF59E0B);
  static const goldLight   = Color(0xFFFCD34D);

  // Backgrounds sombre
  static const bgDark      = Color(0xFF0F172A);
  static const bgCard      = Color(0xFF1E293B);
  static const bgCardLight = Color(0xFF334155);

  // Backgrounds clair
  static const bgLight     = Color(0xFFF8FAFC);
  static const bgCardW     = Color(0xFFFFFFFF);

  // Text
  static const textPrimary = Color(0xFFE2E8F0);
  static const textMuted   = Color(0xFF94A3B8);
  static const textDark    = Color(0xFF1E293B);
}

class AppTheme {
  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: AppColors.emerald,
      secondary: AppColors.gold,
      surface: AppColors.bgCard,
      background: AppColors.bgDark,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    scaffoldBackgroundColor: AppColors.bgDark,
    textTheme: _textTheme(AppColors.textPrimary),
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgCard,
      indicatorColor: AppColors.emerald.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      ),
    ),
  );

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: AppColors.emeraldDark,
      secondary: AppColors.gold,
      surface: AppColors.bgCardW,
      background: AppColors.bgLight,
      onPrimary: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.bgLight,
    textTheme: _textTheme(AppColors.textDark),
    cardTheme: CardThemeData(
      color: AppColors.bgCardW,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgCardW,
      indicatorColor: AppColors.emeraldDark.withValues(alpha: 0.12),
    ),
  );

  static TextTheme _textTheme(Color base) => TextTheme(
    displayLarge: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: base),
    displayMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: base),
    titleLarge: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: base),
    titleMedium: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: base),
    bodyLarge: GoogleFonts.inter(fontSize: 15, color: base),
    bodyMedium: GoogleFonts.inter(fontSize: 13, color: base),
    labelSmall: GoogleFonts.inter(fontSize: 11, color: base.withValues(alpha: 0.6)),
  );
}
