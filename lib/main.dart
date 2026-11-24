import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_settings_service.dart';
import 'core/app_theme.dart';
import 'core/app_version.dart';
import 'core/backup_service.dart';
import 'core/cloud_service.dart';
import 'core/db_helper.dart';
import 'core/license_service.dart';
import 'core/platform_init.dart';
import 'core/security_storage_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_nav_screen.dart';
import 'screens/settings_hub_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopDatabase();
  await DBHelper.instance.database;
  await AppSettingsService.initialize();
  await LicenseService.checkStatus();

  // فحص وتحديث حالة الاشتراك التجاري سحابياً في الخلفية
  SecurityStorageService.getDeviceCode().then((code) {
    CloudService.checkAndSyncSubscriptionStatus(code);
  });

  final bool biometricEnabled = await AppSettingsService.isBiometricEnabled();

  runApp(FurnitureApp(initialBiometricEnabled: biometricEnabled));

  // تنظيف الكاش الذكي والصيانة الدورية في الخلفية بدون أي تأخير على فتح البرنامج
  if (!kIsWeb) {
    BackupService.performSmartStartupMaintenance();
  }
}

class FurnitureApp extends StatelessWidget {
  final bool initialBiometricEnabled;

  const FurnitureApp({
    super.key,
    this.initialBiometricEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettingsService.themeModeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<ShowroomProfile>(
          valueListenable: AppSettingsService.showroomProfileNotifier,
          builder: (context, profile, __) {
            return MaterialApp(
              title: profile.displayName.isNotEmpty
                  ? profile.displayName
                  : AppVersion.appName,
              debugShowCheckedModeBanner: false,
              locale: const Locale('ar', 'EG'),
              supportedLocales: const [Locale('ar', 'EG')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) {
                if (child == null) return const SizedBox.shrink();
                final mq = MediaQuery.of(context);
                final width = mq.size.width;
                // ضبط قياس الخط والأيقونات تلقائياً حسب عرض الشاشة مع وضع سقف آمن لتكبير خط الهاتف
                final double screenScale =
                    width < 390 ? (width / 390.0).clamp(0.84, 1.0) : 1.0;
                final double systemTextScale =
                    mq.textScaler.scale(1.0).clamp(0.90, 1.05);
                final double effectiveTextScale =
                    (systemTextScale * screenScale).clamp(0.82, 1.05);

                return MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(effectiveTextScale),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(size: 23.0 * screenScale.clamp(0.86, 1.0)),
                    child: child,
                  ),
                );
              },
              home: ValueListenableBuilder<LicenseInfo?>(
                valueListenable: LicenseService.statusNotifier,
                builder: (context, license, _) {
                  if (license != null && !license.isUsable) {
                    return const SettingsHubScreen(isLockedMode: true);
                  }
                  return initialBiometricEnabled
                      ? const AuthScreen()
                      : const MainNavigationScreen();
                },
              ),
            );
          },
        );
      },
    );
  }
}
