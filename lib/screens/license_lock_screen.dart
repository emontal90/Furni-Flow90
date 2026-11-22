import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_logo.dart';
import '../core/app_notification.dart';
import '../core/app_theme.dart';
import '../core/cloud_service.dart';
import '../core/license_service.dart';
import 'subscription_screen.dart';

class LicenseLockScreen extends StatefulWidget {
  final LicenseInfo info;

  const LicenseLockScreen({super.key, required this.info});

  @override
  State<LicenseLockScreen> createState() => _LicenseLockScreenState();
}

class _LicenseLockScreenState extends State<LicenseLockScreen> {
  bool _isChecking = false;

  Future<void> _checkActivationNow() async {
    setState(() => _isChecking = true);
    try {
      final sub = await CloudService.checkAndSyncSubscriptionStatus(widget.info.deviceCode);
      final updated = await LicenseService.checkStatus();
      if (!mounted) return;
      setState(() => _isChecking = false);

      if (updated.isUsable) {
        AppNotification.showSuccess(
          context,
          'تم تفعيل البرنامج بنجاح! مرحباً بك في فورني فلو.',
        );
      } else {
        AppNotification.showInfo(
          context,
          sub != null && sub.isPending
              ? 'طلبك قيد المراجعة لدى الإدارة. سيتم التفعيل فور تأكيد التحويل.'
              : 'لم يتم العثور على اشتراك نشط لهذا الجهاز بعد. يرجى الاشتراك أو التواصل مع الإدارة.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isChecking = false);
      AppNotification.showError(
        context,
        'تعذر التحقق من التفعيل السحابي. يرجى التأكد من اتصال الإنترنت.',
      );
    }
  }

  void _closeApp() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      exit(0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isTampered = info.isClockTampered;

    String title;
    String description;
    IconData statusIcon;
    Color statusColor;

    if (isTampered) {
      title = 'تنبيه أمني: اختلاف في ساعة النظام';
      description =
          'تم رصد اختلاف أو تلاعب في تاريخ ووقت هذا الجهاز.\nيرجى ضبط ساعة وتاريخ الجهاز بشكل صحيح وتلقائي لإعادة استخدام البرنامج.';
      statusIcon = Icons.access_time_filled_rounded;
      statusColor = Colors.orange.shade800;
    } else if (info.licenseKey != null && info.licenseKey!.isNotEmpty) {
      title = 'انتهت صلاحية اشتراكك التجاري';
      description =
          'انتهت فترة اشتراكك المحددة لهذا الجهاز.\nللاستمرار في إدارة مبيعات ومعرض الأثاث ومتابعة حسابات الورشة، يرجى تجديد الاشتراك.';
      statusIcon = Icons.lock_clock_rounded;
      statusColor = Colors.red.shade700;
    } else {
      title = 'انتهت فترة التجربة المجانية (30 يوماً)';
      description =
          'لقد استنفذ هذا الجهاز فترة التجربة المجانية الكاملة.\nلمتابعة أعمالك والوصول إلى كافة شاشات وبيانات البرنامج، يرجى الاشتراك في إحدى الباقات.';
      statusIcon = Icons.lock_rounded;
      statusColor = AppTheme.primaryNavy;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C1626),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الشعار مع قفل الحماية
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        const AppLogo(size: 88),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(statusIcon, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // العنوان
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.royalGold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // الوصف
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // كارت معرف الجهاز الثابت مع زر النسخ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF152238),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.royalGold.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'معرف هذا الجهاز الثابت:',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                info.deviceCode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'نسخ معرف الجهاز',
                              icon: const Icon(Icons.copy_rounded, color: AppTheme.royalGold, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: info.deviceCode));
                                AppNotification.showSuccess(context, 'تم نسخ معرف الجهاز');
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // زر الاشتراك الرئيسي
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalGold,
                      foregroundColor: AppTheme.primaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubscriptionScreen(
                            deviceCode: info.deviceCode,
                          ),
                        ),
                      );
                      await _checkActivationNow();
                    },
                    icon: const Icon(Icons.workspace_premium_rounded, size: 22),
                    label: const Text(
                      'اشترك الآن لتفعيل البرنامج',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // زر فحص التفعيل السحابي
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isChecking ? null : _checkActivationNow,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(
                      _isChecking ? 'جاري التحقق من السحابة...' : 'التحقق من حالة التفعيل',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // زر إغلاق التطبيق
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                    ),
                    onPressed: _closeApp,
                    icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                    label: const Text('إغلاق التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
