import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final isDark = AppTheme.isDark(context);
    final effectiveColor = isDark && color == AppTheme.primaryNavy
        ? AppTheme.royalGold
        : color;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: effectiveColor.withValues(alpha: 0.28), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: effectiveColor.withValues(alpha: 0.12),
        highlightColor: effectiveColor.withValues(alpha: 0.06),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10.0 : 13.0,
            vertical: isCompact ? 10.0 : 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 5.5 : 7),
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: effectiveColor, size: isCompact ? 18 : 22),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              style: TextStyle(
                                color: effectiveColor,
                                fontSize: isCompact ? 10.5 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.arrow_forward_ios_rounded, size: 9, color: effectiveColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: isCompact ? 16.5 : 18,
                      fontWeight: FontWeight.w900,
                      color: effectiveColor,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'اضغط لفتح القائمة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.touch_app_rounded, size: 13, color: effectiveColor.withValues(alpha: 0.85)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// كارت إحصائي مقسوم لنصفين (نصف للنمطي ونصف للأوردر، أو أطقم وفردي)
class SplitStatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int standardCount;
  final int customCount;
  final String firstLabel;
  final String secondLabel;
  final String? footerText;
  final VoidCallback? onTap;

  const SplitStatCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.standardCount,
    required this.customCount,
    this.firstLabel = 'نمطي',
    this.secondLabel = 'أوردر',
    this.footerText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = standardCount + customCount;
    final isCompact = MediaQuery.sizeOf(context).width < 380;
    final isDark = AppTheme.isDark(context);
    final effectiveColor = isDark && color == AppTheme.primaryNavy
        ? AppTheme.royalGold
        : color;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: effectiveColor.withValues(alpha: 0.28), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: effectiveColor.withValues(alpha: 0.12),
        highlightColor: effectiveColor.withValues(alpha: 0.06),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 9.0 : 12.0,
            vertical: isCompact ? 9.0 : 10.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 5 : 6),
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: effectiveColor, size: isCompact ? 17 : 20),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: isCompact ? 6 : 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              style: TextStyle(
                                color: effectiveColor,
                                fontSize: isCompact ? 10.5 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.arrow_forward_ios_rounded, size: 9, color: effectiveColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: isDark ? 0.10 : 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: effectiveColor.withValues(alpha: 0.16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            firstLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$standardCount',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: effectiveColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: effectiveColor.withValues(alpha: 0.25),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            secondLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '$customCount',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: effectiveColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      footerText ?? 'الإجمالي: $total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: effectiveColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'فتح القائمة',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.touch_app_rounded, size: 12, color: effectiveColor.withValues(alpha: 0.85)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة إحصاء مضغوطة موحدة (بدلاً من تكرار _StatCard في شاشة النسخ الاحتياطي)
class CompactStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const CompactStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final effectiveColor = isDark && color == AppTheme.primaryNavy
        ? AppTheme.royalGold
        : color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: effectiveColor, size: 22),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: effectiveColor),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context))),
        ],
      ),
    );
  }
}
