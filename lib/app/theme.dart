import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData gymLightTheme(String? accentHex) {
  final parsed = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accentHex ?? '')
      ? int.tryParse(accentHex!.substring(1), radix: 16)
      : null;
  final accent = Color(0xff000000 | (parsed ?? 0xff6600));
  final foreground = accent.computeLuminance() > 0.179
      ? Colors.black
      : Colors.white;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: accent,
    onPrimary: foreground,
    surface: Colors.white,
    onSurface: const Color(0xff202321),
    error: const Color(0xff99433d),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
  );
  final text = GoogleFonts.dmSansTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: GoogleFonts.syne(
        textStyle: text.headlineLarge,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.syne(
        textStyle: text.headlineMedium,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xff202321),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xfff6f7f6),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xfff6f7f6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xffdde0dd)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      selectedIconTheme: IconThemeData(color: Color(0xff0f766e)),
      unselectedIconTheme: IconThemeData(color: Color(0xff6b7280)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xffe5e7e5),
      thickness: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

ThemeData gymDarkTheme(String? accentHex) {
  final parsed = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accentHex ?? '')
      ? int.tryParse(accentHex!.substring(1), radix: 16)
      : null;
  final accent = Color(0xff000000 | (parsed ?? 0xff8800));
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: Colors.black,
    surface: const Color(0xff14161d),
    onSurface: const Color(0xffe5e7eb),
    surfaceContainerHighest: const Color(0xff222634),
    error: const Color(0xffef4444),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xff0d0f14),
  );
  final text = GoogleFonts.dmSansTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: GoogleFonts.syne(
        textStyle: text.headlineLarge,
        fontWeight: FontWeight.w600,
        color: const Color(0xfff3f4f6),
      ),
      headlineMedium: GoogleFonts.syne(
        textStyle: text.headlineMedium,
        fontWeight: FontWeight.w600,
        color: const Color(0xfff3f4f6),
      ),
      bodyLarge: text.bodyLarge?.copyWith(color: const Color(0xffe5e7eb)),
      bodyMedium: text.bodyMedium?.copyWith(color: const Color(0xffd1d5db)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xff0d0f14),
      foregroundColor: Color(0xfff3f4f6),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xff181b24),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xff262b3a), width: 1),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xff181b24),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xff181b24),
      labelStyle: const TextStyle(color: Color(0xff9ca3af)),
      hintStyle: const TextStyle(color: Color(0xff6b7280)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff2b3142)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff2b3142)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Color(0xff374151)),
        foregroundColor: const Color(0xffe5e7eb),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color(0xff10121a),
      selectedIconTheme: IconThemeData(color: Color(0xfff59e0b)),
      unselectedIconTheme: IconThemeData(color: Color(0xff9ca3af)),
      selectedLabelTextStyle: TextStyle(
        color: Color(0xfff59e0b),
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelTextStyle: TextStyle(color: Color(0xff9ca3af)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xff10121a),
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xff222634),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xff232734),
      thickness: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xff14161d),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

// Retro-konpatibilite
ThemeData gymTheme(String? accentHex) => gymLightTheme(accentHex);
