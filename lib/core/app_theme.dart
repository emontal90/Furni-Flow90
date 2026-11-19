import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryNavy = Color(0xFF1E3A5F);
  static const Color primaryNavyDark = Color(0xFF0F2038);
  static const Color royalGold = Color(0xFFD4AF37);
  static const Color bgSurface = Color(0xFFF8F9FA);

  // ألوان الوضع الليلي الاحترافي
  static const Color darkBg = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF131D31);
  static const Color darkCard = Color(0xFF1A2740);
  static const Color darkBorder = Color(0xFF2B3D5E);

  static const String fontFamily = 'NotoSansArabic';

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color cardBg(BuildContext context) =>
      isDark(context) ? darkCard : Colors.white;

  static Color surfaceBg(BuildContext context) =>
      isDark(context) ? darkSurface : bgSurface;

  static Color filterBarBg(BuildContext context) =>
      isDark(context) ? darkSurface : Colors.white;

  static Color subtleBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF21314F) : const Color(0xFFF8FAFC);

  static Color borderColor(BuildContext context) =>
      isDark(context) ? darkBorder : Colors.grey.shade300;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? const Color(0xFFF1F5F9) : primaryNavy;

  static Color textBody(BuildContext context) =>
      isDark(context) ? const Color(0xFFE2E8F0) : Colors.black87;

  static Color textMuted(BuildContext context) =>
      isDark(context) ? const Color(0xFF94A3B8) : Colors.grey.shade700;

  static Color accentOnSurface(BuildContext context) =>
      isDark(context) ? royalGold : primaryNavy;

  /// هامش سفلي ذكي للنوافذ المنبثقة لتجنب تداخل الأزرار مع شريط التنقل بالهاتف أو لوحة المفاتيح
  static EdgeInsets modalSheetPadding(
    BuildContext context, {
    double horizontal = 16,
    double top = 20,
  }) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom > mq.viewPadding.bottom
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    return EdgeInsets.only(
      left: horizontal,
      right: horizontal,
      top: top,
      bottom: bottomInset + 24,
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryNavy,
      secondary: royalGold,
      surface: bgSurface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgSurface,
      fontFamily: fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: primaryNavy,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primaryNavy.withValues(alpha: 0.12),
        height: 68,
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? primaryNavy : Colors.grey.shade800,
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryNavy,
        unselectedLabelColor: Colors.black54,
        indicatorColor: royalGold,
        labelPadding: EdgeInsets.symmetric(horizontal: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryNavy,
      brightness: Brightness.dark,
      primary: royalGold,
      secondary: royalGold,
      surface: darkSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      fontFamily: fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: royalGold.withValues(alpha: 0.18),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? royalGold : const Color(0xFF94A3B8),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? royalGold : const Color(0xFFCBD5E1),
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: royalGold,
        unselectedLabelColor: Color(0xFF94A3B8),
        indicatorColor: royalGold,
        labelPadding: EdgeInsets.symmetric(horizontal: 6),
      ),
      dividerColor: darkBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
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
          borderSide: const BorderSide(color: royalGold, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
