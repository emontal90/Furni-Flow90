import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryNavy = Color(0xFF1E3A5F);
  static const Color primaryNavyDark = Color(0xFF0F2038);
  static const Color royalGold = Color(0xFFD4AF37);
  static const Color brightGold = Color(0xFFF3C94B);
  static const Color bgSurface = Color(0xFFF6F8FB);

  // لوحة ألوان الوضع الليلي الاحترافي عالي التباين (Obsidian Slate + Crisp White + Bright Gold)
  static const Color darkBg = Color(0xFF0A0F1C);
  static const Color darkSurface = Color(0xFF121B2E);
  static const Color darkCard = Color(0xFF19243B);
  static const Color darkSubtle = Color(0xFF22314F);
  static const Color darkBorder = Color(0xFF33476B);

  static const String fontFamily = 'NotoSansArabic';

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color cardBg(BuildContext context) =>
      isDark(context) ? darkCard : Colors.white;

  static Color surfaceBg(BuildContext context) =>
      isDark(context) ? darkBg : bgSurface;

  static Color filterBarBg(BuildContext context) =>
      isDark(context) ? darkSurface : Colors.white;

  static Color subtleBg(BuildContext context) =>
      isDark(context) ? darkSubtle : const Color(0xFFF1F5F9);

  static Color borderColor(BuildContext context) =>
      isDark(context) ? darkBorder : const Color(0xFFDCE3EE);

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? const Color(0xFFFFFFFF) : primaryNavy;

  static Color textBody(BuildContext context) =>
      isDark(context) ? const Color(0xFFE8EFF9) : const Color(0xFF1E293B);

  static Color textMuted(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8BAD3) : const Color(0xFF52627A);

  static Color accentOnSurface(BuildContext context) =>
      isDark(context) ? brightGold : primaryNavy;

  // ألوان دلالية عالية التباين للشارات (Badges) في الوضعين النهاري والليلي
  static Color successBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF123828) : const Color(0xFFECFDF5);
  static Color successBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF22C55E).withValues(alpha: 0.55) : const Color(0xFF86EFAC);
  static Color successFg(BuildContext context) =>
      isDark(context) ? const Color(0xFF6EE7B7) : const Color(0xFF166534);

  static Color warningBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF3B2808) : const Color(0xFFFFFBEB);
  static Color warningBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFFF59E0B).withValues(alpha: 0.65) : const Color(0xFFFCD34D);
  static Color warningFg(BuildContext context) =>
      isDark(context) ? const Color(0xFFFDE047) : const Color(0xFF92400E);

  static Color dangerBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF3D1419) : const Color(0xFFFEF2F2);
  static Color dangerBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFFEF4444).withValues(alpha: 0.6) : const Color(0xFFFCA5A5);
  static Color dangerFg(BuildContext context) =>
      isDark(context) ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);

  static Color infoBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF162C52) : const Color(0xFFEFF6FF);
  static Color infoBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF60A5FA).withValues(alpha: 0.5) : const Color(0xFFBFDBFE);
  static Color infoFg(BuildContext context) =>
      isDark(context) ? const Color(0xFF93C5FD) : primaryNavy;

  static List<Color> setsAvatarGradient(BuildContext context, {required bool hasValue}) {
    if (!hasValue) {
      return isDark(context)
          ? const [Color(0xFF334155), Color(0xFF1E293B)]
          : [Colors.grey.shade700, Colors.grey.shade600];
    }
    return isDark(context)
        ? const [Color(0xFF2563EB), Color(0xFF1D4ED8)]
        : const [primaryNavy, Color(0xFF2B5282)];
  }

  static List<Color> individualAvatarGradient(BuildContext context, {required bool hasValue}) {
    if (!hasValue) {
      return isDark(context)
          ? const [Color(0xFF334155), Color(0xFF1E293B)]
          : [Colors.blueGrey.shade700, Colors.blueGrey.shade600];
    }
    return const [Color(0xFFE58609), Color(0xFFC25E03)];
  }

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
        elevation: 0.8,
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
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
      primary: brightGold,
      onPrimary: primaryNavyDark,
      secondary: brightGold,
      surface: darkSurface,
      onSurface: Colors.white,
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
        elevation: 1,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 3,
        shadowColor: Colors.black54,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Color(0xFFE2E8F0),
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: brightGold.withValues(alpha: 0.22),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? brightGold : const Color(0xFFA8BAD3),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? brightGold : const Color(0xFFD5E0F0),
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: brightGold,
        unselectedLabelColor: Color(0xFFA8BAD3),
        indicatorColor: brightGold,
        labelPadding: EdgeInsets.symmetric(horizontal: 6),
      ),
      dividerColor: darkBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSubtle,
        labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIconColor: brightGold,
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
          borderSide: const BorderSide(color: brightGold, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brightGold,
          side: const BorderSide(color: darkBorder),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brightGold,
        ),
      ),
    );
  }
}
