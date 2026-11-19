import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/app_settings_service.dart';
import '../core/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showBorder;

  const AppLogo({
    super.key,
    this.size = 80,
    this.showBorder = true,
  });

  Widget _buildDefaultLogo() {
    return Image.asset(
      'assets/images/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.chair_rounded,
        size: size * 0.6,
        color: AppTheme.primaryNavy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShowroomProfile>(
      valueListenable: AppSettingsService.showroomProfileNotifier,
      builder: (context, profile, _) {
        Widget logoWidget = _buildDefaultLogo();
        if (!kIsWeb && profile.hasCustomLogo) {
          final file = File(profile.customLogoPath!);
          if (file.existsSync()) {
            logoWidget = Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultLogo(),
            );
          }
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            borderRadius: BorderRadius.circular(size * 0.22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: size * 0.1,
                offset: Offset(0, size * 0.04),
              ),
            ],
            border: showBorder
                ? Border.all(
                    color: AppTheme.royalGold,
                    width: size > 50 ? 2.0 : 1.2,
                  )
                : null,
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(size * 0.22 - (showBorder ? 1.5 : 0)),
            child: logoWidget,
          ),
        );
      },
    );
  }
}

/// عنوان موحد ومتجاوب في الهيدر يعرض الشعار (المخصص أو الافتراضي) واسم الصفحة كاملاً
class AppBarTitleWithLogo extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double logoSize;

  const AppBarTitleWithLogo({
    super.key,
    required this.title,
    this.subtitle,
    this.logoSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = AppTheme.textPrimary(context);
    return Row(
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: titleColor,
                  ),
                  maxLines: 1,
                ),
              ),
              if (subtitle != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: titleColor.withValues(alpha: 0.72),
                    ),
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
