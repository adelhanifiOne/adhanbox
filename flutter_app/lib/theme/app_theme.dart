import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // === Palette principale ===
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color emeraldDeep = Color(0xFF065F46);
  static const Color emeraldLight = Color(0xFF34D399);
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldLight = Color(0xFFFCD34D);

  // === Dark theme ===
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkCardAlt = Color(0xFF243347);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // === Light theme ===
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // === Prayer colors ===
  static const Color fajrColor = Color(0xFF818CF8);
  static const Color dhuhrColor = Color(0xFFFBBF24);
  static const Color asrColor = Color(0xFFFF8C42);
  static const Color maghribColor = Color(0xFFEF4444);
  static const Color ishaColor = Color(0xFF6366F1);

  static Color prayerColor(String name) {
    switch (name.toLowerCase()) {
      case 'fajr': return fajrColor;
      case 'dhuhr': return dhuhrColor;
      case 'asr': return asrColor;
      case 'maghrib': return maghribColor;
      case 'isha': return ishaColor;
      default: return emerald;
    }
  }

  static IconData prayerIcon(String name) {
    switch (name.toLowerCase()) {
      case 'fajr': return Icons.wb_twilight_rounded;
      case 'dhuhr': return Icons.wb_sunny_rounded;
      case 'asr': return Icons.light_mode_rounded;
      case 'maghrib': return Icons.nightlight_round;
      case 'isha': return Icons.dark_mode_rounded;
      default: return Icons.access_time_rounded;
    }
  }

  // === DARK THEME ===
  static ThemeData get dark {
    final base = ThemeData.dark();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: emerald,
        primaryContainer: Color(0xFF064E3B),
        secondary: gold,
        secondaryContainer: Color(0xFF451A03),
        surface: darkSurface,
        background: darkBg,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onBackground: darkTextPrimary,
        outline: darkBorder,
        surfaceVariant: darkCardAlt,
        onSurfaceVariant: darkTextSecondary,
        error: Color(0xFFEF4444),
      ),
      textTheme: _buildTextTheme(base.textTheme, darkTextPrimary, darkTextSecondary, darkTextMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: darkTextPrimary),
        titleTextStyle: GoogleFonts.poppins(
          color: darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: emerald.withOpacity(0.18),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return GoogleFonts.inter(color: emerald, fontSize: 11, fontWeight: FontWeight.w600);
          }
          return GoogleFonts.inter(color: darkTextMuted, fontSize: 11);
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: emerald, size: 22);
          }
          return const IconThemeData(color: darkTextMuted, size: 22);
        }),
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: darkTextSecondary),
      sliderTheme: SliderThemeData(
        activeTrackColor: emerald,
        thumbColor: emerald,
        inactiveTrackColor: darkBorder,
        overlayColor: emerald.withOpacity(0.15),
        trackHeight: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: emerald,
          side: const BorderSide(color: emerald),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: emerald,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emerald, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: darkTextSecondary),
        hintStyle: GoogleFonts.inter(color: darkTextMuted),
        prefixIconColor: darkTextMuted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (s) => s.contains(MaterialState.selected) ? emerald : darkTextMuted,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (s) => s.contains(MaterialState.selected) ? emerald.withOpacity(0.35) : darkBorder,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCardAlt,
        contentTextStyle: GoogleFonts.inter(color: darkTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.poppins(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.inter(color: darkTextSecondary, fontSize: 14),
      ),
      listTileTheme: ListTileThemeData(
        textColor: darkTextPrimary,
        iconColor: darkTextSecondary,
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurface,
        labelStyle: GoogleFonts.inter(color: darkTextSecondary, fontSize: 13),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // === LIGHT THEME ===
  static ThemeData get light {
    final base = ThemeData.light();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      colorScheme: ColorScheme.light(
        primary: emeraldDark,
        primaryContainer: emerald.withOpacity(0.12),
        secondary: gold,
        surface: lightSurface,
        background: lightBg,
        onPrimary: Colors.white,
        onSurface: lightTextPrimary,
        onBackground: lightTextPrimary,
        outline: lightBorder,
        surfaceVariant: const Color(0xFFF1F5F9),
        onSurfaceVariant: lightTextSecondary,
        error: const Color(0xFFEF4444),
      ),
      textTheme: _buildTextTheme(base.textTheme, lightTextPrimary, lightTextSecondary, lightTextMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBg,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: lightTextPrimary),
        titleTextStyle: GoogleFonts.poppins(
          color: lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: emeraldDark.withOpacity(0.12),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return GoogleFonts.inter(color: emeraldDark, fontSize: 11, fontWeight: FontWeight.w600);
          }
          return GoogleFonts.inter(color: lightTextMuted, fontSize: 11);
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: emeraldDark, size: 22);
          }
          return const IconThemeData(color: lightTextMuted, size: 22);
        }),
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: lightTextSecondary),
      sliderTheme: SliderThemeData(
        activeTrackColor: emeraldDark,
        thumbColor: emeraldDark,
        inactiveTrackColor: lightBorder,
        overlayColor: emeraldDark.withOpacity(0.12),
        trackHeight: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emeraldDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: emeraldDark,
          side: const BorderSide(color: emeraldDark),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: emeraldDark,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emeraldDark, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: lightTextSecondary),
        hintStyle: GoogleFonts.inter(color: lightTextMuted),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (s) => s.contains(MaterialState.selected) ? emeraldDark : lightTextMuted,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (s) => s.contains(MaterialState.selected) ? emerald.withOpacity(0.35) : lightBorder,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightCard,
        contentTextStyle: GoogleFonts.inter(color: lightTextPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.poppins(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.inter(color: lightTextSecondary, fontSize: 14),
      ),
      listTileTheme: ListTileThemeData(
        textColor: lightTextPrimary,
        iconColor: lightTextSecondary,
        tileColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    TextTheme base,
    Color primary,
    Color secondary,
    Color muted,
  ) {
    return base.copyWith(
      displayLarge: GoogleFonts.poppins(color: primary, fontSize: 32, fontWeight: FontWeight.bold),
      displayMedium: GoogleFonts.poppins(color: primary, fontSize: 26, fontWeight: FontWeight.bold),
      displaySmall: GoogleFonts.poppins(color: primary, fontSize: 22, fontWeight: FontWeight.w600),
      headlineLarge: GoogleFonts.poppins(color: primary, fontSize: 20, fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.poppins(color: primary, fontSize: 18, fontWeight: FontWeight.w600),
      headlineSmall: GoogleFonts.poppins(color: primary, fontSize: 16, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.poppins(color: primary, fontSize: 16, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.inter(color: primary, fontSize: 14, fontWeight: FontWeight.w500),
      titleSmall: GoogleFonts.inter(color: secondary, fontSize: 13, fontWeight: FontWeight.w500),
      bodyLarge: GoogleFonts.inter(color: primary, fontSize: 16),
      bodyMedium: GoogleFonts.inter(color: secondary, fontSize: 14),
      bodySmall: GoogleFonts.inter(color: muted, fontSize: 12),
      labelLarge: GoogleFonts.inter(color: primary, fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: GoogleFonts.inter(color: secondary, fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: GoogleFonts.inter(color: muted, fontSize: 11),
    );
  }
}
